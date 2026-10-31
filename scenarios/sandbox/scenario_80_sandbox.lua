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
require("ragtag/proximity.lua")
require("ragtag/mission.lua")
require("ragtag/rumors.lua")

local SESSION_ID = "sandbox"

-- Session state
local S = {
    phase = "start",           -- start, exploring, docked, ending
    session_num = 1,           -- which sandbox session this is
    time_exploring = 0,        -- time spent not docked
    encounters_spawned = 0,
    last_opportunity_time = 0,
    visited_regions = {},      -- track where crew has been
    docked_at = nil,
    ending = false,
    witness_active = false,    -- locks job board once The Witness arc begins
    vesper_first_hail = false, -- track first hail to Port Vesper for welcome message
    work_cooldown_enabled = true,  -- false = infinite mission spam (testing), true = 10min cooldown (gameplay)
    mission_distance_mode = "medium",  -- "short" (15-50U), "medium" (60-200U), "long" (120-400U)
}

--------------------------------------------------------------------------------
-- Mission board (JOBS) -- procedurally-generated contracts offered at stations
--------------------------------------------------------------------------------

local JOBS = {}

-- Display-safe short names (objectives must be <=25 chars; "Deliver to " is 11)
local _SHORT = {
    ["Concord Station Arbiter"] = "C.S. Arbiter",
    ["Concord Waypoint Galen"]  = "Waypoint Galen",
    ["Dustmote Salvage"] = "Dustmote",
    ["Lastchance Outpost"]      = "Lastchance",
    ["Dustmote Salvage"]        = "Dustmote",
    ["Greywater Depot"]         = "Greywater",
}
local function _sd(cs) return _SHORT[cs] or cs end   -- short dest name (<=14 chars)

local _active = {}   -- list of {mission=m, phase="active"|"done"}
local _done   = {}   -- id → true (taken or completed this session)

