# How the sandbox campaign is expanded

The sandbox campaign is built in layers. The core world exists without any
enhancement; each layer adds content independently without modifying what came
before it.

---

## The layers

```
VERSE / core                  — the world: stations, regions, factions, traffic
  ├── JOBS                    — player economy: paid contracts, job boards
  ├── RUMORS                  — information economy: circulating intel, quest hooks
  ├── WORLD plugins           — ambient features: patrols, defenders, weather
  └── MISSIONS arcs           — story arcs: multi-phase scripted events
```

### The core world (VERSE + core)

`verse.lua` builds the physical world from data: stations with positions and
factions, region volumes with danger levels, freighter traffic routes, salvage
fields, scan probes, asteroid belts. Stations have comms menus with basic
"buy fuel", "restock missiles", and "any news?" options. Freighters have
travel comms with "where are you headed?" and "heard any news?" options.

`core.lua` manages the campaign save: player ship, credits, upgrades,
objectives, station hooks. Everything in the core world works without JOBS,
MISSIONS, or WORLD plugins loaded — it's a complete universe the crew can
fly around in.

The universe is defined in `verse/drift.lua` (base) and
`verse/extensions/*.lua` (community additions). **Never rename or remove a
place in drift.lua.** Extensions are append-only.

### JOBS — the player economy

JOBS is the job board. When a player docks and hails "Any work available?",
the engine generates 2 offers from the registered contract types and displays
them. Each contract type is a module in `ee/ragtag/jobs/`.

JOBS is part of the core campaign (always loaded) but the individual contract
types are optional. The sandbox ships delivery, salvage, hacking, boarding,
destroy, escort, and tailing. New types can be added without changing anything
else.

### RUMORS — the information economy

RUMORS is the rumor system. Every "heard any news?" comms reply on both
freighters and stations pulls from the unified RUMORS pool. Rumors have:
- `text` — what the NPC says
- `priority` (1–10) — higher priority cuts through the 5-minute cooldown
- `faction` — optional filter; `nil` means any NPC can deliver it
- `category` — optional string key for bulk removal
- `once` — if `true`, removes itself after first delivery

The background pool (priority 1) cycles through all entries before repeating.
Priority 2+ rumors bypass the cooldown entirely, so quest hooks always reach
the player. One-shot rumors (`once=true`) are discarded after delivery;
recycled rumors stay in the pool until explicitly removed.

### WORLD plugins — ambient features

WORLD plugins run every frame, independent of player actions. They manage
their own state through the WORLD engine's lazy-init lifecycle and can be
toggled on/off by the GM at runtime. Current plugins:

| id | Purpose |
|---|---|
| `defenders` | One MT52 Hornet loiters at each Concord/Independent station; respawns |
| `proximity` | Zone-based faction patrols; per-zone intensity (None/Low/Medium/High) |
| `salvage` | Dynamic debris clusters; density (Low/Medium/High) and reward settings |
| `traffic` | Freighter routes and ambient crate drops; density (Low/Medium/High) |

### MISSIONS arcs — story events

MISSIONS arcs are multi-phase scripted events with trigger conditions, GM
controls, and optional player choices. Each arc is a module in
`ee/ragtag/missions/`. Current arcs: `witness` (the Kael Voss arc).

---

## Cross-layer integration

### Missions and rumors

Missions can inject rumors to set up their arc and clear them when done:

```lua
-- Inject background lore (priority 1, recycled, cleared on arc complete):
RUMORS.add({ text = "...", priority = 1, category = "MY_ARC_BACKGROUND" })

-- Inject a quest hook (priority 5, one-shot, visible during offer phase):
RUMORS.add({ text = "Someone at Port Vesper is asking for a discreet crew...",
             priority = 5, category = "MY_ARC_HOOK", once = true })

-- Clean up when the player accepts or the arc ends:
RUMORS.removeCategory("MY_ARC_HOOK")
RUMORS.removeCategory("MY_ARC_BACKGROUND")  -- in M.resolve
```

Priority-5 rumors bypass the cooldown, so even a player who just asked for
news will get the quest hook on the next hail to any ship or station. One-shot
rumors disappear after one delivery; the category bulk-removal sweeps up any
that weren't delivered.

