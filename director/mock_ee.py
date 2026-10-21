"""A fake scenario for testing prompts and the console without running the game.

python main.py --mock

It plays a canned sequence of events from session 1 and acknowledges every
command as if the game ran it.
"""

from __future__ import annotations

import time

SCRIPT = [
    (2, "session_start", {"session": {
        "id": "s1", "title": "Cold Cargo (mock)",
        "premise": "The Magpie takes a delivery job from fixer Mags Oduya. One crate is not what the manifest says.",
        "tone": "Scrappy frontier western in space.",
        "cast": [{"name": "Mags Oduya", "where": "Port Vesper", "role": "fixer", "voice": "dry, warm, menacing"},
                 {"name": "Lt. Corin Vashti", "where": "CPV Diligence", "role": "Concord officer", "voice": "tired, by-the-book"}],
        "director_guidance": "Fire 'inspection' and 'ambush' when timing feels right."}}, "high"),
    (8, "beat", {"id": "briefing", "desc": "Mags hails with the job"}, "normal"),
    (20, "beat", {"id": "cargo_loaded", "desc": "Crates loaded"}, "normal"),
    (35, "comms_ask", {"station": "Port Vesper", "topic": "rumours"}, "high"),
    (70, "tick", {"minutes": 1}, "low"),
    (90, "player_damaged", {"hull_pct": 48}, "high"),
    (120, "npc_hailed", {"callsign": "CPV Diligence", "topic": "intent", "role": "patrol"}, "high"),
]


class MockLink:
    def __init__(self):
        self.t0 = time.time()
        self.run = f"mock-{int(self.t0)}"
        self.events = []
        self.next_id = 1
        self.cmd_ack = 0
        self.results = []
        self.script = list(SCRIPT)
        self.beats = {"briefing": False, "cargo_loaded": False, "inspection": False, "ambush": False}

    def _game_time(self) -> int:
        return int(time.time() - self.t0)

    def read_scenario(self) -> dict:
        now = self._game_time()
        while self.script and self.script[0][0] <= now:
            _, etype, data, pri = self.script.pop(0)
            if etype == "beat":
                self.beats[data["id"]] = True
            self.events.append({"id": self.next_id, "t": now, "type": etype, "data": data, "pri": pri})
            self.next_id += 1
        return {
            "proto": 1, "run": self.run, "seq": now, "events": self.events, "cmd_ack": self.cmd_ack,
            "results": self.results[-12:],
            "state": {
                "time": now, "objective": "Deliver the crates to Halcyon Rest.",
                "beats": [{"id": k, "desc": k, "ai": k in ("inspection", "ambush"), "fired": v} for k, v in self.beats.items()],
                "budget": {"ai_hostiles_alive": 0, "max_ai_hostiles": 5, "credits_given": 0, "credit_cap": 900},
                "player": {"callsign": "Magpie", "sector": "F5", "x": 9000, "y": -5000, "heading": 120,
                           "hull": 100 if now < 90 else 48, "hull_max": 100, "shields_up": True, "credits": 150,
                           "docked_with": None, "damaged_systems": {}, "homing": 2, "hvli": 5,
                           "nearby": [{"callsign": "CPV Diligence", "type": "Phobos M3", "faction": "Human Navy",
                                       "dist_u": 5.2, "hostile": False, "ai_spawned": True},
                                      {"callsign": "Port Vesper", "type": "Medium Station", "faction": "Independent",
                                       "dist_u": 10.4, "hostile": False, "ai_spawned": False}]},
                "campaign": {"credits": 150, "upgrades": [], "flags": {}},
            },
        }

    def write_director(self, msg: dict) -> None:
        ack = int(msg.get("event_ack") or 0)
        self.events = [e for e in self.events if e["id"] > ack]
        for cmd in msg.get("cmds") or []:
            if cmd["id"] > self.cmd_ack:
                self.cmd_ack = cmd["id"]
                ok = True
                note = "mock ok"
                if cmd["action"] == "fire_beat":
                    b = cmd["args"].get("beat")
                    if b in self.beats and not self.beats[b]:
                        self.beats[b] = True
                    else:
                        ok, note = False, "no such beat or already fired"
                self.results.append({"id": cmd["id"], "action": cmd["action"], "ok": ok, "msg": note})
                print(f"    [mock game] ran #{cmd['id']} {cmd['action']} {cmd['args']}")

    def probe(self) -> dict:
        return {"version": "mock", "json": True, "storage": True, "player_ships": 1}

    def read_campaign(self):
        return None
