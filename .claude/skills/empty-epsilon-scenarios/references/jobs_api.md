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
| `work_cooldown_secs` | `600` | Cooldown in seconds (10 min): how long an untaken offer stands |
| `refill_secs` | `nil` | How long a TAKEN slot stays empty (nil: `work_cooldown_secs`). The Short Haul sets 0: a taken job is replaced at once without re-rolling the rest |
| `mission_distance_mode` | `"medium"` | `"short"` / `"medium"` / `"long"` |
| `jobboard_locked` | `false` | Set `true` by an arc (`M.locks_jobs`) to hide the board; also stops new patrols |
| `max_active` | `2` | Max simultaneously active contracts, per ship |
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
JOBS.maxTier(ship)           -- 0/1/2 from that ship's own upgrade spend (no ship = the primary ship)
JOBS.board(cs, ship)         -- what station cs offers ship now: {offers, nag, closed, slots_failed, wait}
JOBS.updateObj()             -- refreshes objective display and relay panel
JOBS.stationHook(src, tgt)   -- wire into station setCommsFunction
JOBS.inject(def) / JOBS.removeCategory(cat) / JOBS.build(type, opts) / JOBS.hasVisited(cs)
                             -- story-arc injection, see "Injected jobs" below
```

### Ownership: several ships on one board

More than one player ship can work the board. **A job belongs to the ship that took it**
(`m.ship`, set by `JOBS.accept(m, skip_log, ship)`; `entry.ship` in `JOBS._active`):

- only the owner advances the job (its position, docking and scans are the ones that count),
  completes it, is paid, gets the job's log lines and hails, and gains or loses standing;
- other player ships can neither help nor sabotage: flying up to another ship's target does
  not provoke or spook it, docking with it does not board it, and a salvage container another
  ship runs into is put back once that ship has moved off;
- each ship has its own cap (`JOBS.config.max_active`), its own Relay job panel, its own
  credits and its own standing; the board is shared, so a job one ship takes is gone for the rest;
- everything an arc injects (`JOBS.inject`: story contracts AND priority-3 seeds, ensured or not)
  is offered to, and can be taken by, the primary ship only, because story arcs belong to that ship.
  A seed sitting in one of the station's shared slots is hidden from other ships. `any_ship = true`
  on `JOBS.inject` marks work that is not an arc's (the test harness's `T.postJob`) as open to all,
  and `for_ship = <ship>` as open to that one ship only (the GM's New delivery); `JOBS._openTo(m, ship)`
  is the one check, used by the board and `JOBS.accept`. `JOBS.removeInjected(id)` takes one entry off;
- a job module keeps the ENTITIES it spawns on the job record (`m.target`, `m.rendezvous`,
  `m.convoy`, `m.fighters`) and uses those; `m.target_cs` and friends are only the names, for
  log lines. Never find a job's ship again with `RT.find`: two ships can share a callsign;
- a job whose ship is destroyed is dropped and cleaned up, at no cost to anyone.

In a job module, never use `RT.players`, `RT.forEachPlayer`, `RT.shipLog`, `RT.hail` or
`RT.addReputation` (`check.py` rejects them). Use:

```lua
JOBS.owner(m)                 -- the owning ship while it is alive, else nil
JOBS.ships(m)                 -- {owner} or {}: for _, p in ipairs(JOBS.ships(m)) do ... end
JOBS.log(m, text, color)      -- ship log line for the owner
JOBS.hail(m, from, text)      -- hail the owner from an entity; false when comms are busy
JOBS.rep(m, faction, amount, reason)   -- change the owner's standing
JOBS.activeFor(ship)          -- that ship's active entries
```

A comms function on something the job spawned (a convoy taking orders) checks
`if src ~= m.ship then ... return end` before offering choices.

Two engine facts to know. **Scans are per faction**: every player ship is Independent, so a scan
made by one ship counts for all of them (`isScannedBy(owner)` is true after another ship's scan).
**Reputation points are per faction too**, which is why credits are not kept there: see "Credits" under the reputation section.

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

- **No duplicates**: two offers on one board never share a summary (type + `short` text, e.g. the same cargo to the same station). A generated job that collides is re-rolled (up to 4 times); a final pass drops any remaining collision, keeping story and ensured jobs over generated ones. Give injected jobs distinct `short` text.
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

**How the board is built**: `JOBS.board(cs, ship)` decides the offers and makes no comms calls
(so it can be called from a test): the reputation gate, the per-slot cooldown, cached offers,
ensured seeds, one new job per free slot (a seed or a generated job), story contracts on top,
de-duplication, shuffle. A small renderer (`_showBoard`) puts the result in the comms window.

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

`RT.addReputation(faction, amount, reason, ship)` / `RT.getReputation(faction, ship)` — unbounded
(no clamp). Standing is per ship, kept in the ship's record (`RT.shipRecord(ship)`): the primary
ship's is the campaign's (used by story arcs and patrols); every other player ship has its own,
starting at 0 and saved under its callsign. Job modules go through `JOBS.rep(m, ...)`. Outside
story arcs the `ship` argument is required (`check.py`).

**Credits** are per ship as well: `RT.credits(ship)`, `RT.addCredits(amount, reason, ship)`,
`RT.setCredits(amount, ship)` (no ship = the primary ship). They are kept by `core.lua`, not in
EmptyEpsilon's reputation points: the engine stores those per *faction*, so every Independent
player ship would share one number. The engine number is unused and held at 0 (the stock
"Reputation" readout reads 0); each ship shows its balance as a `Credits: N` line on Relay and
Operations. Saved with the campaign: the primary ship's as `campaign.credits`, other ships'
balance, standing and upgrades under `campaign.extra_ships` by callsign, restored when a ship of
that name joins. Never call the `ReputationPoints` methods outside `core.lua` (`check.py` rejects it).

**Upgrades** are per ship too (`RT.upgrades(ship)`, `RT.hasUpgrade(id, ship)`): a ship that buys
one pays for it and is the only ship that has it, and `JOBS.maxTier(ship)` follows that ship's
own spend.

**Standard amounts:**
- Job completed: `+mission.reward` (full credit value) with origin faction
- Job expired/failed: `-mission.reward` with origin faction
- Ship destroyed: `-200` with ship's faction, charged to the ship that made the kill
  (`RT.trackShipForReputation`). NOTE: `RT.register` is meant to switch this on for every CpuShip
  but its type test never matches, so today the penalty only applies to ships a module tracks
  explicitly (see the comment in `RT.register`)
- Ship disabled (boarding): `-100` with Corsairs (fired explicitly in boarding module at disable)

**GM adjustment**: +50 / −50 per button press, on the ship the GM picks (Reputation... lists the ships when there are several). Faction list shows live standing; detail sub-menu self-refreshes after each press.

**Job offer reduction by standing** — applied per station based on its faction's rep:

| Standing | Offers shown |
|---|---|
| ≥ 0 | Full (`n_slots`) |
| −1 to −200 | `n_slots − 1` + nag message |
| −201 to −400 | `n_slots − 2` + nag message |
| < −400 | 0 — nag message only |

Logic lives in `_repGate()` (called by `JOBS.board`) in `_engine.lua`, judged by the asking ship's own standing. Slot storage is unaffected; only the displayed count is clamped. Recovery is immediate when standing crosses back above a threshold.

**Proximity spawn effects** (`ee/ragtag/world/proximity.lua`; the standing of the ship the patrol hunts, `group.target`):
- Corsairs ≤ −200: 30% shorter spawn cooldowns; ≤ −400: 50% shorter
- Concord shake-down outcome by standing: ≥ 500 recognised, ≥ 200 clean pass, ≥ 0 nothing flagged,
  ≥ −200 a 100 cr fine, < −200 no shake-down: patrols spawn hostile

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
| `tow` | 6 / 4 / 2 by tier | 0 | 1.2 | +reward (origin faction) | −reward |

**`tow`** (`jobs/tow.lua`): a broken-down ship (no engines, can't be destroyed) somewhere quiet (danger 0, no patrol
zone, within 60U); the crew puts a tow line on it (`TOW`, `ee/ragtag/tow.lua`: Engineering's "Attach tow line" within
2U, for the job's ship only; up to half of warp 1, 15U a minute, which takes Engineering's warp power at ~50%
and Science's "Tow speed" readout; hauling costs energy) and brings it within 4U of the port that got the call,
then docks to be paid. Basic work: its tier weight drops 6 → 4 → 2 as the ship's tier rises (`_TIER_WEIGHTS`).
Raiders: once the asking ship has upgraded, a tow may draw Shroud Raiders (`RAIDER_ODDS`, rolled at generation from
`ctx.max_tier`, the ship's own `JOBS.maxTier`: none at tier 0, 0–1 at tier 1, 0–2 at tier 2; +15% pay a raider, "Raiders
about." on the board, a warning in the brief). They are `TOW.intercept` (`ee/ragtag/tow.lua`, shared with Ice Haul):
the first time the line goes on they appear 10U out (impulse 1.2 × `TOW.MAX_SPEED`, 300: a tow can't outrun them), their
leader hails the crew to cut her loose, and they attack at once; they break off when the tow is home (`TOW.breakOff`) and
are removed when the job ends (`TOW.removeRaiders`).

**Optional module fields for the board's text:** `M.ack_label` names the button under the job details shown after
"Take:" (default "Back"; the tow job: "We'll get 'em home"), and `M.accept_outro` replaces the line added after the
brief (default "Come back when it's done.", nothing for deliveries; the tow job: nothing).

---

## Escort specifics

- Convoy: `"Flavia"` (NPC template — NOT `"Flavia P.Falcon"` which is a player template and won't accept AI orders), Independent, impulse-only (~125 u/s), no weapons
- Escort fighters: 2× MT52 Hornet, Independent, impulse-only (~200 u/s)
- Fighter names: drawn without replacement from `_ESCORT_NAMES` pool (30 bird/indie-flight names)
- Convoy switches from `orderFlyTowards` → `orderDock` when within 5U of destination
- Post-mission: fighters get dismissal comms, fly to a random third station, despawn after 5 min via `_tickDeparting` in `JOBS._tick_hooks`
- Intercept waves: 3× MT52 Hornet Corsairs, ±45° ahead of convoy at 10U, `orderRoaming()`
