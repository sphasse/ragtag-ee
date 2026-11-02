-- ee/ragtag/jobs/delivery.lua
-- Delivery job type: ferry cargo between stations.

local _ARCHETYPES = {
    {
        cargo="medical supplies", urgent=true, reward_mult=1.1, tier_min=0,
        lore="The destination station is short-staffed and someone isn't doing well.",
        accept_msg='"Move fast. People are waiting on the other end."',
        recv_msg='"You got here in time. Thank you."',
        intercept_types={}, intercept_chance=0,
    },
    {
        cargo="a locked strongbox", urgent=false, reward_mult=0.9, tier_min=0,
        lore="Someone is moving their savings to a safer port. Don't ask how much is inside.",
        accept_msg='"Don\'t lose it. Don\'t open it. Please."',
        recv_msg='"I thought I\'d never see this again."',
        intercept_types={{type="pirates",strength="scout",weight=3,
            msg="Two contacts on an intercept heading. They know what you're carrying."}},
        intercept_chance=0.25,
    },
    {
        cargo="survey data cores", urgent=false, reward_mult=1.0, tier_min=0,
        lore="Fresh scan data from a prospecting run. A rival outfit would pay well for it.",
        accept_msg='"Bonded delivery. No stops, no detours."',
        recv_msg='"Ahead of schedule. Appreciated."',
        intercept_types={{type="rival",strength="scout",weight=3,
            msg="A courier just lit off after you. They want that data off your ship."}},
        intercept_chance=0.30,
    },
    {
        cargo="emergency equipment", urgent=true, reward_mult=1.0, tier_min=0,
        lore="Beacon relay parts for an outpost that went dark. No backup comms until you deliver.",
        accept_msg='"Someone out there is waiting to call for help. Move."',
        recv_msg='"We\'re back online. You have no idea what that means to us."',
        intercept_types={}, intercept_chance=0,
    },
    {
        cargo="ration crates", urgent=true, reward_mult=0.95, tier_min=0,
        lore="Another crew quoted this run first. Get there before they do.",
        accept_msg='"Beat them to it and the contract bonus is yours."',
        recv_msg='"You got here first. Contract\'s yours."',
        intercept_types={{type="rival",strength="scout",weight=3,
            msg="Competing delivery ship burning hard on your heading."}},
        intercept_chance=0.40,
    },
    {
        cargo="a sealed crate", urgent=false, reward_mult=1.5, tier_min=1,
        lore="They said don't ask. The pay says don't argue.",
        accept_msg='"You didn\'t see this. We never spoke."',
        recv_msg='"Quiet and fast. Just how we like it."',
        intercept_types={
            {type="pirates",strength="light",weight=2,
             msg="Three ships on intercept. Word got out you're carrying something valuable."},
            {type="concord",strength="light",weight=2,
             msg="Concord inspection frigate blocking the lane. Could be a tip-off, could be routine."},
        },
        intercept_chance=0.60,
    },
    {
        cargo="sealed documents", urgent=false, reward_mult=1.2, tier_min=1,
        lore="Corporate courier contract. The paperwork is above your clearance level.",
        accept_msg='"Deliver to the named recipient only. Do not break the seal."',
        recv_msg='"Intact and on time. Your bond is cleared."',
        intercept_types={{type="rival",strength="light",weight=3,
            msg="Corporate security ship — not Concord. Someone doesn't want those documents to arrive."}},
        intercept_chance=0.45,
    },
    {
        cargo="a bonded prisoner", urgent=false, reward_mult=1.4, tier_min=1,
        lore="Alive and secured. Licensed transfer. Don't let them talk to you.",
        accept_msg='"They\'ll try to negotiate. Standard contract: you don\'t open the bay."',
        recv_msg='"Secure, no incidents. The bond transfers to you now."',
        intercept_types={{type="pirates",strength="light",weight=3,
            msg="Fast ships on an intercept heading. Friends of your passenger, most likely."}},
        intercept_chance=0.50,
    },
    {
        cargo="crated ordnance", urgent=false, reward_mult=1.3, tier_min=2,
        lore="Licensed arms transfer, cleared manifest. Concord will still want to look.",
        accept_msg='"Everything is above board. Mostly. Move fast."',
        recv_msg='"All present, no tamper seals broken. Good work."',
        intercept_types={
            {type="concord",strength="medium",weight=2,
             msg="Concord patrol moving to intercept. Arms manifests get extra scrutiny out here."},
            {type="pirates",strength="medium",weight=2,
             msg="Corsair raiders on an intercept vector. They're after what's in the crates."},
        },
        intercept_chance=0.55,
    },
    {
        cargo="collector's cargo", urgent=false, reward_mult=1.35, tier_min=2,
        lore="Rare items. High value. Somebody talked.",
        accept_msg='"The value is in the pieces, not the container. Be careful."',
        recv_msg='"Every piece intact. I\'ll remember your callsign."',
        intercept_types={{type="pirates",strength="medium",weight=3,
            msg="Two ships on a cut-off vector. They know exactly what the cargo is worth."}},
        intercept_chance=0.55,
    },
}

