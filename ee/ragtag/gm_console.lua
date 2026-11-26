-- ee/ragtag/gm_console.lua
-- The campaign GM console: Campaign Status, Reputation..., Jobs..., Ship Upgrades...
-- Sits on top of everything (it reads RT, JOBS, STATS and friends), so it is loaded by the
-- scenario, not by core. A scenario's addSessionGMFunctions() calls GMCONSOLE.add{...} and then
-- adds its own buttons (story arcs, world plugins, campaign tools).
--
--   GMCONSOLE.add{session = <session number shown in Campaign Status>}
--
-- Submenus return to the main screen with clearGMFunctions() + addSessionGMFunctions(), the
-- global every campaign scenario defines.

GMCONSOLE = GMCONSOLE or {}

function GMCONSOLE.add(opts)
    opts = opts or {}
    addGMFunction("Campaign Status", function()
        local lines = {"=== CAMPAIGN STATUS ===\n"}
        if RT.campaign then
            table.insert(lines, string.format("Session: %d", (opts.session or 1)))
            -- The primary ship's record (the arc ship). Other ships: see OTHER SHIPS below.
            local primary = RT.player
            table.insert(lines, string.format("Credits: %d", RT.credits(primary)))

            -- Upgrades and investment
            local total_invested = RT.upgradeSpend(primary)
            local upgrade_lines = {}
            for _, id in ipairs(RT.upgrades(primary)) do
                local u = RT.upgradeById(id)
                if u then upgrade_lines[#upgrade_lines+1] = string.format("  %s (%dcr)", u.name, u.cost) end
            end
            local tier = JOBS.maxTier(primary)
            local next_threshold = tier == 0 and 500 or (tier == 1 and 1000 or nil)
            local tier_note = next_threshold
                and string.format(" — tier %d (next tier at %dcr)", tier, next_threshold)
                or  string.format(" — tier %d (max)", tier)
            table.insert(lines, string.format("\nUPGRADES: %dcr invested%s", total_invested, tier_note))
            if #upgrade_lines == 0 then
                table.insert(lines, "  (none)")
            else
                for _, l in ipairs(upgrade_lines) do table.insert(lines, l) end
            end

            table.insert(lines, "\nREPUTATION:")
            local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic", "Unknown"}
            for _, faction in ipairs(factions) do
                local rep = RT.getReputation(faction, primary)
                local standing = ""
                if rep >= 50 then standing = " (Friendly)"
                elseif rep >= 20 then standing = " (Liked)"
                elseif rep >= -20 then standing = " (Neutral)"
                elseif rep >= -50 then standing = " (Disliked)"
                else standing = " (Hostile)" end
                table.insert(lines, string.format("  %s: %+d%s", faction, rep, standing))
            end

            -- Every other player ship has its own credits, standing and upgrades.
            local others = {}
            for i = 2, #RT.players do
                local p = RT.players[i]
                if RT.valid(p) then
                    others[#others + 1] = string.format("  %s: %dcr, %dcr in upgrades (tier %d), Concord %+d, Independent %+d",
                        p:getCallSign(), RT.credits(p), RT.upgradeSpend(p), JOBS.maxTier(p),
                        RT.getReputation("Concord", p), RT.getReputation("Independent", p))
                end
            end
            if #others > 0 then
                table.insert(lines, "\nOTHER SHIPS:")
                for _, l in ipairs(others) do table.insert(lines, l) end
            end
        end
        -- Overall overview: money, jobs by type, regions, story arcs, achievements.
        if STATS then
            table.insert(lines, "")
            table.insert(lines, STATS.reportText())
        end
        addGMMessage(table.concat(lines, "\n"))
    end)

    local function _toMain()
        clearGMFunctions()
        addSessionGMFunctions()
    end

    -- Every player ship alive, primary first.
    local function _liveShips()
        local ships = {}
        RT.forEachPlayer(function(p) ships[#ships + 1] = p end)
        return ships
    end

    -- Reputation submenu. Standing is per ship: with several ships the GM picks one first
    -- (skipped when only one ship is in play).
    local showReputation, showReputationFactionList  -- forward declarations (mutual recursion)

    local function _repEffects(faction, rep)
        local lines = {}
        if faction == "Concord" then
            if rep < -500 then
                lines[#lines+1] = "  Action: Shakedowns suspended (treated as wanted)"
            elseif rep < -200 then
                lines[#lines+1] = "  Action: Inspection — detention threat, patrol goes hostile"
            elseif rep < 0 then
                lines[#lines+1] = "  Action: Inspection — fine offer"
            elseif rep < 200 then
                lines[#lines+1] = "  Action: Inspection — nothing flagged"
            elseif rep < 500 then
                lines[#lines+1] = "  Action: Inspection — clean pass"
            else
                lines[#lines+1] = "  Action: Inspection — callsign recognized, compliment"
            end
        elseif faction == "Corsairs" then
            if rep <= -400 then
                lines[#lines+1] = "  Action: Patrols 50% more frequent (very aggressive)"
            elseif rep <= -200 then
                lines[#lines+1] = "  Action: Patrols 30% more frequent"
            else
                lines[#lines+1] = "  Action: Patrol spawn rate normal"
            end
        elseif faction == "Hollow" or faction == "Relic" then
            lines[#lines+1] = "  Action: Always hostile — no rep effects"
            return lines
        end
        if rep < -400 then
            lines[#lines+1] = "  Jobs: board closed at this faction's stations"
        elseif rep < -200 then
            lines[#lines+1] = "  Jobs: 2 fewer offers at this faction's stations"
        elseif rep < 0 then
            lines[#lines+1] = "  Jobs: 1 fewer offer at this faction's stations"
        else
            lines[#lines+1] = "  Jobs: full board at this faction's stations"
        end
        return lines
    end

    local function showRepStatusPopup(p)
        if not RT.valid(p) then addGMMessage("That ship is gone."); return end
        local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic"}
        local msg = {"REPUTATION STATUS: " .. p:getCallSign()}
        for _, faction in ipairs(factions) do
            local rep = RT.getReputation(faction, p) or 0
            msg[#msg+1] = ""
            msg[#msg+1] = string.format("%s: %+d", faction, rep)
            for _, line in ipairs(_repEffects(faction, rep)) do
                msg[#msg+1] = line
            end
        end
        addGMMessage(table.concat(msg, "\n"))
    end

    local function showFactionDetail(faction, p)
        clearGMFunctions()
        addGMFunction("← Back to Factions", function() showReputationFactionList(p) end)
        if not RT.valid(p) then return end
        local current = RT.getReputation(faction, p) or 0
        addGMFunction(string.format("%s %s: %+d", p:getCallSign(), faction, current), function() end)
        addGMFunction("↑  +50", function()
            if RT.valid(p) then RT.addReputation(faction, 50, "GM adjustment", p) end
            RT.saveCampaign()
            showFactionDetail(faction, p)
        end)
        addGMFunction("↓  -50", function()
            if RT.valid(p) then RT.addReputation(faction, -50, "GM adjustment", p) end
            RT.saveCampaign()
            showFactionDetail(faction, p)
        end)
    end

    showReputationFactionList = function(p)
        clearGMFunctions()
        if #_liveShips() > 1 then
            addGMFunction("← Back to Ships", showReputation)
        else
            addGMFunction("← Back to Main", _toMain)
        end
        if not RT.valid(p) then return end
        addGMFunction("Rep Status: " .. p:getCallSign(), function() showRepStatusPopup(p) end)
        local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic"}
        for _, faction in ipairs(factions) do
            local rep = RT.getReputation(faction, p) or 0
            addGMFunction(string.format("%s (%+d)...", faction, rep), function()
                showFactionDetail(faction, p)
            end)
        end
    end

    showReputation = function()
        local ships = _liveShips()
        if #ships == 1 then showReputationFactionList(ships[1]); return end
        clearGMFunctions()
        addGMFunction("← Back to Main", _toMain)
        if #ships == 0 then addGMFunction("(no active ships)", function() end) end
        for _, p in ipairs(ships) do
            addGMFunction(p:getCallSign() .. "...", function() showReputationFactionList(p) end)
        end
    end

    addGMFunction("Reputation...", showReputation)

    local showJobsMenu
    local showUpgradesMenu
    local showShipUpgradesMenu

    WORLD.addGMButton(function()
        clearGMFunctions()
        addSessionGMFunctions()
    end)

    -- ── New delivery (Jobs... → New delivery...) ─────────────────────────────────
    -- The GM writes a delivery job: starting and ending port, cargo, time, pay and who it is for,
    -- then posts it on the starting port's board or hands it straight to a ship. EE's GM screen
    -- has buttons but no text box, so the cargo and its lines come from the delivery archetypes
    -- (picked, or Random). Time and pay start at what the board would offer ("suggested") and
    -- follow the ports until the GM changes them. The draft is kept between visits.
    local showNewDelivery, showPostedJobs, showPortPicker, showCargoPicker, showAdjust
    local GM_CATEGORY = "GM_JOBS"
    local PAGE = 12

    local function _delivery() return JOBS._registry["delivery"] end

    local function _draft()
        local d = GMCONSOLE._draft
        if not d then
            d = {arch_i = 0, urgent = false, special = true}
            GMCONSOLE._draft = d
        end
        if d.who ~= "any" and not RT.valid(d.who) then d.who = RT.player end
        return d
    end

    -- The ports a delivery can run between: universe stations with a job board, by name.
    local function _ports()
        local out = {}
        for _, s in ipairs(VERSE.STATIONS or {}) do
            if s.fac ~= "Corsairs" and s.fac ~= "Hollow" and RT.valid(RT.find(s.cs)) then
                out[#out + 1] = s.cs
            end
        end
        table.sort(out)
        return out
    end

    -- Posted GM jobs still in the engine (waiting on a board or taken and under way).
    local function _gmJobs()
        local out = {}
        for _, e in ipairs(JOBS._injected) do
            if e.category == GM_CATEGORY then out[#out + 1] = e end
        end
        return out
    end

    local function _arch(d)
        return d.arch_i > 0 and _delivery().archetypes()[d.arch_i] or nil
    end

    local function _who(d)
        if d.who == "any" then return nil end
        return d.who
    end

    local function _whoName(d)
        if d.who == "any" then return "any ship" end
        return RT.valid(d.who) and d.who:getCallSign() or "?"
    end

    -- The board's pay and time for the draft, or nil until both ports are set.
    local function _suggested(d)
        if not (d.origin and d.dest) then return nil end
        return _delivery().suggest{origin = d.origin, dest = d.dest, urgent = d.urgent,
                                   arch = _arch(d), ship = _who(d)}
    end

    local function _mins(secs) return string.format("%dm", math.floor(secs / 60)) end

    -- The draft as a job record (cargo resolved now when Random), or nil and why not.
    local function _buildJob(d)
        if not d.origin then return nil, "Pick a starting port first." end
        if not d.dest then return nil, "Pick an ending port first." end
        if d.origin == d.dest then return nil, "The starting and ending ports are the same." end
        local pay, secs = _suggested(d)
        if not pay then return nil, "One of the ports is gone." end
        local arch = _arch(d)
        if not arch then
            local pool = _delivery().archetypesFor(JOBS.stationFaction(d.origin))
            arch = pool[math.random(#pool)]
        end
        local m = JOBS.build("delivery", {
            origin = d.origin, dest = d.dest, cargo = arch.cargo, urgent = d.urgent,
            reward = d.pay or pay, time_limit = d.secs or secs,
            brief = arch.lore .. "\n\n" .. arch.accept_msg, complete_msg = arch.recv_msg,
            story = d.special or nil, category = GM_CATEGORY,
        })
        m.tier = math.min(JOBS.maxTier(_who(d)), 1)
        return m
    end

    local function _summary(m, where)
        return string.format("%s%s: %s\n%dm, %dcr, for %s.\n\n%s",
            m.special and "[SPECIAL] " or "", where, m.short, math.floor(m.time_limit / 60), m.reward,
            _whoName(_draft()), m.brief)
    end

    local function _post(d)
        local m, why = _buildJob(d)
        if not m then addGMMessage(why); return end
        local inj_id
        local function gone() JOBS.removeInjected(inj_id) end
        m.on_complete, m.on_fail = gone, gone   -- finished either way: off the GM list, never re-offered
        inj_id = JOBS.inject{
            category = GM_CATEGORY, priority = 5, origin = d.origin, record = m,
            any_ship = (d.who == "any") or nil,
            for_ship = (d.who ~= "any" and d.who ~= RT.player) and d.who or nil,
        }
        addGMMessage(_summary(m, "Posted at " .. d.origin))
    end

    local function _assign(d)
        local ship = _who(d) or RT.player
        local m, why = _buildJob(d)
        if not m then addGMMessage(why); return end
        if not RT.valid(ship) then addGMMessage("No ship to give it to."); return end
        if not JOBS.accept(m, false, ship) then
            addGMMessage(ship:getCallSign() .. " already has " .. JOBS.config.max_active
                .. " jobs. Make it [SPECIAL] (no cap), or post it.")
            return
        end
        JOBS.log(m, m.brief)
        addGMMessage(_summary(m, "Given to " .. ship:getCallSign()))
    end

    showNewDelivery = function()
        clearGMFunctions()
        local d = _draft()
        addGMFunction("← Back to Jobs", function() showJobsMenu() end)
        addGMFunction("From: " .. (d.origin or "(pick)") .. "...", function() showPortPicker("origin", 1) end)
        addGMFunction("To: " .. (d.dest or "(pick)") .. "...", function() showPortPicker("dest", 1) end)
        local arch = _arch(d)
        addGMFunction("Cargo: " .. (arch and arch.cargo or "Random") .. "...", function() showCargoPicker(1) end)
        addGMFunction("Urgent: " .. (d.urgent and "yes" or "no"), function()
            d.urgent = not d.urgent
            showNewDelivery()
        end)
        local pay, secs = _suggested(d)
        local function adj(val, sug, fmt)
            if not sug then return "(pick ports)" end
            if not val or val == sug then return fmt(sug) .. " (suggested)" end
            return fmt(val) .. " (sugg. " .. fmt(sug) .. ")"
        end
        addGMFunction("Time: " .. adj(d.secs, secs, _mins) .. "...", function() showAdjust("secs") end)
        addGMFunction("Pay: " .. adj(d.pay, pay, function(v) return v .. "cr" end) .. "...", function() showAdjust("pay") end)
        addGMFunction("Kind: " .. (d.special and "[SPECIAL]" or "normal work"), function()
            d.special = not d.special
            showNewDelivery()
        end)
        addGMFunction("For: " .. _whoName(d), function()
            -- Cycle: each live ship (primary first), then any ship.
            local list = {}
            RT.forEachPlayer(function(p) list[#list + 1] = p end)
            list[#list + 1] = "any"
            local at = 0
            for i, w in ipairs(list) do if w == d.who then at = i end end
            d.who = list[at % #list + 1]
            showNewDelivery()
        end)
        addGMFunction("Post at " .. (d.origin and JOBS.shortName(d.origin) or "start"), function()
            _post(d); showNewDelivery()
        end)
        if d.who ~= "any" then
            addGMFunction("Assign now to " .. _whoName(d), function() _assign(d); showNewDelivery() end)
        end
        addGMFunction("Clear draft", function()
            GMCONSOLE._draft = nil
            showNewDelivery()
        end)
    end

    -- A paged list: header buttons, then PAGE entries from `items` (label, fn) with Previous/Next.
    local function _paged(items, page, reopen)
        local pages = math.max(1, math.ceil(#items / PAGE))
        page = math.max(1, math.min(page, pages))
        for i = (page - 1) * PAGE + 1, math.min(#items, page * PAGE) do
            addGMFunction(items[i].label, items[i].fn)
        end
        if page > 1 then addGMFunction("◀ Previous", function() reopen(page - 1) end) end
        if page < pages then addGMFunction("Next ▶", function() reopen(page + 1) end) end
    end

    showPortPicker = function(field, page)
        clearGMFunctions()
        local d = _draft()
        addGMFunction("← Back to the job", function() showNewDelivery() end)
        addGMFunction("Use map selection", function()
            local picked
            for _, obj in ipairs(getGMSelection() or {}) do
                for _, cs in ipairs(_ports()) do
                    if RT.find(cs) == obj then picked = cs end
                end
            end
            if not picked then
                addGMMessage("Select one port on the map first (not a Corsair or Hollow station).")
                return
            end
            d[field] = picked
            showNewDelivery()
        end)
        local items = {}
        for _, cs in ipairs(_ports()) do
            items[#items + 1] = {label = (d[field] == cs and "* " or "") .. cs, fn = function()
                d[field] = cs
                showNewDelivery()
            end}
        end
        _paged(items, page, function(p) showPortPicker(field, p) end)
    end

    showCargoPicker = function(page)
        clearGMFunctions()
        local d = _draft()
        addGMFunction("← Back to the job", function() showNewDelivery() end)
        addGMFunction((d.arch_i == 0 and "* " or "") .. "Random", function()
            d.arch_i = 0
            showNewDelivery()
        end)
        local items = {}
        for i, a in ipairs(_delivery().archetypes()) do
            local label = a.cargo .. (a.urgent and " (urgent)" or "") .. (a.fac and (" [" .. a.fac .. "]") or "")
            items[#items + 1] = {label = (d.arch_i == i and "* " or "") .. label, fn = function()
                d.arch_i = i
                d.urgent = a.urgent and true or false
                showNewDelivery()
            end}
        end
        _paged(items, page, showCargoPicker)
    end

    -- field = "secs" (time limit) or "pay". nil in the draft = follow the suggestion.
    showAdjust = function(field)
        clearGMFunctions()
        local d = _draft()
        local pay, secs = _suggested(d)
        local sug = (field == "secs") and secs or pay
        if not sug then addGMMessage("Pick both ports first."); return showNewDelivery() end
        local cur = d[field] or sug
        local steps, floor, show
        if field == "secs" then
            steps, floor, show = {{"−5 min", -300}, {"−1 min", -60}, {"+1 min", 60}, {"+5 min", 300}}, 60, _mins
        else
            steps, floor, show = {{"−100cr", -100}, {"−25cr", -25}, {"+25cr", 25}, {"+100cr", 100}}, 5,
                                 function(v) return v .. "cr" end
        end
        addGMFunction("← Done (" .. show(cur) .. ")", function() showNewDelivery() end)
        for _, s in ipairs(steps) do
            local delta = s[2]
            addGMFunction(s[1], function()
                d[field] = math.max(floor, cur + delta)
                showAdjust(field)
            end)
        end
        addGMFunction("Use suggested (" .. show(sug) .. ")", function()
            d[field] = nil
            showAdjust(field)
        end)
    end

    showPostedJobs = function()
        clearGMFunctions()
        addGMFunction("← Back to Jobs", function() showJobsMenu() end)
        local list = _gmJobs()
        if #list == 0 then addGMFunction("(none posted)", function() end) end
        for _, e in ipairs(list) do
            local m = e.record
            if m and JOBS._done[m.id] then
                local who = RT.valid(m.ship) and m.ship:getCallSign() or "?"
                addGMFunction("Taken (" .. who .. "): " .. m.short, function() end)
            elseif m then
                addGMFunction("Withdraw: " .. m.short .. " @ " .. JOBS.shortName(m.origin), function()
                    JOBS.removeInjected(e.id)
                    showPostedJobs()
                end)
            end
        end
    end

    local _DISTANCE_MODES = {"short", "medium", "long"}
    local _DISTANCE_NAMES = {short = "Short", medium = "Medium", long = "Long"}

    showJobsMenu = function()
        clearGMFunctions()
        addGMFunction("← Back to Main", function()
            clearGMFunctions()
            addSessionGMFunctions()
        end)

        addGMFunction("New delivery...", function() showNewDelivery() end)
        addGMFunction("Posted GM jobs (" .. #_gmJobs() .. ")...", function() showPostedJobs() end)

        local cool_on = JOBS.config.work_cooldown_enabled
        addGMFunction("Work Cooldown: " .. (cool_on and "ON" or "OFF"), function()
            JOBS.config.work_cooldown_enabled = not JOBS.config.work_cooldown_enabled
            showJobsMenu()
        end)

        local cur_dist = JOBS.config.mission_distance_mode
        for _, mode in ipairs(_DISTANCE_MODES) do
            local cap_mode = mode
            addGMFunction((mode == cur_dist and "* " or "") .. "Dist: " .. _DISTANCE_NAMES[mode], function()
                JOBS.config.mission_distance_mode = cap_mode
                showJobsMenu()
            end)
        end

        -- Credits are per ship: one pair of buttons per ship (named when there are several).
        local ships = _liveShips()
        for _, p in ipairs(ships) do
            local who = (#ships > 1) and (p:getCallSign() .. " ") or ""
            addGMFunction(who .. "Credits +50", function()
                if RT.valid(p) then RT.addCredits(50, "GM reward", p) end
                showJobsMenu()
            end)
            addGMFunction(who .. "Credits -50", function()
                if RT.valid(p) then RT.addCredits(-50, "GM penalty", p) end
                showJobsMenu()
            end)
        end
    end
    addGMFunction("Jobs...", showJobsMenu)

    -- Upgrades submenu
    local _UPGRADE_GROUPS = {
        {label = "Hull",      ids = {"hull_plating", "hull_plating_2", "hull_plating_3"}},
        {label = "Shields",   ids = {"shield_mk2", "shield_mk3", "shield_mk4"}},
        {label = "Beams",     ids = {"forward_beams", "beam_coils", "beam_coils_2", "heavy_beams", "sniper_beam"}},
        {label = "Missiles",  ids = {"missile_racks", "missile_racks_2"}},
        {label = "Tubes",     ids = {"front_tube", "side_tubes"}},
        {label = "Impulse",   ids = {"engine_tune", "engine_tune_2"}},
        {label = "Thrusters", ids = {"combat_thrusters"}},
        {label = "Reactor",   ids = {"reactor_overhaul", "coolant_pump", "coolant_pump_2"}},
        {label = "Repair",    ids = {"repair_crew", "repair_crew_2", "repair_crew_3"}},
        {label = "Sensors",   ids = {"sensor_suite", "sensor_suite_2", "sensor_suite_3"}},
        {label = "Probes",    ids = {"fast_probes", "ludicrous_probes"}},
    }

    -- Upgrades are per ship: every function below works on `p`, the ship picked in the list.
    local function _upgradeLabel(group_label, idx, u, p)
        local locked = not RT.hasUpgrade(u.id, p) and not RT.upgradeOpen(u, p)
        local glyph
        if locked then
            glyph = "×"
        elseif u.crew then
            glyph = (RT.valid(p) and p:getRepairCrewCount() < 8) and "□" or "■"
        else
            glyph = RT.hasUpgrade(u.id, p) and "■" or "□"
        end
        return glyph .. " " .. (u.gm_label or (group_label .. " lvl " .. (idx + 1)))
    end

    local function showShipStatusPopup(p)
        if not RT.valid(p) then addGMMessage("That ship is gone."); return end

        local total_invested = RT.upgradeSpend(p)

        local function uline(id)
            local u = RT.upgradeById(id)
            if not u then return end
            if RT.hasUpgrade(id, p) then
                return string.format("  ■ %s (%dcr)", u.name, u.cost)
            elseif RT.upgradeExcludedBy(u, p) then
                return string.format("  × %s (%dcr)  instead of: %s", u.name, u.cost, RT.upgradeExcludedBy(u, p).name)
            elseif not RT.upgradeNeedsMet(u, p) then
                return string.format("  × %s (%dcr)  needs: %s", u.name, u.cost, RT.upgradeNeedsText(u))
            else
                return string.format("  □ %s (%dcr)", u.name, u.cost)
            end
        end

        local L = {"=== SHIP STATUS: " .. p:getCallSign() .. " ===\n"}
        local function add(s) L[#L+1] = s end
        local function sec(s) add("\n" .. s) end

        add(string.format("Invested: %dcr  |  Job tier: %d\n", total_invested, JOBS.maxTier(p)))

        sec("HULL")
        add(uline("hull_plating")); add(uline("hull_plating_2")); add(uline("hull_plating_3"))
        add(string.format("  hp: %d / %d", math.floor(p:getHull()), math.floor(p:getHullMax())))

        sec("SHIELDS")
        add(uline("shield_mk2")); add(uline("shield_mk3")); add(uline("shield_mk4"))
        local sc = p:getShieldCount()
        if sc >= 2 then
            add(string.format("  front %d/%d  rear %d/%d",
                math.floor(p:getShieldLevel(0)), math.floor(p:getShieldMax(0)),
                math.floor(p:getShieldLevel(1)), math.floor(p:getShieldMax(1))))
        elseif sc == 1 then
            add(string.format("  shield %d/%d", math.floor(p:getShieldLevel(0)), math.floor(p:getShieldMax(0))))
        end

        sec("BEAMS")
        add(uline("forward_beams")); add(uline("beam_coils")); add(uline("beam_coils_2")); add(uline("heavy_beams")); add(uline("sniper_beam"))
        for i = 0, 7 do
            local range = p:getBeamWeaponRange(i)
            if range ~= nil and range > 0 then
                add(string.format("  [%d] dir %d°  arc %d°  rng %dm  %.1fs  %.0fdmg",
                    i, math.floor(p:getBeamWeaponDirection(i)), math.floor(p:getBeamWeaponArc(i)),
                    math.floor(range), p:getBeamWeaponCycleTime(i), p:getBeamWeaponDamage(i)))
            end
        end

        sec("WEAPONS")
        add(uline("missile_racks")); add(uline("missile_racks_2")); add(uline("front_tube")); add(uline("side_tubes"))
        add(string.format("  tubes: %d  homing: %d/%d  HVLI: %d/%d",
            p:getWeaponTubeCount(),
            p:getWeaponStorage("Homing"), p:getWeaponStorageMax("Homing"),
            p:getWeaponStorage("HVLI"), p:getWeaponStorageMax("HVLI")))

        sec("IMPULSE")
        add(uline("engine_tune")); add(uline("engine_tune_2"))
        local fwd, rev = p:getImpulseMaxSpeed()
        add(string.format("  fwd %.0f / rev %.0f u/s", fwd, rev))

        sec("THRUSTERS")
        add(uline("combat_thrusters"))
        add("  combat maneuver: " .. (RT.hasUpgrade("combat_thrusters", p) and "enhanced" or "default"))

        sec("REACTOR")
        add(uline("reactor_overhaul")); add(uline("coolant_pump")); add(uline("coolant_pump_2"))
        add(string.format("  energy: %.0f / %.0f  coolant: %.0f%%", p:getEnergy(), p:getMaxEnergy(), p:getMaxCoolant() * 10))

        sec("REPAIR")
        add(uline("repair_crew")); add(uline("repair_crew_2")); add(uline("repair_crew_3"))
        add(string.format("  crew: %d / 8 max", p:getRepairCrewCount()))

        sec("SENSORS")
        add(uline("sensor_suite")); add(uline("sensor_suite_2")); add(uline("sensor_suite_3"))
        add(string.format("  LR: %.0fu  SR: %.0fu",
            p:getLongRangeRadarRange() / 1000, p:getShortRangeRadarRange() / 1000))

        sec("PROBES")
        add(uline("fast_probes")); add(uline("ludicrous_probes"))
        local spd = RT.PROBE_SPEED_STOCK
        for _, id in ipairs({"ludicrous_probes", "fast_probes"}) do
            if RT.hasUpgrade(id, p) then spd = RT.upgradeById(id).probe_speed; break end
        end
        add(string.format("  speed: %d wu/s (%d U/min)", spd, spd * 60 / 1000))

        addGMMessage(table.concat(L, "\n"))
    end

    showShipUpgradesMenu = function(p)
        clearGMFunctions()
        addGMFunction("← Ships", function() showUpgradesMenu() end)
        if not RT.valid(p) then return end
        addGMFunction("Ship Status", function() showShipStatusPopup(p) end)
        for _, group in ipairs(_UPGRADE_GROUPS) do
            for idx, uid in ipairs(group.ids) do
                local u = RT.upgradeById(uid)
                if u then
                    local cap_id   = uid
                    local cap_crew = u.crew
                    addGMFunction(_upgradeLabel(group.label, idx, u, p), function()
                        local prereq_ok = RT.upgradeOpen(u, p)
                        if cap_crew then
                            if prereq_ok and RT.valid(p) and p:getRepairCrewCount() < 8 then
                                if RT.hasUpgrade(cap_id, p) then
                                    RT.applyUpgrade(p, cap_id)   -- owned but crew died; restore
                                else
                                    RT.grantUpgrade(cap_id, "GM", p)
                                end
                            end
                        else
                            if RT.hasUpgrade(cap_id, p) then
                                RT.revokeUpgrade(cap_id, p)
                            elseif prereq_ok then
                                RT.grantUpgrade(cap_id, "GM", p)
                            end
                        end
                        showShipUpgradesMenu(p)
                    end)
                end
            end
        end
    end

    showUpgradesMenu = function()
        clearGMFunctions()
        addGMFunction("← Back to Main", function()
            clearGMFunctions()
            addSessionGMFunctions()
        end)
        local count = 0
        RT.forEachPlayer(function(p)
            count = count + 1
            addGMFunction(p:getCallSign(), function() showShipUpgradesMenu(p) end)
        end)
        if count == 0 then
            addGMFunction("(no active ships)", function() end)
        end
    end
    addGMFunction("Ship Upgrades...", showUpgradesMenu)
end
