"""Smoke test for ragtag scenarios against a running EmptyEpsilon server.

    python tools/smoke_test.py --ee http://127.0.0.1:8080
    python tools/smoke_test.py --ee http://127.0.0.1:8080 --playthrough

Start a ragtag scenario on the server first (httpserver=8080 in options.ini).
Stop the director before running this: both write the same mailbox key.

The default test sends every director action once and checks the game's
replies. --playthrough additionally teleports the ship through scripted beats
(currently only works for deleted Long Haul Session 1). It cheats, so only
use it on a test server.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "director"))
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
    cases = [
        ("say as station", "say", {"speaker": "Port Vesper", "text": "Smoke test: hello from the dock."}, True),
        ("say to log", "say", {"speaker": "Someone", "text": "Smoke test log line.", "channel": "log"}, True),
        ("main_screen", "main_screen", {"text": "Smoke test banner"}, True),
        ("gm_note", "gm_note", {"text": "Smoke test GM note"}, True),
        ("spawn_npc trader", "spawn_npc", {"role": "trader", "callsign": "Test Trader", "greeting": "Hi.", "distance": 5}, True),
        ("spawn_salvage", "spawn_salvage", {"credits": 25, "label": "Test pod", "distance": 3}, True),
        ("give_credits", "give_credits", {"amount": 10, "reason": "smoke test"}, True),
        ("system_glitch", "system_glitch", {"system": "impulse", "severity": 0.2, "reason": "smoke test"}, True),
        ("spawn_group light Corsairs", "spawn_group", {"faction": "Corsairs", "strength": "light", "distance": 25, "behavior": "idle", "callsign": "Test Raider"}, True),
        ("spawn cooldown enforced", "spawn_group", {"faction": "Corsairs", "strength": "scout", "distance": 25}, False),
        ("npc_order", "npc_order", {"callsign": "Test Trader", "order": "flee"}, True),
        ("scripted beat refused for model", "fire_beat", {"beat": "delivery"}, False),
        ("Hollow not spawnable by model", "spawn_group", {"faction": "Hollow", "strength": "heavy"}, False),
        ("unknown action refused", "launch_nukes", {}, False),
        ("GM-only refused for model", "rename_ship", {"name": "Hacked"}, False),
    ]
    for name, action, args, expect in cases:
        cid = b.send(action, args)
        r = b.wait_result(cid)
        if r is None:
            check(name, False, "no result")
        else:
            check(name, bool(r["ok"]) == expect, r["msg"])
    # Clean up test entities.
    b.lua('for _, o in ipairs(getObjectsInRadius(0, 0, 200000)) do local c = o:getCallSign() '
          'if c:find("^Test") then o:destroy() end end return "ok"')


def playthrough(b: Bridge) -> None:
    print("Session 1 playthrough (teleporting):")
    P = "local p = getPlayerShip(-1)\n"

    def obj(cs: str) -> str:
        return (f'local function find(cs) for _, o in ipairs(getObjectsInRadius(0, 0, 200000)) do '
                f'if o:getCallSign() == cs then return o end end end\nlocal o = find("{cs}")\n')

    def beat_fired(beat_id: str) -> bool:
        st = b.sync().get("state") or {}
        return any(x["id"] == beat_id and x["fired"] for x in st.get("beats", []))

    def wait_beat(beat_id: str, timeout: float = 40) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            if beat_fired(beat_id):
                return True
            time.sleep(1)
        return False

    check("briefing fired", wait_beat("briefing", 15))

    b.lua(P + obj("Port Vesper") + "local x, y = o:getPosition() p:setPosition(x + 1300, y) p:commandDock(o) return 'ok'")
    check("cargo_loaded after docking", wait_beat("cargo_loaded", 40))

    b.lua(P + "p:commandUndock() return 'ok'")
    time.sleep(2)
    b.lua(P + obj("CPV Diligence") + "local x, y = o:getPosition() p:setPosition(x + 5000, y) return 'ok'")
    check("inspection fallback near patrol", wait_beat("inspection", 15))

    # Ignore the hail and leave: should count as running, then escaping.
    b.lua(P + obj("CPV Diligence") + "local x, y = o:getPosition() p:setPosition(x + 16000, y + 2000) return 'ok'")
    ev = b.wait_event(lambda e: e["type"] == "choice" and e["data"].get("choice") == "run", 40)
    check("ignoring the hail counts as running", ev is not None)
    b.lua(P + obj("CPV Diligence") + "local x, y = o:getPosition() p:setPosition(x + 26000, y - 9000) return 'ok'")
    ev = b.wait_event(lambda e: e["type"] == "choice" and e["data"].get("choice") == "escaped", 20)
    check("patrol gives up when outrun", ev is not None)

    check("ambush fallback near Halcyon", wait_beat("ambush", 20))
    st = b.sync()["state"]
    raiders = [n for n in st["player"]["nearby"] if n["faction"] == "Corsairs" and n["callsign"].startswith(("Grinning", "Teeth"))]
    check("raiders spawned", len(raiders) >= 1, ", ".join(n["callsign"] for n in raiders))
    b.lua('for _, o in ipairs(getObjectsInRadius(0, 0, 200000)) do local c = o:getCallSign() '
          'if c == "Grinning Teeth" or c:find("^Teeth") then o:destroy() end end return "ok"')

    b.lua(P + obj("Halcyon Rest") + "local x, y = o:getPosition() p:setPosition(x + 1000, y) p:commandDock(o) return 'ok'")
    check("delivery on docking at Halcyon", wait_beat("delivery", 40))
    credits = b.sync()["state"]["player"]["credits"]
    check("payout received", credits >= 400, f"credits {credits}")

    b.lua(P + "p:commandUndock() return 'ok'")
    b.lua(obj("Wren's Folly") + 'o:setScanStateByFaction("Independent", "full") return "ok"')
    check("scanning the derelict reveals the core", wait_beat("folly_secret", 10))

    b.lua(P + obj("Sealed data core") + "local x, y = o:getPosition() p:setPosition(x, y) return 'ok'")
    ev = b.wait_event(lambda e: e["type"] == "pickup", 15)
    check("data core picked up", ev is not None)
    camp = json.loads(b.ee.get_key("ragtag.campaign.sandbox") or "{}")
    check("campaign flags saved", camp.get("flags", {}).get("lantern_core") is True and camp["flags"].get("ran_from_concord") is True,
          json.dumps(camp.get("flags")))


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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ee", default="http://127.0.0.1:8080")
    ap.add_argument("--playthrough", action="store_true")
    args = ap.parse_args()
    ee = EELink(args.ee)
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
    if args.playthrough:
        playthrough(b)
    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    return 0 if not FAIL else 1


if __name__ == "__main__":
    sys.exit(main())
