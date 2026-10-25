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
-- Mission board (JOBS) — procedurally-generated contracts offered at stations
--------------------------------------------------------------------------------

local JOBS = {}

-- Display-safe short names (objectives must be ≤25 chars; "Deliver to " is 11)
local _SHORT = {
    ["Concord Station Arbiter"] = "C.S. Arbiter",
    ["Concord Waypoint Galen"]  = "Waypoint Galen",
    ["Saint Brennan's Mission"] = "St. Brennan's",
    ["Lastchance Outpost"]      = "Lastchance",
    ["Dustmote Salvage"]        = "Dustmote",
    ["Greywater Depot"]         = "Greywater",
}
local function _sd(cs) return _SHORT[cs] or cs end   -- short dest name (≤14 chars)

-- Route pairs by danger tier (both directions generated at init)
local _ROUTES = {
    [0] = {   -- safe lanes; ≤40u, no hostile zones
        {"Port Vesper",            "Calder's Reach"},
        {"Port Vesper",            "Tamsin Hollow"},
        {"Port Vesper",            "Greywater Depot"},
        {"Port Vesper",            "Halcyon Rest"},
        {"Calder's Reach",         "Tamsin Hollow"},
        {"Tamsin Hollow",          "Greywater Depot"},
        {"Greywater Depot",        "Halcyon Rest"},
        {"Halcyon Rest",           "Saint Brennan's Mission"},
        {"Concord Station Arbiter","Port Vesper"},
    },
    [1] = {   -- risky: Gauntlet fringes, Shroud edge, longer runs
        {"Port Vesper",            "Hob's Landing"},
        {"Port Vesper",            "Dustmote Salvage"},
        {"Halcyon Rest",           "Hob's Landing"},
        {"Greywater Depot",        "Hob's Landing"},
        {"Saint Brennan's Mission","Dustmote Salvage"},
        {"Concord Station Arbiter","Concord Waypoint Galen"},
    },
    [2] = {   -- dangerous: deep Rim, Boneyard fringe, Core long-haul
        {"Hob's Landing",    "Lastchance Outpost"},
        {"Dustmote Salvage", "Lastchance Outpost"},
        {"Halcyon Rest",     "Lastchance Outpost"},
        {"Port Vesper",      "Concord Waypoint Galen"},
    },
}

local _CARGO = {
    {name="medical kits",    note="Someone's waiting.",       pay={55, 100, 170}},
    {name="ore samples",     note="Calder's assay work.",     pay={50,  90, 150}},
    {name="farm tools",      note="Pre-paid order.",          pay={45,  80, 135}},
    {name="spare parts",     note="Running out of excuses.",  pay={55,  95, 155}},
    {name="fuel cells",      note="Cold run.",                pay={50,  90, 145}},
    {name="data cores",      note="Handle with care.",        pay={80, 130, 200}},
    {name="ration crates",   note="Boring but needed.",       pay={40,  75, 120}},
    {name="a sealed crate",  note="Don't ask.",               pay={90, 145, 230}},
}

-- Scout missions: fly to a map location (world units); pay on arrival
local _SCOUTS = {
    -- tier 0
    {tier=0, origin="Port Vesper",     wx=6000,   wy=-10000, pay=70,
     short="Survey Vesper rocks",  obj="Survey Vesper Drift",
     brief='"Our nav charts are old. Sweep the Drift asteroids. 70 credits."'},
    {tier=0, origin="Calder's Reach",  wx=-28000, wy=22000,  pay=65,
     short="Check belt anomaly",   obj="Check belt signal",
     brief='"Odd beacon in the belt. Probably loose rock. 65 credits to confirm."'},
    {tier=0, origin="Tamsin Hollow",   wx=-36000, wy=28000,  pay=60,
     short="Run Tamsin approach",  obj="Scout Tamsin approach",
     brief='"Scan the approach lanes for nav hazards. 60 credits."'},
    {tier=0, origin="Greywater Depot", wx=26000,  wy=10000,  pay=55,
     short="Fly Greywater lanes",  obj="Survey Greywater",
     brief='"Run the lane survey between here and Halcyon. 55 credits."'},
    {tier=0, origin="Halcyon Rest",    wx=44000,  wy=-26000, pay=65,
     short="Scout Shroud edge",    obj="Scout Shroud edge",
     brief='"New debris near the Shroud edge. Worth a look. 65 credits."'},
    -- tier 1
    {tier=1, origin="Port Vesper",     wx=10000,  wy=52000,  pay=150,
     short="Chart west Gauntlet",  obj="Chart west Gauntlet",
     brief='"The Gauntlet belt shifted. We need eyes on it. Risky, 150 credits."'},
    {tier=1, origin="Halcyon Rest",    wx=72000,  wy=-16000, pay=120,
     short="Trace Slow Dancer",    obj="Find Slow Dancer",
     brief='"Slow Dancer missed check-in. Last ping near Dustmote. 120 credits."'},
    {tier=1, origin="Greywater Depot", wx=60000,  wy=-10000, pay=140,
     short="Probe the Shroud",     obj="Scout Shroud interior",
     brief='"Lost a probe in the Shroud. Passive scan run. 140 credits."'},
    {tier=1, origin="Hob's Landing",   wx=52000,  wy=38000,  pay=130,
     short="Count Gauntlet patrols",obj="Scout Gauntlet entry",
     brief='"Count Corsair contacts on the Gauntlet approach. 130 credits."'},
    -- tier 2
    {tier=2, origin="Hob's Landing",   wx=16000,  wy=-62000, pay=250,
     short="Survey Boneyard edge", obj="Survey Boneyard",
     brief='"Map drone patrol patterns at the Boneyard edge. Dangerous work, 250 credits."'},
    {tier=2, origin="Dustmote Salvage",wx=100000, wy=54000,  pay=220,
     short="Verify Lastchance beacon",obj="Check Lastchance beacon",
     brief='"Lastchance beacon is intermittent. Long run to confirm, 220 credits."'},
}

