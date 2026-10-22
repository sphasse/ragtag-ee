---
name: empty-epsilon-scenarios
description: Design, write, debug and test EmptyEpsilon (bridge simulator) Lua scenarios, including multi-session campaigns with persistent progress and the Long Haul AI-director framework where a local LLM drives NPCs and pacing through EmptyEpsilon's HTTP API. Use this whenever the user mentions EmptyEpsilon, Empty Epsilon, EE scenarios, bridge simulator missions, scenario_XX.lua files, the GM screen, the Long Haul campaign, the ragtag/Magpie campaign, or the AI director, even if they just say "write the next session" or "add an enemy wave" or "why is my scenario erroring".
---

# EmptyEpsilon scenarios

EmptyEpsilon scenarios are Lua files in the game's `scripts/` folder. The engine changed a lot in the 2024 ECS rewrite, and much of the scripting knowledge online (and in model training data) predates it. **Don't write API calls from memory.** Check `references/api_signatures.md` (generated from the engine source) and `references/api_notes.md` (behaviours verified on a running server) first.

## Pick the right path

1. **A Long Haul campaign session** (the user's ragtag freighter campaign, or "the next session"): use the framework. Read `references/framework.md` and `scenarios/longhaul/plan.md`, start from `scenarios/_template/scenario_99_template.lua`, and copy the Session 1 conventions. Sessions are stories layered on the shared universe (`ee/ragtag/verse.lua`): don't rebuild stations or regions the verse already has, and place new objects with `VERSE.at(...)`.
5. **Changing the universe itself** (new stations, regions, routes, danger zones, salvage): add an extension file in `ee/ragtag/verse/extensions/` (see "Universe changes" below). Every scenario picks it up. Keep asteroid fields clear of stations and run the traffic check below.
2. **A standalone scenario**: plain EE Lua. You can still require the framework for its helpers (stations, objectives, timers, AI director), or write without it.
3. **Debugging an existing scenario**: get the `LUA-Error` line and traceback from the log, then check `references/api_notes.md` section 4 first. Most ECS-era crashes are a method called on an entity that lacks the component.
4. **Extending the AI director** (new actions, different prompts): `references/framework.md` sections 3–4, plus the Python in `director/`.

## Writing a scenario

### Structure
- Header comments: `-- Name:`, `-- Description:`, `-- Type:`, and `-- Setting[...]` blocks (format in api_notes.md §1). Campaign sessions use `-- Type: Long Haul Campaign` and the Campaign / Difficulty / Director settings from the template.
- `init()` builds the map, spawns the player, defines beats, adds GM buttons and ends with `DIR.init(...)` when using the director.
- `update(delta)` calls `RT.update(delta)`, `VERSE.update(delta)` and `DIR.update(delta)` first, then advances a phase machine (`S.phase = "loading" | "hauling" | ...`) with all mutable state in one table `S`.
- Time everything with `getScenarioTime()`. Never count frames.

### Story beats and the director
Model the story as named beats with `DIR.defineBeat(id, {desc, ai, fn})`.
- Structural moments (briefings, arrivals, payouts) are scripted beats fired from `update()`.
- Dramatic moments whose timing can flex (ambushes, betrayals, cavalry) are `ai = true`, so the director can fire them when it feels right.
- **Every `ai = true` beat must also have a deterministic fallback** in `update()` (distance, elapsed time or progress). The session must be fully playable with the director off, and the Director=Off setting must still work.
- Write `desc` for a reader who has never seen the script: the director decides from this text alone.

The session dictionary in `DIR.init` is the director's entire briefing. Use exact callsigns in each cast member's `where` so the director's lines arrive as hails from the right ship. Put pacing advice in `director_guidance` ("fire X after Y; keep fights small; the crew's ship is weak").

### Crew engagement
Aim for something for every station every few minutes: Helm (hazards, chases, docking), Weapons (fights), Engineering (damage, power juggling), Science (scans that unlock story via `setDescriptions` and `isFullyScannedBy`), Relay (comms choices with `addCommsReply`). Offer one real choice per session, record it with `RT.flag`, and pay it off later.

### Robustness checklist
Before handing a scenario over, check each item:
- [ ] No `getTypeName()` or other component-specific call on entities that might lack the component (asteroids, nebulae, artifacts).
- [ ] Every `sendCommsMessage` has a fallback (use `RT.hail`), because it fails when comms are busy.
- [ ] Story-critical entities have `setCanBeDestroyed(false)`.
- [ ] Every ai beat has a fallback; the GM has buttons to fire key beats and to end the session.
- [ ] `setWeaponTubeCount` is followed by `setWeaponTubeDirection` for every tube.
- [ ] Callbacks use their parameters (`function(source, target)`), not `comms_source` globals.
- [ ] Session end saves via `RT.completeSession`, emits `session_end`, and delays `victory()` ~12 s so the director can read it.
- [ ] A player-ship-destroyed path exists.
- [ ] Session objects use campaign factions (Concord, Corsairs, Unknown...), not Human Navy/Exuari/Ghosts.
- [ ] Nothing story-critical sits inside a hostile garrison's zone by accident.
- [ ] `catchUpCampaign()` gives sane defaults if earlier sessions were skipped.

## Testing
Test as far as the environment allows, and tell the user what was and wasn't verified.
1. **Syntax**: `luac5.4 -p file.lua` (install with `apt-get install lua5.4` if needed).
2. **Headless run** (strongly preferred, catches real API errors): build or install EmptyEpsilon, copy the scripts into its `scripts/` folder, and run `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy EmptyEpsilon headless=scenario_NN.lua httpserver=8080`. Watch the log for `LUA-Error`. Building from source on Linux needs the EmptyEpsilon and SeriousProton repos, `cmake`, `ninja-build`, `libsdl2-dev`, then `cmake .. -G Ninja -DSERIOUS_PROTON_DIR=../SeriousProton && ninja`. It takes about 20 minutes on one core.
3. **Drive it**: `tools/ci_headless.sh` (or `tools/smoke_test.py --playthrough` against a running server) tests the bridge and Session 1. For new sessions, add a playthrough function that teleports the ship (`p:setPosition`), docks (`p:commandDock`), forces scans (`setScanStateByFaction("Independent", "full")`) and checks beats fire via the mailbox state.
4. Stop the director before running the smoke test; both write the same mailbox key.
5. **Traffic check** after changing routes or the map: sample freighter positions every 10 s for 5 minutes over HTTP and confirm ships dock (`getDockedWith()`), depart, and none hover near the same point. Keep each command under a few minutes: start EE detached (`setsid nohup ...`) and log samples to a file rather than running one long blocking command.

## Delivering
- Install with `python tools/install.py --ee <EmptyEpsilon folder>` on the **server** machine only; clients don't need the scripts.
- The server needs `httpserver=8080` in `options.ini` for the director.
- When writing a new session, also update `scenarios/<campaign>/bible.md` if new cast or secrets were introduced, and keep `scenarios/longhaul/plan.md` in sync with what was actually built.

## Where things are (in the ragtag-ee repo)
- `references/api_notes.md`: verified behaviours and gotchas. Read before writing any EE code.
- `references/api_signatures.md`: every API function with arguments, generated from engine source. Grep it.
- `references/framework.md`: RT, VERSE and DIR libraries, events, mailbox protocol, adding director actions.
- `CLAUDE.md` and `CONTRIBUTING.md` at the repo root: layout, contracts, scenario numbering, commands.
- `scenarios/_template/scenario_99_template.lua`: tested skeleton for a new scenario.
- `scenarios/longhaul/plan.md`: plans for Long Haul sessions 2–5; `scenarios/longhaul/bible.md`: its story bible.
- `docs/examples/extension_example.lua`: a complete universe extension.

## Universe changes
Add content as a new file in `ee/ragtag/verse/extensions/` (copy the example); edit `ee/ragtag/verse/drift.lua`
only to change the base map, and never rename or remove places scenarios depend on. Always finish with
`python tools/check.py --fix`, which validates data, scenario dependencies and regenerates derived files.
