-- ee/ragtag/world/defenders.lua
-- Station Defenders: one light fighter per Independent / Concord station,
-- loitering on orderDefendTarget. Respawns after death. When hailed,
-- explains their posting and (if the "defender_cmds_<faction>" flag is set)
-- accepts orders from the player.
--
-- Concord port guards: a player ship with Concord standing below -200 (the patrols' detention
-- line) that comes within 5U of a Concord defender is attacked by it ("Concord Hostile", attacking
-- that ship only). It stands down when the ship is beyond 10U of the port, is lost, or its
-- standing recovers. The lane pickets do the same within 10U of any of their ships, chasing to 20U
-- from their post, then resume their beat. Tuning: hostile_below, guard_radar_u, guard_leash_u,
-- picket_radar_u, picket_leash_u.
--
-- Lane pickets: the universe's garrisons with a beat (VERSE.PICKETS, from beat_u in the verse
-- data: the Concord pickets, not tied to a port) walk a slow square round their post, holding
-- each corner for a while before moving on. The lead flies (orderFlyTowards: it still engages
-- enemies on the way); the rest of the group keeps formation on it. Plugin off: back to holding
-- the post.
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
    picket_dwell_secs  = 45,        -- how long a picket holds each corner of its beat
    picket_arrive_u    = 600,       -- meters: this close to a corner counts as there
    -- Concord port guards and wanted ships: a player ship whose Concord standing is below
    -- hostile_below (the patrols' "detention" line) and comes within guard_radar_u of a Concord
    -- defender is attacked by it ("Concord Hostile", orderAttack on that ship only). It gives up
    -- and goes back to its post when the ship is beyond guard_leash_u of the port, is lost, or its
    -- standing recovers.
    hostile_below   = -200,
    guard_radar_u   = 5000,         -- meters: how far a guard notices a wanted ship
    guard_leash_u   = 10000,        -- meters from its port: how far it chases
    -- Lane pickets do the same with a longer reach: they notice a wanted ship within picket_radar_u
    -- of any ship in the group, chase it to picket_leash_u from their post, then resume their beat.
    picket_radar_u  = 10000,
    picket_leash_u  = 20000,
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

-- source: the hailing player ship; defender: the defender entity itself (never looked up by name).
local function _defenderComms(source, defender, station_cs, fac, slot)
    local fac_slug = fac == "Concord" and "concord" or "independent"
    local can_cmd  = RT.flag("defender_cmds_" .. fac_slug)
    local ship_name = defender:getCallSign()
    local station  = RT.find(station_cs)   -- a universe place, found by name

    if slot and slot.hostile_to then
        setCommsMessage('"' .. ship_name .. '. Your vessel is wanted by the Concord. Power down and prepare to be boarded."')
        return
    end

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
            if RT.valid(defender) and RT.valid(source) then
                defender:orderDefendTarget(source)   -- the ship that asked
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

    local cap_cs, cap_fac, slot = cs, fac, state.slots[cs]
    ship:setCommsFunction(function(src, tgt)
        _defenderComms(src, tgt, cap_cs, cap_fac, slot)
    end)

    slot.ship      = ship   -- the entity: the slot never looks its ship up by name
    slot.ship_name = name
    slot.respawn_at = nil
    slot.hostile_to = nil
end

-- ── Concord guards and wanted ships ─────────────────────────────────────────

local function _wanted(p)
    return (RT.getReputation("Concord", p) or 0) < WORLD.get("defenders", "hostile_below", -200)
end

-- Back to its post: Concord again, defending its port.
local function _standDown(slot, cs)
    slot.hostile_to = nil
    if not RT.valid(slot.ship) then return end
    slot.ship:setFaction("Concord")
    local station = RT.find(cs)
    if RT.valid(station) then slot.ship:orderDefendTarget(station) else slot.ship:orderIdle() end
end

-- Each Concord guard: engage the nearest wanted player ship within its radar; give up when the
-- ship leaves the leash round the port, is lost, or is no longer wanted.
local function _tickGuards(state)
    local radar = WORLD.get("defenders", "guard_radar_u", 5000)
    local leash = WORLD.get("defenders", "guard_leash_u", 10000)
    for cs, slot in pairs(state.slots) do
        if slot.fac == "Concord" and RT.valid(slot.ship) then
            local g = slot.ship
            if slot.hostile_to then
                local p = slot.hostile_to
                local station = RT.find(cs)
                if not RT.valid(p) or not _wanted(p)
                   or (RT.valid(station) and RT.dist(p, station) > leash) then
                    _standDown(slot, cs)
                end
            end
            if not slot.hostile_to then
                local best, best_d
                RT.forEachPlayer(function(p)
                    if _wanted(p) then
                        local d = RT.dist(p, g)
                        if d <= radar and (not best_d or d < best_d) then best, best_d = p, d end
                    end
                end)
                if best then
                    slot.hostile_to = best
                    g:setFaction("Concord Hostile")
                    g:orderAttack(best)
                    best:addToShipLog(string.format(
                        "[Concord] %s: %s, you are wanted by the Concord. Power down and prepare to be boarded.",
                        g:getCallSign(), best:getCallSign()), "#FF4444")
                end
            end
        end
    end
end

-- ── Lane pickets ─────────────────────────────────────────────────────────────

-- Corner k (1-4) of a picket's beat: a square round its post, starting at its own angle.
local function _corner(p, k)
    local a = p.angle + (k - 1) * math.pi / 2
    return p.x + math.cos(a) * p.r, p.y + math.sin(a) * p.r
end

-- Send the group to its current corner: the lead flies there, the rest keep formation behind
-- it, 700 m apart.
local function _walk(p)
    local lead, n = nil, 0
    for _, s in ipairs(p.ships) do
        if RT.valid(s) then
            if not lead then
                lead = s
                lead:orderFlyTowards(_corner(p, p.k))
            else
                n = n + 1
                s:orderFlyFormation(lead, -700 * n, 0)
            end
        end
    end
    p.lead = lead
end

local function _initPickets(state)
    state.pickets = {}
    for _, g in ipairs(VERSE.PICKETS or {}) do
        state.pickets[#state.pickets + 1] = {ships = g.ships, x = g.x, y = g.y, r = g.r,
            angle = math.random() * 2 * math.pi, k = 1, holding_until = nil}
    end
end

local function _tickPickets(state, now)
    local dwell  = WORLD.get("defenders", "picket_dwell_secs", 45)
    local arrive = WORLD.get("defenders", "picket_arrive_u", 600)
    for _, p in ipairs(state.pickets or {}) do
        local lead
        for _, s in ipairs(p.ships) do if RT.valid(s) then lead = s; break end end
        if lead and not p.hostile_to then
            if p.holding_until then
                if now >= p.holding_until then            -- move on to the next corner
                    p.holding_until = nil
                    p.k = p.k % 4 + 1
                    _walk(p)
                end
            elseif lead ~= p.lead then                    -- first tick, or the lead was lost
                _walk(p)
            else
                local lx, ly = lead:getPosition()
                local cx, cy = _corner(p, p.k)
                if math.sqrt((lx - cx) ^ 2 + (ly - cy) ^ 2) < arrive then
                    p.holding_until = now + dwell          -- hold the corner a while
                    lead:orderDefendLocation(cx, cy)
                end
            end
        end
    end
end

-- A picket group turns on the nearest wanted ship within picket_radar_u of any of its ships, and
-- goes back to its beat when the ship is beyond picket_leash_u of its post, is lost, or is no
-- longer wanted.
local function _tickPicketGuards(state)
    local radar = WORLD.get("defenders", "picket_radar_u", 10000)
    local leash = WORLD.get("defenders", "picket_leash_u", 20000)
    for _, p in ipairs(state.pickets or {}) do
        local alive = {}
        for _, s in ipairs(p.ships) do if RT.valid(s) then alive[#alive + 1] = s end end
        if p.hostile_to then
            local t = p.hostile_to
            local tx, ty
            if RT.valid(t) then tx, ty = t:getPosition() end
            if #alive == 0 or not RT.valid(t) or not _wanted(t)
               or math.sqrt((tx - p.x) ^ 2 + (ty - p.y) ^ 2) > leash then
                p.hostile_to = nil
                for _, s in ipairs(alive) do s:setFaction("Concord") end
                p.lead, p.holding_until = nil, nil      -- the beat picks up from its corner
            end
        end
        if not p.hostile_to and #alive > 0 then
            local best, best_d
            RT.forEachPlayer(function(pl)
                if _wanted(pl) then
                    for _, s in ipairs(alive) do
                        local d = RT.dist(pl, s)
                        if d <= radar and (not best_d or d < best_d) then best, best_d = pl, d end
                    end
                end
            end)
            if best then
                p.hostile_to = best
                for _, s in ipairs(alive) do
                    s:setFaction("Concord Hostile")
                    s:orderAttack(best)
                end
                best:addToShipLog(string.format(
                    "[Concord] %s: %s, you are wanted by the Concord. Power down and prepare to be boarded.",
                    alive[1]:getCallSign(), best:getCallSign()), "#FF4444")
            end
        end
    end
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

    _initPickets(state)

    for _, d in ipairs(VERSE.STATIONS) do
        if target_facs[d.fac] then
            state.slots[d.cs] = {
                fac        = d.fac,
                ship       = nil,
                ship_name  = nil,
                respawn_at = 0,   -- 0 = spawn immediately on first check
            }
        end
    end
end

function _P.update(state, delta, now)
    local respawn_secs = WORLD.get("defenders", "respawn_secs", 120)
    _tickPickets(state, now)
    if now >= (state.next_guard or 0) then
        state.next_guard = now + 1
        _tickGuards(state)
        _tickPicketGuards(state)
    end

    for cs, slot in pairs(state.slots) do
        if slot.ship then
            -- Check if current defender is still alive.
            if not RT.valid(slot.ship) then
                state.used_names[slot.ship_name] = nil
                slot.ship      = nil
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
        if RT.valid(slot.ship) then slot.ship:destroy() end
        slot.ship = nil
    end
    -- Pickets stay in the universe: back to holding their post.
    for _, p in ipairs(state.pickets or {}) do
        for _, s in ipairs(p.ships) do
            if RT.valid(s) then
                if p.hostile_to then s:setFaction("Concord") end
                s:orderDefendLocation(p.x, p.y)
            end
        end
        p.lead, p.hostile_to = nil, nil
    end
end

-- ── Register ─────────────────────────────────────────────────────────────────

WORLD.register(_P)
