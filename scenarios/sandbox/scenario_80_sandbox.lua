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
require("ragtag/rumors.lua")

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
    witness_active = false,    -- locks job board once The Witness arc begins
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

-- Creative names for spawned mission targets
local _CORSAIR_NAMES = {
    "Blackjack", "Cutthroat", "Rogue Star", "Night Runner", "Silent Edge",
    "Red Drift", "Ghost Hound", "Dark Current", "Bone Cutter", "Scarlet Wake",
    "Shadow Play", "Viper's Run", "Iron Thorn", "Void Walker", "Cruel Fortune",
    "Wild Card", "Blood Money", "Fast Poison", "Dead Reckoning", "Sharp Practice",
    "Quick Silver", "Bad Penny", "Loose Cannon", "Dirty Business", "Hard Bargain",
    "Last Chance", "Cold Comfort", "Rough Justice", "Dark Horse", "Free Radical",
}

-- Generate a random beacon designator like "Beacon AB3C2"
local function generateBeaconName()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ123456789"  -- no I, O, 0 to avoid confusion
    local code = ""
    for i = 1, 5 do
        local idx = math.random(#chars)
        code = code .. chars:sub(idx, idx)
    end
    return "Beacon " .. code
end
local function jobLine(m, now)
    return m.short
end

function JOBS.refreshPanel()
    local now = getScenarioTime()
    RT.forEachPlayer(function(p)
        for slot = 1, 2 do
            local entry = _active[slot]
            local txt = (entry and entry.phase == "active")
                        and ("Job: " .. jobLine(entry.mission, now))
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

function JOBS.accept(m, skip_log)
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

    -- Spawn boarding/hacking targets immediately so player knows the target name
    if m.type == "boarding" and not m._spawned then
        local s = CpuShip():setTemplate(m.target_template):setFaction("Corsairs")
        -- Give it a creative Corsair name
        local name = _CORSAIR_NAMES[math.random(#_CORSAIR_NAMES)]
        s:setCallSign(name)
        s:setPosition(m.wx + random(-2000, 2000), m.wy + random(-2000, 2000))
        s:orderRoaming()
        RT.register(s)
        DIR.registerKill(s)
        DIR.allowControl(s)
        s:setCommsFunction(function(src, tgt)
            setCommsMessage('"Get away from us."')
        end)
        m.target_cs = name
        -- Update short description and objective with actual target name
        m.short = "Disable the " .. name
        m.obj = "Disable " .. name
        m._spawned  = true
    elseif m.type == "hacking" and not m._spawned then
        -- Spawn our custom comms relay beacon with only reactor system
        local s = CpuShip():setTemplate("Comms Relay Beacon"):setFaction("Concord")
        -- Give it a random beacon designator
        local name = generateBeaconName()
        s:setCallSign(name)
        s:setTypeName("Comms Relay")
        s:setPosition(m.wx, m.wy):orderIdle():setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
        s:setHullMax(50):setHull(50):setShieldsMax(0):setShields(0)
        s:setCanBeDestroyed(false)
        s:setSystemHealth("reactor", 1.0)

        -- Make reactor hackable
        if s.setHackedLevel then
            s:setHackedLevel("reactor", 0.0)
        end
        RT.register(s)
        s:setCommsFunction(function(src, tgt)
            setCommsMessage("Automated relay. No response.")
        end)
        m.target_cs = name
        -- Update short description and objective with actual relay name
        m.short = "Hack the " .. name
        m.obj = "Hack " .. name
        m._spawned  = true
    end

    -- Write contract details to log (unless caller will do it)
    if not skip_log then
        local dest_hint = m.dest or (m.wx and ("grid " .. MISSION.gridRef(m.wx, m.wy)) or "??")
        if m.type == "boarding" or m.type == "hacking" then
            RT.shipLog(string.format("Contract: %s (%d cr). %dm to complete. Target: %s at %s.",
                m.short, m.reward, math.floor(JOBS.MISSION_DURATION / 60), m.target_cs or "unknown", dest_hint), "#A0C0FF")
        else
            RT.shipLog(string.format("Contract: %s (%d cr). %dm to complete. Head to %s.",
                m.short, m.reward, math.floor(JOBS.MISSION_DURATION / 60), dest_hint), "#A0C0FF")
        end
        if m.intercept then
            RT.shipLog("Intelligence suggests this run may not be quiet.", "#FFCC80")
        end
    end
    return true
end

function JOBS.complete(entry, completing_ship)
    entry.phase = "done"
    for i, a in ipairs(_active) do
        if a == entry then table.remove(_active, i); break end
    end
    MISSION.untrack(entry.mission.id)
    RT.addCredits(entry.mission.reward, "job: " .. entry.mission.short, completing_ship)
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
                    JOBS.complete(ent, s)
                    local recv = (ent.mission.complete_msg or '"Received. Good flying."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            elseif m.type == "salvage" and m.origin == cs and m._found then
                local ent = entry
                addCommsReply(string.format("Deliver %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent, s)
                    local recv = (ent.mission.complete_msg or '"Received. Good work."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            elseif m.type == "boarding" and m.origin == cs and m._boarded then
                local ent = entry
                addCommsReply(string.format("Hand off %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent, s)
                    local recv = (ent.mission.complete_msg or '"Good work."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            elseif m.type == "hacking" and m.origin == cs and m._hacked then
                local ent = entry
                addCommsReply(string.format("Deliver %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent, s)
                    local recv = (ent.mission.complete_msg or '"Good extraction."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            end
        end
    end

    -- Job board locked once The Witness arc starts
    if S.witness_active then return end

    -- On-demand job board: generate fresh deliveries each time.
    addCommsReply("Any work available?", function(s, t)
        local offers = {}
        local mt = JOBS.maxTier()

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
            lines[#lines + 1] = string.format("* %s", m.short)
        end
        setCommsMessage(table.concat(lines, "\n"))
        for _, m in ipairs(offers) do
            local cap = m
            addCommsReply(string.format("Take: %s (%d cr)", cap.short, cap.reward), function(s2, t2)
                if #_active >= 2 then
                    setCommsMessage('"You\'re already carrying two jobs. Finish one first."')
                else
                    JOBS.accept(cap, true)  -- skip_log=true, we'll write it after the message
                    setCommsMessage(cap.brief .. "\n\n\"Come back when it\'s done.\"\n\nTransmitting details to your log.")
                    -- Now write to log after showing the message
                    local dest_hint = cap.dest or (cap.wx and ("grid " .. MISSION.gridRef(cap.wx, cap.wy)) or "??")
                    if cap.type == "boarding" or cap.type == "hacking" then
                        RT.shipLog(string.format("Contract: %s (%d cr). %dm to complete. Target: %s at %s.",
                            cap.short, cap.reward, math.floor(JOBS.MISSION_DURATION / 60), cap.target_cs or "unknown", dest_hint), "#A0C0FF")
                    else
                        RT.shipLog(string.format("Contract: %s (%d cr). %dm to complete. Head to %s.",
                            cap.short, cap.reward, math.floor(JOBS.MISSION_DURATION / 60), dest_hint), "#A0C0FF")
                    end
                    if cap.intercept then
                        RT.shipLog("Intelligence suggests this run may not be quiet.", "#FFCC80")
                    end
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
            -- Phase 1: watch for disable (impulse health < 0.3 or hull < 25%)
            -- (target already spawned in JOBS.accept)
            if not m._disabled then
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
                        -- Docking with disabled ships is allowed by default in EE
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
                                -- Player has boarded successfully
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
            -- Phase 1: watch for hack completion (any system to 50%)
            -- (target already spawned in JOBS.accept)
            if not m._hacked then
                local target = RT.find(m.target_cs)
                if not RT.valid(target) then
                    RT.shipLog("[Hack] Relay destroyed before extraction — contract lost.", "#FF8080")
                    MISSION.untrack(m.id)
                    table.remove(_active, i)
                    JOBS.updateObj()
                else
                    -- Check all hackable systems
                    local systems = {"reactor", "beamweapons", "missilesystem", "maneuver", "impulse", "warp", "jumpdrive", "frontshield", "rearshield"}
                    local max_hack = 0
                    local hacked_system = nil
                    for _, sys in ipairs(systems) do
                        local hack_lvl = target:getSystemHackedLevel(sys)
                        if hack_lvl > max_hack then
                            max_hack = hack_lvl
                            hacked_system = sys
                        end
                    end

                    if max_hack >= m.hack_threshold then
                        m._hacked = true
                        target:setCanBeDestroyed(true)
                        m.obj = "Return " .. m.cargo .. " to " .. m.origin
                        RT.shipLog("[Hack] System breach successful! Data extracted from " .. m.target_cs
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
-- THE WITNESS — optional story arc (GM-triggered)
-- Phases: inactive → offer → transit → checkpoint → revealed →
--         shroud_run → halcyon → broadcast → done
-- S.witness_active blocks the job board for the duration.
--------------------------------------------------------------------------------

local W = {
    phase            = "inactive",
    phase_entered    = 0,
    panel_next       = 0,
    -- pod
    pod_stability    = 100.0,
    pod_drain_on     = false,
    ep_next          = 0,        -- emergency power cooldown (scenario time)
    -- flags
    kael_alive       = true,
    complied         = false,    -- surrendered pod at checkpoint
    checkpoint_fired = false,
    checkpoint_choice = nil,     -- "comply" | "stall" | "run"
    checkpoint_timer  = 0,
    sable_warned     = false,
    broadcast_done   = false,
    -- entity callsigns
    concord_names    = {},
    corsair_names    = {},
    buoy_cs          = nil,
    -- cooldowns
    last_warning     = -999,
}

-- ── Utilities ──────────────────────────────────────────────────────────────

local function W_enterPhase(name)
    W.phase        = name
    W.phase_entered = getScenarioTime()
end

-- Drain ship energy and degrade pod stability based on power level.
local function W_podTick(delta)
    if not W.pod_drain_on or not W.kael_alive then return end

    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            p:setEnergyLevel(math.max(0, p:getEnergy() - 5 * delta))
        end
    end)

    local total_frac, count = 0, 0
    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            local mx = p:getMaxEnergy()
            if mx > 0 then
                total_frac = total_frac + p:getEnergy() / mx
                count = count + 1
            end
        end
    end)
    local frac = count > 0 and (total_frac / count) or 1.0

    local change = 0
    if     frac < 0.10 then change = -5.0 * delta
    elseif frac < 0.25 then change = -2.5 * delta
    elseif frac < 0.45 then change = -0.8 * delta
    elseif frac > 0.70 then change =  0.3 * delta
    end

    local prev = W.pod_stability
    W.pod_stability = math.max(0, math.min(100, W.pod_stability + change))

    local now = getScenarioTime()
    for _, thr in ipairs({60, 30, 10}) do
        if prev > thr and W.pod_stability <= thr and now - W.last_warning > 20 then
            W.last_warning = now
            if thr == 60 then
                RT.shipLog("[Stasis] Pod stability dropping. Engineering: watch your energy draw.", "#FFAA00")
            elseif thr == 30 then
                RT.shipLog("[Stasis] CRITICAL — pod failing. Engineering: emergency power now.", "#FF4040")
            elseif thr == 10 then
                RT.shipLog("[Science] Cardiac arrest imminent. We need everything Engineering can give.", "#FF4040")
            end
        end
    end

    if W.pod_stability <= 0 and W.kael_alive then
        W.kael_alive   = false
        W.pod_drain_on = false
        RT.shipLog("[Stasis] Kael Voss — flatlined.", "#FF4040")
        RT.forEachPlayer(function(p)
            if RT.valid(p) then
                p:addCustomInfo("engineering", "w_pod_status", "Stasis pod: OFFLINE — patient lost", 1)
                p:addCustomInfo("science",     "w_pod_vitals", "Patient vitals: flatline",            1)
            end
        end)
    end
end

local function W_updatePanels()
    if not W.kael_alive then return end  -- flatline messages set on death; don't overwrite
    local stab   = W.pod_stability
    local status = stab > 60 and "Stable" or (stab > 30 and "Unstable" or "CRITICAL")
    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            p:addCustomInfo("engineering", "w_pod_status",
                string.format("Stasis pod: %.0f%% — %s", stab, status), 1)
            p:addCustomInfo("science", "w_pod_vitals",
                string.format("Patient vitals: %s (pod %.0f%%)",
                    stab > 60 and "stable" or (stab > 30 and "irregular" or "critical"),
                    stab), 1)
        end
    end)
end

local function W_addPodButtons()
    RT.forEachPlayer(function(p)
        if not RT.valid(p) then return end
        p:addCustomButton("engineering", "w_ep_button", "Emergency Power (pod)", function()
            local now = getScenarioTime()
            if now < W.ep_next then
                RT.shipLog(string.format("[Engineering] Emergency power on cooldown — %.0fs remaining.", W.ep_next - now), "#FFAA00")
                return
            end
            W.ep_next       = now + 90
            W.pod_stability = math.min(100, W.pod_stability + 25)
            RT.shipLog(string.format("[Engineering] Emergency power rerouted — pod stability +25 (now %.0f%%).", W.pod_stability), "#80FF80")
        end, 10)
    end)
end

local function W_removePodUI()
    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            p:removeCustom("w_ep_button")
            p:removeCustom("w_pod_status")
            p:removeCustom("w_pod_vitals")
        end
    end)
end

-- ── Phase functions (defined bottom-up so each can reference earlier ones) ─

local function W_finish()
    if W.broadcast_done then return end
    W.broadcast_done = true
    W_enterPhase("done")
    W.pod_drain_on = false
    W_removePodUI()

    local reward, msg
    if W.kael_alive and not W.complied then
        reward = 600
        msg    = "Broadcast sent. Kael Voss survived. His evidence is on every channel in the Drift — they can't unring this bell."
    elseif not W.kael_alive then
        reward = 400
        msg    = "Broadcast sent. Kael Voss didn't survive the transit, but his evidence did. The truth got out, carried by a dead man's data."
    else
        reward = 300
        msg    = "Broadcast sent. Kael is in Concord custody, but the evidence is now public. It may free him. It may not be enough."
    end

    local outcome = W.kael_alive and (W.complied and "broadcast_after_comply" or "kael_survived") or "broadcast_only"
    RT.addCredits(reward, "The Witness: " .. outcome)
    RT.shipLog("[The Witness] " .. msg .. " +" .. reward .. " cr.", "#80FF80")
    RT.flag("witness_complete", outcome)
    DIR.emit("witness_complete", {outcome = outcome, kael_alive = W.kael_alive, complied = W.complied}, "high")
    RT.setObjective("The Witness: complete", true)

    local buoy = RT.find(W.buoy_cs or "")
    if RT.valid(buoy) then buoy:setCanBeDestroyed(true) end

    globalMessage("The Witness — arc complete. " .. msg, 15)
end

local function W_startBroadcast()
    W_enterPhase("broadcast")

    local buoy = RT.find(W.buoy_cs or "")
    if RT.valid(buoy) then
        local bx, by = buoy:getPosition()
        RT.shipLog("[Relay] " .. W.buoy_cs .. " at grid " .. MISSION.gridRef(bx, by) ..
            ". Open the hacking panel and target the reactor.", "#A0C0FF")
        buoy:setCommsFunction(function(src, tgt)
            setCommsMessage('"Public Relay Node. Unauthorized access detected. This channel is Concord-licensed."')
        end)
    end

    -- Concord response wave
    local ref = RT.nearestPlayer(0, 0)
    if ref and RT.valid(ref) then
        local px, py = ref:getPosition()
        for i = 1, 3 do
            local s = CpuShip():setTemplate("MT52 Hornet"):setFaction("Concord")
            local ang = ((i - 1) / 3) * 2 * math.pi + math.random() * 0.5
            s:setPosition(px + math.cos(ang) * 22000, py + math.sin(ang) * 22000)
            s:orderAttack(ref)
            RT.register(s); DIR.registerKill(s); DIR.allowControl(s)
        end
    end
    RT.shipLog("[Warning] Concord response inbound — three ships. Hold them off while Relay completes the broadcast.", "#FF8080")
end

local function W_startHalcyon()
    W_enterPhase("halcyon")
    RT.setObjective("Dock at Halcyon Rest", true)

    -- Spawn the relay buoy near Halcyon Rest
    local hx, hy = VERSE.at("Halcyon Rest", 8, 6)
    local buoy = CpuShip():setTemplate("Escape Pod"):setFaction("Independent")
    buoy:setPosition(hx + random(-1500, 1500), hy + random(-1500, 1500))
    buoy:orderIdle()
    buoy:setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    buoy:setWeaponTubeCount(0):setCanBeDestroyed(false)
    buoy:setCallSign("Public Relay " .. math.random(10, 99))
    RT.register(buoy)
    W.buoy_cs = buoy:getCallSign()

    local bx, by = buoy:getPosition()
    RT.shipLog("[Intel] Relay buoy: " .. W.buoy_cs .. " at grid " .. MISSION.gridRef(bx, by) .. ".", "#A0C0FF")

    RT.addStationHook("Halcyon Rest", function(source, target)
        if not RT.isPlayer(source) then return end
        if not source:isDocked(target) then return end
        if W.phase ~= "halcyon" then return end
        addCommsReply("Ask for Sable.", function(s2, t2)
            if W.sable_warned then
                setCommsMessage('"Sable checked out an hour ago. Left in a hurry — Concord shuttle was asking after her."')
                addCommsReply("We know where to go.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    W_startBroadcast()
                end)
            else
                setCommsMessage('"She\'s here. Keeps looking at the docks."\n\nA message arrives from Sable: "Don\'t trust me. They have leverage. The broadcast still matters — go to the relay buoy. Don\'t wait."')
                W.sable_warned = true
                addCommsReply("Head to the relay buoy.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    W_startBroadcast()
                end)
            end
        end)
    end)
end

local function W_spawnCorsairAmbush()
    local ref = RT.nearestPlayer(0, 0)
    if not ref then return end
    local px, py = ref:getPosition()
    local ang = math.random() * 2 * math.pi
    W.corsair_names = {}
    local templates = {"MT52 Hornet", "MT52 Hornet", "Adder MK5"}
    for i, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction("Corsairs")
        s:setPosition(px + math.cos(ang + (i-1) * 0.7) * (8000 + random(-1000, 1000)),
                      py + math.sin(ang + (i-1) * 0.7) * (8000 + random(-1000, 1000)))
        s:orderAttack(ref)
        RT.register(s); DIR.registerKill(s); DIR.allowControl(s)
        W.corsair_names[i] = s:getCallSign()
    end
    RT.shipLog("[Ambush] Corsairs — " .. table.concat(W.corsair_names, ", ") .. ". Someone talked.", "#FF8080")
end

local function W_startShroudRun()
    W_enterPhase("shroud_run")
    RT.shipLog("[Navigation] Approaching the Shroud. Long-range sensors degrading. Watch for contacts.", "#C0C0C0")
    RT.setObjective("Reach Halcyon Rest", true)
end

local function W_startRevealed()
    W_enterPhase("revealed")
    if W.complied then
        RT.shipLog('[Message] A dead-drop transmission: "The data wasn\'t in the pod — it\'s still with you, hidden in the lining. Get to Halcyon Rest. There\'s a public relay buoy. Finish this." — unsigned.', "#A0C0FF")
    else
        RT.shipLog('[Stasis] Transmission from the pod: "My name is Kael Voss. I was a Concord logistics officer. What I know will end careers. Get me to Halcyon Rest — there\'s a relay buoy there. One broadcast and it\'s over. Whatever she paid you, I\'ll double it."', "#A0C0FF")
    end
    RT.setObjective("Reach Halcyon Rest", true)
end

local function W_startCheckpoint()
    W_enterPhase("checkpoint")

    local ref = RT.nearestPlayer(0, 0)
    local px, py = 50000, -40000
    if ref and RT.valid(ref) then px, py = ref:getPosition() end
    local sx = px + 10000 + random(-2000, 2000)
    local sy = py -  8000 + random(-2000, 2000)

    local s1 = CpuShip():setTemplate("MT52 Hornet"):setFaction("Concord")
    s1:setPosition(sx, sy):orderIdle():setCanBeDestroyed(true)
    RT.register(s1); DIR.registerKill(s1); DIR.allowControl(s1)
    W.concord_names[1] = s1:getCallSign()

    local s2 = CpuShip():setTemplate("MT52 Hornet"):setFaction("Concord")
    s2:setPosition(sx + 3000, sy + random(-800, 800)):orderIdle():setCanBeDestroyed(true)
    RT.register(s2); DIR.registerKill(s2); DIR.allowControl(s2)
    W.concord_names[2] = s2:getCallSign()

    s1:setCommsFunction(function(src, tgt)
        setCommsMessage('"Independent vessel. Cut engines. You are carrying an unregistered stasis pod. Surrender it — you will be free to go."')
        addCommsReply("We're on a licensed delivery. Nothing unusual aboard.", function(s_r, t_r)
            setCommsMessage('"Scan confirms the pod. You have 45 seconds to comply or we board by force."')
            W.checkpoint_choice = "stall"
            W.checkpoint_timer  = getScenarioTime() + 45
            addCommsReply("Fine. Take it.", function(s_r2, t_r2)
                W.complied        = true
                W.checkpoint_choice = "comply"
                setCommsMessage('"Smart choice. On your way."')
                addCommsReply("...", function(s_r3, t_r3) RT.stationComms(s_r3, t_r3) end)
                RT.shipLog("[Checkpoint] Pod surrendered to Concord.", "#FF8080")
                for _, n in ipairs(W.concord_names) do
                    local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
                end
                W_startRevealed()
            end)
            addCommsReply("Full burn — break contact!", function(s_r2, t_r2)
                W.checkpoint_choice = "run"
                for _, n in ipairs(W.concord_names) do
                    local sc = RT.find(n)
                    if RT.valid(sc) and RT.valid(s_r) then sc:orderAttack(s_r) end
                end
            end)
        end)
        addCommsReply("We're not stopping for anyone.", function(s_r, t_r)
            W.checkpoint_choice = "run"
            setCommsMessage('"All units — pursue."')
            for _, n in ipairs(W.concord_names) do
                local sc = RT.find(n)
                if RT.valid(sc) and RT.valid(src) then sc:orderAttack(src) end
            end
        end)
        addCommsReply("Take the pod. We want no trouble.", function(s_r, t_r)
            W.complied        = true
            W.checkpoint_choice = "comply"
            setCommsMessage('"Transfer complete. On your way."')
            addCommsReply("...", function(s_r2, t_r2) RT.stationComms(s_r2, t_r2) end)
            RT.shipLog("[Checkpoint] Pod surrendered to Concord.", "#FF8080")
            for _, n in ipairs(W.concord_names) do
                local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
            end
            W_startRevealed()
        end)
    end)

    RT.hail(s1, "Independent vessel. Cut engines. You are carrying an unregistered stasis pod. Concord inspection — comply immediately.", "Concord Patrol")
    RT.shipLog("[Warning] Concord patrol on intercept — " .. W.concord_names[1] .. ", " .. W.concord_names[2] .. ".", "#FFAA00")
end

local function W_startOffer()
    S.witness_active = true
    W_enterPhase("offer")

    local vx, vy = VERSE.at("Port Vesper", -2, -1)
    local mira = CpuShip():setTemplate("Escape Pod"):setFaction("Independent")
    mira:setPosition(vx, vy)
    mira:orderIdle()
    mira:setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    mira:setWeaponTubeCount(0):setCanBeDestroyed(false)
    mira:setCallSign("Mira's Luck")
    RT.register(mira)

    mira:setCommsFunction(function(src, tgt)
        setCommsMessage('"I need a discreet crew — no questions asked. Passenger in stasis who needs to reach Saint Brennan\'s Mission quietly. Concord would prefer he never arrive. 300 credits. Yes or no?"')
        addCommsReply("We'll take the job.", function(s2, t2)
            setCommsMessage('"Good. Transferring the pod now. He draws five energy a second from your reactor — keep him stable. Get to Saint Brennan\'s Mission before Concord gets word."\n\nMira\'s Luck goes dark.')
            addCommsReply("Understood.", function(s3, t3) RT.stationComms(s3, t3) end)
            local m = RT.find("Mira's Luck")
            if RT.valid(m) then m:destroy() end
            W_enterPhase("transit")
            W.pod_drain_on = true
            W_addPodButtons()
            W_updatePanels()
            RT.shipLog("[Stasis] Pod aboard — Kael Voss in stasis. Destination: Saint Brennan's Mission.", "#A0C0FF")
            RT.shipLog("[Engineering] Pod drawing 5 energy/sec. Keep energy above 50% to maintain stability.", "#FFAA00")
            RT.setObjective("Reach Saint Brennan's Mission", true)
        end)
        addCommsReply("Not our problem.", function(s2, t2)
            setCommsMessage('"Your call. He won\'t last long without power."')
            addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
        end)
    end)

    RT.hail(mira, "Independent vessel — Mira Doss, Mira's Luck. I've got a private offer. Open comms when you're clear.", "Mira Doss")
end

-- ── Main update dispatcher ───────────────────────────────────────────────────

local function W_update(delta)
    if W.phase == "inactive" or W.phase == "offer" or W.phase == "done" then return end

    local now = getScenarioTime()

    -- Pod drain + panel refresh every 5 s in all active phases
    W_podTick(delta)
    if now >= W.panel_next then
        W.panel_next = now + 5
        W_updatePanels()
    end

    if W.phase == "transit" then
        local ref = RT.nearestPlayer(0, 0)
        if ref and RT.valid(ref) then
            local px, py = ref:getPosition()
            if not W.checkpoint_fired and px * px + py * py > 45000 * 45000 then
                W.checkpoint_fired = true
                W_startCheckpoint()
            end
        end

    elseif W.phase == "checkpoint" then
        if W.checkpoint_choice == "stall" and W.checkpoint_timer > 0 and now > W.checkpoint_timer then
            RT.shipLog("[Checkpoint] Time expired — Concord boarded and took the pod.", "#FF8080")
            W.complied        = true
            W.checkpoint_choice = "comply"
            for _, n in ipairs(W.concord_names) do
                local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
            end
            W_startRevealed()
        elseif W.checkpoint_choice == "run" then
            local alive = false
            for _, n in ipairs(W.concord_names) do
                if RT.valid(RT.find(n)) then alive = true; break end
            end
            if not alive then
                RT.shipLog("[Checkpoint] Concord pursuit broken.", "#80FF80")
                W_startRevealed()
            end
        end

    elseif W.phase == "revealed" then
        if now - W.phase_entered > 60 then
            W_startShroudRun()
        end

    elseif W.phase == "shroud_run" then
        if #W.corsair_names == 0 and now - W.phase_entered > 60 then
            W_spawnCorsairAmbush()
        end
        -- Advance when corsairs cleared, near Halcyon Rest, or 5-min timeout
        local halcyon_e = RT.find("Halcyon Rest")
        local near_halcyon = false
        if RT.valid(halcyon_e) then
            local hx, hy = halcyon_e:getPosition()
            local ref = RT.nearestPlayer(hx, hy)
            if ref and RT.valid(ref) then
                local px, py = ref:getPosition()
                local dx, dy = px - hx, py - hy
                near_halcyon = dx * dx + dy * dy < 15000 * 15000
            end
        end
        local corsairs_alive = false
        for _, n in ipairs(W.corsair_names) do
            if RT.valid(RT.find(n)) then corsairs_alive = true; break end
        end
        if near_halcyon or (#W.corsair_names > 0 and not corsairs_alive) or now - W.phase_entered > 300 then
            W_startHalcyon()
        end

    elseif W.phase == "halcyon" then
        -- Also advance when player reaches the buoy directly (saw grid ref in log)
        local buoy = RT.find(W.buoy_cs or "")
        if RT.valid(buoy) then
            local bx, by = buoy:getPosition()
            local ref = RT.nearestPlayer(bx, by)
            if ref and RT.valid(ref) then
                local px, py = ref:getPosition()
                local dx, dy = px - bx, py - by
                if dx * dx + dy * dy < 8000 * 8000 then
                    W_startBroadcast()
                end
            end
        end
        -- 5-minute fallback in case players skip Halcyon Rest comms
        if now - W.phase_entered > 300 then
            W_startBroadcast()
        end

    elseif W.phase == "broadcast" then
        local buoy = RT.find(W.buoy_cs or "")
        if not RT.valid(buoy) then
            RT.shipLog("[Error] Relay buoy destroyed before broadcast — arc failed.", "#FF8080")
            W_enterPhase("done")
            W.pod_drain_on = false
            W_removePodUI()
        elseif buoy:getSystemHackedLevel("reactor") >= 0.5 then
            W_finish()
        end
    end
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function init()
    VERSE.setupFactions()

    -- Create custom Comms Relay ship template - minimal systems
    local relay_template = ShipTemplate():setName("Comms Relay Beacon"):setModel("combatsat")
    relay_template:setClass("Satellite", "Comms Relay")
    relay_template:setDescription("Automated communications relay beacon.")
    relay_template:setRadarTrace("combatsat.png")
    relay_template:setHull(50)
    relay_template:setShields(0, 0)  -- no shields
    relay_template:setSpeed(0, 0, 0)  -- stationary
    -- Don't define weapons, warp, jump - only reactor, impulse, maneuver will exist by default

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
    VERSE.requirePlaces({"Port Vesper", "Saint Brennan's Mission", "Halcyon Rest"})
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

    addGMFunction("Witness: Start arc", function()
        if W.phase ~= "inactive" then
            globalMessage("Witness arc already at phase: " .. W.phase, 5)
            return
        end
        W_startOffer()
    end)

    addGMFunction("Witness: Skip → checkpoint", function()
        S.witness_active   = true
        W.pod_drain_on     = true
        W.checkpoint_fired = true
        W_addPodButtons()
        W_updatePanels()
        RT.shipLog("[Stasis] Pod aboard — Kael Voss in stasis. (GM skip)", "#A0C0FF")
        W_startCheckpoint()
    end)

    addGMFunction("Witness: Skip → broadcast", function()
        S.witness_active   = true
        W.pod_drain_on     = true
        W.checkpoint_fired = true
        W_addPodButtons()
        W_updatePanels()
        RT.shipLog("[Stasis] Pod aboard — Kael Voss in stasis. (GM skip)", "#A0C0FF")
        W_startHalcyon()
        W_startBroadcast()
    end)

    addGMFunction("Witness: Pod → critical", function()
        if W.pod_drain_on then
            W.pod_stability = 15
            RT.shipLog("[GM] Stasis pod forced to critical stability.", "#FF4040")
        end
    end)

    addGMFunction("Witness: Cancel arc", function()
        if W.phase == "inactive" then return end
        local m = RT.find("Mira's Luck")
        if RT.valid(m) then m:destroy() end
        W.phase            = "inactive"
        W.pod_drain_on     = false
        W.checkpoint_fired = false
        W.corsair_names    = {}
        W.concord_names    = {}
        S.witness_active   = false
        W_removePodUI()
        globalMessage("Witness arc cancelled and reset.", 5)
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
    W_update(delta)

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
