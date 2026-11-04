-- ee/ragtag/world/traffic.lua
-- Freighter traffic and ambient crate drops.
--
-- Spawns initial freighter routes on first tick, then drives the ship AI and
-- ambient pod lifecycle. Density setting reconciles immediately: a change kills
-- all live ships and respawns at the new count.
--
-- Settings:
--   density  1=Low (~half), 2=Medium (baseline), 3=High (~double)

local _P = {}
_P.id              = "traffic"
_P.name            = "Station Traffic"
_P.default_enabled = true
_P.defaults = {
    density = 2,  -- 1=Low, 2=Medium, 3=High
}

-- ─── Constants ────────────────────────────────────────────────────────────────

local _DENSITY_NAMES = {"Low", "Medium", "High"}
local _DENSITY_MULT  = {0.5, 1.0, 2.0}

local _TYPES = {"Personnel", "Goods", "Garbage", "Equipment", "Fuel"}

local _CARGO = {
    Personnel = "passengers and their worldly goods",
    Goods     = "trade goods",
    Garbage   = "scrap metal for the smelters",
    Equipment = "machine parts and tools",
    Fuel      = "fuel cells",
}

local _YARDS = {
    "Rim Works Collective, Ashgrave",
    "Vesper Industrial, Port Vesper",
    "Concord Ordnance Yards, Lumen",
    "Cinder Fields Fabricators",
    "Kestrel Ironworks",
    "Greywater Shipwrights",
    "Calloway & Sons, Kestrel",
    "Ironhold Assembly, Cardinal",
    "Pale Star Works",
    "Settlement Procurement, decommissioned",
}

local _CAPTAINS = {
    {name="Mira Valos",    bio="Former Concord transport pilot. Grounded after Ashgrave — her version of events differs from the record."},
    {name="Dex Hollowell", bio="Third-generation hauler out of the Cinder Fields. Hasn't set foot on a Core world in eleven years and intends to keep it that way."},
    {name="Sable Orrin",   bio="Ran with Corsairs out of Blackwater until the raid on Vesper Station. That was fourteen years ago. Some debts stay paid."},
    {name="Rook Farren",   bio="Ex-Concord quartermaster. Knows every customs trick in the book because he wrote half of them."},
    {name="Tess Malvoy",   bio="Grew up on one of these ships. Inherited it and the debt that came with it. Still paying off both."},
    {name="Calder Prin",   bio="Worked the Maw routes for six years. Retired to the Rim voluntarily. Won't say why."},
    {name="Wren Ashby",    bio="Settlement War veteran, Independent faction. Took the amnesty, bought the ship. Doesn't talk about the war."},
    {name="Orin Slack",    bio="Claims to have never missed a delivery. Most of the stations that could dispute it are no longer standing."},
    {name="Pell Davan",    bio="Came out of the Core with forged credentials and a ship that technically belonged to someone else. That was twenty years ago. Statute of limitations, probably."},
    {name="Saray Cohm",    bio="Inherited a freight contract and a failing ship from a business partner. The contract expired. The ship didn't."},
    {name="Bram Esten",    bio="Flew Concord patrol ships for twelve years. Took early retirement after the Greywater Incident. The Concord calls it a commendation. He calls it a buyout."},
    {name="Vael Drax",     bio="No flight record before fifteen years ago. Pays in cash. Always on time."},
    {name="Corra Nine",    bio="Self-taught pilot out of the Rim. Never held a license the Concord would recognize, but the cargo always arrives."},
    {name="Henley Cass",   bio="Runs the same three-station loop he's run for twenty years. Knows every dock worker by name. Has no ambitions he'll admit to."},
    {name="Zura Falke",    bio="Former science officer, Concord Survey Corps. Left after the Pale Sun expedition. Delivers freight now. Doesn't discuss the expedition."},
}

-- ─── Internal helpers ─────────────────────────────────────────────────────────

local function _stationByName(cs)
    local info = RT.stations[cs]
    if info and RT.valid(info.entity) then return info.entity end
    return RT.find(cs)
end

local function _pickDestination(route, current, rng)
    for _ = 1, 10 do
        local cs = rng.pick(route.stations)
        local st = _stationByName(cs)
        if RT.valid(st) and st ~= current then return st end
    end
    return nil
