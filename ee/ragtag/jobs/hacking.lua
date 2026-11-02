-- ee/ragtag/jobs/hacking.lua
-- Hacking job type: breach a stationary Concord comms relay beacon.

local _ARCHETYPES = {
    {
        cargo="an encrypted nav log", short_offer="Hack a relay for nav logs",
        lore="Someone has been running routes they don't want on record. The log lives in a relay buoy.",
        accept_msg='"Get Relay in position and crack it before anyone notices the uplink."',
        recv_msg='"Routes confirmed. This is exactly what we needed."',
        reward_mult=1.0, tier_min=0, intercept_types={}, intercept_chance=0,
    },
    {
        cargo="a comms archive", short_offer="Extract comms from a dark relay",
        lore="Months of unencrypted traffic between two stations — someone paid to keep this relay dark.",
        accept_msg='"Pull the archive intact. Partial data is worthless to us."',
        recv_msg='"Everything\'s here. Good clean extraction."',
        reward_mult=1.0, tier_min=0,
        intercept_types={{type="rival",strength="scout",weight=2,
            msg="Courier on intercept heading — someone else wants that archive."}},
        intercept_chance=0.20,
    },
    {
        cargo="a contraband manifest", short_offer="Crack a smuggler's relay cache",
        lore="A smuggling outfit uses relay buoys to cache their cargo schedules. Concord wants the manifest.",
        accept_msg='"Crack it quietly. If they notice the uplink they\'ll wipe the buffer."',
        recv_msg='"Manifest intact. Half a dozen ships just had a very bad week."',
        reward_mult=1.1, tier_min=0,
        intercept_types={{type="pirates",strength="scout",weight=3,
            msg="Two contacts breaking off a nearby lane. They're watching this relay."}},
        intercept_chance=0.30,
    },
    {
        cargo="docking access codes", short_offer="Pull codes from a relay buffer",
        lore="Station authority codes rotate weekly but the old set sits in a relay buffer.",
        accept_msg='"In and out before the rotation. You have a narrow window."',
        recv_msg='"Codes are live. We\'ll use them once — don\'t ask what for."',
        reward_mult=1.3, tier_min=1,
        intercept_types={{type="concord",strength="scout",weight=2,
            msg="Concord patrol just changed heading. They may have flagged the uplink attempt."}},
        intercept_chance=0.35,
    },
    {
        cargo="a black ledger fragment", short_offer="Break into a hardened relay",
        lore="Corporate financial records split across relay nodes. One fragment is enough to bring down a board.",
        accept_msg='"This relay is hardened. It will resist. Don\'t stop until you\'re through."',
        recv_msg='"Fragment verified. You just changed some very powerful people\'s plans."',
        reward_mult=1.5, tier_min=2,
        intercept_types={{type="rival",strength="medium",weight=3,
            msg="Corporate security responding. They know what you're pulling."}},
        intercept_chance=0.50,
    },
}

