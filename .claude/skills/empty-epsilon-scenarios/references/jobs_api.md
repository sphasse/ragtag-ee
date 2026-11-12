# Jobs API reference

The job board is a modular contract system. Each job *type* is a self-contained
Lua file in `ee/ragtag/jobs/`. The engine (`_engine.lua`) handles scheduling,
cooldowns, accept/complete/expire lifecycle, and calling into each type module.
Load the whole system with `require("ragtag/jobs.lua")`.

---

## Adding a new job type

1. Create `ee/ragtag/jobs/<type>.lua`.
2. Add `require("ragtag/jobs/<type>.lua")` to `ee/ragtag/jobs.lua`.
3. At the bottom of the file: `JOBS.register(M)`.
4. Optionally register a post-mission tick hook:
   `JOBS._tick_hooks[#JOBS._tick_hooks + 1] = myHookFn`

`check.py` will pick up the new file automatically.

---

## Module interface

Every module exposes a table `M` with these fields.

### Required fields

| Field | Type | Purpose |
|---|---|---|
| `M.type` | string | Unique type key, e.g. `"escort"` |
| `M.weight` | number | Relative probability in weighted type draw |
| `M.generate` | function | Creates a mission record from `opts` |

### Optional fields / methods

| Field | Type | Purpose |
|---|---|---|
| `M.tier_min` | number | Minimum campaign tier before this type is offered (default 0) |
| `M.type_mult` | number | Reward multiplier registered in `JOBS.ECONOMY.type_mult` |
| `M.prepareOpts(ctx)` | function | Build the `opts` table from the station context; return `nil` to skip |
| `M.duration(m)` | function | Time limit in seconds for mission `m` |
| `M.offerText(m, stats)` | function | One-line comms listing text (stats = `"12U · 80cr · 8 min"`) |
| `M.spawn(m)` | function | Spawns world objects when the player accepts (called by engine) |
| `M.acceptLog(m)` | function | Returns the ship-log string shown on accept; engine fallback if nil |
| `M.update(m, entry, ctx)` | function | Called each `JOBS.update()` cycle; return `"remove"` to pull from active list without completing |
| `M.expire(m)` | function | Called when time limit hit; return `true` to suppress generic "time expired" log |
| `M.cleanup(m)` | function | Called on complete **and** expire; destroy/dismiss spawned objects |
| `M.completable(m, cs)` | function | Return true when `cs` (docked station callsign) can complete the mission |
| `M.completeReply(m, entry)` | function | Returns `{label=string, msg=string}` for the comms reply |

### ctx object passed to prepareOpts

```lua
ctx = {
    station_cs     = "Port Vesper",    -- callsign of the offering station
    station_e      = <SpaceStation>,   -- entity (use RT.valid before calling methods)
    tier           = 0,                -- current campaign tier for this slot
    distanceRange  = {min=N, max=N},   -- world-unit distance bounds
    nextCandidate  = function(),        -- returns next shuffled destination callsign or nil
    spawnInVerse   = function(rx, ry), -- picks a random in-verse point at mission distance
    nearbyStations = function(wx, wy, r), -- non-hostile stations within radius_u
    findStation    = RT.find,
    valid          = RT.valid,
}
```

### ctx object passed to update

```lua
ctx = {
    now  = getScenarioTime(),
    jobs = JOBS,
}
```

---

## Faction filtering (archetypes)

Each archetype can carry an optional `fac` field (`"Concord"` or `"Independent"`).
The engine does **not** filter; each `generate()` must implement the two-pass pattern:

```lua
local sfac = opts.origin_faction   -- set in prepareOpts via MISSION.stationFaction(ctx.station_cs)
local pool = {}
for _, a in ipairs(_ARCHETYPES) do
    if (a.tier_min or 0) <= tier and (not a.fac or not sfac or a.fac == sfac) then
        pool[#pool + 1] = a
    end
end
if #pool == 0 then   -- fall back to faction-neutral archetypes
    for _, a in ipairs(_ARCHETYPES) do
        if (a.tier_min or 0) <= tier and not a.fac then pool[#pool + 1] = a end
    end
end
if #pool == 0 then pool = _ARCHETYPES end  -- last resort
```

---

## JOBS engine API

### Config (`JOBS.config`)

| Key | Default | Notes |
|---|---|---|
| `work_cooldown_enabled` | `true` | Gate repeat offers per station slot |
| `work_cooldown_secs` | `600` | Cooldown in seconds (10 min) |
| `mission_distance_mode` | `"medium"` | `"short"` / `"medium"` / `"long"` |
| `jobboard_locked` | `false` | Set `true` during Witness arc to hide jobs |
| `max_active` | `2` | Max simultaneously active contracts |
| `station_slots` | `2` | Default offer slots per station |

