# ragtag-ee — notes for Claude Code

EmptyEpsilon (bridge simulator) scenarios built on a shared universe, with an
optional local-LLM "director" that drives NPCs and pacing over EE's HTTP API.
Contributors add **universe extensions** and **scenarios** independently.

## Layout
- `ee/ragtag/` — Lua framework, installed to EmptyEpsilon `scripts/ragtag/`
  - `core.lua` (RT: campaign saves, ship, upgrades, credits, stations, objectives)
  - `verse.lua` (VERSE engine: builds the universe from data) + `verse/schema.lua` (VERSE.extend, validation)
  - `verse/drift.lua` — base universe **data** (no engine calls)
  - `verse/extensions/*.lua` — community universe additions; `index.lua` is generated
  - `director.lua` (DIR: mailbox to the AI director, events, beats, whitelisted actions)
- `scenarios/<campaign>/scenario_NN_name.lua` (+ `bible.md`, `plan.md`); `scenarios/_template/` is not installed
- `director/` — Python 3.11+ stdlib-only AI director; `generated/world.md` is generated
- `tools/` — `check.py`, `install.py`, `smoke_test.py`, `ci_headless.sh`, `make_map.py`, `gen_world.py`, `dump_verse.lua`
- `.claude/skills/empty-epsilon-scenarios/` — EE scripting knowledge and gotchas. **Read it before writing EE Lua.**

## Commands
- `python tools/check.py` (add `--fix` to regenerate generated files) — run after every change
- `python tools/install.py --ee <EmptyEpsilon dir> [--link]` — install into a game
- `EE_DIR=<EmptyEpsilon checkout with _build/EmptyEpsilon> tools/ci_headless.sh` — headless run + smoke test (Linux).
  Without `EE_DIR` it builds EmptyEpsilon at the pinned commits into `.ee-build/` (~20 min first time).
- `cd director && python main.py --mock --mock-llm` — director + GM console without game or model
- Requires `lua5.4`/`luac5.4` for the tools.

## Contracts (don't break these)
1. **Scenarios never rebuild or hard-code the universe.** They call `VERSE.build`, place their own objects with
   `VERSE.at("Place", dx, dy)`, and list every universe place they rely on in `VERSE.requirePlaces{...}`.
2. **Extensions only add.** Renaming/removing a place in `drift.lua` is a breaking change; `check.py` lists every scenario it breaks.
3. **The model never sends Lua.** Director actions are whitelisted in `ee/ragtag/director.lua` (`DIR.ACTIONS`) and mirrored in
   `director/actions.py`; change both together and clamp every argument on the Lua side.
4. **Every `ai = true` beat has a deterministic fallback**; scenarios must play with Director=Off.
5. **Each campaign has its own save** via `RT.useCampaign("<folder name>")` and its own `scenarios/<campaign>/bible.md`.
6. Scenario numbers must not collide with stock EmptyEpsilon or each other (`check.py` enforces; ranges in CONTRIBUTING.md).
7. Generated files (`extensions/index.lua`, `director/generated/world.md`, `docs/verse_map.svg`) come from `check.py --fix`; never hand-edit.

