-- ee/ragtag/jobs/boarding.lua
-- Boarding job type: disable a target ship and send a boarding party.

local _ARCHETYPES = {
    {
        cargo="a stolen data core", short_offer="Disable a Corsair runner",
        faction_label="Corsair runner",
        lore="A Corsair runner lifted survey data from a prospecting team. The owner wants it back quietly.",
        accept_msg='"Disable the ship and take back the core. Don\'t destroy it — the data might not survive the hull breach."',
        recv_msg='"Data core intact. You\'ve got a friend in this business."',
        reward_mult=1.2, tier_min=0,
        intercept_types={}, intercept_chance=0,
    },
    {
        cargo="a hijacked courier", short_offer="Board a captured courier",
        faction_label="captured Independent courier",
        lore="An independent courier was pulled off their route — ship taken, crew stuck aboard. Someone wants them back.",
        accept_msg='"They\'re still alive. Disable the ship and get them out before the Corsairs move them again."',
        recv_msg='"I thought that was it for me. Thank you."',
        reward_mult=1.4, tier_min=0,
        intercept_types={{type="pirates",strength="scout",weight=2,
            msg="Corsair support ship is responding. They don't want to lose their prize."}},
        intercept_chance=0.25,
    },
    {
        cargo="a locked evidence container", short_offer="Intercept a smuggling run",
        faction_label="Corsair smuggler",
        lore="Smuggler running contraband for a connected outfit. Concord wants the evidence container — not the ship, not the crew.",
        accept_msg='"Disable them cleanly. Destroy the ship and the evidence chain breaks."',
        recv_msg='"Chain of custody intact. Well done."',
        reward_mult=1.1, tier_min=1,
        intercept_types={{type="pirates",strength="scout",weight=2,
            msg="Second ship just altered course toward you. Someone tipped off the outfit."}},
        intercept_chance=0.30,
    },
    {
        cargo="a Corsair lieutenant", short_offer="Capture a Corsair officer",
        faction_label="Corsair officer",
        lore="Mid-level Corsair officer moving between cells. Intelligence wants them alive for questioning.",
        accept_msg='"Disable the escort — they\'ll be running a light ship, fast. Board carefully."',
        recv_msg='"We\'ll take custody from here. What they know is worth more than you\'d guess."',
        reward_mult=1.5, tier_min=1,
        intercept_types={{type="pirates",strength="light",weight=3,
            msg="Two Corsair ships just lit up on sensors. Responding to the escort's distress call."}},
        intercept_chance=0.45,
    },
    {
        cargo="a corporate defector", short_offer="Stop a fleeing operative",
        faction_label="corporate operative",
        lore="A corporate operative who knows too much tried to disappear. The parent company wants them back with the financial records intact.",
        accept_msg='"Disable the ship before they can vent the data. Board fast."',
        recv_msg='"Asset secured and records intact. Discretion noted."',
        reward_mult=1.6, tier_min=2,
        intercept_types={{type="rival",strength="medium",weight=3,
            msg="Corporate security ship on an intercept heading. They have the same contract."}},
        intercept_chance=0.50,
    },
}

local _TEMPLATES = {
    [0] = {"Adder MK5", "MT52 Hornet"},
    [1] = {"Phobos T3", "Adder MK5"},
    [2] = {"Phobos M3P", "Phobos T3"},
}