### Economy (`JOBS.ECONOMY`)

```lua
JOBS.ECONOMY.base_reward = {[0]=50, [1]=65, [2]=80}  -- per tier
JOBS.ECONOMY.type_mult   = {}                          -- populated by register()
```

### Helpers

```lua
JOBS.corsairName()           -- random name from corsair pool
JOBS.freighterName()         -- random name from freighter pool
JOBS.nearbyStations(wx, wy, radius_u)  -- list of non-hostile station callsigns in range
JOBS.spawnInVerse(rx, ry)    -- wx, wy, dist_u, region — random in-verse point at mission distance
JOBS.maxTier()               -- 0/1/2 from campaign upgrade spend
JOBS.updateObj()             -- refreshes objective display and relay panel
JOBS.stationHook(src, tgt)   -- wire into station setCommsFunction
JOBS.inject(def) / JOBS.removeCategory(cat) / JOBS.build(type, opts) / JOBS.hasVisited(cs)
                             -- story-arc injection, see "Injected jobs" below
```

### Injected jobs (story arcs seed the board)

Arcs add jobs to the board with `JOBS.inject()` and remove them with
`JOBS.removeCategory()`, the same pattern as rumors. Injected jobs are **session
state** (they reset every run): inject from the arc's `M.on_load` or a phase `enter`,
never gated on a persistent flag.

```lua
JOBS.inject({
    category = "MYARC_JOBS",              -- for removeCategory
    priority = 5,                         -- 5 = hook, 3 = seed (default 3)
    origin   = {"Port Vesper", "Halcyon Rest"},  -- string, list, or nil = any station
    when     = function(cs) return JOBS.hasVisited("Concord Station Arbiter") end,  -- optional
    record   = function(cs)               -- or a plain mission table
        return JOBS.build("salvage", {id = "myarc_buoy", origin = cs, wx = 22000, wy = -72000,
            cargo = "a survey buoy", reward = 400, story = true, brief = "...",
            on_found = function(m) ... end})
    end,
})
JOBS.removeCategory("MYARC_JOBS")        -- in M.on_unload / phase exit / _clearState
```

- **Order**: the offers on a board are shuffled every time it is shown, so injected jobs are never reliably first or last.
- **priority 5 (hook)**: always on the board at every matching station, *outside* the normal
  slot count, as soon as `when` holds. Use for story contracts. Hidden only when the
  station refuses all work (reputation below -400, the same rule as the normal board).
- **`ensure = true`** (priority 3 only): guarantee the job is on the station's board. It takes a
  free or expired slot, else replaces a cached ordinary job, and is on the board with no
  special tag, so it reads as regular work that happened to be there. Use it to steer the
  crew without telling them they're being steered (Rezkov's M2 cover deliveries to Galen).
- **priority 3 (seed)**: ordinary-looking work. Each time a station fills a slot there is a
  `JOBS.SEED_CHANCE` (0.4) chance an eligible seed is used instead of a random job; it is
  cached in the slot like any other job. Seeds are for filler that moves crews around.
- **Give a shared `id`** when the same job is offered at several stations (`origin` list)
  so accepting it at one hides the others. `record(cs)` is called once per station.
- Once accepted, a job is gone for the session (`JOBS._done`). Story jobs that *fail*
  (cargo destroyed) come back; completed ones never do.

**Builders**: `JOBS.build(type, opts)` calls the module's `build(opts)`.
- `delivery`: `{origin, dest, cargo, reward, brief, complete_msg, urgent}`
- `salvage`: `{origin, wx, wy, cargo, reward, brief, complete_msg, region_name}`. A pod
  cluster spawns at `(wx, wy)` (world units); Science scans to find the target pod; the
  crew returns it to `origin`.

**Common opts** (every type):

