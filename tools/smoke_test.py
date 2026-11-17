"""Smoke test for ragtag scenarios: the universe is built and the director bridge answers.

    python3 tools/smoke_test.py --launch <EmptyEpsilon dir>   # start a headless game, test it, stop it
    python3 tools/smoke_test.py --ee http://127.0.0.1:8080    # test a server that is already running

--launch does everything in one command (any platform): installs this repo into that
EmptyEpsilon (as tools/install.py does), starts the sandbox scenario headless with its own
empty HOME (so no real campaign save is touched), runs the checks, fails on any LUA-Error in
the log, and stops the game. <EmptyEpsilon dir> is what tools/install.py takes, or a checkout
with a _build/ in it (EE_DIR works too).

With --ee, start a ragtag scenario on the server first (httpserver=8080 in options.ini) and
stop the director: both write the same mailbox key. That mode changes the running campaign.

It checks the universe was built and sends every director action once, checking the game's
replies. Story arcs and jobs have their own tests: tools/game_tests.py.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "director"))
sys.path.insert(0, str(ROOT / "tools"))
from ee_link import EELink, EEError  # noqa: E402


class Bridge:
    def __init__(self, ee: EELink):
        self.ee = ee
        self.hb = 0
        self.ack = 0
        self.cmds: list[dict] = []
        self.next_id = 1
        self.events: list[dict] = []
        self.results: dict[int, dict] = {}
        self.msg: dict = {}

    def sync(self) -> dict:
        msg = self.ee.read_scenario()
        if not msg:
            raise SystemExit("No scenario mailbox. Is a ragtag scenario running?")
        if self.msg and msg.get("run") != self.msg.get("run"):
            raise SystemExit("Scenario restarted during the test.")
        self.msg = msg
        for ev in msg.get("events") or []:
            if ev["id"] > self.ack:
                self.ack = ev["id"]
                self.events.append(ev)
        cmd_ack = msg.get("cmd_ack") or 0
        self.cmds = [c for c in self.cmds if c["id"] > cmd_ack]
        for r in msg.get("results") or []:
            self.results[r["id"]] = r
        self.hb += 1
        self.ee.write_director({"proto": 1, "run": msg["run"], "hb": self.hb, "event_ack": self.ack,
                                "paused": False, "cmds": self.cmds})
        return msg

    def send(self, action: str, args: dict, source: str = "llm") -> int:
        cid = self.next_id
        self.next_id += 1
        self.cmds.append({"id": cid, "action": action, "args": args, "source": source})
        return cid

    def wait_result(self, cid: int, timeout: float = 10) -> dict | None:
        end = time.time() + timeout
        while time.time() < end:
            self.sync()
            if cid in self.results:
                return self.results[cid]
            time.sleep(0.7)
        return None

    def wait_event(self, pred, timeout: float = 30) -> dict | None:
        end = time.time() + timeout
        seen = len(self.events)
        while time.time() < end:
            self.sync()
            for ev in self.events[seen:]:
                if pred(ev):
                    return ev
            time.sleep(0.7)
        return None

    def lua(self, code: str) -> str:
        return self.ee.exec(code)


PASS, FAIL = [], []


def check(name: str, ok: bool, detail: str = "") -> None:
    (PASS if ok else FAIL).append(name)
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


def test_actions(b: Bridge) -> None:
    print("Director actions:")
    # (name, action, args, sent by, expected to succeed). The director is observation-only: the
    # model may leave the GM a note or do nothing; whatever the crew can see is the GM's to send.
    cases = [
        ("model: gm_note",            "gm_note",  {"text": "Smoke test GM note"}, "llm", True),
        ("model: noop",               "noop",     {}, "llm", True),
        ("model: say refused",        "say",      {"speaker": "Port Vesper", "text": "Smoke test: the model speaks."}, "llm", False),
        ("model: say to log refused", "say",      {"speaker": "Someone", "text": "Smoke test log line.", "channel": "log"}, "llm", False),
        ("model: set_objective refused", "set_objective", {"text": "Smoke test objective"}, "llm", False),
        ("model: rename_ship refused", "rename_ship", {"name": "Hacked"}, "llm", False),
        ("model: unknown action refused", "launch_nukes", {}, "llm", False),
        ("GM: say as station hail",   "say",      {"speaker": "Port Vesper", "text": "Smoke test: hello from the dock."}, "gm", True),
        ("GM: say to log",            "say",      {"speaker": "Someone", "text": "Smoke test log line.", "channel": "log"}, "gm", True),
    ]
    for name, action, args, source, expect in cases:
        cid = b.send(action, args, source)
        r = b.wait_result(cid)
        if r is None:
            check(name, False, "no result")
        else:
            check(name, bool(r["ok"]) == expect, r["msg"])


def test_verse(b: Bridge) -> None:
    print("The verse:")
    r = b.lua(
        'local c = {stations = 0, freighters = 0, planets = 0, pods = 0, hostiles = 0}\n'
        'for _, o in ipairs(getObjectsInRadius(0, 0, 400000)) do\n'
        '  if o.components.typename ~= nil then\n'
        '    local tn = o:getTypeName()\n'
        '    if tn:find("Station") then c.stations = c.stations + 1 end\n'
        '    if tn:find("Freighter") and o:getImpulseMaxSpeed() > 0 then c.freighters = c.freighters + 1 end\n'
        '    local f = o:getFaction()\n'
        '    if f == "Corsairs" or f == "Hollow" or f == "Relic" then c.hostiles = c.hostiles + 1 end\n'
        '  end\n'
        '  if o.components.planet_render ~= nil then c.planets = c.planets + 1 end\n'
        '  if o.components.pickup ~= nil then c.pods = c.pods + 1 end\n'
        'end\n'
        'return string.format(\'{"stations":%d,"freighters":%d,"hostiles":%d,"pods":%d}\', c.stations, c.freighters, c.hostiles, c.pods)')
    c = json.loads(r)
    check("stations built", c["stations"] >= 16, str(c["stations"]))
    check("transports flying", c["freighters"] >= 12, str(c["freighters"]))
    check("hostile garrisons present", c["hostiles"] >= 30, str(c["hostiles"]))
    check("salvage pods placed", c["pods"] >= 60, str(c["pods"]))
    for f in ("Concord", "Corsairs", "Hollow", "Relic", "Unknown", "Derelict"):
        ok = b.lua(f'return tostring(getFactionInfo("{f}") ~= nil)') == "true"
        check(f"faction {f}", ok)
    st = b.sync()["state"]
    check("region reported", st["extra"].get("region") not in (None, ""), st["extra"].get("region"))


def run_checks(url: str) -> int:
    ee = EELink(url)
    try:
        info = ee.probe()
    except EEError as e:
        print(f"Cannot reach EmptyEpsilon: {e}")
        return 1
    print(f"EmptyEpsilon {info}")
    b = Bridge(ee)
    b.sync()
    print(f"Scenario run {b.msg['run']}")
    test_verse(b)
    test_actions(b)
    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    return 0 if not FAIL else 1


def launch_and_test(ee_dir: str, scenario: str, port: int, install: bool, keep_log: str | None) -> int:
    """Start a headless EmptyEpsilon on `scenario`, run the checks against it, stop it."""
    from game_tests import find_ee   # same folder resolution as the game tests

    res, binary = find_ee(Path(ee_dir))
    if install:
        r = subprocess.run([sys.executable, str(ROOT / "tools" / "install.py"), "--ee", str(res)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr)
            return 1
    home = Path(tempfile.mkdtemp(prefix="smoke_home_"))      # own empty save
    (home / ".emptyepsilon").mkdir()
    log_path = Path(keep_log).expanduser() if keep_log else home / "ee.log"
    env = dict(os.environ, HOME=str(home), SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    url = f"http://127.0.0.1:{port}"
    print(f"Starting {binary} headless={scenario} (http {port})")
    status = 1
    with open(log_path, "wb") as log:
        proc = subprocess.Popen(
            [str(binary), f"headless={scenario}", f"httpserver={port}", f"server_port={port + 1}"],
            cwd=res, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            up = False
            for _ in range(60):
                if proc.poll() is not None:
                    break
                try:
                    EELink(url, timeout=2).probe()
                    up = True
                    break
                except EEError:
                    time.sleep(1)
            if not up:
                print("EmptyEpsilon did not come up" + (f" (exit code {proc.returncode})" if proc.poll() is not None else " within 60 s"))
            else:
                time.sleep(4)                                  # let the scenario build the universe
                status = run_checks(url)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(5)
                except subprocess.TimeoutExpired:
                    proc.kill()
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    lua_errors = [" / ".join(s.strip() for s in lines[i:i + 3]) for i, line in enumerate(lines) if "LUA-Error" in line]
    if lua_errors:
        status = 1
        print(f"\n{len(lua_errors)} LUA-Error line(s) in the EmptyEpsilon log:")
        for e in lua_errors[:10]:
            print("  " + e[:300])
    else:
        print("No LUA-Error in the EmptyEpsilon log.")
    if status != 0 and not keep_log:
        kept = Path(tempfile.gettempdir()) / "smoke_ee.log"
        shutil.copy2(log_path, kept)
        print(f"log: {kept}")
    shutil.rmtree(home, ignore_errors=True)
    return status


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ee", default="http://127.0.0.1:8080", help="URL of a running server (default mode)")
    ap.add_argument("--launch", nargs="?", const=os.environ.get("EE_DIR", ""), metavar="EE_DIR",
                    help="start a headless EmptyEpsilon from this folder (or $EE_DIR), test it, stop it")
    ap.add_argument("--scenario", default="scenario_80_ragtag.lua", help="scenario for --launch")
    ap.add_argument("--port", type=int, default=35990, help="HTTP port for --launch (game port is the next one)")
    ap.add_argument("--no-install", action="store_true", help="--launch: skip tools/install.py")
    ap.add_argument("--log", help="--launch: keep the EmptyEpsilon log here")
    args = ap.parse_args()
    if args.launch is not None:
        if not args.launch:
            ap.error("--launch needs an EmptyEpsilon folder (or set EE_DIR)")
        return launch_and_test(args.launch, args.scenario, args.port, not args.no_install, args.log)
    return run_checks(args.ee)


if __name__ == "__main__":
    sys.exit(main())
