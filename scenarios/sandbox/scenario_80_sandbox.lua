-- Name: Sandbox: Open Play
-- Description: Explore the Drift, earn credits, upgrade your ship. No fixed story--make your own. Perfect for learning the universe and trying out ship systems. The AI director creates dynamic encounters based on your choices.
---
--- Sandbox campaign. Credits and upgrades persist across sessions. No fixed objectives.
--- Optional: run the AI director (director/main.py) for dynamic encounters and opportunities.
-- Type: The Drift Universe
-- Setting[Campaign]: Use saved campaign progress or start over.
-- Campaign[Continue|Default]: Keep credits and upgrades from earlier sessions.
-- Campaign[Fresh start]: Wipe campaign progress and start with a stock ship.
-- Setting[Starting Credits]: How much money to start with (Fresh start only).
-- Starting Credits[Modest (200)|Default]: Enough for a few repairs or one small upgrade.
-- Starting Credits[Comfortable (500)]: Enough to buy a decent upgrade right away.
-- Starting Credits[Well-off (1000)]: Can afford multiple upgrades immediately.
-- Setting[Danger Level]: How aggressive the universe is.
-- Danger Level[Relaxed]: Fewer hostiles, more time to explore.
-- Danger Level[Normal|Default]: Balanced encounters.
-- Danger Level[Dangerous]: More hostiles, tighter director budget for spawns.
-- Setting[Director]: Whether the scenario talks to the external AI director.
-- Director[On|Default]: Dynamic encounters and opportunities from the AI director.
-- Director[Off]: Static universe with scripted random encounters only.

require("utils.lua")
require("ragtag/core.lua")
require("ragtag/verse.lua")
require("ragtag/director.lua")
require("ragtag/jobs.lua")
require("ragtag/missions.lua")
require("ragtag/world.lua")
require("ragtag/ship_templates.lua")  -- custom playership templates; must load before init

local SESSION_ID = "sandbox"

-- Named ships available to the campaign — slot 1 is always the primary.
-- All are Flavia P.Falcon class; names are birds (sister ships to the Magpie).
local _SHIP_ROSTER = {
    "Magpie", "Raven", "Jackdaw", "Starling", "Wren",
    "Kestrel", "Harrier", "Merlin", "Osprey", "Swift",
}

-- Session state
local S = {
    phase = "start",           -- start, exploring, docked, ending
    session_num = 1,           -- which sandbox session this is
    time_exploring = 0,        -- time spent not docked
    visited_regions = {},      -- track where crew has been
    docked_at = nil,
    ending = false,
    vesper_first_hail = false, -- track first hail to Port Vesper for welcome message
}

--------------------------------------------------------------------------------
-- Rumors and wreck logs
--------------------------------------------------------------------------------

local WreckLog = {}

-- Wreck story fragments, keyed by callsign.
local _WRECK_LOGS = {
    -- Boneyard -- Settlement War hulks
    ["CWS Bulwark"]        = '"Day 47 of the siege. Captain Orin to any Concord command: we are holding Ashgrave approach. We are still holding. Please respond."',
    ["Free Ship Defiance"] = '"They told us the vote would be bloodless. Somebody forgot to tell the gunships."  -- last entry, Free Ship Defiance.',
    ["CWS Morningside"]    = 'Distress beacon, CWS Morningside, crew of eleven. Hull breach compartments three through seven. "If anyone receives this -- we were here."',
    ["Free Ship Hollis"]   = 'Hollis crew manifest recovered from emergency memory. Forty-one names. The war ended six weeks after they launched.',
    ["CWS Anvil"]          = '"We\'re not retreating. We\'re advancing in a new direction." -- Commander Vayne, CWS Anvil. Last words before the bridge lost pressure.',
    ["Free Ship Tallow"]   = '"If you\'re reading this, the settlement worked. Tell my kids I held the line."  -- Tallow final transmission.',
    ["CWS Equity"]         = '"We surrendered at 0400. The Concord officer was kind about it. I don\'t know what to make of that."  -- Captain\'s log, CWS Equity.',
    ["Free Ship Long Odds"] = 'Encrypted fragment, twenty-year-old code. "Rally at Ashgrave. One last push."  Free Ship Long Odds never arrived.',
    ["CWS Clarion"]        = 'Automated beacon, CWS Clarion, looping since the war ended. Hull integrity: 12%. Crew status: unknown. Unknown. Unknown.',
    ["Free Ship Harrow"]   = '"You\'re fighting for a rock." "We\'re fighting so the rock is ours."  End of argument. End of recording.',
    ["CWS Mercy"]          = '"We have more injured than bay capacity. I am going to run out of things to write."  -- Medical log, CWS Mercy.',
    ["Free Ship Whistler"] = 'Navigation log, Free Ship Whistler. Last entry automated. Destination: Tamsin. Arrival: never.',
    -- Dustmote -- recent hulks
    ["Hulk 7"]  = 'Salvage tag attached: "Strip to frame, sell the rest." Someone didn\'t finish the job.',
    ["Hulk 12"] = 'Registry plate still readable: Persistent Hope. Someone scraped off the name but left the plate.',
    ["Hulk 19"] = 'A coffee mug magnetically clamped to the helm. Still has coffee in it. Relatively recent.',
    ["Hulk 23"] = 'Personal log found wedged in a console. First entry: "New ship, new start." Last entry: "Engine won\'t start." Three months between.',
    -- Shroud -- missing freighters
    ["Penny Dreadful"]   = '"The Shroud doesn\'t mess with sensors. The Shroud messes with you. We\'re turning back."  -- Penny Dreadful voice log. They didn\'t turn back.',
    ["Calloway's Luck"]  = '"We found something. I don\'t know what it is. I don\'t think it\'s-- [static] --beautiful."  -- Final comms, Calloway\'s Luck.',
    ["Seventh Son"]      = 'Automated log, Seventh Son. Navigation: position unknown. Course: unknown. Drift duration: 47 days. Hull: intact. Crew: [null].',
}

