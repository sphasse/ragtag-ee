# ragtag-ee — notes for Claude Code

EmptyEpsilon (bridge simulator) scenarios built on a shared universe, with an
optional local-LLM "director" that watches the session over EE's HTTP API and keeps notes for the GM
(observation only: it does not change the game).
Contributors add **universe extensions** and **scenarios** independently.

## Layout
- `ee/ragtag/` — Lua framework, installed to EmptyEpsilon `scripts/ragtag/`
  - `core.lua` (RT: campaign saves, flags, per-ship records, credits, player ships, objectives, timers) + `core/*.lua`, loaded by it:
    `events` (the event bus `RT.emit` / `RT.on`, scripted beats, state providers), `sound`, `reputation`, `upgrades`,
    `stations` (comms menu, shipwright, restock), `gm_tools` (backup/restore)
  - `gm_console.lua` (GMCONSOLE: the campaign GM menus; top layer, loaded by the scenario, not by core)
  - `verse.lua` (VERSE engine: builds the universe from data) + `verse/schema.lua` (VERSE.extend, validation)
  - `verse/drift.lua` — base universe **data** (no engine calls)
  - `verse/extensions/*.lua` — community universe additions; `index.lua` is generated
  - `director.lua` (DIR: the mailbox to the AI director and nothing else: it listens to the event bus) +
    `director/actions/*.lua` (the action whitelist; `index.lua` is generated)
  - `jobs/` — the job board: `_engine.lua` (`JOBS.board` decides the offers, a renderer shows them), one file per job type
  - `world/` — ambient plugins: `_engine.lua` (WORLD), `proximity`, `defenders`, `salvage`, `traffic`, `rumors`, `sciencedb`
  - `missions/` — story arcs: `_engine.lua` (MISSIONS phase machine), `_helpers.lua` (`ARC`: helpers shared by arcs), one file per arc.
    Core never depends on this folder; shared arc code goes in `_helpers.lua`, not `core.lua`.
    Arcs belong to the primary ship only (`ARC.player()`; other player ships just work the job board; if it is lost, a ship
    that joins under or is renamed to the campaign's ship name becomes the primary again: `RT.promotePrimary`), and declare
    their saved flags in `M.flags` / `M.reads` (`check.py` rejects undeclared flag names).
- `scenarios/<campaign>/scenario_NN_name.lua` (+ `bible.md`, `plan.md`); `scenarios/_template/` is not installed
- `scenarios/battlelab/scenario_63_battlelab.lua` — Battle Lab: a Concord group vs Corsairs (+ the crew) around six battle
  positions in open space, tunable from the GM screen; for balancing set-piece battles (see its README)
- `director/` — Python 3.11+ stdlib-only AI director; `generated/world.md` is generated
- `tests/` — in-game regression tests run by `tools/game_tests.py` (never installed into a played game): `_harness.lua`,
  `arcs/<arc>.lua` (one per story arc), `jobs/<type>.lua` (one per job type) plus `jobs/board.lua`, `jobs/multiship.lua`
  and `jobs/credits.lua`, `world/<plugin>.lua` (one per world plugin) plus `world/engine.lua`, and `core/records.lua`
  (per-ship ownership), `core/events.lua` (event bus, beats, the director's mailbox and its observation-only guard),
  `core/gm_console.lua` (the GM menus act on the ship picked), `core/primary.lua` (losing and restoring the primary ship)
  and `core/stations.lua` (ports are indestructible; a lost station is reported), `core/upgrades.lua` (the upgrade catalogue and line bases)
- `tools/` — `check.py`, `install.py`, `smoke_test.py`, `game_tests.py`, `ci_headless.sh`, `make_map.py`, `gen_world.py`, `gen_sfx.py` (synthesizes `ee/ragtag/sfx/*.wav`), `dump_verse.lua`
- `ee/ragtag/voice.lua` (`RT.voice`: invisible NPC voices that hail and converse), `ee/ragtag/stats.lua` (`STATS`/`ACH`: persistent statistics and achievements) and `ee/ragtag/battle.lua` (`BATTLE`: set-piece battles over combat points, shared by the Battle Lab and the Corsair arc), all loaded by `core.lua`
- `.claude/skills/empty-epsilon-scenarios/` — EE scripting knowledge and gotchas. **Read it before writing EE Lua.**

## Commands
- `python3 tools/check.py` (add `--fix` to regenerate generated files) — run after every change
- `python3 tools/install.py --ee <EmptyEpsilon dir> [--link]` — install into a game
- `python3 tools/package.py --version N [--radar-icons]` — player release zip in `dist/` (unzip into the EmptyEpsilon folder)
- `python3 tools/release.py [--dry-run] [--radar-icons] [--notes FILE] [--draft]` — numbered GitHub release (next number after the
  highest numeric tag): builds the zip, tags, publishes with `gh`. Needs a clean, pushed main and `gh auth login`.
- `EE_DIR=<EmptyEpsilon checkout with _build/EmptyEpsilon> tools/ci_headless.sh` — headless run + smoke test (Linux).
  Without `EE_DIR` it builds EmptyEpsilon at the pinned commits into `.ee-build/` (~20 min first time).
- `python3 tools/smoke_test.py --launch <EmptyEpsilon dir>` — smoke test in one command on any platform: installs, starts the
  sandbox headless with its own empty save, checks the universe and the director bridge, fails on any `LUA-Error`, stops the game.
- `python3 tools/game_tests.py --ee <EmptyEpsilon dir> [name | folder/name | arcs | jobs | world | core ...] [-v]` —
  in-game regression tests: each story arc, job type and world plugin, and the core systems, played headless through
  their real comms (a couple of minutes, in parallel). `salvage` is in two folders: say `jobs/salvage` or `world/salvage`.
  Run after any change to an arc, a job, a world plugin, the missions or jobs engine, `core.lua` / `core/*.lua` or `director.lua`.
- `cd director && python3 main.py --mock --mock-llm` — director + GM console without game or model
- Requires `lua5.4`/`luac5.4` for the tools (`check.py` also accepts a plain `luac`, and falls back to a pure-Python
  parser for the universe data).

## Contracts (don't break these)
1. **Scenarios never rebuild or hard-code the universe.** They call `VERSE.build`, place their own objects with
   `VERSE.at("Place", dx, dy)`, and list every universe place they rely on in `VERSE.requirePlaces{...}`.
2. **Extensions only add.** Renaming/removing a place in `drift.lua` is a breaking change; `check.py` lists every scenario it breaks.
3. **The model never sends Lua.** Director actions are whitelisted in `ee/ragtag/director/actions/*.lua` (`DIR.ACTIONS`) and
   mirrored in `director/actions.py`; change both together and clamp every argument on the Lua side (`check.py` checks the two match).
4. **Director is observation-only** (as of 2026-10-29). The model may send only `gm_note` and `noop`; everything the crew can
   see or that changes the campaign (`say`, `set_objective`, ...) is GM-only, refused in `actions.py` and again in Lua unless
   the GM sent it (`DIR._h.fromGM(cmd)`). Beats are scripted (`RT.defineBeat` / `RT.fireBeat`); there is no `ai = true`.
5. **Each campaign has its own save** via `RT.useCampaign("<folder name>")` and its own `scenarios/<campaign>/bible.md`.
6. Scenario numbers must not collide with stock EmptyEpsilon or each other (`check.py` enforces; ranges in CONTRIBUTING.md).
7. Generated files (`extensions/index.lua`, `director/actions/index.lua`, `director/generated/world.md`, `docs/verse_map.svg`)
   come from `check.py --fix`; never hand-edit.
8. **Game code never names `DIR`.** Core, jobs, world plugins and arcs report with `RT.emit(type, data, priority)`
   (`core/events.lua`); the director's mailbox is one listener (`RT.on`). Only `director.lua`, `director/`, `gm_console.lua`
   and scenarios may reference `DIR` (`check.py` enforces). The game must play the same with no director.
9. **One record per ship.** Credits, standing and upgrades live in `RT.shipRecord(ship)` (the primary ship's record is the
   campaign table; others are in `campaign.extra_ships`). Outside `ee/ragtag/missions/`, `RT.addCredits`, `RT.addReputation`
   and `RT.grantUpgrade` must be given the ship (`check.py` enforces); "no ship" means the primary ship and is for arcs only.
10. **A callsign is a name, not an identity.** Keep the entity of whatever you spawn (`m.target`, `group.ships`, `slot.ship`)
    and never find it again by callsign; `RT.find` is for universe places and names a person typed. Per-ship state is found
    with `==` on the entity (a list, not a table keyed by ship: one ship can have several Lua handles).

## Engine gotchas that have bitten this project
(Details in the skill's `references/api_notes.md`.)
- `/exec.lua` runs in a separate Lua environment (no scenario globals, no utils.lua) and must return a string.
- `ship:getDockedWith()` returns `false`, not nil, when undocked — test truthiness.
- Losing a player ship costs its record half its credits (`RT.DEATH_PENALTY`, `RT.chargeLoss`), once; upgrades and standing are kept.
- Universe ports (every station but Corsair/Hollow ones) are indestructible (`verse.lua`): job and arc fights come to them.
  A station that dies emits `station_destroyed`. An arc that needs a hostile station to survive sets that itself.
- `getTypeName()` errors on non-ships; filter with `obj.components.typename ~= nil`. Unknown component names raise errors.
  It returns the ship's TEMPLATE name ("MT52 Hornet"), never "CpuShip": use `isObjectType()` to test what something is.
- Freighter impulse is ~0.05u/s; AI traffic on this map needs warp, a spawn on the destination side of stations, 4u clearance, and the stall watchdog.
- `setWeaponTubeCount` resets all tubes; `sendCommsMessage` fails when comms are busy (use `RT.hail`).
- Headless EE: start detached (`setsid nohup ...`) and poll; one server per port.
- **`debug` library not available**: EmptyEpsilon Lua doesn't have `debug.traceback()`. Use `pcall` and `tostring(err)` for error handling.
- **`sendCommsMessage` logs twice**: Once when sent, again when accepted in Relay. Use direct `RT.shipLog()` if you need single-log behavior.
- **`playSoundFile` is server-only** (plays on the server machine, never on clients). Use `RT.sound(id)` for cues; client/positional sound needs an `sfx` entity and the file on every client. Music can't be driven from Lua.

## Definition of done
`python3 tools/check.py` passes, and for Lua changes a headless run shows no `LUA-Error`, the smoke test passes
and `tools/game_tests.py` passes. A change to an arc's, job's or world plugin's behaviour comes with a change to its test
(`tests/arcs/<arc>.lua`, `tests/jobs/<type>.lua`, `tests/world/<plugin>.lua`); a change to core ownership or the event
bus with a change to `tests/core/`.
Say plainly in PR descriptions what was and wasn't tested.

---

## Mission System Architecture (Sandbox Campaign)

### Job Types with Progressive Compensation

(Seven job modules in `ee/ragtag/jobs/`, each setting its own `M.type_mult`.)

**Base multipliers** (delivery = 1.0x baseline):
1. **Delivery** (1.0x): Ferry cargo between stations. Safest, baseline income.
2. **Salvage** (1.2x): Recover cargo pods from coordinates. Moderate risk.
3. **Hacking** (1.4x): Breach comms relay systems (75% hack threshold). Technical challenge.
4. **Destroy** (1.6x): Eliminate hostile targets completely. Combat-focused.
5. **Boarding** (1.8x): Disable and board target ships. Highest difficulty.
6. **Escort** (1.5x, +90 cr munitions allowance): Shepherd a convoy to its destination; the convoy takes orders from its escort.
7. **Tailing** (1.4x): Shadow a ship to a covert meeting and scan both vessels.

**Dynamic scaling**:
- Distance bonus: +1% per U beyond 10U
- Danger bonus: +15% per danger level (0-4: safe/risky/dangerous/deadly)
- Final reward rounded to nearest 5 credits

**Example**: A boarding mission (1.8x) 30U away in danger level 2 space pays:
`base * 1.8 * (1 + 20% distance) * (1 + 30% danger) ≈ 2.8x base reward`

### Several ships

The board works for more than one player ship. A job belongs to the ship that took it: only that ship advances,
completes and is paid for it, and gains or loses standing; each ship has its own 2-job cap, credits, standing, upgrades
and job tier (`JOBS.maxTier(ship)`). Story arcs, and every job an arc injects (story contracts and seeds), are for the primary ship only. Job modules use
`JOBS.owner/ships/log/hail/rep`, never `RT.players` / `RT.shipLog`, and keep the entities they spawn on the job record
(`m.target`, `m.convoy`, ...). Everything a ship owns is in its record (`RT.shipRecord(ship)`: credits, reputation,
upgrades); credits show as a `Credits: N` line on Relay and Operations: use
`RT.credits(ship)` / `RT.addCredits(amount, reason, ship)`. An upgrade is bought by, applied to and saved for one ship
(`RT.installUpgrade` / `RT.grantUpgrade` / `RT.revokeUpgrade(id, ship)`). EE's own reputation points are per faction (shared by all
player ships), so they are unused and held at 0; nothing outside `core.lua` may call the `ReputationPoints` methods. Details: `jobs_api.md`, "Ownership".
Patrols and shakedowns (`PROX`) hunt one ship each (`group.target`, the ship that drew them) and judge it by its own
standing; only that ship is stopped, fined, jammed and attacked. Zone cooldowns and caps are shared by all ships.

### Mission Generation Flow

1. **Station offers 1–3 jobs** (by station size, less with poor standing) when a ship docks and hails "Any work available?".
   `JOBS.board(cs, ship)` decides the offers (no comms calls; testable); `_showBoard` renders them.
2. **Type selection** via weighted random, by the asking ship's tier:
   - tier 0: delivery 15, salvage 7 · tier 1 adds hacking · tier 2 adds destroy and boarding (`_TIER_WEIGHTS`);
     a type the table does not list (escort, tailing) uses its module's `M.weight` (3) at every tier from its `tier_min`
3. **Archetype selection** from each job module's `_ARCHETYPES` table (tier-gated)
4. **Legacy intercept fields** in archetypes (`intercept_types`, `intercept_chance`) are no longer used as of 2026-10-29 (proximity spawn system replaced mission-specific intercepts)
5. **Nearby stations** calculated for boarding/destroy (50U radius) → stored as `target_dest`
6. **Mission record created** with all fields, added to offers list

### Story arcs and the job board

Arcs seed station boards with `JOBS.inject{category, priority, origin, when, record}` (priority 3 = filler,
5 = `story` contract tagged `[SPECIAL]`, bypassing the 2-job cap with no failure penalty). Injected jobs are
offered to the primary ship only (`any_ship = true` opens one to every ship; not for arcs). Build records
with `JOBS.build("delivery"|"salvage", opts)`; remove by category in `M.on_unload`/phase `exit`. Details:
`.claude/skills/empty-epsilon-scenarios/references/jobs_api.md`.

### Proximity Spawn System (Replaced Intercepts)

**Ambient faction patrols** spawn based on player location, not mission progress. System in `ee/ragtag/world/proximity.lua`.

**Zone-based spawns**:
- **Concord Core / Arbiter Line**: Concord shake-downs (comms-first, not immediate attack)
- **Shroud / Gauntlet / Blackwater**: Corsairs (attack on sight)
- **Boneyard**: Relic war drones (no comms, attack)
- **Maw**: Hollow (no comms, attack)

**Spawn conditions** (checked every 8 s, for each player ship, in the zone that ship is deepest in; per-zone GM mode None/Low/Medium/High;
a zone sends at most one patrol per check, after one ship picked at random, so ships flying together draw no more patrols than one):
- Zone cooldown expired (Concord 600/720 s, Corsairs 180–240 s, Boneyard 180 s, Maw 120 s; divided by the mode's frequency,
  shorter with bad Corsair standing)
- Zone ship cap not reached (mode: 6 / 12 / 24; Concord zones: 1)
- Fewer hostiles within 10U than the mode's density limit (3 / 6 / 12)
- No other patrol in the same 18U map cell
- Zone not suspended by an arc, job board not locked
- Spawn point outside every station's 15U exclusion zone

A patrol group keeps its ship ENTITIES (`group.ships`), never callsigns: two patrols can draw the same name.

**Combat warp jammers**: hostile Concord ships (patrols spawned hostile by reputation, shakedowns gone
hostile, and arc fleets that call `PROX.tickCombatJammers`) drop a warp jammer on the player when within 5U.
Like the shakedown jammer it has 1U range and brakes the ship (rides 0.25U behind, impulse forced to 0
each tick until stopped, then stays put). One per ship at a time; it expires after 2 min and the ship
can drop the next 2 min after the last.
All Concord jammers (including the shakedown one) have 10 hull: two 6-damage beam hits. Tuning: `PROX.JAMMER`.

**Several ships**: a patrol hunts its `group.target` and judges it by that ship's own standing (strength, shake-down or
hostile, fine, standing changes, jammers, attack orders, log lines). Another ship that hails a shake-down is told to keep
clear. If the target dies or leaves the zone while another player ship is in it, the patrol takes the nearest one (a new
shake-down target is stopped from scratch; a hostile patrol stays hostile).

**Leash system**: Ships recall to spawn point when no player ship is left in the region, despawn after 120s if none returns.

**Reputation effects**:
- Corsairs ≤ −200 rep: 30% shorter cooldowns; ≤ −400: 50% shorter (hunt you)
- Concord shakedown outcomes (rep thresholds): ≥500 callsign recognised (clean pass with compliment); ≥200 clean pass; ≥0 nothing flagged; ≥−200 fine offer; <−200 detention threat → Concord Ops hostile

**GM control**: World Plugins... → Proximity Spawns: on/off, "Trigger Spawn Now", and a mode per zone
(`PROX.setZoneMode(zone, 1..4)`: None / Low / Medium / High).

**Key insight**: Danger is now location-based (enter the Gauntlet → Corsairs spawn) rather than mission-based (intercept at 40% route progress). Creates predictable risk zones players learn to navigate.

### Target Ships (Boarding/Destroy)

**Creation flow**:
1. Mission generation picks `nearby_stations` (50U radius, excludes origin/Hollow/Corsairs)
2. Random station selected → stored as `target_dest`
3. **On mission accept**, target spawned at `(wx, wy)` with AI order: `orderFlyTowards(target_dest)`
4. Mission log shows: *"Target is at [grid] heading toward [target_dest]"*

**Critical bug fixed 2026-10-28**: Spawning code was ignoring pre-calculated `target_dest` and picking a random station instead. Now uses `m.target_dest` directly.

**Target behavior**:
- Starts Independent faction, flying toward destination
- **Boarding**: When player within 8U, switches to Corsairs and attacks
- **Destroy**: When player within 8U, switches to Corsairs and attacks
- Ships have full health/shields and can dock at stations (for future gameplay)

### Hacking Missions

- Relay is a stationary "Defense platform" CpuShip, Relic faction, cannot be destroyed until hacked
- Armed: six 30° beam arcs at 5U range with 30° gaps — Helm threads the windows while Relay hacks
- Player must hack **any system to 75%** (not just reactor, despite archetype field)
- Mission completes when threshold reached
- Ambient patrols may spawn based on zone (proximity system), not mission-specific

### Object Type Identification

EmptyEpsilon entities don't expose their C++ type directly, but `utils.lua` provides `isObjectType(entity, typeName)` for type checking.

**Identifying specific entity types:**
```lua
if isObjectType(obj, "ScanProbe") then
    -- It's a scan probe
end

if isObjectType(obj, "CpuShip") then
    -- It's an AI ship
end

if isObjectType(obj, "PlayerSpaceship") then
    -- It's a player ship
end
```

**Why this matters:**
- Scan probes have no `typename` component, so `obj:getTypeName()` fails
- `obj:typeName()` doesn't exist
- Heuristics (faction + method presence) are fragile and match unintended objects
- **Always use `isObjectType()` when you need to identify a specific entity type**

**Common use cases:**
- Filtering `getObjectsInRadius()` results by type (e.g. only CpuShips when idling Boneyard drones)
- Type-specific behaviors in event callbacks

Reference: [EmptyEpsilon utils.lua:351](https://github.com/daid/EmptyEpsilon/blob/b492ea94326c229ec8c0047872451129c4338871/scripts/utils.lua#L351)

### Common Mission Bugs and Fixes

**"attempt to index a nil value" in mission generation**:
- Usually missing archetype table (e.g., `_DESTROY_ARCHETYPES` undefined)
- Or missing field in opts (e.g., `nearby_stations` not passed)
- **Diagnostic pattern**: Wrap each `MISSION.new*` in `pcall`, log mission type on error
  ```lua
  local ok, err = pcall(function() return MISSION.newBoarding({...}) end)
  if not ok then
      print("[ERROR] Boarding mission generation failed: " .. tostring(err))
      error("Boarding: " .. tostring(err))
  end
  ```

**Target not flying toward logged destination**:
- Check spawning code uses `m.target_dest`, not re-calculating stations
- Verify `nearby_stations` passed to `MISSION.new*` functions

**Proximity spawns not appearing**:
- Check player is in a zone with patrol config (`PROX.zones` table)
- Verify the zone's cooldown is not active (`state.region_cd`)
- Check the zone's mode is not None and its ship cap is not reached
- Story arcs suspend zone spawns via `PROX.suspendZone("zone name")` — check `PROX._suspended_zones`

### Port Vesper Welcome System

**First hail only** (per session):
- Tracked via `S.vesper_first_hail` boolean
- Custom `setCommsFunction` on Port Vesper station
- First hail shows full welcome: *"Back again, I see. Port Vesper is neutral ground..."*
- Subsequent hails show standard: *"Port Vesper traffic control. Mind the dock clamps, they bite."*
- **No automatic hail** at game start (avoids double-logging from `sendCommsMessage`)

### Error Diagnostics Best Practices

**EmptyEpsilon Lua limitations**:
- No `debug` library → no `debug.traceback()`
- `pcall` returns `(ok, result_or_error)` where error string includes file:line

**Diagnostic pattern**:
```lua
print("[JOBS] Generating " .. mtype .. " mission at tier " .. tier)
local ok, err = pcall(function() return MISSION.newX({...}) end)
if not ok then
    print("[ERROR] X mission generation failed: " .. tostring(err))
    error(mtype .. ": " .. tostring(err))
end
offers[#offers + 1] = err  -- result when ok == true
```

This gives: `[ERROR] Boarding mission generation failed: mission.lua:587: attempt to index a nil value (field 'target_dest')`
