"""Install the framework, universe extensions and scenarios into EmptyEpsilon.

    python tools/install.py --ee "C:/Games/EmptyEpsilon"          # copy
    python tools/install.py --ee ~/EmptyEpsilon --link            # symlink (for development)
    python tools/install.py --ee ~/EmptyEpsilon --only longhaul   # just one scenario folder

--ee is the EmptyEpsilon folder that contains scripts/. Installs:
  ee/ragtag/                  -> scripts/ragtag/            (libraries + universe)
  scenarios/*/scenario_*.lua  -> scripts/                   (EE only lists top-level scenarios)
Folders under scenarios/ whose name starts with "_" (templates) are skipped.
Re-running replaces what the previous install put there, including files from
the old flat layout (ragtag_core.lua etc.).
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check import write_extension_index  # noqa: E402

LEGACY = ["ragtag_core.lua", "ragtag_director.lua", "ragtag_verse.lua", "scenario_70_longhaul_1.lua"]


def scenario_files(only: str | None) -> list[Path]:
    files = []
    for d in sorted((ROOT / "scenarios").iterdir()):
        if not d.is_dir() or d.name.startswith("_") or (only and d.name != only):
            continue
        files += sorted(d.glob("scenario_*.lua"))
    return files


def place(src: Path, dst: Path, link: bool) -> None:
    if dst.is_symlink() or dst.is_file():
        dst.unlink()
    elif dst.is_dir():
        shutil.rmtree(dst)
    if link:
        dst.symlink_to(src.resolve(), target_is_directory=src.is_dir())
    elif src.is_dir():
        shutil.copytree(src, dst)
    else:
        shutil.copy2(src, dst)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ee", required=True, help="EmptyEpsilon folder (the one containing scripts/)")
    ap.add_argument("--link", action="store_true", help="symlink instead of copying (edits show up without reinstalling)")
    ap.add_argument("--only", help="install just this scenarios/ folder")
    args = ap.parse_args()

    scripts = Path(args.ee).expanduser() / "scripts"
    if not scripts.is_dir():
        print(f"No scripts/ folder in {args.ee}. Point --ee at the EmptyEpsilon install folder.")
        return 1

    write_extension_index()
    manifest_path = scripts / ".ragtag_installed.json"
    previous = []
    if manifest_path.exists():
        previous = json.loads(manifest_path.read_text()).get("scenarios", [])
    for name in previous + LEGACY:
        p = scripts / name
        if p.is_file() or p.is_symlink():
            p.unlink()

    place(ROOT / "ee" / "ragtag", scripts / "ragtag", args.link)
    installed = []
    for f in scenario_files(args.only):
        place(f, scripts / f.name, args.link)
        installed.append(f.name)
    manifest_path.write_text(json.dumps({"scenarios": installed}, indent=2))
    print(f"Installed ragtag libraries and {len(installed)} scenario(s) into {scripts}:")
    for n in installed:
        print("  ", n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
