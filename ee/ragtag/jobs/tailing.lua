-- ee/ragtag/jobs/tailing.lua
-- Tailing job type: shadow a ship to a covert meeting; scan both vessels.

local _ARCHETYPES = {
    {
        cargo="traffic analysis", short_offer="Surveil a suspected courier",
        lore="Someone is moving information through this sector on an irregular route. We need to know who they're meeting.",
        accept_msg='"Find it and follow it but not too close. Their sensor suites pick up ships or probes within 10u, so keep your distance. When it meets its contact we want full scan data on both ships."',
        recv_msg='"Contact identified. This is more than we hoped for."',
        reward_mult=1.0, tier_min=0,
    },
    {
        cargo="a contact identification", short_offer="Identify a meeting contact",
        lore="A ship operating without a registered route has been spotted twice. Someone is meeting it out here.",
        accept_msg='"Find it and follow it but not too close. Their sensor suites pick up ships or probes within 10u, so keep your distance. When it meets its contact we want full scan data on both ships."',
        recv_msg='"Got the ID. You\'ve answered a question we\'ve been asking for months."',
        reward_mult=1.0, tier_min=0,
    },
    {
        cargo="rendezvous confirmation", short_offer="Confirm a covert rendezvous",
        lore="Intelligence points to a handoff happening in deep space. We need confirmation — no intercept, just eyes on.",
        accept_msg='"Find it and follow it but not too close. Their sensor suites pick up ships or probes within 10u, so keep your distance. When it meets its contact we want full scan data on both ships. Keep your probes stowed."',
        recv_msg='"Confirmed. This closes the loop on a three-month investigation."',
        reward_mult=1.1, tier_min=1,
    },
    {
        cargo="a defector sighting", short_offer="Locate a missing operative",
        lore="A former Concord analyst went dark six weeks ago. Last known heading puts them somewhere in this sector.",
        accept_msg='"Find it and follow it but not too close. Their sensor suites pick up ships or probes within 10u, so keep your distance. When it meets its contact we want full scan data on both ships."',
        recv_msg='"Both names confirmed. This is sensitive — we\'ll handle it from here."',
        reward_mult=1.3, tier_min=1,
    },
    {
        cargo="supply chain evidence", short_offer="Trace a contraband supply run",
        lore="Someone is running contraband through unregistered drops. We\'ve traced the route to this sector.",
        accept_msg='"Find it and follow it but not too close. Their sensor suites pick up ships or probes within 10u, so keep your distance. When it meets its contact we want full scan data on both ships."',
        recv_msg='"Supply chain mapped. This reaches further up than we thought."',
        reward_mult=1.4, tier_min=2,
    },
}

local _TEMPLATES = {
    [0] = {"Flavia P.Falcon"},
    [1] = {"Flavia P.Falcon", "Phobos T3"},
    [2] = {"Phobos T3", "Phobos M3P"},
}

local function _disperse(m)
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
        local st = RT.find(available[1])
        if RT.valid(st) then
            local sx, sy = st:getPosition()
            tgt:setWarpDrive(true):setWarpSpeed(300)
            tgt:orderFlyTowardsBlind(sx, sy)
        end
    end
    local rdv = RT.find(m.rendezvous_cs or "")
    if RT.valid(rdv) and #available >= 2 then
        local st = RT.find(available[2])
        if RT.valid(st) then
            local sx, sy = st:getPosition()
            rdv:setWarpDrive(true):setWarpSpeed(300)
            rdv:orderFlyTowardsBlind(sx, sy)
        end
    end
end

