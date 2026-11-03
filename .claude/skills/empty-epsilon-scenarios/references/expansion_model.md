# How the sandbox campaign is expanded

Three independent layers let contributors add content without touching core
engine code. Pick the right layer for what you're building.

---

## The three layers

```
Universe (VERSE)       — places, regions, factions; shared by all scenarios
  └── Jobs (JOBS)      — player-triggered economy; one module per contract type
  └── Missions (MISSIONS) — story arcs; one module per arc
  └── World (WORLD)    — ambient session features; one module per feature
```

### When to use each

| You want to add… | Use |
|---|---|
| A new station, region, or asteroid field | VERSE extension |
| A new type of paid contract (delivery, hacking, …) | JOBS type module |
| A new multi-phase story arc | MISSIONS arc module |
| A new persistent ambient feature (patrols, weather, events) | WORLD plugin |

---

## Jobs — new contract types

Jobs are player-triggered tasks offered at stations. Each contract **type**
is a self-contained module in `ee/ragtag/jobs/`.

### Adding a contract type

1. Create `ee/ragtag/jobs/<type>.lua` with a `JOBS.registerType(T)` call.
2. Add `require("ragtag/jobs/<type>.lua")` to `ee/ragtag/jobs.lua`.
3. Run `python tools/check.py`.

### Type module interface

```lua
T.id          = "my_type"
T.label       = "My Contract"
T.weight      = 5            -- weighted random selection when generating offers
T.base_mult   = 1.2          -- reward multiplier relative to delivery (1.0)
T.min_tier    = 0            -- player upgrade tier gate

-- Called by JOBS to generate one offer at station 'cs', player tier 'tier'.
-- Return a job record table, or nil to skip.
function T.generate(cs, tier, opts)
    return {
        type        = T.id,
        title       = "...",
        desc        = "...",
        reward      = JOBS.calcReward(T.base_mult, distance_u, danger_level),
        -- type-specific fields:
        destination = opts.nearby_station,
        cargo       = "Illegal Goods",
    }
end

-- Called when the player accepts the offer.
function T.accept(job)  ... end

-- Called every update() while the job is active.
-- Call JOBS.complete(job) or JOBS.fail(job) when done.
function T.update(job, delta)  ... end
```

See `references/jobs_api.md` for the full API including reward formula,
faction filtering, and reputation effects.

---

## Missions — story arcs

Missions are multi-phase story arcs with scripted beats and trigger conditions.
Each arc is a self-contained module in `ee/ragtag/missions/`.

### Adding a mission arc

1. Create `ee/ragtag/missions/<arc>.lua` with a `MISSIONS.register(M)` call.
2. Add `require("ragtag/missions/<arc>.lua")` to `ee/ragtag/missions.lua`.
3. Run `python tools/check.py`.

### Arc module interface

```lua
local M = {}
M.id          = "my_arc"
M.name        = "My Arc"
M.locks_jobs  = false        -- true: job board paused while arc runs

-- Trigger conditions (all must pass for the arc to become available):
M.triggers = {
    not_flagged   = {"my_arc_complete"},  -- campaign flags that must be absent
    upgrades_min  = 50,                   -- minimum upgrade count
    rep_min       = {faction="Corsairs", amount=-10},
    custom        = function() return S.some_condition end,
}

-- Phase definitions: each key is a phase name.
-- MISSIONS.phase(M.id, "next_phase") transitions between phases.
M.phases = {
    offer = {
        enter = function(st) ... end,
        update = function(st, delta) ... end,
        exit = function(st) ... end,
    },
    active = { ... },
    done   = { ... },
}

-- Called once when arc starts.
function M.on_start(st) ... end

MISSIONS.register(M)
```

**Key constraint**: use `MISSIONS.phase(id, name)` to transition — NOT
`MISSIONS.goto()`. `goto` is a reserved keyword in Lua 5.4 and causes a
syntax error.

See `references/missions_api.md` for the full API including GM menu wiring,
trigger conditions, and the Witness arc as a reference implementation.

---

## World plugins — ambient features

World plugins run every frame, independent of player actions. Each plugin
manages its own state through the WORLD engine's lazy-init lifecycle.

### Adding a world plugin

1. Create `ee/ragtag/world/<name>.lua` with a `WORLD.register(_P)` call.
2. Add `require("ragtag/world/<name>.lua")` to `ee/ragtag/world.lua`.
3. Run `python tools/check.py`.

### Plugin module interface

```lua
local _P = {}
_P.id   = "my_plugin"
_P.name = "My Plugin"
_P.defaults = { interval = 30 }   -- overridable via WORLD.set()

-- Called once before the first update tick.
function _P.init(state)
    state.timer = 0
end

-- Called every frame while enabled.
function _P.update(state, delta, now)
    state.timer = state.timer + delta
    local interval = WORLD.get("my_plugin", "interval", 30)
    if state.timer >= interval then
        state.timer = 0
        -- do something
    end
end

-- Called when disabled mid-session (optional).
function _P.cleanup(state)
    -- destroy any spawned objects
end

WORLD.register(_P)
```

### Current plugins

| id | Purpose |
|---|---|
| `defenders` | One MT52 Hornet loiters at each Concord/Independent station; respawns |
| `proximity` | Zone-based ambient faction patrols; shakedowns; leash/despawn |

See `references/world_api.md` for full plugin documentation.

---

## Key contracts

- **Universe stability**: never rename or remove a place in `verse/drift.lua`
  that a scenario depends on. `check.py` lists every dependent scenario.
- **Extensions only add**: add new places in `verse/extensions/`, not drift.
- **MISSIONS.phase(), not MISSIONS.goto()**: `goto` is reserved in Lua 5.4.
- **PROX shims**: `PROX.getModeName()`, `PROX.cycleMode()`, `PROX.addExclusion()`
  remain usable in scenario GM menus even though PROX state is now inside the
  WORLD engine.
- **Generated files**: `check.py --fix` regenerates `extensions/index.lua`,
  `director/generated/world.md`, and `docs/verse_map.svg`. Never hand-edit.
