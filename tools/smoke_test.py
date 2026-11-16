"""Smoke test for ragtag scenarios against a running EmptyEpsilon server.

    python tools/smoke_test.py --ee http://127.0.0.1:8080

Start a ragtag scenario on the server first (httpserver=8080 in options.ini).
Stop the director before running this: both write the same mailbox key.

It checks the universe was built and sends every director action once, checking
the game's replies. Story arcs have their own tests: tools/game_tests.py.
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
        ("say as station hail",   "say",      {"speaker": "Port Vesper", "text": "Smoke test: hello from the dock."}, True),
        ("say to log",            "say",      {"speaker": "Someone", "text": "Smoke test log line.", "channel": "log"}, True),
        ("gm_note",               "gm_note",  {"text": "Smoke test GM note"}, True),
        ("noop",                  "noop",     {}, True),
        ("unknown action refused","launch_nukes", {}, False),
        ("GM-only refused for model", "rename_ship", {"name": "Hacked"}, False),
    ]
    for name, action, args, expect in cases:
        cid = b.send(action, args)
        r = b.wait_result(cid)
        if r is None:
            check(name, False, "no result")
        else:
            check(name, bool(r["ok"]) == expect, r["msg"])


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
    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    return 0 if not FAIL else 1


if __name__ == "__main__":
    sys.exit(main())
