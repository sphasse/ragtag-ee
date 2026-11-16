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
4. Create `tests/arcs/<name>.lua` — the arc's regression test (`check.py` errors without it). See "Testing an arc" below.
5. Run `python3 tools/check.py` after any change, and `python3 tools/arc_tests.py --ee <EmptyEpsilon dir> <name>` after any change to the arc.

That's the entire integration surface. The arc is self-contained; core gameplay (jobs board, proximity spawns, reputation) keeps working while it's inactive.

---

## Use the shared helpers (ARC)

`ee/ragtag/missions/_helpers.lua` holds what every arc needs. **Read it before writing an arc**
(it is short) and use it instead of local copies; `check.py` rejects the usual re-implementations.

| Need | Helper |
|---|---|
| The player ship / is it near a point | `ARC.player()`, `ARC.playerNear(x, y, r)` |
| Distances | `ARC.dist(x1, y1, x2, y2)`, `ARC.near(ent, x, y, r)` |
| Which spawned ships are left / remove them | `ARC.alive(list)`, `ARC.kill(entity_or_table)` |
| A dialog that needs a dock | `ARC.docked(src, tgt, "message when not docked")` |
| A station hook | `ARC.stationHook(callsign, fn)` (never a `_hook_registered` boolean) |
| Meeting a character with a Science DB profile | `ARC.meet(arc_id, profile_key, "Name")` |
| Paying a reward once | `ARC.once("<arc>_rewarded", fn)` |
| `init` routing by saved flags | `ARC.route(arc_id, {{flag_or_fn, phase}, ...}, default)` |
| GM state buttons and reset | `ARC.jumper(arc_id)`, `ARC.resetState(M, st)` |

**Keep the layers apart.** `ARC` belongs to the missions layer. When two arcs need the same new
helper, add it to `_helpers.lua` (and to the table in `missions_api.md`, "Arc helpers (ARC)").
Do not add mission helpers to `core.lua` (`RT`), the job board or world plugins: core must not
know arcs exist. Going the other way is fine: arcs call `RT`, `JOBS`, `PROX`, `RUMORS`, `SCIDB`.

## What belongs in the arc module

- Phase definitions with `enter`, `update`, `exit` functions
- Trigger conditions (rep thresholds, upgrade totals, flags)
- GM buttons: `M.gm_states` (a `→` per phase and one `→ Done:` per end state; the engine adds Mission criteria, Mission state and → Inactive) and `M.gm_actions` for phase helpers
- World objects spawned in `enter`, cleaned up in `on_cancel`
- State mutations via `RT.flag`, `RT.addReputation`, `RT.addCredits`
- The arc's own achievements (`ACH.define{...}` in the arc file, not in `stats.lua`) and Science DB rules (`SCIDB.rule`)

## What does NOT belong in the arc module

- Changes to `ee/ragtag/jobs/` or the JOBS board — use a job module
- Changes to `ee/ragtag/world/` plugins — use a WORLD plugin
- Changes to `verse/drift.lua` or extensions — use a verse extension
- Logic in scenario `update()` or `init()` beyond the three MISSIONS wiring calls
- Mission-only helpers in `ee/ragtag/core.lua` — shared arc code goes in `ee/ragtag/missions/_helpers.lua` (`ARC`)

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

## Testing an arc

`tests/arcs/<name>.lua` plays the arc inside a headless EmptyEpsilon running the real sandbox
scenario (`tools/arc_tests.py`; about a minute per arc). Read `tests/arcs/_harness.lua` for the
API and copy the shape of `tests/arcs/ledger.lua`:

