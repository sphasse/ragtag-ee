"""Pure-Python Lua table parser: reads VERSE.extend({...}) calls without lua5.4.

Only handles the subset of Lua used in verse data files (drift.lua and
extensions): table literals, strings, numbers, booleans, nil.  No arithmetic,
no variables, no function definitions.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Tokeniser
# ---------------------------------------------------------------------------

def _tokenize(src: str) -> list[tuple[str, Any]]:
    toks: list[tuple[str, Any]] = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        # whitespace
        if c in " \t\r\n":
            i += 1
            continue
        # comments
        if src[i:i+2] == "--":
            if src[i+2:i+4] == "[[":
                end = src.find("]]", i + 4)
                i = (end + 2) if end >= 0 else n
            else:
                end = src.find("\n", i)
                i = (end + 1) if end >= 0 else n
            continue
        # long strings  [[ ... ]]
        if src[i:i+2] == "[[":
            end = src.find("]]", i + 2)
            if end < 0:
                raise SyntaxError("unterminated long string in Lua source")
            toks.append(("STR", src[i+2:end]))
            i = end + 2
            continue
        # short strings
        if c in "\"'":
            j = i + 1
            parts: list[str] = []
            while j < n and src[j] != c:
                if src[j] == "\\":
                    j += 1
                    parts.append({
                        "a": "\a", "b": "\b", "f": "\f", "n": "\n",
                        "r": "\r", "t": "\t", "v": "\v",
                        "\\": "\\", "'": "'", '"': '"',
                    }.get(src[j], src[j]))
                else:
                    parts.append(src[j])
                j += 1
            toks.append(("STR", "".join(parts)))
            i = j + 1
            continue
        # numbers (hex or decimal)
        if c.isdigit() or (c == "." and i + 1 < n and src[i+1].isdigit()):
            m = re.match(r"0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?", src[i:])
            v = m.group()  # type: ignore[union-attr]
            if v.lower().startswith("0x"):
                toks.append(("NUM", int(v, 16)))
            elif "." in v or "e" in v.lower():
                toks.append(("NUM", float(v)))
            else:
                toks.append(("NUM", int(v)))
            i += len(v)
            continue
        # identifiers / keywords
        if c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_]\w*", src[i:])
            w = m.group()  # type: ignore[union-attr]
            i += len(w)
            if w == "true":   toks.append(("BOOL", True))
            elif w == "false": toks.append(("BOOL", False))
            elif w == "nil":  toks.append(("NIL", None))
            else:             toks.append(("ID", w))
            continue
        # multi-char punctuation
        if src[i:i+3] == "...":
            toks.append(("VARARG", None)); i += 3; continue
        if src[i:i+2] == "..":
            toks.append(("CONCAT", None)); i += 2; continue
        if src[i:i+2] in ("==", "~=", "<=", ">="):
            toks.append((src[i:i+2], None)); i += 2; continue
        # single-char
        toks.append((c, c)); i += 1
    toks.append(("EOF", None))
    return toks


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

class _Parser:
    def __init__(self, tokens: list[tuple[str, Any]]) -> None:
        self.t = tokens
        self.p = 0

    def peek(self, offset: int = 0) -> tuple[str, Any]:
        idx = self.p + offset
        return self.t[idx] if idx < len(self.t) else ("EOF", None)

    def next(self) -> tuple[str, Any]:
        tok = self.t[self.p]
        self.p += 1
        return tok

    def expect(self, kind: str) -> tuple[str, Any]:
        tok = self.next()
        if tok[0] != kind:
            raise SyntaxError(f"expected {kind!r}, got {tok!r} (pos {self.p})")
        return tok

    def parse_value(self) -> Any:
        k, v = self.peek()
        if k == "STR":   self.next(); return v
        if k == "NUM":   self.next(); return v
        if k == "BOOL":  self.next(); return v
        if k == "NIL":   self.next(); return None
        if k == "{":     return self.parse_table()
        if k == "-":
            self.next()
            val = self.parse_value()
            return -val if isinstance(val, (int, float)) else val
        if k == "ID":
            name = v
            self.next()
            while self.peek()[0] == ".":
                self.next()
                _, nm = self.expect("ID")
                name += "." + nm
            # Function call: f(...) or f{...} or f"..."
            if self.peek()[0] == "(":
                self.next()
                while self.peek()[0] != ")":
                    self.parse_value()
                    if self.peek()[0] == ",":
                        self.next()
                self.next()  # )
                return None
            if self.peek()[0] in ("{", "STR"):
                self.parse_value()
                return None
            return name
        # skip unknown single token
        self.next()
        return None

    def parse_table(self) -> Any:
        self.expect("{")
        lst: list[Any] = []
        dct: dict[Any, Any] = {}
        while self.peek()[0] != "}":
            # named key:  ident = value
            if self.peek(0)[0] == "ID" and self.peek(1)[0] == "=":
                key = self.next()[1]
                self.next()  # =
                dct[key] = self.parse_value()
            # computed key:  [expr] = value
            elif self.peek(0)[0] == "[" and self.peek(1)[0] != "[":
                self.next()  # [
                key = self.parse_value()
                self.expect("]")
                self.expect("=")
                dct[key] = self.parse_value()
            else:
                lst.append(self.parse_value())
            if self.peek()[0] in (",", ";"):
                self.next()
        self.next()  # }
        if lst and not dct:
            return lst
        if dct and not lst:
            return dct
        # Mixed (unusual): Lua uses integer keys 1..n for the list part.
        for i, val in enumerate(lst, 1):
            dct[i] = val
        return dct

    def parse_top(self) -> list[dict]:
        """Scan for VERSE.extend({...}) calls; return their table arguments."""
        specs: list[dict] = []
        while self.peek()[0] != "EOF":
            k, v = self.peek()
            if k == "ID" and v == "VERSE":
                self.next()
                if self.peek()[0] == ".":
                    self.next()
                    if self.peek()[0] == "ID" and self.peek()[1] == "extend":
                        self.next()
                        if self.peek()[0] == "(":
                            self.next()
                            table = self.parse_table()
                            if self.peek()[0] == ")":
                                self.next()
                            if isinstance(table, dict):
                                specs.append(table)
                            continue
            self.next()
        return specs


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

_LISTS = [
    "stars", "planets", "stations", "regions",
    "nebula_fields", "asteroid_fields", "garrisons",
    "minefields", "hazards", "wreck_fields", "salvage",
    "routes", "rumors", "lore",
]


def load(ragtag_dir: Path, ext_files: list[Path]) -> dict:
    """Load universe data from drift.lua + extension files without lua5.4.

    Returns the same structure as verse_data.load() (minus deep validation).
    """
    data: dict = {k: [] for k in _LISTS}
    data["extensions"] = []
    data["problems"] = []
    data["places"] = {}
    seen: set[str] = set()

    def _norm(v: Any) -> Any:
        """Normalise mixed Lua tables: integer-keyed dicts → lists."""
        if isinstance(v, list):
            return [_norm(i) for i in v]
        if isinstance(v, dict):
            int_keys = sorted([k for k in v if isinstance(k, int)])
            if int_keys and int_keys == list(range(1, len(int_keys) + 1)) and len(int_keys) == len(v):
                return [_norm(v[k]) for k in int_keys]
            return {str(k): _norm(vv) for k, vv in v.items()}
        return v

    def _apply(spec: dict) -> None:
        sid = spec.get("id")
        if not isinstance(sid, str) or sid in seen:
            return
        seen.add(sid)
        data["extensions"].append({"id": sid, "title": spec.get("title", sid)})

        for key in _LISTS:
            raw = spec.get(key)
            if raw is None:
                continue
            items = _norm(raw)
            if not isinstance(items, list):
                continue
            for item in items:
                if isinstance(item, dict):
                    item["source"] = sid
                data[key].append(item)

        rs = spec.get("route_stops")
        if isinstance(rs, dict):
            for route_id, stops in rs.items():
                stops_list = _norm(stops) if not isinstance(stops, list) else stops
                for r in data["routes"]:
                    if isinstance(r, dict) and r.get("id") == route_id:
                        r.setdefault("stations", []).extend(stops_list)

    drift = ragtag_dir / "verse" / "drift.lua"
    for path in [drift] + list(ext_files):
        src = path.read_text(encoding="utf-8")
        parser = _Parser(_tokenize(src))
        for spec in parser.parse_top():
            _apply(spec)

    # Build places (mirrors VERSE.validate's place registration)
    for kind, key, name_field in [
        ("star", "stars", "name"),
        ("planet", "planets", "name"),
        ("station", "stations", "cs"),
    ]:
        for e in data[kind + "s"]:
            if isinstance(e, dict):
                nm = e.get(name_field)
                if nm:
                    data["places"][nm] = kind

    return data
