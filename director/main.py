"""AI director for the Long Haul EmptyEpsilon campaign.

Run on the PC with the GPU (or any PC that can reach both the model server and
the EmptyEpsilon server):

    python main.py --config config.toml          # normal
    python main.py --config config.toml --probe  # check connections and exit
    python main.py --mock --mock-llm             # no game, no model: test the console

Requires Python 3.11+ and nothing else.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import tomllib
from pathlib import Path

from brain import Director
from console import start_console
from ee_link import EELink, EEError
from llm import LLMClient, LLMError

BASE = Path(__file__).resolve().parent


class FakeLLM:
    """Canned replies so the plumbing can be tested without a model server."""
    model = "fake-llm"
    last_latency = 0.0

    def chat(self, messages):
        text = messages[-1]["content"]
        new = text.split("## What just happened")[-1]
        if "Summarise the session" in text:
            return json.dumps({"summary": ["The crew hauled cargo (fake summary)."], "npcs": {"Mags Oduya": "fixer, amused by the crew"}})
        if "npc_hailed" in new:
            cs = "CPV Diligence"
            if '"callsign":"' in new:
                cs = new.split('"callsign":"', 1)[1].split('"', 1)[0]
            return json.dumps({"intent": "Answer the hail in character.",
                               "actions": [{"action": "say", "args": {"speaker": cs, "text": "Keep your transponder on and we'll get along fine."}}]})
        if "comms_ask" in new:
            return json.dumps({"intent": "Share a rumour.", "actions": [{"action": "say", "args": {
                "speaker": "Port Vesper", "text": "Word is Grinning Teeth have been sniffing around the asteroid lane."}}]})
        if "GAME MASTER INSTRUCTION" in new:
            return json.dumps({"intent": "Follow the GM.", "actions": [{"action": "spawn_salvage", "args": {"credits": 40, "label": "Loose crate"}}]})
        return json.dumps({"intent": "Nothing needed right now.", "actions": []})


def load_config(path: Path) -> dict:
    if not path.exists():
        example = BASE / "config.example.toml"
        print(f"No config at {path}; using {example.name}. Copy it to config.toml and edit.")
        path = example
    with open(path, "rb") as f:
        return tomllib.load(f)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=str(BASE / "config.toml"))
    ap.add_argument("--probe", action="store_true", help="test connections and exit")
    ap.add_argument("--mock", action="store_true", help="use a fake game instead of EmptyEpsilon")
    ap.add_argument("--mock-llm", action="store_true", help="use canned model replies")
    args = ap.parse_args()

    cfg = load_config(Path(args.config))
    ee_cfg, llm_cfg, d_cfg = cfg.get("ee", {}), cfg.get("llm", {}), cfg.get("director", {})

    if args.mock:
        from mock_ee import MockLink
        ee = MockLink()
    else:
        ee = EELink(ee_cfg.get("url", "http://127.0.0.1:8080"), timeout=float(ee_cfg.get("timeout", 4)))

    if args.mock_llm:
        llm = FakeLLM()
    else:
        llm = LLMClient(
            base_url=llm_cfg.get("base_url", "http://127.0.0.1:11434/v1"),
            model=llm_cfg.get("model", "qwen2.5:14b-instruct"),
            api_key=llm_cfg.get("api_key", "local"),
            temperature=float(llm_cfg.get("temperature", 0.8)),
            timeout=float(llm_cfg.get("timeout", 90)),
            json_mode=bool(llm_cfg.get("json_mode", True)),
            max_tokens=int(llm_cfg.get("max_tokens", 900)),
        )

    if args.probe:
        ok = True
        try:
            info = ee.probe()
            print(f"EmptyEpsilon: reachable. {info}")
            if not info.get("json"):
                print("  WARNING: toJSON/fromJSON missing. This EmptyEpsilon build is too old for the bridge.")
                ok = False
            if not args.mock:
                msg = ee.read_scenario()
                print("  Scenario mailbox:", "active, run " + msg.get("run", "?") if msg else "empty (start a Long Haul scenario)")
        except EEError as e:
            print(f"EmptyEpsilon: NOT reachable: {e}")
            print("  Is httpserver=8080 set in options.ini on the game server, and is a scenario running?")
            ok = False
        try:
            t0 = time.time()
            reply = llm.chat([{"role": "user", "content": 'Reply with exactly this JSON: {"ok": true}'}])
            print(f"Model: reachable in {time.time() - t0:.1f}s. Reply: {reply[:80]}")
        except LLMError as e:
            print(f"Model: NOT reachable: {e}")
            ok = False
        return 0 if ok else 1

    director = Director(cfg, ee, llm, BASE)
    bind = d_cfg.get("console_bind", "0.0.0.0")
    port = int(d_cfg.get("console_port", 8765))
    start_console(director, bind, port, d_cfg.get("console_token", ""))
    print(f"GM console: http://{'localhost' if bind in ('0.0.0.0', '127.0.0.1') else bind}:{port}/")

    poll = float(ee_cfg.get("poll_seconds", 1.5))
    try:
        while True:
            t0 = time.time()
            director.poll()
            director.maybe_think()
            time.sleep(max(0.2, poll - (time.time() - t0)))
    except KeyboardInterrupt:
        print("Stopping director.")
        director.save_memory()
    return 0


if __name__ == "__main__":
    sys.exit(main())
