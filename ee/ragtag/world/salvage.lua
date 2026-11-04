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
        if DIR then
            DIR.emit("pickup", {label = label, kind = kind_rec.kind, value = value, tier = tier,
                region = VERSE.region and VERSE.region.name or "open space"}, tier >= 2 and "normal" or "low")
        end
    end)
    return art
end

-- value_mult scales credit values (0.5/1.0/2.0 for low/medium/high reward).
-- Returns a list of spawned artifact objects so callers can track them.
local function _spawnClusterRaw(cx, cy, tier, rng, value_mult)
    value_mult = value_mult or 1.0
    local t    = VERSE.SALVAGE_TIERS[tier]
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

-- Pick a random spawn location anchored to an existing VERSE.SALVAGE entry.
-- Returns wx, wy (world units), tier.  Stays inside the active Drift.
local function _randomLocation()
    local rng = VERSE.rng_live
    local c   = rng.pick(VERSE.SALVAGE)
    local jx  = rng.float(-20, 20)
    local jy  = rng.float(-20, 20)
    local tier = math.max(0, math.min(3, c.tier + math.random(-1, 1)))
    return (c.x + jx) * VERSE.U, (c.y + jy) * VERSE.U, tier
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

local function _updateWrecks()
    local p = RT.player
    if not RT.valid(p) then return end
    for _, w in ipairs(VERSE.wrecks) do
        if not w.looted and RT.valid(w.ship) and RT.dist(p, w.ship) < 15000 and w.ship:isFullyScannedBy(p) then
            w.looted = true
            local x, y = w.ship:getPosition()
            _spawnClusterRaw(x, y, math.min(3, w.tier + 1), VERSE.rng_live)
            p:addToShipLog("Science: salvage located around " .. w.ship:getCallSign() .. ".", "#80C0FF")
            if DIR then DIR.emit("wreck_scanned", {wreck = w.ship:getCallSign(), tier = w.tier}, "low") end
        end
    end
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

function _P.init(state)
    state.clusters       = {}
    state.next_check     = 0
    state.next_wreck_check = 0
    state.density_idx    = WORLD.get("salvage", "density", 2)
    state.reward_idx     = WORLD.get("salvage", "reward",  2)
    state.pod_debt       = 0   -- fractional respawn debt from pod pickups

    local base   = #VERSE.SALVAGE
    local target = math.max(1, math.floor(base * _DENSITY_MULT[state.density_idx] + 0.5))
    local rng    = VERSE.rng_live

    for i = 1, target do
        local c  = VERSE.SALVAGE[((i - 1) % base) + 1]
        local jx = rng.float(-2, 2)
        local jy = rng.float(-2, 2)
        _spawnCluster(state, (c.x + jx) * VERSE.U, (c.y + jy) * VERSE.U, c.tier)
    end

    print(string.format("[Salvage] %d clusters spawned (density=%s reward=%s).",
        target, _DENSITY_NAMES[state.density_idx], _REWARD_NAMES[state.reward_idx]))
end

function _P.update(state, delta, now)
    if now >= state.next_wreck_check then
        state.next_wreck_check = now + 2
        _updateWrecks()
    end

    if now < state.next_check then return end
    state.next_check = now + _CHECK_INTERVAL

    local density_idx = WORLD.get("salvage", "density", 2)
    local reward_idx  = WORLD.get("salvage", "reward",  2)

    -- ── Reward changed: destroy all clusters and respawn with new values ────
    if reward_idx ~= state.reward_idx then
        for _, cl in ipairs(state.clusters) do _killCluster(cl) end
        state.clusters    = {}
        state.pod_debt    = 0
        state.reward_idx  = reward_idx
        -- Fall through: alive=0 so the density-reconcile block will respawn.
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
    end

    -- ── Normal top-up: spawn one cluster per _PODS_PER_RESPAWN collected ────
    -- Count pods that disappeared since last check as collected.
    local total_pods = 0
    for _, cl in ipairs(state.clusters) do
        for _, art in ipairs(cl.pods) do
            if RT.valid(art) then total_pods = total_pods + 1 end
        end
    end
    -- (pod_debt carries over; tracks fractional progress toward next respawn)

    -- Spawn to reach target if below (covers initial respawn after reward reset
    -- and gradual density-increase ramp).
    while alive < target do
        local wx, wy, tier = _randomLocation()
        _spawnCluster(state, wx, wy, tier)
        alive = alive + 1
        RT.shipLog(string.format("[Salvage] New debris cluster at grid %s.", JOBS.gridRef(wx, wy)), "#C0B070")
    end

    -- Also watch for organic collection and earn extra respawn debt.
    -- Compare against a stored pod count from previous check.
    if state.prev_pods ~= nil and state.prev_pods > total_pods then
        state.pod_debt = state.pod_debt + (state.prev_pods - total_pods)
    end
    state.prev_pods = total_pods

    while state.pod_debt >= _PODS_PER_RESPAWN do
        state.pod_debt = state.pod_debt - _PODS_PER_RESPAWN
        local wx, wy, tier = _randomLocation()
        _spawnCluster(state, wx, wy, tier)
        alive = alive + 1
        RT.shipLog(string.format("[Salvage] New debris cluster at grid %s.", JOBS.gridRef(wx, wy)), "#C0B070")
    end
end

function _P.cleanup(state)
    -- Leave pods in the world; just clear tracking.
    -- Re-enabling resets state entirely and respawns the full set.
    state.clusters = {}
end

WORLD.register(_P)

-- ─── SALV shims (for GM menu and scenario scripts) ───────────────────────────

SALV = SALV or {}
SALV.DENSITY_NAMES = _DENSITY_NAMES
SALV.REWARD_NAMES  = _REWARD_NAMES

function SALV.getDensity()    return WORLD.get("salvage", "density", 2)                       end
function SALV.setDensity(idx) WORLD.set("salvage", "density", math.max(1, math.min(3, idx))) end
function SALV.getReward()     return WORLD.get("salvage", "reward",  2)                       end
function SALV.setReward(idx)  WORLD.set("salvage", "reward",  math.max(1, math.min(3, idx))) end

-- Pod primitives exposed for other plugins (e.g. traffic ambient crate drops).
SALV.POD_KINDS = _POD_KINDS
SALV.spawnPod  = _spawnPod
