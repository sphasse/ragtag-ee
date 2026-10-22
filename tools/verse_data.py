"""Load the universe data by running tools/dump_verse.lua (the same schema code the game runs)."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAGTAG = ROOT / "ee" / "ragtag"
EXT_DIR = RAGTAG / "verse" / "extensions"


def lua_binary() -> str:
    for name in ("lua5.4", "lua54", "lua"):
        path = shutil.which(name)
        if path:
            return path
    raise SystemExit("Lua 5.4 is required for this tool (apt install lua5.4 / brew install lua / scoop install lua).")


def extension_files() -> list[Path]:
    return sorted(p for p in EXT_DIR.glob("*.lua") if p.name != "index.lua")


def load() -> dict:
    cmd = [lua_binary(), str(ROOT / "tools" / "dump_verse.lua"), str(RAGTAG)] + [str(p) for p in extension_files()]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise SystemExit(f"Universe data failed to load:\n{res.stderr.strip()}")
    data = json.loads(res.stdout)
    for key, val in list(data.items()):
        if val == {}:          # empty Lua tables encode as {}
            data[key] = []
    return data
