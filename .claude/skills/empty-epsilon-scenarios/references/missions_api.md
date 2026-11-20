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
| `M.on_load(st)` | function | Optional. Runs once when the arc is enabled and *waiting* (inactive/triggered), i.e. before its trigger is met. Use it to seed vague rumors (`RUMORS.add{priority=2, category="X_SEED"}`). Must be idempotent (remove the category first). Re-runs after a cancel. |
| `M.on_unload(st)` | function | Optional. Runs when the arc starts or is GM-disabled (`MISSIONS.setEnabled(id,false)`, "Disable arc" button). Undo what `on_load` did. |

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

### Linear arcs (no branching)

Every arc is **one phase path**. From any phase the arc goes to exactly one of:

- the **next** phase in `phase_order`,
- **`done`**, with the outcome recorded in a flag (`<id>_arc_done = "..."`), or
- **back** to an earlier phase, as a failure restart (e.g. the Maw's missed shot restarts `staging`).

A crew decision either **ends** the arc with an outcome or **continues** down the path; it never
picks between two different continuations. Variation lives *inside* a phase as flags: dialogue
variants (Ledger's `rezkov_ai_planted` briefing), optional objectives that shape the outcome
(Boneyard's drone flip and Annex lasers; Arc 6's rally wings), and outcome modifiers read in
`resolve`. If a design needs two genuinely different missions, make them two arcs.

This keeps state management simple: `M.completed` can replay any prefix of `phase_order`, and
every GM `→` jump has one well-defined world to rebuild.

The engine checks it: `MISSIONS.phase` logs `[MISSIONS] WARNING: <id> non-linear transition a -> b`
for anything else. Leaving `init` (start-of-session routing by saved flags) and GM jumps are exempt.

### Science database follows the arc state

Arc-dependent Science DB entries are derived from campaign flags, so a GM jump (forward, back,
to an end state, or `→ Inactive`) leaves the database matching the state it lands in.
`MISSIONS.gmJump` and `gmDeactivate` call `SCIDB.sync()`, and so does every session start.

- **People**: `SCIDB.meet(arc_id, "thresh_profile")` when the crew meets someone. It sets
  `<arc_id>_met_<who>` and adds the profile, returning true the first time.
  The profile exists while any arc's met-flag is set, so it disappears when the arcs that met the
  person are reset, and stays while another arc still has met them.
- **Announcements**: every entry added (`SCIDB.addEntry`, profiles) or revealed (`SCIDB.unlock`)
  during play is announced in every player ship's log (Relay reads it) with where it is:
  `[Science] Database entry added: Lore > Thresh.` / `... updated: Lore > Ashgrave Research.`
  An arc never writes its own "database updated" line. A story line ("Survivor records
  received.") goes **before** the SCIDB call so it reads first. Building the database and
  `SCIDB.sync()` are quiet (restoring what a save already earned is not news); for any other
  restore use `SCIDB.quietly(SCIDB.unlock, key)`. Tests read `SCIDB.announced` (the ship log
  cannot be read from Lua).
- **Locked lore**: `SCIDB.rule("ashgrave_research", {lock = true, want = fn})` is unlocked while
  `want()` is true and goes back to its placeholder (description and revealed keys) otherwise.
- **Runtime entries**: `SCIDB.rule("boneyard_survivors", {want = fn, add = fn})`. `add()` creates the
  entry (store it in `SCIDB._entries[key]`) while `want()` is true. Otherwise it is removed
  (`SCIDB.removeEntry`; entries are entities and `destroy()` removes them from the database).

Register rules at the bottom of the arc module. Keep the arc's normal unlock/add calls (they
carry the log lines); the rules only correct the database after state changes.

### GM console (every arc has the same screen)

The engine builds the arc's GM screen. Buttons, in order:

`← Missions` | `Mission criteria` (popup: each trigger condition, `[MET]` or `[ ? ]`) |
`Mission state` (popup: status, phase, `gm_state_fn` label, saved flags matching
`gm_flag_prefixes`, and every variable in the arc's state table) | `Enable arc` / `Disable arc`
(whenever the arc is not running; either way it first resets the arc to "never happened": `MISSIONS.gmResetArc`
clears every flag of the arc, its done flag included, and rebuilds its state table) | one `→` button per entry in `M.gm_states` | phase helpers from `M.gm_actions`.

```lua
M.gm_flag_prefixes = {"myarc_"}            -- flags shown in "Mission state" (default: id .. "_")
M.gm_state_fn = function() return "Hacking" end   -- optional one-line state label

-- One "→" button per phase and one per end state. Each jumps from ANY status (forward, back,
-- or from done/inactive) with the full context the target expects, via MISSIONS.gmJump:
--   1. M.gm_reset(st, target): destroy everything the arc spawned, cancel its timers, remove its
--      rumors/jobs, reset `st` to init_state in place, clear the objective, clear its flags
--      (MISSIONS.gmClearFlags). Afterwards SCIDB.sync() makes the Science DB match the flags.
--   2. M.completed[p](st) for every phase p BEFORE the target, in phase_order: the lasting effects
--      of having finished p (stations/ships left in the world, flags, DB entries). Idempotent.
--   3. setup(st): flags/objects specific to this jump (an end state's outcome flags).
--   4. the target phase's normal `enter`.
-- Write M.completed so replaying any prefix of phases yields the world a real run would have.
-- Resets cannot undo reputation, credits or Science DB entries; make `resolve` pay once
-- (e.g. a "<id>_rewarded" flag) so GM end-state jumps don't pay twice.
M.gm_reset = function(st, target) ... end
M.completed = {
    meeting = function(st) RT.flag("myarc_met", true) end,
}
local function _jump(phase, setup, opts) return function() MISSIONS.gmJump("myarc", phase, setup, opts) end end
M.gm_states = {
    {key = "meeting",   label = "→ Meeting",     fn = _jump("meeting")},
    {key = "done_win",  label = "→ Done: Win",   fn = _jump("done", function() RT.flag("myarc_won", true) end,
                                                              {skip_completed = true})},   -- clean end world
    {key = "done_lose", label = "→ Done: Lose",  fn = _jump("done", nil, {skip = {meeting = true}})},
}
-- "→ Inactive" is added by the engine (MISSIONS.gmDeactivate: M.gm_reset(st, nil) so the arc
-- "never happened" (world, timers, flags, Science DB), then cancel + disable so criteria cannot
-- re-trigger it) unless an entry has key = "inactive", which then replaces it.

-- State-specific helpers: shown only while the arc is in one of the listed phases ("done" and
-- "inactive", waiting for its triggers, count as phases here).
M.gm_actions = {
    {label = "Complete hack", phases = {"hack"}, fn = function(st) ... end},
}
```

Provide one `→ Done:` state for **every** possible end state (each value the arc can write to
its `<id>_arc_done` flag), so the GM can test every ending. `resolve()` runs on `done` as usual.

**Labels are 18 characters max** (GM console limit; the engine truncates and logs the arc id).
Count the `→` as one character. `gm_actions` fields: `label` (string or `function(st)`), `fn`,
`phases` (required for it to show; `"done"` is allowed). Arcs with no `gm_states` fall back to
the legacy Start / `> phase` / Cancel buttons and unscoped `gm_actions`.

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
    custom_label = "text for the GM criteria popup", -- optional, names the custom condition; or a function returning it (live counts)
    requires       = function() return RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined") end,
    requires_label = "Rezkov arc finished or declined",  -- the arc's prerequisite (see below)
}
```

`requires` is the arc's prerequisite: another arc it follows. It gates the start like any
trigger, and it is also watched while the arc runs: if it changes from met to unmet (the GM
rewinds the arc it depends on), the running arc is reset to "never happened" (`M.gm_reset` with
no target, then cancelled) and waits to trigger again. Only that change stops an arc: a GM jump
straight into an arc whose prerequisite was never met keeps running. Done arcs are left alone.
Use `custom` for any other condition (it is only checked before the start).

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
MISSIONS.setEnabled(id, bool) -- false: ignore triggers and call on_unload (keeps flags and state)
MISSIONS.gmToggleEnabled(id) -- the GM "Enable/Disable arc" button: gmResetArc, then flip enabled
MISSIONS.gmResetArc(id)       -- reset to "never happened" from any status: gm_reset, every arc flag cleared, fresh state
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

## Flags

Saved flags (`RT.flag`) are how arcs remember progress across sessions and how later arcs read
earlier outcomes. They are plain strings, so every arc **declares** the ones it owns:

```lua
M.gm_flag_prefixes = {"myarc_"}          -- GM resets clear everything with these prefixes
M.keep_flags = {"myarc_jobs_base"}       -- ...except these: campaign records, not arc progress
M.flags = {
    myarc_accepted    = "took the job from the contact",
    myarc_arc_done    = 'outcome: "won" | "lost"',
    myarc_rewarded    = "rewards were paid (an end state pays once)",
    ["myarc_part_*"]  = "part N recovered (myarc_part_1 .. 3)",       -- a family of names
    ["myarc_met_*"]   = "Science DB profile met, set by ARC.meet",    -- needed when the arc uses ARC.meet
}
M.reads = {"rezkov_arc_done", "rezkov_declined"}   -- other arcs' flags this arc looks at
```

Rules, enforced by `check.py` (statically, on every flag literal in `RT.flag`, `RT.clearFlag`,
`ARC.once`, `ARC.route` rules, `flagged` / `not_flagged` triggers) and by the arc tests (at run
time, on every flag written):

- a flag that no arc declares is an error (this is what catches typos);
- a declared flag must start with one of the arc's `gm_flag_prefixes`, and must be used;
- another arc's flag must be listed in `M.reads`, and is read-only: only the owner sets or clears it;
- arc flags used outside the arcs (other layers, scenarios, tests) must be declared too.

The meaning string is the documentation: write what the flag being set tells a later arc, and
list the values when it is not a boolean. `MISSIONS.flagOwner(name)` returns the owning arc id
and that string. The GM "Mission state" popup marks set flags that are not declared.

---

## Arc helpers (ARC)

`ee/ragtag/missions/_helpers.lua` defines `ARC`, the helpers shared by the arcs. It is part of the
missions layer (loaded by `missions.lua` right after the engine); core (`RT`), the job board and
world plugins do not know about it. **Use these instead of writing a local version**
(`check.py` rejects the common re-implementations), and when two arcs need the same new thing,
add it to `_helpers.lua`, not to `core.lua` and not to both arcs.

| Helper | Use |
|---|---|
| `ARC.player()` | The arc ship: the campaign's primary ship (`RT.players[1]`), or nil while it is destroyed. |
| `ARC.isArcShip(ship)` | True for the arc ship only. |
| `ARC.withPlayer(fn)` | Run `fn(ship)` on the arc ship (instead of `RT.forEachPlayer`). |
| `ARC.log(msg, color)` | Ship log line on the arc ship only (instead of `RT.shipLog`). |
| `ARC.hail(from, text, speaker)` | Hail the arc ship only (instead of `RT.hail`); false when comms are busy. |
| `ARC.comms(fn, other)` | Wrap a comms function: the arc ship gets the dialog, any other ship gets `other`. |
| `ARC.dist(x1, y1, x2, y2)` | Distance between two points. (`RT.dist(a, b)` is entity to entity.) |
| `ARC.near(ent, x, y, r)` | True when a valid entity is within `r` of the point. |
| `ARC.playerNear(x, y, r)` | The player ship when within `r` of the point, else nil. |
| `ARC.anyPlayerNear(x, y, r)` | Any player ship (sister ships too) within `r`, else nil. Only for world events any ship can set off (a frozen battle starting), never story progress. |
| `ARC.register(ship, callsign)` | `RT.register` without the kill penalty: use it for every ship an arc registers (an arc fight settles its own consequences). Ships an arc spawns without registering are not tracked either. |
| `ARC.alive(list)` | New list of the valid entities (`#ARC.alive(st.fleet) == 0`: all dead). |
| `ARC.kill(x)` | Remove one entity or every entity in a table, indestructible ones too; nil-safe. |
| `ARC.docked(src, tgt, msg)` | Dialog gate: true when `src` is the arc ship and docked; else sets `msg` (if given) and returns false. |
| `ARC.stationHook(callsign, fn)` | `RT.addStationHook`, once per session however often `init` runs; runs for the arc ship only. |
| `ARC.meet(arc_id, profile_key, who)` | First meeting: `SCIDB.meet` plus the one-time "records added" log line. |
| `ARC.once(flag, fn)` | Run `fn` the first time only (saved flag). Rewards in `M.resolve`. |
| `ARC.route(arc_id, rules, default)` | `init` routing by saved flags: first rule `{flag_or_fn, phase}` that holds. |
| `ARC.jumper(arc_id)` | Builder for `M.gm_states` buttons: `_jump(phase, setup, opts)`. |
| `ARC.resetState(M, st)` | For `M.gm_reset`: wipe `st` and refill from `M.init_state()`, in place. |

The skeleton they add up to:

```lua
local _jump = ARC.jumper("myarc")

local function _clearWorld(st)             -- everything the arc spawned or scheduled
    RT.cancelTimer("myarc_cleanup")
    ARC.kill(st.fleet);  st.fleet = {}
    ARC.kill(st.station); st.station = nil
    RUMORS.removeCategory("MYARC_HOOK")
    RT.clearObjective("myarc")
end

M.phases.init = {
    enter = function(st)
        ARC.stationHook("Dustmote Salvage", _dustmoteHook)
        ARC.route("myarc", {                -- furthest progress first
            {"myarc_arc_done", "done"},
            {"myarc_accepted", "run"},
        }, "hook")
    end,
}

M.phases.run = {
    update = function(st, delta, now)
        local p = ARC.playerNear(_SITE_X, _SITE_Y, 5 * U)
        if p and #ARC.alive(st.fleet) == 0 then MISSIONS.phase("myarc", "done") end
    end,
}

function M.resolve(st)
    ARC.once("myarc_rewarded", function() RT.addCredits(600, "My Arc") end)
end

M.on_cancel = _clearWorld
M.gm_reset = function(st, target)
    _clearWorld(st)
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("myarc", function(name)
        return name == "myarc_rewarded" and target == "done"   -- an end state does not pay twice
    end)
end
M.gm_states = { {key = "hook", label = "→ Hook", fn = _jump("hook")}, {key = "run", label = "→ Run", fn = _jump("run")} }
```

In a comms function: `if not ARC.docked(src, tgt, '"Dock first."') then return end`, then
`ARC.meet("myarc", "rezkov_profile", "Orlan Rezkov")`.

### One ship per campaign story

Story arcs belong to the campaign's primary ship (the Magpie, `RT.players[1]`). Other player
ships may be in the game working the job board; arcs must not react to them. In an arc:

- never loop over ships: no `RT.players`, `RT.forEachPlayer`, `RT.shipLog`, `RT.hail`,
  `RT.voice.hail/log` (`check.py` rejects them). Use `ARC.player()`, `ARC.withPlayer`, `ARC.log`,
  `ARC.hail`;
- wrap every comms function that offers a choice or changes arc state in `ARC.comms(fn, other)`;
  station hooks registered with `ARC.stationHook` and dialogs gated with `ARC.docked` are already
  arc-ship only;
- while the arc ship is destroyed `ARC.player()` is nil and the arc waits; no other ship takes over.

Still shared by every ship (core features, not arc code): objective lines (`RT.setObjective`),
`RT.voice` conversation trees, rumors, reputation, and story contracts on the job board.

**Layering.** Arcs call down into `RT`, `JOBS`, `PROX`, `RUMORS`, `SCIDB`, `STATS`/`ACH`; nothing
below calls up. `check.py` errors if a core file (`core.lua`, `stats.lua`, `verse.lua`, `voice.lua`,
`ship_templates.lua`) references `MISSIONS` or `ARC`. Two consequences:

- an arc defines its own achievements in its own file
  (`if ACH and ACH.define then ACH.define{id = ..., check = function(s) return (s.arcs.myarc or {}).completed end} end`);
- when core needs something from the arcs, the engine hands it over (the statistics report lists
  arcs through `STATS.arc_source`, which the engine sets) instead of core reading `MISSIONS`.

---

## Regression tests

Every arc has `tests/arcs/<id>.lua` (`check.py` errors if one is missing), run by
`python3 tools/game_tests.py --ee <EmptyEpsilon dir> [arc ...]`. A test runs inside a headless
EmptyEpsilon on top of the real sandbox scenario and drives the arc with real comms, forced docks,
teleports, the arc's `gm_states` and `gm_actions`; the API is documented at the top of
`tests/_harness.lua`. Three engine facts the tests lean on, which arcs must keep true:

- every state a GM can jump to is in `M.gm_states` with a `key` (`T.gmWalk` presses each one and
  fails if one is not listed in the test);
- `M.gm_reset(st, nil)` followed by cancel leaves no flags with the arc's `gm_flag_prefixes`, no
  spawned objects and no objective line (`T.deactivate`);
- errors inside `enter` / `exit` / `completed` / `gm_reset` are caught and logged as
  `[MISSIONS] ... error`; the tests turn those log lines into failures.

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
| `rezkov`   | Rezkov Arc    | no  | upgrades_min + not_flagged    | hook, m1_navigate, m2_active, m2_deliver, m3_active, m3_deliver |
| `boneyard` | Boneyard Arc  | no  | upgrades_min + not_flagged + requires (Rezkov) | hook, annex_hack, annex_control, report |
| `ledger`   | Ledger Arc    | no  | upgrades_min + not_flagged + requires (Rezkov) + custom (2 board jobs after Rezkov) | hook, meet, relay_run, carry |
| `corsair`  | Corsair Arc   | no  | upgrades_min + not_flagged + requires (Rezkov) (hook on entering the Gauntlet) | hook, escort, briefing, raid, return, battle |

Retired arcs (Witness, Whistleblower) live in `ee/ragtag/missions/attic/` — kept for
reference, never required by the loader. `check.py` errors on any file in
`ee/ragtag/missions/` that isn't required by `missions.lua`, so attic/ is where
intentionally unloaded arcs go.

Design notes for each arc: `ee/ragtag/missions/<id>.md`.

---

## Common patterns

### Detecting a completed hack

```lua
-- In the phase update (every tick). EE decays hacked_level before scripts run, so a finished
-- hack reads just under 1.0 here: >= 1.0 never fires. 0.99 leaves about a 2 s window.
local ok, lvl = pcall(function() return target:getSystemHackedLevel("frontshield") end)
if ok and (lvl or 0) >= 0.99 then
    MISSIONS.phase("myarc", "after_hack")   -- latch: advance now, never re-read later
end
```

A GM "Complete hack" helper (`phases = {"hack"}`) just calls
`target:setSystemHackedLevel("frontshield", 1.0)`; the check above fires on the next frame.

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
    ARC.kill(st.ship); st.ship = nil       -- nil-safe; also removes indestructible objects
end
```

### Idempotent GM jumps

A GM jump must be safe from any state, forward or back. Write one `_clearWorld(st)` that removes
everything the arc spawned or scheduled, and call it from both `M.on_cancel` and `M.gm_reset`
(see the skeleton under **Arc helpers (ARC)**). `MISSIONS.gmJump` then replays `M.completed[...]`
for the phases before the target, so each jump starts from a clean, correct world:

```lua
local _jump = ARC.jumper("myarc")
M.gm_reset = function(st, target)
    _clearWorld(st)
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("myarc")
end
M.gm_states = { {key = "phase2", label = "→ Phase 2", fn = _jump("phase2")} }
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

`RT.after` timers survive phase transitions — cancel them explicitly in `exit` or
`_clearState` if they should not fire after the phase ends.

```lua
RT.after(90, function()
    -- Guard: arc may have been cancelled before this fires
    if MISSIONS._status["myarc"] ~= "active" then return end
    local st = MISSIONS._state["myarc"]
    if st then _doThing(st) end
end, "myarc_timer_name")

-- Cancel by the name passed as the third argument:
RT.cancelTimer("myarc_timer_name")
```

### Checking active phase from outside the engine

```lua
if MISSIONS._status["witness"] == "active"
   and MISSIONS._cur_phase["witness"] == "broadcast" then
    -- ...
end
```

Use `RT.flag("witness_complete")` for cross-session state; `_status` is session-only and
starts as `"inactive"` each run.

### Suspending proximity spawns in a named zone

Use `PROX.suspendZone(name)` to suppress ambient spawns while the arc controls a region,
and `PROX.resumeZone(name)` to restore them on resolve or cancel.

```lua
-- In a phase update when the arc takes over a zone:
PROX.suspendZone("the Boneyard")

-- In M.resolve and M.on_cancel:
PROX.resumeZone("the Boneyard")
```

Zone names match the keys in `PROX.zones` (see `ee/ragtag/world/proximity.lua`). The
leash/despawn watchdog keeps running during suspension — only new spawns are blocked.
Call `PROX.suspendZone` again in every GM skip action that jumps to a post-suspend phase.

### Unlocking Science database entries from arc resolve

When an arc recovers classified information, unlock the corresponding SCIDB entries in
`M.resolve`. The entries must have been created with a `lock_key` in `sciencedb.lua`.

```lua
function M.resolve(st)
    if RT.flag("myarc_data_retrieved") then
        ARC.log("[Science] Recovered files indexed.", "#00CCAA")   -- first: SCIDB announces each entry
        SCIDB.unlock("hollow_true_nature")
        SCIDB.unlock("ashgrave_research")
    end
end
```

### Injecting and cleaning up arc rumors

Add arc-specific rumors with a `category` tag, inject in the hook phase's `enter`,
and remove the category in `exit` so they retire when the player acts on them.
Injected rumors are session state — they reset every run — so **never gate the
injection on a persistent `RT.flag`**: the flag survives to session 2, the rumors
don't, and the hook silently disappears.

```lua
hook = {
    enter = function(st)
        RUMORS.removeCategory("MYARC_HOOK")  -- idempotent for GM re-entry
        RUMORS.add({text = "...", priority = 5, category = "MYARC_HOOK"})  -- 5 = actionable hook; 3 = background seed (see Rumor tiers)
    end,
    exit = function(st)
        RUMORS.removeCategory("MYARC_HOOK")  -- phase transitions always run exit
    end,
}

-- And in _clearState (covers cancel and GM skip actions):
RUMORS.removeCategory("MYARC_HOOK")
RUMORS.removeCategory("MYARC_DONE")
```

Note: `RUMORS.get` returns **nil** when the rumors WORLD plugin is disabled —
guard any direct concatenation with `or "fallback line"`.

### Seeding jobs from an arc

An arc can put work on the station job boards, both pre-trigger seeds and the hook
contract. Full API (builders, `story` rules, priorities): `jobs_api.md` → "Injected jobs".
Pair it with the lifecycle hooks and phase `enter`/`exit`, exactly like rumors:

```lua
function M.on_load(st)                    -- waiting for the trigger: seed filler
    JOBS.removeCategory("MYARC_JOBS")     -- idempotent
    JOBS.inject({category = "MYARC_JOBS", priority = 3, origin = "Port Vesper",
        record = function(cs) return JOBS.build("delivery",
            {origin = cs, dest = "Halcyon Rest", cargo = "coolant", reward = 70, brief = "..."}) end})
end
function M.on_unload(st) JOBS.removeCategory("MYARC_JOBS") end

-- hook phase: the special contract that leads into the arc
hook = {
    enter = function(st)
        JOBS.inject({category = "MYARC_SPECIAL", priority = 5, origin = {"Port Vesper", "Halcyon Rest"},
            record = function(cs) return JOBS.build("salvage", {id = "myarc_buoy", story = true,
                origin = cs, wx = 22000, wy = -72000, cargo = "a survey buoy", reward = 400,
                brief = "...", on_found = function(m) RT.shipLog("[Science] ...") end}) end})
    end,
    exit = function(st) JOBS.removeCategory("MYARC_SPECIAL") end,
}
-- and in _clearState: JOBS.removeCategory("MYARC_SPECIAL")
```

To steer crews with a job that looks perfectly ordinary, use a priority-3 seed with `ensure = true`: it is guaranteed on the board at each matching station (gate it with `when`, e.g. on the arc's phase) but gets no `[SPECIAL]` tag and normal rewards. Rules of thumb: seeds are priority 3 and look like normal work; the one story contract
is priority 5 with `story = true` (`[SPECIAL]`, bypasses the 2-job cap, no
penalty). Use a shared `id` when one contract is offered at several stations. Injected
jobs reset each run, so never gate injection on a persistent `RT.flag`; use
`JOBS.hasVisited(cs)` in `when` to gate on progress.

### Destruction hooks and kill tracking

`entity:onDestruction` holds ONE callback per entity; reputation tracking, director
kill events, and loot drops all share it. **Always register through
`RT.onKill(ship, fn(ship, instigator))`** — it installs a single dispatcher and
calls every registered fn.

- Fires on damage kills only; a scripted `entity:destroy()` fires nothing, so
  despawns in `_clearState`/`on_cancel` are automatically penalty-free.
- `RT.register()` on a CpuShip auto-wires a -200 rep penalty that fires **only
  when the player is the instigator**. Pseudo-factions (`Concord Hostile`,
  `Corsair Friendly`, `Relic Active`) and `Derelict`/`Unknown` are never tracked.
- `RT.cancelKillTracking(ship)` suppresses the auto penalty for a ship the arc
  lets die to damage while applying its own rep consequences (e.g. a story
  target with an explicit `RT.addReputation` outcome).

### Station hooks: register once

Register station hooks in `init.enter` with `ARC.stationHook`, which ignores a second
registration of the same function (a GM restart re-enters `init`):

```lua
M.phases.init = {
    enter = function(st)
        ARC.stationHook("My Station", _myStationHook)   -- not RT.addStationHook
    end,
}
```

The hook itself decides whether to offer anything:
`if not ARC.docked(src, tgt) then return end`, then check the arc's phase.

## Rumor tiers (RUMORS.add priority)

- **3 seed**: background foreshadowing, loaded from `M.on_load` while the arc waits for its trigger. Mixed into the normal "Any news?" rotation: each unheard seed is picked slightly more readily than each pool rumor (`RUMORS.SEED_WEIGHT` = 1.5 vs 1), subject to the 5-minute cooldown, each heard once before repeating. Harmless if never heard. (Priority 2 is treated the same.)
- **5 hook** (anything >= 4): actionable lead, set in the hook phase. Bypasses the cooldown and replaces the background pool entirely; hooks of equal priority from different arcs are mixed, so give Phase II arcs the same priority and the crew hears every lead. Higher priority hides lower (Rezkov's 5 would hide a 4).
