-- ee/ragtag/jobs/destroy.lua
-- Destroy job type: hunt and eliminate a hostile target ship.

local _ARCHETYPES = {
    {
        cargo="a bounty claim", short_offer="Eliminate a wanted fugitive",
        faction_label="wanted Corsair",
        lore="A wanted corsair with a dead-or-alive bounty. Last seen operating a fast raider.",
        accept_msg='"Destroy the target completely. No boarding, no survivors. We want proof."',
        recv_msg='"Target eliminated. Bounty posted to your account."',
        target_template="MT52 Hornet",
        reward_mult=1.0, tier_min=0,
    },
    {
        cargo="proof of destruction", short_offer="Destroy a rogue AI ship",
        faction_label="rogue AI drone",
        lore="An automated patrol ship malfunctioned and is broadcasting corrupted IFF codes. It's firing on friendlies.",
        accept_msg='"Eliminate the target. Do not attempt boarding — the AI is hostile to all organics."',
        recv_msg='"Threat neutralized. Wreckage retrieved for analysis."',
        target_template="Adder MK5",
        reward_mult=1.1, tier_min=0,
    },
    {
        cargo="a quarantine certificate", short_offer="Destroy a plague ship",
        faction_label="quarantined plague freighter",
        lore="A freighter carrying an unstable bioweapon sample lost containment. The crew is dead or worse.",
        accept_msg='"Burn it out of space. Do not approach within 1U. Do not board. Complete destruction only."',
        recv_msg='"Contaminated hulk destroyed. Medical authority confirms clean burn."',
        target_template="Flavia P.Falcon",
        reward_mult=1.2, tier_min=1,
    },
    {
        cargo="combat telemetry", short_offer="Eliminate a pirate captain",
        faction_label="Corsair captain",
        lore="A corsair captain with fifteen raids to their name. Known for heavy armor and refusing surrender.",
        accept_msg='"No quarter. This one doesn\'t run and doesn\'t dock quietly."',
        recv_msg='"Captain confirmed KIA. The lanes just got safer."',
        target_template="Phobos T3",
        reward_mult=1.3, tier_min=1,
    },
    {
        cargo="a black-ops confirmation", short_offer="Destroy a defector's ship",
        faction_label="Concord defector",
        lore="A former Concord officer stole classified files and is running for Hollow space. Eliminate before they cross the line.",
        accept_msg='"Target is armed, experienced, and knows you\'re coming. Total destruction. No witnesses."',
        recv_msg='"Target eliminated. Files unrecoverable. This conversation never happened."',
        target_template="Phobos M3P",
        reward_mult=1.5, tier_min=2,
    },
}

local M = {}
M.type      = "destroy"
M.weight    = 3
M.tier_min  = 2
M.type_mult = 1.6

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    local wx, wy, dist, region = ctx.spawnInVerse(rx, ry)
    if not wx then return nil end
    local nearby = ctx.nearbyStations(wx, wy, 150000)
    -- Exclude origin, Hollow, and Corsair stations from target destinations.
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
    local arch   = pool[math.random(#pool)]
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["destroy"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)

    local target_dest = nil
    if opts.nearby_stations and #opts.nearby_stations > 0 then
        target_dest = opts.nearby_stations[math.random(#opts.nearby_stations)]
    end

    return {
        id              = MISSION.nextId(),
        type            = "destroy",
        tier            = tier,
        origin          = opts.origin,
        wx              = opts.wx,
        wy              = opts.wy,
        cargo           = arch.cargo,
        reward          = reward,
        short           = arch.short_offer,
        obj             = "Locate and destroy target",
        brief           = arch.lore .. "\n\n" .. arch.accept_msg
                          .. "\n\nTarget must be completely destroyed. No boarding, no salvage.",
        complete_msg    = arch.recv_msg,
        target_template = arch.target_template,
        target_dest     = target_dest,
        distance_u      = opts.distance_u or 0,
        region_name     = opts.region_name,
        faction_label   = arch.faction_label,
        _spawned        = false,
        _destroyed      = false,
        _attacking      = false,
        target_cs       = nil,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.warp1 + 600)
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    return string.format("● Eliminate a %s in %s.\n  %s", m.faction_label or "target", region, stats)
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
    m.short      = "Destroy " .. name
    m.obj        = "Destroy " .. name
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
    if m._destroyed then return nil end

    local target = RT.find(m.target_cs)
    if not RT.valid(target) then
        m._destroyed = true
        RT.addReputation("Corsairs", -200, "destroyed " .. (m.target_cs or "unknown"))
        m.obj = "Return to " .. m.origin
        RT.shipLog("[Target] " .. (m.target_cs or "target") .. " destroyed. Return to " .. m.origin .. ".", "#80FF80")
        JOBS.updateObj()
        return nil
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
    return nil
end

function M.completable(m, cs)
    return m.origin == cs and m._destroyed == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Submit %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Target confirmed destroyed."',
    }
end

JOBS.register(M)
