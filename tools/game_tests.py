#!/usr/bin/env python3
"""Run the in-game regression tests against a headless EmptyEpsilon:
story arcs (tests/arcs/*.lua) and the job board (tests/jobs/*.lua).

    python3 tools/game_tests.py --ee <EmptyEpsilon dir>            # everything
    python3 tools/game_tests.py --ee <EmptyEpsilon dir> ledger -v  # one test, every check listed
    python3 tools/game_tests.py --ee <EmptyEpsilon dir> jobs       # one folder (arcs | jobs)
    EE_DIR=<EmptyEpsilon dir> python3 tools/game_tests.py

--ee is what tools/install.py takes (the folder with scripts/), or an EmptyEpsilon checkout with
a _build/ in it. Each test file runs in its own EmptyEpsilon process with its own empty HOME, so tests
start from a fresh campaign and never touch a real save. The repo is installed into that
EmptyEpsilon first (same as tools/install.py); the test files are copied in for the run and
removed afterwards.

How it works: for each test file a scenario is generated that loads the real sandbox
scenario, then tests/_harness.lua, then the test. The harness drives the game from inside
(GM jumps, teleports, real comms) and prints "[ARCTEST] PASS|FAIL ..." lines, which this script
collects from the log. A LUA-Error anywhere in the log fails the arc. Tests run in real time:
about one minute per file, in parallel.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
SUITES = ("arcs", "jobs")     # tests/<suite>/<name>.lua; names are unique across suites
BASE_SCENARIO = ROOT / "scenarios" / "sandbox" / "scenario_80_ragtag.lua"
SCRIPT_DIR_NAME = "ragtag_arctests"          # under EmptyEpsilon's scripts/
SCENARIO_PREFIX = "scenario_97_arctest_"     # 97: not a number check.py hands out


def find_ee(path: Path) -> tuple[Path, Path]:
    """Return (resources dir holding scripts/, binary) for an EmptyEpsilon folder."""
    path = path.expanduser().resolve()
    bundle = "_build/EmptyEpsilon.app/Contents/Resources"
    for res in (path, path / bundle, path / "EmptyEpsilon" / bundle):
        if not (res / "scripts").is_dir():
            continue
        for binary in (res.parent / "MacOS" / "EmptyEpsilon",      # macOS app bundle
                       res / "_build" / "EmptyEpsilon",            # Linux checkout
                       res / "EmptyEpsilon"):                      # installed copy
            if binary.is_file() and os.access(binary, os.X_OK):
                return res, binary
    raise SystemExit(f"No EmptyEpsilon with a scripts/ folder and a binary under {path}.")


def scenario_text(arc: str) -> str:
    """The base scenario's header (so its settings and defaults apply), then base + harness + test."""
    header = []
    for line in BASE_SCENARIO.read_text(encoding="utf-8").splitlines():
        if not line.startswith("--"):
            break
        header.append(f"-- Name: Arc test {arc}" if line.startswith("-- Name:") else line)
    body = [
        f'require("{BASE_SCENARIO.name}")',
        f'require("{SCRIPT_DIR_NAME}/_harness.lua")',
        f'require("{SCRIPT_DIR_NAME}/{arc}.lua")',
    ]
    return "\n".join(header + [""] + body) + "\n"


