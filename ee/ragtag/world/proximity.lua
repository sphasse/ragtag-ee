-- ee/ragtag/world/proximity.lua
-- Ambient faction proximity spawns as a WORLD plugin.
-- Wraps the PROX global for GM-menu compatibility (PROX.getModeName,
-- PROX.cycleMode, PROX.addExclusion still work from the scenario).
--
-- Spawn frequency is controlled by a GM button that cycles four modes:
--   None / Low / Medium (default) / High
-- Jobboard lock (JOBS.config.jobboard_locked) suppresses all new spawns
-- but the watchdog still cleans up existing groups.

local _P = {}
_P.id   = "proximity"
_P.name = "Proximity Spawns"

local U = 1000  -- world units per universe unit

-- ── Spawn modes ─────────────────────────────────────────────────────────────
-- freq: cooldown divisor (higher = shorter cooldowns = more spawns).
-- max_active: ship cap across all zones.
-- density: hostile ships within density_radius before a spawn is suppressed.
local _SPAWN_MODES = {
    {name = "None",   freq = 0,   max_active =  0, density =  0},
    {name = "Low",    freq = 0.5, max_active =  6, density =  3},
    {name = "Medium", freq = 1.0, max_active = 12, density =  6},
    {name = "High",   freq = 2.0, max_active = 24, density = 12},
}

-- ── Config defaults ──────────────────────────────────────────────────────────
_P.defaults = {
    check_interval      = 8,     -- seconds between proximity checks
    density_radius_u    = 10,    -- radius (u) for the per-zone density check
    spawn_lead_u        = 10,    -- u ahead of player for spawn aim
    spawn_spread_u      = 4,     -- random spread (u) around spawn aim point
    station_exclusion_u = 20,    -- no spawns within this radius of any station
    station_despawn_u   = 15,    -- despawn any patrol within this radius of a friendly station
    recall_timeout      = 120,   -- seconds before a recalled group despawns
    shakedown_timeout   = 45,    -- seconds before an unresponded shake-down auto-resolves
    shakedown_scan_secs = 30,    -- delay after player submits to inspection
    concord_despawn     = 120,   -- seconds after peaceful Concord resolution before ships vanish
    default_zone_mode   = 3,     -- starting mode for each zone (1=None 2=Low 3=Medium 4=High)
}

-- ── Static data ──────────────────────────────────────────────────────────────

local _PATROL_NAMES = {
    Concord = {
        "Dortmunder",   "Long Arm",      "Due Process",   "Standing Order", "Iron Mandate",
        "Hard Line",    "Last Warning",  "Quiet Authority","Fine Print",    "Common Law",
        "By The Book",  "Public Order",  "Clear Channel", "The Compact",   "Right of Way",
        "Warrant Served","No Exception", "Border Notice", "Terms of Service","The Arbiter",
    },
    Corsairs = {
        "Iron Hand",    "Toll Taker",    "Night Watch",   "Knife's Edge",  "Dead Weight",
        "Rough Rider",  "Bloodhound",    "Dark Passage",  "Last Stop",     "The Collector",
        "Chain Breaker","Gravel Voice",  "Broken Wing",   "Rust & Bone",   "Border Watch",
        "Razorbill",    "Red Watch",     "Scar Tissue",   "Grim Patrol",   "Hard Collection",
    },
    Hollow = {
        "The Patience", "Null Signal",   "What Remains",  "Absent Light",  "The Quiet",
        "Echo Null",    "No Return",     "The Hunger",    "Empty Passage", "Far Signal",
        "Last Transmission", "Signal Ghost", "The Watching", "Deep Null",  "Void Thought",
        "Absence",      "What Follows",  "No Memory",     "Still Hollow",  "Fragment Seven",
    },
}

local _RELIC_GROUPS = {
    scout  = {"WX-Lindworm"},
    light  = {"WX-Lindworm", "WX-Lindworm"},
    medium = {"Stalker Q7", "WX-Lindworm"},
    heavy  = {"Stalker R7", "Stalker Q7"},
}

