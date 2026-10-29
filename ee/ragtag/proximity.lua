-- ee/ragtag/proximity.lua
-- Ambient faction spawns scaled by player strength, zone danger, and reputation.
-- Spawned ships are leashed to their region: they recall to their spawn point when
-- the player leaves, and despawn after recall_timeout seconds if the player doesn't return.
-- Concord ships run a comms-first shake-down instead of attacking immediately.
--
-- Usage in a scenario:
--   require("ragtag/proximity.lua")
--   -- in init(), after VERSE.build():
--   PROX.init()
--   -- in update(delta):
--   PROX.update(delta)

PROX = PROX or {}

local U = 1000  -- world units per universe unit

PROX.config = {
    check_interval       = 8,     -- seconds between proximity checks
    region_cooldown      = 90,    -- min seconds between spawns per region
    global_cooldown      = 60,    -- min seconds between any spawn event
    max_active           = 4,     -- max simultaneous proximity-spawn ships (all zones)
    density_limit        = 3,     -- skip spawn if this many hostiles already within density_radius
    density_radius_u     = 10,    -- radius (u) for the density check
    spawn_lead_u         = 10,    -- u ahead of player toward region centre for spawn aim
    spawn_spread_u       = 4,     -- random spread (u) around spawn aim point
    station_exclusion_u  = 20,    -- no spawns within this radius of any station
    station_despawn_u    = 15,    -- despawn any patrol ship within this radius of a friendly station
    recall_timeout       = 120,   -- seconds before a recalled group despawns
    shakedown_timeout    = 45,    -- seconds before an unresponded Concord shake-down auto-resolves
    shakedown_scan_secs  = 30,    -- delay after player submits to inspection
    spawn_frequency      = 1.0,   -- spawn rate multiplier (0.5 = half as often, 2.0 = twice as often, exposed to GM)
}

-- Boneyard-specific relic war drone groups.
local _RELIC_GROUPS = {
    scout  = {"WX-Lindworm"},
    light  = {"WX-Lindworm", "WX-Lindworm"},
    medium = {"Stalker Q7", "WX-Lindworm"},
    heavy  = {"Stalker R7", "Stalker Q7"},
}

-- Zone definitions: each VERSE region name maps to a patrol config.
-- comms = "shakedown"  → Concord inspection before engaging
-- comms = "none"       → silent attack on sight (Relic, Hollow)
-- comms = nil          → default Corsair taunt
PROX.zones = {
    ["the Concord Core"]  = {faction = "Concord",  comms = "shakedown"},
    ["the Arbiter Line"]  = {faction = "Concord",  comms = "shakedown"},
    ["the Shroud"]        = {faction = "Corsairs"},
    ["Halcyon Rest"]      = {faction = "Corsairs"},
    ["the Gauntlet"]      = {faction = "Corsairs"},
    ["Blackwater Reach"]  = {faction = "Corsairs"},
    ["the Boneyard"]      = {faction = "Relic",    groups = _RELIC_GROUPS, comms = "none"},
    ["the Maw"]           = {faction = "Hollow",   comms = "none"},
}

-- Internal state — reset by PROX.init().
PROX._regions    = {}   -- region_name → VERSE region record
PROX._active     = {}   -- list of group records
PROX._region_cd  = {}   -- region_name → last spawn time
PROX._exclusions = {}   -- {x, y, r} in world units — no-spawn bubbles around stations
PROX._safe_stns  = {}   -- {x, y, r} in world units — Layer 3 despawn safety net (friendly stations)
PROX._next_check = 0
PROX._last_spawn = -99999

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function _cellKey(wx, wy)
    local cs = 18 * U
    return math.floor(wx / cs + 0.5) .. "," .. math.floor(wy / cs + 0.5)
end

-- Returns depth: >0 when inside the region, 0 at edge, <0 when outside.
local function _depthIn(wx, wy, region)
    local dx = wx - region.x * U
    local dy = wy - region.y * U
    return 1 - math.sqrt(dx * dx + dy * dy) / (region.r * U)
end

local function _playerTier()
    local n = RT.campaign and #(RT.campaign.upgrades or {}) or 0
    if n >= 5 then return 2 elseif n >= 2 then return 1 else return 0 end
