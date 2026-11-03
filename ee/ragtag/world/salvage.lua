-- ee/ragtag/world/salvage.lua
-- Dynamic salvage cluster system.
--
-- Spawns the initial salvage clusters from VERSE.SALVAGE on first tick, then
-- watches for pods being picked up and respawns new clusters elsewhere in the
-- active universe as they're collected.
--
-- Settings (all adjustable at runtime via GM menu):
--   density  1=Low (~half), 2=Medium (baseline), 3=High (~double)
--   reward   1=Low (50%), 2=Medium (100%), 3=High (200%) of base credit values
--
-- New cluster positions are chosen by picking a random anchor from VERSE.SALVAGE
-- and applying a ±20 map-unit jitter, keeping spawns inside the active Drift.

local _P = {}
_P.id             = "salvage"
_P.name           = "Salvage Clusters"
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

-- How often (seconds) the plugin checks collection counts.
local _CHECK_INTERVAL = 30

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Spawn one cluster, track returned artifacts, append to state.pods.
local function _spawnTracked(state, cx, cy, tier)
    local reward_idx = WORLD.get("salvage", "reward", 2)
    local arts       = VERSE.spawnCluster(cx, cy, tier, VERSE.rng_live, _REWARD_MULT[reward_idx])
    for _, art in ipairs(arts) do
        state.pods[#state.pods + 1] = art
    end
    return #arts
end

-- Pick a random spawn location anchored to an existing VERSE.SALVAGE entry.
-- Returns wx, wy (world units), tier.
local function _randomLocation()
    local rng     = VERSE.rng_live
    local anchors = VERSE.SALVAGE
    local c       = rng.pick(anchors)
    -- jitter ±20 map units; tier ±1 for variety
    local jx      = rng.float(-20, 20)
    local jy      = rng.float(-20, 20)
    local tier    = math.max(0, math.min(3, c.tier + math.random(-1, 1)))
    return (c.x + jx) * VERSE.U, (c.y + jy) * VERSE.U, tier
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

function _P.init(state)
    state.pods            = {}   -- artifact handles for all live pods
    state.next_check      = 0
    state.prev_count      = 0    -- pod count at last check, for delta calculation
    state.respawn_credits = 0    -- accumulated fractional respawn debt

    local density_idx = WORLD.get("salvage", "density", 2)
    local base        = #VERSE.SALVAGE
    local target      = math.max(1, math.floor(base * _DENSITY_MULT[density_idx] + 0.5))
    local rng         = VERSE.rng_live

    -- Spawn initial clusters. If target > base, wrap around the anchor list.
    for i = 1, target do
        local c  = VERSE.SALVAGE[((i - 1) % base) + 1]
        local jx = rng.float(-2, 2)
        local jy = rng.float(-2, 2)
        _spawnTracked(state, (c.x + jx) * VERSE.U, (c.y + jy) * VERSE.U, c.tier)
    end

    state.prev_count = #state.pods
    print(string.format("[Salvage] Spawned %d initial clusters (%d pods, density=%s, reward=%s).",
        target, #state.pods,
        _DENSITY_NAMES[density_idx] or "?",
        _REWARD_NAMES[WORLD.get("salvage", "reward", 2)] or "?"))
end

function _P.update(state, delta, now)
    if now < state.next_check then return end
    state.next_check = now + _CHECK_INTERVAL

    -- Count surviving pods and detect how many were collected since last check.
    local remaining = 0
    for _, art in ipairs(state.pods) do
        if RT.valid(art) then remaining = remaining + 1 end
    end

    local collected = math.max(0, state.prev_count - remaining)
    if collected > 0 then
        state.respawn_credits = state.respawn_credits + collected
    end
    state.prev_count = remaining

    -- Prune dead references to keep the list tidy.
    for i = #state.pods, 1, -1 do
        if not RT.valid(state.pods[i]) then table.remove(state.pods, i) end
    end

    -- Spawn one new cluster per _PODS_PER_RESPAWN collected.
    while state.respawn_credits >= _PODS_PER_RESPAWN do
        state.respawn_credits = state.respawn_credits - _PODS_PER_RESPAWN
        local wx, wy, tier = _randomLocation()
        local n = _spawnTracked(state, wx, wy, tier)
        RT.shipLog(string.format("[Salvage] New debris cluster detected at grid %s.",
            JOBS.gridRef(wx, wy)), "#C0B070")
        state.prev_count = state.prev_count + n
    end
end

function _P.cleanup(state)
    -- Leave spawned pods in the world; just stop tracking them.
    state.pods = {}
end

WORLD.register(_P)

-- ─── SALV shims (GM menu helpers) ────────────────────────────────────────────

SALV = SALV or {}
SALV.DENSITY_NAMES = _DENSITY_NAMES
SALV.REWARD_NAMES  = _REWARD_NAMES

function SALV.getDensity()         return WORLD.get("salvage", "density", 2)                           end
function SALV.setDensity(idx)      WORLD.set("salvage", "density", math.max(1, math.min(3, idx)))      end
function SALV.getReward()          return WORLD.get("salvage", "reward",  2)                           end
function SALV.setReward(idx)       WORLD.set("salvage", "reward",  math.max(1, math.min(3, idx)))      end