local _MISSION_WEIGHTS = {
    {type = "delivery", weight = 15},
    {type = "salvage",  weight = 7},
    {type = "boarding", weight = 3},
    {type = "hacking",  weight = 3},
    {type = "tailing",  weight = 3},
    {type = "destroy",  weight = 3},
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
JOBS.WORK_COOLDOWN    = 10 * 60   -- seconds before slot offers new work after mission taken/expired

-- Mission distance calculation based on mode
function JOBS.getMissionDistance()
    local mode = S.mission_distance_mode or "medium"
    if mode == "short" then
        return (15 + math.random() * 35) * 1000  -- 15-50U
    elseif mode == "long" then
        return (120 + math.random() * 280) * 1000  -- 120-400U
    else
        return (60 + math.random() * 140) * 1000  -- 60-200U (medium/default)
    end
end

-- Bounding box of the verse: derived from VERSE.REGIONS extents + margin (in game units).
-- Computed once on first call; open space inside the box is valid mission territory.
local _VERSE_BOUNDS = nil
local function _verseBounds()
    if _VERSE_BOUNDS then return _VERSE_BOUNDS end
    local xn, xx, yn, yx = math.huge, -math.huge, math.huge, -math.huge
    for _, r in ipairs(VERSE.REGIONS) do
        if r.x - r.r < xn then xn = r.x - r.r end
        if r.x + r.r > xx then xx = r.x + r.r end
        if r.y - r.r < yn then yn = r.y - r.r end
        if r.y + r.r > yx then yx = r.y + r.r end
    end
    _VERSE_BOUNDS = {x_min = xn * VERSE.U, x_max = xx * VERSE.U, y_min = yn * VERSE.U, y_max = yx * VERSE.U}
    return _VERSE_BOUNDS
end

-- Pick a spawn coordinate within the verse bounding box (named region or open space).
-- Returns wx, wy, dist, region on success; nil, nil, nil, nil if all attempts miss.
local function _spawnInVerse(rx, ry, max_tries)
    local b = _verseBounds()
    for _ = 1, (max_tries or 8) do
        local ang  = math.random() * 2 * math.pi
        local dist = JOBS.getMissionDistance()
        local wx = math.floor(rx + math.cos(ang) * dist)
        local wy = math.floor(ry + math.sin(ang) * dist)
        if wx >= b.x_min and wx <= b.x_max and wy >= b.y_min and wy <= b.y_max then
            return wx, wy, dist, VERSE.regionAt(wx, wy)
        end
    end
    return nil, nil, nil, nil
end

-- Get the distance range (min, max) for the current mode
function JOBS.getDistanceRange()
    local mode = S.mission_distance_mode or "medium"
    if mode == "short" then
        return 15000, 50000  -- 15-50U
    elseif mode == "long" then
        return 120000, 400000  -- 120-400U
    else
        return 60000, 200000  -- 60-200U (medium/default)
    end
end

-- Extract distance/reward suffix from mission short description
-- e.g. "Disable Blackjack (boarding) (the Shroud, 45u) (185cr)" -> " (the Shroud, 45u) (185cr)"
local function _distRewardSuffix(mission)
    local suffix = mission.short:match("( %([^)]+%) %(%d+cr%))$")
    return suffix or ""
end

-- Per-station work tracking: {callsign → {slots = {[1] = {mission, offered_at, taken_at}, ...}}}
-- Each slot tracks a mission independently with its own cooldown timer
local _station_work = {}

-- Number of job slots a station offers. Tune per-station or per-faction here.
local function _stationSlots(cs)
    return 2
end

local _TYPE_PFX = {delivery="[D]", salvage="[S]", boarding="[B]", hacking="[H]", tailing="[T]", destroy="[X]"}

-- Names for tailing mission rendezvous ships (anonymous freighters)
local _FREIGHTER_NAMES = {
    "Quiet Trade", "Long Run", "Far Margin", "Still Water", "Low Profile",
    "Unmarked", "Grey Cargo", "Clean Manifest", "Third Party", "No Questions",
    "Standard Rate", "Passing Through", "Brief Stop", "Short Notice", "Slow Moving",
    "Common Carriage", "Side Channel", "Dark Freight", "Off The Books", "Thin Air",
}

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

    -- Mark which station slot this mission came from (for per-slot cooldown)
    if m.origin and S.work_cooldown_enabled then
        local station_state = _station_work[m.origin]
        if station_state and station_state.slots then
            for slot_num, slot in pairs(station_state.slots) do
                if slot.mission and slot.mission.id == m.id then
                    m._slot_num = slot_num
                    slot.taken_at = getScenarioTime()
                    slot.mission = nil  -- Clear mission from slot
                    break
                end
            end
        end
    end

    JOBS.updateObj()

    -- Spawn salvage cargo pod immediately so player can see it on scanners
    if m.type == "salvage" and not m._spawned then
        local cargo_pod = SupplyDrop():setFaction("Independent"):setPosition(m.wx, m.wy)
        cargo_pod:setDescriptions("Salvage Container", m.cargo)
        -- Use the cargo name as the callsign (capitalize first letter)
        local cargo_name = m.cargo:gsub("^%l", string.upper)
        cargo_pod:setCallSign(cargo_name)
        print(string.format("[SALVAGE SPAWN] Pod spawned at (%d, %d) for mission from %s", m.wx, m.wy, m.origin))
        -- Set up pickup callback to mark mission complete
        cargo_pod:onPickUp(function(self, player)
            -- Find the mission this cargo belongs to
            for _, entry in ipairs(_active) do
                local mission = entry.mission
                if mission.type == "salvage" and mission.cargo_obj == self then
                    mission._found = true
                    mission.obj = "Return " .. mission.cargo .. " to " .. mission.origin
                    RT.shipLog("[Salvage] Cargo pod collected: " .. mission.cargo .. ". Return to " .. mission.origin .. " for payment.", "#80FF80")
                    JOBS.updateObj()
                    if mission.intercept and not mission.intercept.fired then
                        mission.intercept.fired = true
                        MISSION._spawnIntercept(mission, player:getPosition())
                    end
                    break
                end
            end
        end)
        RT.register(cargo_pod)
        m.cargo_obj = cargo_pod  -- store reference
        m._spawned = true
    -- Spawn boarding/hacking/destroy targets immediately so player knows the target name
    elseif (m.type == "boarding" or m.type == "destroy") and not m._spawned then
        -- Use the pre-calculated target_dest from mission generation
        local dest_station = nil
        if m.target_dest then
            dest_station = RT.find(m.target_dest)
        end

        -- Use base template directly - custom templates causing spawn issues
        -- Spawn as Unknown faction so they require Science scanning to identify
        local s = CpuShip():setTemplate(m.target_template):setFaction("Unknown")
        -- Give it a creative Corsair name
        local name = _CORSAIR_NAMES[math.random(#_CORSAIR_NAMES)]
        s:setCallSign(name)
        s:setPosition(m.wx + random(-2000, 2000), m.wy + random(-2000, 2000))

        -- Ensure ship spawns with full health (sometimes templates have damaged systems)
        s:setHull(s:getHullMax())
        s:setSystemHealth("impulse", 1.0)
        s:setSystemHealth("reactor", 1.0)
        s:setSystemHealth("beamweapons", 1.0)
        s:setSystemHealth("missilesystem", 1.0)
        s:setSystemHealth("maneuver", 1.0)
        s:setSystemHealth("warp", 1.0)
        s:setSystemHealth("jumpdrive", 1.0)
        s:setSystemHealth("frontshield", 1.0)
        s:setSystemHealth("rearshield", 1.0)

        -- Set shields to max
        local max_front = s:getShieldMax(0)
        local max_rear = s:getShieldMax(1)
        if max_front > 0 then s:setShields(max_front, max_rear) end

        -- Make easy to scan (low complexity/depth for Unknown faction targets)
        s:setScanningParameters(1, 1)  -- complexity=1, depth=1 (quick scan)

        -- Order ship to fly toward destination station
        if dest_station then
            local dx, dy = dest_station:getPosition()
            s:orderFlyTowards(dx, dy)
        else
            s:orderRoaming()
        end

        RT.register(s)
        DIR.registerKill(s)
        DIR.allowControl(s)
        s:setCommsFunction(function(src, tgt)
            setCommsMessage('"Get away from us."')
        end)

        m.target_cs = name
        -- Update short description and objective with actual target name
        local suffix = _distRewardSuffix(m)
        if m.type == "boarding" then
            m.short = "Disable " .. name .. " (boarding)" .. suffix
            m.obj = "Intercept " .. name
        else  -- destroy
            m.short = "Destroy " .. name .. " (destroy)" .. suffix
            m.obj = "Destroy " .. name
        end
        m._spawned  = true
        m._attacking = false  -- Track if ship has engaged player
    elseif m.type == "hacking" and not m._spawned then
        -- Spawn our custom comms relay beacon with only reactor system
        local grid = MISSION.gridRef(m.wx, m.wy)
        print(string.format("[HACKING SPAWN] Spawning relay at (%.0f, %.0f) grid %s", m.wx, m.wy, grid))
        local s = CpuShip():setTemplate("ANT 615"):setFaction("Concord")
        -- Give it a random beacon designator
        local name = generateBeaconName()
        s:setCallSign(name)
        s:setTypeName("Comms Relay")
        s:setPosition(m.wx, m.wy):orderIdle():setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
        s:setHullMax(50):setHull(50):setShieldsMax(0):setShields(0)
        s:setCanBeDestroyed(false)
        s:setSystemHealth("reactor", 1.0)

        -- Make reactor hackable
        s:setSystemHackedLevel("reactor", 0.0)
        -- Don't use RT.register - it triggers CpuShip reputation tracking that might destroy it
        -- Just add to named lookup directly
        RT.named[name] = s
        s:setCommsFunction(function(src, tgt)
            setCommsMessage("Automated relay. No response.")
        end)

        m.target_cs = name
        -- Update short description and objective with actual relay name
        local suffix = _distRewardSuffix(m)
        m.short = "Hack " .. name .. " (hacking)" .. suffix
        m.obj = "Hack " .. name
        m._spawned  = true
    elseif m.type == "tailing" and not m._spawned then
        -- Timing: place both ships equidistant from the meeting point so they arrive
        -- at the same moment the player (travelling at warp 1) reaches the target area.
        local WARP1    = 500  -- game units/sec (warp 1 = 30 U/min)
        local px, py   = RT.player:getPosition()
        local d_player = math.sqrt((m.wx - px)^2 + (m.wy - py)^2)
        local d_meet   = math.max(d_player, 15000)  -- minimum 15 U (~30 s at warp 1)
        local T        = d_meet / WARP1

        -- Keep pre-computed meeting direction; recalculate distance so timing works out
        local meet_ang = math.atan(m.my - m.wy, m.mx - m.wx)
        m.mx = math.floor(m.wx + math.cos(meet_ang) * d_meet)
        m.my = math.floor(m.wy + math.sin(meet_ang) * d_meet)

        -- Target ship: Unknown faction — requires Science scan to identify
        local tname = _CORSAIR_NAMES[math.random(#_CORSAIR_NAMES)]
        local target = CpuShip():setTemplate(m.target_template):setFaction("Unknown")
        target:setCallSign(tname)
        target:setPosition(m.wx + random(-2000, 2000), m.wy + random(-2000, 2000))
        target:setHull(target:getHullMax())
        target:setScanningParameters(1, 1)
        target:orderFlyTowards(m.mx, m.my)
        RT.register(target)
        target:setCommsFunction(function(src, tgt) setCommsMessage('"No response."') end)

        -- Rendezvous ship: spawn d_meet beyond meeting point (total 2×d_meet from target)
        -- Both ships travel at warp 1 and arrive at the meeting point at time T.
        local rname = _FREIGHTER_NAMES[math.random(#_FREIGHTER_NAMES)]
        local rx = math.floor(m.mx + math.cos(meet_ang) * d_meet)
        local ry = math.floor(m.my + math.sin(meet_ang) * d_meet)
        local rendezvous = CpuShip():setTemplate("Flavia P.Falcon"):setFaction("Unknown")
        rendezvous:setCallSign(rname)
        rendezvous:setPosition(rx, ry)
        rendezvous:orderFlyTowards(m.mx, m.my)
        RT.register(rendezvous)
        rendezvous:setCommsFunction(function(src, tgt) setCommsMessage('"Move along."') end)

        m.target_cs     = tname
        m.rendezvous_cs = rname
        m._meet_at      = getScenarioTime() + T
        local suffix = _distRewardSuffix(m)
        m.short = "Surveil " .. tname .. " (tailing)" .. suffix
        m.obj   = "Locate " .. tname
        m._spawned = true
    end

    -- Write contract details to log (unless caller will do it)
    if not skip_log then
        local dest_hint
        if m.type == "delivery" and m.dest then
            -- For delivery missions, include station name and grid
            local dest_e = RT.find(m.dest)
            if RT.valid(dest_e) then
                local dx, dy = dest_e:getPosition()
                local grid = MISSION.gridRef(dx, dy)
                dest_hint = m.dest .. " (" .. grid .. ")"
            else
                dest_hint = m.dest
            end
        else
            -- For other mission types, use grid coordinates
            dest_hint = m.dest or (m.wx and ("grid " .. MISSION.gridRef(m.wx, m.wy)) or "??")
        end

        if m.type == "boarding" or m.type == "destroy" then
            local heading_text = m.target_dest and (" heading toward " .. m.target_dest) or ""
            RT.shipLog(string.format("Contract: %s. %dm to complete. %s is at %s%s.",
                m.short, math.floor(JOBS.MISSION_DURATION / 60), m.target_cs or "unknown", dest_hint, heading_text), "#60CCFF")
        elseif m.type == "hacking" then
            RT.shipLog(string.format("Contract: %s. %dm to complete. Target: %s at %s.",
                m.short, math.floor(JOBS.MISSION_DURATION / 60), m.target_cs or "unknown", dest_hint), "#60CCFF")
        elseif m.type == "tailing" then
            -- Heading from spawn to meeting point (EE: 0=north, 90=east)
            local hdx = m.mx - m.wx
            local hdy = m.my - m.wy
            local heading_deg = math.floor((math.deg(math.atan(hdx, -hdy)) + 360) % 360 + 0.5)
            local t_min = math.max(1, math.floor((m._meet_at - getScenarioTime()) / 60 + 0.5))
            RT.shipLog(string.format("Contract: %s. %dm to complete. Target last spotted at %s heading %03d. We expect a rendezvous in ~%dm. Approach with care.",
                m.short, math.floor(JOBS.MISSION_DURATION / 60), dest_hint, heading_deg, t_min), "#60CCFF")
        else
            RT.shipLog(string.format("Contract: %s. %dm to complete. Head to %s.",
                m.short, math.floor(JOBS.MISSION_DURATION / 60), dest_hint), "#60CCFF")
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

    -- Award reputation based on mission origin station's faction
    local origin_station = RT.find(entry.mission.origin)
    if RT.valid(origin_station) then
        local faction = origin_station:getFaction()
        RT.addReputation(faction, 10, "mission: " .. entry.mission.short)
    end

    -- For destroy missions, penalize Corsairs since we killed one of theirs
    if entry.mission.type == "destroy" then
        RT.addReputation("Corsairs", -10, "destroyed Corsair target")
    end

    JOBS.updateObj()
    DIR.emit("job_complete", {type=entry.mission.type, tier=entry.mission.tier, reward=entry.mission.reward}, "low")
end

function JOBS.updateObj()
    if #_active == 0 then
        RT.setObjective("Explore the Drift", true)
    else
        -- Job panel already shows mission details, keep objective generic
        RT.setObjective("Explore the Drift", true)
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
            elseif (m.type == "hacking" or m.type == "destroy") and m.origin == cs and (m._hacked or m._destroyed) then
                local ent = entry
                addCommsReply(string.format("Deliver %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent, s)
                    local recv = (ent.mission.complete_msg or '"Good extraction."')
                    setCommsMessage(recv .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            elseif m.type == "tailing" and m.origin == cs and m._scanned then
                local ent = entry
                addCommsReply(string.format("Deliver %s (+%d cr)", m.cargo, m.reward), function(s, t)
                    JOBS.complete(ent, s)
                    local recv = (ent.mission.complete_msg or '"Good work."')
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
        local ok, err = pcall(function()
            local offers = {}
            local mt = JOBS.maxTier()
            local now = getScenarioTime()

            -- Initialize station work tracking (per-slot system)
            local n_slots = _stationSlots(cs)
            if not _station_work[cs] then
                local slots = {}
                for i = 1, n_slots do
                    slots[i] = {mission = nil, offered_at = 0, taken_at = nil}
                end
                _station_work[cs] = {slots = slots}
            end
            local station_state = _station_work[cs]

            -- Per-slot cooldown system: each slot tracks independently
            local slots_to_generate = {}
            if S.work_cooldown_enabled then
                for slot_num = 1, n_slots do
                    local slot = station_state.slots[slot_num]

                    if slot.mission and not slot.taken_at then
                        -- Slot has mission that hasn't been taken
                        if now - slot.offered_at < JOBS.WORK_COOLDOWN then
                            -- Still within offer window: show existing mission
                            offers[#offers + 1] = slot.mission
                        else
                            -- Offer expired: generate new mission for this slot
                            slots_to_generate[#slots_to_generate + 1] = slot_num
                        end
                    elseif slot.taken_at then
                        -- Slot's mission was taken
                        if now - slot.taken_at >= JOBS.WORK_COOLDOWN then
                            -- Cooldown expired: generate new mission for this slot
                            slot.taken_at = nil  -- Clear cooldown
                            slots_to_generate[#slots_to_generate + 1] = slot_num
                        end
                        -- else: still on cooldown, slot stays empty
                    else
                        -- Slot is empty (first visit or cooldown cleared): generate mission
                        slots_to_generate[#slots_to_generate + 1] = slot_num
                    end
                end
            else
                -- Cooldown disabled: always generate for all slots
                for i = 1, n_slots do slots_to_generate[i] = i end
            end

            -- Director-pushed deliveries take priority (no re-offer if already taken)
        for _, m in ipairs(MISSION._dynamic_queue) do
            if m.origin == cs and not _done[m.id] then
                offers[#offers + 1] = m
            end
        end

        -- Generate missions for slots that need them
        local slots_failed = 0
        if #slots_to_generate > 0 then
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
            local dist_min, dist_max = JOBS.getDistanceRange()
            for _, slot_num in ipairs(slots_to_generate) do
                local tier  = math.min(mt, math.random(0, 1))
                local mtype = pickMissionType()
                local generated_mission = nil
                if mtype == "delivery" and dest_idx <= #candidates then
                    local dest_e = RT.find(candidates[dest_idx])
                    local distance_u = 0
                    local dest_danger = 0
                    local dest_region = nil
                    if RT.valid(station_e) and RT.valid(dest_e) then
                        local ox, oy = station_e:getPosition()
                        local dx, dy = dest_e:getPosition()
                        local ddx, ddy = dx - ox, dy - oy
                        distance_u = math.sqrt(ddx * ddx + ddy * ddy)
                        dest_region = VERSE.regionAt(dx, dy)
                        dest_danger = dest_region and dest_region.danger or 0
                        print(string.format("[DELIVERY] %s > %s | Dist: %.1fU | Slot %d", cs, candidates[dest_idx], distance_u/1000, slot_num))
                    end
                    generated_mission = MISSION.newDelivery({
                        origin = cs,
                        dest = candidates[dest_idx],
                        tier = tier,
                        distance_u = distance_u,
                        danger_level = dest_danger,
                        region_name = dest_region and dest_region.name or nil,
                        distance_min_u = dist_min,
                        distance_max_u = dist_max,
                    })
                    dest_idx = dest_idx + 1
                elseif mtype == "salvage" and RT.valid(station_e) then
                    local rx, ry = station_e:getPosition()
                    local wx, wy, dist, region = _spawnInVerse(rx, ry)
                    if not wx then
                        slots_failed = slots_failed + 1
                    else
                        print(string.format("[SALVAGE] Station: %s (%d, %d) | Target: (%d, %d) | Dist: %.1fU (%.0f) | Slot %d",
                            cs, rx, ry, wx, wy, dist/1000, dist, slot_num))
                        local mission_ok, mission_err = pcall(function()
                            return MISSION.newSalvage({
                                origin = cs,
                                wx = wx,
                                wy = wy,
                                tier = tier,
                                distance_u = dist,
                                danger_level = region.danger,
                                region_name = region.name,
                                distance_min_u = dist_min,
                                distance_max_u = dist_max,
                            })
                        end)
                        if mission_ok then
                            generated_mission = mission_err
                        else
                            print("[ERROR] Salvage mission generation failed: " .. tostring(mission_err))
                            error("Salvage: " .. tostring(mission_err))
                        end
                    end
                elseif mtype == "boarding" and RT.valid(station_e) then
                    local rx, ry = station_e:getPosition()
                    local wx, wy, dist, region = _spawnInVerse(rx, ry)
                    if not wx then
                        slots_failed = slots_failed + 1
                    else
                        print(string.format("[BOARDING] Station: %s (%d, %d) | Target: (%d, %d) | Dist: %.1fU (%.0f) | Slot %d",
                            cs, rx, ry, wx, wy, dist/1000, dist, slot_num))
                        local nearby = {}
                        for _, st in ipairs(VERSE.STATIONS) do
                            if st.cs ~= cs and st.fac ~= "Corsairs" and st.fac ~= "Hollow" then
                                local st_e = RT.find(st.cs)
                                if RT.valid(st_e) then
                                    local sx, sy = st_e:getPosition()
                                    local ddx, ddy = sx - wx, sy - wy
                                    if ddx * ddx + ddy * ddy < 150000 * 150000 then
                                        nearby[#nearby + 1] = st.cs
                                    end
                                end
                            end
                        end
                        local mission_ok, mission_err = pcall(function()
                            return MISSION.newBoarding({
                                origin = cs,
                                wx = wx,
                                wy = wy,
                                tier = tier,
                                distance_u = dist,
                                danger_level = region.danger,
                                region_name = region.name,
                                nearby_stations = nearby,
                                distance_min_u = dist_min,
                                distance_max_u = dist_max,
                            })
                        end)
                        if mission_ok then
                            offers[#offers + 1] = mission_err
                        else
                            print("[ERROR] Boarding mission generation failed: " .. tostring(mission_err))
                            error("Boarding: " .. tostring(mission_err))
                        end
                    end
                elseif (mtype == "hacking" or mtype == "destroy") and RT.valid(station_e) then
                    local rx, ry = station_e:getPosition()
                    local wx, wy, dist, region = _spawnInVerse(rx, ry)
                    if not wx then
                        slots_failed = slots_failed + 1
                    elseif mtype == "hacking" then
                        print(string.format("[HACKING] Station: %s (%d, %d) | Target: (%d, %d) | Dist: %.1fU (%.0f) | Slot %d",
                            cs, rx, ry, wx, wy, dist/1000, dist, slot_num))
                        local mission_ok, mission_err = pcall(function()
                            return MISSION.newHacking({
                                origin = cs,
                                wx = wx,
                                wy = wy,
                                tier = tier,
                                distance_u = dist,
                                danger_level = region.danger,
                                region_name = region.name,
                                distance_min_u = dist_min,
                                distance_max_u = dist_max,
                            })
                        end)
                        if mission_ok then
                            generated_mission = mission_err
                        else
                            print("[ERROR] Hacking mission generation failed: " .. tostring(mission_err))
                            error("Hacking: " .. tostring(mission_err))
                        end
                    else  -- destroy
                        print(string.format("[DESTROY] Station: %s (%d, %d) | Target: (%d, %d) | Dist: %.1fU (%.0f) | Slot %d",
                            cs, rx, ry, wx, wy, dist/1000, dist, slot_num))
                        local nearby = {}
                        for _, st in ipairs(VERSE.STATIONS) do
                            if st.cs ~= cs and st.fac ~= "Corsairs" and st.fac ~= "Hollow" then
                                local st_e = RT.find(st.cs)
                                if RT.valid(st_e) then
                                    local sx, sy = st_e:getPosition()
                                    local ddx, ddy = sx - wx, sy - wy
                                    if ddx * ddx + ddy * ddy < 150000 * 150000 then
                                        nearby[#nearby + 1] = st.cs
                                    end
                                end
                            end
                        end
                        local mission_ok, mission_err = pcall(function()
                            return MISSION.newDestroy({
                                origin = cs,
                                wx = wx,
                                wy = wy,
                                tier = tier,
                                nearby_stations = nearby,
                                distance_u = dist,
                                danger_level = region.danger,
                                region_name = region.name,
                                distance_min_u = dist_min,
                                distance_max_u = dist_max,
                            })
                        end)
                        if mission_ok then
                            generated_mission = mission_err
                        else
                            print("[ERROR] Destroy mission generation failed: " .. tostring(mission_err))
                            error("Destroy: " .. tostring(mission_err))
                        end
                    end
                elseif mtype == "tailing" and RT.valid(station_e) then
                    local rx, ry = station_e:getPosition()
                    local wx, wy, dist, region = _spawnInVerse(rx, ry)
                    if not wx then
                        slots_failed = slots_failed + 1
                    else
                        local meet_ang  = math.random() * 2 * math.pi
                        local meet_dist = (20 + math.random() * 15) * 1000
                        local mx = math.floor(wx + math.cos(meet_ang) * meet_dist)
                        local my = math.floor(wy + math.sin(meet_ang) * meet_dist)
                        print(string.format("[TAILING] Station: %s | Target: (%d,%d) | Meet: (%d,%d) | Dist: %.1fU | Slot %d",
                            cs, wx, wy, mx, my, dist/1000, slot_num))
                        local mission_ok, mission_err = pcall(function()
                            return MISSION.newTailing({
                                origin = cs,
                                wx = wx, wy = wy,
                                mx = mx, my = my,
                                tier = tier,
                                distance_u = dist,
                                danger_level = region.danger,
                                region_name = region.name,
                                distance_min_u = dist_min,
                                distance_max_u = dist_max,
                            })
                        end)
                        if mission_ok then
                            generated_mission = mission_err
                        else
                            print("[ERROR] Tailing mission generation failed: " .. tostring(mission_err))
                            error("Tailing: " .. tostring(mission_err))
                        end
                    end
                elseif dest_idx <= #candidates then
                    -- fallback: delivery
                    generated_mission = MISSION.newDelivery({origin = cs, dest = candidates[dest_idx], tier = tier})
                    dest_idx = dest_idx + 1
                end

                -- Store mission in slot and add to offers
                if generated_mission then
                    if S.work_cooldown_enabled then
                        station_state.slots[slot_num].mission = generated_mission
                        station_state.slots[slot_num].offered_at = now
                        station_state.slots[slot_num].taken_at = nil
                    end
                    offers[#offers + 1] = generated_mission
                end
            end
        end

        if #offers == 0 then
            -- All slots on cooldown
            if S.work_cooldown_enabled then
                local min_remaining = math.huge
                for _, slot in pairs(station_state.slots) do
                    if slot.taken_at then
                        local remaining = JOBS.WORK_COOLDOWN - (now - slot.taken_at)
                        if remaining > 0 and remaining < min_remaining then
                            min_remaining = remaining
                        end
                    end
                end
                if min_remaining < math.huge then
                    local minutes = math.floor(min_remaining / 60)
                    local seconds = math.ceil(min_remaining % 60)
                    setCommsMessage(string.format('"No new contracts right now. Check back in %dm %ds."', minutes, seconds))
                else
                    setCommsMessage('"Nothing going out from here right now."')
                end
            else
                setCommsMessage('"Nothing going out from here right now."')
            end
            addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
            return
        end

        local lines = {"Work out of " .. cs .. ":\n"}
        for _, m in ipairs(offers) do
            lines[#lines + 1] = string.format("* %s", m.short)
        end
        if slots_failed > 0 then
            local noun = slots_failed == 1 and "contract was" or "contracts were"
            lines[#lines + 1] = string.format("\n(%d %s just picked up by another crew.)", slots_failed, noun)
        end
        setCommsMessage(table.concat(lines, "\n"))
        for _, m in ipairs(offers) do
            local cap = m
            addCommsReply(string.format("Take: %s", cap.short), function(s2, t2)
                if #_active >= 2 then
                    setCommsMessage('"You\'re already carrying two jobs. Finish one first."')
                else
                    JOBS.accept(cap, true)  -- skip_log=true, we'll write it after the message
                    setCommsMessage(cap.brief .. "\n\n\"Come back when it\'s done.\"\n\nTransmitting details to your log.")
                    -- Now write to log after showing the message
                    local dest_hint
                    if cap.type == "delivery" and cap.dest then
                        -- For delivery missions, include station name and grid
                        local dest_e = RT.find(cap.dest)
                        if RT.valid(dest_e) then
                            local dx, dy = dest_e:getPosition()
                            local grid = MISSION.gridRef(dx, dy)
                            dest_hint = cap.dest .. " (" .. grid .. ")"
                        else
                            dest_hint = cap.dest
                        end
                    else
                        -- For other mission types, use grid coordinates
                        dest_hint = cap.dest or (cap.wx and ("grid " .. MISSION.gridRef(cap.wx, cap.wy)) or "??")
                    end

                    if cap.type == "boarding" or cap.type == "destroy" then
                        local heading_text = cap.target_dest and (" heading toward " .. cap.target_dest) or ""
                        RT.shipLog(string.format("Contract: %s. %dm to complete. %s is at %s%s.",
                            cap.short, math.floor(JOBS.MISSION_DURATION / 60), cap.target_cs or "unknown", dest_hint, heading_text), "#60CCFF")
                    elseif cap.type == "hacking" then
                        RT.shipLog(string.format("Contract: %s. %dm to complete. Target: %s at %s.",
                            cap.short, math.floor(JOBS.MISSION_DURATION / 60), cap.target_cs or "unknown", dest_hint), "#60CCFF")
                    elseif cap.type == "tailing" then
                        local hdx = cap.mx - cap.wx
                        local hdy = cap.my - cap.wy
                        local heading_deg = math.floor((math.deg(math.atan(hdx, -hdy)) + 360) % 360 + 0.5)
                        RT.shipLog(string.format("Contract: %s. %dm to complete. Target last spotted at %s heading %03d. Approach with care.",
                            cap.short, math.floor(JOBS.MISSION_DURATION / 60), dest_hint, heading_deg), "#60CCFF")
                    else
                        RT.shipLog(string.format("Contract: %s. %dm to complete. Head to %s.",
                            cap.short, math.floor(JOBS.MISSION_DURATION / 60), dest_hint), "#60CCFF")
                    end
                end
                addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
            end)
        end
        addCommsReply("Nothing for me", function(s2, t2) RT.stationComms(s2, t2) end)
        end)  -- end pcall function

        if not ok then
            -- Error occurred - log detailed error
            print("[ERROR] Mission generation failed: " .. tostring(err))
            -- debug library not available in EE Lua, but err should contain the traceback
            setCommsMessage('"System error generating contracts. Please report to the dockmaster."')
            addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
        end
    end)
end

-- Send target and rendezvous to separate stations after the meeting (success or timeout)
local function _tailingDisperse(m)
    local available = {}
    for _, st in ipairs(VERSE.STATIONS) do
        if st.fac ~= "Corsairs" and st.fac ~= "Hollow" then
            available[#available + 1] = st.cs
        end
    end
    for i = #available, 2, -1 do
        local j = math.random(i); available[i], available[j] = available[j], available[i]
    end
    local tgt = RT.find(m.target_cs or "")
    if RT.valid(tgt) and #available >= 1 then
        local st = RT.find(available[1]); if RT.valid(st) then
            local sx, sy = st:getPosition(); tgt:setFaction("Independent"); tgt:orderFlyTowards(sx, sy)
        end
    end
    local rdv = RT.find(m.rendezvous_cs or "")
    if RT.valid(rdv) and #available >= 2 then
        local st = RT.find(available[2]); if RT.valid(st) then
            local sx, sy = st:getPosition(); rdv:orderFlyTowards(sx, sy)
        end
    end
end

-- Target detected the player or a probe — abort mission
local function _tailingSpook(m, reason)
    RT.shipLog("[Tailing] " .. reason .. " -- target spooked. Contract lost.", "#FF8080")
    _tailingDisperse(m)
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
            RT.shipLog("[Contract] " .. m.short .. " -- time expired. Contract lost.", "#FF8080")
            MISSION.untrack(m.id)
            table.remove(_active, i)
            JOBS.updateObj()
            goto next_entry
        end

        if m.type == "salvage" and not m._found then
            -- Check if cargo pod still exists (if destroyed before pickup)
            if m.cargo_obj and not RT.valid(m.cargo_obj) then
                RT.shipLog("[Salvage] Cargo destroyed -- contract lost.", "#FF8080")
                MISSION.untrack(m.id)
                table.remove(_active, i)
                JOBS.updateObj()
                goto next_entry
            end
            -- Pickup is handled by onPickUp callback on the SupplyDrop

        elseif m.type == "boarding" then
            -- Phase 1: watch for disable (impulse health < 0.3 or hull < 25%)
            -- (target already spawned in JOBS.accept)
            if not m._disabled then
                local target = RT.find(m.target_cs)
                if not RT.valid(target) then
                    -- Destroyed before boarding -- mission lost
                    RT.shipLog("[Boarding] Target destroyed before boarding -- contract lost.", "#FF8080")
                    MISSION.untrack(m.id)
                    table.remove(_active, i)
                    JOBS.updateObj()
                else
                    -- When player gets close, set to Corsairs faction and engage
                    if not m._attacking then
                        for _, p in ipairs(RT.players) do
                            if RT.valid(p) then
                                local dist = RT.dist(target, p)
                                if dist < 8000 then  -- 8U engagement range
                                    target:setFaction("Corsairs")  -- Now hostile to player
                                    target:orderAttack(p)
                                    m._attacking = true
                                    RT.shipLog("[Target] " .. m.target_cs .. " detected our approach and is engaging!", "#FF8080")
                                    break
                                end
                            end
                        end
                    end

                    local impulse_h = target:getSystemHealth("impulse") or 1
                    local hull_pct  = target:getHull() / target:getHullMax()
                    if impulse_h < 0.3 or hull_pct < 0.25 then
                        m._disabled = true
                        target:setCanBeDestroyed(false)
                        target:orderIdle()
                        target:setImpulseMaxSpeed(5)
                        target:setCommsFunction(function(src, tgt)
                            setCommsMessage('"We\'re done. Come aboard and take what you came for."')
                        end)
                        m.obj = "Board " .. m.target_cs
                        RT.shipLog("[Target] " .. m.target_cs .. " disabled. Move within 1U to board.", "#FFCC80")
                        JOBS.updateObj()
                    end
                end

            -- Phase 3: wait for player to get close (proximity boarding since docking doesn't work reliably)
            elseif not m._boarded then
                local target = RT.find(m.target_cs)
                if RT.valid(target) then
                    local tx, ty = target:getPosition()
                    for _, p in ipairs(RT.players) do
                        if RT.valid(p) then
                            local px, py = p:getPosition()
                            local dx, dy = px - tx, py - ty
                            local dist = math.sqrt(dx * dx + dy * dy)
                            if dist < 1000 then  -- 1U proximity boarding
                                m._boarded = true
                                m.obj = "Return " .. m.cargo .. " to " .. m.origin
                                RT.shipLog("[Boarding] " .. m.cargo .. " secured. Return to " .. m.origin .. ".", "#80FF80")
                                JOBS.updateObj()
                                break
                            end
                        end
                    end
                end
            end

        elseif m.type == "destroy" then
            -- Phase 1: watch for target destroyed
            if not m._destroyed then
                local target = RT.find(m.target_cs)
                if not RT.valid(target) then
                    -- Target destroyed!
                    m._destroyed = true
                    m.obj = "Return to " .. m.origin
                    RT.shipLog("[Target] " .. m.target_cs .. " destroyed. Return to " .. m.origin .. ".", "#80FF80")
                    JOBS.updateObj()
                else
                    -- When player gets close, set to Corsairs faction and engage
                    if not m._attacking then
                        for _, p in ipairs(RT.players) do
                            if RT.valid(p) then
                                local dist = RT.dist(target, p)
                                if dist < 8000 then  -- 8U engagement range
                                    target:setFaction("Corsairs")  -- Now hostile to player
                                    target:orderAttack(p)
                                    m._attacking = true
                                    RT.shipLog("[Target] " .. m.target_cs .. " detected our approach and is engaging!", "#FF8080")
                                    break
                                end
                            end
                        end
                    end
                end
            end

        elseif m.type == "hacking" then
            -- Phase 1: watch for hack completion (any system >= 75%)
            if not m._hacked then
                local target = RT.find(m.target_cs)
                if not RT.valid(target) then
                    RT.shipLog("[Hack] Relay destroyed before extraction -- contract lost.", "#FF8080")
                    MISSION.untrack(m.id)
                    table.remove(_active, i)
                    JOBS.updateObj()
                else
                    -- Relay jamming: check for probes every 2 seconds (performance throttle)
                    m._last_jam_check = m._last_jam_check or 0
                    if now - m._last_jam_check > 2 then
                        m._last_jam_check = now
                        local rx, ry = target:getPosition()
                        for _, obj in ipairs(getObjectsInRadius(rx, ry, 5000)) do
                            -- Don't destroy the relay itself!
                            if RT.valid(obj) and obj ~= target then
                                -- Test isObjectType from utils.lua
                                if isObjectType(obj, "ScanProbe") then
                                    obj:destroy()
                                    RT.shipLog("[Relay] Jamming field neutralised a probe.", "#FF8080")
                                end
                            end
                        end
                    end

                    -- Check all hackable systems (wrap in pcall since custom templates may not support hasSystem)
                    local systems = {"reactor", "beamweapons", "missilesystem", "maneuver", "impulse", "warp", "jumpdrive", "frontshield", "rearshield"}
                    local max_hack = 0
                    local hacked_system = nil
                    for _, sys in ipairs(systems) do
                        local has_system = false
                        local ok = pcall(function() has_system = target:hasSystem(sys) end)
                        if ok and has_system then
                            local hack_ok, hack_lvl = pcall(function() return target:getSystemHackedLevel(sys) end)
                            if hack_ok and hack_lvl and hack_lvl > max_hack then
                                max_hack = hack_lvl
                                hacked_system = sys
                            end
                        end
                    end

                    -- Complete when threshold reached on any system
                    if max_hack >= m.hack_threshold then
                        m._hacked = true
                        target:setCanBeDestroyed(true)
                        m.obj = "Return " .. m.cargo .. " to " .. m.origin
                        local sys_name = hacked_system or "system"
                        RT.shipLog("[Hack] " .. sys_name .. " breach successful! Data extracted from " .. m.target_cs
                            .. ". Return to " .. m.origin .. ".", "#80FF80")
                        JOBS.updateObj()
                    end
                end
            end
        elseif m.type == "tailing" then
            local tgt = RT.find(m.target_cs or "")
            local rdv = RT.find(m.rendezvous_cs or "")

            if not m._meeting then
                -- Target gone before meeting
                if not RT.valid(tgt) then
                    RT.shipLog("[Tailing] Target lost -- contract failed.", "#FF8080")
                    MISSION.untrack(m.id)
                    table.remove(_active, i)
                    JOBS.updateObj()
                    goto next_entry
                end

                -- Detection: player within 5u
                for _, p in ipairs(RT.players) do
                    if RT.valid(p) and RT.dist(p, tgt) < 5000 then
                        _tailingSpook(m, "Player within detection range")
                        MISSION.untrack(m.id)
                        table.remove(_active, i)
                        JOBS.updateObj()
                        goto next_entry
                    end
                end

                -- Detection: scan probe within 5u
                local tx, ty = tgt:getPosition()
                for _, obj in ipairs(getObjectsInRadius(tx, ty, 5000)) do
                    if RT.valid(obj) and isObjectType(obj, "ScanProbe") then
                        _tailingSpook(m, "Target detected a probe")
                        MISSION.untrack(m.id)
                        table.remove(_active, i)
                        JOBS.updateObj()
                        goto next_entry
                    end
                end

                -- Meeting: target and rendezvous within 1.5u
                if RT.valid(rdv) and RT.dist(tgt, rdv) < 1500 then
                    m._meeting    = true
                    m._meeting_at = now
                    tgt:orderIdle()
                    rdv:orderIdle()
                    local mx, my = tgt:getPosition()
                    RT.shipLog("[Tailing] Meeting in progress at " .. MISSION.gridRef(mx, my)
                        .. ". Science: scan both ships. 60 seconds.", "#FFCC80")
                    m.obj = "Scan both ships at meeting"
                    JOBS.updateObj()
                end

            elseif not m._scanned then
                -- 60-second scan window
                if now - m._meeting_at > 60 then
                    RT.shipLog("[Tailing] Meeting ended — not scanned in time. Contract lost.", "#FF8080")
                    _tailingDisperse(m)
                    MISSION.untrack(m.id)
                    table.remove(_active, i)
                    JOBS.updateObj()
                else
                    if RT.valid(tgt) and RT.valid(rdv) then
                        for _, p in ipairs(RT.players) do
                            if RT.valid(p) then
                                if not m._tgt_scanned then
                                    local ok, s = pcall(function() return tgt:isScannedBy(p) end)
                                    if ok and s then
                                        m._tgt_scanned = true
                                        RT.shipLog("[Tailing] " .. m.target_cs .. " identified. Scan the contact.", "#FFCC80")
                                    end
                                end
                                if not m._rdv_scanned then
                                    local ok, s = pcall(function() return rdv:isScannedBy(p) end)
                                    if ok and s then
                                        m._rdv_scanned = true
                                        RT.shipLog("[Tailing] Contact ship identified.", "#FFCC80")
                                    end
                                end
                                if m._tgt_scanned and m._rdv_scanned then
                                    m._scanned = true
                                    m.obj = "Return intel to " .. m.origin
                                    local cx, cy = tgt:getPosition()
                                    RT.shipLog("[Tailing] Both ships identified at " .. MISSION.gridRef(cx, cy)
                                        .. ". Return to " .. m.origin .. ".", "#80FF80")
                                    JOBS.updateObj()
                                    _tailingDisperse(m)
                                    break
                                end
                            end
                        end
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
-- THE WITNESS -- optional story arc (GM-triggered)
-- Phases: inactive → offer → transit → checkpoint → revealed →
--         shroud_run → halcyon → broadcast → done
-- S.witness_active blocks the job board for the duration.
--------------------------------------------------------------------------------

local W = {
    phase            = "inactive",
    phase_entered    = 0,
    panel_next       = 0,
    offer_hail_at    = nil,      -- delayed hail timer for offer phase
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
                RT.shipLog("[Stasis] CRITICAL -- pod failing. Engineering: emergency power now.", "#FF4040")
            elseif thr == 10 then
                RT.shipLog("[Science] Cardiac arrest imminent. We need everything Engineering can give.", "#FF4040")
            end
        end
    end

    if W.pod_stability <= 0 and W.kael_alive then
        W.kael_alive   = false
        W.pod_drain_on = false
        RT.shipLog("[Stasis] Kael Voss -- flatlined.", "#FF4040")
        RT.forEachPlayer(function(p)
            if RT.valid(p) then
                p:addCustomInfo("engineering", "w_pod_status", "Stasis pod: OFFLINE -- patient lost", 1)
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
                string.format("Stasis pod: %.0f%% -- %s", stab, status), 1)
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
                RT.shipLog(string.format("[Engineering] Emergency power on cooldown -- %.0fs remaining.", W.ep_next - now), "#FFAA00")
                return
            end
            W.ep_next       = now + 90
            W.pod_stability = math.min(100, W.pod_stability + 25)
            RT.shipLog(string.format("[Engineering] Emergency power rerouted -- pod stability +25 (now %.0f%%).", W.pod_stability), "#80FF80")
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
        msg    = "Broadcast sent. Kael Voss survived. His evidence is on every channel in the Drift -- they can't unring this bell."
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

    globalMessage("The Witness -- arc complete. " .. msg, 15)
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
    RT.shipLog("[Warning] Concord response inbound -- three ships. Hold them off while Relay completes the broadcast.", "#FF8080")
end

local function W_startHalcyon()
    W_enterPhase("halcyon")
    RT.setObjective("Dock at Halcyon Rest", true)

    -- Spawn the relay buoy near Halcyon Rest
    local hx, hy = VERSE.at("Halcyon Rest", 8, 6)
    local buoy = CpuShip():setTemplate("Flavia"):setFaction("Independent")
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
                setCommsMessage('"Sable checked out an hour ago. Left in a hurry -- Concord shuttle was asking after her."')
                addCommsReply("We know where to go.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    W_startBroadcast()
                end)
            else
                setCommsMessage('"She\'s here. Keeps looking at the docks."\n\nA message arrives from Sable: "Don\'t trust me. They have leverage. The broadcast still matters -- go to the relay buoy. Don\'t wait."')
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
    RT.shipLog("[Ambush] Corsairs -- " .. table.concat(W.corsair_names, ", ") .. ". Someone talked.", "#FF8080")
end

local function W_startShroudRun()
    W_enterPhase("shroud_run")
    RT.shipLog("[Navigation] Approaching the Shroud. Long-range sensors degrading. Watch for contacts.", "#C0C0C0")
    RT.setObjective("Reach Halcyon Rest", true)
end

local function W_startRevealed()
    W_enterPhase("revealed")
    if W.complied then
        RT.shipLog('[Message] A dead-drop transmission: "The data wasn\'t in the pod -- it\'s still with you, hidden in the lining. Get to Halcyon Rest. There\'s a public relay buoy. Finish this." -- unsigned.', "#A0C0FF")
    else
        RT.shipLog('[Stasis] Transmission from the pod: "My name is Kael Voss. I was a Concord logistics officer. What I know will end careers. Get me to Halcyon Rest -- there\'s a relay buoy there. One broadcast and it\'s over. Whatever she paid you, I\'ll double it."', "#A0C0FF")
    end
    RT.setObjective("Reach Halcyon Rest", true)
end

local function W_startCheckpoint()
    W_enterPhase("checkpoint")

    local ref = RT.nearestPlayer(0, 0)
    if not ref or not RT.valid(ref) then return end

    local px, py = ref:getPosition()
    local heading = ref:getHeading()

    -- Spawn 10U ahead of player along their heading
    local angle_rad = math.rad(heading - 90)  -- EE heading conversion
    local lead_dist = 10000  -- 10U ahead
    local cx = px + math.cos(angle_rad) * lead_dist
    local cy = py + math.sin(angle_rad) * lead_dist

    -- Create perpendicular line formation (5 ships across their path)
    local perp_rad = angle_rad + math.pi/2  -- 90 degrees to heading
    local spacing = 2500  -- 2.5U between ships

    local templates = {"MT52 Hornet", "MT52 Hornet", "MU52 Hornet", "MT52 Hornet", "MT52 Hornet"}
    for i = 1, 5 do
        local offset = (i - 3) * spacing  -- -2, -1, 0, 1, 2 positions
        local sx = cx + math.cos(perp_rad) * offset
        local sy = cy + math.sin(perp_rad) * offset

        local ship = CpuShip():setTemplate(templates[i]):setFaction("Concord")
        ship:setPosition(sx, sy):orderIdle():setCanBeDestroyed(true)
        RT.register(ship); DIR.registerKill(ship); DIR.allowControl(ship)
        W.concord_names[i] = ship:getCallSign()
    end

    -- Lead ship gets comms function
    local s1 = RT.find(W.concord_names[1])
    if not RT.valid(s1) then return end

    s1:setCommsFunction(function(src, tgt)
        setCommsMessage('"Independent vessel. Cut engines. You are carrying an unregistered stasis pod. Surrender it -- you will be free to go."')
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
            addCommsReply("Full burn -- break contact!", function(s_r2, t_r2)
                W.checkpoint_choice = "run"
                for _, n in ipairs(W.concord_names) do
                    local sc = RT.find(n)
                    if RT.valid(sc) and RT.valid(s_r) then sc:orderAttack(s_r) end
                end
            end)
        end)
        addCommsReply("We're not stopping for anyone.", function(s_r, t_r)
            W.checkpoint_choice = "run"
            setCommsMessage('"All units -- pursue."')
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

    RT.hail(s1, "Independent vessel. Cut engines. You are carrying an unregistered stasis pod. Concord inspection -- comply immediately.", "Concord Patrol")
    RT.shipLog("[Warning] Concord blockade on intercept -- five ships blocking our path.", "#FFAA00")
end

local function W_startOffer()
    S.witness_active = true
    W_enterPhase("offer")

    local vx, vy = VERSE.at("Port Vesper", -2, -1)
    local mira = CpuShip():setTemplate("Flavia"):setFaction("Independent")
    mira:setPosition(vx, vy)
    mira:orderIdle()
    mira:setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    mira:setWeaponTubeCount(0):setCanBeDestroyed(false)
    mira:setCallSign("Mira's Luck")
    RT.register(mira)

    mira:setCommsFunction(function(src, tgt)
        setCommsMessage('"I need a discreet crew -- no questions asked. Passenger in stasis who needs to reach Dustmote Salvage quietly. Concord would prefer he never arrive. 300 credits. Yes or no?"')
        addCommsReply("We'll take the job.", function(s2, t2)
            setCommsMessage('"Good. Transferring the pod now. He draws five energy a second from your reactor -- keep him stable. Get to Dustmote Salvage before Concord gets word."\n\nMira\'s Luck goes dark.')
            addCommsReply("Understood.", function(s3, t3) RT.stationComms(s3, t3) end)
            local m = RT.find("Mira's Luck")
            if RT.valid(m) then m:destroy() end
            W_enterPhase("transit")
            W.pod_drain_on = true
            W_addPodButtons()
            W_updatePanels()
            RT.shipLog("[Stasis] Pod aboard -- Kael Voss in stasis. Destination: Dustmote Salvage.", "#A0C0FF")
            RT.shipLog("[Engineering] Pod drawing 5 energy/sec. Keep energy above 50% to maintain stability.", "#FFAA00")
            RT.setObjective("Reach Dustmote Salvage", true)
        end)
        addCommsReply("Not our problem.", function(s2, t2)
            setCommsMessage('"Your call. He won\'t last long without power."')
            addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
        end)
    end)

    -- Delay hail by 3 seconds to avoid comms collision if player is in station dialog
    W.offer_hail_at = getScenarioTime() + 3
    globalMessage("Witness arc starting -- incoming hail in 3 seconds...", 3)
end

-- ── Main update dispatcher ───────────────────────────────────────────────────

local function W_update(delta)
    local now = getScenarioTime()

    -- Handle delayed hail in offer phase
    if W.phase == "offer" and W.offer_hail_at and now >= W.offer_hail_at then
        W.offer_hail_at = nil
        local mira = RT.find("Mira's Luck")
        if RT.valid(mira) then
            RT.hail(mira, "Independent vessel -- Mira Doss, Mira's Luck. I've got a private offer. Open comms when you're clear.", "Mira Doss")
        end
    end

    if W.phase == "inactive" or W.phase == "offer" or W.phase == "done" then return end

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
            -- Trigger checkpoint when 40U from Dustmote Salvage (104, -36)
            local dx, dy = px - 104000, py + 36000
            local dist_sq = dx * dx + dy * dy
            if not W.checkpoint_fired and dist_sq < 40000 * 40000 then
                W.checkpoint_fired = true
                W_startCheckpoint()
            end
        end

    elseif W.phase == "checkpoint" then
        if W.checkpoint_choice == "stall" and W.checkpoint_timer > 0 and now > W.checkpoint_timer then
            RT.shipLog("[Checkpoint] Time expired -- Concord boarded and took the pod.", "#FF8080")
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
            RT.shipLog("[Error] Relay buoy destroyed before broadcast -- arc failed.", "#FF8080")
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
    PROX.init()

    -- Spawn player at Port Vesper (safe starting location)
    local px, py = VERSE.at("Port Vesper", 1.5, 1.5)
    RT.spawnPlayer(px, py, 0)

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
            table.insert(lines, string.format("Credits: %d\n", RT.campaign.credits))

            table.insert(lines, "REPUTATION:")
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
    local function showReputationFactionList()
        clearGMFunctions()
        addGMFunction("< Back to Main", function()
            clearGMFunctions()
            addSessionGMFunctions()
        end)

        local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic"}
        for _, faction in ipairs(factions) do
            addGMFunction(faction .. "...", function()
                clearGMFunctions()
                addGMFunction("< Back to Factions", showReputationFactionList)

                local current = RT.getReputation(faction) or 0
                addGMFunction(string.format("Current: %+d", current), function()
                    addGMMessage(string.format("%s reputation: %+d", faction, RT.getReputation(faction) or 0))
                end)

                addGMFunction(faction .. " +50", function()
                    RT.adjustReputation(faction, 50)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s +50 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " +10", function()
                    RT.adjustReputation(faction, 10)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s +10 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " +1", function()
                    RT.adjustReputation(faction, 1)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s +1 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " -1", function()
                    RT.adjustReputation(faction, -1)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s -1 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " -10", function()
                    RT.adjustReputation(faction, -10)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s -10 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " -50", function()
                    RT.adjustReputation(faction, -50)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s -50 (now %+d)", faction, RT.getReputation(faction)))
                end)
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

    addGMFunction("Credits +10", function()
        if RT.valid(RT.player) then
            RT.addCredits(10, "GM reward")
        end
    end)

    addGMFunction("Credits -10", function()
        if RT.valid(RT.player) then
            RT.addCredits(-10, "GM penalty")
        end
    end)

    addGMFunction("Work Cooldown: " .. (S.work_cooldown_enabled and "ON" or "OFF"), function()
        S.work_cooldown_enabled = not S.work_cooldown_enabled
        -- Clear the function and re-add with new label
        clearGMFunctions()
        addSessionGMFunctions()
        local mode = S.work_cooldown_enabled and "ENABLED" or "DISABLED"
        addGMMessage("Work cooldown " .. mode .. ".\n\n" ..
            (S.work_cooldown_enabled and "Taking a mission triggers a 10 minute new job cooldown." or
            "Stations offer unlimited missions (testing mode)."))
    end)

    local distance_labels = {short = "SHORT", medium = "MEDIUM", long = "LONG"}
    addGMFunction("Job Distance: " .. (distance_labels[S.mission_distance_mode] or "MEDIUM"), function()
        -- Cycle: short -> medium -> long -> short
        if S.mission_distance_mode == "short" then
            S.mission_distance_mode = "medium"
        elseif S.mission_distance_mode == "medium" then
            S.mission_distance_mode = "long"
        else
            S.mission_distance_mode = "short"
        end
        -- Clear and re-add with new label
        clearGMFunctions()
        addSessionGMFunctions()
        local ranges = {short = "15-50U", medium = "60-200U", long = "120-400U"}
        addGMMessage("Job distance set to " .. distance_labels[S.mission_distance_mode] .. ".\n\n" ..
            "New missions will spawn at " .. ranges[S.mission_distance_mode] .. " from origin station.")
    end)

    addGMFunction("Witness: Start", function()
        if W.phase ~= "inactive" then
            local msg = "Witness arc already at phase: " .. W.phase
            globalMessage(msg, 5)
            addGMMessage(msg)
            return
        end
        W_startOffer()
    end)

    addGMFunction("Witness: >Chkpt", function()
        S.witness_active   = true
        W.pod_drain_on     = true
        W.checkpoint_fired = true
        W_addPodButtons()
        W_updatePanels()
        RT.shipLog("[Stasis] Pod aboard -- Kael Voss in stasis. (GM skip)", "#A0C0FF")
        W_startCheckpoint()
    end)

    addGMFunction("Witness: >Bcast", function()
        S.witness_active   = true
        W.pod_drain_on     = true
        W.checkpoint_fired = true
        W_addPodButtons()
        W_updatePanels()
        RT.shipLog("[Stasis] Pod aboard -- Kael Voss in stasis. (GM skip)", "#A0C0FF")
        W_startHalcyon()
        W_startBroadcast()
    end)

    addGMFunction("Witness: Pod>Crit", function()
        if W.pod_drain_on then
            W.pod_stability = 15
            RT.shipLog("[GM] Stasis pod forced to critical stability.", "#FF4040")
        end
    end)

    addGMFunction("Witness: Cancel", function()
        if W.phase == "inactive" then return end
        local m = RT.find("Mira's Luck")
        if RT.valid(m) then m:destroy() end
        W.phase            = "inactive"
        W.offer_hail_at    = nil
        W.pod_drain_on     = false
        W.checkpoint_fired = false
        W.corsair_names    = {}
        W.concord_names    = {}
        S.witness_active   = false
        W_removePodUI()
        globalMessage("Witness arc cancelled and reset.", 5)
        addGMMessage("Witness arc cancelled. Phase reset to inactive.")
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
    RT.updateKillTracking()  -- Track ship kills for reputation
    VERSE.update(delta)
    DIR.update(delta)
    if not S.witness_active then PROX.update(delta) end

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

end