local function _beaconName()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ123456789"
    local code = ""
    for _ = 1, 5 do
        local idx = math.random(#chars)
        code = code .. chars:sub(idx, idx)
    end
    return "Beacon " .. code
end

local M = {}
M.type      = "hacking"
M.weight    = 3
M.tier_min  = 1   -- requires 500cr investment
M.type_mult = 1.4

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    local wx, wy, dist, region = ctx.spawnInVerse(rx, ry)
    if not wx then return nil end
    return {
        origin         = ctx.station_cs,
        wx = wx, wy = wy,
        tier           = ctx.tier,
        distance_u     = dist,
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
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["hacking"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)

    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = MISSION.weightedPick(arch.intercept_types)
        intercept = {itype=ic.type, strength=ic.strength, trigger=0, msg_log=ic.msg, fired=false}
    end

    return {
        id             = MISSION.nextId(),
        type           = "hacking",
        tier           = tier,
        origin         = opts.origin,
        wx             = opts.wx,
        wy             = opts.wy,
        cargo          = arch.cargo,
        hack_threshold = 0.75,
        reward         = reward,
        short          = arch.short_offer,
        obj            = "Hack relay near " .. opts.origin,
        brief          = arch.lore .. "\n\n" .. arch.accept_msg
                         .. "\n\nHack any of the relay's systems to 75% to breach its datastore.",
        complete_msg   = arch.recv_msg,
        intercept      = intercept,
        distance_u     = opts.distance_u or 0,
        region_name    = opts.region_name,
        _spawned       = false,
        _hacked        = false,
        target_cs      = nil,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.warp1 + 780)
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    return string.format("● Breach a Concord comms relay in %s.\n  %s", region, stats)
end

function M.spawn(m)
    if m._spawned then return end
    local name = _beaconName()
    local s = CpuShip():setTemplate("ANT 615"):setFaction("Concord")
    s:setCallSign(name):setTypeName("Comms Relay")
    s:setPosition(m.wx, m.wy):orderIdle():setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    s:setHullMax(50):setHull(50):setShieldsMax(0):setShields(0)
    s:setCanBeDestroyed(false)
    s:setSystemHealth("reactor", 1.0)
    s:setSystemHealth("beamweapons", 1.0)
    -- Four overlapping 120° mounts at 90° intervals → full 360° coverage at 4U.
    s:setBeamWeapon(0, 120,   0, 4000, 6, 4)
    s:setBeamWeapon(1, 120,  90, 4000, 6, 4)
    s:setBeamWeapon(2, 120, 180, 4000, 6, 4)
    s:setBeamWeapon(3, 120, 270, 4000, 6, 4)
    s:setSystemHackedLevel("reactor", 0.0)
    RT.named[name] = s
    s:setCommsFunction(function(src, tgt)
        setCommsMessage("Automated relay. No response.")
    end)
    m.target_cs = name
    m.short     = "Hack " .. name
    m.obj       = "Hack " .. name
    m._spawned  = true
end

function M.acceptLog(m)
    return string.format("Contract: %s. %dm to complete. Target: %s at grid %s.",
        m.short, math.floor(m._time_limit / 60),
        m.target_cs or "unknown", MISSION.gridRef(m.wx, m.wy))
end

local _SYSTEMS = {"reactor","beamweapons","missilesystem","maneuver","impulse","warp","jumpdrive","frontshield","rearshield"}

function M.update(m, entry, ctx)
    if m._hacked then return nil end  -- waiting for return

    local target = RT.find(m.target_cs)
    if not RT.valid(target) then
        RT.shipLog("[Hack] Relay destroyed before extraction -- contract lost.", "#FF8080")
        return "remove"
    end

    -- Every 2s: aim beams at nearest player within 4U; jam probes within 5U.
    m._last_jam_check = m._last_jam_check or 0
    if ctx.now - m._last_jam_check > 2 then
        m._last_jam_check = ctx.now

        local beam_target, beam_dist = nil, math.huge
        for _, p in ipairs(RT.players) do
            if RT.valid(p) then
                local d = RT.dist(target, p)
                if d < 4000 and d < beam_dist then
                    beam_target = p; beam_dist = d
                end
            end
        end
        if beam_target then
            target:orderAttack(beam_target)
        else
            target:orderIdle()
        end

        local rx, ry = target:getPosition()
        for _, obj in ipairs(getObjectsInRadius(rx, ry, 5000)) do
            if RT.valid(obj) and obj ~= target and isObjectType(obj, "ScanProbe") then
                obj:destroy()
                RT.shipLog("[Relay] Jamming field neutralised a probe.", "#FF8080")
            end
        end
    end

    -- Check any system hacked to threshold.
    local max_hack, hacked_sys = 0, nil
    for _, sys in ipairs(_SYSTEMS) do
        local has = false
        local ok1 = pcall(function() has = target:hasSystem(sys) end)
        if ok1 and has then
            local ok2, lvl = pcall(function() return target:getSystemHackedLevel(sys) end)
            if ok2 and lvl and lvl > max_hack then
                max_hack = lvl; hacked_sys = sys
            end
        end
    end

    if max_hack >= m.hack_threshold then
        m._hacked = true
        target:setCanBeDestroyed(true)
        m.obj = "Return " .. m.cargo .. " to " .. m.origin
        RT.shipLog("[Hack] " .. (hacked_sys or "system") .. " breach successful! Data extracted from "
            .. m.target_cs .. ". Return to " .. m.origin .. ".", "#80FF80")
        JOBS.updateObj()
    end
    return nil
end

function M.completable(m, cs)
    return m.origin == cs and m._hacked == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Deliver %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Good extraction."',
    }
end

JOBS.register(M)