end

local function _transportComms(source, target, rec)
    local dest = (rec.dest and RT.valid(rec.dest)) and rec.dest:getCallSign() or "wherever pays"
    if rec.route.fac == "Concord" then
        setCommsMessage("\"Concord transport " .. target:getCallSign() .. ". We're on a scheduled run. Please maintain separation.\"")
    else
        setCommsMessage("\"" .. target:getCallSign() .. " here. Go ahead, neighbour.\"")
    end
    addCommsReply("Where are you headed?", function(s, t)
        setCommsMessage(string.format("\"Bound for %s with a hold full of %s.\"", dest, _CARGO[rec.kind]))
        addCommsReply("Back", function(s2, t2) _transportComms(s2, t2, rec) end)
    end)
    addCommsReply("Heard any news?", function(s, t)
        local rumor_text = (RUMORS and RUMORS.get and RUMORS.get(s:getCallSign(), t:getFaction()))
            or "Not much worth repeating, friend."
        setCommsMessage("\"" .. rumor_text .. "\"")
        if DIR and DIR.online then
            DIR.emit("npc_hailed", {callsign = t:getCallSign(), faction = t:getFaction(), topic = "news",
                role = "freighter crew", cargo = rec.kind, heading_to = dest}, "normal")
        end
        addCommsReply("Back", function(s2, t2) _transportComms(s2, t2, rec) end)
    end)
    if rec.route.fac ~= "Concord" and rec.kind == "Fuel" then
        addCommsReply("Sell us some fuel? (recharge energy, 30 cr)", function(s, t)
            if RT.credits(s) < 30 then
                setCommsMessage("\"Cash first, friend.\"")
            elseif RT.dist(s, t) > 5000 then
                setCommsMessage("\"Come alongside first. Within five units.\"")
            else
                RT.addCredits(-30, "fuel from " .. t:getCallSign(), s)
                s:setEnergy(s:getMaxEnergy())
                setCommsMessage("\"Pleasure doing business.\"")
            end
        end)
    elseif rec.route.fac ~= "Concord" and rec.kind == "Equipment" then
        addCommsReply("Got any ordnance to spare? (2 homing, 40 cr)", function(s, t)
            if RT.credits(s) < 40 then
                setCommsMessage("\"Cash first, friend.\"")
            elseif RT.dist(s, t) > 5000 then
                setCommsMessage("\"Come alongside first. Within five units.\"")
            elseif s:getWeaponStorage("Homing") >= s:getWeaponStorageMax("Homing") then
                setCommsMessage("\"Your racks are full already.\"")
            else
                RT.addCredits(-40, "ordnance from " .. t:getCallSign(), s)
                s:setWeaponStorage("Homing", math.min(s:getWeaponStorageMax("Homing"), s:getWeaponStorage("Homing") + 2))
                setCommsMessage("\"Two birds, loaded. Don't tell anyone where you got them.\"")
            end
        end)
    end
end

