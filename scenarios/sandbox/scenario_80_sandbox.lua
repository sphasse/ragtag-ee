-- Name: Sandbox: Open Play
-- Description: Explore the Drift, earn credits, upgrade your ship. No fixed story—make your own. Perfect for learning the universe and trying out ship systems. The AI director creates dynamic encounters based on your choices.
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
-- Starting Credits[Well-off (1000)]: Can afford multiple upgrades or a jump drive.
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

local SESSION_ID = "sandbox"

-- Session state
local S = {
    phase = "start",           -- start, exploring, docked, ending
    session_num = 1,           -- which sandbox session this is
    time_exploring = 0,        -- time spent not docked
    encounters_spawned = 0,
    last_encounter_time = 0,
    last_opportunity_time = 0,
    visited_regions = {},      -- track where crew has been
    docked_at = nil,
    ending = false,
}

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
    VERSE.requirePlaces({"Port Vesper"})

    -- Spawn player at Port Vesper (safe starting location)
    local px, py = VERSE.at("Port Vesper", 1.5, 1.5)
    RT.spawnPlayer(px, py, 0)

    RT.addCampaignGMFunctions()
    addSessionGMFunctions()
    defineBeats()

    DIR.addStateProvider(function()
        return {
            phase = S.phase,
            session_num = S.session_num,
            time_exploring = math.floor(S.time_exploring),
            encounters = S.encounters_spawned,
            region = getCurrentRegion(),
            visited = table.concat(getVisitedRegionsList(), ", "),
        }
    end)

    DIR.init({
        id = SESSION_ID,
        campaign = "sandbox",
        title = "Open Play (Session " .. S.session_num .. ")",
        premise = "The crew of an independent freighter explores the Drift, a frontier cluster of five suns. No fixed mission—just opportunities, dangers, and whatever the crew decides to pursue. This is session " .. S.session_num .. " of their ongoing story.",
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
Sandbox mode: no fixed plot. Create dynamic encounters based on:
1. Location danger level (safe/risky/dangerous/deadly)
2. What the crew is doing (exploring, trading, salvaging, fleeing)
3. Time since last encounter (avoid overwhelming them)
4. Their apparent goals (support interesting choices)

Encounter types:
- Salvage: debris with credits/equipment (scan to reveal value)
- Trade rumours: "Station X needs Y, will pay well"
- Distress calls: ships under attack (may be real or bait)
- Odd jobs: escort, delivery, recovery
- Patrols: Concord asking questions (neutral unless crew is hostile)
- Pirates: Corsairs demanding cargo (flee, fight, or bribe)
- Mysteries: strange signals, derelicts with logs

Match threat to location. Don't spawn deadly enemies in safe zones. Reward exploration of dangerous areas with better salvage. Let quiet moments happen—not every minute needs action.

If the crew seems lost, offer a rumour or opportunity. If they're focused on something, support that narrative thread. Remember what they've done and reference it.
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
    DIR.defineBeat("welcome", {desc = "Port Vesper dockmaster welcomes the crew", fn = function()
        local session_text = S.session_num == 1 and "Welcome to the Drift, independents." or "Back again, I see."
        RT.hail(RT.find("Port Vesper"), session_text .. " Port Vesper is neutral ground—you're safe here. But out there? That's on you. The Gauntlet has good salvage if you can keep it, Core stations pay top credits but ask questions, and nobody goes to the Maw and comes back. Fly safe.", "Port Vesper Dockmaster")
        RT.setObjective("Explore the Drift. Earn credits. Upgrade your ship. Make your own story.")
    end})

    DIR.defineBeat("first_undock", {desc = "Crew undocks for the first time this session", fn = function()
        RT.player:addToShipLog("Session " .. S.session_num .. " begins. Current funds: " .. RT.credits() .. " credits.", "#A0E0A0")
        if S.session_num == 1 then
            RT.player:addToShipLog("Helm: Stations are marked on the sector map. Science: Scan objects to reveal details. Relay: Hail stations for rumours. Engineering: Watch your power and repair damage. Weapons: Keep missiles loaded.", "#E0E0A0")
        end
    end})

    -- Dynamic beats the director can fire
    DIR.defineBeat("opportunity", {ai = true, desc = "Director offers a trade rumour, distress call, or odd job", fn = function()
        -- The director will provide the specific opportunity via "say" or custom actions
    end})

    DIR.defineBeat("encounter", {ai = true, desc = "Director spawns an encounter (hostile, neutral, or mystery)", fn = function()
        S.encounters_spawned = S.encounters_spawned + 1
        S.last_encounter_time = getScenarioTime()
    end})

    DIR.defineBeat("mystery", {ai = true, desc = "Director creates a mystery or strange signal", fn = function()
        -- The director will provide the details
    end})
end

function addSessionGMFunctions()
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

    addGMFunction("+500 credits", function()
        if RT.valid(RT.player) then
            RT.addCredits(500, "GM reward")
        end
    end)

    addGMFunction("Spawn salvage", function()
        if RT.valid(RT.player) then
            local px, py = RT.player:getPosition()
            local value = math.random(20, 80)
            local pod = SupplyDrop():setFaction("Independent"):setPosition(px + random(-3000, 3000), py + random(-3000, 3000))
            pod:setEnergy(value):setDescriptions("Supply pod", "Credits: " .. value)
            RT.player:addToShipLog("Salvage detected nearby.", "#A0E0E0")
        end
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
        encounters = S.encounters_spawned,
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
    VERSE.update(delta)
    DIR.update(delta)

    if S.phase == "ending" then return end

    if not RT.valid(RT.player) then
        if not S.ending then
            finishSession("destroyed", "The ship was lost after " .. math.floor(S.time_exploring / 60) .. " minutes.")
        end
        return
    end

    local now = getScenarioTime()
    local docked = RT.player:getDockedWith()

    -- Track region visits
    local region = getCurrentRegion()
    if region and region ~= "unknown" and not S.visited_regions[region] then
        S.visited_regions[region] = true
        RT.player:addToShipLog("Entered " .. region .. ".", "#C0C0C0")
        DIR.emit("region_visited", {region = region}, "low")
    end

    -- Phase management
    if S.phase == "start" then
        if now > 5 then
            DIR.fireBeat("welcome", "script")
            S.phase = "docked"
            S.docked_at = "Port Vesper"
        end
    elseif S.phase == "docked" then
        if not docked or not RT.valid(docked) then
            -- Just undocked
            DIR.fireBeat("first_undock", "script")
            S.phase = "exploring"
            S.undocked_at = now
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

    -- Scripted random encounters when director is off
    if not DIR.enabled and S.phase == "exploring" then
        -- Simple fallback: occasional random encounters in dangerous areas
        if now - S.last_encounter_time > 300 then  -- 5 minutes
            local region_data = VERSE.regionAt(RT.player:getPosition())
            if region_data and region_data.danger >= 1 and math.random() < 0.3 then
                spawnScriptedEncounter(region_data)
                S.last_encounter_time = now
                S.encounters_spawned = S.encounters_spawned + 1
            end
        end
    end
end

-- Fallback encounters when director is off
function spawnScriptedEncounter(region_data)
    if not RT.valid(RT.player) then return end

    local px, py = RT.player:getPosition()
    local angle = random(0, 360)
    local distance = random(8000, 15000)
    local sx = px + math.cos(math.rad(angle)) * distance
    local sy = py + math.sin(math.rad(angle)) * distance

    local templates = {"MT52 Hornet"}
    if region_data.danger >= 2 then
        templates = {"Adder MK5", "MT52 Hornet"}
    end

    local template = templates[math.random(#templates)]
    local ship = CpuShip():setTemplate(template):setFaction("Corsairs")
    ship:setPosition(sx, sy):orderRoaming()

    RT.player:addToShipLog("Contact: " .. template .. " detected in " .. region_data.name .. ".", "#FF8080")
end
