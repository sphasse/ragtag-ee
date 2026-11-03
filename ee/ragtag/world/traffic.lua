-- ee/ragtag/world/traffic.lua
-- Freighter traffic and ambient crate drops.
--
-- Spawns initial freighter routes on first tick, then drives the update loop
-- that was previously in VERSE.update(). Density setting reconciles immediately:
-- a change kills all live ships and respawns at the new count.
--
-- Settings:
--   density  1=Low (~half), 2=Medium (baseline), 3=High (~double)

local _P = {}
_P.id              = "traffic"
_P.name            = "Station Traffic"
_P.default_enabled = true
_P.defaults = {
    density = 2,  -- 1=Low, 2=Medium, 3=High
}

-- ─── Constants ────────────────────────────────────────────────────────────────

local _DENSITY_NAMES = {"Low", "Medium", "High"}
local _DENSITY_MULT  = {0.5, 1.0, 2.0}

-- ─── Internal helpers ─────────────────────────────────────────────────────────

local function _routeCount(route, density_idx)
    return math.max(1, math.floor(route.count * _DENSITY_MULT[density_idx] + 0.5))
end

local function _spawnAll(density_idx)
    local rng = VERSE.rng_live
    for _, route in ipairs(VERSE.ROUTES) do
        local count = _routeCount(route, density_idx)
        for _ = 1, count do VERSE.spawnTransport(route, rng) end
    end
end

local function _killAll()
    for _, rec in ipairs(VERSE.transports) do
        if RT.valid(rec.ship) then
            pcall(function() rec.ship:destroy() end)
        end
    end
    VERSE.transports    = {}
    VERSE.respawn_queue = {}
    VERSE.ambient_pods  = {}
    VERSE.next_ambient  = getScenarioTime() + 300
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

function _P.init(state)
    state.density_idx = WORLD.get("traffic", "density", 2)
    state.next_check  = 0

    _spawnAll(state.density_idx)

    print(string.format("[Traffic] Spawned %d routes (density=%s).",
        #VERSE.ROUTES, _DENSITY_NAMES[state.density_idx]))
end

function _P.update(state, delta, now)
    local density_idx = WORLD.get("traffic", "density", 2)

    if density_idx ~= state.density_idx then
        _killAll()
        state.density_idx = density_idx
        _spawnAll(density_idx)
        print(string.format("[Traffic] Density changed to %s; traffic respawned.", _DENSITY_NAMES[density_idx]))
    end

    if now >= state.next_check then
        state.next_check = now + 2
        VERSE.updateTransports(now)
        VERSE.updateAmbient(now)
    end
end

function _P.cleanup(state)
    _killAll()
end

WORLD.register(_P)

-- ─── TRAFF shims (for GM menu and scenario scripts) ──────────────────────────

TRAFF = TRAFF or {}
TRAFF.DENSITY_NAMES = _DENSITY_NAMES

function TRAFF.getDensity()    return WORLD.get("traffic", "density", 2)                        end
function TRAFF.setDensity(idx) WORLD.set("traffic", "density", math.max(1, math.min(3, idx))) end
