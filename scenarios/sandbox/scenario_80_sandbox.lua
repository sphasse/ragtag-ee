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
require("ragtag/patrol.lua")
require("ragtag/mission.lua")

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

local _active = {}   -- list of {mission=m, phase="active"|"done"}
local _done   = {}   -- id → true (taken or completed this session)

local _MISSION_WEIGHTS = {
    {type = "delivery", weight = 20},
    {type = "salvage",  weight = 7},
    {type = "boarding", weight = 3},
    {type = "hacking",  weight = 3},
}
local function pickMissionType()
    local total = 0
    for _, t in ipairs(_MISSION_WEIGHTS) do total = total + t.weight end
    local r = math.random() * total
    for _, t in ipairs(_MISSION_WEIGHTS) do
        r = r - t.weight
        if r <= 0 then return t.type end
    end
    return "delivery"
end

JOBS.MISSION_DURATION = 20 * 60   -- seconds before an untouched mission expires
JOBS._panel_next      = 0          -- next scenario-time to refresh the relay panel

local _TYPE_PFX = {delivery="[D]", salvage="[S]", boarding="[B]", hacking="[H]"}
local function jobLine(m, now)
    local mins  = m._expires_at and math.max(0, math.ceil((m._expires_at - now) / 60)) or "?"
    local where
    if m.type == "delivery" then
        where = "→ " .. _sd(m.dest or "?")
    elseif m.type == "salvage" then
        where = m._found and ("ret → " .. _sd(m.origin)) or "→ site"
    elseif m.type == "boarding" then
        if m._boarded        then where = "ret → " .. _sd(m.origin)
        elseif m._disabled   then where = "→ board " .. (m.target_cs or "?")
        else                      where = "→ disable" end
    elseif m.type == "hacking" then
        where = m._hacked and ("ret → " .. _sd(m.origin)) or "→ hack relay"
    else
        where = m.obj or "active"
    end
    return string.format("%s %s  %dcr  %sm", _TYPE_PFX[m.type] or "[?]", where, m.reward, mins)
end

function JOBS.refreshPanel()
    local now = getScenarioTime()
    RT.forEachPlayer(function(p)
        for slot = 1, 2 do
            local entry = _active[slot]
            local txt = (entry and entry.phase == "active")
                        and ("Job " .. slot .. ": " .. jobLine(entry.mission, now))
                        or  ("Job " .. slot .. ": (none)")
            p:addCustomInfo("relay", "rt_job_" .. slot, txt, slot)
        end
    end)
end

function JOBS.maxTier()
    local n = RT.campaign and #(RT.campaign.upgrades or {}) or 0
    if n >= 5 then return 2 elseif n >= 2 then return 1 else return 0 end
end

function JOBS.init() end

