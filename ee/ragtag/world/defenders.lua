-- ee/ragtag/world/defenders.lua
-- Station Defenders: one light fighter per Independent / Concord station,
-- loitering on orderDefendTarget. Respawns after death. When hailed,
-- explains their posting and (if the "defender_cmds_<faction>" flag is set)
-- accepts orders from the player.
--
-- Player-command flags:
--   RT.flag("defender_cmds_independent", true)  -- enables orders for Indie defenders
--   RT.flag("defender_cmds_concord",     true)  -- enables orders for Concord defenders

local _P = {}
_P.id   = "defenders"
_P.name = "Station Defenders"

_P.defaults = {
    template        = "MT52 Hornet",
    respawn_secs    = 120,          -- cooldown after death before respawn
    orbit_range_ku  = 3,            -- kU: spawn/orbit distance from station (3-5)
    order_radius_u  = 20000,        -- meters: search radius when ordered to attack
    factions        = {"Concord", "Independent"},
}

-- ── Name pools ──────────────────────────────────────────────────────────────

-- Independent defenders: scrappy, frontier-flavored personal callsigns.
local _IND_NAMES = {
    "Dusthawk", "Freehold", "Grey Sovereign", "Vagrant Star", "Rust Knife",
    "Thin Ice",  "Pale Dog", "Loose Change",  "Hollow Point", "Ember Cross",
    "Driftwood", "Ragged Wing", "Stone Cold", "Last Round",   "Bare Knuckle",
    "Salt Flat", "Blind Eye",  "Half Credit", "Crosswind",    "Bone Dry",
    "Running Tab", "Split Second", "Long Shot", "Dead Weight","Silver Tongue",
    "Bad Penny", "Far Cry",    "Rough Trade", "Dry Dock",     "Sunburn",
    "Ironweed",  "Cinder Walk", "Odd Job",    "Slow Burn",    "Stray Volt",
}

