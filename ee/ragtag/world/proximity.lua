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
    station_exclusion_u = 15,    -- no spawns within this radius of any station
    station_despawn_u   = 15,    -- despawn any patrol within this radius of a friendly station
    recall_timeout      = 120,   -- seconds before a recalled group despawns
    shakedown_timeout   = 45,    -- seconds before an ignored shake-down auto-resolves
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

-- Single Atlantis X23 destroyer for every strength tier — one very capable enforcer per spawn.
local _CONCORD_GROUPS = {
    scout  = {"Atlantis X23"},
    light  = {"Atlantis X23"},
    medium = {"Atlantis X23"},
    heavy  = {"Atlantis X23"},
}

-- Zone definitions: VERSE region name -> patrol config.
-- comms = "shakedown"  -> Concord inspection before engaging
-- comms = "none"       -> silent attack on sight (Relic, Hollow)
-- comms = nil          -> default faction taunt
-- max_active           -> per-zone override for concurrent ships (default: mode.max_active)
PROX = PROX or {}
PROX.zones = {
    ["the Concord Core"]  = {faction = "Concord",  comms = "shakedown", cooldown = 600, groups = _CONCORD_GROUPS, max_active = 1},
    ["the Arbiter Line"]  = {faction = "Concord",  comms = "shakedown", cooldown = 720, groups = _CONCORD_GROUPS, max_active = 1},
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

local _STALL_RESPONSES = {
    "Copy that. Initiating compliance procedures... still initiating.",
    "Transponder's been glitching since the last jump. Tech filed a ticket. We're in the queue.",
    "One moment, I need to find the manifest. It's definitely on this ship.",
    "Our compliance officer is currently indisposed. This may take a moment.",
    "We just did an inspection two sectors back. They gave us a sticker and everything.",
    "Could you repeat that? Our comms filter flagged your signal as potential spam.",
    "We're flagged as a pre-Compact heritage registry. Different documentation requirements. Very old forms.",
    "The captain is on a call with Concord Command right now. Can we reschedule?",
    "We switched cargo management systems last port and the data migration isn't quite done.",
    "Our cargo hold is sealed under a separate Concord court order. We'd need a counter-order to open it.",
    "Per regulation 7-Delta, we require that inspection request in writing before we can proceed.",
    "We're carrying live animals. The documentation is extensive and emotionally complex.",
    "According to the Compact of -- [static] -- section -- [static] -- we have the right to -- [static].",
    "Oh, is THIS the Concord checkpoint? We thought this was the scenic bypass.",
    "Your scanner might be miscalibrated. Our readings look fine from here. Have you tried restarting it?",
    "We're actually undercover. Can't say more than that. You understand.",
    "The manifest says 'miscellaneous.' What additional information do you require?",
    "We're running a little behind -- medical cargo. Medical-adjacent. It's for a doctor. A friend of a doctor.",
    "One moment -- our ship's lawyer is currently waking up.",
    "We have no idea what's in those containers either, honestly. That's what the inspection will tell us both.",
    "We're observing a registered religious fast that prohibits stopping between jumps. We can schedule something for next week.",
    "We were already inspected by a patrol called the Quiet Authority forty minutes ago. Can you check with them?",
    "Copy that. We're pulling over right now. Our pilot is just finishing a very important sandwich.",
    "Ah yes, the inspection. We've been expecting you. Please hold while we absolutely do not panic.",
    "Have you considered that perhaps YOUR ship is the one that needs inspecting?",
    "Our entire crew is currently testifying in an unrelated matter via remote link. We'll be right with you.",
    "We're under a non-disclosure agreement regarding the nature of this cargo. Ironically, it's with Concord.",
    "The hold is sealed. The seals are certified. The certifications are filed. The filing office is closed. It's a whole thing.",
    "Understood. We are cooperating fully. This is what full cooperation looks like.",
    "I'm going to be completely transparent with you -- and that's going to take some time.",
}


local _THREAT_MSGS = {
    "Prepare to have your ship remnants brought into custody.",
    "Your vessel is flagged for seizure. Resistance will be noted.",
    "Non-compliance logged. This stop is now a detention.",
    "Final notice. After this transmission, we are authorized to use force.",
    "Your cooperation window has closed. Stand by for boarding — or don't.",
    "Warrant confirmed. Weapons free.",
    "We've been waiting for you. This stop wasn't random.",
}

local function _makeShakedownComms(group)
    return function(src, tgt)
        if group.shakedown_done then
            if group.shakedown_hostile then
                setCommsMessage('"Concord Hostile. Your vessel is under arrest."')
            else
                setCommsMessage('"Move along."')
            end
            return
        end

        local rep    = RT.getReputation("Concord") or 0
        local player = _firstPlayer()
        local fine   = 100
        group._stall_count = group._stall_count or 0

        local function doGoHostile()
            group.shakedown_done    = true
            group.shakedown_hostile = true
            RT.campaign.flags = RT.campaign.flags or {}
            RT.campaign.flags.wanted = true
            RT.addReputation("Concord", -150, "escalated Concord inspection to hostile")
            RT.shipLog("[Concord] Warrant issued. Patrol is hostile.", "#FF4444")
            if player then
                for _, cs in ipairs(group.ships) do
                    local s = RT.named[cs]
                    if RT.valid(s) then
                        s:setCommsScript(""):setCommsFunction(function(src2, tgt2)
                            setCommsMessage('"Concord Hostile. Your vessel is under arrest."')
                        end)
                        s:setFaction("Concord Hostile")
                        s:orderAttack(player)
                    end
                end
            end
        end

        local function doThreat(after_fn)
            setCommsMessage('"' .. _THREAT_MSGS[math.random(#_THREAT_MSGS)] .. '"')
            addCommsReply("[Acknowledge.]", function(s3, t3)
                after_fn()
                setCommsMessage("The channel closes.")
            end)
        end

        local function doOutcome()
            if rep >= 500 then
                group.shakedown_done    = true
                group.shakedown_hostile = false
                setCommsMessage('"' .. tgt:getCallSign() .. ' — your record precedes you. The Concord values operators who keep their word. Safe travels."')
                addCommsReply("Acknowledged.", function() setCommsMessage("The channel closes.") end)

            elseif rep >= 200 then
                group.shakedown_done    = true
                group.shakedown_hostile = false
                setCommsMessage('"Records are clean. Carry on."')
                addCommsReply("Acknowledged.", function() setCommsMessage("The channel closes.") end)

            elseif rep >= 0 then
                group.shakedown_done    = true
                group.shakedown_hostile = false
                setCommsMessage('"Nothing flagged. Move along."')
                addCommsReply("Acknowledged.", function() setCommsMessage("The channel closes.") end)

            elseif rep >= -200 then
                setCommsMessage('"Your record raises some flags. Inspection fee: ' .. fine .. ' credits."')
                addCommsReply("Pay the fine (" .. fine .. " cr).", function(s2, t2)
                    RT.addCredits(-fine, "Concord inspection fee", player)
                    RT.addReputation("Concord", 100, "paid Concord inspection fee")
                    RT.shipLog("[Concord] Inspection fee: -" .. fine .. "cr. Standing improved.", "#8888FF")
                    group.shakedown_done    = true
                    group.shakedown_hostile = false
                    setCommsMessage('"Fee received. Move along."')
                    addCommsReply("Acknowledged.", function() setCommsMessage("The channel closes.") end)
                end)
                addCommsReply("Refuse to pay.", function(s2, t2)
                    doThreat(doGoHostile)
                end)

            else
                -- rep < -200: flagged for detainment
                setCommsMessage('"Your vessel is flagged for detainment. Prepare to be boarded."')
                addCommsReply("[Acknowledge.]", function(s2, t2)
                    doThreat(doGoHostile)
                end)
                addCommsReply("[Open fire first.]", function(s2, t2)
                    doGoHostile()
                    setCommsMessage("The channel closes.")
                end)
            end
        end

        -- Opening message reflects whether crew has stalled before
        if group._stall_count > 0 then
            setCommsMessage('"Concord patrol. We\'re still waiting on your compliance confirmation."')
        else
            setCommsMessage('"Concord patrol. All stop. Stand by for transponder verification."')
        end

        addCommsReply("Confirmed. Standing by.", function(s2, t2)
            doOutcome()
        end)

        if group._stall_count < 2 then
            addCommsReply(group._stall_count == 0
                    and "One moment — running checks on our end."
                    or  "Still working on it...", function(s2, t2)
                group._stall_count = group._stall_count + 1
                local line = _STALL_RESPONSES[math.random(#_STALL_RESPONSES)]
                local patience = group._stall_count >= 2
                    and '\n\n[Concord]: "Final warning. Comply immediately."'
                    or  '\n\n[Concord]: "Move it along."'
                setCommsMessage('"' .. line .. '"' .. patience)
                addCommsReply("Confirmed. Standing by.", function(s3, t3)
                    doOutcome()
                end)
                if group._stall_count < 2 then
                    addCommsReply("Still working on it...", function(s3, t3)
                        group._stall_count = group._stall_count + 1
                        setCommsMessage('"' .. _STALL_RESPONSES[math.random(#_STALL_RESPONSES)] .. '"'
                            .. '\n\n[Concord]: "Final warning. Comply immediately."')
                        addCommsReply("Confirmed. Standing by.", function(s4, t4)
                            doOutcome()
                        end)
                        addCommsReply("[Cut the channel.]", function(s4, t4)
                            doThreat(doGoHostile)
                        end)
                    end)
                end
                addCommsReply("[Cut the channel.]", function(s3, t3)
                    doThreat(doGoHostile)
                end)
            end)
        end

        addCommsReply("Tell them where to file their inspection.", function(s2, t2)
            doThreat(doGoHostile)
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
        and (RT.getReputation("Concord") or 0) >= -500

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
            s:setCommsScript(""):setCommsFunction(function(src, tgt)
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
        RT.shipLog("[Concord] Patrol detected in sector.", "#8888FF")
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
        jammer             = nil,
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
        shakedown_state    = is_shakedown and "approaching" or nil,
        shakedown_start    = nil,
    }

    if is_shakedown then
        for _, cs in ipairs(ship_names) do
            local s = RT.named[cs]
            if RT.valid(s) then s:setCommsScript(""):setCommsFunction(_makeShakedownComms(group)) end
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
        if group.jammer and RT.valid(group.jammer) then group.jammer:destroy() end
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
        if group.jammer and RT.valid(group.jammer) then group.jammer:destroy() end
        return true
    end

    if group.is_shakedown and not group.shakedown_done then
        -- Approach interception: deploy jammer and hail when within 5U and outside station exclusions
        if group.shakedown_state == "approaching" and player then
            local px2, py2 = player:getPosition()
            local near_station = false
            for _, ex in ipairs(st.exclusions) do
                local dx, dy = px2 - ex.x, py2 - ex.y
                if math.sqrt(dx * dx + dy * dy) < ex.r then
                    near_station = true; break
                end
            end
            if not near_station then
                for _, cs in ipairs(group.ships) do
                    local s = RT.named[cs]
                    if RT.valid(s) then
                        local ssx, ssy = s:getPosition()
                        local dx, dy = ssx - px2, ssy - py2
                        if math.sqrt(dx * dx + dy * dy) < 5 * U then
                            -- Lead placement: if player is warping, drop jammer 0.5U ahead.
                            local jx, jy = px2, py2
                            local ok_v, vx, vy = pcall(function() return player:getVelocity() end)
                            if ok_v and vx then
                                local spd = math.sqrt(vx * vx + vy * vy)
                                if spd > 500 then   -- well above impulse max (~50 wu/s)
                                    jx = px2 + (vx / spd) * 0.5 * U
                                    jy = py2 + (vy / spd) * 0.5 * U
                                end
                            end
                            local jammer = WarpJammer()
                            jammer:setPosition(jx, jy)
                            jammer:setRange(1 * U)
                            jammer:setFaction("Concord")
                            jammer:setDescriptions("Concord WarpJammer",
                                "Active Concord warp suppression emitter. Disrupts warp drive within 1U. Destroy the emitter to clear the field.")
                            pcall(function() jammer:setHull(100):setHullMax(100) end)
                            group.jammer          = jammer
                            group.shakedown_state = "pending"
                            group.shakedown_start = now
                            s:openCommsTo(player)
                            RT.shipLog("[Concord] Standby for inspection. Incoming patrol comms on Relay.", "#8888FF")
                            break
                        end
                    end
                end
            end
        end

        -- Pursuit and escape: keep ships on the player; resolve if player gets 10U clear
        if group.shakedown_state == "pending" and player then
            local px2, py2 = player:getPosition()
            local min_dist = math.huge
            for _, cs in ipairs(group.ships) do
                local s = RT.named[cs]
                if RT.valid(s) then
                    local ssx, ssy = s:getPosition()
                    local dx, dy = ssx - px2, ssy - py2
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < min_dist then min_dist = dist end
                end
            end
            if min_dist > 10 * U then
                RT.addReputation("Concord", -100, "evaded Concord inspection")
                RT.shipLog("[Concord] Vessel fled inspection. Concord standing reduced.", "#FF8040")
                group.shakedown_done    = true
                group.shakedown_hostile = false
            else
                for _, cs in ipairs(group.ships) do
                    local s = RT.named[cs]
                    if RT.valid(s) then s:orderFlyTowards(px2, py2) end
                end
            end
        end

        -- Jammer destroyed by crew during active inspection: rep penalty, free to go.
        if group.shakedown_state == "pending" and not group.shakedown_done and
           group.jammer and not RT.valid(group.jammer) then
            RT.addReputation("Concord", -75, "destroyed Concord warp jammer")
            RT.shipLog("[Concord] Jammer destroyed. Concord standing reduced.", "#FF8040")
            group.shakedown_done    = true
            group.shakedown_hostile = false
        end

        -- Timeout: crew ignored the inspection hail entirely.
        if group.shakedown_state == "pending" and not group.shakedown_done and
           now - group.shakedown_start > _cfg("shakedown_timeout") then
            local rep = RT.getReputation("Concord") or 0
            if rep < 0 then
                RT.campaign.flags = RT.campaign.flags or {}
                RT.campaign.flags.wanted = true
                RT.addReputation("Concord", -100, "ignored Concord inspection")
                RT.shipLog("[Concord] No response — warrant issued. Patrol is hostile.", "#FF4444")
                if player then
                    for _, cs in ipairs(group.ships) do
                        local s = RT.named[cs]
                        if RT.valid(s) then
                            s:setCommsScript(""):setCommsFunction(function(src2, tgt2)
                                setCommsMessage('"Concord Hostile. Your vessel is under arrest."')
                            end)
                            s:setFaction("Concord Hostile")
                            s:orderAttack(player)
                        end
                    end
                end
                group.shakedown_hostile = true
            else
                RT.shipLog("[Concord] No response. Patrol moving on.", "#8888FF")
            end
            group.shakedown_done = true
        end
    end

    if group.is_shakedown and group.shakedown_done and
       not group.shakedown_hostile and not group.despawn_at then
        group.despawn_at = now + _cfg("concord_despawn")
        for _, cs in ipairs(group.ships) do
            local s = RT.named[cs]
            if RT.valid(s) then s:orderFlyTowards(group.spawn_x, group.spawn_y) end
        end
        if group.jammer and RT.valid(group.jammer) then
            group.jammer:destroy()
            group.jammer = nil
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
            if group.jammer and RT.valid(group.jammer) then group.jammer:destroy() end
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
        if ok and (fac == "Corsairs" or fac == "Relic" or fac == "Hollow" or fac == "Concord Hostile") then
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

            -- Per-zone active ship cap (zone.max_active overrides mode default).
            local zone_cap = zone.max_active or mode.max_active
            if (zone_ships[name] or 0) >= zone_cap then goto skip end

            -- Per-zone cooldown (zone.cooldown shortened by mode frequency).
            -- Corsair rep scales patrol aggressiveness: -200 → 30% shorter, -400 → 50% shorter.
            local last = state.region_cd[name] or -99999
            local effective_cooldown = zone.cooldown
            if zone.faction == "Corsairs" then
                local crep = RT.getReputation("Corsairs") or 0
                if     crep <= -400 then effective_cooldown = effective_cooldown * 0.5
                elseif crep <= -200 then effective_cooldown = effective_cooldown * 0.7
                end
            end
            if now - last < effective_cooldown / mode.freq then goto skip end

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
        if group.jammer and RT.valid(group.jammer) then group.jammer:destroy() end
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
