-- ee/ragtag/jobs/escort.lua
-- Escort an impulse-only convoy ship from origin to a destination station.
-- Two Independent escort fighters spawn at origin and stand by for player orders.
-- Two Corsair intercept waves spawn at 1/3 and 2/3 of the route.

local M = {}
M.type      = "escort"
M.weight    = 3
M.tier_min  = 0
M.type_mult = 1.5

local U = 1000  -- world units per universe unit

-- Callsign pool for independent escort fighters.
local _ESCORT_NAMES = {
    "Jackdaw",    "Kestrel",    "Merlin",     "Hobby",      "Shrike",
    "Harrier",    "Skua",       "Fulmar",     "Tern",       "Martin",
    "Whimbrel",   "Dunlin",     "Sanderling", "Turnstone",  "Razorbill",
    "Low Rider",  "Flat Spin",  "Slip Draft", "Dead Air",   "Quick Burn",
    "Knife Edge", "Short Hop",  "Belly Down", "Wide Open",  "Hard Bank",
    "Mudlark",    "Guillemot",  "Puffin",     "Curlew",     "Redshank",
}

-- Post-completion departure tracking; processed by _tickDeparting each JOBS cycle.
local _departing = {}  -- list of {ships={cs,...}, despawn_at=t}

local function _tickDeparting(now)
    local i = #_departing
    while i >= 1 do
        local d = _departing[i]
        if now > d.despawn_at then
            for _, cs in ipairs(d.ships) do
                local s = RT.find(cs)
                if RT.valid(s) then s:destroy() end
            end
            table.remove(_departing, i)
        end
        i = i - 1
    end
end

-- ---------------------------------------------------------------------------
-- Archetypes
-- ---------------------------------------------------------------------------