-- Concord defenders: orderly, patrol-designation callsigns.
local _CCD_NAMES = {
    "CPV Longwatch", "CPV Vigil",    "CPV Steadfast",  "CPV Ironclad",   "CPV Constant",
    "CPV Sure Hand", "CPV Clear Sky","CPV Bright Sword","CPV High Ground","CPV Watch Fire",
    "CPV Even Keel", "CPV True Course","CPV Standing Order","CPV Lawkeeper","CPV Still Water",
    "CPV Safeguard", "CPV First Light","CPV Surefire",  "CPV Rampart",    "CPV Outpost",
}

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function _pickName(pool, used)
    local avail = {}
    for _, n in ipairs(pool) do
        if not used[n] then avail[#avail + 1] = n end
    end
    if #avail == 0 then return pool[math.random(#pool)] end
    return avail[math.random(#avail)]
end

local function _nearestEnemy(ship, radius)
    if not RT.valid(ship) then return nil end
    local sx, sy = ship:getPosition()
    for _, obj in ipairs(getObjectsInRadius(sx, sy, radius)) do
        if RT.valid(obj) and obj ~= ship then
            local ok1, is_enemy = pcall(function() return ship:isEnemy(obj) end)
            if ok1 and is_enemy then
                local ok2, is_ship = pcall(function()
                    return isObjectType(obj, "CpuShip") or isObjectType(obj, "PlayerSpaceship")
                end)
                if ok2 and is_ship then return obj end
            end
        end
    end
    return nil
end

local function _defenderComms(ship_name, station_cs, fac)
    local fac_slug = fac == "Concord" and "concord" or "independent"
    local can_cmd  = RT.flag("defender_cmds_" .. fac_slug)
    local defender = RT.find(ship_name)
    local station  = RT.find(station_cs)

    if fac == "Concord" then
        setCommsMessage('"' .. ship_name .. ', patrol assignment ' ..
            station_cs .. '. You are being logged. State your business."')
    else
        setCommsMessage('"' .. ship_name .. ', on post at ' ..
            station_cs .. '. Station keeps me fed; I keep trouble off their hull. What do you need?"')
    end

    -- Player-order options: gated by flag, available for future mission arcs.
    if can_cmd then
        addCommsReply("We need backup -- attack the nearest hostile.", function(s2, t2)
            local target = RT.valid(defender) and
                _nearestEnemy(defender, WORLD.get("defenders", "order_radius_u", 20000)) or nil
            if target and RT.valid(defender) then
                defender:orderAttack(target)
                setCommsMessage('"Copy. Engaging."')
            else
                setCommsMessage('"No valid targets in range. Holding post."')
            end
            addCommsReply("Understood.", function(s3, t3) setCommsMessage('"' .. ship_name .. ' out."') end)
        end)

        addCommsReply("Defend our ship.", function(s2, t2)
            if RT.valid(defender) then
                -- Use first player as the defend target (comms_source should be player).
                RT.forEachPlayer(function(p)
                    if RT.valid(p) then defender:orderDefendTarget(p) end
                end)
                setCommsMessage('"On your wing."')
            else
                setCommsMessage('"Copy."')
            end
            addCommsReply("Good.", function(s3, t3) setCommsMessage('"' .. ship_name .. ' out."') end)
        end)

        addCommsReply("Return to your station.", function(s2, t2)
            if RT.valid(defender) and RT.valid(station) then
                defender:orderDefendTarget(station)
                setCommsMessage('"Returning to post."')
            else
                setCommsMessage('"Copy."')
            end
            addCommsReply("Good.", function(s3, t3) setCommsMessage('"' .. ship_name .. ' out."') end)
        end)
    end

    if fac == "Concord" then
        addCommsReply("Just passing through.", function(s2, t2)
            setCommsMessage('"Logged. Proceed."')
            addCommsReply("Out.", function(s3, t3) setCommsMessage('"' .. ship_name .. ' out."') end)
        end)
    else
        addCommsReply("Just checking in.", function(s2, t2)
            setCommsMessage('"Keep your transponder live and you\'ll have no trouble from me."')
            addCommsReply("Out.", function(s3, t3) setCommsMessage('"' .. ship_name .. ' out."') end)
        end)
    end
end

local function _spawnDefender(state, cs, fac)
    local pool  = fac == "Concord" and _CCD_NAMES or _IND_NAMES
    local name  = _pickName(pool, state.used_names)
    state.used_names[name] = true

    local r_ku  = WORLD.get("defenders", "orbit_range_ku", 3)
    local ang   = math.random() * 2 * math.pi
    local d_ku  = r_ku + math.random() * 2   -- 3-5 kU
    local wx, wy = VERSE.at(cs, math.cos(ang) * d_ku, math.sin(ang) * d_ku)

    local ship  = CpuShip():setTemplate(WORLD.get("defenders", "template", "MT52 Hornet"))
    ship:setFaction(fac):setCallSign(name):setPosition(wx, wy)
    ship:setCanBeDestroyed(true)
    RT.register(ship)

    local station = RT.find(cs)
    if RT.valid(station) then
        ship:orderDefendTarget(station)
    else
        ship:orderIdle()
    end

    -- Capture locals for the comms closure.
    local cap_name = name
    local cap_cs   = cs
    local cap_fac  = fac
    ship:setCommsFunction(function(src, tgt)
        _defenderComms(cap_name, cap_cs, cap_fac)
    end)

    state.slots[cs].ship_cs   = name
    state.slots[cs].ship_name = name
    state.slots[cs].respawn_at = nil
end

-- ── Plugin interface ─────────────────────────────────────────────────────────

function _P.gmMenu(addButton, showSelf)
    local on = WORLD.isEnabled("defenders")
    addButton(_P.name .. ": " .. (on and "ON" or "OFF"), function()
        if on then WORLD.disable("defenders") else WORLD.enable("defenders") end
        showSelf()
    end)
end

function _P.init(state)
    state.slots      = {}
    state.used_names = {}

    -- Build one slot per Concord/Independent station.
    local target_facs = {}
    for _, f in ipairs(WORLD.get("defenders", "factions", {"Concord","Independent"})) do
        target_facs[f] = true
    end

    for _, d in ipairs(VERSE.STATIONS) do
        if target_facs[d.fac] then
            state.slots[d.cs] = {
                fac        = d.fac,
                ship_cs    = nil,
                ship_name  = nil,
                respawn_at = 0,   -- 0 = spawn immediately on first check
            }
        end
    end
end

function _P.update(state, delta, now)
    local respawn_secs = WORLD.get("defenders", "respawn_secs", 120)

    for cs, slot in pairs(state.slots) do
        if slot.ship_cs then
            -- Check if current defender is still alive.
            if not RT.valid(RT.find(slot.ship_cs)) then
                state.used_names[slot.ship_name] = nil
                slot.ship_cs   = nil
                slot.ship_name = nil
                slot.respawn_at = now + respawn_secs
            end
        elseif (slot.respawn_at or 0) <= now then
            -- Spawn a new defender for this station.
            local ok, err = pcall(_spawnDefender, state, cs, slot.fac)
            if not ok then
                log("[WORLD/defenders] spawn error at " .. cs .. ": " .. tostring(err))
                slot.respawn_at = now + 30  -- back-off
            end
        end
    end
end

function _P.cleanup(state)
    -- Destroy all active defenders on disable.
    for cs, slot in pairs(state.slots or {}) do
        if slot.ship_cs then
            local s = RT.find(slot.ship_cs)
            if RT.valid(s) then s:destroy() end
        end
    end
end

-- ── Register ─────────────────────────────────────────────────────────────────

WORLD.register(_P)