| Opt | Effect |
|---|---|
| `story = true` | Bypasses `max_active`; no expiry timer (unless `time_limit`); no reputation penalty on failure; re-offered after a failure; listed `[SPECIAL]` |
| `time_limit` | Seconds. Gives a story job a clock (still no penalty; it comes back after a miss) |
| `urgent = true` | Salvage: "URGENT:" prefix and the faster duration formula |
| `special = true` | Listed `[SPECIAL]` only (normal rules) |
| `id` | Stable id (see above) |
| `accept_log` | Text for the accept ship log (replaces the generic "N minutes" line) |
| `on_accept(m)`, `on_complete(m)`, `on_fail(m)` | Lifecycle callbacks (pcall'd) |
| `on_found(m)` | **Salvage only**: the target pod was picked up, before the return trip. The natural place for a story reveal |

**Visits**: `JOBS.hasVisited(cs)` is true once the crew has docked at `cs`
(flag `visited_<callsign>`, saved with the campaign). Use it in `when` and in arc triggers
("after they have been to Arbiter").

**Director queue**: `JOBS._dynamic_queue` still works; entries whose `origin` matches are
shown like priority-5 injected jobs.

### Post-mission tick hooks

For work that must continue after a mission completes (e.g. despawn timers),
register a function into the list:

```lua
JOBS._tick_hooks[#JOBS._tick_hooks + 1] = function(now) ... end
```

All hooks are called every `JOBS.update()` cycle regardless of active missions.

---

## MISSION utilities

```lua
MISSION.calcReward(base, type_mult, distance_u, danger_level, dist_min_u, dist_max_u)
    -- Returns reward rounded to nearest 5. distance/danger bonuses applied automatically.

MISSION.nextId()             -- monotonically increasing integer id
MISSION.gridRef(wx, wy)      -- e.g. "C-4"
MISSION.stationFaction(cs)   -- "Concord", "Independent", or nil for unknown/corsair stations
MISSION.weightedPick(list)   -- pick entry by .weight field
MISSION.untrack(id)          -- remove from internal tracking table
MISSION._dynamic_queue       -- list of director-injected missions; engine drains on offer
```

---

## Reward formula

```
reward = base_reward[tier]
       * type_mult
       * distance_bonus      -- 1 + max(0, distance_u/1000 - 10) * 0.01
       * danger_bonus         -- 1 + danger_level * 0.15
-- rounded to nearest 5
```

Danger levels: 0=safe, 1=risky, 2=dangerous, 3=deadly, 4=extremely deadly.

---

## Reputation system

`RT.addReputation(faction, amount, reason)` — unbounded (no clamp). Persisted to campaign save.

**Standard amounts:**
- Job completed: `+mission.reward` (full credit value) with origin faction
- Job expired/failed: `-mission.reward` with origin faction
- Ship destroyed: `-200` with ship's faction (fires automatically from `RT.trackShipForReputation`)
- Ship disabled (boarding): `-100` with Corsairs (fired explicitly in boarding module at disable)

**GM adjustment**: +100 / −100 per button press. Faction list shows live standing; detail sub-menu self-refreshes after each press.

**Job offer reduction by standing** — applied per station based on its faction's rep:

| Standing | Offers shown |
|---|---|
| ≥ 0 | Full (`n_slots`) |
| −1 to −200 | `n_slots − 1` + nag message |
| −201 to −400 | `n_slots − 2` + nag message |
| < −400 | 0 — nag message only |

Logic lives in `_offerMissions()` in `_engine.lua`. Slot storage is unaffected; only the displayed count is clamped. Recovery is immediate when standing crosses back above a threshold.

**Proximity spawn effects** (from CLAUDE.md):
- Corsairs >+20: 50% longer spawn cooldowns
- Corsairs <−20: 30% shorter cooldowns (hunt you)
- Concord >+20: shake-downs dismissed without fine
- Concord <−20: skip shake-down, immediate attack

---

## Registered job types (current)

| Type | Weight | tier_min | mult | Rep on complete | Rep on fail/expire |
|---|---|---|---|---|---|
| `delivery` | 15 | 0 | 1.0 | +reward (origin faction) | −reward |
| `salvage` | 7 | 0 | 1.2 | +reward (origin faction) | −reward |
| `hacking` | 3 | 0 | 1.4 | none (undetected) | none |
| `tailing` | 3 | 0 | 1.3 | +reward (origin faction) | −reward |
| `destroy` | 3 | 0 | 1.6 | +reward (origin faction); −200 Corsairs on kill | −reward |
| `boarding` | 3 | 0 | 1.8 | +reward (origin faction); −100 Corsairs on disable | −reward |
| `escort` | 3 | 0 | 1.5 | +reward (origin faction) | −reward |

---

## Escort specifics

- Convoy: `"Flavia"` (NPC template — NOT `"Flavia P.Falcon"` which is a player template and won't accept AI orders), Independent, impulse-only (~125 u/s), no weapons
- Escort fighters: 2× MT52 Hornet, Independent, impulse-only (~200 u/s)
- Fighter names: drawn without replacement from `_ESCORT_NAMES` pool (30 bird/indie-flight names)
- Convoy switches from `orderFlyTowards` → `orderDock` when within 5U of destination
- Post-mission: fighters get dismissal comms, fly to a random third station, despawn after 5 min via `_tickDeparting` in `JOBS._tick_hooks`
- Intercept waves: 3× MT52 Hornet Corsairs, ±45° ahead of convoy at 10U, `orderRoaming()`
