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
    shakedown_timeout   = 60,    -- seconds of comms silence before an ignored shake-down goes hostile
    concord_despawn     = 120,   -- seconds after peaceful Concord resolution before ships vanish
    default_zone_mode   = 3,     -- starting mode for each zone (1=None 2=Low 3=Medium 4=High)
    control_tint        = true,  -- tint each faction's patrol zones on the long-range radars (PROX.showControl)
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
    -- The Shroud's own crews, who never took Blackwater's terms.
    ["Shroud Raiders"] = {
        "Fog Bank",     "Blind Corner",  "No Return Fare","Grey Wolf",     "Low Visibility",
        "Smoke Signal", "Lost Bearing",  "Static Bite",   "The Undertow",  "Pale Rider",
        "Wrong Turn",   "Cold Wake",     "Mist Walker",   "Silent Partner","Dead Reckoning",
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
    ["the Escrow Marches"] = {faction = "Concord", comms = "shakedown", cooldown = 720, groups = _CONCORD_GROUPS, max_active = 1},
    -- The Shroud and the Deep Shroud: the Shroud Raiders, hostile whatever the Corsair standing.
    ["the Shroud"]        = {faction = "Shroud Raiders",                 cooldown = 240},
    ["Halcyon Rest"]      = {faction = "Shroud Raiders",                 cooldown = 240},
    ["the Deep Shroud"]   = {faction = "Shroud Raiders",                 cooldown = 240},
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

-- Patrol strength follows the upgrades of the ship the patrol is sent after.
local function _playerTier(player)
    local n = #RT.upgrades(player)
    if n >= 5 then return 2 elseif n >= 2 then return 1 else return 0 end
end

local _TIER_LABELS = {"scout", "light", "medium", "heavy", "heavy"}

-- Default patrol hulls by strength (zones may set their own `groups`). Faction only changes
-- allegiance, not hulls.
PROX = PROX or {}
PROX.GROUPS = {
    scout  = {"MT52 Hornet"},
    light  = {"Adder MK5", "MT52 Hornet"},
    medium = {"Phobos T3", "Adder MK5", "MT52 Hornet"},
    heavy  = {"Nirvana R5", "Phobos T3", "Adder MK5", "Adder MK5"},
}

local function _pickStrength(region, player)
    local danger   = region.danger or 0
    local zone_mod = (danger <= 0) and 0 or (danger == 1) and 1 or 2
    local tier     = math.max(1, math.min(_playerTier(player) + zone_mod + 1, 5))
    return _TIER_LABELS[tier]
end

-- Several player ships: every patrol hunts ONE ship, `group.target` (the ship whose presence
-- spawned it). That ship's standing decides how the patrol behaves, it is the ship that is
-- stopped, fined, jammed and attacked, and it alone pays for the outcome. Other ships are left
-- alone unless they fire (kills are charged to whoever made them). If the target dies or leaves
-- the zone while another player ship is in it, the patrol takes the nearest one (see _retarget).
-- Zone cooldowns and caps are shared: flying together draws no more patrols than flying alone.

-- The primary ship (the first one alive): only the GM "Trigger Spawn Now" button uses it.
local function _firstPlayer()
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then return p end
    end
end

-- Every player ship alive, in a random order, so no ship is always the one a patrol picks.
local function _livePlayers()
    local out = {}
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then out[#out + 1] = p end
    end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

local function _inRegion(ship, region)
    if not region or not RT.valid(ship) then return false end
    local x, y = ship:getPosition()
    return _depthIn(x, y, region) > 0
end

-- True when any ship of the list is alive. Groups keep the ship ENTITIES they spawned, never
-- callsigns: two patrols can draw the same name from the pool.
local function _anyAlive(ships)
    for _, s in ipairs(ships) do
        if RT.valid(s) then return true end
    end
    return false
end

-- Position of the group (its first live ship), or nil.
local function _groupPos(group)
    for _, s in ipairs(group.ships) do
        if RT.valid(s) then return s:getPosition() end
    end
end

-- The live target of a group, or nil.
local function _target(group)
    return RT.valid(group.target) and group.target or nil
end

-- A log line for the patrol's target (everyone when it has none).
local function _log(group, msg, color)
    local t = _target(group)
    if t then t:addToShipLog(msg, color) else RT.shipLog(msg, color) end
end

-- Send the group after its target: a peaceful shake-down flies to it, anything else attacks.
-- A shake-down that is over and on its way home is left alone.
local function _engage(group)
    local t = _target(group)
    if not t or group.despawn_at then return end
    local peaceful = group.is_shakedown and not group.shakedown_hostile
    local tx, ty = t:getPosition()
    for _, s in ipairs(group.ships) do
        if RT.valid(s) then
            if peaceful then s:orderFlyTowards(tx, ty) else s:orderAttack(t) end
        end
    end
end

-- Keep the group's target, or hand it the nearest player ship in its zone when the target is
-- dead or has left. A shake-down that has stopped its ship (pending) keeps it while it lives:
-- running from the stop is handled by the shake-down itself. A new target of a shake-down is
-- stopped from scratch and judged by its own standing; a hostile patrol stays hostile.
local function _retarget(st, group)
    local region = st.regions[group.region_name]
    local t = _target(group)
    if t and (group.shakedown_state == "pending" or _inRegion(t, region)) then return end
    local gx, gy = _groupPos(group)
    if not gx or not region then return end
    local best, best_d
    for _, p in ipairs(RT.players) do
        if p ~= t and _inRegion(p, region) then
            local px, py = p:getPosition()
            local d = (px - gx) ^ 2 + (py - gy) ^ 2
            if not best_d or d < best_d then best, best_d = p, d end
        end
    end
    if not best then return end
    group.target = best
    if group.shakedown_state == "pending" and not group.shakedown_done then
        -- The stopped ship died: start over on the new one.
        if RT.valid(group.jammer) then group.jammer:destroy() end
        group.jammer, group.shakedown_state, group.shakedown_hailed = nil, "approaching", false
        group._stall_count, group.last_comms_activity = 0, nil
    end
    PROX.clearCombatJammers(group.cjam)   -- those jammers were braking the old target
    if not group.recalled then _engage(group) end
end

-- ── Combat warp jammers ───────────────────────────────────────────────────────
-- Hostile Concord ships (patrols spawned hostile by low reputation, shakedowns gone hostile,
-- arc fleets) drop a warp jammer behind the player when within PROX.JAMMER.trigger_u. Like the
-- shakedown jammer it reaches only 1U (a limit of the tech) and brakes the ship: it rides
-- 0.25U behind the player, forcing impulse to 0 every tick, until the ship is stopped; then it
-- stays where it is. Each ship has one jammer at a time: it lasts `lifetime` seconds, and the
-- ship can drop the next `cooldown` seconds after the last. Every Concord jammer has `hull`
-- hull: two hits from a 6-damage beam destroy it.
PROX.JAMMER = {trigger_u = 5, cooldown = 120, lifetime = 120, range_u = 1, hull = 10, stop_speed = 25}

local function _behind(player, j)
    local px, py = player:getPosition()
    local h = math.rad(player:getHeading())
    j:setPosition(px - math.sin(h) * 0.25 * U, py + math.cos(h) * 0.25 * U)
    if j.components.physics then j.components.physics.velocity = {0, 0} end
end

-- A Concord warp jammer at (x, y), at rest, with the shared low hull.
function PROX.makeJammer(x, y, range_u, desc)
    local j = WarpJammer():setPosition(x, y)
    if j.components.physics then j.components.physics.velocity = {0, 0} end
    j:setRange((range_u or PROX.JAMMER.range_u) * U)
    j:setFaction("Concord Hostile")
    j:setDescriptions("Concord WarpJammer", desc or
        "Active Concord warp suppression emitter. Lightly built: a couple of beam hits will knock it out.")
    pcall(function() j:setHullMax(PROX.JAMMER.hull):setHull(PROX.JAMMER.hull) end)
    return j
end

-- Per-tick driver (call every frame: the brake must run each tick). `holder` is a table owned
-- by the caller (one per group/fleet, start it as {}); `ships` is a list of ship entities.
-- The holder is a list of {ship, jammer, at, holding}, one per ship that has dropped a jammer.
-- trigger_u (optional): how close a ship must be to drop one (default PROX.JAMMER.trigger_u).
function PROX.tickCombatJammers(holder, ships, player, now, trigger_u)
    local cfg = PROX.JAMMER
    local trigger = (trigger_u or cfg.trigger_u) * U
    -- Expire jammers (including those of ships that have since died).
    for _, rec in ipairs(holder) do
        if rec.jammer and (now - rec.at >= cfg.lifetime or not RT.valid(rec.jammer)) then
            if RT.valid(rec.jammer) then rec.jammer:destroy() end
            rec.jammer = nil
        end
    end
    if not RT.valid(player) then return end
    -- Brake: a freshly dropped jammer rides behind the ship and holds impulse at 0 until stopped.
    for _, rec in ipairs(holder) do
        if rec.holding and RT.valid(rec.jammer) then
            pcall(function() player:commandImpulse(0) end)
            _behind(player, rec.jammer)
            local vx, vy = 0, 0
            pcall(function() vx, vy = player:getVelocity() end)
            if math.sqrt(vx * vx + vy * vy) < cfg.stop_speed then rec.holding = false end
        elseif rec.holding then
            rec.holding = false
        end
    end
    local px, py = player:getPosition()
    for _, s in ipairs(ships) do
        if RT.valid(s) then
            local rec
            for _, r in ipairs(holder) do
                if r.ship == s then rec = r; break end
            end
            if not rec or (not rec.jammer and now - rec.at >= cfg.cooldown) then
                local sx, sy = s:getPosition()
                local dx, dy = sx - px, sy - py
                if dx * dx + dy * dy < trigger ^ 2 then
                    local j = PROX.makeJammer(px, py)
                    _behind(player, j)
                    if not rec then rec = {ship = s}; holder[#holder + 1] = rec end
                    rec.jammer, rec.at, rec.holding = j, now, true
                    RT.sound("jammer_engage", {now = true})
                    player:addToShipLog("[Science] " .. s:getCallSign() .. " dropped a warp jammer on us. Engines are braking. Two beam hits will take it out.", "#FF8040")
                end
            end
        end
    end
end

function PROX.clearCombatJammers(holder)
    holder = holder or {}
    for i = #holder, 1, -1 do
        local rec = holder[i]
        if rec.jammer and RT.valid(rec.jammer) then rec.jammer:destroy() end
        holder[i] = nil
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
    "Your standing is confirmed hostile. Weapons free.",
    "We've been waiting for you. This stop wasn't random.",
}

local _HOSTILE_LINES = {
    "Standby for disassembly.",
    "Your hull has been reclassified as scrap.",
    "Prepare for unscheduled decommissioning.",
    "You've been designated a navigation hazard.",
    "Your flight plan has been permanently cancelled.",
    "Transmitting termination order now.",
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

        -- The patrol talks only to the ship it is stopping, and judges it by its own standing.
        local player = _target(group)
        if not player or RT.playerShip(src) ~= player then
            setCommsMessage('"This stop is not about you. Keep clear and keep moving."')
            return
        end
        -- The stopped ship's Relay opened the channel — reset the 60-second compliance timer.
        group.last_comms_activity = getScenarioTime()
        local rep    = RT.concordSees(player)   -- a fake transponder code reads as clean
        local fine   = 100
        group._stall_count = group._stall_count or 0

        local function doGoHostile()
            group.shakedown_done    = true
            group.shakedown_hostile = true
            RT.addReputation("Concord", -150, "escalated Concord inspection to hostile", player)
            player:addToShipLog("[Concord] Inspection escalated. Patrol is hostile.", "#FF4444")
            if player then
                for _, s in ipairs(group.ships) do
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
                setCommsMessage('"' .. src:getCallSign() .. ' — your record precedes you. The Concord values operators who keep their word. Safe travels."')
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
                    if RT.credits(player) < fine then
                        -- Can't pay: the stop is still open (pay later, refuse, or let it time out).
                        setCommsMessage('"Your account doesn\'t cover it. Find the credits or we do this the hard way."')
                        addCommsReply("Refuse to pay.", function(s3, t3) doThreat(doGoHostile) end)
                        return
                    end
                    RT.addCredits(-fine, "Concord inspection fee", player)
                    RT.addReputation("Concord", 100, "paid Concord inspection fee", player)
                    player:addToShipLog("[Concord] Inspection fee: -" .. fine .. "cr. Standing improved.", "#8888FF")
                    group.shakedown_done    = true
                    group.shakedown_hostile = false
                    setCommsMessage('"Fee received. Move along."')
                    addCommsReply("Acknowledged.", function() setCommsMessage("The channel closes.") end)
                end)
                addCommsReply("Refuse to pay.", function(s2, t2)
                    doThreat(doGoHostile)
                end)

            else
                -- rep < -200: no negotiation
                setCommsMessage('"You\'re not welcome in Concord space. ' .. _HOSTILE_LINES[math.random(#_HOSTILE_LINES)] .. '"')
                doGoHostile()
                addCommsReply("[Cut channel.]", function(s2, t2)
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
                group.last_comms_activity = getScenarioTime()  -- delay option buys another minute
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
                        group.last_comms_activity = getScenarioTime()  -- each stall buys another minute
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

-- Spawn a patrol in `region_name` sent after `player` (the ship at px, py).
local function _spawnGroup(st, region_name, player, px, py)
    local region = st.regions[region_name]
    local zone   = PROX.zones[region_name]
    if not region or not zone then return end
    if not RT.valid(player) then return end

    local strength  = _pickStrength(region, player)
    local grp_tbl   = zone.groups or PROX.GROUPS
    local templates = grp_tbl[strength]
    if not templates or #templates == 0 then return end

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

    local now         = getScenarioTime()
    local concord_rep = RT.concordSees(player)   -- a fake transponder code reads as clean
    local is_shakedown = (zone.comms == "shakedown") and concord_rep >= -200

    -- Concord patrols spawning against a hostile-rep player use the hostile
    -- faction so they can be targeted immediately.
    local spawn_faction = zone.faction
    if zone.faction == "Concord" and not is_shakedown then
        spawn_faction = "Concord Hostile"
    end

    local ships = {}   -- the entities of this group
    local _name_pool  = _PATROL_NAMES[zone.faction]
    local _used_names = {}
    for _, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction(spawn_faction)
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
        if zone.faction == "Concord" then
            if is_shakedown then
                s:setDescriptions("Concord warship.", "Concord patrol interceptor. Active interdiction assignment.")
                s:setDescriptionForScanState("fullscan", "Traffic interdiction patrol. Authorized to stop and board civilian vessels. If you're running a hot manifest, now is the time to find a different route.")
            else
                s:setDescriptions("Concord warship.", "Concord enforcement vessel. Hostile-standing response.")
                s:setDescriptionForScanState("fullscan", "Your Concord standing has this patrol treating you as hostile. It is here for you specifically. Recommend evasive action.")
            end
            s:setScanningParameters(1, 2)
        end

        RT.register(s)
        RT.reportKills(s)

        local zdanger = region.danger or 0
        RT.onKill(s, function(self, instigator)
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
                        pl:addToShipLog("[Salvage] Recovered " .. arch.cargo .. ": +" .. reward .. "cr.", "#80FF80")
                    end
                end)
            end
        end)

        if zone.faction == "Relic" and VERSE.droneComms then
            s:setCommsScript(""):setCommsFunction(VERSE.droneComms)   -- base64, threat or welcome
        elseif zone.comms ~= "none" and not is_shakedown then
            local zfac = zone.faction
            s:setCommsScript(""):setCommsFunction(function(src, tgt)
                if zfac == "Corsairs" then
                    setCommsMessage('"Corsair space. Move along or stay forever."')
                elseif zfac == "Shroud Raiders" then
                    setCommsMessage('"Blackwater\'s rules don\'t reach in here. Cut your engines and open your hold."')
                elseif zfac == "Concord" then
                    setCommsMessage('"Concord patrol. Your standing with Concord is hostile. Stand down."')
                else
                    setCommsMessage('"You are in the wrong place."')
                end
            end)
        end

        table.insert(ships, s)
    end

    if is_shakedown then
        local ppx, ppy = player:getPosition()
        for _, s in ipairs(ships) do
            if RT.valid(s) then s:orderFlyTowards(ppx, ppy) end
        end
        player:addToShipLog("[Concord] Patrol detected in sector.", "#8888FF")
    else
        for _, s in ipairs(ships) do
            if RT.valid(s) then s:orderAttack(player) end
        end
    end

    local group = {
        ships              = ships,
        target             = player,   -- the ship this patrol hunts (see _retarget)
        jammer             = nil,
        concord            = (zone.faction == "Concord"),
        cjam               = {},   -- combat jammers (PROX.tickCombatJammers)
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
        for _, s in ipairs(ships) do
            if RT.valid(s) then s:setCommsScript(""):setCommsFunction(_makeShakedownComms(group)) end
        end
    end

    table.insert(st.active, group)
    st.region_cd[region_name] = now
    st.last_spawn = now

    RT.emit("prox_spawned", {
        region   = region_name,
        faction  = zone.faction,
        strength = strength,
        count    = #ships,
    }, "normal")
end

-- ── Group watchdog ────────────────────────────────────────────────────────────
-- Returns true when the group should be removed from st.active.

local function _processGroup(st, group, now)
    if not _anyAlive(group.ships) then
        if group.jammer and RT.valid(group.jammer) then group.jammer:destroy() end
        if not group.recalled then
            _log(group, "[" .. group.region_name .. "] Area clear.", "#80FF80")
            RT.emit("prox_cleared", {region = group.region_name}, "normal")
        end
        return true
    end

    if group.despawn_at and now > group.despawn_at then
        for _, s in ipairs(group.ships) do
            if RT.valid(s) then s:destroy() end
        end
        if group.jammer and RT.valid(group.jammer) then group.jammer:destroy() end
        return true
    end

    _retarget(st, group)
    local player = _target(group)   -- the ship this patrol hunts (nil: none alive)

    -- The stopped ship is gone and no other ship is in the zone to stop instead: the stop is
    -- over and nobody is charged for it (a standing change with no ship would hit the primary).
    if group.is_shakedown and not group.shakedown_done and group.shakedown_state == "pending"
       and not player then
        group.shakedown_done    = true
        group.shakedown_hostile = false
    end

    if group.is_shakedown and not group.shakedown_done then
        -- Dynamic rep watch: if rep drops below -200 while this group is on a shakedown
        -- approach (before jammer deploy), flip them to hostile immediately.
        if player and RT.concordSees(player) < -200
           and group.shakedown_state == "approaching" then
            player:addToShipLog("[Concord] Relations deteriorated. Patrol is now hostile.", "#FF4444")
            for _, s2 in ipairs(group.ships) do
                if RT.valid(s2) then
                    s2:setFaction("Concord Hostile")
                    if player then s2:orderAttack(player) end
                end
            end
            group.is_shakedown    = false
            group.shakedown_done  = true
            group.shakedown_hostile = true
        end

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
                for _, s in ipairs(group.ships) do
                    if RT.valid(s) then
                        local cs = s:getCallSign()
                        local ssx, ssy = s:getPosition()
                        local dx, dy = ssx - px2, ssy - py2
                        if math.sqrt(dx * dx + dy * dy) < 5 * U then
                            -- Spawn jammer 0.25U BEHIND player at zero velocity.
                            -- Dynamic physics; commandImpulse(0) every tick slows the player.
                            local head_rad = math.rad(player:getHeading())
                            local jammer = PROX.makeJammer(
                                px2 - math.sin(head_rad) * 0.25 * U,
                                py2 + math.cos(head_rad) * 0.25 * U, 1,
                                "Active Concord warp suppression emitter. Disrupts warp drive within 1U. Destroy the emitter to clear the field.")
                            group.jammer           = jammer
                            group.hailing_ship     = s    -- the entity that will hail
                            group.hailing_name     = cs
                            group.shakedown_state  = "pending"
                            group.shakedown_start  = now
                            group.shakedown_hailed = false
                            -- Sound: jammer engages, interference bed while it holds.
                            RT.sound("jammer_engage", {now = true})
                            group.sound_loop = "prox_jammer_" .. cs .. "_" .. math.floor(now)
                            RT.soundLoop(group.sound_loop, "jammer_bed", 10, function()
                                return RT.valid(group.jammer) and not group.shakedown_done
                            end)
                            -- Broadcast fires immediately with jammer deploy; hail fires once stopped
                            _log(group, "[" .. cs .. "] We are Concord interceptor " .. cs .. ". You are being warp jammed and we have weapons targeted. We are in the area checking transponder codes and cargo. Respond to our hail and comply in a timely manner or suffer the consequences. You have one minute.", "#8888FF")
                            local _msg = "CONCORD INTERCEPTION — " .. cs .. "\nWarp jammer deployed. Weapons targeted.\nRespond to hail within 60 seconds or face consequences."
                            local _key = "concord_insp_" .. math.floor(now)
                            for _, _st in ipairs({"Helms","Weapons","Engineering","Engineering+","Science","Relay","Tactical","Operations","AltRelay"}) do
                                player:addCustomMessage(_st, _key .. _st, _msg)
                            end
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
            for _, s in ipairs(group.ships) do
                if RT.valid(s) then
                    local ssx, ssy = s:getPosition()
                    local dx, dy = ssx - px2, ssy - py2
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < min_dist then min_dist = dist end
                end
            end
            if min_dist > 10 * U then
                RT.addReputation("Concord", -100, "evaded Concord inspection", player)
                _log(group, "[Concord] Vessel fled inspection. Concord standing reduced.", "#FF8040")
                group.shakedown_done    = true
                group.shakedown_hostile = false
            else
                for _, s in ipairs(group.ships) do
                    if RT.valid(s) then s:orderFlyTowards(px2, py2) end
                end
            end
        end

        -- commandImpulse(0), speed check, and hail run every tick in _P.update
        -- (before the rate-limit gate) so the player is halted quickly.

        -- Jammer destroyed by crew during active inspection: rep penalty, free to go.
        if group.shakedown_state == "pending" and not group.shakedown_done and
           group.jammer and not RT.valid(group.jammer) then
            RT.addReputation("Concord", -50, "destroyed Concord warp jammer", player)
            _log(group, "[Concord] Jammer destroyed. Concord standing reduced.", "#FF8040")
            group.shakedown_done    = true
            group.shakedown_hostile = false
        end

        -- Timeout: crew failed to respond within the 60-second window.
        -- Timer is measured from the last comms activity (opening the channel or choosing
        -- a stall option), so engaging with Relay always resets the clock.
        -- Only fires after the player has actually been hailed (stopped).
        if group.shakedown_state == "pending" and not group.shakedown_done
           and group.shakedown_hailed then
            local t0 = group.last_comms_activity or group.shakedown_hailed_at or group.shakedown_start
            -- Ten-second warning, re-armed whenever Relay resets the clock.
            if group.sound_warned_for ~= t0 and now - t0 > _cfg("shakedown_timeout") - 10 then
                group.sound_warned_for = t0
                RT.sound("concord_warning", {now = true})
            end
            if now - t0 > _cfg("shakedown_timeout") then
                local hostile_line = _HOSTILE_LINES[math.random(#_HOSTILE_LINES)]
                local hs_name = group.hailing_name or "Concord"
                RT.addReputation("Concord", -100, "failed to comply with Concord inspection", player)
                _log(group, "[" .. hs_name .. "] You were warned to comply in a timely manner. " .. hostile_line, "#FF4444")
                local _hmsg = "CONCORD PATROL HOSTILE\n" .. hs_name .. ": \"" .. hostile_line .. "\"\nPatrol hostile. -100 Concord standing."
                local _hkey = "concord_hostile_" .. math.floor(now)
                if player then
                    for _, _st2 in ipairs({"Helms","Weapons","Engineering","Engineering+","Science","Relay","Tactical","Operations","AltRelay"}) do
                        player:addCustomMessage(_st2, _hkey .. _st2, _hmsg)
                    end
                end
                if player then
                    for _, s in ipairs(group.ships) do
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
                group.shakedown_done    = true
            end
        end
    end

    if group.is_shakedown and group.shakedown_done and
       not group.shakedown_hostile and not group.despawn_at then
        group.despawn_at = now + _cfg("concord_despawn")
        for _, s in ipairs(group.ships) do
            if RT.valid(s) then s:orderFlyTowards(group.spawn_x, group.spawn_y) end
        end
        if group.jammer and RT.valid(group.jammer) then
            group.jammer:destroy()
            group.jammer = nil
        end
    end

    -- Layer 3: station proximity safety net.
    for _, s in ipairs(group.ships) do
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

    -- Layers 1 & 2: region boundary and player-exit recall. After _retarget the target is in the
    -- zone whenever any player ship is: the patrol goes home only when nobody is left to hunt.
    local region = st.regions[group.region_name]
    if region then
        local player_in = _inRegion(player, region)

        if not player_in and not group.recalled then
            group.mode        = "recalled"
            group.recalled    = true
            group.recalled_at = now
            for _, s in ipairs(group.ships) do
                if RT.valid(s) then s:orderFlyTowards(group.spawn_x, group.spawn_y) end
            end

        elseif player_in and group.recalled then
            group.mode        = "attack"
            group.recalled    = false
            group.recalled_at = nil
            _engage(group)
        end

        if not group.recalled then
            for _, s in ipairs(group.ships) do
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
            for _, s in ipairs(group.ships) do
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
        if ok and VERSE.HOSTILE_FACTIONS[fac] then
            count = count + 1
        end
    end
    return count
end

-- The deepest zone `player` (at px, py, in grid cell `cell`) is in where a patrol may spawn for
-- it now, or nil. `taken` holds the zones and cells that already drew a patrol this check.
local function _bestZone(st, player, px, py, cell, zone_ships, now, taken)
    if taken.cells[cell] then return nil end
    local cell_busy = false
    for _, g in ipairs(st.active) do
        if g.cell_key == cell then cell_busy = true end   -- one group per grid cell at a time
    end
    local best_name, best_depth = nil, 0
    for name, region in pairs(st.regions) do
        local depth = _depthIn(px, py, region)
        local zone  = PROX.zones[name]
        local mode  = _SPAWN_MODES[st.zone_modes[name] or _cfg("default_zone_mode")]
        local chase = PROX._chase_zones[name]
        local ok = depth > best_depth and not taken.zones[name]
                   and not PROX._suspended_zones[name] and mode.freq > 0
                   and (chase ~= nil or not cell_busy)   -- a chase ignores the one-group-per-cell rule
        -- Per-zone active ship cap (zone.max_active overrides mode default; a chase overrides both).
        if ok then ok = (zone_ships[name] or 0) < ((chase and chase.max_active) or zone.max_active or mode.max_active) end
        if ok then
            -- Per-zone cooldown (zone.cooldown shortened by mode frequency). Corsair standing of
            -- this ship scales aggressiveness: -200 → 30% shorter, -400 → 50% shorter.
            local cooldown = zone.cooldown
            if zone.faction == "Corsairs" then
                local crep = RT.getReputation("Corsairs", player) or 0
                if     crep <= -400 then cooldown = cooldown * 0.5
                elseif crep <= -200 then cooldown = cooldown * 0.7
                end
            end
            if chase then cooldown = chase.cooldown * mode.freq end   -- a chase's cooldown is absolute
            ok = now - (st.region_cd[name] or -99999) >= cooldown / mode.freq
        end
        -- Per-zone density: don't pile on if enough hostiles already nearby.
        if ok then ok = _nearbyHostiles(px, py) < mode.density end
        if ok then best_name, best_depth = name, depth end
    end
    return best_name
end

-- ── Control tint ─────────────────────────────────────────────────────────────
-- Who patrols where, as a faint tint on the long-range radars (Relay, Science, Operations, the GM):
-- each faction's patrol zones (PROX.zones) merged into one outline and drawn as an engine Zone.
-- The engine fills a zone at a fixed alpha (64), so the tint's strength comes from how dark the
-- colour is: CONTROL_COLORS are muted on purpose. Zone() carries never_radar_blocked, so Relay sees
-- it through its fog of war. No labels (the engine sizes a label to the zone: far too big).

PROX.CONTROL_COLORS = {   -- halved after the first playtest (2026-11-25: "good, half as much")
    Concord            = {30, 48, 82},
    Corsairs           = {82, 45, 18},
    ["Shroud Raiders"] = {60, 30, 18},
    Relic              = {62, 59, 25},
    Hollow             = {70, 15, 15},
}
PROX.CONTROL_STEPS = 120   -- points round each region's circle
PROX._control = PROX._control or {}   -- the Zone entities drawn

-- The outlines: {{faction = f, points = {{x, y}, ...}}, ...} in world units. Same-faction regions
-- that overlap become one outline (the arcs of each circle outside the others, chained end to end),
-- so an overlap is not tinted twice.
function PROX.controlOutlines()
    local by = {}
    for _, r in ipairs(VERSE.REGIONS) do
        local z = PROX.zones[r.name]
        if z and PROX.CONTROL_COLORS[z.faction] then
            by[z.faction] = by[z.faction] or {}
            table.insert(by[z.faction], {x = r.x * U, y = r.y * U, r = r.r * U})
        end
    end
    local out = {}
    local N = PROX.CONTROL_STEPS
    for fac, circles in pairs(by) do
        -- Each circle's arcs outside every other circle of the faction, in the same turning direction.
        local arcs = {}
        for i, c in ipairs(circles) do
            local pts, keep, all = {}, {}, true
            for j = 1, N do
                local a = (j - 1) / N * 2 * math.pi
                local x, y = c.x + math.cos(a) * c.r, c.y + math.sin(a) * c.r
                local inside = false
                for k, o in ipairs(circles) do
                    if k ~= i and (x - o.x) ^ 2 + (y - o.y) ^ 2 < (o.r - 1) ^ 2 then inside = true; break end
                end
                pts[j], keep[j] = {x, y}, not inside
                if inside then all = false end
            end
            if all then
                arcs[#arcs + 1] = {points = pts, closed = true}
            else
                for j = 1, N do
                    local prev = (j - 2) % N + 1
                    if keep[j] and not keep[prev] then
                        local arc, k = {}, j
                        while keep[k] do
                            arc[#arc + 1] = pts[k]
                            k = k % N + 1
                            if k == j then break end
                        end
                        arcs[#arcs + 1] = {points = arc}
                    end
                end
            end
        end
        -- Chain the arcs: each ends where the next (on another circle) begins.
        local used = {}
        for i, arc in ipairs(arcs) do
            if not used[i] then
                used[i] = true
                if arc.closed then
                    out[#out + 1] = {faction = fac, points = arc.points}
                else
                    local loop = {}
                    local cur = arc
                    for _ = 1, #arcs do
                        for _, p in ipairs(cur.points) do loop[#loop + 1] = p end
                        local last = cur.points[#cur.points]
                        local best, best_d = nil, math.huge
                        for k, other in ipairs(arcs) do
                            if (not used[k] or k == i) and not other.closed then
                                local f = other.points[1]
                                local d = (f[1] - last[1]) ^ 2 + (f[2] - last[2]) ^ 2
                                if d < best_d then best, best_d = k, d end
                            end
                        end
                        if not best or best == i then break end
                        used[best] = true
                        cur = arcs[best]
                    end
                    out[#out + 1] = {faction = fac, points = loop}
                end
            end
        end
    end
    return out
end

-- Draw (on = true) or remove the tint.
function PROX.showControl(on)
    for _, z in ipairs(PROX._control) do
        if z:isValid() then z:destroy() end
    end
    PROX._control = {}
    if not on then return end
    for _, o in ipairs(PROX.controlOutlines()) do
        local ok, err = pcall(function()
            local flat = {}
            for _, p in ipairs(o.points) do flat[#flat + 1] = p[1]; flat[#flat + 1] = p[2] end
            local c = PROX.CONTROL_COLORS[o.faction]
            local z = Zone():setColor(c[1], c[2], c[3]):setPoints(table.unpack(flat))
            PROX._control[#PROX._control + 1] = z
        end)
        if not ok then log("[PROX] control tint failed for " .. o.faction .. ": " .. tostring(err)) end
    end
end

function PROX.controlShown() return #PROX._control > 0 end

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
    if _cfg("control_tint") then PROX.showControl(true) end
end

function _P.update(state, delta, now)
    -- Jobboard lock suppresses new spawns; watchdog still cleans up groups.
    local spawning_ok = not (JOBS.config and JOBS.config.jobboard_locked)

    -- Every-tick shakedown pass: commandImpulse(0) must fire each frame to halt the
    -- player; at 8-second intervals it fires too rarely and the player can fly freely.
    do
        for _, group in ipairs(state.active) do
            local player2 = _target(group)   -- the ship this patrol has stopped
            if player2 then
                if group.shakedown_state == "pending" and not group.shakedown_done
                   and not group.shakedown_hailed
                   and group.jammer and RT.valid(group.jammer) then
                    pcall(function() player2:commandImpulse(0) end)
                    -- Track jammer 0.25U behind player every tick so it stays within
                    -- suppression range until the player stops.
                    local px3, py3 = player2:getPosition()
                    local head_rad = math.rad(player2:getHeading())
                    group.jammer:setPosition(
                        px3 - math.sin(head_rad) * 0.25 * U,
                        py3 + math.cos(head_rad) * 0.25 * U)
                    if group.jammer.components.physics then
                        group.jammer.components.physics.velocity = {0, 0}
                    end
                    local pvx, pvy = 0, 0
                    pcall(function() pvx, pvy = player2:getVelocity() end)
                    local pspeed = math.sqrt(pvx * pvx + pvy * pvy)
                    if pspeed < 25 then
                        group.shakedown_hailed    = true
                        group.shakedown_hailed_at = now
                        group.last_comms_activity = now
                        local hs = group.hailing_ship
                        if RT.valid(hs) then hs:openCommsTo(player2) end
                        RT.sound("concord_hail", {now = true})
                    end
                end
            end
            -- Stop resolved (any path): one closing cue. The bed loop ends on its own.
            if group.sound_loop and not group.sound_resolved
               and (group.shakedown_done or not RT.valid(group.jammer)) then
                group.sound_resolved = true
                RT.sound(group.shakedown_hostile and "concord_hostile" or "jammer_release", {now = true})
            end
        end
    end

    -- Hostile Concord groups drop combat warp jammers on the ship they hunt (every tick: the
    -- brake needs it).
    do
        for _, group in ipairs(state.active) do
            if group.concord and group.cjam
               and (not group.is_shakedown or group.shakedown_hostile) and not group.recalled then
                PROX.tickCombatJammers(group.cjam, group.ships, _target(group), now)
            end
        end
    end

    if now < state.next_check then return end
    state.next_check = now + _cfg("check_interval")

    local players = _livePlayers()
    if #players == 0 then return end

    local i = #state.active
    while i >= 1 do
        if _processGroup(state, state.active[i], now) then
            PROX.clearCombatJammers(state.active[i].cjam)
            table.remove(state.active, i)
        end
        i = i - 1
    end

    if not spawning_ok then return end

    -- Count active ships per zone for per-zone cap checks.
    local zone_ships = {}
    for _, g in ipairs(state.active) do
        local zn = g.region_name
        zone_ships[zn] = (zone_ships[zn] or 0) + #g.ships
    end

    -- Every ship may draw a patrol in the deepest zone it is in where all per-zone conditions
    -- pass. Cooldowns and caps are per zone, so one zone sends at most one patrol per check,
    -- after whichever ship comes first (the order is random), and none until its cooldown is over.
    local taken = {zones = {}, cells = {}}
    for _, player in ipairs(players) do
        local px, py = player:getPosition()
        local cell = _cellKey(px, py)
        local name = _bestZone(state, player, px, py, cell, zone_ships, now, taken)
        if name then
            taken.zones[name], taken.cells[cell] = true, true
            _spawnGroup(state, name, player, px, py)
        end
    end
end

function _P.cleanup(state)
    for _, group in ipairs(state.active or {}) do
        for _, s in ipairs(group.ships) do
            if RT.valid(s) then s:destroy() end
        end
        if group.jammer and RT.valid(group.jammer) then group.jammer:destroy() end
        PROX.clearCombatJammers(group.cjam)
    end
end

-- ── GM menu ───────────────────────────────────────────────────────────────────

local _ZONE_ORDER = {
    "the Concord Core", "the Arbiter Line", "the Escrow Marches",
    "the Shroud", "Halcyon Rest", "the Deep Shroud", "the Gauntlet", "Blackwater Reach",
    "the Boneyard", "the Maw",
}
local _ZONE_LABEL = {
    ["the Concord Core"]  = "Concord Core",
    ["the Arbiter Line"]  = "Arbiter Line",
    ["the Escrow Marches"] = "Escrow Marches",
    ["the Shroud"]        = "The Shroud",
    ["Halcyon Rest"]      = "Halcyon Rest",
    ["the Deep Shroud"]   = "Deep Shroud",
    ["the Gauntlet"]      = "The Gauntlet",
    ["Blackwater Reach"]  = "Blackwater Reach",
    ["the Boneyard"]      = "The Boneyard",
    ["the Maw"]           = "The Maw",
}

-- The faction zones' tint on the radars: a switch at the top of World Plugins, and in this menu.
local function _zonesLabel() return "Faction zones: " .. (PROX.controlShown() and "ON" or "OFF") end
_P.gmToggles = {
    {label = function() return _zonesLabel() end, fn = function() PROX.showControl(not PROX.controlShown()) end},
}

function _P.gmMenu(addButton, showSelf)
    local on = WORLD.isEnabled("proximity")
    addButton(_P.name .. ": " .. (on and "ON" or "OFF"), function()
        if on then WORLD.disable("proximity") else WORLD.enable("proximity") end
        showSelf()
    end)
    addButton(_zonesLabel(), function()
        PROX.showControl(not PROX.controlShown())
        showSelf()
    end)
    addButton("Trigger Spawn Now", function()
        local st = WORLD._state["proximity"]
        if not st then return end
        local player = _firstPlayer()
        if not player then return end
        local px, py = player:getPosition()
        local best_name, best_depth = nil, 0
        for name, region in pairs(st.regions) do
            local depth = _depthIn(px, py, region)
            if depth > best_depth then
                best_name, best_depth = name, depth
            end
        end
        if not best_name then return end
        st.region_cd = {}
        st.last_spawn = -99999
        _spawnGroup(st, best_name, player, px, py)
    end)
    addButton("Spawn Zones...", function()
        local showZoneListMenu
        local showZoneDetailMenu

        showZoneListMenu = function()
            clearGMFunctions()
            addGMFunction("← Back to Proximity", showSelf)
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
            addGMFunction("← Back to Zones", showZoneListMenu)
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

-- Despawn any active hostile Concord patrols and reset zone cooldowns.
-- Call this from the GM menu after manually restoring Concord standing.
function PROX.clearWantedStatus()
    local st = WORLD._state["proximity"]
    if not st then return end
    local i = #st.active
    while i >= 1 do
        local g = st.active[i]
        if g.shakedown_hostile or (PROX.zones[g.region_name] and PROX.zones[g.region_name].faction == "Concord") then
            for _, s in ipairs(g.ships) do
                if RT.valid(s) then s:destroy() end
            end
            if g.jammer and RT.valid(g.jammer) then g.jammer:destroy() end
            PROX.clearCombatJammers(g.cjam)
            table.remove(st.active, i)
        end
        i = i - 1
    end
    st.region_cd["the Concord Core"]  = nil
    st.region_cd["the Arbiter Line"]  = nil
    st.region_cd["the Escrow Marches"] = nil
end

-- Suppress ambient spawns in a named zone (e.g. during a story arc).
-- Suspended zones still run the leash/despawn watchdog; only new spawns are blocked.
PROX._suspended_zones = PROX._suspended_zones or {}

function PROX.suspendZone(name)
    PROX._suspended_zones[name] = true
end

function PROX.resumeZone(name)
    PROX._suspended_zones[name] = nil
end

-- A chase (e.g. after a story arc's robbery): the zone sends a patrol every `cooldown` seconds,
-- whatever its GM mode's frequency (mode None still sends none), up to `max_active` ships, even into
-- a grid cell that already has one. The density limit still applies. PROX.endChase puts it back.
PROX._chase_zones = PROX._chase_zones or {}

function PROX.chaseZone(name, cooldown, max_active)
    PROX._chase_zones[name] = {cooldown = cooldown or 30, max_active = max_active or 4}
end

function PROX.endChase(name)
    PROX._chase_zones[name] = nil
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