local _wrecks_logged = {}       -- callsign -> true
local _next_wreck_log_check = 0 -- rate-limit: check every 2 seconds

function WreckLog.checkWrecks()
    local now = getScenarioTime()
    if now < _next_wreck_log_check then return end
    _next_wreck_log_check = now + 2

    if not RT.valid(RT.player) then return end
    for _, entry in ipairs(VERSE.wrecks) do
        local s = entry.ship
        if RT.valid(s) then
            local cs = s:getCallSign()
            if not _wrecks_logged[cs] then
                local ok, scanned = pcall(function() return s:isFullyScannedBy(RT.player) end)
                if ok and scanned then
                    _wrecks_logged[cs] = true
                    local log = _WRECK_LOGS[cs] or
                        ('Automated beacon, ' .. cs .. '. Crew status: no response.')
                    RT.shipLog("[Scan] " .. cs .. ": " .. log, "#C0A0A0")
                end
            end
        end
    end
end

-- The Witness arc lives in ee/ragtag/missions/witness.lua (MISSIONS engine).



--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function init()
    VERSE.setupFactions()

    RT.useCampaign("sandbox")
    local fresh = getScenarioSetting("Campaign") == "Fresh start"
    RT.loadCampaign(fresh)

    if fresh then
        -- Set starting credits based on setting
        local start_credits = getScenarioSetting("Starting Credits")
        if start_credits == "Comfortable (500)" then
            RT.campaign.credits = 500
        elseif start_credits == "Well-off (1000)" then
            RT.campaign.credits = 1000
        else
            RT.campaign.credits = 200
        end
        RT.saveCampaign()
    end

    -- Track which sandbox session this is
    S.session_num = (RT.campaign.sandbox_sessions or 0) + 1
    RT.campaign.sandbox_sessions = S.session_num

    local danger = getScenarioSetting("Danger Level")
    if danger == "Relaxed" then
        DIR.config.max_ai_hostiles = 2
        DIR.config.spawn_cooldown = 240  -- 4 minutes between spawns
    elseif danger == "Dangerous" then
        DIR.config.max_ai_hostiles = 8
        DIR.config.spawn_cooldown = 90   -- 1.5 minutes between spawns
    else
        DIR.config.max_ai_hostiles = 5
        DIR.config.spawn_cooldown = 150  -- 2.5 minutes between spawns
    end
    DIR.enabled = getScenarioSetting("Director") ~= "Off"

    VERSE.build({session = S.session_num})
    -- Sandbox uses the whole universe; only explicitly require the starting location
    VERSE.requirePlaces({"Port Vesper", "Dustmote Salvage", "Halcyon Rest"})
    -- Spawn the primary ship at Port Vesper. Additional ships join via the
    -- in-game "Create player ship" selection screen; onNewPlayerShip handles them.
    RT.PLAYER_TEMPLATE = "Light Freighter"
    local px, py = VERSE.at("Port Vesper", 1.5, 1.5)
    RT.spawnPlayer(px, py, 0)

    -- Ships created via the "Create player ship" selection screen spawn at 0,0 with no
    -- faction or name.  Move them to Port Vesper, set faction, and assign the next
    -- available roster name so every Drift freighter gets its bird name.
    onNewPlayerShip(function(ship)
        local vx, vy = VERSE.at("Port Vesper", 1.5, 1.5)
        local offset = #RT.players * 4000
        ship:setPosition(vx + offset, vy)
        local tmpl = ship:getTypeName()
        local faction =
            tmpl == "Concord Enforcer" and "Concord"  or
            tmpl == "Corsair Raider"   and "Corsairs" or
            RT.PLAYER_FACTION
        ship:setFaction(faction)
        -- Auto-assign the next available roster name for freighters.
        -- RT.spawnPlayer overrides this with its explicit callsign, so no conflict.
        if tmpl == "Light Freighter" then
            local used = {}
            for _, p in ipairs(RT.players) do used[p:getCallSign()] = true end
            for _, name in ipairs(_SHIP_ROSTER) do
                if not used[name] then ship:setCallSign(name); break end
            end
        end
        if RT.campaign then
            ship:setReputationPoints(RT.campaign.credits or 150)
        end
        -- Pre-register so RT.update's sync loop doesn't override the faction next frame.
        -- (RT.spawnPlayer may also insert; the duplicate guard there prevents double-entry.)
        local found = false
        for _, p in ipairs(RT.players) do
            if p == ship then found = true; break end
        end
        if not found then
            table.insert(RT.players, ship)
            RT.player = RT.players[1]
        end
    end)

    -- Custom Port Vesper comms: welcome message on first hail, standard message after
    local vesper = RT.find("Port Vesper")
    if RT.valid(vesper) then
        vesper:setCommsFunction(function(source, target)
            if source:isEnemy(target) then
                setCommsMessage("Static. Then a click. They've cut the channel.")
                return
            end

            local msg
            if not S.vesper_first_hail then
                -- First hail: welcome message
                S.vesper_first_hail = true
                local session_text = S.session_num == 1 and "Welcome to the Drift, independents." or "Back again, I see."
                msg = session_text .. " Port Vesper is neutral ground--you're safe here. But out there? That's on you. The Gauntlet has good salvage if you can keep it, Core stations pay top credits but ask questions, and nobody goes to the Maw and comes back. Fly safe."
            else
                -- Subsequent hails: standard docking message
                msg = "Port Vesper traffic control. Mind the dock clamps, they bite."
            end

            if source:isDocked(target) then
                msg = msg .. "\n\nYou're docked. Balance: " .. RT.credits(source) .. " credits."
            end
            setCommsMessage(msg)

            -- Run standard station hooks (mission board, upgrades, etc.)
            local info = RT.stations["Port Vesper"]
            if info then
                for _, hook in ipairs(info.hooks) do
                    local ok, err = pcall(hook, source, target, info)
                    if not ok then print("[RT] station hook failed: " .. tostring(err)) end
                end

                if source:isDocked(target) then
                    if info.shop then
                        addCommsReply("Shipwright: browse upgrades", function(s, t)
                            RT.shipwrightMenu(s, t)
                        end)
                    end
                end
            end

            addCommsReply("Back", function() end)
        end)
    end

    -- Wire mission board into every friendly station
    JOBS.init()
    for _, d in ipairs(VERSE.STATIONS) do
        if d.fac ~= "Corsairs" and d.fac ~= "Hollow" then
            RT.addStationHook(d.cs, JOBS.stationHook)
        end
    end

    RT.addCampaignGMFunctions()
    addSessionGMFunctions()
    defineBeats()

    DIR.addStateProvider(function()
        local job_descs = {}
        for _, entry in ipairs(JOBS._active) do
            job_descs[#job_descs+1] = entry.mission.short .. " (" .. entry.mission.type .. ")"
        end
        return {
            phase = S.phase,
            session_num = S.session_num,
            time_exploring = math.floor(S.time_exploring),
            region = getCurrentRegion(),
            visited = table.concat(getVisitedRegionsList(), ", "),
            active_jobs = table.concat(job_descs, "; "),
        }
    end)

    DIR.init({
        id = SESSION_ID,
        campaign = "sandbox",
        title = "Open Play (Session " .. S.session_num .. ")",
        premise = "The crew of an independent freighter explores the Drift, a frontier cluster of five suns. No fixed mission--just opportunities, dangers, and whatever the crew decides to pursue. This is session " .. S.session_num .. " of their ongoing story.",
        tone = "Space-western sandbox. Wry humour, real stakes, never grimdark. The crew are independents making their way. Every choice matters, but nothing is scripted. React to what the crew does and where they go.",
        cast = {
            {name = "Port Vesper Dockmaster", where = "Port Vesper", role = "neutral port authority", voice = "professional, knows everyone's business"},
            {name = "Freighter Captains", where = "various stations", role = "sources of rumours", voice = "varied; some friendly, some suspicious"},
            {name = "Corsair Raiders", where = "ambush sites", role = "opportunistic pirates", voice = "greedy, avoid fair fights"},
            {name = "Concord Patrols", where = "patrol routes", role = "the law", voice = "by-the-book, can be reasoned with"},
        },
        locations = {
            {name = "The Drift", note = "The whole universe is accessible. Danger increases toward the edges: Gauntlet (risky), Blackwater (dangerous), Boneyard (dangerous), Maw (deadly)."},
        },
        director_guidance = [[
You are observing a sandbox campaign set in the Drift. The crew flies an independent freighter through a frontier cluster of five suns.

Your role:
- Watch events and track what's happening
- Periodically summarize the situation (every 5-10 minutes of play)
- Note significant moments: first combat, reputation changes, close calls, discoveries
- Track crew's choices and their consequences

DO NOT:
- Fire story beats or spawn encounters (proximity spawns handle this automatically)
- Push narrative or complications
- Voice NPCs unless explicitly asked by GM
- Suggest opportunities or actions

Your summaries should be factual and concise:
- Current location and activity
- Recent events (last 5-10 minutes)
- Notable changes (credits, reputation, damage)
- Active missions (shown in state as "active_jobs")

Example summary:
"Crew completed salvage mission in the Gauntlet (+120cr, Corsairs -10 rep). Currently docked at Halcyon Rest with 45% hull. One boarding mission active (target heading to Dustmote)."
]],
    })
end

function getCurrentRegion()
    if not RT.valid(RT.player) then return "unknown" end
    local px, py = RT.player:getPosition()
    local region = VERSE.regionAt(px, py)
    return region and region.name or "deep space"
end

function getVisitedRegionsList()
    local list = {}
    for region, _ in pairs(S.visited_regions) do
        table.insert(list, region)
    end
    return list
end

--------------------------------------------------------------------------------
-- Story beats
--------------------------------------------------------------------------------

function defineBeats()
    -- No automatic welcome beat - player gets welcome message on first hail to Port Vesper

    DIR.defineBeat("first_undock", {desc = "Crew undocks for the first time this session", fn = function()
        RT.shipLog("Session " .. S.session_num .. " begins. Current funds: " .. RT.credits() .. " credits.", "#A0E0A0")
        if S.session_num == 1 then
            RT.shipLog("Helm: Stations are marked on the sector map. Science: Scan objects to reveal details. Relay: Hail stations for rumours. Engineering: Watch your power and repair damage. Weapons: Keep missiles loaded.", "#E0E0A0")
        end
    end})

    -- AI beats removed 2026-10-29: Director now observes and summarizes rather than driving narrative beats
end

function addSessionGMFunctions()
    addGMFunction("Campaign Status", function()
        local lines = {"=== CAMPAIGN STATUS ===\n"}
        if RT.campaign then
            table.insert(lines, string.format("Session: %d", S.session_num))
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
        addGMMessage(table.concat(lines, "\n"))
    end)

    -- Reputation adjustment submenu
    local function showFactionDetail(faction)
        clearGMFunctions()
        addGMFunction("< Back to Factions", showReputationFactionList)
        local current = RT.getReputation(faction) or 0
        addGMFunction(string.format("%s: %+d", faction, current), function() end)
        local deltas = {100, -100}
        for _, d in ipairs(deltas) do
            local label = string.format("%s %+d", faction, d)
            addGMFunction(label, function()
                RT.addReputation(faction, d, "GM adjustment")
                RT.saveCampaign()
                showFactionDetail(faction)
            end)
        end
    end

    local function showReputationFactionList()
        clearGMFunctions()
        addGMFunction("< Back to Main", function()
            clearGMFunctions()
            addSessionGMFunctions()
        end)

        local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic"}
        for _, faction in ipairs(factions) do
            local rep = RT.getReputation(faction) or 0
            addGMFunction(string.format("%s (%+d)...", faction, rep), function()
                showFactionDetail(faction)
            end)
        end
    end

    addGMFunction("Adjust Reputation...", showReputationFactionList)

    addGMFunction("End session", function()
        if RT.valid(RT.player) then
            local docked = RT.player:getDockedWith()
            if docked and RT.valid(docked) then
                finishSession("completed", "Session ended at " .. docked:getCallSign() .. ".")
            else
                globalMessage("Dock at a friendly station first.", 5)
            end
        end
    end)

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
        addGMFunction("< Back to Main", function()
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
            addGMFunction("Distance: " .. _DISTANCE_NAMES[mode] .. (mode == cur_dist and " [*]" or ""), function()
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

    showShipUpgradesMenu = function(ship_cs)
        clearGMFunctions()
        addGMFunction("< Back to Ships", function() showUpgradesMenu() end)
        for _, u in ipairs(RT.UPGRADES) do
            local owned  = RT.hasUpgrade(u.id)
            local locked = u.requires ~= nil and not RT.hasUpgrade(u.requires)
            local cap_id = u.id
            local label
            if owned then
                label = "[*] " .. u.name
            elseif locked then
                label = u.name .. " [locked]"
            else
                label = u.name .. " (" .. u.cost .. "cr)"
            end
            addGMFunction(label, function()
                if owned then
                    _revokeUpgrade(cap_id)
                elseif not locked then
                    RT.grantUpgrade(cap_id)
                end
                showShipUpgradesMenu(ship_cs)
            end)
        end
    end

    showUpgradesMenu = function()
        clearGMFunctions()
        addGMFunction("< Back to Main", function()
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

    MISSIONS.addGMButton(function()
        clearGMFunctions()
        addSessionGMFunctions()
    end)
end

--------------------------------------------------------------------------------
-- Ending
--------------------------------------------------------------------------------

function finishSession(outcome, note)
    if S.ending then return end
    S.ending = true
    S.phase = "ending"

    RT.completeSession(SESSION_ID .. "_" .. S.session_num, outcome, note)
    DIR.emit("session_end", {
        session = SESSION_ID,
        session_num = S.session_num,
        outcome = outcome,
        note = note,
        credits = RT.credits(),
        time_exploring = S.time_exploring,
        visited = getVisitedRegionsList(),
        flags = RT.campaign.flags
    }, "high")

    globalMessage("Session " .. S.session_num .. " complete: " .. note .. " | Credits: " .. RT.credits(), 12)

    -- Give the director time to generate a session summary
    RT.after(12, function() victory(RT.PLAYER_FACTION) end, "victory")
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

function update(delta)
    RT.update(delta)
    RT.updateKillTracking()  -- Track ship kills for reputation
    VERSE.update(delta)
    DIR.update(delta)

    if S.phase == "ending" then return end

    if not RT.anyPlayerAlive() then
        if not S.ending then
            finishSession("destroyed", "The ship was lost after " .. math.floor(S.time_exploring / 60) .. " minutes.")
        end
        return
    end

    local now = getScenarioTime()
    local docked = RT.valid(RT.player) and RT.player:getDockedWith() or nil

    -- Track region visits (primary ship drives phase/region logic)
    local region = getCurrentRegion()
    if region and region ~= "unknown" and not S.visited_regions[region] then
        S.visited_regions[region] = true
        RT.shipLog("Entered " .. region .. ".", "#C0C0C0")
        DIR.emit("region_visited", {region = region}, "low")
    end

    -- Phase management
    if S.phase == "start" then
        if now > 5 then
            -- Set initial objective
            RT.setObjective("Explore the Drift")
            S.phase = "docked"
            S.docked_at = "Port Vesper"
        end
    elseif S.phase == "docked" then
        if not docked or not RT.valid(docked) then
            -- Just undocked
            DIR.fireBeat("first_undock", "script")
            S.phase = "exploring"
            S.docked_at = nil
        end
    elseif S.phase == "exploring" then
        S.time_exploring = S.time_exploring + delta

        if docked and RT.valid(docked) then
            -- Just docked
            S.phase = "docked"
            S.docked_at = docked:getCallSign()
            DIR.emit("docked", {station = S.docked_at}, "medium")
        end
    end

    JOBS.update()
    MISSIONS.update(delta)
    WORLD.update(delta)
    WreckLog.checkWrecks()

end