## Engine gotchas that have bitten this project
(Details in the skill's `references/api_notes.md`.)
- `/exec.lua` runs in a separate Lua environment (no scenario globals, no utils.lua) and must return a string.
- `ship:getDockedWith()` returns `false`, not nil, when undocked — test truthiness.
- `getTypeName()` errors on non-ships; filter with `obj.components.typename ~= nil`. Unknown component names raise errors.
- Freighter impulse is ~0.05u/s; AI traffic on this map needs warp, a spawn on the destination side of stations, 4u clearance, and the stall watchdog.
- `setWeaponTubeCount` resets all tubes; `sendCommsMessage` fails when comms are busy (use `RT.hail`).
- Headless EE: start detached (`setsid nohup ...`) and poll; one server per port.
- **`debug` library not available**: EmptyEpsilon Lua doesn't have `debug.traceback()`. Use `pcall` and `tostring(err)` for error handling.
- **`sendCommsMessage` logs twice**: Once when sent, again when accepted in Relay. Use direct `RT.shipLog()` if you need single-log behavior.

## Definition of done
`python tools/check.py` passes, and for Lua changes a headless run shows no `LUA-Error` and the smoke test passes.
Say plainly in PR descriptions what was and wasn't tested.

---

## Mission System Architecture (Sandbox Campaign)

### Five Mission Types with Progressive Compensation

**Base multipliers** (delivery = 1.0x baseline):
1. **Delivery** (1.0x): Ferry cargo between stations. Safest, baseline income.
2. **Salvage** (1.2x): Recover cargo pods from coordinates. Moderate risk.
3. **Hacking** (1.4x): Breach comms relay systems (75% hack threshold). Technical challenge.
4. **Destroy** (1.6x): Eliminate hostile targets completely. Combat-focused.
5. **Boarding** (1.8x): Disable and board target ships. Highest difficulty.

**Dynamic scaling**:
- Distance bonus: +1% per U beyond 10U
- Danger bonus: +15% per danger level (0-4: safe/risky/dangerous/deadly)
- Final reward rounded to nearest 5 credits

**Example**: A boarding mission (1.8x) 30U away in danger level 2 space pays:
`base * 1.8 * (1 + 20% distance) * (1 + 30% danger) ≈ 2.8x base reward`

### Mission Generation Flow

1. **Station offers 2 missions** when player docks and hails "Any work available?"
2. **Type selection** via weighted random:
   - delivery: 15, salvage: 7, boarding: 3, hacking: 3, destroy: 3
3. **Archetype selection** from mission.lua `_*_ARCHETYPES` tables (tier-gated)
4. **Legacy intercept fields** in archetypes (`intercept_types`, `intercept_chance`) are no longer used as of 2026-10-29 (proximity spawn system replaced mission-specific intercepts)
5. **Nearby stations** calculated for boarding/destroy (50U radius) → stored as `target_dest`
6. **Mission record created** with all fields, added to offers list

### Proximity Spawn System (Replaced Intercepts)

**Ambient faction patrols** spawn based on player location, not mission progress. System in `ee/ragtag/proximity.lua`.

**Zone-based spawns**:
- **Concord Core / Arbiter Line**: Concord shake-downs (comms-first, not immediate attack)
- **Shroud / Gauntlet / Blackwater**: Corsairs (attack on sight)
- **Boneyard**: Relic war drones (no comms, attack)
- **Maw**: Hollow (no comms, attack)

**Spawn conditions**:
- Player in dangerous zone for 8+ seconds (check interval)
- Region cooldown expired (90s base, scaled by reputation)
- Global cooldown expired (60s)
- <4 active patrol ships total
- <3 hostiles within 10U (density check)
- Outside 20U station exclusion zones

**Leash system**: Ships recall to spawn point when player exits region, despawn after 120s if player doesn't return.

**Reputation effects**:
- Corsairs >+20 rep: 50% longer cooldowns (less frequent spawns)
- Corsairs <-20 rep: 30% shorter cooldowns (hunt you)
- Concord >+20 rep: shake-downs dismissed without fine
- Concord <-20 rep: skip shake-down, immediate attack

**GM control**: `PROX.config.spawn_frequency` multiplier (0.5 = half as often, 2.0 = twice as often).

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

- Spawn custom "Comms Relay Beacon" template (only reactor system)
- Relay is stationary, Concord faction, cannot be destroyed
- Player must hack **any system to 75%** (not just reactor, despite archetype field)
- **Relay jamming**: Active relays neutralise scan probes within 5U (checked every 2s)
- Mission completes when threshold reached
- Ambient patrols may spawn based on zone (proximity system), not mission-specific

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
- Verify cooldowns not active (90s region, 60s global)
- Check max_active limit not reached (4 ships default)
- Witness arc sets `S.witness_active = true` which suspends all spawns

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
