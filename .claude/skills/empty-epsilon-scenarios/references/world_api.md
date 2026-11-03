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

No `PROX.init()` or `PROX.update()` calls needed — the proximity plugin is
handled automatically by `WORLD.update()`.

---

## Registered plugins (current)

| id | Name | Notes |
|---|---|---|
| `defenders` | Station Defenders | One MT52 Hornet per Concord/Independent station; respawns on death |
| `proximity` | Proximity Spawns | Ambient faction patrols; zone-based; GM-controllable spawn mode |

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

## Proximity plugin

Zone-based ambient patrol spawns that create predictable risk zones players
learn to navigate. Ships spawn ahead of the player, leash to their region,
and despawn when the player leaves.

### Spawn mode (GM control)

The scenario's GM button cycles four modes via `PROX.cycleMode()` / `PROX.getModeName()`:

| Mode | Freq | Max ships | Density cap |
|---|---|---|---|
| None | 0 | 0 | 0 |
| Low | 0.5x | 6 | 3 |
| Medium (default) | 1.0x | 12 | 6 |
| High | 2.0x | 24 | 12 |

### Zone definitions (`PROX.zones`)

| Region | Faction | Comms |
|---|---|---|
| the Concord Core | Concord | shakedown |
| the Arbiter Line | Concord | shakedown |
| the Shroud | Corsairs | taunt |
| Halcyon Rest | Corsairs | taunt |
| the Gauntlet | Corsairs | taunt |
| Blackwater Reach | Corsairs | taunt |
| the Boneyard | Relic | silent |
| the Maw | Hollow | silent |

### Shakedown (Concord)

Concord patrols in non-wanted mode open comms and request inspection rather
than attacking. Players can submit, declare clean cargo, or refuse. Refusing
issues a `wanted` flag; submitting or complying may levy a fine scaled to
current credits.

### Config defaults

| Key | Default | Effect |
|---|---|---|
| `check_interval` | `8` | Seconds between proximity checks |
| `global_cooldown` | `120` | Min seconds between any spawn (scaled by mode freq) |
| `station_exclusion_u` | `20` | No spawns within this radius of any station |
| `recall_timeout` | `120` | Seconds before a recalled group despawns |
| `spawn_mode_idx` | `3` | Starting mode index (1=None, 2=Low, 3=Medium, 4=High) |

Override: `WORLD.set("proximity", "global_cooldown", 60)`

### Jobboard lock

When `JOBS.config.jobboard_locked` is true, new spawns are suppressed but the
watchdog still cleans up existing groups.

### PROX shims

The `PROX` global still exists for GM-menu compatibility:

```lua
PROX.getModeName()             -- returns current mode name string
PROX.cycleMode()               -- advances to next mode
PROX.addExclusion(cs, r_u)     -- adds a no-spawn bubble around station 'cs'
PROX.zones                     -- zone configuration table (read/write)
```
