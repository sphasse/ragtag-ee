-- ee/ragtag/jobs/salvage.lua
-- Salvage job type: recover cargo pods from open space.

local _ARCHETYPES = {
    {
        cargo="a drifting cargo pod", urgent=false, reward_mult=1.0, tier_min=0,
        lore="A sealed container came off a freighter in the belt. Transponder's still pinging.",
        accept_msg='"Finder\'s fee. Bring it back intact."',
        recv_msg='"Container secured. That\'s what we were hoping for."',
        intercept_types={{type="pirates",strength="scout",weight=2,
            msg="Another ship is burning hard for the same beacon. They want the pod."}},
        intercept_chance=0.20,
    },
    {
        cargo="an emergency beacon kit", urgent=false, reward_mult=0.9, tier_min=0,
        lore="Evac pod came down in the field. No crew — just the kit. Still useful to someone.",
        accept_msg='"Salvage rights are clear. Just go get it."',
        recv_msg='"That kit will save someone\'s life eventually."',
        intercept_types={}, intercept_chance=0,
    },
    {
        cargo="a lost survey drone", urgent=false, reward_mult=1.1, tier_min=0,
        lore="Mapping probe went dark after passing through a debris cloud. Data core may still be intact.",
        accept_msg='"If the core is readable, there\'s a bonus in it."',
        recv_msg='"Data core intact. The bonus is yours."',
        intercept_types={{type="rival",strength="scout",weight=2,
            msg="Competing salvager just changed heading. They know about the drone."}},
        intercept_chance=0.20,
    },
    {
        cargo="a corporate flight recorder", urgent=false, reward_mult=1.3, tier_min=1,
        lore="A wreck that nobody is officially looking for. The flight recorder is worth more than the hull.",
        accept_msg='"Don\'t look at what\'s on it. Just bring it back."',
        recv_msg='"We\'ll take it from here. You didn\'t find this."',
        intercept_types={{type="rival",strength="light",weight=3,
            msg="Corporate security ship just appeared on sensors. Someone tipped them off."}},
        intercept_chance=0.40,
    },
    {
        cargo="a sealed courier pouch", urgent=true, reward_mult=1.2, tier_min=1,
        lore="A courier ran into trouble. The ship is gone, but the pouch is hardened and should have survived.",
        accept_msg='"Delivery contract is intact if the pouch is. Same rate."',
        recv_msg='"Seal\'s unbroken. Contract honoured."',
        intercept_types={{type="pirates",strength="light",weight=3,
            msg="Whoever took out the courier is still in the area."}},
        intercept_chance=0.50,
    },
    {
        cargo="a weapons locker", urgent=true, reward_mult=1.4, tier_min=2,
        lore="Patrol ship went down hard. The armory container ejected clean. Concord will want it, but finders keep it.",
        accept_msg='"Manifest says it\'s unsecured. Move fast."',
        recv_msg='"Secured. We\'ll keep this one quiet."',
        intercept_types={
            {type="concord",strength="medium",weight=2,
             msg="Concord patrol is moving to secure the site. They want that locker."},
            {type="pirates",strength="medium",weight=2,
             msg="Corsair raider closing fast. They're after the weapons locker."},
        },
        intercept_chance=0.55,
    },
}

-- Expose for combat drops (other systems reference MISSION.SALVAGE_ARCHETYPES).
MISSION.SALVAGE_ARCHETYPES = _ARCHETYPES

local _DECOY_LORE = {
    "Pressurised coolant drum — salvage value, no mission relevance.",
    "Fuel cell casing, empty. Useful for the alloy.",
    "Structural debris, stripped clean.",
    "Machine components, fire-damaged.",
}
local _DECOY_CARGO = {"Scrap Metal", "Coolant Residue", "Spent Fuel Cells", "Salvage Debris"}

local function _cleanCluster(m)
    if not m._cluster then return end
    for _, e in ipairs(m._cluster) do
        if not e._materialized and RT.valid(e.marker) then
            e.marker:setCanBeDestroyed(true)
            e.marker:destroy()
        end
    end
end