### Missions and jobs

Missions can lock the job board while an arc runs:

```lua
M.locks_jobs = true  -- JOBS.config.jobboard_locked set true on start, false on done/cancel
```

Missions can also post dynamic jobs directly via the director:

```lua
DIR.ACTIONS.create_delivery = function(a) ... table.insert(JOBS._dynamic_queue, job) end
```

### World plugins and proximity

Missions that need to suppress ambient patrols (e.g. a scripted encounter
takes over):

```lua
S.witness_active = true   -- checked by the proximity plugin's spawning logic
```

---

## Adding content

### Adding a VERSE extension (new stations, regions)

1. Create `ee/ragtag/verse/extensions/<name>.lua` — copy the example in
   `docs/examples/extension_example.lua`.
2. Run `python tools/check.py --fix` to regenerate the index.

### Adding a contract type (JOBS)

1. Create `ee/ragtag/jobs/<type>.lua` — copy an existing type as a template.
2. Add `require("ragtag/jobs/<type>.lua")` to `ee/ragtag/jobs.lua`.
3. Run `python tools/check.py`.

**Job cleanup**: jobs must clean up their spawned entities and state when
completed, failed, or abandoned. Every job record should handle all three
outcomes:
- `JOBS.complete(job)` — success path; give reward, clear spawns, log result
- `JOBS.fail(job)` — failure path; clear spawns, log result, no reward
- **Abandoned jobs** (player ignores for too long): call `JOBS.untrack(job.id)`
  after a timeout. Each job type is responsible for its own timeout in its
  `update()` function. A good default is 20–30 minutes after the job board
  showed the offer. Check `getScenarioTime() - job.started_at > timeout`.

Never leave spawned NPC ships or beacons orphaned. If an update tick fires and
the job's target entity is no longer valid, treat it as auto-failed rather than
looping forever.

### Adding a WORLD plugin (ambient features)

1. Create `ee/ragtag/world/<name>.lua` with a `WORLD.register(_P)` call.
2. Add `require("ragtag/world/<name>.lua")` to `ee/ragtag/world.lua`.
3. Run `python tools/check.py`.

```lua
local _P = {}
_P.id      = "my_plugin"
_P.name    = "My Plugin"
_P.defaults = { interval = 30 }

function _P.init(state)   state.timer = 0                                    end
function _P.update(state, delta, now)
    -- use WORLD.get("my_plugin", "interval", 30) for runtime-tunable params
end
function _P.cleanup(state) end   -- destroy spawned objects here

WORLD.register(_P)
```

### Adding a MISSIONS arc (story events)

1. Create `ee/ragtag/missions/<arc>.lua` with a `MISSIONS.register(M)` call.
2. Add `require("ragtag/missions/<arc>.lua")` to `ee/ragtag/missions.lua`.
3. Run `python tools/check.py`.

**CRITICAL**: use `MISSIONS.phase(id, "name")` to transition — **NOT**
`MISSIONS.goto()`. `goto` is a reserved keyword in Lua 5.4 and causes a
syntax error.

---

## Quick decision guide

| I want to add… | Use |
|---|---|
| A new station, region, or asteroid field | VERSE extension |
| A new paid contract the job board can offer | JOBS type module |
| Background lore or faction chatter | `RUMORS.add({priority=1})` |
| A quest hook that steers the player somewhere | `RUMORS.add({priority=5, once=true})` |
| A new persistent ambient feature (patrols, weather) | WORLD plugin |
| A new multi-phase story arc | MISSIONS arc module |

---

## Key constraints (don't break these)

- **Universe stability**: never rename or remove a place in `verse/drift.lua`.
  `check.py` lists every scenario that depends on each place.
- **Extensions only add**: new places go in `verse/extensions/`, not drift.
- **MISSIONS.phase(), not MISSIONS.goto()**: `goto` is reserved in Lua 5.4.
- **Generated files**: `check.py --fix` regenerates `extensions/index.lua`,
  `director/generated/world.md`, and `docs/verse_map.svg`. Never hand-edit.
- **Jobs clean up**: every contract type handles complete, fail, and timeout.
  Orphaned NPC ships and beacons are a session reliability bug.