local _pool = {}          -- all generated missions, shuffled once at init
local _offers = {}        -- cs -> {m,...} lazily assigned on first dock
local _active = {}        -- list of {mission=m, phase="active"|"done"}
local _done = {}          -- set of id -> true (taken or completed this session)

function JOBS.maxTier()
    local n = RT.campaign and #(RT.campaign.upgrades or {}) or 0
    if n >= 5 then return 2 elseif n >= 2 then return 1 else return 0 end
end

function JOBS.init()
    local id = 0
    for tier = 0, 2 do
        for _, route in ipairs(_ROUTES[tier] or {}) do
            for dir = 1, 2 do
                local from = dir == 1 and route[1] or route[2]
                local to   = dir == 1 and route[2] or route[1]
                for _, c in ipairs(_CARGO) do
                    id = id + 1
                    local reward = c.pay[tier + 1]
                    local dest_s = _sd(to)
                    table.insert(_pool, {
                        id      = "j" .. id,
                        type    = "delivery",
                        tier    = tier,
                        origin  = from,
                        dest    = to,
                        cargo   = c.name,
                        reward  = reward,
                        short   = c.name .. " -> " .. dest_s,
                        obj     = "Deliver to " .. dest_s,
                        brief   = string.format('"Need %s at %s. %s %d credits on delivery."',
                                      c.name, dest_s, c.note, reward),
                    })
                end
            end
        end
    end
    for _, sc in ipairs(_SCOUTS) do
        id = id + 1
        table.insert(_pool, {
            id     = "j" .. id,
            type   = "scout",
            tier   = sc.tier,
            origin = sc.origin,
            wx     = sc.wx,
            wy     = sc.wy,
            reward = sc.pay,
            short  = sc.short,
            obj    = sc.obj,
            brief  = sc.brief,
        })
    end
    -- Fisher-Yates shuffle using session RNG
    local rng = VERSE.rng(VERSE.SEED + (RT.campaign.sandbox_sessions or 1) * 7919)
    for i = #_pool, 2, -1 do
        local j = rng.int(1, i)
        _pool[i], _pool[j] = _pool[j], _pool[i]
    end
end