local M = {}
M.type      = "salvage"
M.weight    = 7
M.tier_min  = 0
M.type_mult = 1.2

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
    local urgent = arch.urgent or false
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["salvage"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u,
        urgent and 1.5 or 1.0)
    local prefix = urgent and "URGENT: " or ""

    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = MISSION.weightedPick(arch.intercept_types)
        intercept = {itype=ic.type, strength=ic.strength, trigger=0, msg_log=ic.msg, fired=false}
    end

    return {
        id           = MISSION.nextId(),
        type         = "salvage",
        tier         = tier,
        origin       = opts.origin,
        wx           = opts.wx,
        wy           = opts.wy,
        cargo        = arch.cargo,
        reward       = reward,
        short        = prefix .. arch.cargo,
        obj          = "Recover " .. arch.cargo,
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        intercept    = intercept,
        urgent       = urgent,
        distance_u   = opts.distance_u or 0,
        region_name  = opts.region_name,
        _found       = false,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    if m.urgent then
        return math.floor(2 * d / JOBS.SPEED.warp1 + 180)
    else
        return math.floor(2 * d / JOBS.SPEED.impulse + 180)
    end
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    local prefix = m.urgent and "URGENT: " or ""
    return string.format("● %sRecover %s from %s. · %s", prefix, m.cargo, region, stats)
end

function M.spawn(m)
    if m._spawned then return end
    local n = math.random(3, 5)
    local target_idx = math.random(1, n)
    m._cluster = {}
    for i = 1, n do
        local angle  = (i - 1) * (360 / n) + math.random(-20, 20)
        local spread = math.random(1500, 4000)
        local cx = m.wx + math.cos(math.rad(angle)) * spread
        local cy = m.wy + math.sin(math.rad(angle)) * spread
        local pod = CpuShip():setTemplate("MT52 Hornet"):setFaction("Unknown")
        pod:setPosition(cx, cy):setCallSign("Unknown Salvage"):orderIdle()
        pod:setCanBeDestroyed(false):setScanningParameters(1, 1)
        if i == target_idx then
            pod:setDescriptions(
                "Unidentified salvage container — have Science scan to identify",
                "Mission Cargo: " .. m.cargo .. ". Retrieve and return to " .. m.origin .. ".")
            m._cluster[i] = {marker=pod, is_target=true,  _materialized=false}
        else
            local di = math.random(#_DECOY_CARGO)
            pod:setDescriptions(
                "Unidentified salvage container — have Science scan to identify",
                _DECOY_LORE[di])
            m._cluster[i] = {marker=pod, is_target=false, cargo=_DECOY_CARGO[di], _materialized=false}
        end
        RT.register(pod)
    end
    m._spawned = true
end

function M.acceptLog(m)
    return string.format("Contract: %s. %dm to complete. Head to grid %s.",
        m.short, math.floor(m._time_limit / 60), MISSION.gridRef(m.wx, m.wy))
end

function M.update(m, entry, ctx)
    -- Cargo pod destroyed before pickup → mission lost.
    if m.cargo_obj and not RT.valid(m.cargo_obj) then
        RT.shipLog("[Salvage] Cargo destroyed — contract lost.", "#FF8080")
        _cleanCluster(m)
        return "remove"
    end

    if m._found then return nil end  -- waiting for return to station

    -- Scan the cluster: materialise a SupplyDrop when each pod is identified.
    if not m._cluster then return nil end
    for _, ce in ipairs(m._cluster) do
        if not ce._materialized and RT.valid(ce.marker) then
            local scanned = false
            for _, p in ipairs(RT.players) do
                if ce.marker:isFullyScannedBy(p) then scanned = true; break end
            end
            if scanned then
                local mx, my = ce.marker:getPosition()
                ce.marker:setCanBeDestroyed(true); ce.marker:destroy()
                ce._materialized = true
                local drop = SupplyDrop():setFaction("Independent"):setPosition(mx, my)
                RT.register(drop)
                if ce.is_target then
                    local cargo_name = m.cargo:gsub("^%l", string.upper)
                    drop:setDescriptions("Salvage Container", m.cargo):setCallSign(cargo_name)
                    drop:onPickUp(function(self, player)
                        for _, ae in ipairs(JOBS._active) do
                            local mis = ae.mission
                            if mis.type == "salvage" and mis.cargo_obj == self then
                                mis._found = true
                                mis.obj    = "Return " .. mis.cargo .. " to " .. mis.origin
                                RT.shipLog("[Salvage] Cargo collected: " .. mis.cargo
                                    .. ". Return to " .. mis.origin .. " for payment.", "#80FF80")
                                JOBS.updateObj()
                                if mis.intercept and not mis.intercept.fired then
                                    mis.intercept.fired = true
                                    if MISSION._spawnIntercept then
                                        MISSION._spawnIntercept(mis, player:getPosition())
                                    end
                                end
                                break
                            end
                        end
                    end)
                    m.cargo_obj = drop
                else
                    local label = ce.cargo or "Salvage Debris"
                    drop:setDescriptions("Standard Salvage", label):setCallSign(label)
                    drop:onPickUp(function(self, player)
                        player:setReputationPoints(player:getReputationPoints() + math.random(25, 50))
                        RT.shipLog("[Salvage] Standard debris recovered — small bonus.", "#FFFF80")
                    end)
                end
            end
        end
    end
    return nil
end

function M.expire(m)
    _cleanCluster(m)
    RT.shipLog("[Contract] " .. m.short .. " -- time expired. Contract lost.", "#FF8080")
    if m.origin_faction then
        RT.addReputation(m.origin_faction, -2 * m.reward, "failed: " .. m.short)
    end
    return true  -- suppress default engine expiry handling
end

function M.cleanup(m)
    _cleanCluster(m)
end

function M.completable(m, cs)
    return m.origin == cs and m._found == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Deliver %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Received. Good work."',
    }
end

JOBS.register(M)
