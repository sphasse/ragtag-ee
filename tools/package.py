#!/usr/bin/env python3
"""Build a player release: a zip to unzip into the EmptyEpsilon folder.

    python3 tools/package.py --version 0.1.0                 # dist/ragtag-0.1.0.zip
    python3 tools/package.py --version 0.1.0 --radar-icons   # also the sharper station radar icons

The zip holds what tools/install.py copies, laid out from the EmptyEpsilon folder:
  scripts/ragtag/                  ee/ragtag/ (libraries, universe, arcs, jobs, world, sfx)
  scripts/scenario_*.lua           scenarios/*/ (not folders starting with "_")
  resources/radar/*.png            assets/radar/ (only with --radar-icons; replaces stock icons)
  RAGTAG_README.txt                how to install
Regenerates the generated files first (check.py --fix; --no-fix leaves the tree untouched and only
checks), then runs check.py; refuses to build if it reports errors. Only files tracked by git go
in. Tests, the template scenario, the developer scenarios (DEV_SCENARIOS: the Battle and Audit
Labs) and the Python director are not included.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from install import scenario_files  # noqa: E402

README = """Ragtag for EmptyEpsilon, version {version}
=========================================

Install
-------
1. Find your EmptyEpsilon folder:
   - Windows / Linux: the folder with EmptyEpsilon.exe / EmptyEpsilon in it
   - macOS: right-click EmptyEpsilon.app, Show Package Contents, then Contents/Resources
2. Upgrading? Delete the old scripts/ragtag folder first (your campaign save is not in it).
3. Unzip this file into that folder, merging its scripts/ folder with the one already there.
4. Start EmptyEpsilon and pick the scenario "{scenarios}" on the server.

{radar}Files
-----
scripts/ragtag/          the framework, the universe, story arcs, jobs and sounds
scripts/scenario_*.lua   the campaign scenario(s)
"""

RADAR_NOTE = """Radar icons
-----------
resources/radar/ holds sharper station radar icons. They replace EmptyEpsilon's own icons of the
same names; leave that folder out if you prefer the stock art.

"""


# Scenario folders for developers (balancing test beds), installed by install.py but not released.
# (The Battle and Audit Labs are parked in scenarios/_battlelab, skipped anyway; this keeps them
# out of a release if the folder is renamed back to battlelab.)
DEV_SCENARIOS = {"battlelab"}


def release_scenarios() -> list[Path]:
    return [f for f in scenario_files(None) if f.parent.name not in DEV_SCENARIOS]


def tracked(folder: Path) -> list[Path]:
    """Files under folder that git tracks (a stray untracked file never ships)."""
    out = subprocess.run(["git", "ls-files", "-z", "--", str(folder.relative_to(ROOT))], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout
    return sorted(ROOT / f for f in out.split("\0") if f)


def scenario_titles(files: list[Path]) -> str:
    titles = []
    for f in files:
        for line in f.read_text(encoding="utf-8").splitlines()[:10]:
            if line.startswith("-- Name:"):
                titles.append(line.split(":", 1)[1].strip())
                break
        else:
            titles.append(f.stem)
    return ", ".join(titles)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", required=True, help="release version, e.g. 0.1.0 (goes in the file name)")
    ap.add_argument("--radar-icons", action="store_true", help="include assets/radar/*.png as resources/radar/")
    ap.add_argument("--out", default=str(ROOT / "dist"), help="output folder (default dist/)")
    ap.add_argument("--no-fix", action="store_true",
                    help="do not regenerate the generated files (change nothing in the tree); only check")
    args = ap.parse_args()

    cmds = [[sys.executable, str(ROOT / "tools" / "check.py")]]
    if not args.no_fix:
        cmds.insert(0, [sys.executable, str(ROOT / "tools" / "check.py"), "--fix"])
    for cmd in cmds:
        if subprocess.run(cmd, cwd=ROOT).returncode != 0:
            print("check.py failed: fix the errors before packaging.")
            return 1

    scenarios = release_scenarios()
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    zpath = out / f"ragtag-{args.version}.zip"
    count = 0
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for f in tracked(ROOT / "ee" / "ragtag"):
            if f.is_file():
                z.write(f, Path("scripts/ragtag") / f.relative_to(ROOT / "ee" / "ragtag"))
                count += 1
        for f in scenarios:
            z.write(f, Path("scripts") / f.name)
            count += 1
        if args.radar_icons:
            for f in sorted((ROOT / "assets" / "radar").glob("*.png")):
                z.write(f, Path("resources/radar") / f.name)
                count += 1
        z.writestr("RAGTAG_README.txt", README.format(
            version=args.version, scenarios=scenario_titles(scenarios),
            radar=RADAR_NOTE if args.radar_icons else ""))
    print(f"Wrote {zpath} ({count} files, {zpath.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