end

local _TIER_LABELS = {"scout", "light", "medium", "heavy", "heavy"}

local function _pickStrength(region)
    local danger = region.danger or 0
    local zone_mod = (danger <= 0) and 0 or (danger == 1) and 1 or 2
    local tier = math.max(1, math.min(_playerTier() + zone_mod + 1, 5))
    return _TIER_LABELS[tier]
end

local function _firstPlayer()
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then return p end
    end
end

-- Fine = 50% of credits on hand, rounded to nearest 5cr, min 25cr.
-- Returns 0 if the crew can't afford a meaningful fine (< 50cr): warning only.
local function _concordFine()
    local credits = (RT.campaign and RT.campaign.credits) or 0
    if credits < 50 then return 0 end
    return math.max(25, math.floor(credits * 0.5 / 5 + 0.5) * 5)
end

-- Build the comms closure for a Concord shake-down group.
local function _makeShakedownComms(group)
    return function(src, tgt)
        if group.shakedown_done then
            setCommsMessage('"Move along, freighter."')
            return
        end

        local rep = RT.getReputation("Concord") or 0
        if rep > 20 then
            setCommsMessage('"Records check out. Safe travels."')
            group.shakedown_done    = true
            group.shakedown_hostile = false
            return
        end

        setCommsMessage('"Freighter, transponder check. State your business."')

        addCommsReply("Submit to inspection", function(src2, tgt2)
            group.shakedown_state      = "scanning"
            group.shakedown_resolve_at = getScenarioTime() + PROX.config.shakedown_scan_secs
            setCommsMessage('"Stand by. Scanning."')
        end)

        addCommsReply("Declare clean cargo", function(src2, tgt2)
            if rep >= 10 then
                setCommsMessage('"Records check out. Move along."')
                group.shakedown_done    = true
                group.shakedown_hostile = false
            else
                local fine = _concordFine()
                if fine == 0 then
                    setCommsMessage('"Watch yourself out here."')
                    group.shakedown_done    = true
                    group.shakedown_hostile = false
                else
                    RT.campaign.credits = RT.campaign.credits - fine
                    RT.shipLog("Concord citation: " .. fine .. " cr.", "#FF8040")
                    setCommsMessage('"Suspicious filing. ' .. fine .. ' cr citation. Move along."')
                    group.shakedown_done    = true
                    group.shakedown_hostile = false
                end
            end
        end)

        addCommsReply("I don't answer to Concord here.", function(src2, tgt2)
            setCommsMessage('"Wrong answer."')
            RT.campaign.flags = RT.campaign.flags or {}
            RT.campaign.flags.wanted = true
            RT.shipLog("Concord patrol: warrant issued.", "#FF4444")
            local player = _firstPlayer()
            if player then
                for _, cs in ipairs(group.ships) do
                    local s = RT.named[cs]
                    if RT.valid(s) then s:orderAttack(player) end
                end
            end
            group.shakedown_done    = true
            group.shakedown_hostile = true
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Spawn
-- ---------------------------------------------------------------------------

local function _spawnGroup(region_name, px, py)
    local region = PROX._regions[region_name]
    local zone   = PROX.zones[region_name]
    if not region or not zone then return end

    local strength  = _pickStrength(region)
    local grp_tbl   = zone.groups or DIR.GROUPS
    local templates = grp_tbl[strength]
    if not templates or #templates == 0 then return end

    -- Aim spawn lead_u ahead of the player toward region centre.
    local cx, cy = region.x * U, region.y * U
    local ddx, ddy = cx - px, cy - py
    local len = math.sqrt(ddx * ddx + ddy * ddy)
    if len > 0 then ddx, ddy = ddx / len, ddy / len else ddx, ddy = 1, 0 end
    local lead   = PROX.config.spawn_lead_u * U
    local spread = PROX.config.spawn_spread_u * U
    local sx = px + ddx * lead + (math.random() * 2 - 1) * spread * 0.5
    local sy = py + ddy * lead + (math.random() * 2 - 1) * spread * 0.5

    -- Clamp inside region boundary.
    local sdx, sdy = sx - cx, sy - cy
    local sdist = math.sqrt(sdx * sdx + sdy * sdy)
    local max_r = region.r * U * 0.95
    if sdist > max_r then
        sx = cx + sdx * max_r / sdist
        sy = cy + sdy * max_r / sdist
    end

    -- Layer A: reject spawn inside station exclusion zones.
    for _, ex in ipairs(PROX._exclusions) do
        local edx, edy = sx - ex.x, sy - ex.y
        if math.sqrt(edx * edx + edy * edy) < ex.r then return end
    end

    local now    = getScenarioTime()
    local wanted = RT.campaign.flags and RT.campaign.flags.wanted
    local is_shakedown = (zone.comms == "shakedown") and not wanted
    local player = _firstPlayer()

    -- Spawn ships.
    local ship_names = {}
    for _, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction(zone.faction)
        s:setPosition(sx + (math.random() * 2 - 1) * 500,
                      sy + (math.random() * 2 - 1) * 500)
        RT.register(s)
        DIR.registerKill(s)
        DIR.allowControl(s)

        if zone.comms ~= "none" and not is_shakedown then
            -- Corsairs and wanted-Concord: default taunt
            local zfac = zone.faction
            s:setCommsFunction(function(src, tgt)
                if zfac == "Corsairs" then
                    setCommsMessage('"Corsair space. Move along or stay forever."')
                elseif zfac == "Concord" then
                    setCommsMessage('"Concord patrol. You are a wanted vessel."')
                else
                    setCommsMessage('"You are in the wrong place."')
                end
            end)
        end

        table.insert(ship_names, s:getCallSign())
    end

    -- Initial orders.
    if is_shakedown then
        if player then
            local ppx, ppy = player:getPosition()
            for _, cs in ipairs(ship_names) do
                local s = RT.named[cs]
                if RT.valid(s) then s:orderFlyTowards(ppx, ppy) end
            end
        end
        RT.shipLog("[Concord] Patrol requesting transponder check. Open comms to respond.", "#8888FF")
    else
        if player then
            for _, cs in ipairs(ship_names) do
                local s = RT.named[cs]
                if RT.valid(s) then s:orderAttack(player) end
            end
        end
    end

    -- Build group record.
    local group = {
        ships              = ship_names,
        cell_key           = _cellKey(px, py),
        region_name        = region_name,
        spawn_x            = sx,
        spawn_y            = sy,
        mode               = "attack",    -- "attack" | "recalled"
        recalled           = false,
        recalled_at        = nil,
        despawn_at         = nil,         -- set for peaceful Concord departure
        -- Shake-down state (Concord only)
        is_shakedown       = is_shakedown,
        shakedown_done     = false,
        shakedown_hostile  = false,
        shakedown_state    = is_shakedown and "pending" or nil,
        shakedown_start    = is_shakedown and now or nil,
        shakedown_resolve_at = nil,
    }

    if is_shakedown then
        for _, cs in ipairs(ship_names) do
            local s = RT.named[cs]
            if RT.valid(s) then s:setCommsFunction(_makeShakedownComms(group)) end
        end
    end

    table.insert(PROX._active, group)
    PROX._region_cd[region_name] = now
    PROX._last_spawn = now

    DIR.emit("prox_spawned", {
        region   = region_name,
        faction  = zone.faction,
        strength = strength,
        count    = #ship_names,
    }, "normal")
end

-- ---------------------------------------------------------------------------
-- Watchdog: runs each check cycle on every active group.
-- Returns true if the group should be removed from PROX._active.
-- ---------------------------------------------------------------------------

local function _processGroup(group, now, player)
    -- Remove fully dead groups.
    local any_alive = false
    for _, cs in ipairs(group.ships) do
        if RT.valid(RT.named[cs]) then any_alive = true; break end
    end
    if not any_alive then
        if not group.recalled then
            RT.shipLog("[" .. group.region_name .. "] Area clear.", "#80FF80")
            DIR.emit("prox_cleared", {region = group.region_name}, "normal")
        end
        return true
    end

    -- Scheduled departure (peaceful Concord resolution).
    if group.despawn_at and now > group.despawn_at then
        for _, cs in ipairs(group.ships) do
            local s = RT.named[cs]
            if RT.valid(s) then s:destroy() end
        end
        return true
    end

    -- Shake-down timer resolution.
    if group.is_shakedown and not group.shakedown_done then
        if group.shakedown_state == "pending" and
           now - group.shakedown_start > PROX.config.shakedown_timeout then
            -- No response: rep determines outcome.
            local rep = RT.getReputation("Concord") or 0
            if rep < 0 then
                RT.campaign.flags = RT.campaign.flags or {}
                RT.campaign.flags.wanted = true
                RT.shipLog("Concord patrol: no response -- warrant issued.", "#FF4444")
                if player then
                    for _, cs in ipairs(group.ships) do
                        local s = RT.named[cs]
                        if RT.valid(s) then s:orderAttack(player) end
                    end
                end
                group.shakedown_hostile = true
            else
                RT.shipLog("[Concord] No response. Patrol moving on.", "#8888FF")
            end
            group.shakedown_done = true

        elseif group.shakedown_state == "scanning" and
               group.shakedown_resolve_at and now > group.shakedown_resolve_at then
            local fine = _concordFine()
            if fine > 0 then
                RT.campaign.credits = RT.campaign.credits - fine
                RT.shipLog("Concord inspection: " .. fine .. " cr fine.", "#FF8040")
            else
                RT.shipLog("[Concord] Scan complete. Move along.", "#8888FF")
            end
            group.shakedown_done    = true
            group.shakedown_hostile = false
        end
    end

    -- After a peaceful shake-down, schedule departure (fly back to spawn, then vanish).
    if group.is_shakedown and group.shakedown_done and
       not group.shakedown_hostile and not group.despawn_at then
        group.despawn_at = now + 30
        for _, cs in ipairs(group.ships) do
            local s = RT.named[cs]
            if RT.valid(s) then s:orderFlyTowards(group.spawn_x, group.spawn_y) end
        end
    end

    -- Layer 3: station proximity safety net.
    for _, cs in ipairs(group.ships) do
        local s = RT.named[cs]
        if RT.valid(s) then
            local ssx, ssy = s:getPosition()
            for _, stn in ipairs(PROX._safe_stns) do
                local edx, edy = ssx - stn.x, ssy - stn.y
                if math.sqrt(edx * edx + edy * edy) < stn.r then
                    s:destroy()
                    break
                end
            end
        end
    end

    -- Layers 1 & 2: region boundary and player-exit recall.
    local region = PROX._regions[group.region_name]
    if region and player then
        local ppx, ppy = player:getPosition()
        local player_in = _depthIn(ppx, ppy, region) > 0

        if not player_in and not group.recalled then
            -- Player left region: recall all ships to spawn point.
            group.mode      = "recalled"
            group.recalled  = true
            group.recalled_at = now
            for _, cs in ipairs(group.ships) do
                local s = RT.named[cs]
                if RT.valid(s) then s:orderFlyTowards(group.spawn_x, group.spawn_y) end
            end

        elseif player_in and group.recalled then
            -- Player back in region: resume attack.
            group.mode     = "attack"
            group.recalled = false
            group.recalled_at = nil
            for _, cs in ipairs(group.ships) do
                local s = RT.named[cs]
                if RT.valid(s) then s:orderAttack(player) end
            end
        end

        -- Layer 1: individual ships that crossed the boundary get sent back.
        if not group.recalled then
            for _, cs in ipairs(group.ships) do
                local s = RT.named[cs]
                if RT.valid(s) then
                    local ssx, ssy = s:getPosition()
                    if _depthIn(ssx, ssy, region) <= 0 then
                        s:orderFlyTowards(group.spawn_x, group.spawn_y)
                    end
                end
            end
        end

        -- Recall timeout: despawn if player hasn't returned.
        if group.recalled and group.recalled_at and
           now - group.recalled_at > PROX.config.recall_timeout then
            for _, cs in ipairs(group.ships) do
                local s = RT.named[cs]
                if RT.valid(s) then s:destroy() end
            end
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function PROX.init()
    PROX._regions    = {}
    PROX._active     = {}
    PROX._region_cd  = {}
    PROX._exclusions = {}
    PROX._safe_stns  = {}
    PROX._next_check = 0
    PROX._last_spawn = -99999

    for _, r in ipairs(VERSE.REGIONS) do
        if PROX.zones[r.name] then
            PROX._regions[r.name] = r
        end
    end

    local ex_r = PROX.config.station_exclusion_u * U
    local ds_r = PROX.config.station_despawn_u * U
    local friendly = {Independent = true, Concord = true}
    for _, stn in ipairs(VERSE.STATIONS) do
        local wx, wy = (stn.x or 0) * U, (stn.y or 0) * U
        -- No spawns near any station.
        table.insert(PROX._exclusions, {x = wx, y = wy, r = ex_r})
        -- Layer 3 safety net: only player-friendly stations.
        if friendly[stn.fac] then
            table.insert(PROX._safe_stns, {x = wx, y = wy, r = ds_r})
        end
    end
end

-- Manually add a no-spawn exclusion zone around a named station.
function PROX.addExclusion(station_cs, radius_u)
    local s = RT.named[station_cs]
    if RT.valid(s) then
        local wx, wy = s:getPosition()
        table.insert(PROX._exclusions, {x = wx, y = wy, r = (radius_u or 20) * U})
    end
end

-- Count hostile ships within density_radius of (px, py).
local function _nearbyHostiles(px, py)
    local r = PROX.config.density_radius_u * U
    local count = 0
    for _, obj in ipairs(getObjectsInRadius(px, py, r)) do
        local ok, fac = pcall(function() return obj:getFaction() end)
        if ok and (fac == "Corsairs" or fac == "Relic" or fac == "Hollow") then
            count = count + 1
        end
    end
    return count
end

function PROX.update(delta)
    local now = getScenarioTime()
    if now < PROX._next_check then return end
    PROX._next_check = now + PROX.config.check_interval

    if not RT.anyPlayerAlive() then return end

    local player = _firstPlayer()

    -- Run watchdog on all active groups (iterate backward for safe removal).
    local i = #PROX._active
    while i >= 1 do
        if _processGroup(PROX._active[i], now, player) then
            table.remove(PROX._active, i)
        end
        i = i - 1
    end

    -- Count total active ships across all groups.
    local active_ship_count = 0
    for _, g in ipairs(PROX._active) do
        active_ship_count = active_ship_count + #g.ships
    end
    if active_ship_count >= PROX.config.max_active then return end

    -- Global cooldown (adjusted by spawn frequency).
    local freq_mult = PROX.config.spawn_frequency or 1.0
    local adj_global = PROX.config.global_cooldown / freq_mult
    if now - PROX._last_spawn < adj_global then return end

    if not player then return end
    local px, py = player:getPosition()

    -- Density check: don't pile on if there are already enough nearby hostiles.
    if _nearbyHostiles(px, py) >= PROX.config.density_limit then return end

    -- Find the deepest eligible zone the player is in.
    local best_name, best_depth = nil, 0
    for name, region in pairs(PROX._regions) do
        local depth = _depthIn(px, py, region)
        if depth > 0 then
            local zone   = PROX.zones[name]
            local wanted = RT.campaign.flags and RT.campaign.flags.wanted

            -- Concord never spawns when the player is wanted (they stay in their zones
            -- but the wanted flag means the normal patrol system handles pursuit there).
            if zone.faction == "Concord" and wanted then goto skip end

            -- Region cooldown (frequency-adjusted).
            local freq_mult = PROX.config.spawn_frequency or 1.0
            local adj_region_cd = PROX.config.region_cooldown / freq_mult
            local last = PROX._region_cd[name] or -99999
            if now - last < adj_region_cd then goto skip end

            -- No active group already in the same cell.
            local cell = _cellKey(px, py)
            local cell_busy = false
            for _, g in ipairs(PROX._active) do
                if g.cell_key == cell then cell_busy = true; break end
            end
            if cell_busy then goto skip end

            if depth > best_depth then
                best_name, best_depth = name, depth
            end
        end
        ::skip::
    end

    if best_name then
        _spawnGroup(best_name, px, py)
    end
end
