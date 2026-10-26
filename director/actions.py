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
SYSTEMS = ["reactor", "beams", "missiles", "maneuver", "impulse", "warp", "jumpdrive", "frontshield", "rearshield"]


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
_add(Action("main_screen", "Short banner on every main screen. Use rarely, for big moments.", {
    "text": Arg("str", True, max_len=120),
}))
_add(Action("gm_note", "Private message to the human game master explaining what you are doing or suggesting something.", {
    "text": Arg("str", True, max_len=400),
}))
_add(Action("spawn_group", "Spawn a group of ships. Hostile factions attack by default. Subject to a hostile budget and cooldown.", {
    "faction": Arg("enum", True, choices=FACTIONS),
    "strength": Arg("enum", True, choices=["scout", "light", "medium", "heavy"], help="scout=1 ship, light=2, medium=3, heavy=4"),
    "near": Arg("str", max_len=40, help="'player' (default) or a callsign"),
    "distance": Arg("float", lo=6, hi=30, help="units from anchor, default 12"),
    "side": Arg("enum", choices=["ahead", "behind", "any"]),
    "behavior": Arg("enum", choices=["attack", "patrol", "idle", "flee", "follow"]),
    "callsign": Arg("str", max_len=24, help="optional name for the leader"),
}))
_add(Action("spawn_npc", "Spawn one non-hostile NPC ship the crew can hail. When hailed, you will get an npc_hailed event and should answer with 'say' using its callsign as speaker.", {
    "role": Arg("enum", True, choices=["trader", "patrol", "derelict", "stranger"]),
    "faction": Arg("enum", choices=FACTIONS),
    "callsign": Arg("str", max_len=24),
    "near": Arg("str", max_len=40),
    "distance": Arg("float", lo=3, hi=25),
    "side": Arg("enum", choices=["ahead", "behind", "any"]),
    "greeting": Arg("str", max_len=300, help="first line shown when the crew hails them"),
    "description": Arg("str", max_len=300, help="what Science sees on a scan"),
}))
_add(Action("spawn_salvage", "Place a pick-up-able cargo pod worth a few credits.", {
    "near": Arg("str", max_len=40),
    "distance": Arg("float", lo=2, hi=20),
    "side": Arg("enum", choices=["ahead", "behind", "any"]),
    "credits": Arg("int", lo=0, hi=150),
    "label": Arg("str", max_len=40),
    "description": Arg("str", max_len=200),
}))
_add(Action("give_credits", "Pay or fine the crew. Positive amounts are capped per session.", {
    "amount": Arg("int", True, lo=-300, hi=300),
    "reason": Arg("str", max_len=60),
}))
_add(Action("system_glitch", "Damage one ship system a little so Engineering has a problem to solve. Has a cooldown. Justify it in-fiction.", {
    "system": Arg("enum", True, choices=SYSTEMS),
    "severity": Arg("float", lo=0.1, hi=0.5),
    "reason": Arg("str", max_len=120, help="shown in the ship's log"),
}))
_add(Action("fire_beat", "Trigger one of the scenario's story beats that is marked ai=true and not yet fired.", {
    "beat": Arg("str", True, max_len=40),
}))
_add(Action("npc_order", "Give an order to an NPC you spawned (or one the scenario lets you control).", {
    "callsign": Arg("str", True, max_len=40),
    "order": Arg("enum", True, choices=["attack", "flee", "idle", "follow", "patrol", "dock"]),
    "target": Arg("str", max_len=40, help="station callsign for dock"),
}))
_add(Action("noop", "Do nothing this time.", {}))
_add(Action("create_mission", "Create a director-driven delivery or escort mission. The crew must fly from the origin to the destination and dock there. Events fire automatically at 1/3 and 2/3 of the route. Pay is awarded on docking. Use sparingly: one or two active at a time.", {
    "from_cs":         Arg("str",   True,  max_len=40,  help="callsign of the origin station or NPC"),
    "to_cs":           Arg("str",   True,  max_len=40,  help="callsign of the destination station or NPC"),
    "cargo":           Arg("str",   False, max_len=80,  help="what is being transported, e.g. 'medical supplies'"),
    "reward":          Arg("int",   False, lo=50, hi=500, help="credits paid on completion, default 120"),
    "intro":           Arg("str",   False, max_len=400, help="first thing the origin character says to kick off the job"),
    "speaker":         Arg("str",   False, max_len=40,  help="who speaks the intro; defaults to from_cs"),
    "event_1":         Arg("str",   False, max_len=400, help="message at ~1/3 of the route (optional)"),
    "event_1_speaker": Arg("str",   False, max_len=40,  help="speaker for event_1; defaults to from_cs"),
    "event_2":         Arg("str",   False, max_len=400, help="message at ~2/3 of the route (optional)"),
    "event_2_speaker": Arg("str",   False, max_len=40,  help="speaker for event_2; defaults to from_cs"),
}))
_add(Action("say_sequence", "Queue several lines from one speaker at timed intervals. Use this for any encounter that needs more than one NPC line — taunts, negotiations, reveals. One LLM call covers the whole interaction; no further calls needed.", {
    "speaker": Arg("str", True, max_len=40, help="character name or ship/station callsign"),
    "lines": Arg("list", True, max_len=8, help='[{"text":"...","delay":5}, ...] — first line fires immediately; delay is seconds after the previous line'),
}))
_add(Action("comms_tree", "Pre-load a reply tree onto a director NPC so the crew gets instant answers when they hail. Use right after spawning the NPC. No LLM round-trip at hail time.", {
    "callsign": Arg("str", True, max_len=24, help="callsign of the NPC"),
    "opening": Arg("str", True, max_len=300, help="what the NPC says when the crew opens comms"),
    "options": Arg("list", True, max_len=4, help='[{"label":"What do you want?","reply":"Credits, like everyone."}] — up to 4 crew choices and NPC responses'),
}))

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
