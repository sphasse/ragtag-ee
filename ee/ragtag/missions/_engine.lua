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

-- Register a mission module. Called by each mission file at the bottom.
function MISSIONS.register(M)
    assert(M.id,           "mission module missing .id")
    assert(M.name,         "mission module missing .name")
    assert(M.phases,       "mission module missing .phases")
    assert(M.start_phase,  "mission module missing .start_phase")
    MISSIONS._registry[M.id]   = M
    MISSIONS._status[M.id]     = "inactive"
    MISSIONS._state[M.id]      = {}
    MISSIONS._cur_phase[M.id]  = nil
    MISSIONS._order[#MISSIONS._order + 1] = M.id
end

-- Start a mission (GM or auto_start).
function MISSIONS.start(id)
    local M = MISSIONS._registry[id]
    if not M then return end
    if MISSIONS._status[id] == "active" then return end

    MISSIONS._state[id]  = M.init_state and M.init_state() or {}
    MISSIONS._status[id] = "active"

    if M.locks_jobs then JOBS.config.jobboard_locked = true end

    MISSIONS._enterPhase(id, M.start_phase)
end

-- Transition to a named phase. Called from comms callbacks or phase update functions.
function MISSIONS.phase(id, phase_name)
    if MISSIONS._status[id] ~= "active" then return end
    MISSIONS._enterPhase(id, phase_name)
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
                print("[MISSIONS] " .. id .. "." .. old .. " exit error: " .. tostring(err))
            end
        end
    end

    MISSIONS._cur_phase[id]  = phase_name
    MISSIONS._entered_at[id] = getScenarioTime()

    if phase_name == "done" then
        MISSIONS._status[id] = "done"
        if M.locks_jobs then JOBS.config.jobboard_locked = false end
        if M.resolve then
            local ok, err = pcall(M.resolve, st)
            if not ok then
                print("[MISSIONS] " .. id .. " resolve error: " .. tostring(err))
            end
        end
        return
    end

    local pdef = M.phases[phase_name]
    if not pdef then
        print("[MISSIONS] " .. id .. ": unknown phase '" .. tostring(phase_name) .. "'")
        return
    end
    if pdef.enter then
        local ok, err = pcall(pdef.enter, st)
        if not ok then
            print("[MISSIONS] " .. id .. "." .. phase_name .. " enter error: " .. tostring(err))
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

        -- Trigger checking for non-active missions that have trigger conditions.
        if (status == "inactive" or status == "triggered") and M.triggers then
            local met = MISSIONS._checkTriggers(id)
            if met and status == "inactive" then
                MISSIONS._status[id] = "triggered"
                print("[MISSIONS] " .. M.name .. ": trigger conditions met")
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
                        print("[MISSIONS] " .. id .. "." .. phase_name
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
        lines[#lines+1] = string.format("  %s Custom condition", met and "[MET]" or "[ ? ]")
    end

    local overall = MISSIONS._checkTriggers(id)
    local status  = MISSIONS._status[id]
    lines[#lines+1] = string.format("\nResult: %s  |  Status: %s",
        overall and "ALL MET" or "not yet met", status)

    return table.concat(lines, "\n")
end

-- Add the single top-level "Missions..." button to the GM menu.
-- backToMainFn: rebuilds the main GM screen (clearGMFunctions + addSessionGMFunctions).
function MISSIONS.addGMButton(backToMainFn)
    local label = "Missions..."
    for _, id in ipairs(MISSIONS._order) do
        if MISSIONS._status[id] == "triggered" then
            label = "Missions..."
            break
        end
    end
    addGMFunction(label, function()
        MISSIONS._showList(backToMainFn)
    end)
end

function MISSIONS._showList(backToMainFn)
    clearGMFunctions()
    addGMFunction("< Back to Main", backToMainFn)
    for _, id in ipairs(MISSIONS._order) do
        local M      = MISSIONS._registry[id]
        local status = MISSIONS._status[id]
        local phase  = MISSIONS._cur_phase[id]
        local lbl
        if     status == "active"    then lbl = M.name .. " [" .. (phase or "?") .. "]"
        elseif status == "triggered" then lbl = M.name .. " [READY]"
        elseif status == "done"      then lbl = M.name .. " [done]"
        else                              lbl = M.name .. " [inactive]"
        end
        local mid = id
        addGMFunction(lbl, function()
            MISSIONS._showDetail(mid, backToMainFn)
        end)
    end
end

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

    local status_lbl = status .. (phase and (" / " .. phase) or "")
    addGMFunction(M.name .. ": " .. status_lbl, function() end)

    if M.triggers and not M.no_criteria_button then
        addGMFunction("Mission criteria", function()
            addGMMessage(MISSIONS._criteriaText(id))
        end)
    end

    if status == "inactive" or status == "triggered" then
        addGMFunction("Start " .. M.name, function()
            MISSIONS.start(id)
            MISSIONS._showDetail(id, backToMainFn)
        end)
    end

    if status == "active" then
        -- Phase jump buttons in declared order (skip current phase, skip no_skip phases).
        if M.phase_order then
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
        end

        -- Module-level custom GM actions (shown when mission is active).
        if M.gm_actions then
            for _, action in ipairs(M.gm_actions) do
                local a = action
                local show = true
                if a.phases then
                    show = false
                    for _, p in ipairs(a.phases) do
                        if p == phase then show = true; break end
                    end
                end
                if show then
                    addGMFunction(a.label, function()
                        pcall(a.fn, st)
                        MISSIONS._showDetail(id, backToMainFn)
                    end)
                end
            end
        end

        if not M.no_auto_cancel then
            addGMFunction("Cancel " .. M.name, function()
                MISSIONS.cancel(id)
                globalMessage(M.name .. " -- arc cancelled.", 5)
                MISSIONS._showDetail(id, backToMainFn)
            end)
        end
    end
end
