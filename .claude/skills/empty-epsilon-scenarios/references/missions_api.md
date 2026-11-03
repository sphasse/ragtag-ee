# MISSIONS engine reference

The MISSIONS engine is a modular story-arc system. Each arc is a
self-contained phase machine in `ee/ragtag/missions/`. Load everything with
`require("ragtag/missions.lua")` in the scenario after the JOBS require.

---

## Authoring a mission module

Create `ee/ragtag/missions/<name>.lua`. At the bottom call `MISSIONS.register(M)`.
Add `require("ragtag/missions/<name>.lua")` to `ee/ragtag/missions.lua`.

### Required fields

| Field | Type | Notes |
|---|---|---|
| `M.id` | string | Unique key, e.g. `"witness"` |
| `M.name` | string | Display name shown in GM menu |
| `M.phases` | table | Map of `phase_name → {enter, update, exit}` |
| `M.start_phase` | string | Phase entered on `MISSIONS.start(id)` |

### Optional fields

| Field | Type | Notes |
|---|---|---|
| `M.phase_order` | list | Ordered phase names for GM jump buttons |
| `M.locks_jobs` | bool | Set `JOBS.config.jobboard_locked` while active |
| `M.auto_start` | bool | Auto-launch when all trigger conditions met (default false) |
| `M.triggers` | table | See **Trigger conditions** below |
| `M.gm_actions` | list | `{{label=string, fn=fn(st)}}` shown in GM detail while active |
| `M.init_state()` | function | Returns fresh mutable state table for each run |
| `M.resolve(st)` | function | Called when entering the terminal `"done"` phase |
| `M.on_cancel(st)` | function | Called on `MISSIONS.cancel(id)`; clean up world objects here |

### Phase definition

```lua
M.phases = {
    my_phase = {
        enter  = function(st) ... end,   -- optional; runs on phase entry
        update = function(st, delta, now) ... end,  -- optional; runs every frame
        exit   = function(st) ... end,   -- optional; runs before leaving phase
        no_skip = true,                  -- optional; hides phase from GM jump buttons
    },
    done = {},  -- terminal; triggers M.resolve(st)
}
```

---

## Trigger conditions

`M.triggers` gates when status flips from `"inactive"` to `"triggered"`.
All conditions must be true simultaneously.

```lua
M.triggers = {
    rep_min      = {Corsairs = 20},        -- faction rep >= value
    rep_max      = {Concord  = -10},       -- faction rep <= value
    upgrades_min = 200,                    -- total credits spent on upgrades >= value
    not_flagged  = {"witness_complete"},   -- RT.flag(name) must be falsy for each
    custom       = function(st) return ... end,  -- any extra condition
}
```

Trigger checking runs every frame in `MISSIONS.update(delta)`. When
conditions are met but `auto_start = false`, status becomes `"triggered"`,
which appends `[READY]` to the GM Missions button. When `auto_start = true`,
the mission starts automatically.

---

## Engine API

```lua
MISSIONS.register(M)         -- called by each module at load time
MISSIONS.start(id)           -- activate; init_state, lock jobs, enter start_phase
MISSIONS.phase(id, name)     -- transition to named phase (NOTE: not .goto — reserved keyword)
MISSIONS.cancel(id)          -- exit current phase, call on_cancel, unlock jobs
MISSIONS.update(delta)       -- call every frame from scenario update()
MISSIONS.addGMButton(backFn) -- single top-level GM button (self-labels [READY] when any triggered)
```

**Important**: the transition function is `MISSIONS.phase()`, NOT `MISSIONS.goto()`.
`goto` is a reserved keyword in Lua 5.4 and will cause a syntax error.

### Status values

| Status | Meaning |
|---|---|
| `"inactive"` | Not started; triggers not met (or no triggers defined) |
| `"triggered"` | Triggers met; waiting for GM to start |
| `"active"` | Running; current phase in `MISSIONS._cur_phase[id]` |
| `"done"` | Resolved; `M.resolve(st)` has been called |
| `"cancelled"` | Cancelled; `M.on_cancel(st)` has been called |

---

## Scenario wiring

```lua
-- In init():
require("ragtag/missions.lua")  -- already at top of file

-- In update(delta):
MISSIONS.update(delta)

-- In addSessionGMFunctions():
MISSIONS.addGMButton(function()
    clearGMFunctions()
    addSessionGMFunctions()
end)
```

---

## GM menu

The engine provides a three-level GM UI with one button per scenario:

1. **"Missions..."** (or **"Missions [READY]..."** when any mission is triggered)
2. **Mission list** — one row per registered mission with status/phase label
3. **Mission detail** — Start button (if inactive/triggered), phase jump buttons
   (from `M.phase_order`, skipping `no_skip` and current phase), custom
   `M.gm_actions`, and Cancel button (if active)

Phase jump buttons call `MISSIONS.phase(id, pname)` directly — useful for
skipping slow-travel phases during testing.

---

## Registered missions (current)

| id | Name | locks_jobs | Trigger | Phases |
|---|---|---|---|---|
| `witness` | The Witness | yes | not_flagged: witness_complete | offer, transit, checkpoint, revealed, shroud_run, halcyon, broadcast |

---

## Common patterns

### Spawning a world object in enter, destroying in on_cancel

```lua
M.phases = {
    transit = {
        enter = function(st)
            st.ship = CpuShip():setTemplate("Flavia"):setPosition(x, y)
            st.ship:orderFlyTowards(RT.find("Port Vesper"))
        end,
    },
}
M.on_cancel = function(st)
    if RT.valid(st.ship) then st.ship:destroy() end
end
```

### Using RT.after inside a phase

`RT.after` timers survive phase transitions — cancel them explicitly in
`exit` if they should not fire after the phase ends.

### Checking active phase from outside the engine

```lua
if MISSIONS._status["witness"] == "active"
   and MISSIONS._cur_phase["witness"] == "broadcast" then
    -- ...
end
```

Use `RT.flag("witness_complete")` for cross-session state; `_status` is
session-only and starts as `"inactive"` each run.
