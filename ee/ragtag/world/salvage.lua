-- ee/ragtag/world/salvage.lua
-- Dynamic salvage cluster system.
--
-- Spawns initial clusters on first tick, then watches for collection and
-- respawns new clusters in random Drift-zone locations to maintain the
-- target density. Both density and reward settings reconcile immediately:
--   density change  → excess clusters destroyed, or new ones added, right away
--   reward change   → all live clusters destroyed and respawned with new values
--
-- Settings (adjustable at runtime via SALV.set* or GM menu):
--   density  1=Low (~half), 2=Medium (baseline), 3=High (~double)
--   reward   1=Low (50%), 2=Medium (100%), 3=High (200%) of base credit values

local _P = {}
_P.id              = "salvage"
_P.name            = "Salvage Clusters"
_P.default_enabled = true
_P.defaults = {
    density = 2,   -- 1=Low, 2=Medium, 3=High
    reward  = 2,   -- 1=Low, 2=Medium, 3=High
}

-- ─── Constants ────────────────────────────────────────────────────────────────

local _DENSITY_NAMES = {"Low", "Medium", "High"}
local _REWARD_NAMES  = {"Low", "Medium", "High"}
local _REWARD_MULT   = {0.5, 1.0, 2.0}
local _DENSITY_MULT  = {0.5, 1.0, 2.0}

local _SALVAGE_TIERS = {
    [0] = {pods = {3, 5}, value = {5,  10}, spread = 1.5},
    [1] = {pods = {4, 5}, value = {7,  12}, spread = 2.0},
    [2] = {pods = {4, 6}, value = {9,  15}, spread = 2.5},
    [3] = {pods = {5, 7}, value = {13, 20}, spread = 3.0},
}

-- How many pods must be collected before one new cluster is spawned.
local _PODS_PER_RESPAWN = 4

-- How often (seconds) the plugin checks for collection and reconciles settings.
local _CHECK_INTERVAL = 30

-- ─── Pod and cluster primitives ───────────────────────────────────────────────

local _POD_KINDS = {
    {kind = "credits", weight = 75, label = "Cargo pod"},
    {kind = "missiles", weight = 10, label = "Munitions crate"},
    {kind = "hull", weight = 10, label = "Hull patch kit"},
    {kind = "data", weight = 5, label = "Encrypted data chip"},
}

local function _pickKind(rng)
    local roll = rng.int(1, 100)
    local acc = 0
    for _, k in ipairs(_POD_KINDS) do
        acc = acc + k.weight
        if roll <= acc then return k end
    end
    return _POD_KINDS[1]
end

local function _spawnPod(x, y, value, kind_rec, tier)
    local art = Artifact():setPosition(x, y):allowPickup(true)
    local label = kind_rec.label
    art:setCallSign(label)
    local scanned
    if kind_rec.kind == "credits" then
        scanned = string.format("%s. Salvage value roughly %d credits.", label, value)
    elseif kind_rec.kind == "missiles" then
        scanned = "Military munitions crate. Compatible with your launchers."
    elseif kind_rec.kind == "hull" then
        scanned = "Emergency hull patch kit, still sealed."
    else
        scanned = "Encrypted data chip. Someone will pay well to read it, or to make sure nobody does."
    end
    art:setDescriptions("Small object", scanned)
    art:setScanningParameters(1, 1)
    art:onPickUp(function(obj, player)
        if kind_rec.kind == "credits" then
            RT.addCredits(value, "salvage", player)
        elseif kind_rec.kind == "missiles" then
            for _, w in ipairs({"Homing", "HVLI"}) do
                player:setWeaponStorage(w, math.min(player:getWeaponStorageMax(w), player:getWeaponStorage(w) + (w == "Homing" and 2 or 3)))
            end
            player:addToShipLog("Salvage: munitions crate. Missiles restocked.", "#E0C060")
        elseif kind_rec.kind == "hull" then
            player:setHull(math.min(player:getHullMax(), player:getHull() + 25))
            player:addToShipLog("Salvage: hull patch kit applied (+25 hull).", "#E0C060")
        else
            RT.addCredits(value * 2, "data chip", player)
        end
        RT.emit("pickup", {label = label, kind = kind_rec.kind, value = value, tier = tier,
            region = VERSE.region and VERSE.region.name or "open space"}, tier >= 2 and "normal" or "low")
    end)
    return art