def run_arc(arc: str, res: Path, binary: Path, port: int, timeout: float, log_dir: Path) -> dict:
    home = Path(tempfile.mkdtemp(prefix=f"arctest_{arc}_"))
    (home / ".emptyepsilon").mkdir()
    log_path = log_dir / f"{arc}.log"
    env = dict(os.environ, HOME=str(home), SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    started = time.time()
    with open(log_path, "wb") as log:
        proc = subprocess.Popen(
            [str(binary), f"headless={SCENARIO_PREFIX}{arc}.lua", f"server_port={port}"],
            cwd=res, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        ended = "timeout"
        try:
            while time.time() - started < timeout:
                time.sleep(1)
                text = log_path.read_text(encoding="utf-8", errors="replace")
                if "[ARCTEST] DONE" in text:
                    ended = "done"
                    break
                if proc.poll() is not None:
                    ended = f"EmptyEpsilon exited ({proc.returncode})"
                    break
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(5)
                except subprocess.TimeoutExpired:
                    proc.kill()
    shutil.rmtree(home, ignore_errors=True)

    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    passed, failed, lua_errors = [], [], []
    for i, line in enumerate(lines):
        m = re.search(r"\[ARCTEST\] (PASS|FAIL) (.*)", line)
        if m:
            (passed if m.group(1) == "PASS" else failed).append(m.group(2))
        elif "LUA-Error" in line:
            lua_errors.append(" / ".join(s.strip() for s in lines[i:i + 3]))
    if ended != "done":
        failed.append(f"run did not finish: {ended} after {time.time() - started:.0f}s")
    return {"arc": arc, "passed": passed, "failed": failed, "lua_errors": lua_errors,
            "seconds": time.time() - started, "log": log_path}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("arcs", nargs="*", help="tests to run: names or a folder (arcs, jobs); default everything")
    ap.add_argument("--ee", default=os.environ.get("EE_DIR"), help="EmptyEpsilon folder (or set EE_DIR)")
    ap.add_argument("--jobs", type=int, default=4, help="EmptyEpsilon processes to run at once (default 4)")
    ap.add_argument("--timeout", type=float, default=420, help="seconds before one arc's run is abandoned")
    ap.add_argument("--port", type=int, default=35700, help="first game server port (one per arc)")
    ap.add_argument("--logs", help="keep the EmptyEpsilon logs in this folder")
    ap.add_argument("--no-install", action="store_true", help="skip tools/install.py (the repo is already installed)")
    ap.add_argument("-v", "--verbose", action="store_true", help="list every check, not only failures")
    args = ap.parse_args()
    if not args.ee:
        ap.error("give --ee <EmptyEpsilon folder> or set EE_DIR")

    by_suite = {su: sorted(p.stem for p in (TESTS / su).glob("*.lua") if not p.name.startswith("_")) for su in SUITES}
    available = [n for su in SUITES for n in by_suite[su]]
    arcs = []
    for a in (args.arcs or available):
        arcs += by_suite[a] if a in by_suite else [a]
    unknown = [a for a in arcs if a not in available]
    if unknown:
        raise SystemExit(f"No test for: {', '.join(unknown)}. Available: {', '.join(available)}")

    res, binary = find_ee(Path(args.ee))
    scripts = res / "scripts"
    if not args.no_install:
        r = subprocess.run([sys.executable, str(ROOT / "tools" / "install.py"), "--ee", str(res)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr)
            return 1

    log_dir = Path(args.logs).expanduser() if args.logs else Path(tempfile.mkdtemp(prefix="arctest_logs_"))
    log_dir.mkdir(parents=True, exist_ok=True)
    test_dir = scripts / SCRIPT_DIR_NAME
    generated = [scripts / f"{SCENARIO_PREFIX}{a}.lua" for a in arcs]
    try:
        if test_dir.exists():
            shutil.rmtree(test_dir)
        test_dir.mkdir()
        shutil.copy2(TESTS / "_harness.lua", test_dir / "_harness.lua")
        for su in SUITES:
            for f in (TESTS / su).glob("*.lua"):
                shutil.copy2(f, test_dir / f.name)
        for arc, path in zip(arcs, generated):
            path.write_text(scenario_text(arc), encoding="utf-8")
        print(f"Game tests: {', '.join(arcs)}  (EmptyEpsilon: {binary})")
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            futures = [pool.submit(run_arc, arc, res, binary, args.port + i, args.timeout, log_dir)
                       for i, arc in enumerate(arcs)]
            results = [f.result() for f in futures]
    finally:
        shutil.rmtree(test_dir, ignore_errors=True)
        for path in generated:
            path.unlink(missing_ok=True)

    ok = True
    for r in results:
        bad = len(r["failed"]) + len(r["lua_errors"])
        ok = ok and bad == 0
        print(f"\n{r['arc']}: {len(r['passed'])} passed, {len(r['failed'])} failed, "
              f"{len(r['lua_errors'])} Lua errors  ({r['seconds']:.0f}s)")
        if args.verbose:
            for name in r["passed"]:
                print(f"  PASS  {name}")
        for name in r["failed"]:
            print(f"  FAIL  {name}")
        for err in r["lua_errors"]:
            print(f"  LUA   {err[:300]}")
        if bad:
            print(f"  log: {r['log']}")
    if ok and not args.logs:
        shutil.rmtree(log_dir, ignore_errors=True)
    print("\nAll game tests passed." if ok else "\nGame tests FAILED.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