-- Zone definitions: VERSE region name -> patrol config.
-- comms = "shakedown"  -> Concord inspection before engaging
-- comms = "none"       -> silent attack on sight (Relic, Hollow)
-- comms = nil          -> default faction taunt
PROX = PROX or {}
PROX.zones = {
    ["the Concord Core"]  = {faction = "Concord",  comms = "shakedown", cooldown = 300},
    ["the Arbiter Line"]  = {faction = "Concord",  comms = "shakedown", cooldown = 360},
    ["the Shroud"]        = {faction = "Corsairs",                       cooldown = 240},
    ["Halcyon Rest"]      = {faction = "Corsairs",                       cooldown = 240},
    ["the Gauntlet"]      = {faction = "Corsairs",                       cooldown = 180},
    ["Blackwater Reach"]  = {faction = "Corsairs",                       cooldown = 180},
    ["the Boneyard"]      = {faction = "Relic",    groups = _RELIC_GROUPS, comms = "none", cooldown = 180},
    ["the Maw"]           = {faction = "Hollow",   comms = "none",      cooldown = 120},
}

-- ── Internal helpers ─────────────────────────────────────────────────────────

local function _cfg(key)
    return WORLD.get("proximity", key, _P.defaults[key])
end

local function _cellKey(wx, wy)
    local cs = 18 * U
    return math.floor(wx / cs + 0.5) .. "," .. math.floor(wy / cs + 0.5)
end

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
    local danger   = region.danger or 0
    local zone_mod = (danger <= 0) and 0 or (danger == 1) and 1 or 2
    local tier     = math.max(1, math.min(_playerTier() + zone_mod + 1, 5))
    return _TIER_LABELS[tier]
end

local function _firstPlayer()
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then return p end
    end
end

local function _concordFine()
    local credits = (RT.campaign and RT.campaign.credits) or 0
    if credits < 50 then return 0 end
    return math.max(25, math.floor(credits * 0.5 / 5 + 0.5) * 5)
end

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
            group.shakedown_resolve_at = getScenarioTime() + _cfg("shakedown_scan_secs")
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

-- ── Spawn ────────────────────────────────────────────────────────────────────