local function _spawnTransport(route, rng, near_station)
    local kind = rng.pick(_TYPES)
    local size = rng.int(1, 5)
    -- Jump freighters hover instead of jumping on long AI dock orders, so all
    -- traffic uses plain freighters with warp drives.
    local tmpl = string.format("%s Freighter %d", kind, size)
    local origin = near_station or _stationByName(rng.pick(route.stations))
    if not RT.valid(origin) then return nil end
    local ox, oy = origin:getPosition()
    -- Spawn on the side of the origin facing the destination. Ships spawned
    -- behind a station try to fly through it and get stuck on its hull.
    local dest = _pickDestination(route, origin, rng)
    local bearing = rng.float(0, 360)
    if dest then
        local tx, ty = dest:getPosition()
        bearing = angleHeading(ox, oy, tx, ty) + rng.float(-25, 25)
    end
    local dx, dy = vectorFromAngle(bearing, rng.float(2500, 4000), true)
    local s = CpuShip():setTemplate(tmpl):setFaction(route.fac):setPosition(ox + dx, oy + dy)
    s:setHeading(bearing)
    -- Pick a name not already in use.
    local name = nil
    for _ = 1, 12 do
        local n = rng.pick(route.names)
        if RT.find(n) == nil then name = n; break end
    end
    if name then s:setCallSign(name) end
    -- Freighter impulse is ~0.05u/s, far too slow for a map this size, so every
    -- freighter gets a modest warp drive (the AI uses it on long legs).
    s:setWarpDrive(true)
    s:setWarpSpeed(rng.float(250, 400))
    local yard = rng.pick(_YARDS)
    local age  = rng.int(8, 45)
    local cap  = rng.pick(_CAPTAINS)
    local scan2 = string.format("Currently hauling %s. Captain %s — %s", _CARGO[kind], cap.name, cap.bio)
    if #scan2 > 200 then scan2 = string.sub(scan2, 1, 197) .. "..." end
    s:setDescriptions(
        string.format("%s. %s, %d years in service.", tmpl, yard, age),
        scan2
    )
    local rec = {ship = s, route = route, kind = kind, dest = nil, docked_since = nil,
                 linger = rng.float(20, 60), last_order = getScenarioTime(), name = s:getCallSign()}
    rec.dest = dest
    if rec.dest then s:orderDock(rec.dest) end
    s:setCommsFunction(function(source, target) _transportComms(source, target, rec) end)
    s:onDestruction(function(ship, instigator)
        local x, y = ship:getPosition()
        if DIR then
            DIR.emit("transport_destroyed", {callsign = rec.name, route = route.id,
                by = (instigator and instigator:isValid()) and instigator:getFaction() or "unknown",
                region = VERSE.regionAt(x, y).name}, "normal")
        end
    end)
    RT.register(s)
    table.insert(VERSE.transports, rec)
    return rec
end

local function _updateTransports(now)
    for i = #VERSE.transports, 1, -1 do
        local rec = VERSE.transports[i]
        local s = rec.ship
        if not RT.valid(s) then
            table.remove(VERSE.transports, i)
            table.insert(VERSE.respawn_queue, {route = rec.route, at = now + VERSE.rng_live.float(150, 300)})
        else
            local docked = s:getDockedWith()
            if docked then
                rec.stall_t = nil
                rec.docked_since = rec.docked_since or now
                if now - rec.docked_since > rec.linger then
                    rec.dest = _pickDestination(rec.route, docked, VERSE.rng_live)
                    if rec.dest then s:orderDock(rec.dest) end
                    rec.docked_since = nil
                    rec.linger = VERSE.rng_live.float(20, 60)
                    rec.last_order = now
                end
            else
                rec.docked_since = nil
                local x, y = s:getPosition()
                -- Resume docking after a sidestep.
                if rec.resume_at and now >= rec.resume_at then
                    rec.resume_at = nil
                    if RT.valid(rec.dest) then s:orderDock(rec.dest) end
                end
                -- Stall watchdog: ships can get stuck on planets or deadlock with each other.
                -- Track position and give progressively more aggressive fixes.
                if rec.stall_t == nil then
                    rec.stall_t, rec.stall_x, rec.stall_y = now, x, y
                    rec.stall_count = 0
                elseif now - rec.stall_t >= 60 then
                    local moved = math.sqrt((x - rec.stall_x) ^ 2 + (y - rec.stall_y) ^ 2)
                    if moved < 1500 and rec.resume_at == nil then
                        rec.stall_count = (rec.stall_count or 0) + 1
                        if rec.stall_count >= 3 then
                            -- Stuck for 3+ minutes: destroy and respawn elsewhere
                            table.remove(VERSE.transports, i)
                            table.insert(VERSE.respawn_queue, {route = rec.route, at = now + VERSE.rng_live.float(30, 90)})
                            s:destroy()
                        elseif rec.stall_count == 2 then
                            -- Stuck for 2 minutes: teleport to destination's vicinity if far from player
                            if rec.dest and RT.valid(rec.dest) and (not RT.valid(RT.player) or RT.dist(s, RT.player) > 15000) then
                                local tx, ty = rec.dest:getPosition()
                                local angle = VERSE.rng_live.float(0, 360)
                                local dx, dy = vectorFromAngle(angle, VERSE.rng_live.float(8000, 12000), true)
                                s:setPosition(tx + dx, ty + dy)
                                s:setHeading(angle)
                                s:orderDock(rec.dest)
                                rec.last_order = now
                            else
                                -- Player watching or no dest: try larger sidestep
                                local dx, dy = vectorFromAngle(s:getHeading() + 90, 5000, true)
                                s:setPosition(x + dx, y + dy)
                            end
                        else
                            -- First stall (1 minute): small nudge
                            local dx, dy = vectorFromAngle(s:getHeading() + 90, 1500, true)
                            if not RT.valid(RT.player) or RT.dist(s, RT.player) > 12000 then
                                s:setPosition(x + dx, y + dy)
                            else
                                s:orderFlyTowardsBlind(x + dx * 2, y + dy * 2)
                                rec.resume_at = now + 15
                            end
                        end
                    else
                        -- Ship is moving, reset stall counter
                        rec.stall_count = 0
                    end
                    rec.stall_t, rec.stall_x, rec.stall_y = now, x, y
                end
                -- Lost its destination, or wandering far too long: re-route.
                if not RT.valid(rec.dest) or now - rec.last_order > 1200 then
                    rec.dest = _pickDestination(rec.route, nil, VERSE.rng_live)
                    if rec.dest then s:orderDock(rec.dest) end
                    rec.last_order = now
                end
            end
        end
    end
    for i = #VERSE.respawn_queue, 1, -1 do
        local q = VERSE.respawn_queue[i]
        if now >= q.at then
            local st = _stationByName(VERSE.rng_live.pick(q.route.stations))
            -- Don't pop a ship into existence right next to the crew.
            if RT.valid(st) and (not RT.valid(RT.player) or RT.dist(st, RT.player) > 10000) then
                table.remove(VERSE.respawn_queue, i)
                _spawnTransport(q.route, VERSE.rng_live, st)
            else
                q.at = now + 30
            end
        end
    end
