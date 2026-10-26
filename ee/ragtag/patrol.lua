-- ee/ragtag/patrol.lua
-- Dynamic hostile patrol spawning based on player position in danger zones.
--
-- As the player moves into a hostile region, patrol groups spawn near them.
-- Difficulty scales with depth (edge = easier, centre = harder).  Once a
-- patrol group is wiped out, that grid cell stays safe for cell_cooldown
-- seconds, giving the crew breathing room to work or retreat.
--
-- Usage in a scenario:
--   require("ragtag/patrol.lua")
--   -- in init(), after VERSE.build():
--   PATROL.init()
--   -- in update(delta):
--   PATROL.update(delta)
--
-- Zones are Corsair-only by default; call PATROL.addZone() before PATROL.init()
-- to add or override zones for other factions.

PATROL = PATROL or {}

PATROL.config = {
    check_interval  = 8,    -- seconds between proximity checks
    cell_size       = 18,   -- universe units per cleared-area cell
    cell_cooldown   = 360,  -- seconds a cleared cell stays safe
    region_cooldown = 90,   -- minimum seconds between consecutive spawns per region
    max_active      = 3,    -- max simultaneous patrol groups (all zones combined)
    spawn_lead_u    = 10,   -- u ahead of player (toward region centre) to aim spawn
    spawn_spread_u  = 4,    -- ±u random spread around spawn aim point
}

-- danger level → {outer (depth<0.33), mid (0.33-0.67), inner (>0.67)} strength
PATROL.DEPTH_STRENGTH = {
    [1] = {"scout",  "light",  "medium"},
    [2] = {"light",  "medium", "heavy"},
    [3] = {"medium", "heavy",  "heavy"},
}

-- Zone table: region_name → {faction=...}.
-- Populated with Corsair defaults; override with PATROL.addZone().
PATROL.zones = {
    ["the Gauntlet"]     = {faction = "Corsairs"},
    ["Blackwater Reach"] = {faction = "Corsairs"},
}

PATROL._regions    = {}   -- name → VERSE region record (set by init())
PATROL._active     = {}   -- list of {ships={callsign,...}, cell_key, region_name}
PATROL._cleared    = {}   -- cell_key → cleared_at (scenario time)
PATROL._region_cd  = {}   -- region_name → last_spawn_at
PATROL._next_check = 0

local U = 1000   -- 1 universe unit = 1000 world units

-- Add or override a zone before calling PATROL.init().
function PATROL.addZone(region_name, faction)
    PATROL.zones[region_name] = {faction = faction}
end

function PATROL.init()
    PATROL._regions = {}
    for _, r in ipairs(VERSE.REGIONS) do
        if PATROL.zones[r.name] then
            PATROL._regions[r.name] = r
        end
    end
end

-- -------------------------------------------------------------------------
-- Internal helpers
-- -------------------------------------------------------------------------

local function cellKey(wx, wy)
    local cs = PATROL.config.cell_size * U
    local cx = math.floor(wx / cs + 0.5)
    local cy = math.floor(wy / cs + 0.5)
    return cx .. "," .. cy
end

-- Returns 0 (at edge) to 1 (at centre); negative when outside the region.
local function depthIn(wx, wy, region)
    local dx, dy = wx - region.x * U, wy - region.y * U
    return 1 - math.sqrt(dx * dx + dy * dy) / (region.r * U)
end

local function pickStrength(region, depth)
    local danger = math.min(region.danger or 1, 3)
    local levels = PATROL.DEPTH_STRENGTH[danger]
    if depth < 0.33 then return levels[1]
    elseif depth < 0.67 then return levels[2]
    else return levels[3] end
end

