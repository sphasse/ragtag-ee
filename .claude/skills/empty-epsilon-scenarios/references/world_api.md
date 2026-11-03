# World plugin API reference

The WORLD engine hosts ambient, persistent session features — things that run
the whole time, independent of story arcs (MISSIONS) or player-triggered jobs
(JOBS). Load everything with `require("ragtag/world.lua")`.

---

## Authoring a world plugin

Create `ee/ragtag/world/<name>.lua`. At the bottom call `WORLD.register(_P)`.
Add `require("ragtag/world/<name>.lua")` to `ee/ragtag/world.lua`.

### Module interface

| Field | Type | Notes |
|---|---|---|
| `P.id` | string | Unique key, e.g. `"defenders"` |
| `P.name` | string | Human-readable name for logs |
| `P.defaults` | table | Default config values — overridable at runtime via `WORLD.set` |
| `P.default_enabled` | bool | `false` = starts disabled (default: true) |
| `P.init(state)` | function | Called once before the first update tick |
| `P.update(state, delta, now)` | function | Called every frame while enabled |
| `P.cleanup(state)` | function | Called when disabled mid-session |

`state` is a fresh Lua table owned by the engine; use it for all mutable plugin state.

### Example skeleton

```lua
local _P = {}
_P.id   = "my_plugin"
_P.name = "My Plugin"
_P.defaults = { some_value = 42 }

function _P.init(state)
    state.counter = 0
end

function _P.update(state, delta, now)
    state.counter = state.counter + delta
    local cfg = WORLD.get("my_plugin", "some_value", 42)
    -- ...
end

WORLD.register(_P)
```

---

## Engine API

```lua
WORLD.register(P)              -- called by each plugin at load time
WORLD.get(id, key, fallback)   -- read config (runtime override > defaults > fallback)
WORLD.set(id, key, value)      -- write a runtime config override
WORLD.enable(id)               -- enable plugin (re-inits state)
WORLD.disable(id)              -- disable + call cleanup
WORLD.update(delta)            -- call every frame from scenario update()
```

---

## Scenario wiring

```lua
-- In scenario file top:
require("ragtag/world.lua")   -- after core/verse/jobs/missions

-- In update(delta):
WORLD.update(delta)
```

---

## Registered plugins (current)

| id | Name | Factions | Notes |
|---|---|---|---|
| `defenders` | Station Defenders | Concord, Independent | One fighter per station; respawns on death |

---

## Defenders plugin

Each Concord and Independent station gets one `MT52 Hornet` defender.
The defender idles near the station on `orderDefendTarget`. When killed,
a new one spawns after a 120s cooldown.

### Config

| Key | Default | Effect |
|---|---|---|
| `template` | `"MT52 Hornet"` | Ship template for all defenders |
| `respawn_secs` | `120` | Cooldown after death |
| `orbit_range_ku` | `3` | Base spawn/orbit distance from station in kU (actual: +0-2kU random) |
| `order_radius_u` | `20000` | Meters searched when ordered to attack a target |
| `factions` | `{"Concord","Independent"}` | Which station factions get defenders |

Override at runtime: `WORLD.set("defenders", "respawn_secs", 60)`

### Name pools

Independent defenders draw from ~35 scrappy frontier callsigns (Dusthawk,
Freehold, Grey Sovereign, …). Concord defenders draw from ~20 `CPV <Name>`
patrol designations (CPV Longwatch, CPV Vigil, …). Names are de-duplicated
across live defenders.

### Player-order hook

Defenders accept player orders if a flag is set:

```lua
RT.flag("defender_cmds_independent", true)  -- Indie defenders accept orders
RT.flag("defender_cmds_concord",     true)  -- Concord defenders accept orders
```

When the flag is set, the defender's comms offer three choices:
1. **Attack nearest hostile** — `orderAttack` on the closest enemy within 20U
2. **Defend our ship** — `orderDefendTarget(player)`
3. **Return to station** — `orderDefendTarget(station)` (reset to default)

These flags are `false` by default and intended to be set by a future mission
arc that grants the player local military authority.

### Comms tone

- Independent: casual, hired-gun flavour — *"Station keeps me fed; I keep trouble off their hull."*
- Concord: curt, institutional — *"You are being logged. State your business."*

---

## Future: migrating proximity spawns

`ee/ragtag/proximity.lua` contains the same ambient-update pattern and would
fit naturally as a world plugin. To migrate:

1. Wrap its logic in a `_P` module with `_P.init` / `_P.update`.
2. Move PROX config into `_P.defaults`.
3. Register it and add `require("ragtag/world/proximity.lua")` to `world.lua`.
4. Replace `PROX.update(delta)` in the scenario with `WORLD.update(delta)`.