function JOBS.getOffers(cs)
    if _offers[cs] then return _offers[cs] end
    local mt = JOBS.maxTier()
    local out, seen = {}, {}
    for _, m in ipairs(_pool) do
        if #out >= 2 then break end
        if m.origin == cs and m.tier <= mt and not _done[m.id] then
            local key = m.dest or (m.wx .. "," .. m.wy)
            if not seen[key] then out[#out+1] = m; seen[key] = true end
        end
    end
    _offers[cs] = out
    return out
end

function JOBS.accept(m)
    if #_active >= 2 then return false end
    _done[m.id] = true
    _active[#_active+1] = {mission = m, phase = "active"}
    _offers[m.origin] = nil   -- refresh board next dock
    JOBS.updateObj()
    local dest = m.dest or "the target location"
    RT.player:addToShipLog(string.format("Job: %s (%d cr). Head to %s.", m.short, m.reward, dest), "#A0C0FF")
    return true
end

function JOBS.complete(entry)
    entry.phase = "done"
    for i, a in ipairs(_active) do
        if a == entry then table.remove(_active, i); break end
    end
    RT.addCredits(entry.mission.reward, "job: " .. entry.mission.short)
    JOBS.updateObj()
    DIR.emit("job_complete", {type=entry.mission.type, tier=entry.mission.tier, reward=entry.mission.reward}, "low")
end

function JOBS.updateObj()
    if #_active == 0 then
        RT.setObjective("Explore the Drift", true)
    elseif #_active == 1 then
        RT.setObjective(_active[1].mission.obj, true)
    else
        RT.setObjective("2 jobs active", true)
    end
end

function JOBS.stationHook(source, target)
    if not source:isDocked(target) then return end
    local cs = target:getCallSign()
    local tier_label = {"safe run", "risky run", "dangerous run"}

    -- Complete deliveries due here
    for _, entry in ipairs(_active) do
        local m = entry.mission
        if m.type == "delivery" and m.dest == cs and entry.phase == "active" then
            local ent = entry
            addCommsReply(string.format("Hand off %s (+%d cr)", m.cargo, m.reward), function(s, t)
                JOBS.complete(ent)
                setCommsMessage(string.format('"Received. %d credits transferred. Good flying."', m.reward))
                addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
            end)
        end
    end

    -- Job board
    local offers = JOBS.getOffers(cs)
    if #offers == 0 then return end
    addCommsReply("Check the job board", function(s, t)
        local lines = {"Job board — " .. cs .. ":\n"}
        for _, m in ipairs(offers) do
            lines[#lines+1] = string.format("* %s  [%d cr, %s]",
                m.short, m.reward, tier_label[m.tier + 1])
        end
        setCommsMessage(table.concat(lines, "\n"))
        for _, m in ipairs(offers) do
            local cap = m
            addCommsReply(string.format("Take: %s (%d cr)", m.short, m.reward), function(s2, t2)
                if #_active >= 2 then
                    setCommsMessage('"You\'re already carrying two jobs. Finish one first."')
                else
                    JOBS.accept(cap)
                    setCommsMessage(cap.brief .. "\n\n\"Come back when it's done.\"")
                end
                addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
            end)
        end
        addCommsReply("Nothing for me", function(s2, t2) RT.stationComms(s2, t2) end)
    end)
end

function JOBS.update()
    if not RT.valid(RT.player) then return end
    local px, py = RT.player:getPosition()
    for _, entry in ipairs(_active) do
        if entry.mission.type == "scout" and entry.phase == "active" then
            local dx = px - entry.mission.wx
            local dy = py - entry.mission.wy
            if dx*dx + dy*dy < 8000*8000 then
                entry.phase = "done"
                local ent = entry
                RT.player:addToShipLog("Scout complete — " .. ent.mission.short .. string.format(" (+%d cr)", ent.mission.reward), "#80FF80")
                JOBS.complete(ent)
            end
        end
    end
end

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

    -- Mission board: generate pool and wire hooks into every friendly station
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
        for _, entry in ipairs(_active) do
            job_descs[#job_descs+1] = entry.mission.short .. " (" .. entry.mission.type .. ")"
        end
        return {
            phase = S.phase,
            session_num = S.session_num,
            time_exploring = math.floor(S.time_exploring),
            encounters = S.encounters_spawned,
            region = getCurrentRegion(),
            visited = table.concat(getVisitedRegionsList(), ", "),
            active_jobs = table.concat(job_descs, "; "),
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
Sandbox mode: no fixed plot. The state includes "active_jobs" showing what the crew is currently hauling. Use this context.

Create dynamic encounters based on:
1. Location danger level (safe/risky/dangerous/deadly) and tier of the active job
2. What the crew is doing (exploring, on a delivery run, at a station)
3. Time since last encounter (avoid overwhelming them)
4. Their apparent goals

Encounter types:
- Salvage: debris with credits (scan to reveal value)
- Complications on runs: a pirate intercept for a high-value delivery, a comms tip that the destination has trouble
- Distress calls: ships under attack (may be real or bait)
- Patrols: Concord asking questions
- Pirates: Corsairs demanding cargo (flee, fight, or bribe)
- Mysteries: strange signals, derelicts with logs

The job board at each station offers up to 2 procedural contracts (delivery or scout). As the crew buys upgrades, higher-tier (more dangerous, more lucrative) jobs unlock. Don't spoil the board — let the crew discover it by docking.

Match threat to location. Don't spawn deadly enemies in safe zones. Let quiet moments happen. If the crew has an active delivery job, a well-timed ambush by someone who "heard about the cargo" adds drama. If they're flying a scout mission into the Shroud, a strange contact rewards the risk.
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
        RT.setObjective("Explore the Drift")
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

    JOBS.update()

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
