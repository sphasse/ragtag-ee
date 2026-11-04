"""Action catalog for the AI director.

This mirrors DIR.ACTIONS in ee_scripts/ragtag_director.lua. The Lua side is the
real safety boundary (it clamps everything again); this side exists to:
  * describe the actions to the language model,
  * reject malformed output early so the model gets useful feedback,
  * keep GM-only actions away from the model.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

FACTIONS = ["Corsairs", "Independent", "Concord", "Unknown"]


@dataclass
class Arg:
    type: str                      # "str" | "int" | "float" | "enum" | "dict" | "list"
    required: bool = False
    choices: list[str] | None = None
    lo: float | None = None
    hi: float | None = None
    max_len: int = 200
    help: str = ""


@dataclass
class Action:
    name: str
    help: str
    args: dict[str, Arg] = field(default_factory=dict)
    llm_allowed: bool = True


ACTIONS: dict[str, Action] = {}


def _add(a: Action) -> None:
    ACTIONS[a.name] = a


_add(Action("say", "Speak to the crew as a named character. If the speaker is a ship or station callsign nearby, it arrives as a comms hail; otherwise it goes to the ship's log.", {
    "speaker": Arg("str", True, max_len=40, help="character name or ship/station callsign"),
    "text": Arg("str", True, max_len=500, help="what they say; 1-3 short sentences"),
    "channel": Arg("enum", choices=["hail", "log"], help="default hail"),
}))
_add(Action("gm_note", "Private message to the human game master explaining what you are doing or suggesting something.", {
    "text": Arg("str", True, max_len=400),
}))
_add(Action("noop", "Do nothing this time.", {}))

# GM-only: the console can send these, the model cannot.
_add(Action("set_objective", "Set the crew's displayed objective.", {"text": Arg("str", True, max_len=160)}, llm_allowed=False))
_add(Action("restore_campaign", "Overwrite the campaign save on the game server.", {"campaign": Arg("dict", True)}, llm_allowed=False))
_add(Action("rename_ship", "Rename the crew's ship (persists).", {"name": Arg("str", True, max_len=24)}, llm_allowed=False))


def validate(action: str, args: Any, *, from_llm: bool) -> tuple[bool, dict, str]:
    """Return (ok, cleaned_args, error)."""
    spec = ACTIONS.get(action)
    if spec is None:
        return False, {}, f"unknown action '{action}'"
    if from_llm and not spec.llm_allowed:
        return False, {}, f"action '{action}' is GM-only"
    if args is None:
        args = {}
    if not isinstance(args, dict):
        return False, {}, "args must be an object"
    cleaned: dict[str, Any] = {}
    for name, arg in spec.args.items():
        if name not in args or args[name] in (None, ""):
            if arg.required:
                return False, {}, f"missing required arg '{name}'"
            continue
        v = args[name]
        try:
            if arg.type == "str":
                v = str(v).strip()[: arg.max_len]
            elif arg.type == "int":
                v = int(round(float(v)))
                if arg.lo is not None:
                    v = max(int(arg.lo), v)
                if arg.hi is not None:
                    v = min(int(arg.hi), v)
            elif arg.type == "float":
                v = float(v)
                if arg.lo is not None:
                    v = max(arg.lo, v)
                if arg.hi is not None:
                    v = min(arg.hi, v)
            elif arg.type == "enum":
                v = str(v).strip()
                match = [c for c in (arg.choices or []) if c.lower() == v.lower()]
                if not match:
                    return False, {}, f"arg '{name}' must be one of {arg.choices}"
                v = match[0]
            elif arg.type == "dict":
                if not isinstance(v, dict):
                    return False, {}, f"arg '{name}' must be an object"
            elif arg.type == "list":
                if not isinstance(v, list):
                    return False, {}, f"arg '{name}' must be an array"
                if arg.max_len:
                    v = v[:arg.max_len]
        except (TypeError, ValueError):
            return False, {}, f"arg '{name}' has the wrong type"
        cleaned[name] = v
    unknown = set(args) - set(spec.args)
    note = f" (ignored unknown args: {sorted(unknown)})" if unknown else ""
    return True, cleaned, note


def catalog_for_prompt() -> str:
    lines = []
    for a in ACTIONS.values():
        if not a.llm_allowed:
            continue
        parts = []
        for n, arg in a.args.items():
            t = arg.type
            if arg.choices:
                t = "|".join(arg.choices)
            elif arg.lo is not None or arg.hi is not None:
                t = f"{arg.type} {arg.lo:g}..{arg.hi:g}"
            req = "" if arg.required else "?"
            hint = f" ({arg.help})" if arg.help else ""
            parts.append(f"{n}{req}: {t}{hint}")
        lines.append(f"- {a.name}: {a.help}\n    args: {{{', '.join(parts)}}}" if parts else f"- {a.name}: {a.help}")
    return "\n".join(lines)
