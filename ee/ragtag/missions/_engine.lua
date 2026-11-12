-- ee/ragtag/missions/_engine.lua
-- Modular story mission engine. Missions are self-contained phase machines.
-- Load via ee/ragtag/missions.lua, not directly.

MISSIONS = MISSIONS or {}

MISSIONS._registry   = {}   -- id -> module
MISSIONS._state      = {}   -- id -> mutable state table
MISSIONS._status     = {}   -- id -> "inactive"|"triggered"|"active"|"done"|"cancelled"
MISSIONS._cur_phase  = {}   -- id -> current phase name (nil when inactive/done)
MISSIONS._entered_at = {}   -- id -> scenario time when current phase was entered
MISSIONS._order      = {}   -- insertion order for consistent GM display
MISSIONS._enabled    = {}   -- id -> bool (false = GM-disabled: no triggers, no seeds)
MISSIONS._loaded     = {}   -- id -> bool (M.on_load has run and M.on_unload has not)

-- Register a mission module. Called by each mission file at the bottom.
function MISSIONS.register(M)
    assert(M.id,           "mission module missing .id")
    assert(M.name,         "mission module missing .name")
    assert(M.phases,       "mission module missing .phases")
    assert(M.start_phase,  "mission module missing .start_phase")
    MISSIONS._registry[M.id]   = M
    MISSIONS._status[M.id]     = "inactive"
    MISSIONS._state[M.id]      = {}
    MISSIONS._enabled[M.id]    = true
    MISSIONS._loaded[M.id]     = false
    MISSIONS._cur_phase[M.id]  = nil
    MISSIONS._order[#MISSIONS._order + 1] = M.id
end

-- Start a mission (GM or auto_start).
function MISSIONS.start(id)
    local M = MISSIONS._registry[id]
    if not M then return end
    if MISSIONS._status[id] == "active" then return end

    MISSIONS._unload(id)
    MISSIONS._state[id]  = M.init_state and M.init_state() or {}
    MISSIONS._status[id] = "active"
    if STATS then STATS.arcEvent(id, "started") end

    if M.locks_jobs then JOBS.config.jobboard_locked = true end

    MISSIONS._enterPhase(id, M.start_phase)
end

-- Transition to a named phase. Called from comms callbacks or phase update functions.
function MISSIONS.phase(id, phase_name)
    if MISSIONS._status[id] ~= "active" then return end
    MISSIONS._enterPhase(id, phase_name)
end

-- Lifecycle hooks. A mission that is enabled and waiting (inactive/triggered) is
-- "loaded": M.on_load(st) runs once (seed rumors, ambient set-up) and M.on_unload(st)
-- runs when it starts, is disabled, or is otherwise no longer waiting. A cancel
-- returns the mission to waiting, so it loads again. Both hooks must be idempotent
-- (the engine does not persist across a scenario restart).
function MISSIONS._load(id)
    local M = MISSIONS._registry[id]
    if not M or MISSIONS._loaded[id] then return end
    MISSIONS._loaded[id] = true
    if M.on_load then
        local ok, err = pcall(M.on_load, MISSIONS._state[id] or {})
        if not ok then log("[MISSIONS] " .. id .. " on_load error: " .. tostring(err)) end
    end
end

function MISSIONS._unload(id)
    local M = MISSIONS._registry[id]
    if not M or not MISSIONS._loaded[id] then return end
    MISSIONS._loaded[id] = false
    if M.on_unload then
        local ok, err = pcall(M.on_unload, MISSIONS._state[id] or {})
        if not ok then log("[MISSIONS] " .. id .. " on_unload error: " .. tostring(err)) end
    end
end

-- Enable or disable a waiting mission (GM). Disabled: triggers ignored, on_unload runs.
function MISSIONS.setEnabled(id, on)
    if not MISSIONS._registry[id] then return end
    MISSIONS._enabled[id] = on and true or false
    if not on then MISSIONS._unload(id) end
end

-- Cancel an active mission (GM action).
function MISSIONS.cancel(id)
    local M  = MISSIONS._registry[id]
    local st = MISSIONS._state[id]
    if not M then return end

    local phase_name = MISSIONS._cur_phase[id]
    if phase_name then
        local pdef = M.phases[phase_name]
        if pdef and pdef.exit then pcall(pdef.exit, st) end
    end

    if M.on_cancel then pcall(M.on_cancel, st) end
    if M.locks_jobs then JOBS.config.jobboard_locked = false end
    if STATS then STATS.arcEvent(id, "cancelled") end

    MISSIONS._status[id]    = "inactive"
    MISSIONS._cur_phase[id] = nil
    MISSIONS._state[id]     = {}
end

-- Internal: run phase exit, advance pointer, run phase enter.
function MISSIONS._enterPhase(id, phase_name)
    local M  = MISSIONS._registry[id]
    local st = MISSIONS._state[id]
    if not M then return end

    local old = MISSIONS._cur_phase[id]
    if old then
        local old_def = M.phases[old]
        if old_def and old_def.exit then
            local ok, err = pcall(old_def.exit, st)
            if not ok then
                log("[MISSIONS] " .. id .. "." .. old .. " exit error: " .. tostring(err))
            end
        end
    end

    MISSIONS._cur_phase[id]  = phase_name
    MISSIONS._entered_at[id] = getScenarioTime()

    if phase_name == "done" then
        MISSIONS._status[id] = "done"
        if M.locks_jobs then JOBS.config.jobboard_locked = false end
        if STATS then STATS.arcEvent(id, "completed") end
        if M.resolve then
            local ok, err = pcall(M.resolve, st)
            if not ok then
                log("[MISSIONS] " .. id .. " resolve error: " .. tostring(err))
            end
        end
        return
    end

    local pdef = M.phases[phase_name]
    if not pdef then
        log("[MISSIONS] " .. id .. ": unknown phase '" .. tostring(phase_name) .. "'")
        return
    end
    if pdef.enter then
        local ok, err = pcall(pdef.enter, st)
        if not ok then
            log("[MISSIONS] " .. id .. "." .. phase_name .. " enter error: " .. tostring(err))
        end
    end
end

-- Compute total upgrade spend for trigger checks.
local function _upgradeSpend()
    if not RT.campaign then return 0 end
    local cost_map = {}
    for _, u in ipairs(RT.UPGRADES) do cost_map[u.id] = u.cost end
    local total = 0
    for _, uid in ipairs(RT.campaign.upgrades or {}) do
        total = total + (cost_map[uid] or 0)
    end
    return total
end

-- Check whether all trigger conditions for a mission are met.
function MISSIONS._checkTriggers(id)
    local M = MISSIONS._registry[id]
    local t = M and M.triggers
    if not t then return false end

    if t.rep_min then
        for fac, min_val in pairs(t.rep_min) do
            if (RT.getReputation(fac) or 0) < min_val then return false end
        end
    end
    if t.rep_max then
        for fac, max_val in pairs(t.rep_max) do
            if (RT.getReputation(fac) or 0) > max_val then return false end
        end
    end
    if t.upgrades_min then
        if _upgradeSpend() < t.upgrades_min then return false end
    end
    if t.not_flagged then
        for _, flag in ipairs(t.not_flagged) do
            if RT.flag(flag) then return false end
        end
    end
    if t.custom then
        local ok, result = pcall(t.custom, MISSIONS._state[id] or {})
        if not ok or not result then return false end
    end
    return true
end

-- Called every frame from the scenario update().
function MISSIONS.update(delta)
    if not RT.anyPlayerAlive() then return end

    for _, id in ipairs(MISSIONS._order) do
        local M      = MISSIONS._registry[id]
        local status = MISSIONS._status[id]

        -- Lifecycle: waiting + enabled missions are loaded (e.g. seed rumors in place).
        if (status == "inactive" or status == "triggered") and MISSIONS._enabled[id] then
            MISSIONS._load(id)
        else
            MISSIONS._unload(id)
        end

        -- Trigger checking for non-active missions that have trigger conditions.
        if (status == "inactive" or status == "triggered") and M.triggers
           and MISSIONS._enabled[id] then
            local met = MISSIONS._checkTriggers(id)
            if met and status == "inactive" then
                MISSIONS._status[id] = "triggered"
                log("[MISSIONS] " .. M.name .. ": trigger conditions met")
            elseif not met and status == "triggered" then
                MISSIONS._status[id] = "inactive"
            end
            if met and M.auto_start then
                MISSIONS.start(id)
                status = MISSIONS._status[id]
            end
        end

        -- Run active mission's current phase update.
        if status == "active" then
            local phase_name = MISSIONS._cur_phase[id]
            if phase_name then
                local pdef = M.phases[phase_name]
                if pdef and pdef.update then
                    local now = getScenarioTime()
                    local ok, err = pcall(pdef.update, MISSIONS._state[id], delta, now)
                    if not ok then
                        log("[MISSIONS] " .. id .. "." .. phase_name
                              .. " update error: " .. tostring(err))
                    end
                end
            end
        end
    end
end

-- ── GM interface ──────────────────────────────────────────────────────────────

-- Build a human-readable criteria status string for the GM popup.
function MISSIONS._criteriaText(id)
    local M = MISSIONS._registry[id]
    local t = M and M.triggers
    if not t then return "(no trigger conditions defined)" end

    local lines = {"=== " .. M.name .. " -- Trigger Conditions ===\n"}

    if t.rep_min then
        for fac, min_val in pairs(t.rep_min) do
            local cur = (RT.getReputation and RT.getReputation(fac)) or 0
            local met = cur >= min_val
            lines[#lines+1] = string.format("  %s %s rep >= %+d  (now: %+d)",
                met and "[MET]" or "[ ? ]", fac, min_val, cur)
        end
    end

    if t.rep_max then
        for fac, max_val in pairs(t.rep_max) do
            local cur = (RT.getReputation and RT.getReputation(fac)) or 0
            local met = cur <= max_val
            lines[#lines+1] = string.format("  %s %s rep <= %+d  (now: %+d)",
                met and "[MET]" or "[ ? ]", fac, max_val, cur)
        end
    end

    if t.upgrades_min then
        local spent = _upgradeSpend()
        local met   = spent >= t.upgrades_min
        lines[#lines+1] = string.format("  %s Upgrade investment >= %dcr  (now: %dcr)",
            met and "[MET]" or "[ ? ]", t.upgrades_min, spent)
    end

    if t.not_flagged then
        for _, flag in ipairs(t.not_flagged) do
            local val = RT.flag and RT.flag(flag)
            local met = not val
            local val_str = val and tostring(val) or "not set"
            lines[#lines+1] = string.format("  %s Flag '%s' not set  (now: %s)",
                met and "[MET]" or "[ ? ]", flag, val_str)
        end
    end

    if t.custom then
        local ok, result = pcall(t.custom, MISSIONS._state[id] or {})
        local met = ok and result
        lines[#lines+1] = string.format("  %s %s", met and "[MET]" or "[ ? ]",
            t.custom_label or "Custom condition")
    end

    local overall = MISSIONS._checkTriggers(id)
    local status  = MISSIONS._status[id]
    lines[#lines+1] = string.format("\nResult: %s  |  Status: %s",
        overall and "ALL MET" or "not yet met", status)

    if M.gm_state_fn then
        local ok, lbl = pcall(M.gm_state_fn)
        if ok and lbl then
            lines[#lines+1] = "State:  " .. lbl
        end
    end

    return table.concat(lines, "\n")
end

-- Add the single top-level "Missions..." button to the GM menu.
-- backToMainFn: rebuilds the main GM screen (clearGMFunctions + addSessionGMFunctions).
function MISSIONS.addGMButton(backToMainFn)
    addGMFunction("Missions...", function()
        MISSIONS._showList(backToMainFn)
    end)
end

function MISSIONS._showList(backToMainFn)
    clearGMFunctions()
    addGMFunction("← Back to Main", backToMainFn)
    for _, id in ipairs(MISSIONS._order) do
        local M      = MISSIONS._registry[id]
        local status = MISSIONS._status[id]
        local phase  = MISSIONS._cur_phase[id]
        local lbl = M.name
        local mid = id
        addGMFunction(lbl, function()
            MISSIONS._showDetail(mid, backToMainFn)
        end)
    end
end

-- GM buttons must fit the console: 18 characters max. Over-long labels are
-- truncated and logged so the offending arc gets fixed (not silently clipped).
MISSIONS.GM_LABEL_MAX = 18
function MISSIONS._gmLabel(lbl, id)
    lbl = tostring(lbl or "?")
    -- Count characters, not bytes: "→" is 3 bytes in UTF-8 but one character.
    local function nchars(str) return select(2, str:gsub("[^\128-\191]", "")) end
    local n = nchars(lbl)
    if n > MISSIONS.GM_LABEL_MAX then
        log("[MISSIONS] GM label too long (" .. n .. " > " .. MISSIONS.GM_LABEL_MAX .. ") in '" .. tostring(id) .. "': " .. lbl)
        local out, count = {}, 0
        for ch in lbl:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            count = count + 1
            if count > MISSIONS.GM_LABEL_MAX then break end
            out[#out + 1] = ch
        end
        lbl = table.concat(out)
    end
    return lbl
end

-- ── GM state popup ────────────────────────────────────────────────────────────

local function _fmtVal(v)
    local t = type(v)
    if t == "boolean" or t == "number" or t == "string" or t == "nil" then return tostring(v) end
    if t == "function" then return nil end
    -- Entities (userdata or table-like): show callsign, or "(gone)" once destroyed.
    local ok, cs = pcall(function() return v:getCallSign() end)
    if ok and cs then return RT.valid(v) and ("ship " .. tostring(cs)) or "(destroyed)" end
    if t == "table" then
        local n, live = 0, 0
        for _, x in pairs(v) do
            n = n + 1
            local ok2 = pcall(function() return x:getCallSign() end)
            if ok2 and RT.valid(x) then live = live + 1 end
        end
        if live > 0 then return string.format("%d items (%d alive)", n, live) end
        return string.format("%d items", n)
    end
    return "(" .. t .. ")"
end

-- Everything the GM needs to know about a mission at a glance: status, phase, the arc's own
-- state label, its campaign flags (prefix list) and every variable in its state table.
function MISSIONS._stateText(id)
    local M = MISSIONS._registry[id]
    if not M then return "(unknown mission)" end
    local st = MISSIONS._state[id] or {}
    local lines = {"=== " .. M.name .. " -- State ===\n"}
    lines[#lines+1] = "Status:  " .. tostring(MISSIONS._status[id])
    lines[#lines+1] = "Phase:   " .. tostring(MISSIONS._cur_phase[id] or "-")
    if M.gm_state_fn then
        local ok, lbl = pcall(M.gm_state_fn)
        if ok and lbl then lines[#lines+1] = "State:   " .. tostring(lbl) end
    end
    lines[#lines+1] = "Enabled: " .. tostring(MISSIONS._enabled[id])
    if MISSIONS._entered_at[id] and MISSIONS._cur_phase[id] then
        lines[#lines+1] = string.format("In phase: %ds", math.floor(getScenarioTime() - MISSIONS._entered_at[id]))
    end

    local prefixes = M.gm_flag_prefixes or {id .. "_"}
    local flags = {}
    for name, val in pairs((RT.campaign and RT.campaign.flags) or {}) do
        for _, pre in ipairs(prefixes) do
            if name:sub(1, #pre) == pre then flags[#flags+1] = name; break end
        end
    end
    table.sort(flags)
    lines[#lines+1] = "\nFlags (saved):"
    if #flags == 0 then lines[#lines+1] = "  (none set)" end
    for _, name in ipairs(flags) do
        lines[#lines+1] = string.format("  %s = %s", name, tostring(RT.campaign.flags[name]))
    end

    local rows = {}
    for k, v in pairs(st) do rows[#rows+1] = {tostring(k), v} end
    table.sort(rows, function(x, y) return x[1] < y[1] end)
    lines[#lines+1] = "\nVariables (this run):"
    local shown = 0
    for _, row in ipairs(rows) do
        local v = _fmtVal(row[2])
        if v then
            lines[#lines+1] = string.format("  %s = %s", row[1], v)
            shown = shown + 1
        end
    end
    if shown == 0 then lines[#lines+1] = "  (none)" end
    return table.concat(lines, "\n")
end

-- ── GM state transitions ──────────────────────────────────────────────────────

-- Make sure the mission is running so a "->" button can jump into any state, even from
-- inactive or done. Starting runs the arc's start phase; the button's fn then jumps on.
function MISSIONS._ensureActive(id)
    local M = MISSIONS._registry[id]
    if not M or MISSIONS._status[id] == "active" then return end
    local st = MISSIONS._state[id]
    if MISSIONS._status[id] == "done" and M.on_cancel then pcall(M.on_cancel, st or {}) end
    MISSIONS._status[id] = "inactive"
    MISSIONS.start(id)
end

-- Default "-> Inactive": stop the arc and keep it from re-triggering (until re-enabled).
function MISSIONS.gmDeactivate(id)
    local M = MISSIONS._registry[id]
    if not M then return end
    if MISSIONS._status[id] == "active" then
        MISSIONS.cancel(id)
    elseif MISSIONS._status[id] == "done" then
        if M.on_cancel then pcall(M.on_cancel, MISSIONS._state[id] or {}) end
        MISSIONS._status[id]    = "inactive"
        MISSIONS._cur_phase[id] = nil
        MISSIONS._state[id]     = {}
    end
    MISSIONS.setEnabled(id, false)
end

-- GM detail screen, same shape for every arc:
--   <- Missions | Mission criteria | Mission state | (Enable/Disable arc, while waiting)
--   -> buttons from M.gm_states (arc-defined: each phase, plus one per end state)
--   phase helpers from M.gm_actions entries that carry `phases = {...}`
-- M.gm_states = { {key=, label="-> Name" (max 18 chars), fn=function(st) end}, ... }
-- fn runs after the mission is made active (a fresh state table when it had to be started).
-- If no entry has key "inactive", the engine adds a default "-> Inactive".
function MISSIONS._showDetail(id, backToMainFn)
    local M      = MISSIONS._registry[id]
    local status = MISSIONS._status[id]
    local phase  = MISSIONS._cur_phase[id]
    local st     = MISSIONS._state[id]
    if not M then return end

    clearGMFunctions()
    addGMFunction("← Missions", function()
        MISSIONS._showList(backToMainFn)
    end)

    if M.triggers and not M.no_criteria_button then
        addGMFunction("Mission criteria", function()
            addGMMessage(MISSIONS._criteriaText(id))
        end)
    end
    addGMFunction("Mission state", function()
        addGMMessage(MISSIONS._stateText(id))
    end)

    if status == "inactive" or status == "triggered" then
        local on = MISSIONS._enabled[id]
        addGMFunction(on and "Disable arc" or "Enable arc", function()
            MISSIONS.setEnabled(id, not on)
            MISSIONS._showDetail(id, backToMainFn)
        end)
    end

    if M.gm_states then
        local has_inactive = false
        for _, d in ipairs(M.gm_states) do if d.key == "inactive" then has_inactive = true end end
        if not has_inactive then
            addGMFunction("→ Inactive", function()
                MISSIONS.gmDeactivate(id)
                globalMessage("[GM] " .. M.name .. ": → Inactive (disabled).", 4)
                MISSIONS._showDetail(id, backToMainFn)
            end)
        end
        for _, d in ipairs(M.gm_states) do
            local def = d
            addGMFunction(MISSIONS._gmLabel(def.label, id), function()
                MISSIONS._ensureActive(id)
                MISSIONS._enabled[id] = true
                local ok, err = pcall(def.fn, MISSIONS._state[id])
                if not ok then log("[MISSIONS] " .. id .. " gm state '" .. tostring(def.label) .. "' error: " .. tostring(err)) end
                globalMessage("[GM] " .. M.name .. ": " .. tostring(def.label) .. ".", 4)
                MISSIONS._showDetail(id, backToMainFn)
            end)
        end
    elseif status == "inactive" or status == "triggered" then
        -- Arcs without gm_states keep the old Start / phase-jump / Cancel buttons.
        addGMFunction("Start " .. M.name, function()
            MISSIONS.start(id)
            MISSIONS._showDetail(id, backToMainFn)
        end)
    elseif status == "active" and M.phase_order then
        for _, pname in ipairs(M.phase_order) do
            local pdef = M.phases[pname]
            if pdef and not pdef.no_skip and pname ~= phase then
                local pn = pname
                addGMFunction("> " .. pn, function()
                    MISSIONS.phase(id, pn)
                    MISSIONS._showDetail(id, backToMainFn)
                end)
            end
        end
        if not M.no_auto_cancel then
            addGMFunction("Cancel arc", function()
                MISSIONS.cancel(id)
                MISSIONS._showDetail(id, backToMainFn)
            end)
        end
    end

    -- State-specific helpers ("Complete hack"): only for the phase they apply to.
    if M.gm_actions then
        for _, action in ipairs(M.gm_actions) do
            local a = action
            local show = false
            if a.phases then
                for _, p in ipairs(a.phases) do
                    if p == (status == "done" and "done" or phase) then show = true; break end
                end
            elseif not M.gm_states and status == "active" then
                show = true   -- legacy arcs: unscoped actions show while active
            end
            if show then
                local lbl = MISSIONS._gmLabel(type(a.label) == "function" and a.label(st) or a.label, id)
                addGMFunction(lbl, function()
                    pcall(a.fn, MISSIONS._state[id])
                    MISSIONS._showDetail(id, backToMainFn)
                end)
            end
        end
    end
end
