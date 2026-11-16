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
            table.insert(lines, string.format("Credits: %d", RT.campaign.credits))

            -- Upgrades and investment
            local cost_map = {}
            for _, u in ipairs(RT.UPGRADES) do cost_map[u.id] = u.cost end
            local total_invested = 0
            local upgrade_lines = {}
            for _, id in ipairs(RT.campaign.upgrades or {}) do
                local cost = cost_map[id] or 0
                total_invested = total_invested + cost
                for _, u in ipairs(RT.UPGRADES) do
                    if u.id == id then
                        upgrade_lines[#upgrade_lines+1] = string.format("  %s (%dcr)", u.name, cost)
                        break
                    end
                end
            end
            local tier = JOBS.maxTier()
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
                local rep = RT.getReputation(faction)
                local standing = ""
                if rep >= 50 then standing = " (Friendly)"
                elseif rep >= 20 then standing = " (Liked)"
                elseif rep >= -20 then standing = " (Neutral)"
                elseif rep >= -50 then standing = " (Disliked)"
                else standing = " (Hostile)" end
                table.insert(lines, string.format("  %s: %+d%s", faction, rep, standing))
            end
        end
        -- Overall overview: money, jobs by type, regions, story arcs, achievements.
        if STATS then
            table.insert(lines, "")
            table.insert(lines, STATS.reportText())
        end
        addGMMessage(table.concat(lines, "\n"))
    end)

    -- Reputation submenu
    local showReputationFactionList  -- forward declaration (mutual recursion)

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

    local function showRepStatusPopup()
        local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic"}
        local msg = {"REPUTATION STATUS"}
        for _, faction in ipairs(factions) do
            local rep = RT.getReputation(faction) or 0
            msg[#msg+1] = ""
            msg[#msg+1] = string.format("%s: %+d", faction, rep)
            for _, line in ipairs(_repEffects(faction, rep)) do
                msg[#msg+1] = line
            end
        end
        addGMMessage(table.concat(msg, "\n"))
    end

    local function showFactionDetail(faction)
        clearGMFunctions()
        addGMFunction("← Back to Factions", showReputationFactionList)
        local current = RT.getReputation(faction) or 0
        addGMFunction(string.format("%s: %+d", faction, current), function() end)
        addGMFunction("↑  +50", function()
            RT.addReputation(faction, 50, "GM adjustment")
            RT.saveCampaign()
            showFactionDetail(faction)
        end)
        addGMFunction("↓  -50", function()
            RT.addReputation(faction, -50, "GM adjustment")
            RT.saveCampaign()
            showFactionDetail(faction)
        end)
    end

    showReputationFactionList = function()
        clearGMFunctions()
        addGMFunction("← Back to Main", function()
            clearGMFunctions()
            addSessionGMFunctions()
        end)
        addGMFunction("Rep Status", showRepStatusPopup)
        local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic"}
        for _, faction in ipairs(factions) do
            local rep = RT.getReputation(faction) or 0
            addGMFunction(string.format("%s (%+d)...", faction, rep), function()
                showFactionDetail(faction)
            end)
        end
    end

    addGMFunction("Reputation...", showReputationFactionList)

    local showJobsMenu
    local showUpgradesMenu
    local showShipUpgradesMenu

    WORLD.addGMButton(function()
        clearGMFunctions()
        addSessionGMFunctions()
    end)

    local _DISTANCE_MODES = {"short", "medium", "long"}
    local _DISTANCE_NAMES = {short = "Short", medium = "Medium", long = "Long"}

    showJobsMenu = function()
        clearGMFunctions()
        addGMFunction("← Back to Main", function()
            clearGMFunctions()
            addSessionGMFunctions()
        end)

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

        addGMFunction("Credits +50", function()
            if RT.valid(RT.player) then RT.addCredits(50, "GM reward") end
            showJobsMenu()
        end)
        addGMFunction("Credits -50", function()
            if RT.valid(RT.player) then RT.addCredits(-50, "GM penalty") end
            showJobsMenu()
        end)
    end
    addGMFunction("Jobs...", showJobsMenu)

    -- Upgrades submenu
    local _UPGRADE_GROUPS = {
        {label = "Hull",      ids = {"hull_plating", "hull_plating_2"}},
        {label = "Shields",   ids = {"shield_mk2", "shield_mk3"}},
        {label = "Beams",     ids = {"forward_beams", "beam_coils", "heavy_beams"}},
        {label = "Weapons",   ids = {"missile_racks", "front_tube"}},
        {label = "Impulse",   ids = {"engine_tune"}},
        {label = "Thrusters", ids = {"combat_thrusters"}},
        {label = "Warp",      ids = {"warp_overhaul"}},
        {label = "Reactor",   ids = {"reactor_overhaul"}},
        {label = "Repair",    ids = {"repair_crew", "repair_crew_2", "repair_crew_3"}},
        {label = "Sensors",   ids = {"sensor_suite"}},
        {label = "Probes",    ids = {"fast_probes", "ludicrous_probes"}},
    }

    local function _revokeUpgrade(id)
        local new_list = {}
        for _, uid in ipairs(RT.campaign.upgrades) do
            if uid ~= id then new_list[#new_list + 1] = uid end
        end
        RT.campaign.upgrades = new_list
        RT.forEachPlayer(function(p)
            local x, y  = p:getPosition()
            local rot   = p:getRotation()
            local cs    = p:getCallSign()
            local fac   = p:getFaction()
            p:setTemplate(RT.PLAYER_TEMPLATE)
            p:setCallSign(cs)
            p:setFaction(fac)
            p:setPosition(x, y)
            p:setRotation(rot)
            for _, uid in ipairs(RT.campaign.upgrades) do RT.applyUpgrade(p, uid) end
        end)
        RT.saveCampaign()
        local u = RT.upgradeById(id)
        if u then RT.shipLog("Upgrade removed: " .. u.name, "#FF8080") end
    end

    local function _upgradeLabel(group_label, idx, u)
        local locked = u.requires ~= nil and not RT.hasUpgrade(u.requires)
        local glyph
        if locked then
            glyph = "×"
        elseif u.crew then
            local p = RT.player
            glyph = (RT.valid(p) and p:getRepairCrewCount() < 8) and "□" or "■"
        else
            glyph = RT.hasUpgrade(u.id) and "■" or "□"
        end
        return glyph .. " " .. (u.gm_label or (group_label .. " lvl " .. (idx + 1)))
    end

    local function showShipStatusPopup()
        local p = RT.player
        if not RT.valid(p) then addGMMessage("No active player ship."); return end

        local cost_map = {}
        for _, u in ipairs(RT.UPGRADES) do cost_map[u.id] = u.cost end
        local total_invested = 0
        for _, id in ipairs(RT.campaign.upgrades or {}) do
            total_invested = total_invested + (cost_map[id] or 0)
        end

        local function uline(id)
            local u = RT.upgradeById(id)
            if not u then return end
            if RT.hasUpgrade(id) then
                return string.format("  ■ %s (%dcr)", u.name, u.cost)
            elseif u.requires and not RT.hasUpgrade(u.requires) then
                local req = RT.upgradeById(u.requires)
                return string.format("  × %s (%dcr)  needs: %s", u.name, u.cost, req and req.name or u.requires)
            else
                return string.format("  □ %s (%dcr)", u.name, u.cost)
            end
        end

        local L = {"=== SHIP STATUS ===\n"}
        local function add(s) L[#L+1] = s end
        local function sec(s) add("\n" .. s) end

        add(string.format("Invested: %dcr  |  Job tier: %d\n", total_invested, JOBS.maxTier()))

        sec("HULL")
        add(uline("hull_plating")); add(uline("hull_plating_2"))
        add(string.format("  hp: %d / %d", math.floor(p:getHull()), math.floor(p:getHullMax())))

        sec("SHIELDS")
        add(uline("shield_mk2")); add(uline("shield_mk3"))
        local sc = p:getShieldCount()
        if sc >= 2 then
            add(string.format("  front %d/%d  rear %d/%d",
                math.floor(p:getShieldLevel(0)), math.floor(p:getShieldMax(0)),
                math.floor(p:getShieldLevel(1)), math.floor(p:getShieldMax(1))))
        elseif sc == 1 then
            add(string.format("  shield %d/%d", math.floor(p:getShieldLevel(0)), math.floor(p:getShieldMax(0))))
        end

        sec("BEAMS")
        add(uline("forward_beams")); add(uline("beam_coils")); add(uline("heavy_beams"))
        for i = 0, 7 do
            local range = p:getBeamWeaponRange(i)
            if range ~= nil and range > 0 then
                add(string.format("  [%d] dir %d°  arc %d°  rng %dm  %.1fs  %.0fdmg",
                    i, math.floor(p:getBeamWeaponDirection(i)), math.floor(p:getBeamWeaponArc(i)),
                    math.floor(range), p:getBeamWeaponCycleTime(i), p:getBeamWeaponDamage(i)))
            end
        end

        sec("WEAPONS")
        add(uline("missile_racks")); add(uline("front_tube"))
        add(string.format("  tubes: %d  homing: %d/%d  HVLI: %d/%d",
            p:getWeaponTubeCount(),
            p:getWeaponStorage("Homing"), p:getWeaponStorageMax("Homing"),
            p:getWeaponStorage("HVLI"), p:getWeaponStorageMax("HVLI")))

        sec("IMPULSE")
        add(uline("engine_tune"))
        local fwd, rev = p:getImpulseMaxSpeed()
        add(string.format("  fwd %.0f / rev %.0f u/s", fwd, rev))

        sec("THRUSTERS")
        add(uline("combat_thrusters"))
        add("  combat maneuver: " .. (RT.hasUpgrade("combat_thrusters") and "enhanced" or "default"))

        sec("WARP")
        add(uline("warp_overhaul"))
        add(string.format("  speed: %.0f wu/s", p:getWarpSpeed()))

        sec("REACTOR")
        add(uline("reactor_overhaul"))
        add(string.format("  energy: %.0f / %.0f", p:getEnergy(), p:getMaxEnergy()))

        sec("REPAIR")
        add(uline("repair_crew")); add(uline("repair_crew_2")); add(uline("repair_crew_3"))
        add(string.format("  crew: %d / 8 max", p:getRepairCrewCount()))

        sec("SENSORS")
        add(uline("sensor_suite"))
        add(string.format("  LR: %.0fu  SR: %.0fu",
            p:getLongRangeRadarRange() / 1000, p:getShortRangeRadarRange() / 1000))

        sec("PROBES")
        add(uline("fast_probes")); add(uline("ludicrous_probes"))
        local spd = RT.hasUpgrade("ludicrous_probes") and 4000
                 or RT.hasUpgrade("fast_probes") and 2000 or 1000
        add(string.format("  speed: %d wu/s", spd))

        addGMMessage(table.concat(L, "\n"))
    end

    showShipUpgradesMenu = function(ship_cs)
        clearGMFunctions()
        addGMFunction("← Ships", function() showUpgradesMenu() end)
        addGMFunction("Ship Status", function() showShipStatusPopup() end)
        for _, group in ipairs(_UPGRADE_GROUPS) do
            for idx, uid in ipairs(group.ids) do
                local u = RT.upgradeById(uid)
                if u then
                    local cap_id   = uid
                    local cap_req  = u.requires
                    local cap_crew = u.crew
                    addGMFunction(_upgradeLabel(group.label, idx, u), function()
                        if cap_crew then
                            local prereq_ok = cap_req == nil or RT.hasUpgrade(cap_req)
                            local p = RT.player
                            if prereq_ok and RT.valid(p) and p:getRepairCrewCount() < 8 then
                                if RT.hasUpgrade(cap_id) then
                                    RT.applyUpgrade(p, cap_id)   -- owned but crew died; restore
                                else
                                    RT.grantUpgrade(cap_id)
                                end
                            end
                        else
                            if RT.hasUpgrade(cap_id) then
                                _revokeUpgrade(cap_id)
                            elseif cap_req == nil or RT.hasUpgrade(cap_req) then
                                RT.grantUpgrade(cap_id)
                            end
                        end
                        showShipUpgradesMenu(ship_cs)
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
            local cs = p:getCallSign()
            addGMFunction(cs, function() showShipUpgradesMenu(cs) end)
        end)
        if count == 0 then
            addGMFunction("(no active ships)", function() end)
        end
    end
    addGMFunction("Ship Upgrades...", showUpgradesMenu)
end
