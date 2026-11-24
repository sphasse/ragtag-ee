---
name: sandbox-missions
description: Add or extend a story arc in the ragtag sandbox campaign using the MISSIONS phase-machine engine. Use for new arc modules, extending or debugging existing arcs (Witness, Rezkov), or understanding how the arc engine works, and for set-piece battles between groups of NPC ships (BATTLE, the Battle Lab). For scenario writing, job types, universe extensions, proximity spawns, or core campaign changes, use the empty-epsilon-scenarios skill instead.
---

# Adding a story arc (sandbox-missions)

**Read `references/missions_api.md` now.** It is the authoritative reference.
**Note**: this file is also kept in `.claude/skills/empty-epsilon-scenarios/references/missions_api.md` — update both when it changes (`check.py` errors if the two copies differ).
The reference implementation is `ee/ragtag/missions/rezkov.lua`; its GM guide is `docs/GM_REZKOV_MISSION.md`.

---

## Quick start

1. Create `ee/ragtag/missions/<name>.lua`.
2. Create `docs/GM_<NAME>_MISSION.md`, the arc's GM guide, from `references/gm_guide_template.md`. See "The arc's GM guide" below.
3. Add `require("ragtag/missions/<name>.lua")` to `ee/ragtag/missions.lua`.
4. Create `tests/arcs/<name>.lua` — the arc's regression test (`check.py` errors without it). See "Testing an arc" below.
5. Run `python3 tools/check.py` after any change, and `python3 tools/game_tests.py --ee <EmptyEpsilon dir> <name>` after any change to the arc.

That's the entire integration surface. The arc is self-contained; core gameplay (jobs board, proximity spawns, reputation) keeps working while it's inactive.

---

## The arc's GM guide

Every arc has one GM guide, `docs/GM_<NAME>_MISSION.md` (e.g. `GM_REZKOV_MISSION.md`), started from
`references/gm_guide_template.md`. It is written for a GM running a session, and it is where arc-specific detail lives
(not CLAUDE.md, not `missions_api.md`). Sections, in this order:

