---
name: sandbox-missions
description: Add or extend a story arc in the ragtag sandbox campaign using the MISSIONS phase-machine engine. Use for new arc modules, extending or debugging existing arcs (Witness, Rezkov), or understanding how the arc engine works. For scenario writing, job types, universe extensions, proximity spawns, or core campaign changes, use the empty-epsilon-scenarios skill instead.
---

# Adding a story arc (sandbox-missions)

**Read `references/missions_api.md` now.** It is the authoritative reference.
**Note**: this file is also kept in `.claude/skills/empty-epsilon-scenarios/references/missions_api.md` — update both when it changes (`check.py` errors if the two copies differ).
The reference implementation is `ee/ragtag/missions/rezkov.lua`; design notes live in `ee/ragtag/missions/rezkov.md`.

---

## Quick start

1. Create `ee/ragtag/missions/<name>.lua`.
2. Create `ee/ragtag/missions/<name>.md` — design notes, state diagram, lore. Arc-specific details go here; don't add them to CLAUDE.md.
3. Add `require("ragtag/missions/<name>.lua")` to `ee/ragtag/missions.lua`.
4. Run `python3 tools/check.py` after any change.

That's the entire integration surface. The arc is self-contained; core gameplay (jobs board, proximity spawns, reputation) keeps working while it's inactive.

---

## What belongs in the arc module

- Phase definitions with `enter`, `update`, `exit` functions
- Trigger conditions (rep thresholds, upgrade totals, flags)
- GM buttons: `M.gm_states` (a `→` per phase and one `→ Done:` per end state; the engine adds Mission criteria, Mission state and → Inactive) and `M.gm_actions` for phase helpers
- World objects spawned in `enter`, cleaned up in `on_cancel`
- State mutations via `RT.flag`, `RT.addReputation`, `RT.addCredits`

## What does NOT belong in the arc module

- Changes to `ee/ragtag/jobs/` or the JOBS board — use a job module
- Changes to `ee/ragtag/world/` plugins — use a WORLD plugin
- Changes to `verse/drift.lua` or extensions — use a verse extension
- Logic in scenario `update()` or `init()` beyond the three MISSIONS wiring calls

---

## Interaction with other layers

- **Suspend the job board** while the arc is active: set `M.locks_jobs = true`.
- **Disable / Enable arc**: every arc gets this GM button automatically (arc detail screen, while waiting for its trigger). It calls `MISSIONS.setEnabled(id, bool)`: a disabled arc ignores triggers and runs `M.on_unload`. You get it for free, so don't add your own; pair it with `M.on_load`/`M.on_unload` for anything the waiting arc sets up (seed rumors).
- **Seed rumors while waiting**: add `M.on_load` (idempotent: `RUMORS.removeCategory` first, then `RUMORS.add{priority=3, category="X_SEED"}`) and `M.on_unload` (remove the category). Seeds are priority 3 (slightly favoured over the pool); the actionable hook lines stay priority 5. See `references/missions_api.md` → Rumor tiers.
- **Seed jobs on the station boards**: `JOBS.inject{category, priority 3|5, origin, when, record}` from `M.on_load` (priority-3 filler deliveries) and the hook phase (one priority-5 `story = true` contract, e.g. a special salvage job whose `on_found` reveals the lead). Remove by category in `on_unload`/`exit`/`_clearState`. See `references/missions_api.md` → "Seeding jobs from an arc" and `jobs_api.md` → "Injected jobs".
- **Add a rumor as an arc hook**: inject in the hook phase's `enter` (call `RUMORS.removeCategory` first so GM re-entry doesn't duplicate), remove the category in `exit` and in `_clearState`. Do NOT gate injection on a persistent `RT.flag` — injected rumors reset every session, so a persistent "already injected" flag silently kills the hook in session 2.
- **Proximity spawn suspension**: call `PROX.suspendZone("zone name")` to block new spawns in a region while your arc controls it, and `PROX.resumeZone("zone name")` in both `M.resolve` and `M.on_cancel`. Zone names match the keys in `PROX.zones`. Call suspend again in any GM skip action that jumps to a post-suspend phase.
- **Cross-session state**: `RT.flag(name, true)` to persist, `RT.clearFlag(name)` to clear. Never use `RT.flag(name, nil)` to clear — that is a read, not a write.

---

## Common mistakes

- **`MISSIONS.goto()` doesn't exist** — `goto` is a Lua 5.4 reserved keyword. Use `MISSIONS.phase()`.
- **`RT.flag("x", nil)` is a no-op read** — it does not clear the flag. Use `RT.clearFlag("x")`.
- **Not cleaning up in `on_cancel`** — world objects persist across GM restarts.
- **Double-registering station hooks** — if the GM restarts the arc in the same session, hooks fire twice. Guard with a file-level `_hook_registered` boolean.
- **Forgetting the require** — the arc never loads and the game throws no error, but `check.py` now errors on any `ee/ragtag/missions/*.lua` not required by `missions.lua`. Intentionally unloaded arcs go in `ee/ragtag/missions/attic/`.
- **Telling Science to hack** — hacking is a **Relay** function in this engine (no hack control on Science). Say "Relay" in ship logs, comms and design docs; see `api_notes.md` §12b for the mechanics (50% per success, 180 s decay).
- **GM button labels over 18 characters** — the GM console clips them. Keep every `M.gm_states` / `M.gm_actions` label (including function labels like a state/phase readout) to **18 characters max**; put detail in the `globalMessage` the action fires, not the label. `→ Annex control` (15) is fine; `→ Annex control (hack done)` is not. The engine truncates and logs `GM label too long` as a backstop.
- **Calling `entity:onDestruction` directly** — one callback slot per entity; a direct call clobbers reputation tracking, director kill events, and loot drops. Register via `RT.onKill(ship, fn(ship, instigator))`. It fires only on damage kills (never on scripted `destroy()`), and `instigator` tells you whether the player did it.

---

## Checklist before shipping

- [ ] The arc is linear: each phase goes to the next phase, `done`, or back to an earlier phase (no branching; see "Linear arcs" in the reference)
- [ ] `M.on_cancel` destroys all spawned objects
- [ ] `M.gm_reset` + `M.completed` let every `→` button land with the full context (jump through each phase and back; no leftover ships, timers, flags or state)
- [ ] `RT.after` timers cancelled with `RT.cancelTimer(name)` in `_clearState` if they shouldn't fire after phase ends
- [ ] Arc triggers use `not_flagged` to prevent re-triggering after completion
- [ ] Destruction callbacks registered via `RT.onKill`, never `entity:onDestruction`
- [ ] Every `M.gm_states` / `M.gm_actions` label is ≤ 18 characters (check function labels at their longest value)
- [ ] Hook rumors injected in `enter` / removed in `exit`, not gated on a persistent flag
- [ ] Design doc exists at `ee/ragtag/missions/<name>.md`
- [ ] `python3 tools/check.py` passes