local function spawnGroup(region_name, px, py)
    local region = PATROL._regions[region_name]
    local zone   = PATROL.zones[region_name]
    if not region or not zone then return end

    local depth    = depthIn(px, py, region)
    local strength = pickStrength(region, depth)
    local templates = DIR.GROUPS[strength]
    if not templates then return end

    -- Aim spawn toward region centre, lead_u ahead of the player.
    local cx, cy = region.x * U, region.y * U
    local dx, dy = cx - px, cy - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then dx, dy = dx / len, dy / len else dx, dy = 1, 0 end
    local lead = PATROL.config.spawn_lead_u * U
    local half_spread = PATROL.config.spawn_spread_u * U * 0.5
    local sx = px + dx * lead + random(-half_spread, half_spread)
    local sy = py + dy * lead + random(-half_spread, half_spread)
    -- Clamp inside region bounds (keep 5% margin so ships don't spawn at the rim).
    local sdx, sdy = sx - cx, sy - cy
    local sdist = math.sqrt(sdx * sdx + sdy * sdy)
    local max_r = region.r * U * 0.95
    if sdist > max_r then
        sx = cx + sdx * max_r / sdist
        sy = cy + sdy * max_r / sdist
    end

    local cell  = cellKey(px, py)
    local names = {}
    for i, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction(zone.faction)
        s:setPosition(sx + random(-500, 500), sy + random(-500, 500))
        RT.register(s)
        DIR.registerKill(s)
        DIR.allowControl(s)
        s:setCommsFunction(function(src, tgt)
            setCommsMessage("\"Corsair space, freelancer. Move along or stay forever.\"")
        end)
        table.insert(names, s:getCallSign())
    end
    DIR.orderGroup(names, "attack")

    table.insert(PATROL._active, {ships = names, cell_key = cell, region_name = region_name})
    PATROL._region_cd[region_name] = getScenarioTime()

    DIR.emit("patrol_spawned", {
        region   = region_name,
        strength = strength,
        count    = #names,
        depth    = math.floor(depth * 100),
    }, "normal")
end

-- -------------------------------------------------------------------------
-- Per-frame update — call from scenario update(delta)
-- -------------------------------------------------------------------------

function PATROL.update(delta)
    local now = getScenarioTime()
    if now < PATROL._next_check then return end
    PATROL._next_check = now + PATROL.config.check_interval

    if not RT.anyPlayerAlive() then return end

    -- Sweep active patrols: mark cells cleared when an entire group is dead.
    for i = #PATROL._active, 1, -1 do
        local pat = PATROL._active[i]
        local alive = false
        for _, cs in ipairs(pat.ships) do
            if RT.valid(RT.find(cs)) then alive = true; break end
        end
        if not alive then
            PATROL._cleared[pat.cell_key] = now
            table.remove(PATROL._active, i)
            RT.shipLog("[" .. pat.region_name .. "] Area clear.", "#80FF80")
            DIR.emit("patrol_cleared", {region = pat.region_name}, "normal")
        end
    end

    if #PATROL._active >= PATROL.config.max_active then return end

    -- For zone triggering, use the player deepest inside any zone.
    -- Iterate all players; pick position from the deepest one.
    local best_name, best_depth, spawn_px, spawn_py = nil, 0, 0, 0
    for _, p in ipairs(RT.players) do
        if not RT.valid(p) then goto next_player end
        local px, py = p:getPosition()
        for name, region in pairs(PATROL._regions) do
            local depth = depthIn(px, py, region)
            if depth > 0 then
                -- Region cooldown
                local last = PATROL._region_cd[name] or -99999
                if now - last < PATROL.config.region_cooldown then goto continue end
                -- Cell cooldown
                local cell = cellKey(px, py)
                local cleared_at = PATROL._cleared[cell]
                if cleared_at and (now - cleared_at) < PATROL.config.cell_cooldown then goto continue end
                -- No active patrol already in this cell
                for _, pat in ipairs(PATROL._active) do
                    if pat.cell_key == cell then goto continue end
                end
                if depth > best_depth then
                    best_name, best_depth = name, depth
                    spawn_px, spawn_py = px, py
                end
            end
            ::continue::
        end
        ::next_player::
    end

    if best_name then
        spawnGroup(best_name, spawn_px, spawn_py)
    end
end