1. **Premise**: one paragraph of story, then "Where it sits in the campaign": bullets on which thread the arc is,
   who it introduces and what they do later, what it does to the factions and which later arcs or options that sets up
   (e.g. "The Concord's losses set up its further destabilization; the friendly Corsairs open options for future Corsair
   stories; Reva is introduced"). Name the later arcs and flags. Take the big picture from `scenarios/sandbox/plan.md`.
2. **Triggers**: every start condition in GM words, how it starts, and what is seeded while it waits.
3. **Phases**: the phase diagram, then a `###` per phase named as the GM screen shows it: what the crew sees and does,
   the choices (bold reply text → result), where, and how it can fail.
4. **GM console**: every `M.gm_states` button and `M.gm_actions` helper (and its phase), and what a jump resets.
5. **Exports**: the flags other arcs read (and who reads them), rewards, Science DB entries.
6. **Design notes**: last. State, saved flags, engine workarounds, tuning constants, rumor/job categories, history
   (what a playtest changed and why), open playtest questions, testing.

Write the GM sections from the code (button labels, numbers, quoted lines), not from memory or the plan.
Add the arc to the story-arc table in `docs/GM_GUIDE.md` (with a link to its guide), and point its row in
`scenarios/sandbox/plan.md` and the module's header comment at the guide.

**Keep it current.** Any change to an arc's behaviour, text, numbers, buttons or flags updates its GM guide in the same
commit; a playtest fix also gets a line under Design notes → History.

---

## Use the shared helpers (ARC)

`ee/ragtag/missions/_helpers.lua` holds what every arc needs. **Read it before writing an arc**
(it is short) and use it instead of local copies; `check.py` rejects the usual re-implementations.

| Need | Helper |
|---|---|
| The player ship / is it near a point | `ARC.player()`, `ARC.playerNear(x, y, r)` |
| Do something to the ship / log / hail | `ARC.withPlayer(fn)`, `ARC.log(msg, color)`, `ARC.hail(from, text, speaker)` |
| A comms function with choices | `ship:setCommsFunction(ARC.comms(fn, "line for other ships"))` |
| Distances | `ARC.dist(x1, y1, x2, y2)`, `ARC.near(ent, x, y, r)` |
| Which spawned ships are left / remove them | `ARC.alive(list)`, `ARC.kill(entity_or_table)` |
| A dialog that needs a dock | `ARC.docked(src, tgt, "message when not docked")` |
| A station hook | `ARC.stationHook(callsign, fn)` (never a `_hook_registered` boolean) |
| Meeting a character with a Science DB profile | `ARC.meet(arc_id, profile_key, "Name")` |
| Paying a reward once | `ARC.once("<arc>_rewarded", fn)` |
| `init` routing by saved flags | `ARC.route(arc_id, {{flag_or_fn, phase}, ...}, default)` |
| GM state buttons and reset | `ARC.jumper(arc_id)`, `ARC.resetState(M, st)` |
| GM travel shortcut ("Ship → Hob's") | `ARC.travel(label, phases, target)` in `M.gm_actions` (uses `ARC.shipTo`) |

**One ship.** Arcs belong to the campaign's primary ship (the Magpie). Other player ships can be
in the game working the job board, and an arc must not react to them. So arcs never use
`RT.players`, `RT.forEachPlayer`, `RT.shipLog` or `RT.hail` (`check.py` rejects them): `ARC.player()`
is the arc ship, `ARC.log` / `ARC.hail` reach only it, and `ARC.comms`, `ARC.docked` and
`ARC.stationHook` keep arc dialogs away from other ships.

**Keep the layers apart.** `ARC` belongs to the missions layer. When two arcs need the same new
helper, add it to `_helpers.lua` (and to the table in `missions_api.md`, "Arc helpers (ARC)").
Do not add mission helpers to `core.lua` (`RT`), the job board or world plugins: core must not
know arcs exist. Going the other way is fine: arcs call `RT`, `JOBS`, `PROX`, `RUMORS`, `SCIDB`.

## Declare the arc's flags

Every saved flag the arc sets goes in `M.flags = {name = "meaning", ...}`; other arcs' flags it
reads go in `M.reads = {...}`. `check.py` rejects any `RT.flag` name that is not declared (a typo
is an error instead of a silent no-op), a write to another arc's flag, and an unused declaration;
the arc tests reject undeclared flags written at run time. Flag names start with the arc's
prefix (`<id>_`). Details: `missions_api.md`, "Flags".

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
- **Disable / Enable arc**: every arc gets this GM button automatically (arc detail screen, whenever the arc is not running, finished arcs included). It calls `MISSIONS.gmToggleEnabled(id)`: the arc is first reset to "never happened" (`MISSIONS.gmResetArc`: `M.gm_reset`, every flag of the arc cleared, its done flag included, a fresh state table), then enabled or disabled; a disabled arc ignores triggers and runs `M.on_unload`. Every arc test checks this (`T.deactivate`). You get it for free, so don't add your own; pair it with `M.on_load`/`M.on_unload` for anything the waiting arc sets up (seed rumors).
- **Seed rumors while waiting**: add `M.on_load` (idempotent: `RUMORS.removeCategory` first, then `RUMORS.add{priority=3, category="X_SEED"}`) and `M.on_unload` (remove the category). Seeds are priority 3 (slightly favoured over the pool); the actionable hook lines stay priority 5. See `references/missions_api.md` → Rumor tiers.
- **Seed jobs on the station boards**: `JOBS.inject{category, priority 3|5, origin, when, record}` from `M.on_load` (priority-3 filler deliveries) and the hook phase (one priority-5 `story = true` contract, e.g. a special salvage job whose `on_found` reveals the lead). Remove by category in `on_unload`/`exit`/`_clearState`. See `references/missions_api.md` → "Seeding jobs from an arc" and `jobs_api.md` → "Injected jobs".
- **Add a rumor as an arc hook**: inject in the hook phase's `enter` (call `RUMORS.removeCategory` first so GM re-entry doesn't duplicate), remove the category in `exit` and in `_clearState`. Do NOT gate injection on a persistent `RT.flag` — injected rumors reset every session, so a persistent "already injected" flag silently kills the hook in session 2.
- **Proximity spawn suspension**: call `PROX.suspendZone("zone name")` to block new spawns in a region while your arc controls it, and `PROX.resumeZone("zone name")` in both `M.resolve` and `M.on_cancel`. Zone names match the keys in `PROX.zones`. Call suspend again in any GM skip action that jumps to a post-suspend phase.
- **Battles between groups of ships** (a fleet against the crew's allies, a set piece): use `BATTLE` (`ee/ragtag/battle.lua`): combat points, normalized speeds, no warp, retargeting. **Read `references/set_piece_battles.md` first**: what the stock AI does wrong with big groups and what playtests taught. Tune it in the Battle Lab (scenario 63; parked in `scenarios/_battlelab/`: rename the folder to `battlelab` and reinstall to use it).
- **Cross-session state**: `RT.flag(name, true)` to persist, `RT.clearFlag(name)` to clear. Never use `RT.flag(name, nil)` to clear — that is a read, not a write.

---

## Testing an arc

`tests/arcs/<name>.lua` plays the arc inside a headless EmptyEpsilon running the real sandbox
scenario (`tools/game_tests.py`; about a minute per arc). Read `tests/_harness.lua` for the
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
- **Undeclared or misspelled flags** — `RT.flag("myarc_acepted")` used to fail silently. Declare flags in `M.flags`; `check.py` catches the rest.
- **Writing another arc's flag** — flags listed in `M.reads` are read-only. If two arcs need to agree, the owner sets the flag.
- **Talking to every ship** — `RT.shipLog` / `RT.hail` reach all player ships. Arcs use `ARC.log` / `ARC.hail`.
- **Re-implementing a shared helper** — a local `_firstPlayer`, `_dist`, `_alive`, `_kill` or `_addRecords` in an arc. Use `ARC.*` (`check.py` errors on these).
- **Putting an arc helper in `core.lua`** — shared arc code lives in `ee/ragtag/missions/_helpers.lua`.
- **Forgetting the require** — the arc never loads and the game throws no error, but `check.py` now errors on any `ee/ragtag/missions/*.lua` not required by `missions.lua`. Intentionally unloaded arcs go in `ee/ragtag/missions/attic/`.
- **Telling Science to hack** — hacking is a **Relay** function in this engine (no hack control on Science). Say "Relay" in ship logs, comms and design docs; see `api_notes.md` §12b for the mechanics (50% per success, 180 s decay).
- **Checking a hack with `>= 1.0`** — it never fires. EE lowers every `hacked_level` by 1/180 per second in the system update, *before* the scenario script runs, so a hack that lands at 100% already reads just under 1.0 when your phase `update` checks it. Complete at **`>= 0.99`** (about a 2 s window), check every tick, and latch it (advance the phase or set a flag) rather than re-reading the level later. A GM "Complete hack" helper sets the level to 1.0 and lets the normal check fire next frame. Boneyard (Annex) and Rezkov (Galen) both do this.
- **GM button labels over 18 characters** — the GM console clips them. Keep every `M.gm_states` / `M.gm_actions` label (including function labels like a state/phase readout) to **18 characters max**; put detail in the `globalMessage` the action fires, not the label. `→ Annex control` (15) is fine; `→ Annex control (hack done)` is not. The engine truncates and logs `GM label too long` as a backstop.
- **Keeping state in a `custom` trigger** — the engine checks triggers in order and stops at the first that fails (`rep_min`/`rep_max`, `upgrades_min`, `not_flagged`, then `custom`, then `requires`), so `custom` does not run while an earlier condition fails. Something it notes (a starting count, a timestamp) is noted late. The Ledger's "2 board jobs since Rezkov" counted from the moment the crew reached 800 cr of upgrades, so its hook never came in a playtest. Note such state in `requires` (the engine evaluates it every frame for every arc, whatever its status) and keep `custom` a pure check; test the gate through the engine (`T.wait` and `T.status()`), not by calling `custom` directly (`tests/arcs/ledger.lua`).
- **Writing your own "database updated" log line** — SCIDB announces every entry it adds or reveals in the ship log (Relay) with its place, e.g. `[Science] Database entry added: Lore > Boneyard Survivor Records.`, and as a pop-up on Science, Operations and Single Pilot (entries within a second share one); a second line or pop-up from the arc doubles it. Log only the story beat, before the `SCIDB.addEntry` / `SCIDB.unlock` / `ARC.meet` call. A restore that is not news (resuming a session) goes through `SCIDB.quietly(...)`; `SCIDB.sync()` is already quiet. See `missions_api.md`, "Science database follows the arc state".
- **A raw `Artifact()` as a voice or hidden helper** — `Artifact()` is not position-less: it has a position (0, 0 = Port Vesper unless moved), a radar blip and a 3D model, so its callsign shows on radar over Vesper. Lifeboat Survivors and the Ledger AI both did until a playtest caught it. For a voice with no ship use `RT.voice.create` (it strips them); for any other invisible scripted object, strip `radar_trace`, `mesh_render`, `physics` and `transform` yourself. Headless tests cannot see radar, so assert the components are gone (`tests/arcs/boneyard.lua` does).
- **Calling `entity:onDestruction` directly** — one callback slot per entity; a direct call clobbers reputation tracking, director kill events, and loot drops. Register via `RT.onKill(ship, fn(ship, instigator))`. It fires only on damage kills (never on scripted `destroy()`), and `instigator` tells you whether the player did it.

---

## Checklist before shipping

- [ ] The arc is linear: each phase goes to the next phase, `done`, or back to an earlier phase (no branching; see "Linear arcs" in the reference)
- [ ] Science DB entries the arc reveals follow its flags (`SCIDB.meet` for people, `SCIDB.rule` for lore/runtime entries)
- [ ] `M.on_cancel` destroys all spawned objects (`ARC.kill`)
- [ ] `M.flags` declares every flag the arc sets, with its meaning; `M.reads` lists other arcs' flags it reads
- [ ] Reacts to the arc ship only: no `RT.players` / `RT.forEachPlayer` / `RT.shipLog` / `RT.hail`; choice-bearing comms wrapped in `ARC.comms`
- [ ] Uses `ARC` helpers where one exists; anything two arcs share was added to `_helpers.lua`, nothing mission-specific was added to `core.lua`
- [ ] `M.gm_reset` + `M.completed` let every `→` button land with the full context (jump through each phase and back; no leftover ships, timers, flags or state)
- [ ] `RT.after` timers cancelled with `RT.cancelTimer(name)` in `_clearState` if they shouldn't fire after phase ends
- [ ] Arc triggers use `not_flagged` to prevent re-triggering after completion
- [ ] Destruction callbacks registered via `RT.onKill`, never `entity:onDestruction`
- [ ] Every `M.gm_states` / `M.gm_actions` label is ≤ 18 characters (check function labels at their longest value)
- [ ] Every phase that sends the crew somewhere has a GM travel shortcut: `ARC.travel("Place", {phases}, target)` ("Ship → Place", 5U away), listed in the GM guide
- [ ] Hook rumors injected in `enter` / removed in `exit`, not gated on a persistent flag
- [ ] GM guide `docs/GM_<NAME>_MISSION.md` (Premise, Triggers, Phases, GM console, Exports, Design notes) matches the code and is linked from `docs/GM_GUIDE.md`; a change to an existing arc updated its guide
- [ ] `tests/arcs/<name>.lua` plays the real path, every ending, every GM state and "-> Inactive"; `tools/game_tests.py` passes
- [ ] `python3 tools/check.py` passes
