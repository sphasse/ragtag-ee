"""Load the universe data by running tools/dump_verse.lua (the same schema code the game runs).

Falls back to a pure-Python Lua table parser (lua_parse.py) when lua5.4 is not
available, so checks and code generation work without the Lua toolchain.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAGTAG = ROOT / "ee" / "ragtag"
EXT_DIR = RAGTAG / "verse" / "extensions"


def lua_binary() -> str | None:
    for name in ("lua5.4", "lua54", "lua"):
        path = shutil.which(name)
        if path:
            return path
    return None


def extension_files() -> list[Path]:
    return sorted(p for p in EXT_DIR.glob("*.lua") if p.name != "index.lua")


def load() -> dict:
    lua = lua_binary()
    if lua:
        cmd = [lua, str(ROOT / "tools" / "dump_verse.lua"), str(RAGTAG)] + [str(p) for p in extension_files()]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise SystemExit(f"Universe data failed to load:\n{res.stderr.strip()}")
        data = json.loads(res.stdout)
        for key, val in list(data.items()):
            if val == {}:          # empty Lua tables encode as {}
                data[key] = []
        return data

    # Lua not available: use the pure-Python parser.
    import lua_parse  # noqa: PLC0415
    return lua_parse.load(RAGTAG, extension_files())