function JOBS.accept(m)
    if #_active >= 2 then return false end
    _done[m.id] = true
    -- Drain from dynamic queue if this was director-pushed
    for i, dm in ipairs(MISSION._dynamic_queue) do
        if dm.id == m.id then table.remove(MISSION._dynamic_queue, i); break end
    end
    m._expires_at = getScenarioTime() + JOBS.MISSION_DURATION
    _active[#_active+1] = {mission = m, phase = "active"}
    MISSION.track(m)   -- register for route interception
    JOBS.updateObj()
    local dest_hint = m.dest or (m.wx and ("grid " .. MISSION.gridRef(m.wx, m.wy)) or "??")
    RT.shipLog(string.format("Contract: %s (%d cr). %dm to complete. Head to %s.",
        m.short, m.reward, math.floor(JOBS.MISSION_DURATION / 60), dest_hint), "#A0C0FF")
    if m.intercept then
        RT.shipLog("Intelligence suggests this run may not be quiet.", "#FFCC80")
    end
    return true
end

function JOBS.complete(entry)
    entry.phase = "done"
    for i, a in ipairs(_active) do
        if a == entry then table.remove(_active, i); break end
    end
    MISSION.untrack(entry.mission.id)
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
    JOBS.refreshPanel()
end

function JOBS.stationHook(source, target)
    if not RT.isPlayer(source) then return end
    if not source:isDocked(target) then return end
    local cs = target:getCallSign()

    -- Complete deliveries and salvage returns due here
    for _, entry in ipairs(_active) do
        local m = entry.mission
        if entry.phase == "active" then
            if m.type == "delivery" and m.dest == cs then
                local ent = entry
                addCommsReply(string.format("Hand off %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent)
                    local recv = (ent.mission.complete_msg or '"Received. Good flying."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            elseif m.type == "salvage" and m.origin == cs and m._found then
                local ent = entry
                addCommsReply(string.format("Deliver %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent)
                    local recv = (ent.mission.complete_msg or '"Received. Good work."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            elseif m.type == "boarding" and m.origin == cs and m._boarded then
                local ent = entry
                addCommsReply(string.format("Hand off %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent)
                    local recv = (ent.mission.complete_msg or '"Good work."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            elseif m.type == "hacking" and m.origin == cs and m._hacked then
                local ent = entry
                addCommsReply(string.format("Deliver %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent)
                    local recv = (ent.mission.complete_msg or '"Good extraction."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            end
        end
    end

    -- On-demand job board: generate fresh deliveries each time.
    addCommsReply("Any work available?", function(s, t)
        local offers = {}
        local mt = JOBS.maxTier()
        local tier_label = {"safe run", "risky run", "dangerous run"}

        -- Director-pushed deliveries take priority (no re-offer if already taken)
        for _, m in ipairs(MISSION._dynamic_queue) do
            if m.origin == cs and not _done[m.id] then
                offers[#offers + 1] = m
            end
        end

        -- Generate fresh missions to fill up to 2 slots (weighted: delivery 20, salvage 7, boarding 3, hacking 3).
        if #offers < 2 then
            local candidates = {}
            for _, d in ipairs(VERSE.STATIONS) do
                if d.cs ~= cs and d.fac ~= "Corsairs" and d.fac ~= "Hollow" then
                    candidates[#candidates + 1] = d.cs
                end
            end
            for i = #candidates, 2, -1 do
                local j = math.random(i)
                candidates[i], candidates[j] = candidates[j], candidates[i]
            end
            local station_e = RT.find(cs)
            local dest_idx  = 1
            for slot = 1, 2 do
                if #offers >= 2 then break end
                local tier  = math.min(mt, math.random(0, 1))
                local mtype = pickMissionType()
                if mtype == "delivery" and dest_idx <= #candidates then
                    offers[#offers + 1] = MISSION.newDelivery({origin = cs, dest = candidates[dest_idx], tier = tier})
                    dest_idx = dest_idx + 1
                elseif mtype == "salvage" and RT.valid(station_e) then
                    local rx, ry = station_e:getPosition()
                    local ang  = math.random() * 2 * math.pi
                    local dist = (15 + math.random() * 25) * 1000
                    offers[#offers + 1] = MISSION.newSalvage({
                        origin = cs,
                        wx = math.floor(rx + math.cos(ang) * dist),
                        wy = math.floor(ry + math.sin(ang) * dist),
                        tier = tier,
                    })
                elseif mtype == "boarding" and RT.valid(station_e) then
                    local rx, ry = station_e:getPosition()
                    local ang  = math.random() * 2 * math.pi
                    local dist = (20 + math.random() * 30) * 1000
                    offers[#offers + 1] = MISSION.newBoarding({
                        origin = cs,
                        wx = math.floor(rx + math.cos(ang) * dist),
                        wy = math.floor(ry + math.sin(ang) * dist),
                        tier = tier,
                    })
                elseif mtype == "hacking" and RT.valid(station_e) then
                    local rx, ry = station_e:getPosition()
                    local ang  = math.random() * 2 * math.pi
                    local dist = (8 + math.random() * 12) * 1000   -- relay buoys sit closer than boarding targets
                    offers[#offers + 1] = MISSION.newHacking({
                        origin = cs,
                        wx = math.floor(rx + math.cos(ang) * dist),
                        wy = math.floor(ry + math.sin(ang) * dist),
                        tier = tier,
                    })
                elseif dest_idx <= #candidates then
                    -- fallback: delivery
                    offers[#offers + 1] = MISSION.newDelivery({origin = cs, dest = candidates[dest_idx], tier = tier})
                    dest_idx = dest_idx + 1
                end
            end
        end

        if #offers == 0 then
            setCommsMessage('"Nothing going out from here right now."')
            addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
            return
        end

        local lines = {"Work out of " .. cs .. ":\n"}
        for _, m in ipairs(offers) do
            lines[#lines + 1] = string.format("* %s  [%d cr, %s]",
                m.short, m.reward, tier_label[(m.tier or 0) + 1])
        end
        setCommsMessage(table.concat(lines, "\n"))
        for _, m in ipairs(offers) do
            local cap = m
            addCommsReply(string.format("Take: %s (%d cr)", cap.short, cap.reward), function(s2, t2)
                if #_active >= 2 then
                    setCommsMessage('"You\'re already carrying two jobs. Finish one first."')
                else
                    JOBS.accept(cap)
                    setCommsMessage(cap.brief .. "\n\n\"Come back when it\'s done.\"")
                end
                addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
            end)
        end
        addCommsReply("Nothing for me", function(s2, t2) RT.stationComms(s2, t2) end)
    end)
end

function JOBS.update()
    if not RT.anyPlayerAlive() then return end
    local now = getScenarioTime()

    -- Refresh relay panel countdown every 15 s
    if now >= JOBS._panel_next then
        JOBS._panel_next = now + 15
        JOBS.refreshPanel()
    end

    for i = #_active, 1, -1 do   -- iterate backwards; boarding failure may remove entry
        local entry = _active[i]
        local m = entry.mission
        if entry.phase ~= "active" then goto next_entry end

        -- Expiry check (before any type logic so we never act on a dead mission)
        if m._expires_at and now > m._expires_at then
            RT.shipLog("[Contract] " .. m.short .. " — time expired. Contract lost.", "#FF8080")
            MISSION.untrack(m.id)
            table.remove(_active, i)
            JOBS.updateObj()
            goto next_entry
        end

        if m.type == "salvage" and not m._found then
            for _, p in ipairs(RT.players) do
                if RT.valid(p) then
                    local px, py = p:getPosition()
                    local dx, dy = px - m.wx, py - m.wy
                    if dx*dx + dy*dy < 5000*5000 then
                        m._found = true
                        m.obj = "Return " .. m.cargo .. " to " .. m.origin
                        RT.shipLog("[Salvage] " .. m.cargo .. " recovered. Return to " .. m.origin .. ".", "#80FF80")
                        JOBS.updateObj()
                        if m.intercept and not m.intercept.fired then
                            m.intercept.fired = true
                            MISSION._spawnIntercept(m, px, py)
                        end
                        break
                    end
                end
            end

        elseif m.type == "boarding" then
            -- Phase 1: spawn target ship on first update after accept
            if not m._spawned then
                local s = CpuShip():setTemplate(m.target_template):setFaction("Corsairs")
                s:setPosition(m.wx + random(-2000, 2000), m.wy + random(-2000, 2000))
                s:orderRoaming():setDockingPortCount(0)
                RT.register(s)
                DIR.registerKill(s)
                DIR.allowControl(s)
                s:setCommsFunction(function(src, tgt)
                    setCommsMessage('"Get away from us."')
                end)
                m.target_cs = s:getCallSign()
                m._spawned  = true
                RT.shipLog("[Boarding] Target located: " .. m.target_cs
                    .. ". Disable its engines — Weapons: set beam system target to impulse.", "#FFCC80")

            -- Phase 2: watch for disable (impulse health < 0.3 or hull < 25%)
            elseif not m._disabled then
                local target = RT.find(m.target_cs)
                if not RT.valid(target) then
                    -- Destroyed before boarding — mission lost
                    RT.shipLog("[Boarding] Target destroyed before boarding — contract lost.", "#FF8080")
                    MISSION.untrack(m.id)
                    table.remove(_active, i)
                    JOBS.updateObj()
                else
                    local impulse_h = target:getSystemHealth("impulse") or 1
                    local hull_pct  = target:getHull() / target:getHullMax()
                    if impulse_h < 0.3 or hull_pct < 0.25 then
                        m._disabled = true
                        target:setCanBeDestroyed(false)
                        target:orderIdle()
                        target:setImpulseMaxSpeed(5)
                        target:setDockingPortCount(1)
                        target:setCommsFunction(function(src, tgt)
                            setCommsMessage('"We\'re done. Come aboard and take what you came for."')
                        end)
                        m.obj = "Board " .. m.target_cs
                        RT.shipLog("[Target] " .. m.target_cs .. " disabled. Move in and dock to board.", "#FFCC80")
                        JOBS.updateObj()
                    end
                end

            -- Phase 3: wait for any player to dock with the disabled target
            elseif not m._boarded then
                local target = RT.find(m.target_cs)
                if RT.valid(target) then
                    for _, p in ipairs(RT.players) do
                        if RT.valid(p) then
                            local docked = p:getDockedWith()
                            if docked and docked == target then
                                m._boarded = true
                                m.obj = "Return " .. m.cargo .. " to " .. m.origin
                                target:setDockingPortCount(0)
                                RT.shipLog("[Boarding] " .. m.cargo .. " secured. Return to " .. m.origin .. ".", "#80FF80")
                                -- Fire intercept on the return leg
                                if m.intercept and not m.intercept.fired then
                                    m.intercept.fired = true
                                    local origin_e = RT.find(m.origin)
                                    if RT.valid(origin_e) then
                                        m._dx, m._dy = origin_e:getPosition()
                                    end
                                    local px, py = p:getPosition()
                                    MISSION._spawnIntercept(m, px, py)
                                end
                                JOBS.updateObj()
                                break
                            end
                        end
                    end
                end
            end

        elseif m.type == "hacking" then
            -- Phase 1: spawn relay buoy on first update after accept
            if not m._spawned then
                local s = CpuShip():setTemplate("Escape Pod"):setFaction("Corsairs")
                s:setPosition(m.wx + random(-1000, 1000), m.wy + random(-1000, 1000))
                s:orderIdle()
                s:setImpulseMaxSpeed(0)
                s:setRotationMaxSpeed(0)
                s:setWeaponTubeCount(0)
                s:setCanBeDestroyed(false)
                s:setCallSign("Data Relay " .. math.random(10, 99))
                RT.register(s)
                m.target_cs = s:getCallSign()
                m._spawned  = true
                RT.shipLog("[Hack] Relay located: " .. m.target_cs
                    .. ". Relay station: open hacking panel and target the reactor subsystem.", "#FFCC80")

            -- Phase 2: watch for hack completion
            elseif not m._hacked then
                local target = RT.find(m.target_cs)
                if not RT.valid(target) then
                    RT.shipLog("[Hack] Relay destroyed before extraction — contract lost.", "#FF8080")
                    MISSION.untrack(m.id)
                    table.remove(_active, i)
                    JOBS.updateObj()
                else
                    local hack_lvl = target:getSystemHackedLevel(m.system)
                    if hack_lvl >= m.hack_threshold then
                        m._hacked = true
                        target:setCanBeDestroyed(true)
                        m.obj = "Return " .. m.cargo .. " to " .. m.origin
                        RT.shipLog("[Hack] Data extracted from " .. m.target_cs
                            .. ". Return to " .. m.origin .. ".", "#80FF80")
                        if m.intercept and not m.intercept.fired then
                            m.intercept.fired = true
                            local origin_e = RT.find(m.origin)
                            if RT.valid(origin_e) then
                                m._dx, m._dy = origin_e:getPosition()
                            end
                            local ref = RT.nearestPlayer(m.wx, m.wy)
                            if ref then
                                local px, py = ref:getPosition()
                                MISSION._spawnIntercept(m, px, py)
                            end
                        end
                        JOBS.updateObj()
                    end
                end
            end
        end

        ::next_entry::
    end
end

--------------------------------------------------------------------------------
-- Rumors and wreck logs
--------------------------------------------------------------------------------

local RUMORS = {}

-- Wreck story fragments, keyed by callsign.
local _WRECK_LOGS = {
    -- Boneyard — Settlement War hulks
    ["CWS Bulwark"]        = '"Day 47 of the siege. Captain Orin to any Concord command: we are holding Ashgrave approach. We are still holding. Please respond."',
    ["Free Ship Defiance"] = '"They told us the vote would be bloodless. Somebody forgot to tell the gunships."  — last entry, Free Ship Defiance.',
    ["CWS Morningside"]    = 'Distress beacon, CWS Morningside, crew of eleven. Hull breach compartments three through seven. "If anyone receives this — we were here."',
    ["Free Ship Hollis"]   = 'Hollis crew manifest recovered from emergency memory. Forty-one names. The war ended six weeks after they launched.',
    ["CWS Anvil"]          = '"We\'re not retreating. We\'re advancing in a new direction." — Commander Vayne, CWS Anvil. Last words before the bridge lost pressure.',
    ["Free Ship Tallow"]   = '"If you\'re reading this, the settlement worked. Tell my kids I held the line."  — Tallow final transmission.',
    ["CWS Equity"]         = '"We surrendered at 0400. The Concord officer was kind about it. I don\'t know what to make of that."  — Captain\'s log, CWS Equity.',
    ["Free Ship Long Odds"] = 'Encrypted fragment, twenty-year-old code. "Rally at Ashgrave. One last push."  Free Ship Long Odds never arrived.',
    ["CWS Clarion"]        = 'Automated beacon, CWS Clarion, looping since the war ended. Hull integrity: 12%. Crew status: unknown. Unknown. Unknown.',
    ["Free Ship Harrow"]   = '"You\'re fighting for a rock." "We\'re fighting so the rock is ours."  End of argument. End of recording.',
    ["CWS Mercy"]          = '"We have more injured than bay capacity. I am going to run out of things to write."  — Medical log, CWS Mercy.',
    ["Free Ship Whistler"] = 'Navigation log, Free Ship Whistler. Last entry automated. Destination: Tamsin. Arrival: never.',
    -- Dustmote — recent hulks
    ["Hulk 7"]  = 'Salvage tag attached: "Strip to frame, sell the rest." Someone didn\'t finish the job.',
    ["Hulk 12"] = 'Registry plate still readable: Persistent Hope. Someone scraped off the name but left the plate.',
    ["Hulk 19"] = 'A coffee mug magnetically clamped to the helm. Still has coffee in it. Relatively recent.',
    ["Hulk 23"] = 'Personal log found wedged in a console. First entry: "New ship, new start." Last entry: "Engine won\'t start." Three months between.',
    -- Shroud — missing freighters
    ["Penny Dreadful"]   = '"The Shroud doesn\'t mess with sensors. The Shroud messes with you. We\'re turning back."  — Penny Dreadful voice log. They didn\'t turn back.',
    ["Calloway's Luck"]  = '"We found something. I don\'t know what it is. I don\'t think it\'s— [static] —beautiful."  — Final comms, Calloway\'s Luck.',
    ["Seventh Son"]      = 'Automated log, Seventh Son. Navigation: position unknown. Course: unknown. Drift duration: 47 days. Hull: intact. Crew: [null].',
}

local _wrecks_logged = {}  -- callsign -> true

function RUMORS.checkWrecks()
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
                    DIR.emit("wreck_scanned", {name=cs, tier=entry.tier}, "low")
                end
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
    PATROL.init()

    -- Spawn player at Port Vesper (safe starting location)
    local px, py = VERSE.at("Port Vesper", 1.5, 1.5)
    RT.spawnPlayer(px, py, 0)

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
        RT.shipLog("Session " .. S.session_num .. " begins. Current funds: " .. RT.credits() .. " credits.", "#A0E0A0")
        if S.session_num == 1 then
            RT.shipLog("Helm: Stations are marked on the sector map. Science: Scan objects to reveal details. Relay: Hail stations for rumours. Engineering: Watch your power and repair damage. Weapons: Keep missiles loaded.", "#E0E0A0")
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
            RT.shipLog("Salvage detected nearby.", "#A0E0E0")
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
    PATROL.update(delta)
    MISSION.update(delta)

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
    RUMORS.checkWrecks()

    -- Scripted random encounters when director is off
    if not DIR.enabled and S.phase == "exploring" then
        -- Simple fallback: occasional random encounters in dangerous areas
        if now - S.last_encounter_time > 300 then  -- 5 minutes
            local ref = RT.nearestPlayer(0, 0)
            local region_data = ref and VERSE.regionAt(ref:getPosition())
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
    local ref = RT.nearestPlayer(0, 0)
    if not ref then return end

    local px, py = ref:getPosition()
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

    RT.shipLog("Contact: " .. template .. " detected in " .. region_data.name .. ".", "#FF8080")
end
