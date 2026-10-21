"""The AI director: syncs with the scenario mailbox, decides when to ask the
model for a move, validates its answer, and keeps campaign memory."""

from __future__ import annotations

import collections
import json
import threading
import time
from pathlib import Path
from typing import Any

import actions as act
from ee_link import EELink, EEError
from llm import LLMClient, LLMError, parse_json_reply

PROTO = 1


def _fmt_time(seconds: Any) -> str:
    try:
        s = int(seconds)
    except (TypeError, ValueError):
        return "--:--"
    return f"{s // 60:02d}:{s % 60:02d}"


def _compact(obj: Any, limit: int = 300) -> str:
    s = json.dumps(obj, separators=(",", ":"), ensure_ascii=False)
    return s if len(s) <= limit else s[: limit - 3] + "..."


class Director:
    def __init__(self, cfg: dict, ee: EELink, llm: LLMClient, base_dir: Path):
        self.cfg = cfg
        dcfg = cfg.get("director", {})
        self.ee = ee
        self.llm = llm
        self.base_dir = base_dir
        self.lock = threading.RLock()

        self.mode = dcfg.get("mode", "auto")                 # auto | approve
        self.paused = False
        self.min_gap_high = float(dcfg.get("min_seconds_between_urgent_calls", 4))
        self.min_gap_normal = float(dcfg.get("min_seconds_between_calls", 20))
        self.max_actions_per_reply = int(dcfg.get("max_actions_per_reply", 4))
        self.max_actions_per_minute = int(dcfg.get("max_actions_per_minute", 8))
        self.react_to_ticks = bool(dcfg.get("react_to_ticks", True))

        prompt_path = base_dir / dcfg.get("system_prompt", "prompts/system.md")
        self.system_template = prompt_path.read_text(encoding="utf-8")
        bible_path = base_dir / dcfg.get("campaign_bible", "campaign_bible.md")
        self.bible = bible_path.read_text(encoding="utf-8") if bible_path.exists() else ""
        self.memory_path = base_dir / dcfg.get("memory_file", "director_memory.json")
        self.memory = self._load_memory()

        # Mailbox state
        self.run: str | None = None
        self.hb = 0
        self.event_ack = 0
        self.next_cmd_id = 1
        self.outgoing: list[dict] = []
        self.cmd_ack = 0
        self.seen_results: set = set()
        self.state: dict = {}
        self.session: dict = {}
        self.ee_online = False
        self.last_ee_error = ""
        self.last_scenario_seq = None

        # Thinking state
        self.history: collections.deque = collections.deque(maxlen=40)   # events for context
        self.pending: list[dict] = []                                    # events not yet shown to the model
        self.gm_prompts: list[str] = []
        self.recent_results: collections.deque = collections.deque(maxlen=10)
        self.recent_own: collections.deque = collections.deque(maxlen=10)
        self.rejections: collections.deque = collections.deque(maxlen=6)
        self.action_times: collections.deque = collections.deque(maxlen=50)
        self.busy = False
        self.last_call = 0.0
        self.last_intent = ""
        self.approvals: list[dict] = []
        self.next_approval_id = 1

        self.log: collections.deque = collections.deque(maxlen=400)
        self._log("info", f"Director ready. Mode={self.mode}. Model={llm.model}.")

    # ------------------------------------------------------------------ memory

    def _load_memory(self) -> dict:
        base = {"campaign_log": [], "npcs": {}, "notes": [], "directives": "", "campaign_mirror": None}
        if self.memory_path.exists():
            try:
                data = json.loads(self.memory_path.read_text(encoding="utf-8"))
                base.update(data)
            except ValueError:
                pass
        return base

    def save_memory(self) -> None:
        tmp = self.memory_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.memory, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp.replace(self.memory_path)

    # --------------------------------------------------------------------- log

    def _log(self, kind: str, text: str) -> None:
        with self.lock:
            self.log.append({"t": time.strftime("%H:%M:%S"), "kind": kind, "text": text})
        print(f"[{kind}] {text}", flush=True)

    # ----------------------------------------------------------------- mailbox

    def poll(self) -> None:
        """One sync cycle with the game. Call every ~1.5 s."""
        try:
            msg = self.ee.read_scenario()
            if not self.ee_online:
                self._log("info", "Connected to EmptyEpsilon.")
            self.ee_online = True
            self.last_ee_error = ""
        except EEError as e:
            if self.ee_online or self.last_ee_error != str(e):
                self._log("error", str(e))
            self.ee_online = False
            self.last_ee_error = str(e)
            return

        if not msg or msg.get("proto") != PROTO:
            return

        with self.lock:
            if msg.get("run") != self.run:
                self._new_run(msg.get("run"))

            for ev in msg.get("events") or []:
                if not isinstance(ev, dict):
                    continue
                eid = int(ev.get("id", 0))
                if eid <= self.event_ack:
                    continue
                self.event_ack = eid
                self._on_event(ev)

            self.cmd_ack = int(msg.get("cmd_ack") or 0)
            self.outgoing = [c for c in self.outgoing if c["id"] > self.cmd_ack]
            for r in msg.get("results") or []:
                if not isinstance(r, dict):
                    continue
                key = (self.run, r.get("id"))
                if key in self.seen_results:
                    continue
                self.seen_results.add(key)
                status = "ok" if r.get("ok") else "FAILED"
                self.recent_results.append(f"#{r.get('id')} {r.get('action')} {status}: {r.get('msg')}")
                self._log("result", f"#{r.get('id')} {r.get('action')} {status}: {r.get('msg')}")

            if isinstance(msg.get("state"), dict):
                self.state = msg["state"]
                camp = self.state.get("campaign")
                if isinstance(camp, dict) and camp != self.memory.get("campaign_mirror"):
                    self.memory["campaign_mirror"] = camp
                    self.save_memory()

            self.hb += 1
            out = {"proto": PROTO, "run": self.run, "hb": self.hb, "event_ack": self.event_ack,
                   "paused": self.paused, "cmds": list(self.outgoing)}
        try:
            self.ee.write_director(out)
        except EEError as e:
            self._log("error", f"write failed: {e}")

    def _new_run(self, run: str | None) -> None:
        self.run = run
        self.event_ack = 0
        self.next_cmd_id = 1
        self.outgoing = []
        self.cmd_ack = 0
        self.pending = []
        self.history.clear()
        self.recent_results.clear()
        self.recent_own.clear()
        self.approvals = []
        self._log("info", f"New scenario run detected: {run}")

    def _on_event(self, ev: dict) -> None:
        etype = ev.get("type")
        if etype == "session_start":
            self.session = (ev.get("data") or {}).get("session") or {}
        self.history.append(ev)
        self.pending.append(ev)
        self._log("event", f"[{_fmt_time(ev.get('t'))}] {etype} {_compact(ev.get('data'), 200)}")
        if etype == "session_end":
            threading.Thread(target=self._summarise_session, args=(ev,), daemon=True).start()

    # ----------------------------------------------------------------- actions

    def queue_action(self, action: str, args: dict, source: str, intent: str = "") -> tuple[bool, str]:
        ok, cleaned, note = act.validate(action, args, from_llm=(source == "llm"))
        if not ok:
            return False, note
        with self.lock:
            if self.run is None:
                return False, "no scenario running"
            if source == "llm" and self.mode == "approve":
                self.approvals.append({"id": self.next_approval_id, "action": action, "args": cleaned,
                                       "intent": intent, "t": time.strftime("%H:%M:%S")})
                self.next_approval_id += 1
                return True, "awaiting GM approval" + note
            cmd = {"id": self.next_cmd_id, "action": action, "args": cleaned, "source": source}
            self.next_cmd_id += 1
            self.outgoing.append(cmd)
            self.action_times.append(time.time())
            if source == "llm":
                self.recent_own.append(f"{action} {_compact(cleaned, 160)}")
        self._log("action", f"#{cmd['id']} ({source}) {action} {_compact(cleaned, 240)}")
        return True, "queued" + note

    def approve(self, approval_id: int) -> tuple[bool, str]:
        with self.lock:
            item = next((a for a in self.approvals if a["id"] == approval_id), None)
            if not item:
                return False, "not found"
            self.approvals.remove(item)
        ok, cleaned, note = act.validate(item["action"], item["args"], from_llm=True)
        if not ok:
            return False, note
        with self.lock:
            cmd = {"id": self.next_cmd_id, "action": item["action"], "args": cleaned, "source": "llm"}
            self.next_cmd_id += 1
            self.outgoing.append(cmd)
            self.recent_own.append(f"{item['action']} {_compact(cleaned, 160)}")
        self._log("action", f"#{cmd['id']} (approved) {item['action']} {_compact(cleaned, 240)}")
        return True, "approved"

    def reject(self, approval_id: int) -> tuple[bool, str]:
        with self.lock:
            item = next((a for a in self.approvals if a["id"] == approval_id), None)
            if not item:
                return False, "not found"
            self.approvals.remove(item)
            self.rejections.append(f"GM rejected: {item['action']} {_compact(item['args'], 120)}")
        return True, "rejected"

    # -------------------------------------------------------------- GM inputs

    def gm_prompt(self, text: str) -> None:
        text = text.strip()
        if not text:
            return
        with self.lock:
            self.gm_prompts.append(text)
        self._log("gm", f"Instruction: {text}")

    def set_directives(self, text: str) -> None:
        with self.lock:
            self.memory["directives"] = text.strip()
            self.save_memory()
        self._log("gm", "Standing directives updated.")

    # ---------------------------------------------------------------- thinking

    def maybe_think(self) -> None:
        with self.lock:
            if self.busy or self.paused or self.run is None or not self.ee_online:
                return
            now = time.time()
            since = now - self.last_call
            has_gm = bool(self.gm_prompts)
            high = [e for e in self.pending if e.get("pri") == "high" and e.get("type") != "session_end"]
            normal = [e for e in self.pending if e.get("pri") == "normal"]
            ticks = [e for e in self.pending if e.get("type") == "tick"]
            go = False
            if has_gm or (high and since >= self.min_gap_high):
                go = True
            elif normal and since >= self.min_gap_normal:
                go = True
            elif ticks and self.react_to_ticks and since >= 60:
                go = True
            if not go:
                return
            if self._actions_last_minute() >= self.max_actions_per_minute and not has_gm:
                return
            trigger = list(self.pending)
            self.pending = []
            gm = list(self.gm_prompts)
            self.gm_prompts = []
            self.busy = True
            self.last_call = now
        threading.Thread(target=self._think, args=(trigger, gm), daemon=True).start()

    def _actions_last_minute(self) -> int:
        cutoff = time.time() - 60
        return sum(1 for t in self.action_times if t > cutoff)

    def _system_prompt(self) -> str:
        mem = self.memory
        camp_log = "\n".join(f"- {line}" for s in mem.get("campaign_log", [])[-5:] for line in s.get("summary", [])) or "(no earlier sessions recorded)"
        npcs = "\n".join(f"- {k}: {v}" for k, v in list(mem.get("npcs", {}).items())[-20:]) or "(none yet)"
        notes = "\n".join(f"- {n}" for n in mem.get("notes", [])[-10:]) or "(none)"
        return (self.system_template
                .replace("{{ACTIONS}}", act.catalog_for_prompt())
                .replace("{{BIBLE}}", self.bible.strip() or "(no campaign bible provided)")
                .replace("{{CAMPAIGN_LOG}}", camp_log)
                .replace("{{NPCS}}", npcs)
                .replace("{{NOTES}}", notes)
                .replace("{{DIRECTIVES}}", mem.get("directives") or "(none)")
                .replace("{{MAX_ACTIONS}}", str(self.max_actions_per_reply)))

    def _situation(self, trigger: list[dict], gm: list[str]) -> str:
        st = self.state or {}
        ses = self.session or {}
        lines = []
        if ses:
            lines.append(f"## Session: {ses.get('title', '?')} ({ses.get('id', '?')})")
            lines.append(f"Premise: {ses.get('premise', '')}")
            if ses.get("tone"):
                lines.append(f"Tone: {ses['tone']}")
            for c in ses.get("cast") or []:
                lines.append(f"- Cast: {c.get('name')} ({c.get('where', '')}) - {c.get('role', '')}; voice: {c.get('voice', '')}")
            for loc in ses.get("locations") or []:
                lines.append(f"- Place: {loc.get('name')} - {loc.get('note', '')}")
            if ses.get("director_guidance"):
                lines.append(f"Scenario guidance for you: {ses['director_guidance']}")
        lines.append("")
        lines.append(f"## Current state (game time {_fmt_time(st.get('time'))})")
        lines.append(f"Objective: {st.get('objective') or '(none)'}")
        p = st.get("player") or {}
        if p.get("destroyed"):
            lines.append("The crew's ship has been destroyed.")
        elif p:
            lines.append(
                f"Ship {p.get('callsign')}: hull {p.get('hull')}/{p.get('hull_max')}, shields {'up' if p.get('shields_up') else 'down'}, "
                f"credits {p.get('credits')}, sector {p.get('sector')}, docked with {p.get('docked_with') or 'nothing'}, "
                f"missiles homing {p.get('homing')} / hvli {p.get('hvli')}")
            dmg = p.get("damaged_systems") or {}
            if dmg:
                lines.append("Damaged systems (% health): " + ", ".join(f"{k} {v}" for k, v in dmg.items()))
            near = p.get("nearby") or []
            if near:
                lines.append("Nearby (within 30u):")
                for n in near[:12]:
                    tag = " HOSTILE" if n.get("hostile") else ""
                    tag += " [yours to control]" if n.get("ai_spawned") is True else ""
                    lines.append(f"  - {n.get('callsign')} ({n.get('faction')} {n.get('type')}, {n.get('dist_u')}u){tag}")
        beats = st.get("beats") or []
        if beats:
            lines.append("Story beats:")
            for b in beats:
                mark = "x" if b.get("fired") else " "
                who = " (you may fire this)" if b.get("ai") and not b.get("fired") else ""
                lines.append(f"  [{mark}] {b.get('id')}: {b.get('desc')}{who}")
        bud = st.get("budget") or {}
        if bud:
            lines.append(f"Budget: your hostiles alive {bud.get('ai_hostiles_alive')}/{bud.get('max_ai_hostiles')}, "
                         f"credits you've given {bud.get('credits_given')}/{bud.get('credit_cap')}")
        if st.get("extra"):
            lines.append(f"Scenario details: {_compact(st['extra'], 400)}")
        camp = st.get("campaign") or {}
        if camp:
            flags = camp.get("flags") or {}
            lines.append(f"Campaign: upgrades {camp.get('upgrades') or []}; story flags {_compact(flags, 300)}")
        if st.get("paused"):
            lines.append("NOTE: the GM has paused you in-game; only gm_note will be accepted.")

        lines.append("")
        trigger_ids = {e.get("id") for e in trigger}
        older = [e for e in self.history if e.get("id") not in trigger_ids and e.get("type") != "session_start"][-15:]
        if older:
            lines.append("## Earlier this session (oldest first)")
            for e in older:
                lines.append(f"- [{_fmt_time(e.get('t'))}] {e.get('type')}: {_compact(e.get('data'), 220)}")
        if self.recent_own:
            lines.append("## Your recent actions")
            lines.extend(f"- {a}" for a in self.recent_own)
        if self.recent_results:
            lines.append("## Results reported by the game")
            lines.extend(f"- {r}" for r in self.recent_results)
        if self.rejections:
            lines.append("## Problems with your earlier output")
            lines.extend(f"- {r}" for r in self.rejections)
        lines.append("")
        lines.append("## What just happened (respond to this)")
        if trigger:
            for e in trigger:
                if e.get("type") == "session_start":
                    lines.append(f"- [{_fmt_time(e.get('t'))}] session_start: the session has just begun.")
                else:
                    lines.append(f"- [{_fmt_time(e.get('t'))}] {e.get('type')}: {_compact(e.get('data'), 300)}")
        else:
            lines.append("- (nothing new)")
        for g in gm:
            lines.append(f"- GAME MASTER INSTRUCTION (follow it, within the rules): {g}")
        lines.append("")
        lines.append('Reply with one JSON object: {"intent": "...", "actions": [...], "remember": "optional"}')
        return "\n".join(lines)

    def _think(self, trigger: list[dict], gm: list[str]) -> None:
        try:
            messages = [
                {"role": "system", "content": self._system_prompt()},
                {"role": "user", "content": self._situation(trigger, gm)},
            ]
            raw = self.llm.chat(messages)
            try:
                reply = parse_json_reply(raw)
            except ValueError:
                self._log("error", f"Model reply was not JSON: {raw[:200]}")
                with self.lock:
                    self.rejections.append("Your last reply was not valid JSON. Reply with JSON only.")
                return
            intent = str(reply.get("intent", ""))[:300]
            self.last_intent = intent
            self._log("think", f"({self.llm.last_latency:.1f}s) {intent}")
            acts = reply.get("actions") or []
            if not isinstance(acts, list):
                acts = []
            with self.lock:
                self.rejections.clear()
            for item in acts[: self.max_actions_per_reply]:
                if not isinstance(item, dict):
                    continue
                name = str(item.get("action", ""))
                if name == "noop":
                    continue
                ok, msg = self.queue_action(name, item.get("args") or {}, "llm", intent)
                if not ok:
                    self._log("reject", f"{name}: {msg}")
                    with self.lock:
                        self.rejections.append(f"{name} {_compact(item.get('args'), 120)} rejected: {msg}")
            if len(acts) > self.max_actions_per_reply:
                with self.lock:
                    self.rejections.append(f"Only the first {self.max_actions_per_reply} actions were used.")
            remember = reply.get("remember")
            if isinstance(remember, str) and remember.strip():
                with self.lock:
                    self.memory["notes"].append(remember.strip()[:240])
                    self.memory["notes"] = self.memory["notes"][-40:]
                    self.save_memory()
        except LLMError as e:
            self._log("error", f"Model call failed: {e}")
            with self.lock:
                # Put high-priority events back so they are not lost.
                self.pending = [e2 for e2 in trigger if e2.get("pri") == "high"] + self.pending
                self.gm_prompts = gm + self.gm_prompts
        finally:
            with self.lock:
                self.busy = False

    def _summarise_session(self, ev: dict) -> None:
        data = ev.get("data") or {}
        sid = data.get("session") or self.session.get("id") or "?"
        hist = "\n".join(f"- [{_fmt_time(e.get('t'))}] {e.get('type')}: {_compact(e.get('data'), 200)}" for e in self.history)
        prompt = (
            "You are the chronicler of a space-western campaign. Summarise the session below for the campaign log.\n"
            f"Session {sid}: {self.session.get('title', '')}. Outcome: {data.get('outcome')}. {data.get('note', '')}\n"
            f"Final flags: {_compact(data.get('flags'), 400)}\n\nEvents:\n{hist}\n\n"
            'Reply with JSON: {"summary": ["3-6 short past-tense bullet points about what the crew did and chose"], '
            '"npcs": {"Name": "one line: who they are and how they feel about the crew"}}'
        )
        try:
            raw = self.llm.chat([{"role": "user", "content": prompt}])
            reply = parse_json_reply(raw)
        except (LLMError, ValueError) as e:
            self._log("error", f"Session summary failed: {e}")
            reply = {"summary": [f"Session {sid} ended: {data.get('outcome')} - {data.get('note', '')}"], "npcs": {}}
        with self.lock:
            summary = [str(s)[:200] for s in (reply.get("summary") or [])][:8]
            self.memory["campaign_log"] = [s for s in self.memory["campaign_log"] if s.get("session") != sid]
            self.memory["campaign_log"].append({"session": sid, "title": self.session.get("title"), "summary": summary,
                                                "outcome": data.get("outcome")})
            npcs = reply.get("npcs") or {}
            if isinstance(npcs, dict):
                for k, v in list(npcs.items())[:12]:
                    self.memory["npcs"][str(k)[:40]] = str(v)[:200]
            self.save_memory()
        self._log("info", f"Session {sid} summarised into campaign memory.")

    # ------------------------------------------------------------------ status

    def status(self) -> dict:
        with self.lock:
            return {
                "ee_online": self.ee_online, "ee_error": self.last_ee_error, "run": self.run,
                "busy": self.busy, "mode": self.mode, "paused": self.paused, "model": self.llm.model,
                "last_intent": self.last_intent, "session": self.session, "state": self.state,
                "approvals": list(self.approvals), "outgoing": list(self.outgoing),
                "log": list(self.log)[-150:], "directives": self.memory.get("directives", ""),
                "campaign_log": self.memory.get("campaign_log", []), "npcs": self.memory.get("npcs", {}),
                "pending_events": len(self.pending),
                "actions": {k: {"help": a.help, "llm": a.llm_allowed, "args": {n: {"type": g.type, "required": g.required, "choices": g.choices} for n, g in a.args.items()}}
                            for k, a in act.ACTIONS.items()},
            }
