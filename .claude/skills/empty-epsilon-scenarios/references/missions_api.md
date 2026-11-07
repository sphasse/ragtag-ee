# MISSIONS engine reference

The MISSIONS engine is a modular story-arc system. Each arc is a **self-contained** phase
machine in `ee/ragtag/missions/`. Missions must be decoupled from core gameplay: they must
function (or gracefully do nothing) even if the player never encounters them, and core systems
(jobs board, reputation, proximity spawns) must work with no arc active.

**Mission-specific design notes go in a per-mission doc (`ee/ragtag/missions/<name>.md`),
not in CLAUDE.md or this reference.** The module itself is the authority on its own state.

Load everything with `require("ragtag/missions.lua")` in the scenario after the JOBS require.

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
| `M.gm_actions` | list | Custom GM buttons; see **GM actions** below |
| `M.no_auto_cancel` | bool | Suppress the auto-generated "Cancel \<name\>" button |
| `M.no_criteria_button` | bool | Suppress the "Mission criteria" popup button |
| `M.gm_state_fn` | function | Called with no args; return string appended as `State: <value>` in the criteria popup |
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

### GM actions

`M.gm_actions` is an ordered list of action tables. The engine shows them when the mission
is active (filtered by current phase) and optionally when done.

```lua
M.gm_actions = {
    -- Static label, always shown while active
    {label = "→ Skip to deliver", fn = function(st)
        MISSIONS.phase("myarc", "deliver")
    end},

    -- Function label — re-evaluated on each render (good for state display)
    {label = function(st) return "State: " .. _myStateLabel() end,
     done_ok = true, fn = function(st) end},  -- no-op; info display only

    -- Phase filter: only shown when current phase matches one of the list
    {label = "→ M2", phases = {"m1_active", "m1_deliver"}, fn = function(st)
        MISSIONS.phase("myarc", "m2_active")
    end},

    -- Shown when done (restart, post-arc actions)
    {label = "Restart arc", phases = {"done"}, fn = function(st)
        local cur = MISSIONS._state["myarc"]
        if cur then _clearState(cur) end
        MISSIONS._status["myarc"] = "inactive"
        MISSIONS.start("myarc")
    end},
}
```

**Action fields:**

| Field | Type | Default | Notes |
|---|---|---|---|
| `label` | string or `function(st)` | required | Function form re-evaluated each render |
| `fn` | `function(st)` | required | Called when GM taps the button |
| `phases` | list of strings | nil | If set, shown only when current phase matches |
| `done_ok` | bool | false | Also show when status is `"done"` |

When status is `"done"`: only actions with `done_ok = true` or `phases` containing `"done"`
are shown — all other active-phase actions are hidden.

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

Trigger checking runs every frame in `MISSIONS.update(delta)`. When conditions are met but
`auto_start = false`, status becomes `"triggered"`. When `auto_start = true`, the mission
starts automatically.

---

## Engine API

```lua
MISSIONS.register(M)         -- called by each module at load time
MISSIONS.start(id)           -- activate; init_state, lock jobs, enter start_phase
MISSIONS.phase(id, name)     -- transition to named phase (NOTE: not .goto — reserved keyword)
MISSIONS.cancel(id)          -- exit current phase, call on_cancel, unlock jobs
MISSIONS.update(delta)       -- call every frame from scenario update()
MISSIONS.addGMButton(backFn) -- single top-level GM button (self-labels when any triggered)
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

1. **"Missions..."** — single top-level button
2. **Mission list** — one button per registered mission labeled with `M.name` only
3. **Mission detail** — in order:
   - **← Missions** — back to list
   - **Mission criteria** popup (if `M.triggers` defined and `M.no_criteria_button` not set);
     appends `State: <value>` from `M.gm_state_fn` when defined
   - **Start \<name\>** (if inactive/triggered)
   - Phase jump buttons (from `M.phase_order`, skipping `no_skip` and current phase)
   - `M.gm_actions` filtered by current phase
   - **Cancel \<name\>** (if active and `M.no_auto_cancel` not set)
   - Done-state actions: `M.gm_actions` entries with `done_ok = true` or `phases = {"done"}`
     (shown only when status is `"done"`)

---

## Mission modularity principle

Each mission must be **self-contained and decoupled**:

- Do not modify core campaign tables directly; use `RT.flag`, `RT.addReputation`,
  `JOBS.config.*` via approved fields.
- Core gameplay (job board, proximity spawns, reputation) must work without the arc active.
- Do not add arc logic to scenario `update()` or `init()` beyond the MISSIONS wiring calls.
- Design and state machine details go in a **per-mission doc** (`ee/ragtag/missions/<name>.md`);
  not in CLAUDE.md or this reference file.

This makes arcs easy to disable, restart, skip, or test independently.

---

## Registered missions (current)

| id | Name | locks_jobs | Trigger | Phases |
|---|---|---|---|---|
| `witness` | The Witness | yes | not_flagged: witness_complete | offer, transit, checkpoint, revealed, shroud_run, halcyon, broadcast |
| `rezkov` | Rezkov Arc | no | upgrades_min + not_flagged | hook, m1_navigate, m2_active, m2_deliver, m3_active, m3_deliver |

Design notes for each arc: `ee/ragtag/missions/<id>.md`.

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

### Idempotent GM skip buttons

Every GM skip action should clean up all prior state before entering the target phase, so
skipping backward or forward is always safe. Write a single `_clearState(st)` helper and
call it at the top of every GM action that changes phase:

```lua
local function _clearState(st)
    if RT.valid(st.target) then st.target:destroy() end
    st.target   = nil
    st.step_done = false
    RT.clearFlag("myarc_step")
    RT.clearFlag("myarc_done")
end

-- In gm_actions:
{label = "→ Phase 2", fn = function(st)
    _clearState(st)
    MISSIONS.phase("myarc", "phase2")
end},
```

### RT.clearFlag — clearing persistent flags

```lua
RT.clearFlag("myarc_flag")   -- clears the flag and saves campaign
```

**CRITICAL**: `RT.flag(name, nil)` is a **READ**, not a clear. The nil guard short-circuits
to `return RT.campaign.flags[name]` — no write happens. Any loop that calls
`RT.flag("x", nil)` to reset flags does nothing; the flags persist. Always use
`RT.clearFlag(name)` to actually clear a flag.

### Using RT.after inside a phase

`RT.after` timers survive phase transitions — cancel them explicitly in `exit` if they
should not fire after the phase ends.

### Checking active phase from outside the engine

```lua
if MISSIONS._status["witness"] == "active"
   and MISSIONS._cur_phase["witness"] == "broadcast" then
    -- ...
end
```

Use `RT.flag("witness_complete")` for cross-session state; `_status` is session-only and
starts as `"inactive"` each run.

### Guard against double hook registration on restart

If a mission registers station hooks in `init.enter`, guard with a file-level boolean so
restarting the arc in the same session doesn't double-register:

```lua
local _hook_registered = false

M.phases = {
    init = {
        enter = function(st)
            if _hook_registered then return end
            _hook_registered = true
            RT.addStationHook(RT.find("My Station"), function(...)
                -- ...
            end)
        end,
    },
}
```