local function _spawnGroup(st, region_name, px, py)
    local region = st.regions[region_name]
    local zone   = PROX.zones[region_name]
    if not region or not zone then return end

    local strength  = _pickStrength(region)
    local grp_tbl   = zone.groups or DIR.GROUPS
    local templates = grp_tbl[strength]
    if not templates or #templates == 0 then return end

    local player = _firstPlayer()
    if not player then return end

    local heading   = player:getHeading()
    local angle_rad = math.rad(heading - 90)
    local ddx = math.cos(angle_rad)
    local ddy = math.sin(angle_rad)

    local lead   = _cfg("spawn_lead_u") * U
    local spread = _cfg("spawn_spread_u") * U
    local sx = px + ddx * lead + (math.random() * 2 - 1) * spread * 0.5
    local sy = py + ddy * lead + (math.random() * 2 - 1) * spread * 0.5

    -- Clamp inside region boundary.
    local cx, cy = region.x * U, region.y * U
    local sdx, sdy = sx - cx, sy - cy
    local sdist = math.sqrt(sdx * sdx + sdy * sdy)
    local max_r = region.r * U * 0.95
    if sdist > max_r then
        sx = cx + sdx * max_r / sdist
        sy = cy + sdy * max_r / sdist
    end

    -- Layer A: reject spawn inside station exclusion zones.
    for _, ex in ipairs(st.exclusions) do
        local edx, edy = sx - ex.x, sy - ex.y
        if math.sqrt(edx * edx + edy * edy) < ex.r then return end
    end

    local now    = getScenarioTime()
    local wanted = RT.campaign.flags and RT.campaign.flags.wanted
    local is_shakedown = (zone.comms == "shakedown") and not wanted

    local ship_names = {}
    local _name_pool  = _PATROL_NAMES[zone.faction]
    local _used_names = {}
    for _, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction(zone.faction)
        s:setPosition(sx + (math.random() * 2 - 1) * 500,
                      sy + (math.random() * 2 - 1) * 500)
        if _name_pool then
            local avail = {}
            for _, n in ipairs(_name_pool) do
                if not _used_names[n] then avail[#avail+1] = n end
            end
            if #avail > 0 then
                local picked = avail[math.random(#avail)]
                s:setCallSign(picked)
                _used_names[picked] = true
            end
        end
        RT.register(s)
        DIR.registerKill(s)
        DIR.allowControl(s)

        local zdanger = zone.danger or 0
        s:onDestruction(function(self, instigator)
            local dx, dy = self:getPosition()
            local count = math.random(1, 3)
            for _ = 1, count do
                local arch   = JOBS.SALVAGE_ARCHETYPES[math.random(#JOBS.SALVAGE_ARCHETYPES)]
                local min_cr = 5 + zdanger * 2
                local max_cr = 10 + math.floor(zdanger * 2.5)
                local reward = math.random(min_cr, max_cr)
                local ox = (math.random() * 2 - 1) * 2000
                local oy = (math.random() * 2 - 1) * 2000
                local pod = SupplyDrop():setFaction("Independent")
                                        :setCallSign("Debris")
                                        :setPosition(dx + ox, dy + oy)
                pod:setDescriptions("Salvage Container", arch.cargo)
                pod:onPickUp(function(pod_self, pl)
                    if RT.valid(pl) then
                        RT.addCredits(reward, "salvage: " .. arch.cargo, pl)
                        RT.shipLog("[Salvage] Recovered " .. arch.cargo .. ": +" .. reward .. "cr.", "#80FF80")
                    end
                end)
            end
        end)

        if zone.comms ~= "none" and not is_shakedown then
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

    local group = {
        ships              = ship_names,
        cell_key           = _cellKey(px, py),
        region_name        = region_name,
        spawn_x            = sx,
        spawn_y            = sy,
        mode               = "attack",
        recalled           = false,
        recalled_at        = nil,
        despawn_at         = nil,
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

    table.insert(st.active, group)
    st.region_cd[region_name] = now
    st.last_spawn = now

    DIR.emit("prox_spawned", {
        region   = region_name,
        faction  = zone.faction,
        strength = strength,
        count    = #ship_names,
    }, "normal")
end

-- ── Group watchdog ────────────────────────────────────────────────────────────
-- Returns true when the group should be removed from st.active.

local function _processGroup(st, group, now, player)
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

    if group.despawn_at and now > group.despawn_at then
        for _, cs in ipairs(group.ships) do
            local s = RT.named[cs]
            if RT.valid(s) then s:destroy() end
        end
        return true
    end

    if group.is_shakedown and not group.shakedown_done then
        if group.shakedown_state == "pending" and
           now - group.shakedown_start > _cfg("shakedown_timeout") then
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

    if group.is_shakedown and group.shakedown_done and
       not group.shakedown_hostile and not group.despawn_at then
        group.despawn_at = now + _cfg("concord_despawn")
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
            for _, stn in ipairs(st.safe_stns) do
                local edx, edy = ssx - stn.x, ssy - stn.y
                if math.sqrt(edx * edx + edy * edy) < stn.r then
                    s:destroy()
                    break
                end
            end
        end
    end

    -- Layers 1 & 2: region boundary and player-exit recall.
    local region = st.regions[group.region_name]
    if region and player then
        local ppx, ppy = player:getPosition()
        local player_in = _depthIn(ppx, ppy, region) > 0

        if not player_in and not group.recalled then
            group.mode        = "recalled"
            group.recalled    = true
            group.recalled_at = now
            for _, cs in ipairs(group.ships) do
                local s = RT.named[cs]
                if RT.valid(s) then s:orderFlyTowards(group.spawn_x, group.spawn_y) end
            end

        elseif player_in and group.recalled then
            group.mode        = "attack"
            group.recalled    = false
            group.recalled_at = nil
            for _, cs in ipairs(group.ships) do
                local s = RT.named[cs]
                if RT.valid(s) then s:orderAttack(player) end
            end
        end

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

        if group.recalled and group.recalled_at and
           now - group.recalled_at > _cfg("recall_timeout") then
            for _, cs in ipairs(group.ships) do
                local s = RT.named[cs]
                if RT.valid(s) then s:destroy() end
            end
            return true
        end
    end

    return false
end

local function _nearbyHostiles(px, py)
    local r = _cfg("density_radius_u") * U
    local count = 0
    for _, obj in ipairs(getObjectsInRadius(px, py, r)) do
        local ok, fac = pcall(function() return obj:getFaction() end)
        if ok and (fac == "Corsairs" or fac == "Relic" or fac == "Hollow") then
            count = count + 1
        end
    end
    return count
end

-- ── Plugin interface ──────────────────────────────────────────────────────────

function _P.init(state)
    state.regions    = {}
    state.active     = {}
    state.region_cd  = {}
    state.zone_modes = {}   -- region_name -> mode index (1=None 2=Low 3=Medium 4=High)
    state.exclusions = {}
    state.safe_stns  = {}
    state.next_check = 0

    local default_mode = _cfg("default_zone_mode")
    for _, r in ipairs(VERSE.REGIONS) do
        if PROX.zones[r.name] then
            state.regions[r.name]    = r
            state.zone_modes[r.name] = default_mode
        end
    end

    local ex_r     = _cfg("station_exclusion_u") * U
    local ds_r     = _cfg("station_despawn_u") * U
    local friendly = {Independent = true, Concord = true}
    for _, stn in ipairs(VERSE.STATIONS) do
        local wx, wy = (stn.x or 0) * U, (stn.y or 0) * U
        table.insert(state.exclusions, {x = wx, y = wy, r = ex_r})
        if friendly[stn.fac] then
            table.insert(state.safe_stns, {x = wx, y = wy, r = ds_r})
        end
    end
end

function _P.update(state, delta, now)
    -- Jobboard lock suppresses new spawns; watchdog still cleans up groups.
    local spawning_ok = not (JOBS.config and JOBS.config.jobboard_locked)

    if now < state.next_check then return end
    state.next_check = now + _cfg("check_interval")

    if not RT.anyPlayerAlive() then return end

    local player = _firstPlayer()

    local i = #state.active
    while i >= 1 do
        if _processGroup(state, state.active[i], now, player) then
            table.remove(state.active, i)
        end
        i = i - 1
    end

    if not spawning_ok then return end
    if not player then return end

    local px, py = player:getPosition()

    -- Count active ships per zone for per-zone cap checks.
    local zone_ships = {}
    for _, g in ipairs(state.active) do
        local zn = g.region_name
        zone_ships[zn] = (zone_ships[zn] or 0) + #g.ships
    end

    -- Find the deepest zone the player is in where all per-zone conditions pass.
    local best_name, best_depth = nil, 0
    for name, region in pairs(state.regions) do
        local depth = _depthIn(px, py, region)
        if depth > 0 then
            local zone     = PROX.zones[name]
            local mode_idx = state.zone_modes[name] or _cfg("default_zone_mode")
            local mode     = _SPAWN_MODES[mode_idx]
            local wanted   = RT.campaign.flags and RT.campaign.flags.wanted

            -- Zone disabled or Concord suppressed on wanted status.
            if mode.freq == 0 then goto skip end
            if zone.faction == "Concord" and wanted then goto skip end

            -- Per-zone active ship cap.
            if (zone_ships[name] or 0) >= mode.max_active then goto skip end

            -- Per-zone cooldown (zone.cooldown shortened by mode frequency).
            local last = state.region_cd[name] or -99999
            if now - last < zone.cooldown / mode.freq then goto skip end

            -- Per-zone density: don't pile on if enough hostiles already nearby.
            if _nearbyHostiles(px, py) >= mode.density then goto skip end

            -- One group per grid cell at a time.
            local cell = _cellKey(px, py)
            local cell_busy = false
            for _, g in ipairs(state.active) do
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
        _spawnGroup(state, best_name, px, py)
    end
end

function _P.cleanup(state)
    for _, group in ipairs(state.active or {}) do
        for _, cs in ipairs(group.ships) do
            local s = RT.named[cs]
            if RT.valid(s) then s:destroy() end
        end
    end
end

-- ── GM menu ───────────────────────────────────────────────────────────────────

local _ZONE_ORDER = {
    "the Concord Core", "the Arbiter Line",
    "the Shroud", "Halcyon Rest", "the Gauntlet", "Blackwater Reach",
    "the Boneyard", "the Maw",
}
local _ZONE_LABEL = {
    ["the Concord Core"]  = "Concord Core",
    ["the Arbiter Line"]  = "Arbiter Line",
    ["the Shroud"]        = "The Shroud",
    ["Halcyon Rest"]      = "Halcyon Rest",
    ["the Gauntlet"]      = "The Gauntlet",
    ["Blackwater Reach"]  = "Blackwater Reach",
    ["the Boneyard"]      = "The Boneyard",
    ["the Maw"]           = "The Maw",
}

function _P.gmMenu(addButton, showSelf)
    local on = WORLD.isEnabled("proximity")
    addButton(_P.name .. ": " .. (on and "ON" or "OFF"), function()
        if on then WORLD.disable("proximity") else WORLD.enable("proximity") end
        showSelf()
    end)
    addButton("Spawn Zones...", function()
        local showZoneListMenu
        local showZoneDetailMenu

        showZoneListMenu = function()
            clearGMFunctions()
            addGMFunction("< Back to Proximity", showSelf)
            for _, zn in ipairs(_ZONE_ORDER) do
                local label     = _ZONE_LABEL[zn] or zn
                local mode_idx  = PROX.getZoneMode(zn)
                local cap_zn    = zn
                addGMFunction(label .. ": " .. (PROX.MODE_NAMES[mode_idx] or "?"), function()
                    showZoneDetailMenu(cap_zn)
                end)
            end
        end

        showZoneDetailMenu = function(zone_name)
            clearGMFunctions()
            addGMFunction("< Back to Zones", showZoneListMenu)
            local label   = _ZONE_LABEL[zone_name] or zone_name
            local cur_idx = PROX.getZoneMode(zone_name)
            for i, mode_name in ipairs(PROX.MODE_NAMES) do
                local cap_i  = i
                local cap_zn = zone_name
                addGMFunction((i == cur_idx and "* " or "") .. mode_name, function()
                    PROX.setZoneMode(cap_zn, cap_i)
                    showZoneDetailMenu(cap_zn)
                end)
            end
        end

        showZoneListMenu()
    end)
end

-- ── PROX shims (GM-menu and scenario compatibility) ───────────────────────────
-- Scenario code reads PROX.MODE_NAMES and calls PROX.getZoneMode /
-- PROX.setZoneMode for per-zone spawn control.

PROX.MODE_NAMES = {"None", "Low", "Medium", "High"}

-- Returns the mode index for a named zone (1=None 2=Low 3=Medium 4=High).
function PROX.getZoneMode(zone_name)
    local st = WORLD._state["proximity"]
    if not st or not st.zone_modes then
        return _cfg("default_zone_mode")
    end
    return st.zone_modes[zone_name] or _cfg("default_zone_mode")
end

-- Sets the mode index for a named zone.
function PROX.setZoneMode(zone_name, idx)
    local st = WORLD._state["proximity"]
    if not st or not st.zone_modes then return end
    st.zone_modes[zone_name] = math.max(1, math.min(idx, #_SPAWN_MODES))
end

-- Manually add a no-spawn exclusion zone around a named station.
function PROX.addExclusion(station_cs, radius_u)
    local st = WORLD._state["proximity"]
    if not st then return end
    local s = RT.named[station_cs]
    if RT.valid(s) then
        local wx, wy = s:getPosition()
        table.insert(st.exclusions, {x = wx, y = wy, r = (radius_u or 20) * U})
    end
end

-- ── Register ──────────────────────────────────────────────────────────────────

WORLD.register(_P)