end

-- value_mult scales credit values (0.5/1.0/2.0 for low/medium/high reward).
-- Returns a list of spawned artifact objects so callers can track them.
local function _spawnClusterRaw(cx, cy, tier, rng, value_mult)
    value_mult = value_mult or 1.0
    local t    = _SALVAGE_TIERS[tier]
    local U    = VERSE.U
    local n    = rng.int(t.pods[1], t.pods[2])
    local arts = {}
    for i = 1, n do
        local a      = rng.float(0, 360)
        local d      = rng.float(0.2, t.spread) * U
        local dx, dy = vectorFromAngle(a, d, true)
        local val    = math.max(1, math.floor(rng.int(t.value[1], t.value[2]) * value_mult + 0.5))
        arts[#arts + 1] = _spawnPod(cx + dx, cy + dy, val, _pickKind(rng), tier)
    end
    return arts
end

-- ─── Internal helpers ─────────────────────────────────────────────────────────

-- Spawn one cluster, store as a cluster record, and append to state.clusters.
-- Returns the record.
local function _spawnCluster(state, cx, cy, tier)
    local reward_idx = WORLD.get("salvage", "reward", 2)
    local arts       = _spawnClusterRaw(cx, cy, tier, VERSE.rng_live, _REWARD_MULT[reward_idx])
    local cl         = {pods = arts, tier = tier, alive = #arts > 0}
    state.clusters[#state.clusters + 1] = cl
    return cl
end

-- Salvage never sits near civilization: every pod of a cluster stays at least this far (U)
-- from every universe station (playtest: debris parked beside a port made no sense).
-- The freight crates that freighters lose (_updateAmbient) follow the same rule.
_P.STATION_CLEAR_U = 20

-- True when a point (world units) with pods out to spread_u around it is clear of stations.
local function _clearOfStations(wx, wy, spread_u)
    local U    = VERSE.U
    local need = (_P.STATION_CLEAR_U + (spread_u or 0)) * U
    for _, s in ipairs(VERSE.STATIONS) do
        local dx, dy = wx - s.x * U, wy - s.y * U
        if dx * dx + dy * dy < need * need then return false end
    end
    return true
end

-- A spot near anchor c for a cluster of `tier`: random offsets up to `jitter` U, widening to
-- 20U while they keep landing near a station. nil when none is clear.
local function _spotNear(c, tier, jitter, rng)
    local spread = _SALVAGE_TIERS[tier].spread
    for attempt = 1, 30 do
        local j  = math.min(20, jitter + (attempt - 1))
        local wx = (c.x + rng.float(-j, j)) * VERSE.U
        local wy = (c.y + rng.float(-j, j)) * VERSE.U
        if _clearOfStations(wx, wy, spread) then return wx, wy end
    end
end

-- Pick a random spawn location anchored to an existing VERSE.SALVAGE entry, clear of stations.
-- Returns wx, wy (world units), tier; nil when no anchor gives a clear spot.
local function _randomLocation()
    local rng = VERSE.rng_live
    for _ = 1, 10 do
        local c    = rng.pick(VERSE.SALVAGE)
        local tier = math.max(0, math.min(3, c.tier + math.random(-1, 1)))
        local wx, wy = _spotNear(c, tier, 20, rng)
        if wx then return wx, wy, tier end
    end
end

-- Destroy all pods in a cluster and mark it dead.
local function _killCluster(cl)
    for _, art in ipairs(cl.pods) do
        if RT.valid(art) then
            pcall(function() art:destroy() end)
        end
    end
    cl.alive = false
end

-- Count alive clusters (at least one pod still valid).
local function _aliveClusters(state)
    local n = 0
    for _, cl in ipairs(state.clusters) do
        if cl.alive then n = n + 1 end
    end
    return n
end

-- Pods still in the world across all tracked clusters.
local function _countPods(state)
    local n = 0
    for _, cl in ipairs(state.clusters) do
        for _, art in ipairs(cl.pods) do
            if RT.valid(art) then n = n + 1 end
        end
    end
    return n
end

-- Refresh alive flag for each cluster (pod pickup makes artifacts invalid).
local function _refresh(state)
    for _, cl in ipairs(state.clusters) do
        if cl.alive then
            local any = false
            for _, art in ipairs(cl.pods) do
                if RT.valid(art) then any = true; break end
            end
            cl.alive = any
        end
    end
    -- Prune fully dead clusters.
    for i = #state.clusters, 1, -1 do
        if not state.clusters[i].alive then table.remove(state.clusters, i) end
    end
end

-- ─── Wreck scanning ───────────────────────────────────────────────────────────

-- Any player ship within 15U of a scanned wreck finds its salvage (and hears about it). Scans
-- are per faction in the engine, so a scan by one ship counts for all of them.
local function _updateWrecks()
    for _, w in ipairs(VERSE.wrecks) do
        if not w.looted and RT.valid(w.ship) then
            for _, p in ipairs(RT.players) do
                if RT.valid(p) and RT.dist(p, w.ship) < 15000 and w.ship:isFullyScannedBy(p) then
                    w.looted = true
                    local x, y = w.ship:getPosition()
                    _spawnClusterRaw(x, y, math.min(3, w.tier + 1), VERSE.rng_live)
                    p:addToShipLog("Science: salvage located around " .. w.ship:getCallSign() .. ".", "#80C0FF")
                    RT.emit("wreck_scanned", {wreck = w.ship:getCallSign(), tier = w.tier}, "low")
                    break
                end
            end
        end
    end
end

-- ─── Ambient freight drops ────────────────────────────────────────────────────

-- Every few minutes a freighter loses a crate — a minor salvage opportunity.
local function _updateAmbient(state, now)
    if now < state.next_ambient then return end
    state.next_ambient = now + VERSE.rng_live.float(300, 480)
    for i = #state.ambient_pods, 1, -1 do
        if not RT.valid(state.ambient_pods[i]) then table.remove(state.ambient_pods, i) end
    end
    if #state.ambient_pods >= 6 or #VERSE.transports == 0 then return end
    local rec = VERSE.rng_live.pick(VERSE.transports)
    if not RT.valid(rec.ship) or rec.ship:getDockedWith() then return end
    local x, y = rec.ship:getPosition()
    if not _clearOfStations(x, y, 2) then return end   -- not within sight of a port
    local dx, dy = vectorFromAngle(rec.ship:getHeading() + 180, 1500, true)
    local pod = _spawnPod(x + dx, y + dy, VERSE.rng_live.int(5, 10), _POD_KINDS[1], 0)
    pod:setCallSign("Lost crate")
    table.insert(state.ambient_pods, pod)
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

function _P.init(state)
    state.clusters       = {}
    state.next_check     = 0
    state.next_wreck_check = 0
    state.ambient_pods   = {}
    state.next_ambient   = 300
    state.density_idx    = WORLD.get("salvage", "density", 2)
    state.reward_idx     = WORLD.get("salvage", "reward",  2)
    state.pod_debt       = 0   -- fractional respawn debt from pod pickups

    local base   = #VERSE.SALVAGE
    local target = math.max(1, math.floor(base * _DENSITY_MULT[state.density_idx] + 0.5))
    local rng    = VERSE.rng_live

    for i = 1, target do
        local c  = VERSE.SALVAGE[((i - 1) % base) + 1]
        -- Close to its anchor (2U), unless that is near a station: then as far out as it takes.
        local wx, wy = _spotNear(c, c.tier, 2, rng)
        local tier = c.tier
        if not wx then wx, wy, tier = _randomLocation() end
        if wx then _spawnCluster(state, wx, wy, tier) end
    end

    log(string.format("[Salvage] %d clusters spawned (density=%s reward=%s).",
        target, _DENSITY_NAMES[state.density_idx], _REWARD_NAMES[state.reward_idx]))
end

function _P.update(state, delta, now)
    if now >= state.next_wreck_check then
        state.next_wreck_check = now + 2
        _updateWrecks()
        _updateAmbient(state, now)
    end

    if now < state.next_check then return end
    state.next_check = now + _CHECK_INTERVAL

    local density_idx = WORLD.get("salvage", "density", 2)
    local reward_idx  = WORLD.get("salvage", "reward",  2)

    -- Pods this pass removes because a SETTING changed are not pods the crew collected: they
    -- must not earn respawns (or Low density would grow straight back).
    local settings_changed = false

    -- ── Reward changed: destroy all clusters and respawn with new values ────
    if reward_idx ~= state.reward_idx then
        for _, cl in ipairs(state.clusters) do _killCluster(cl) end
        state.clusters    = {}
        state.pod_debt    = 0
        state.reward_idx  = reward_idx
        settings_changed  = true
        -- Fall through: alive=0 so the top-up below will respawn.
    end

    _refresh(state)
    local alive = _aliveClusters(state)

    -- ── Density changed: reconcile cluster count immediately ─────────────────
    local base   = #VERSE.SALVAGE
    local target = math.max(1, math.floor(base * _DENSITY_MULT[density_idx] + 0.5))

    if density_idx ~= state.density_idx then
        if alive > target then
            -- Cull from the end of the list (oldest-first respawn order).
            for i = #state.clusters, 1, -1 do
                if alive <= target then break end
                local cl = state.clusters[i]
                if cl.alive then
                    _killCluster(cl)
                    alive = alive - 1
                end
            end
            _refresh(state)
        end
        state.density_idx = density_idx
        settings_changed  = true
    end

    -- ── Collection: pods gone since the last check earn respawn debt ────────
    -- (pod_debt carries over; tracks fractional progress toward next respawn)
    if not settings_changed and state.prev_pods ~= nil then
        local total_pods = _countPods(state)
        if state.prev_pods > total_pods then
            state.pod_debt = state.pod_debt + (state.prev_pods - total_pods)
        end
    end

    -- ── Top-up ──────────────────────────────────────────────────────────────
    -- Spawn to reach target if below (covers initial respawn after reward reset
    -- and gradual density-increase ramp).
    while alive < target do
        local wx, wy, tier = _randomLocation()
        if not wx then break end   -- no clear spot this time; the next check tries again
        _spawnCluster(state, wx, wy, tier)
        alive = alive + 1
        RT.shipLog(string.format("[Salvage] New debris cluster at grid %s.", JOBS.gridRef(wx, wy)), "#C0B070")
    end

    -- One extra cluster per _PODS_PER_RESPAWN pods collected.
    while state.pod_debt >= _PODS_PER_RESPAWN do
        local wx, wy, tier = _randomLocation()
        if not wx then break end   -- keep the debt; the next check tries again
        state.pod_debt = state.pod_debt - _PODS_PER_RESPAWN
        _spawnCluster(state, wx, wy, tier)
        alive = alive + 1
        RT.shipLog(string.format("[Salvage] New debris cluster at grid %s.", JOBS.gridRef(wx, wy)), "#C0B070")
    end

    -- What is out there now (new clusters included) is what the next check compares against.
    state.prev_pods = _countPods(state)
end

function _P.cleanup(state)
    -- Leave pods in the world; just clear tracking.
    -- Re-enabling resets state entirely and respawns the full set.
    state.clusters     = {}
    state.ambient_pods = {}
end

WORLD.register(_P)

-- ─── GM menu ──────────────────────────────────────────────────────────────────

function _P.gmMenu(addButton, showSelf)
    local on = WORLD.isEnabled("salvage")
    addButton(_P.name .. ": " .. (on and "ON" or "OFF"), function()
        if on then WORLD.disable("salvage") else WORLD.enable("salvage") end
        showSelf()
    end)
    local cur_d = SALV.getDensity()
    for i, name in ipairs(SALV.DENSITY_NAMES) do
        local cap_i = i
        addButton((i == cur_d and "* " or "") .. "Density: " .. (#name > 4 and name:sub(1,3) or name), function()
            SALV.setDensity(cap_i)
            showSelf()
        end)
    end
    local cur_r = SALV.getReward()
    for i, name in ipairs(SALV.REWARD_NAMES) do
        local cap_i = i
        addButton((i == cur_r and "* " or "") .. "Reward: " .. (#name > 4 and name:sub(1,3) or name), function()
            SALV.setReward(cap_i)
            showSelf()
        end)
    end
end

-- ─── SALV shims (for GM menu and scenario scripts) ───────────────────────────

SALV = SALV or {}
SALV.DENSITY_NAMES = _DENSITY_NAMES
SALV.REWARD_NAMES  = _REWARD_NAMES

function SALV.getDensity()    return WORLD.get("salvage", "density", 2)                       end
function SALV.setDensity(idx) WORLD.set("salvage", "density", math.max(1, math.min(3, idx))) end
function SALV.getReward()     return WORLD.get("salvage", "reward",  2)                       end
function SALV.setReward(idx)  WORLD.set("salvage", "reward",  math.max(1, math.min(3, idx))) end