end


local function _routeCount(route, density_idx)
    return math.max(1, math.floor(route.count * _DENSITY_MULT[density_idx] + 0.5))
end

local function _spawnAll(density_idx)
    local rng = VERSE.rng_live
    for _, route in ipairs(VERSE.ROUTES) do
        local count = _routeCount(route, density_idx)
        for _ = 1, count do _spawnTransport(route, rng) end
    end
end

local function _killAll()
    for _, rec in ipairs(VERSE.transports) do
        if RT.valid(rec.ship) then
            pcall(function() rec.ship:destroy() end)
        end
    end
    VERSE.transports    = {}
    VERSE.respawn_queue = {}
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

function _P.init(state)
    state.density_idx = WORLD.get("traffic", "density", 2)
    state.next_check  = 0

    _spawnAll(state.density_idx)

    print(string.format("[Traffic] Spawned %d routes (density=%s).",
        #VERSE.ROUTES, _DENSITY_NAMES[state.density_idx]))
end

function _P.update(state, delta, now)
    local density_idx = WORLD.get("traffic", "density", 2)

    if density_idx ~= state.density_idx then
        _killAll()
        state.density_idx = density_idx
        _spawnAll(density_idx)
        print(string.format("[Traffic] Density changed to %s; traffic respawned.", _DENSITY_NAMES[density_idx]))
    end

    if now >= state.next_check then
        state.next_check = now + 2
        _updateTransports(now)
    end
end

function _P.cleanup(state)
    _killAll()
end

WORLD.register(_P)

-- ─── GM menu ──────────────────────────────────────────────────────────────────

function _P.gmMenu(addButton, showSelf)
    local on = WORLD.isEnabled("traffic")
    addButton(_P.name .. ": " .. (on and "ON" or "OFF"), function()
        if on then WORLD.disable("traffic") else WORLD.enable("traffic") end
        showSelf()
    end)
    local cur_d = TRAFF.getDensity()
    for i, name in ipairs(TRAFF.DENSITY_NAMES) do
        local cap_i = i
        addButton("Density: " .. name .. (i == cur_d and " [*]" or ""), function()
            TRAFF.setDensity(cap_i)
            showSelf()
        end)
    end
end

-- ─── TRAFF shims (for GM menu and scenario scripts) ──────────────────────────

TRAFF = TRAFF or {}
TRAFF.DENSITY_NAMES = _DENSITY_NAMES

function TRAFF.getDensity()    return WORLD.get("traffic", "density", 2)                        end
function TRAFF.setDensity(idx) WORLD.set("traffic", "density", math.max(1, math.min(3, idx))) end