local M = {}
M.type      = "boarding"
M.weight    = 3
M.tier_min  = 2
M.type_mult = 1.8

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    local wx, wy, dist, region = ctx.spawnInVerse(rx, ry)
    if not wx then return nil end
    local nearby = ctx.nearbyStations(wx, wy, 150000)
    local filtered = {}
    for _, cs in ipairs(nearby) do
        if cs ~= ctx.station_cs then
            local e = ctx.findStation(cs)
            if ctx.valid(e) then
                local ok, fac = pcall(function() return e:getFaction() end)
                if ok and fac ~= "Hollow" and fac ~= "Corsairs" then
                    filtered[#filtered + 1] = cs
                end
            end
        end
    end
    return {
        origin         = ctx.station_cs,
        wx = wx, wy = wy,
        tier           = ctx.tier,
        distance_u     = dist,
        danger_level   = region and region.danger or 0,
        region_name    = region and region.name or nil,
        distance_min_u = ctx.distanceRange.min,
        distance_max_u = ctx.distanceRange.max,
        nearby_stations = filtered,
    }
end

function M.generate(opts)
    local tier = opts.tier or 0
    local pool = {}
    for _, a in ipairs(_ARCHETYPES) do
        if a.tier_min <= tier then pool[#pool + 1] = a end
    end
    if #pool == 0 then pool = _ARCHETYPES end
    local arch      = pool[math.random(#pool)]
    local templates = _TEMPLATES[tier] or _TEMPLATES[0]
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["boarding"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)

    local target_dest = nil
    if opts.nearby_stations and #opts.nearby_stations > 0 then
        target_dest = opts.nearby_stations[math.random(#opts.nearby_stations)]
    end

    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = MISSION.weightedPick(arch.intercept_types)
        intercept = {itype=ic.type, strength=ic.strength, trigger=0, msg_log=ic.msg, fired=false}
    end

    return {
        id              = MISSION.nextId(),
        type            = "boarding",
        tier            = tier,
        origin          = opts.origin,
        wx              = opts.wx,
        wy              = opts.wy,
        cargo           = arch.cargo,
        reward          = reward,
        short           = arch.short_offer,
        obj             = "Locate and disable target",
        brief           = arch.lore .. "\n\n" .. arch.accept_msg
                          .. "\n\nTarget propulsion with beam weapons (Weapons station → system target: impulse) to disable without destroying.",
        complete_msg    = arch.recv_msg,
        target_template = templates[math.random(#templates)],
        target_dest     = target_dest,
        intercept       = intercept,
        distance_u      = opts.distance_u or 0,
        region_name     = opts.region_name,
        faction_label   = arch.faction_label,
        _spawned        = false,
        _attacking      = false,
        _disabled       = false,
        _boarded        = false,
        target_cs       = nil,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.warp1 + 900)
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    return string.format("Disable and board a %s in %s.", m.faction_label or "target", region)
        .. "\n  Boarding · " .. stats
end

function M.spawn(m)
    if m._spawned then return end
    local dest_station = nil
    if m.target_dest then dest_station = RT.find(m.target_dest) end

    local s = CpuShip():setTemplate(m.target_template):setFaction("Unknown")
    local name = JOBS.corsairName()
    s:setCallSign(name)
    s:setPosition(m.wx + math.random(-2000, 2000), m.wy + math.random(-2000, 2000))
    s:setHull(s:getHullMax())
    for _, sys in ipairs({"impulse","reactor","beamweapons","missilesystem","maneuver","warp","jumpdrive","frontshield","rearshield"}) do
        s:setSystemHealth(sys, 1.0)
    end
    local mf = s:getShieldMax(0)
    local mr = s:getShieldMax(1)
    if mf > 0 then s:setShields(mf, mr) end
    s:setScanningParameters(1, 1)
    if dest_station and RT.valid(dest_station) then
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
    m.target_cs  = name
    m.short      = "Disable " .. name
    m.obj        = "Intercept " .. name
    m._spawned   = true
    m._attacking = false
end

function M.acceptLog(m)
    local heading_text = m.target_dest and (" heading toward " .. m.target_dest) or ""
    return string.format("Contract: %s. %dm to complete. %s last seen around %s%s.",
        m.short, math.floor(m._time_limit / 60),
        m.target_cs or "unknown", MISSION.gridRef(m.wx, m.wy), heading_text)
end

function M.update(m, entry, ctx)
    if m._boarded then return nil end

    local target = RT.find(m.target_cs)

    if not m._disabled then
        if not RT.valid(target) then
            RT.shipLog("[Boarding] Target destroyed before boarding -- contract lost.", "#FF8080")
            return "remove"
        end

        if not m._attacking then
            for _, p in ipairs(RT.players) do
                if RT.valid(p) and RT.dist(target, p) < 8000 then
                    target:setFaction("Corsairs")
                    target:orderAttack(p)
                    m._attacking = true
                    RT.shipLog("[Target] " .. m.target_cs .. " detected our approach and is engaging!", "#FF8080")
                    break
                end
            end
        end

        local impulse_h = target:getSystemHealth("impulse") or 1
        local hull_pct  = target:getHull() / target:getHullMax()
        if impulse_h < 0.3 or hull_pct < 0.25 then
            m._disabled = true
            RT.addReputation("Corsairs", -100, "boarded " .. m.target_cs)
            target:setCanBeDestroyed(false)
            target:orderIdle()
            target:setImpulseMaxSpeed(5)
            target:setCommsFunction(function(src, tgt)
                local tx, ty = tgt:getPosition()
                local sx, sy = src:getPosition()
                local dx, dy = tx - sx, ty - sy
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 250 then
                    setCommsMessage(string.format(
                        '"%s" is drifting — no response on any channel.\n\nRange: %.2fU. Close to within 0.25U to pull alongside.',
                        m.target_cs, dist / 1000))
                else
                    setCommsMessage(string.format(
                        '"%s" is alongside — crew standing by.\n\nSend the boarding party?',
                        m.target_cs))
                    addCommsReply("Send boarding party", function(s2, t2)
                        m._boarded = true
                        m.obj = "Return " .. m.cargo .. " to " .. m.origin
                        RT.shipLog("[Boarding] " .. m.cargo .. " secured. Return to " .. m.origin .. ".", "#80FF80")
                        JOBS.updateObj()
                        setCommsMessage(string.format('"Take it. Just let us go."\n\n%s secured.', m.cargo))
                    end)
                end
            end)
            m.obj = "Board " .. m.target_cs
            RT.shipLog("[Target] " .. m.target_cs .. " disabled. Close to 0.25U and hail to board.", "#FFCC80")
            JOBS.updateObj()
        end
    end
    -- Phase 2: _boarded is set via the comms reply above; nothing to poll here.
    return nil
end

function M.completable(m, cs)
    return m.origin == cs and m._boarded == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Deliver %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Good boarding."',
    }
end

JOBS.register(M)