1. **The real path, start to finish.** `T.jump("hook")`, then drive every transition the way a
   crew would: `T.dock(station)` + `T.talk(target, {"reply label", ...})` for dialogs (real comms:
   the arc's own comms functions and station hooks run), `T.moveTo` / `T.moveNear` for proximity
   triggers, `T.waitFor(name, predicate, seconds)` for anything the phase `update` decides.
   After each transition assert the phase, the flags, what was spawned, the objective, and
   rewards (measure credits and reputation right around the paying step: flying into a new
   region pays survey credits).
2. **Every other ending** (losses, declines), by jumping back with `T.jump(key)` and playing the
   last step differently.
3. **`T.gmWalk{...}`**: every GM state in turn, with a check per state. It fails if a GM state is
   not listed, so a new state needs a test.
4. **`T.deactivate{gone = {...}}`**: "-> Inactive" leaves no flags, no named objects, no objective.

Use the arc's GM helpers (`T.action("Complete hack")`) for things a headless game cannot do
(a Relay hack, winning a fight) and move timers back (`T.st().download_start = ... - 58`) rather
than waiting them out. Docking is forced and movement is teleporting; say at the top of the
test file what it does not cover. Compare against a baseline taken before the arc starts when
counting things the universe also has (mines, Derelict wrecks).

Errors the engine catches and logs (`[MISSIONS] ... error`, non-linear transition warnings) and
any `LUA-Error` in the log fail the test, so a test that only walks the states still catches a
crash in `enter`, `gm_reset` or a `completed` hook.

## Common mistakes

- **`MISSIONS.goto()` doesn't exist** — `goto` is a Lua 5.4 reserved keyword. Use `MISSIONS.phase()`.
- **`RT.flag("x", nil)` is a no-op read** — it does not clear the flag. Use `RT.clearFlag("x")`.
- **Not cleaning up in `on_cancel`** — world objects persist across GM restarts.
- **Double-registering station hooks** — if the GM restarts the arc in the same session, hooks fire twice. Register with `ARC.stationHook(callsign, fn)`, which ignores the repeat.
- **Re-implementing a shared helper** — a local `_firstPlayer`, `_dist`, `_alive`, `_kill` or `_addRecords` in an arc. Use `ARC.*` (`check.py` errors on these).
- **Putting an arc helper in `core.lua`** — shared arc code lives in `ee/ragtag/missions/_helpers.lua`.
- **Forgetting the require** — the arc never loads and the game throws no error, but `check.py` now errors on any `ee/ragtag/missions/*.lua` not required by `missions.lua`. Intentionally unloaded arcs go in `ee/ragtag/missions/attic/`.
- **Telling Science to hack** — hacking is a **Relay** function in this engine (no hack control on Science). Say "Relay" in ship logs, comms and design docs; see `api_notes.md` §12b for the mechanics (50% per success, 180 s decay).
- **Checking a hack with `>= 1.0`** — it never fires. EE lowers every `hacked_level` by 1/180 per second in the system update, *before* the scenario script runs, so a hack that lands at 100% already reads just under 1.0 when your phase `update` checks it. Complete at **`>= 0.99`** (about a 2 s window), check every tick, and latch it (advance the phase or set a flag) rather than re-reading the level later. A GM "Complete hack" helper sets the level to 1.0 and lets the normal check fire next frame. Boneyard (Annex) and Rezkov (Galen) both do this.
- **GM button labels over 18 characters** — the GM console clips them. Keep every `M.gm_states` / `M.gm_actions` label (including function labels like a state/phase readout) to **18 characters max**; put detail in the `globalMessage` the action fires, not the label. `→ Annex control` (15) is fine; `→ Annex control (hack done)` is not. The engine truncates and logs `GM label too long` as a backstop.
- **Calling `entity:onDestruction` directly** — one callback slot per entity; a direct call clobbers reputation tracking, director kill events, and loot drops. Register via `RT.onKill(ship, fn(ship, instigator))`. It fires only on damage kills (never on scripted `destroy()`), and `instigator` tells you whether the player did it.

---

## Checklist before shipping

- [ ] The arc is linear: each phase goes to the next phase, `done`, or back to an earlier phase (no branching; see "Linear arcs" in the reference)
- [ ] Science DB entries the arc reveals follow its flags (`SCIDB.meet` for people, `SCIDB.rule` for lore/runtime entries)
- [ ] `M.on_cancel` destroys all spawned objects (`ARC.kill`)
- [ ] Uses `ARC` helpers where one exists; anything two arcs share was added to `_helpers.lua`, nothing mission-specific was added to `core.lua`
- [ ] `M.gm_reset` + `M.completed` let every `→` button land with the full context (jump through each phase and back; no leftover ships, timers, flags or state)
- [ ] `RT.after` timers cancelled with `RT.cancelTimer(name)` in `_clearState` if they shouldn't fire after phase ends
- [ ] Arc triggers use `not_flagged` to prevent re-triggering after completion
- [ ] Destruction callbacks registered via `RT.onKill`, never `entity:onDestruction`
- [ ] Every `M.gm_states` / `M.gm_actions` label is ≤ 18 characters (check function labels at their longest value)
- [ ] Hook rumors injected in `enter` / removed in `exit`, not gated on a persistent flag
- [ ] Design doc exists at `ee/ragtag/missions/<name>.md`
- [ ] `tests/arcs/<name>.lua` plays the real path, every ending, every GM state and "-> Inactive"; `tools/arc_tests.py` passes
- [ ] `python3 tools/check.py` passes