local _ARCHETYPES = {
    -- Any faction
    {cargo="an escort receipt", short_offer="Escort a medical supply run",
     lore="A freighter loaded with vaccines and surgical equipment needs to reach its destination. No weapons aboard.",
     accept_msg='"Get our ship there in one piece. Whatever it takes."',
     recv_msg='"Supplies delivered. The station owes you."',
     reward_mult=1.0, tier_min=0},
    {cargo="a transit certificate", short_offer="Escort a refugee evacuation ship",
     lore="A converted transport is carrying displaced families out of a hot zone. One damaged engine, no defenses.",
     accept_msg='"They\'ve been through enough. Don\'t let the Corsairs add to it."',
     recv_msg='"Everyone made it. That\'s the only thing that matters."',
     reward_mult=1.1, tier_min=0},
    {cargo="a fuel delivery receipt", short_offer="Escort a fuel tanker",
     lore="A full tanker runs slow and burns bright on any sensor. The destination station is running critical reserves.",
     accept_msg='"She\'s a fat target. Keep the wolves off her."',
     recv_msg='"Fuel delivered. Half the station was on backup power. You have no idea."',
     reward_mult=1.0, tier_min=0},
    {cargo="a cargo security receipt", short_offer="Escort a salvage haul",
     lore="A salvage crew recovered something worth fighting over. Their ship can\'t outrun a determined raider.",
     accept_msg='"We just need to get home. Stay close."',
     recv_msg='"Made it. The find pays for three months. And for you."',
     reward_mult=1.1, tier_min=0},
    {cargo="a passenger transit cert", short_offer="Escort a passenger liner",
     lore="A civilian liner is running a route through increasingly dangerous space. The operators are cutting corners on security.",
     accept_msg='"Three hundred souls. Don\'t let the numbers make it abstract."',
     recv_msg='"Passengers disembarked safely. Liner operator sends his thanks."',
     reward_mult=1.0, tier_min=0},
    {cargo="an equipment delivery cert", short_offer="Escort industrial equipment",
     lore="Heavy station-building equipment in a slow, ungainly transport. Raiders have hit this route twice this month.",
     accept_msg='"The equipment arrives, or three stations don\'t get built. Simple as that."',
     recv_msg='"Equipment received. Construction resumes."',
     reward_mult=1.0, tier_min=0},
    {cargo="a food aid receipt", short_offer="Escort a food aid run",
     lore="A station running short-ration protocols is waiting on this delivery. The crew is independent aid workers.",
     accept_msg='"They\'re not soldiers. Keep them safe."',
     recv_msg='"Delivery complete. Three thousand people eat today because of this."',
     reward_mult=1.1, tier_min=0},
    {cargo="a survey team transit cert", short_offer="Escort a returning survey team",
     lore="A research team returning from a deep survey carries data worth more than the ship. They\'ve been gone eight months.",
     accept_msg='"They found something. I don\'t know what. Neither do the people shooting at them."',
     recv_msg='"Team recovered safely. Survey data intact. You\'ll read about it eventually."',
     reward_mult=1.2, tier_min=1},
    -- Independent stations only
    {cargo="an off-manifest transit cert", short_offer="Escort an off-manifest run",
     lore="The cargo doesn\'t appear on the official manifest. The people who want it know that.",
     accept_msg='"No questions about the cargo. Your job is the ship."',
     recv_msg='"Delivered clean. Payment in full."',
     reward_mult=1.2, tier_min=0, fac="Independent"},
    {cargo="a specialist transit cert", short_offer="Escort a grey-market specialist",
     lore="A technical specialist moving their expertise from one operation to another. Several parties would prefer they didn\'t arrive.",
     accept_msg='"The specialist has enemies. So does everyone useful."',
     recv_msg='"Specialist delivered. Their work continues."',
     reward_mult=1.3, tier_min=1, fac="Independent"},
    {cargo="a defector transit cert", short_offer="Escort a Corsair defector",
     lore="A Corsair operative wants out. The people they\'re leaving behind want to make an example.",
     accept_msg='"They know the routes, the signals, the timing. The Corsairs will throw everything at this."',
     recv_msg='"Defector delivered. What they know will make a difference."',
     reward_mult=1.4, tier_min=1, fac="Independent"},
    {cargo="an ore shipment receipt", short_offer="Escort an independent ore haul",
     lore="An independent miner hit a rich vein and now has a full hold and no friends. Word gets around.",
     accept_msg='"Three years of prospecting in that hold. I\'m not losing it now."',
     recv_msg='"Ore delivered. The miner kept their claim. This time."',
     reward_mult=1.1, tier_min=0, fac="Independent"},
    {cargo="a construction contract receipt", short_offer="Escort a station builder",
     lore="A small construction company is moving fabrication equipment to a new contract site. Competitors play rough.",
     accept_msg='"It\'s not politics, it\'s just business. Expensive business."',
     recv_msg='"Equipment delivered. Contract begins on schedule."',
     reward_mult=1.0, tier_min=0, fac="Independent"},
    {cargo="a trade goods receipt", short_offer="Escort a travelling merchant",
     lore="A travelling merchant dealing in rare goods that don\'t appear on the usual market lists. The route is exposed.",
     accept_msg='"The goods are legitimate. The route is not. Your job is the ship."',
     recv_msg='"Merchant arrived. Business concluded. Payment transferred."',
     reward_mult=1.2, tier_min=1, fac="Independent"},
    -- Concord stations only
    {cargo="an evidence transport cert", short_offer="Escort an evidence transport",
     lore="Physical evidence for an ongoing tribunal is being moved under seal. Several parties have reason to stop it.",
     accept_msg='"The evidence reaches the tribunal intact, or three cases collapse. Understood?"',
     recv_msg='"Evidence received by tribunal custody. Chain intact."',
     reward_mult=1.3, tier_min=1, fac="Concord"},
    {cargo="a prisoner transfer cert", short_offer="Escort a prisoner transfer",
     lore="A high-value prisoner in a lightly armed transport. Their associates know the route.",
     accept_msg='"Alive and in custody. Non-negotiable on both counts."',
     recv_msg='"Prisoner transferred to custody. Booking underway."',
     reward_mult=1.3, tier_min=1, fac="Concord"},
    {cargo="a diplomatic transit cert", short_offer="Escort a diplomatic courier",
     lore="An official courier carrying sealed correspondence between Concord authorities. The seals matter.",
     accept_msg='"The courier and the documents arrive intact. That\'s the entire contract."',
     recv_msg='"Courier delivered. Correspondence sealed and intact. Well done."',
     reward_mult=1.2, tier_min=0, fac="Concord"},
    {cargo="a medical requisition cert", short_offer="Escort a Concord medical requisition",
     lore="A Concord medical requisition shipment headed for a forward station. Marked as routine; isn\'t.",
     accept_msg='"The manifest says standard supplies. It doesn\'t say what for."',
     recv_msg='"Requisition received. Thank you for not asking questions."',
     reward_mult=1.1, tier_min=0, fac="Concord"},
    {cargo="a fleet supply receipt", short_offer="Escort Concord fleet support",
     lore="Fleet support equipment for a patrol station running low on critical spares. Losing the shipment grounds two patrol ships.",
     accept_msg='"Two patrol ships stand down if this doesn\'t arrive. The implications are significant."',
     recv_msg='"Fleet supply received. Patrols resume on schedule."',
     reward_mult=1.2, tier_min=1, fac="Concord"},
    {cargo="a sealed courier receipt", short_offer="Escort a classified Concord courier",
     lore="A sealed courier with classified orders in a ship that doesn\'t look official. That\'s the point.",
     accept_msg='"You don\'t know what\'s in the packet. You don\'t need to. Get the ship there."',
     recv_msg='"Courier delivered. Orders received. Classification maintained."',
     reward_mult=1.4, tier_min=2, fac="Concord"},
}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function _dismissFighters(m)
    if m._fighters_dismissed then return end
    m._fighters_dismissed = true
    local fighter_list = m.fighter_cs or {}
    if #fighter_list == 0 then return end
    local candidates = {}
    for cs, _ in pairs(VERSE.STATIONS or {}) do
        if cs ~= m.origin and cs ~= m.dest then candidates[#candidates + 1] = cs end
    end
    local tx, ty
    if #candidates > 0 then
        local dep_e = RT.find(candidates[math.random(#candidates)])
        if RT.valid(dep_e) then tx, ty = dep_e:getPosition() end
    end
    if not tx then tx = m.dx + (m.dx - m.ox); ty = m.dy + (m.dy - m.oy) end
    local dep_ships = {}
    for _, cs in ipairs(fighter_list) do
        local s = RT.find(cs)
        if RT.valid(s) then
            s:orderFlyTowardsBlind(tx, ty)
            s:setCommsFunction(function(src, tgt)
                setCommsMessage('"Good flying, Captain. We\'ve got our own heading now."')
            end)
            dep_ships[#dep_ships + 1] = cs
        end
    end
    if #dep_ships > 0 then
        _departing[#_departing + 1] = {ships = dep_ships, despawn_at = getScenarioTime() + 300}
    end
end

local function _spawnInterceptors(m, cx, cy)
    local to_dest = math.atan(m.dy - cy, m.dx - cx)
    for _ = 1, 3 do
        local angle = to_dest + math.rad(math.random() * 90 - 45)
        local ex = cx + math.cos(angle) * 10 * U + (math.random() - 0.5) * 500
        local ey = cy + math.sin(angle) * 10 * U + (math.random() - 0.5) * 500
        local s = CpuShip():setTemplate("MT52 Hornet"):setFaction("Corsairs")
        local cs = JOBS.corsairName()
        s:setCallSign(cs)
        s:setPosition(ex, ey)
        s:setImpulseMaxSpeed(200, 60)
        s:setWarpSpeed(0)
        local convoy_target = RT.find(m.convoy_cs)
        if RT.valid(convoy_target) then
            s:orderAttack(convoy_target)
        else
            s:orderRoaming()
        end
        RT.register(s)
        DIR.registerKill(s)
        DIR.allowControl(s)
        m._interceptors[#m._interceptors + 1] = {
            cs = cs, sx = ex, sy = ey,
            init_hull    = s:getHullMax(),
            init_shields = s:getShieldMax(0),
            switched     = false,
        }
    end
end

-- ---------------------------------------------------------------------------
-- Module interface
-- ---------------------------------------------------------------------------

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local dest_cs = ctx.nextCandidate()
    if not dest_cs then return nil end
    local dest_e = ctx.findStation(dest_cs)
    if not ctx.valid(dest_e) then return nil end
    local ox, oy = ctx.station_e:getPosition()
    local dx, dy = dest_e:getPosition()
    local ddx, ddy = dx - ox, dy - oy
    local region = VERSE.regionAt(dx, dy)
    return {
        origin         = ctx.station_cs,
        origin_faction = MISSION.stationFaction(ctx.station_cs),
        dest           = dest_cs,
        tier           = ctx.tier,
        ox = ox, oy = oy,
        dx = dx, dy = dy,
        distance_u     = math.sqrt(ddx*ddx + ddy*ddy),
        danger_level   = region and region.danger or 0,
        region_name    = region and region.name or nil,
        distance_min_u = ctx.distanceRange.min,
        distance_max_u = ctx.distanceRange.max,
    }
end

function M.generate(opts)
    local tier = opts.tier or 0
    local sfac = opts.origin_faction
    local pool = {}
    for _, a in ipairs(_ARCHETYPES) do
        if (a.tier_min or 0) <= tier and (not a.fac or not sfac or a.fac == sfac) then
            pool[#pool + 1] = a
        end
    end
    if #pool == 0 then
        for _, a in ipairs(_ARCHETYPES) do
            if (a.tier_min or 0) <= tier and not a.fac then pool[#pool + 1] = a end
        end
    end
    if #pool == 0 then pool = _ARCHETYPES end
    local arch = pool[math.random(#pool)]
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["escort"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)
    return {
        id             = MISSION.nextId(),
        type           = "escort",
        tier           = tier,
        origin         = opts.origin,
        dest           = opts.dest,
        ox = opts.ox, oy = opts.oy,
        dx = opts.dx, dy = opts.dy,
        cargo          = arch.cargo,
        reward         = reward,
        short          = arch.short_offer,
        obj            = "Escort convoy to " .. opts.dest .. " (" .. MISSION.gridRef(opts.dx, opts.dy) .. ")",
        brief          = arch.lore .. "\n\nDestination: " .. opts.dest .. " (" .. MISSION.gridRef(opts.dx, opts.dy) .. ")\n\n" .. arch.accept_msg .. "\n\nUndock when you're ready to begin.",
        complete_msg   = arch.recv_msg,
        distance_u     = opts.distance_u or 0,
        region_name    = opts.region_name,
        _spawned        = false,
        _convoy_waiting = true,
        _convoy_docking = false,
        _convoy_arrived = false,
        _arrived_at     = nil,
        _convoy_lost    = false,
        _ambush1        = false,
        _ambush2        = false,
        _interceptors       = {},
        _fighters_dismissed = false,
        convoy_cs       = nil,
        fighter_cs      = {},
    }
end

function M.duration(m)
    -- Convoy travels at impulse (~125 u/s) + 15 min buffer for two intercept fights.
    return math.floor((m.distance_u or 60000) / 125 + 900)
end

function M.offerText(m, stats)
    return string.format("* Escort convoy to %s.\n  %s", m.dest, stats)
end

function M.spawn(m)
    if m._spawned then return end
    local origin_e = RT.find(m.origin)
    local dest_e   = RT.find(m.dest)
    if not RT.valid(origin_e) or not RT.valid(dest_e) then return end

    -- Re-fetch positions at spawn time for accuracy.
    local ox, oy = origin_e:getPosition()
    local dx, dy = dest_e:getPosition()
    m.ox, m.oy = ox, oy
    m.dx, m.dy = dx, dy

    -- Convoy ship: impulse-only (~1/4 warp), no weapons, shields.
    -- Spawns near the origin dock and idles there; orderDock is avoided because
    -- issuing orderFlyTowards to a docked ship in EE ECS is unreliable.
    local convoy_name = JOBS.freighterName()
    local convoy = CpuShip():setTemplate("Flavia"):setFaction("Independent")
    convoy:setCallSign(convoy_name)
    local dock_angle = math.random() * 2 * math.pi
    convoy:setPosition(ox + math.cos(dock_angle) * 800, oy + math.sin(dock_angle) * 800)
    convoy:setImpulseMaxSpeed(125, 40)
    convoy:setWarpSpeed(0)
    local sf = convoy:getShieldMax(0)
    local sr = convoy:getShieldMax(1)
    if sf > 0 then convoy:setShields(sf, sr) end
    convoy:orderIdle()
    RT.register(convoy)
    DIR.registerKill(convoy)
    local mission_ref = m
    convoy:setCommsFunction(function(src, tgt)
        print(string.format("[ESCORT-DIAG] convoy comms opened: waiting=%s", tostring(mission_ref._convoy_waiting)))
        if mission_ref._convoy_waiting then
            setCommsMessage('"Standing by at the dock. Ready to depart on your mark."')
        else
            setCommsMessage('"We\'re underway to ' .. mission_ref.dest .. '. Thank you for the escort."')
        end
    end)
    m.convoy_cs = convoy_name
    print(string.format("[ESCORT-DIAG] spawn complete: convoy=%s pos=(%.0f,%.0f) dx=%.0f dy=%.0f spawned=%s",
        convoy_name, ox + math.cos(dock_angle) * 800, oy + math.sin(dock_angle) * 800,
        m.dx, m.dy, tostring(m._spawned)))

    -- Two escort fighters: impulse-only (~1/3 warp), standing by at origin.
    -- Pick two distinct names from the pool.
    local name_pool = {}
    for _, n in ipairs(_ESCORT_NAMES) do name_pool[#name_pool + 1] = n end
    local function _pickEscortName()
        local idx = math.random(#name_pool)
        local n = name_pool[idx]
        table.remove(name_pool, idx)
        return n
    end

    local fighters = {}
    for i = 1, 2 do
        local angle = (i - 1) * math.pi + math.random() * 0.4 - 0.2
        local fx = ox + math.cos(angle) * 3 * U
        local fy = oy + math.sin(angle) * 3 * U
        local f = CpuShip():setTemplate("MT52 Hornet"):setFaction("Independent")
        local fname = _pickEscortName()
        f:setCallSign(fname)
        f:setPosition(fx, fy)
        f:setImpulseMaxSpeed(200, 60)
        f:setWarpSpeed(0)
        f:orderDefendTarget(convoy)
        RT.register(f)
        DIR.registerKill(f)
        DIR.allowControl(f)
        local cname = convoy_name
        f:setCommsFunction(function(src, tgt)
            setCommsMessage('"Standing by, Captain. Your orders?"')
            addCommsReply("Defend " .. cname, function(s2, t2)
                local cv = RT.find(cname)
                if RT.valid(cv) then
                    tgt:orderDefendTarget(cv)
                    setCommsMessage('"Copy. Protecting ' .. cname .. '."')
                else
                    setCommsMessage('"Unable to locate convoy."')
                end
            end)
            addCommsReply("Weapons free — engage threats", function(s2, t2)
                tgt:orderRoaming()
                setCommsMessage('"Copy. Weapons free."')
            end)
            addCommsReply("Form up on convoy", function(s2, t2)
                local cv2 = RT.find(cname)
                if RT.valid(cv2) then
                    tgt:orderDefendTarget(cv2)
                    setCommsMessage('"Copy. Forming up."')
                else
                    setCommsMessage('"Unable to locate convoy."')
                end
            end)
        end)
        fighters[i] = fname
    end
    m.fighter_cs = fighters
    m._spawned   = true
end

function M.acceptLog(m)
    local f1 = (m.fighter_cs and m.fighter_cs[1]) or "Escort-1"
    local f2 = (m.fighter_cs and m.fighter_cs[2]) or "Escort-2"
    return string.format(
        "[Escort] %s is standing by at %s dock. Destination: %s (%s). You command the escort fleet — %s and %s are standing by. Undock when ready to begin.",
        m.convoy_cs or "Convoy", m.origin, m.dest, MISSION.gridRef(m.dx, m.dy), f1, f2)
end

function M.update(m, entry, ctx)
    if not m._spawned or m._convoy_lost then return nil end

    local convoy = RT.find(m.convoy_cs)

    if not RT.valid(convoy) then
        m._convoy_lost = true
        RT.shipLog("[Escort] " .. (m.convoy_cs or "convoy") .. " has been destroyed. Contract failed.", "#FF4444")
        m.obj = "Mission failed — convoy lost"
        JOBS.updateObj()
        m._expires_at = ctx.now - 1
        return nil
    end

    -- Wait at origin until the player undocks, then release the convoy.
    if m._convoy_waiting then
        local origin_e = RT.find(m.origin)
        local origin_valid = RT.valid(origin_e)
        local player_count = 0
        local player_left = true
        RT.forEachPlayer(function(p)
            player_count = player_count + 1
            local docked = p:getDockedWith()
            local docked_cs = (docked and docked ~= false and RT.valid(docked)) and docked:getCallSign() or "nil"
            print(string.format("[ESCORT-DIAG] player %d: getDockedWith=%s origin_valid=%s origin=%s",
                player_count, tostring(docked_cs), tostring(origin_valid), tostring(m.origin)))
            if docked and origin_valid and docked == origin_e then
                player_left = false
            end
        end)
        -- Throttle: print waiting status every ~10s
        if not m._diag_next or ctx.now >= m._diag_next then
            m._diag_next = ctx.now + 10
            print(string.format("[ESCORT-DIAG] waiting: players=%d player_left=%s convoy_cs=%s dx=%.0f dy=%.0f",
                player_count, tostring(player_left), tostring(m.convoy_cs), m.dx or -1, m.dy or -1))
        end
        if player_left then
            m._convoy_waiting = false
            print(string.format("[ESCORT-DIAG] releasing convoy %s -> orderFlyTowards(%.0f, %.0f)",
                m.convoy_cs, m.dx, m.dy))
            convoy:orderFlyTowards(m.dx, m.dy)
            RT.shipLog("[Escort] " .. m.convoy_cs .. " is underway. Escort them to " .. m.dest .. ".", "#60CCFF")
        end
        return nil
    end

    -- Switch interceptors to roaming (fight back) once they take any damage.
    for _, interc in ipairs(m._interceptors) do
        if not interc.switched then
            local s = RT.find(interc.cs)
            if RT.valid(s) then
                local hit = s:getHull() < interc.init_hull
                    or (interc.init_shields > 0 and s:getShieldLevel(0) < interc.init_shields)
                if hit then
                    s:orderRoaming()
                    interc.switched = true
                end
            end
        end
    end

    local cx, cy = convoy:getPosition()

    if not m._convoy_arrived then
        local dest_e = RT.find(m.dest)
        if RT.valid(dest_e) then
            local dex, dey = dest_e:getPosition()
            local cdist = math.sqrt((cx - dex)^2 + (cy - dey)^2)
            if not m._convoy_docking and cdist < 5 * U then
                convoy:orderDock(dest_e)
                m._convoy_docking = true
            end
            local docked = convoy:getDockedWith()
            if docked and docked == dest_e then
                m._convoy_arrived = true
                m._arrived_at = ctx.now
                for _, interc in ipairs(m._interceptors) do
                    local s = RT.find(interc.cs)
                    if RT.valid(s) then s:orderFlyTowardsBlind(interc.sx, interc.sy) end
                end
                _dismissFighters(m)
                RT.shipLog("[Escort] " .. m.convoy_cs .. " has docked at " .. m.dest .. ". Dock to collect payment.", "#80FF80")
                m.obj = "Dock at " .. m.dest .. " to collect payment"
                JOBS.updateObj()
            end
        end
    end

    -- Despawn recalled interceptors 2 minutes after convoy docks.
    if m._arrived_at and ctx.now > m._arrived_at + 120 and #m._interceptors > 0 then
        for _, interc in ipairs(m._interceptors) do
            local s = RT.find(interc.cs)
            if RT.valid(s) then s:destroy() end
        end
        m._interceptors = {}
    end

    if not m._ambush1 or not m._ambush2 then
        local vdx = m.dx - m.ox
        local vdy = m.dy - m.oy
        local tsq = vdx * vdx + vdy * vdy
        if tsq > 0 then
            local prog = ((cx - m.ox) * vdx + (cy - m.oy) * vdy) / tsq
            if not m._ambush1 and prog >= 0.33 then
                _spawnInterceptors(m, cx, cy)
                m._ambush1 = true
                RT.shipLog("[Escort] Corsair intercept at " .. MISSION.gridRef(cx, cy) .. "!", "#FF8080")
                DIR.emit("escort_ambush", {wave=1, convoy=m.convoy_cs}, "normal")
            elseif m._ambush1 and not m._ambush2 and prog >= 0.67 then
                _spawnInterceptors(m, cx, cy)
                m._ambush2 = true
                RT.shipLog("[Escort] Second intercept wave inbound!", "#FF8080")
                DIR.emit("escort_ambush", {wave=2, convoy=m.convoy_cs}, "normal")
            end
        end
    end

    return nil
end

function M.expire(m)
    if m._convoy_lost then
        if m.origin_faction then
            RT.addReputation(m.origin_faction, -2 * m.reward, "failed: " .. m.short)
        end
        return true  -- suppress generic "time expired" message
    end
    return false
end

function M.cleanup(m)
    if m.convoy_cs then
        local s = RT.find(m.convoy_cs)
        if RT.valid(s) and not m._convoy_arrived then s:destroy() end
    end

    for _, interc in ipairs(m._interceptors or {}) do
        local s = RT.find(interc.cs)
        if RT.valid(s) then s:destroy() end
    end

    if m._convoy_arrived then
        _dismissFighters(m)  -- no-op if already dismissed in update()
    else
        for _, cs in ipairs(m.fighter_cs or {}) do
            local s = RT.find(cs)
            if RT.valid(s) then s:destroy() end
        end
    end
end

function M.completable(m, cs)
    return m._convoy_arrived and cs == m.dest
end

function M.completeReply(m, entry)
    return {
        label = string.format("Collect escort payment (+%d cr)", m.reward),
        msg   = m.complete_msg or '"The convoy made it. Payment transferred."',
    }
end

JOBS.register(M)
JOBS._tick_hooks[#JOBS._tick_hooks + 1] = _tickDeparting
