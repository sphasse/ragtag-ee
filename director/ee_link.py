"""Talks to EmptyEpsilon's built-in HTTP API (/exec.lua).

/exec.lua runs posted Lua in a fresh environment that cannot see scenario
globals, and its return value must be a string. Both environments share the
process-wide ScriptStorage, so we read and write two mailbox keys there.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request

KEY_FROM_SCENARIO = "rt.from_scenario"
KEY_FROM_DIRECTOR = "rt.from_director"
CAMPAIGN_KEY = "ragtag.campaign"


def lua_string(s: str) -> str:
    """Encode a Python string as a safe Lua string literal."""
    out = ['"']
    for b in s.encode("utf-8"):
        c = chr(b)
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif 32 <= b < 127:
            out.append(c)
        else:
            out.append("\\%03d" % b)
    out.append('"')
    return "".join(out)


class EEError(Exception):
    pass


class EELink:
    def __init__(self, url: str, timeout: float = 4.0):
        # Accept "http://host:8080" or the full ".../exec.lua" URL.
        url = url.rstrip("/")
        if not url.endswith("/exec.lua"):
            url += "/exec.lua"
        self.url = url
        self.timeout = timeout

    def exec(self, code: str) -> str:
        req = urllib.request.Request(self.url, data=code.encode("utf-8"), method="POST",
                                     headers={"Content-Type": "text/plain"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                body = resp.read().decode("utf-8", errors="replace")
        except (urllib.error.URLError, OSError) as e:
            raise EEError(f"cannot reach EmptyEpsilon at {self.url}: {e}") from e
        if body.startswith('{"ERROR"'):
            try:
                raise EEError(json.loads(body)["ERROR"])
            except (ValueError, KeyError):
                raise EEError(body)
        return body

    def probe(self) -> dict:
        """Check connectivity and API features. Returns a dict describing the server."""
        code = r"""
local v = "unknown"
if getEEVersion then v = tostring(getEEVersion()) end
local ships = 0
if getActivePlayerShips then ships = #getActivePlayerShips() end
return string.format('{"version":"%s","json":%s,"storage":%s,"player_ships":%d}',
    v, tostring(toJSON ~= nil and fromJSON ~= nil), tostring(getScriptStorage ~= nil), ships)
"""
        return json.loads(self.exec(code))

    def get_key(self, key: str) -> str:
        code = (
            f"local v = getScriptStorage():get({lua_string(key)})\n"
            'if type(v) ~= "string" then return "" end\n'
            "return v"
        )
        return self.exec(code)

    def set_key(self, key: str, value: str) -> None:
        code = f"getScriptStorage():set({lua_string(key)}, {lua_string(value)})\nreturn \"ok\""
        self.exec(code)

    def read_scenario(self) -> dict | None:
        raw = self.get_key(KEY_FROM_SCENARIO)
        if not raw:
            return None
        try:
            return json.loads(raw)
        except ValueError:
            return None

    def write_director(self, msg: dict) -> None:
        self.set_key(KEY_FROM_DIRECTOR, json.dumps(msg, separators=(",", ":")))

    def read_campaign(self) -> dict | None:
        raw = self.get_key(CAMPAIGN_KEY)
        try:
            return json.loads(raw) if raw else None
        except ValueError:
            return None