local M = {}
M.type      = "delivery"
M.weight    = 15
M.tier_min  = 0
M.type_mult = 1.0

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
        dest           = dest_cs,
        dest_faction   = MISSION.stationFaction(dest_cs),
        tier           = ctx.tier,
        distance_u     = math.sqrt(ddx*ddx + ddy*ddy),
        danger_level   = region and region.danger or 0,
        region_name    = region and region.name or nil,
        distance_min_u = ctx.distanceRange.min,
        distance_max_u = ctx.distanceRange.max,
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
    local urgent = arch.urgent or false
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["delivery"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u,
        urgent and 1.5 or 1.0)
    local prefix = urgent and "URGENT: " or ""
    local dest_short = MISSION.shortName(opts.dest)

    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = MISSION.weightedPick(arch.intercept_types)
        intercept = {itype=ic.type, strength=ic.strength, trigger=0.40+math.random()*0.25, msg_log=ic.msg, fired=false}
    end

    return {
        id           = MISSION.nextId(),
        type         = "delivery",
        tier         = tier,
        origin       = opts.origin,
        dest         = opts.dest,
        cargo        = arch.cargo,
        reward       = reward,
        short        = prefix .. arch.cargo .. " → " .. dest_short,
        obj          = "Deliver to " .. dest_short,
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        intercept    = intercept,
        urgent       = urgent,
        distance_u   = opts.distance_u or 0,
        region_name  = opts.region_name,
        dest_faction = opts.dest_faction or "Independent",
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    if m.urgent then
        return math.floor(d / JOBS.SPEED.warp1 + 180)
    else
        return math.floor(d / JOBS.SPEED.impulse + 180)
    end
end

function M.offerText(m, stats)
    local fac    = m.dest_faction or "Independent"
    local prefix = m.urgent and "URGENT: " or ""
    return string.format("%sDeliver %s to %s (%s).", prefix, m.cargo, m.dest, fac)
        .. "\n  Delivery · " .. stats
end

function M.spawn(m)
    -- No world objects to spawn for delivery.
end

function M.acceptLog(m)
    local dest_e = RT.find(m.dest)
    if RT.valid(dest_e) then
        local dx, dy = dest_e:getPosition()
        return string.format("Contract: %s. %dm to complete. Head to %s (%s).",
            m.short, math.floor(m._time_limit / 60), m.dest, MISSION.gridRef(dx, dy))
    end
    return string.format("Contract: %s. %dm to complete. Head to %s.",
        m.short, math.floor(m._time_limit / 60), m.dest or "??")
end

function M.update(m, entry, ctx)
    -- No per-frame logic; completion is handled by stationHook completable check.
    return nil
end

function M.completable(m, cs)
    return m.dest == cs
end

function M.completeReply(m, entry)
    return {
        label = string.format("Hand off %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Received. Good flying."',
    }
end

JOBS.register(M)