local M = {}
M.type      = "tailing"
M.weight    = 3
M.tier_min  = 1
M.type_mult = 1.4

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    -- The meeting point is the full spawn distance; ships spawn at D/4 and D/2 from that point.
    local mx, my, dist, region = ctx.spawnInVerse(rx, ry)
    if not mx then return nil end
    return {
        origin         = ctx.station_cs,
        wx = mx, wy = my,   -- placeholder; spawn overwrites with target position
        mx = mx, my = my,
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
    local arch    = pool[math.random(#pool)]
    local templates = _TEMPLATES[tier] or _TEMPLATES[0]
    local target_template = templates[math.random(#templates)]
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["tailing"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)

    return {
        id               = MISSION.nextId(),
        type             = "tailing",
        tier             = tier,
        origin           = opts.origin,
        wx               = opts.wx,
        wy               = opts.wy,
        mx               = opts.mx,
        my               = opts.my,
        cargo            = arch.cargo,
        reward           = reward,
        short            = arch.short_offer,
        obj              = "Locate target",
        brief            = arch.lore .. "\n\n" .. arch.accept_msg
                           .. "\n\nThey'll detect a probe signature or any ship within weapons range — spook them before the meeting and the contract is lost.",
        complete_msg     = arch.recv_msg,
        target_template  = target_template,
        distance_u       = opts.distance_u or 0,
        region_name      = opts.region_name,
        _spawned         = false,
        _meeting         = false,
        _meeting_at      = nil,
        _scanned         = false,
        target_cs        = nil,
        rendezvous_cs    = nil,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.warp1 + 600)
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    return string.format("● Shadow a ship to a covert meeting in %s. · %s", region, stats)
end

function M.spawn(m)
    if m._spawned then return end
    local WARP1     = 500
    local SHIP_WARP = 125
    local RDV_WARP  = 250
    local D  = math.max(m.distance_u, 15000)
    local T  = D / WARP1
    local spawn_dist     = T * SHIP_WARP   -- D/4
    local rdv_spawn_dist = T * RDV_WARP    -- D/2

    local t_ang   = math.random() * 2 * math.pi
    local rdv_ang = t_ang + math.pi * 0.5 + math.random() * math.pi

    local tname = JOBS.corsairName()
    local twx = math.floor(m.mx + math.cos(t_ang) * spawn_dist)
    local twy = math.floor(m.my + math.sin(t_ang) * spawn_dist)
    local target = CpuShip():setTemplate(m.target_template):setFaction("Unknown")
    target:setCallSign(tname)
    target:setPosition(twx + math.random(-1000, 1000), twy + math.random(-1000, 1000))
    target:setRotation((270 - math.deg(t_ang)) % 360)
    target:setHull(target:getHullMax())
    target:setScanningParameters(1, 1)
    target:setWarpDrive(false):setImpulseMaxSpeed(SHIP_WARP)
    target:orderFlyTowardsBlind(m.mx, m.my)
    RT.register(target)
    target:setCommsFunction(function(src, tgt) setCommsMessage('"No response."') end)

    local rname = JOBS.freighterName()
    local rwx = math.floor(m.mx + math.cos(rdv_ang) * rdv_spawn_dist)
    local rwy = math.floor(m.my + math.sin(rdv_ang) * rdv_spawn_dist)
    local rendezvous = CpuShip():setTemplate("Flavia P.Falcon"):setFaction("Unknown")
    rendezvous:setCallSign(rname)
    rendezvous:setPosition(rwx, rwy)
    rendezvous:setRotation((270 - math.deg(rdv_ang)) % 360)
    rendezvous:setWarpDrive(false):setImpulseMaxSpeed(RDV_WARP)
    rendezvous:orderFlyTowardsBlind(m.mx, m.my)
    RT.register(rendezvous)
    rendezvous:setCommsFunction(function(src, tgt) setCommsMessage('"Move along."') end)

    -- Overwrite wx/wy with target's actual spawn position for the log hint.
    m.wx = twx
    m.wy = twy

    m.target_cs     = tname
    m.rendezvous_cs = rname
    m._meet_at      = getScenarioTime() + T
    m.short = "Surveil " .. tname
    m.obj   = "Locate " .. tname
    m._spawned = true
end

function M.acceptLog(m)
    local hdx = m.mx - m.wx
    local hdy = m.my - m.wy
    local heading_deg = math.floor((math.deg(math.atan(hdx, -hdy)) + 360) % 360 + 0.5)
    local t_min = math.max(1, math.floor((m._meet_at - getScenarioTime()) / 60 + 0.5))
    return string.format(
        "Contract: %s. %dm to complete. Target last spotted at %s heading %03d. We expect a rendezvous in ~%dm. Approach with care.",
        m.short, math.floor(m._time_limit / 60),
        MISSION.gridRef(m.wx, m.wy), heading_deg, t_min)
end

function M.update(m, entry, ctx)
    if m._scanned then return nil end  -- waiting for return

    local tgt = RT.find(m.target_cs or "")
    local rdv = RT.find(m.rendezvous_cs or "")

    if not m._meeting then
        if not RT.valid(tgt) then
            RT.shipLog("[Tailing] Target lost -- contract failed.", "#FF8080")
            return "remove"
        end

        -- Detection en route: player or probe within 10U spooks the target.
        local spook = nil
        for _, p in ipairs(RT.players) do
            if RT.valid(p) and RT.dist(p, tgt) < 10000 then
                spook = "target spotted the ship"; break
            end
        end
        if not spook then
            local tx, ty = tgt:getPosition()
            for _, obj in ipairs(getObjectsInRadius(tx, ty, 10000)) do
                if RT.valid(obj) and isObjectType(obj, "ScanProbe") then
                    spook = "target detected a probe"; break
                end
            end
        end
        if spook then
            RT.shipLog("[Tailing] Contract failed — looks like they got spooked. (" .. spook .. ")", "#FF8080")
            _disperse(m)
            return "remove"
        end

        -- Stall watchdog: re-issue fly orders every 20s.
        m._fly_refresh = m._fly_refresh or 0
        if ctx.now > m._fly_refresh then
            tgt:orderFlyTowardsBlind(m.mx, m.my)
            if RT.valid(rdv) then rdv:orderFlyTowardsBlind(m.mx, m.my) end
            m._fly_refresh = ctx.now + 20
        end

        -- Meeting: target and rendezvous within 1.5U.
        if RT.valid(rdv) and RT.dist(tgt, rdv) < 1500 then
            m._meeting    = true
            m._meeting_at = ctx.now
            tgt:orderIdle()
            rdv:orderIdle()
            local mx, my = tgt:getPosition()
            RT.shipLog("[Tailing] Meeting in progress at " .. MISSION.gridRef(mx, my)
                .. ". Science: scan both ships. 90 seconds.", "#FFCC80")
            m.obj = "Scan both ships at meeting"
            JOBS.updateObj()
        end

        -- Rendezvous deadline: 120s grace past T.
        if ctx.now > m._meet_at + 120 and not m._meeting then
            RT.shipLog("[Tailing] Ships completed their rendezvous unobserved. Contract failed.", "#FF8080")
            _disperse(m)
            return "remove"
        end

    else
        -- Meeting in progress: watch for detection.
        local spook = nil
        for _, p in ipairs(RT.players) do
            if RT.valid(p) and RT.valid(tgt) and RT.dist(p, tgt) < 10000 then
                spook = "ship got too close during the meeting"; break
            end
        end
        if not spook and RT.valid(tgt) then
            local tx, ty = tgt:getPosition()
            for _, obj in ipairs(getObjectsInRadius(tx, ty, 10000)) do
                if RT.valid(obj) and isObjectType(obj, "ScanProbe") then
                    spook = "probe detected during the meeting"; break
                end
            end
        end
        if spook then
            RT.shipLog("[Tailing] Contract failed — looks like they got spooked. (" .. spook .. ")", "#FF8080")
            _disperse(m)
            return "remove"
        end

        -- 90-second scan window.
        if ctx.now - m._meeting_at > 90 then
            RT.shipLog("[Tailing] Meeting ended — not scanned in time. Contract lost.", "#FF8080")
            _disperse(m)
            return "remove"
        end

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
                            RT.shipLog("[Tailing] Contact ship " .. m.rendezvous_cs .. " identified.", "#FFCC80")
                        end
                    end
                    if m._tgt_scanned and m._rdv_scanned then
                        m._scanned = true
                        m.obj = "Return intel to " .. m.origin
                        local cx, cy = tgt:getPosition()
                        RT.shipLog("[Tailing] Both ships identified at " .. MISSION.gridRef(cx, cy)
                            .. ". Return to " .. m.origin .. ".", "#80FF80")
                        JOBS.updateObj()
                        _disperse(m)
                        return nil
                    end
                end
            end
        end
    end
    return nil
end

function M.expire(m)
    local tgt = RT.find(m.target_cs or "")
    local rdv = RT.find(m.rendezvous_cs or "")
    if RT.valid(tgt) then tgt:destroy() end
    if RT.valid(rdv) then rdv:destroy() end
    RT.shipLog("[Contract] " .. m.short .. " -- time expired. Contract lost.", "#FF8080")
    if m.origin_faction then
        RT.addReputation(m.origin_faction, -2 * m.reward, "failed: " .. m.short)
    end
    return true  -- suppress engine default
end

function M.completable(m, cs)
    return m.origin == cs and m._scanned == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Deliver %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Intel received."',
    }
end

JOBS.register(M)
