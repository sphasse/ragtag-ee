-- ee/ragtag/core.lua
-- Shared library for the "Long Haul" ragtag campaign.
--
-- Provides:
--   * Campaign persistence across sessions (getScriptStorage, key "ragtag.campaign")
--   * Player ship creation with purchased upgrades re-applied every session
--   * Credits (stored as the player ship's reputation points, visible on Relay)
--   * A generic station comms menu with a shipwright (upgrade shop) and rumours
--   * Objective display on Relay / Operations screens
--   * Small helpers (named object registry, distance, timers)
--
-- Usage in a scenario:
--   require("utils.lua")
--   require("ragtag/core.lua")
--   require("ragtag/verse.lua")
--   require("ragtag/director.lua")
--
-- Written against the ECS-era EmptyEpsilon scripting API (2024+ releases).

RT = RT or {}
RT.VERSION = "1.0"
RT.CAMPAIGN_KEY = "ragtag.campaign"   -- set per campaign by RT.useCampaign()
RT.SHIP_KEY     = "ragtag.ship"        -- portable ship record, not tied to any campaign
RT.PLAYER_FACTION = "Independent"
RT.PLAYER_TEMPLATE = "Flavia P.Falcon"

RT.named = {}          -- callsign -> entity, for objects the scenario or director created
RT.stations = {}       -- callsign -> {entity=..., shop=bool, flavor=string, hooks={fn,...}}
RT.objective = ""
RT.player  = nil       -- first player ship (backward-compat alias for RT.players[1])
RT.players = {}        -- all active player ships; append via RT.spawnPlayer()
RT.timers = {}         -- list of {at=time, fn=function, name=string}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

function RT.valid(e)
    return e ~= nil and e:isValid()
end

function RT.now()
    return getScenarioTime()
end

-- Run fn after `seconds` of scenario time. Returns the timer record.
function RT.after(seconds, fn, name)
    local t = {at = getScenarioTime() + seconds, fn = fn, name = name or "timer"}
    table.insert(RT.timers, t)
    return t
end

function RT.cancelTimer(name)
    for i = #RT.timers, 1, -1 do
        if RT.timers[i].name == name then table.remove(RT.timers, i) end
    end
end

function RT.updateTimers()
    local now = getScenarioTime()
    for i = #RT.timers, 1, -1 do
        local t = RT.timers[i]
        if now >= t.at then
            table.remove(RT.timers, i)
            local ok, err = pcall(t.fn)
            if not ok then log("[RT] timer '" .. t.name .. "' failed: " .. tostring(err)) end
        end
    end
end

--------------------------------------------------------------------------------
-- Sound cues.
--
-- Server-side by default: EE's playSoundFile() plays ONLY on the server machine
-- (engine src/script.cpp:1408). That is the room-wide channel for a bridge whose
-- server has the speakers. It has no volume/pitch/stop, so cues are short files
-- and a queue keeps them from stacking.
--
-- Optional client-side positional cue (RT.sound_client_enabled): an entity with
-- an `sfx` component replicates to every client and plays once there. With a
-- position it is only heard on screens that render a 3D view (main screen),
-- relative to that screen's ship. Off by default: clients would need the file.
--
-- Cue files live in ee/ragtag/sfx/ (installed to scripts/ragtag/sfx/, which EE
-- resolves as "ragtag/sfx/<name>.wav"). Entries below point at files
-- as synthesized by tools/gen_sfx.py — see ee/ragtag/sfx/SOURCES.md.
--------------------------------------------------------------------------------

RT.sound_enabled        = true    -- GM toggle; silences every cue
RT.sound_client_enabled = false   -- also emit positional client cues (needs files on clients)

-- id -> {file, seconds}. `seconds` is the clip length, used for queue pacing.
RT.SOUNDS = {
    -- Concord patrol stop
    concord_hail      = {file = "ragtag/sfx/concord_hail.wav",    seconds = 3.4},
    concord_warning   = {file = "ragtag/sfx/concord_warning.wav", seconds = 0.5},
    concord_hostile   = {file = "ragtag/sfx/concord_hostile.wav", seconds = 1.8},
    -- Warp jammer (Concord stop and Boneyard)
    jammer_engage     = {file = "ragtag/sfx/jammer_engage.wav",   seconds = 3.1},
    jammer_bed        = {file = "ragtag/sfx/jammer_bed.wav",      seconds = 8.0},
    jammer_release    = {file = "ragtag/sfx/jammer_release.wav",  seconds = 1.5},
}

RT._sound_queue      = {}   -- pending {id, opts}
RT._sound_busy_until = 0    -- scenario time the current cue ends
RT._sound_loops      = {}   -- name -> {id, interval, next_at, alive}

local function _soundPlayNow(entry, opts)
    local ok, err = pcall(playSoundFile, entry.file)
    if not ok then log("[RT] sound '" .. entry.file .. "' failed: " .. tostring(err)) end
    RT._sound_busy_until = getScenarioTime() + (entry.seconds or 2)
    if RT.sound_client_enabled and opts.x and opts.y then
        pcall(function()
            local e = createEntity()
            e.components = {
                transform = {},
                sfx = {sound = entry.file, volume = opts.volume or 100, pitch = opts.pitch or 1.0},
            }
            e:setPosition(opts.x, opts.y)
            -- Late-joining clients receive every live sfx entity; drop it once played.
            RT.after(5, function() if e:isValid() then e:destroy() end end, "sfx_cleanup")
        end)
    end
end

-- Play a cue by id. opts: {now=true (skip the queue), skip_if_busy=true (drop
-- instead of queueing), x, y (positional client cue), volume, pitch}.
function RT.sound(id, opts)
    if not RT.sound_enabled then return false end
    opts = opts or {}
    local entry = RT.SOUNDS[id]
    if entry == nil then log("[RT] unknown sound cue: " .. tostring(id)); return false end
    local now = getScenarioTime()
    if opts.now or now >= RT._sound_busy_until then
        _soundPlayNow(entry, opts)
        return true
    end
    if opts.skip_if_busy then return false end
    for _, q in ipairs(RT._sound_queue) do
        if q.id == id then return false end   -- already queued; don't stack repeats
    end
    table.insert(RT._sound_queue, {id = id, opts = opts})
    return true
end

-- Re-fire a cue every `interval` seconds while alive() (optional) returns true.
-- Loop cues never queue: if something else is playing, that beat is skipped.
function RT.soundLoop(name, id, interval, alive)
    RT._sound_loops[name] = {id = id, interval = interval, next_at = 0, alive = alive}
end

function RT.stopSoundLoop(name)
    RT._sound_loops[name] = nil
end

function RT.updateSounds()
    local now = getScenarioTime()
    for name, loop in pairs(RT._sound_loops) do
        if loop.alive and not loop.alive() then
            RT._sound_loops[name] = nil
        elseif now >= loop.next_at then
            loop.next_at = now + loop.interval
            RT.sound(loop.id, {skip_if_busy = true})
        end
    end
    if #RT._sound_queue > 0 and now >= RT._sound_busy_until then
        local q = table.remove(RT._sound_queue, 1)
        local entry = RT.SOUNDS[q.id]
        if entry then _soundPlayNow(entry, q.opts) end
    end
end

function RT.register(entity, callsign)
    if callsign then entity:setCallSign(callsign) end
    RT.named[entity:getCallSign()] = entity

    -- Automatically track CpuShips for reputation on kill
    -- Check if getTypeName exists and is actually a function before calling
    if entity.getTypeName and type(entity.getTypeName) == "function" then
        local ok, typename = pcall(function() return entity:getTypeName() end)
        if ok and typename == "CpuShip" then
            RT.trackShipForReputation(entity)
        end
    end

    return entity
end

-- Find an entity by callsign: registry first, then a radius scan around the nearest player.
function RT.find(callsign)
    if callsign == nil or callsign == "" then return nil end
    local e = RT.named[callsign]
    if RT.valid(e) then return e end
    local cx, cy = 0, 0
    local np = RT.nearestPlayer(0, 0)
    if np then cx, cy = np:getPosition() end
    for _, obj in ipairs(getObjectsInRadius(cx, cy, 100000)) do
        if obj.getCallSign and obj:getCallSign() == callsign then
            RT.named[callsign] = obj
            return obj
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Multi-player helpers
--------------------------------------------------------------------------------

function RT.anyPlayerAlive()
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then return true end
    end
    return false
end

function RT.isPlayer(entity)
    if not RT.valid(entity) then return false end
    for _, p in ipairs(RT.players) do
        if p == entity then return true end
    end
    return false
end

-- Nearest valid player ship to (x, y). Returns nil when no players are alive.
function RT.nearestPlayer(x, y)
    local best, best_dist = nil, math.huge
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then
            local px, py = p:getPosition()
            local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
            if d < best_dist then best, best_dist = p, d end
        end
    end
    return best
end

-- addToShipLog on every alive player ship.
function RT.shipLog(msg, color)
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then p:addToShipLog(msg, color or "#FFFFFF") end
    end
end

function RT.forEachPlayer(fn)
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then fn(p) end
    end
end

function RT.dist(a, b)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Compute a ship's combat strength from its max stats (unchanged by damage).
-- Returns {offense=N, defense=N, total=N}:
--   defense  = hull_max + sum of all shield segment maxima
--   offense  = beam DPS (dmg/cycle across all slots) + missile capacity DPS equivalent
--   total    = defense + offense * 30  (the single balancing number; compare player vs enemy)
-- Safe to call on any valid ship at any time, including inside onDestruction callbacks.
function RT.shipStrength(ship)
    if not RT.valid(ship) then return {offense = 0, defense = 0, total = 0} end
    local hull = ship:getHullMax() or 0
    -- Use the ECS API (getShieldCount/getShieldMax) — getShieldsMax() is
    -- a PlayerSpaceship-only compat shim and errors on CpuShip.
    local shields = 0
    local sc = ship:getShieldCount() or 0
    for i = 0, sc - 1 do shields = shields + (ship:getShieldMax(i) or 0) end
    local defense = hull + shields
    local dps = 0
    for i = 0, 15 do
        local range = ship:getBeamWeaponRange(i)
        if range ~= nil and range > 0 then
            local dmg = ship:getBeamWeaponDamage(i) or 0
            local cyc = ship:getBeamWeaponCycleTime(i) or 1
            if cyc > 0 then dps = dps + dmg / cyc end
        end
    end
    -- Missile capacity contributes as a burst spread over ~30 s.
    local missile_dps = 0
    for w, dmg_equiv in pairs({Homing = 8, HVLI = 2, Nuke = 60, EMP = 15}) do
        local cap = ship:getWeaponStorageMax(w)
        if cap and cap > 0 then missile_dps = missile_dps + cap * dmg_equiv / 30 end
    end
    local offense = dps + missile_dps
    return {
        offense = math.floor(offense * 10 + 0.5) / 10,
        defense = math.floor(defense),
        total   = math.floor(defense + offense * 30),
    }
end

-- Hail all player ships from an entity; if comms are busy on a ship, fall back to its log.
-- Returns true if at least one comms message landed.
function RT.hail(from, text, speaker)
    local sent = false
    local tag = speaker or (RT.valid(from) and from:getCallSign()) or "Unknown"
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then
            if RT.valid(from) then
                -- sendCommsMessage opens hail with message and auto-logs to ship log
                if from:sendCommsMessage(p, text) then
                    sent = true
                end
            else
                -- No sender entity, log directly with speaker tag
                p:addToShipLog("[" .. tag .. "] " .. text, "#C0E0FF")
            end
        end
    end
    return sent
end

-- Remove control characters and clamp length for anything shown to players.
function RT.cleanText(s, max_len)
    s = tostring(s or "")
    s = s:gsub("[%c]", function(c) if c == "\n" then return "\n" end return " " end)
    max_len = max_len or 600
    if #s > max_len then s = s:sub(1, max_len - 3) .. "..." end
    return s
end

--------------------------------------------------------------------------------
-- Campaign persistence
--------------------------------------------------------------------------------

local function defaultCampaign()
    return {
        version = 1,
        ship_name = "Magpie",
        credits = 150,
        upgrades = {},    -- list of upgrade ids, applied in purchase order
        extra_ships = {}, -- [{name, credits}, ...] one entry per ship beyond the primary
        sessions = {},   -- "s1" -> {outcome="success", at=...}
        flags = {},      -- story flags: string -> bool/number/string
        notes = {},      -- short human-readable campaign log lines
        discovered = {}, -- names of charted regions (see ragtag_verse.lua)
        stats = {},      -- statistics (see ragtag/stats.lua)
        achievements = {}, -- id -> {at, session} (see ragtag/stats.lua)
        reputation = {   -- standing with each faction (unbounded; thresholds at ±200/±400/±500)
            Concord = 0,
            Corsairs = 0,
            Hollow = 0,
            Relic = 0,
            Unknown = 0,
            Independent = 0,
        },
    }
end

-- Each campaign keeps its own save, so scenarios from different campaigns
-- (or one-shots) never overwrite each other. Call before RT.loadCampaign().
function RT.useCampaign(id)
    RT.campaign_id = id
    RT.CAMPAIGN_KEY = "ragtag.campaign." .. id
    -- Saves from before the repo layout used a single shared key; adopt it once.
    if id == "longhaul" then
        local s = getScriptStorage()
        local cur = s:get(RT.CAMPAIGN_KEY)
        local legacy = s:get("ragtag.campaign")
        if (cur == nil or cur == "") and type(legacy) == "string" and legacy ~= "" then
            s:set(RT.CAMPAIGN_KEY, legacy)
        end
    end
end

function RT.loadCampaign(fresh)
    local c = nil
    if not fresh then
        local raw = getScriptStorage():get(RT.CAMPAIGN_KEY)
        if type(raw) == "string" and raw ~= "" then
            local ok, v = pcall(fromJSON, raw)
            if ok and type(v) == "table" then c = v end
        end
    end
    local d = defaultCampaign()
    if c == nil then
        c = d
    else
        for k, v in pairs(d) do
            if c[k] == nil then c[k] = v end
        end
        -- toJSON turns empty tables into arrays; normalise the keyed ones.
        if type(c.flags) ~= "table" then c.flags = {} end
        if type(c.sessions) ~= "table" then c.sessions = {} end
        if type(c.discovered) ~= "table" then c.discovered = {} end
        if type(c.stats) ~= "table" then c.stats = {} end
        if type(c.achievements) ~= "table" then c.achievements = {} end
    end
    RT.campaign = c
    return c
end

function RT.saveCampaign()
    if RT.campaign == nil then return end
    if RT._saves_frozen then return end   -- a backup was restored: don't overwrite it until restart
    if RT.valid(RT.player) then
        RT.campaign.credits = math.floor(RT.player:getReputationPoints())
    end
    RT.campaign.extra_ships = RT.campaign.extra_ships or {}
    for i = 2, #RT.players do
        local p = RT.players[i]
        if RT.valid(p) then
            local entry = RT.campaign.extra_ships[i-1] or {}
            entry.name    = p:getCallSign()
            entry.credits = math.floor(p:getReputationPoints())
            RT.campaign.extra_ships[i-1] = entry
        end
    end
    getScriptStorage():set(RT.CAMPAIGN_KEY, toJSON(RT.campaign))
end

--------------------------------------------------------------------------------
-- Reputation system
--------------------------------------------------------------------------------

-- Threshold table for rep-change notifications.
-- Concord has inspection-specific entries; _default covers job-access thresholds for all factions.
local _REP_THRESHOLDS = {
    Concord = {
        { 500, "Concord will now wave you through inspections without stopping.",
                "Concord will now conduct inspections again." },
        { 200, "Concord now accepts cargo declarations without proof.",
                "Concord no longer accepts cargo declarations without proof." },
        {   0, "Concord patrols give benefit of doubt on ignored hails.",
                "Concord patrols will now issue warrants for ignored inspections." },
        {-200, "More work becoming available at Concord ports.",
                "Very few jobs available at Concord ports." },
        {-400, "Concord ports may offer limited work again.",
                "Concord ports will no longer offer work." },
        {-500, "Concord inspection protocols restored.",
                "Concord patrols will now attack on sight." },
    },
    Corsairs = {
        {   0, "Full job access restored at Corsair-adjacent ports.",
                "Fewer jobs offered at Corsair-adjacent ports." },
        {-200, "Corsair patrol pressure easing — longer intercept intervals.",
                "Corsair patrols becoming more aggressive in their territory." },
        {-400, "Some work returning at Corsair-adjacent ports.",
                "Corsairs are now actively targeting your ship." },
    },
    _default = {
        {   0, "Full job access restored at this faction's ports.",
                "Fewer jobs will be offered at this faction's ports." },
        {-200, "More work becoming available at this faction's ports.",
                "Very limited jobs available at this faction's ports." },
        {-400, "Some jobs may return at this faction's ports.",
                "This faction will no longer offer work." },
    },
}

-- Modify reputation with a faction. Unbounded.
function RT.addReputation(faction, amount, reason)
    if not RT.campaign or not RT.campaign.reputation then return end
    if not RT.campaign.reputation[faction] then
        RT.campaign.reputation[faction] = 0
    end

    local old_rep = RT.campaign.reputation[faction]
    local new_rep = old_rep + amount
    RT.campaign.reputation[faction] = new_rep

    if amount ~= 0 then
        -- Line 1: what changed and why
        local sign = amount > 0 and "+" or ""
        local why  = reason and (" — " .. reason) or ""
        RT.shipLog(string.format("%s reputation %s%d%s", faction, sign, amount, why),
                   amount > 0 and "#80C0FF" or "#FF8080")

        -- Line 2: current standings for the three main factions
        local rtbl = RT.campaign.reputation
        local function _s(f)
            local r = rtbl[f] or 0
            return f .. ": " .. (r >= 0 and "+" or "") .. r
        end
        RT.shipLog("Current reputation: " .. _s("Independent") .. " | " .. _s("Concord") .. " | " .. _s("Corsairs"), "#888888")

        -- Line 3 (optional): threshold-crossing notification
        local thresholds = _REP_THRESHOLDS[faction] or _REP_THRESHOLDS._default
        for _, t in ipairs(thresholds) do
            local val, msg_up, msg_down = t[1], t[2], t[3]
            if old_rep < val and new_rep >= val then
                RT.shipLog("[Rep] " .. msg_up, "#80FF80")
            elseif old_rep >= val and new_rep < val then
                RT.shipLog("[Rep] " .. msg_down, "#FF8040")
            end
        end
    end

    RT.saveCampaign()
end

-- Get current reputation with a faction
function RT.getReputation(faction)
    if not RT.campaign or not RT.campaign.reputation then return 0 end
    return RT.campaign.reputation[faction] or 0
end

-- Destruction callbacks. EE's onDestruction holds a single callback per entity,
-- so this dispatcher lets several systems (reputation, director events, loot
-- drops) hook the same ship without clobbering each other.
-- fn(ship, instigator). onDestruction only fires on damage kills, never on a
-- scripted destroy(), and instigator identifies the killer.
RT._kill_cbs      = setmetatable({}, {__mode = "k"})
RT._rep_cancelled = setmetatable({}, {__mode = "k"})

function RT.onKill(ship, fn)
    if not ship or not RT.valid(ship) then return end
    local cbs = RT._kill_cbs[ship]
    if cbs == nil then
        cbs = {}
        RT._kill_cbs[ship] = cbs
        ship:onDestruction(function(s, instigator)
            for _, cb in ipairs(cbs) do
                local ok, err = pcall(cb, s, instigator)
                if not ok then log("[RT] kill callback failed: " .. tostring(err)) end
            end
        end)
    end
    cbs[#cbs + 1] = fn
end

-- Suppress the reputation penalty for a ship an arc is managing itself.
-- (Scripted destroy() never fires onDestruction anyway; this covers arcs that
-- let a ship die to damage but apply their own consequences.)
function RT.cancelKillTracking(ship)
    if ship ~= nil then RT._rep_cancelled[ship] = true end
end

-- Register a ship for a reputation penalty when the PLAYER destroys it.
-- NPC-vs-NPC kills and scripted despawns cost nothing.
function RT.trackShipForReputation(ship)
    if not ship or not RT.valid(ship) then return end
    local faction = ship:getFaction()
    -- Skip player ships, inert factions, and presentation-only pseudo-factions.
    local skip = {
        [RT.PLAYER_FACTION] = true, Derelict = true, Unknown = true,
        ["Concord Hostile"] = true, ["Corsair Friendly"] = true, ["Relic Active"] = true,
    }
    if skip[faction] then return end
    local callsign = ship:getCallSign()   -- capture before entity is destroyed
    RT.onKill(ship, function(s, instigator)
        if RT._rep_cancelled[s] then return end
        if not RT.isPlayer(instigator) then return end
        RT.addReputation(faction, -200, "destroyed " .. callsign)
    end)
end

--------------------------------------------------------------------------------
-- Portable ship record (upgrades + damage state, no campaign or position)
-- Use to carry a ship between campaigns or hand it off to a new scenario.
--------------------------------------------------------------------------------

-- Write current ship state to the shared, campaign-independent key.
function RT.saveShipRecord()
    if not RT.valid(RT.player) then return nil end
    local hull_pct = RT.player:getHull() / RT.player:getHullMax()
    local fs, rs   = RT.player:getShieldLevel()
    local fm, rm   = RT.player:getShieldsMax()
    local record = {
        ship_name        = RT.player:getCallSign(),
        upgrades         = RT.campaign and RT.campaign.upgrades or {},
        hull_pct         = hull_pct,
        front_shield_pct = fm > 0 and fs / fm or 0,
        rear_shield_pct  = rm > 0 and rs / rm or 0,
        energy_pct       = RT.player:getEnergy() / RT.player:getMaxEnergy(),
    }
    getScriptStorage():set(RT.SHIP_KEY, toJSON(record))
    return record
end

function RT.loadShipRecord()
    local raw = getScriptStorage():get(RT.SHIP_KEY)
    if type(raw) ~= "string" or raw == "" then return nil end
    local ok, v = pcall(fromJSON, raw)
    return (ok and type(v) == "table") and v or nil
end

function RT.clearShipRecord()
    getScriptStorage():set(RT.SHIP_KEY, "")
end

-- Merge a ship record into the current campaign so the next RT.spawnPlayer
-- spawns with the right upgrades and wear. Omit `record` to read from storage.
function RT.importShipRecord(record)
    record = record or RT.loadShipRecord()
    if not record then return false end
    local c = RT.campaign or RT.loadCampaign()
    if record.ship_name then c.ship_name = record.ship_name end
    if type(record.upgrades) == "table" then c.upgrades = record.upgrades end
    c.ship_condition = {
        hull_pct         = record.hull_pct         or 1,
        front_shield_pct = record.front_shield_pct or 1,
        rear_shield_pct  = record.rear_shield_pct  or 1,
        energy_pct       = record.energy_pct       or 1,
    }
    RT.saveCampaign()
    return true
end

function RT.flag(name, value)
    if value == nil then return RT.campaign.flags[name] end
    RT.campaign.flags[name] = value
    RT.saveCampaign()
    return value
end

-- Explicitly clear a flag (RT.flag(name, nil) is a read, not a clear).
function RT.clearFlag(name)
    RT.campaign.flags[name] = nil
    RT.saveCampaign()
end

function RT.note(text)
    table.insert(RT.campaign.notes, RT.cleanText(text, 200))
    while #RT.campaign.notes > 40 do table.remove(RT.campaign.notes, 1) end
end

function RT.hasUpgrade(id)
    for _, u in ipairs(RT.campaign.upgrades) do
        if u == id then return true end
    end
    return false
end

-- Mark a session finished and persist. outcome: "success", "partial", "failed"
function RT.completeSession(session_id, outcome, note)
    RT.campaign.sessions[session_id] = {outcome = outcome, at = math.floor(getScenarioTime())}
    if note then RT.note(session_id .. ": " .. note) end
    RT.saveCampaign()
end

--------------------------------------------------------------------------------
-- Credits (reputation points on the player ship)
--------------------------------------------------------------------------------

-- Returns the current credit balance (reputation points) of a specific ship.
-- If no ship provided, returns the first player ship's balance (backward compat).
function RT.credits(ship)
    ship = ship or RT.player
    if not RT.valid(ship) then return 0 end
    return math.floor(ship:getReputationPoints())
end

-- Add credits to a specific ship. If no ship provided, affects only the first player ship.
-- Ships maintain independent credit pools - no automatic syncing.
function RT.addCredits(amount, reason, ship)
    ship = ship or RT.player
    if not RT.valid(ship) then return end
    amount = math.floor(amount)
    local new_total
    if amount >= 0 then
        ship:addReputationPoints(amount)
        new_total = math.floor(ship:getReputationPoints())
    else
        new_total = math.max(0, RT.credits(ship) + amount)
        ship:setReputationPoints(new_total)
    end
    local sign = amount >= 0 and "+" or ""
    ship:addToShipLog(string.format("Credits %s%d (%s). Balance: %d", sign, amount, reason or "misc", new_total), "#E0C060")
    if STATS then STATS.noteCredits(amount, reason) end
    -- Only save campaign for the primary ship
    if ship == RT.player then
        RT.saveCampaign()
    end
end

--------------------------------------------------------------------------------
-- Upgrades. Each apply() must be idempotent-safe when re-run on a fresh ship
-- (they are re-applied in purchase order at the start of every session).
--------------------------------------------------------------------------------

RT.UPGRADES = {
    {id = "hull_plating", name = "Salvaged hull plating", gm_name = "Hull armor", cost = 200,
     desc = "+50 hull.",
     apply = function(p) p:setHullMax(p:getHullMax() + 50); p:setHull(p:getHullMax()) end},
    {id = "shield_mk2", name = "Mk II shield emitters", gm_name = "Shield II", cost = 250,
     desc = "Shields to 100 / 100.",
     apply = function(p) p:setShieldsMax(100, 100); p:setShields(100, 100) end},
    {id = "forward_beams", name = "Forward beam mount", gm_name = "Fwd beams", cost = 300,
     desc = "Adds a forward-firing beam. Finally something pointing where you're going.",
     apply = function(p) p:setBeamWeapon(2, 50, 0, 1000, 6, 6) end},
    {id = "beam_coils", name = "Overclocked beam coils", gm_name = "Beam coils", cost = 250, requires = "forward_beams",
     desc = "+2 damage on every beam.",
     apply = function(p)
        for i = 0, 15 do
            local range = p:getBeamWeaponRange(i)
            if range ~= nil and range > 0 then
                p:setBeamWeapon(i, p:getBeamWeaponArc(i), p:getBeamWeaponDirection(i), range,
                    p:getBeamWeaponCycleTime(i), p:getBeamWeaponDamage(i) + 2)
            end
        end
     end},
    {id = "engine_tune", name = "Black-market engine tune", gm_name = "Eng tune", cost = 200,
     desc = "Impulse 60 -> 75.",
     apply = function(p) p:setImpulseMaxSpeed(75, 37) end},
    {id = "missile_racks", name = "Extra missile racks", gm_name = "Missiles", cost = 150,
     desc = "+4 homing, +6 HVLI capacity.",
     apply = function(p)
        p:setWeaponStorageMax("Homing", p:getWeaponStorageMax("Homing") + 4)
        p:setWeaponStorageMax("HVLI", p:getWeaponStorageMax("HVLI") + 6)
        p:setWeaponStorage("Homing", p:getWeaponStorageMax("Homing"))
        p:setWeaponStorage("HVLI", p:getWeaponStorageMax("HVLI"))
     end},
    {id = "front_tube", name = "Bow torpedo tube", gm_name = "Bow tube", cost = 350,
     desc = "Adds a forward missile tube.",
     apply = function(p)
        -- setWeaponTubeCount rebuilds all tubes, so re-set both directions.
        p:setWeaponTubeCount(2)
        p:setWeaponTubeDirection(0, 180)
        p:setWeaponTubeDirection(1, 0)
     end},
    {id = "repair_crew", name = "Two more hands", gm_name = "Repair crew", gm_label = "Repair 4 crew", cost = 150, crew = true,
     desc = "+2 repair crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "repair_crew_2", name = "Three more hands", gm_name = "Repair crew 2", gm_label = "Repair 6 crew", cost = 150, crew = true,
     requires = "repair_crew", desc = "+2 repair crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "repair_crew_3", name = "Full crew complement", gm_name = "Repair crew 3", gm_label = "Repair 8 crew", cost = 150, crew = true,
     requires = "repair_crew_2", desc = "+2 repair crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "sensor_suite", name = "Long-range sensor suite", gm_name = "Sensors", cost = 150,
     desc = "Long-range radar 30u -> 45u.",
     apply = function(p) p:setLongRangeRadarRange(45000) end},
    {id = "fast_probes", name = "Overcharged probe capacitors", gm_name = "Fast probes", cost = 200,
     desc = "Scan probes fly at 2× speed.",
     apply = function(p) p:onProbeLaunch(function(ship, probe) probe:setSpeed(2000) end) end},
    {id = "ludicrous_probes", name = "Ludicrous-speed probe mod", gm_name = "Ludicrous", cost = 250, requires = "fast_probes",
     desc = "Scan probes fly at 4× speed. They've hit the plaid.",
     apply = function(p) p:onProbeLaunch(function(ship, probe) probe:setSpeed(4000) end) end},
    -- Second tier: what it takes to survive Blackwater, the Boneyard and, eventually, the Maw.
    {id = "reactor_overhaul", name = "Reactor overhaul", gm_name = "Reactor", cost = 200,
     desc = "+50% energy capacity.",
     apply = function(p) p:setMaxEnergy(p:getMaxEnergy() * 1.5); p:setEnergy(p:getMaxEnergy()) end},
    {id = "warp_overhaul", name = "Warp coil overhaul", gm_name = "Warp coils", cost = 250,
     desc = "Warp speed +50%.",
     apply = function(p) p:setWarpSpeed(p:getWarpSpeed() * 1.5) end},
    {id = "combat_thrusters", name = "Combat thrusters", gm_name = "Thrusters", cost = 300,
     desc = "Much stronger combat boost and strafe. Gets you out of trouble.",
     apply = function(p) p:setCombatManeuver(450, 300) end},
    {id = "hull_plating_2", name = "Armoured hull", gm_name = "Armor II", cost = 450, requires = "hull_plating",
     desc = "+100 hull.",
     apply = function(p) p:setHullMax(p:getHullMax() + 100); p:setHull(p:getHullMax()) end},
    {id = "heavy_beams", name = "Heavy beam emitters", gm_name = "Heavy beams", cost = 400, requires = "beam_coils",
     desc = "+400 range on every beam.",
     apply = function(p)
        for i = 0, 15 do
            local range = p:getBeamWeaponRange(i)
            if range ~= nil and range > 0 then
                p:setBeamWeapon(i, p:getBeamWeaponArc(i), p:getBeamWeaponDirection(i), range + 400,
                    p:getBeamWeaponCycleTime(i), p:getBeamWeaponDamage(i))
            end
        end
     end},
    {id = "shield_mk3", name = "Military shield generators", gm_name = "Shield III", cost = 600, requires = "shield_mk2",
     desc = "Shields to 160 / 160. Concord military surplus, officially.",
     apply = function(p) p:setShieldsMax(160, 160); p:setShields(160, 160) end},
}

function RT.upgradeById(id)
    for _, u in ipairs(RT.UPGRADES) do
        if u.id == id then return u end
    end
    return nil
end

function RT.applyUpgrade(p, id)
    local u = RT.upgradeById(id)
    if u == nil then return false end
    local ok, err = pcall(u.apply, p)
    if not ok then log("[RT] upgrade " .. id .. " failed: " .. tostring(err)) end
    return ok
end

-- Grant an upgrade for free (story reward). Saves.
function RT.grantUpgrade(id, reason)
    if RT.hasUpgrade(id) or RT.upgradeById(id) == nil then return false end
    table.insert(RT.campaign.upgrades, id)
    RT.forEachPlayer(function(p) RT.applyUpgrade(p, id) end)
    RT.shipLog("Upgrade installed: " .. RT.upgradeById(id).name .. (reason and (" (" .. reason .. ")") or ""), "#80FF80")
    RT.saveCampaign()
    if DIR then DIR.emit("upgrade", {id = id, how = "granted", reason = reason}) end
    return true
end

--------------------------------------------------------------------------------
-- Player ship
--------------------------------------------------------------------------------

-- opts (optional 4th arg): {callsign, template, faction}
-- First call creates the primary ship (RT.player alias). Subsequent calls add
-- a second crew ship. Extra ships get their own callsign (opts.callsign or
-- primary_name.."-2", "-3", …) and share the campaign's credit balance.
function RT.spawnPlayer(x, y, heading, opts)
    opts = opts or {}
    local c = RT.campaign or RT.loadCampaign()
    local is_primary = (#RT.players == 0)
    local tmpl    = opts.template or RT.PLAYER_TEMPLATE
    local faction = opts.faction  or RT.PLAYER_FACTION
    local cs      = opts.callsign or (is_primary and c.ship_name or (c.ship_name .. "-" .. (#RT.players + 1)))
    local p = PlayerSpaceship():setTemplate(tmpl):setFaction(faction)
    p:setCallSign(cs):setPosition(x, y)
    if heading then p:setHeading(heading) end
    -- A modest, slightly battered start: no nukes or mines on a freight hauler.
    p:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
    p:setWeaponStorageMax("Mine", 0):setWeaponStorage("Mine", 0)
    p:setWeaponStorage("Homing", 2)
    p:setRepairCrewCount(2)
    for _, id in ipairs(c.upgrades) do RT.applyUpgrade(p, id) end
    if is_primary and c.ship_condition then
        local cond = c.ship_condition
        local cm_f, cm_r = p:getShieldsMax()
        p:setHull(p:getHullMax() * cond.hull_pct)
        p:setShields(cm_f * cond.front_shield_pct, cm_r * cond.rear_shield_pct)
        p:setEnergy(p:getMaxEnergy() * cond.energy_pct)
    end
    p:setReputationPoints(opts.credits ~= nil and opts.credits or c.credits or 0)
    -- onNewPlayerShip fires during setTemplate above and may have already registered
    -- the ship (e.g. to preserve a non-Independent faction). Guard against duplicates.
    local already = false
    for _, existing in ipairs(RT.players) do
        if existing == p then already = true; break end
    end
    if not already then table.insert(RT.players, p) end
    RT.player = RT.players[1]   -- backward-compat alias always points to first ship
    RT.named[cs] = p
    return p
end

--------------------------------------------------------------------------------
-- Objectives (shown on Relay and Operations, logged to ship's log)
--------------------------------------------------------------------------------

function RT.setObjective(text, silent)
    RT.objective = RT.cleanText(text, 160)
    RT.forEachPlayer(function(p)
        p:addCustomInfo("relay", "rt_objective", "Objective: " .. RT.objective, 0)
        p:addCustomInfo("operations", "rt_objective_ops", "Objective: " .. RT.objective, 0)
        if not silent then p:addToShipLog("New objective: " .. RT.objective, "#80C0FF") end
    end)
    if DIR then DIR.emit("objective", {text = RT.objective}) end
end

-- Remove the objective line from the Relay and Operations screens (used when a GM jump lands
-- in a state that has no objective).
function RT.clearObjective()
    RT.objective = ""
    RT.forEachPlayer(function(p)
        pcall(function() p:removeCustom("rt_objective") end)
        pcall(function() p:removeCustom("rt_objective_ops") end)
    end)
end

--------------------------------------------------------------------------------
-- Stations and comms
--------------------------------------------------------------------------------

-- Create a station that uses the campaign comms menu.
--   opts: template, faction, callsign, x, y, shop (bool), flavor (string), description
function RT.station(opts)
    local s = SpaceStation():setTemplate(opts.template or "Small Station")
    s:setFaction(opts.faction or "Independent"):setPosition(opts.x, opts.y)
    if opts.callsign then s:setCallSign(opts.callsign) end
    if opts.description then s:setDescription(opts.description) end
    local cs = s:getCallSign()
    RT.stations[cs] = {entity = s, shop = opts.shop or false, flavor = opts.flavor or "", hooks = {}}
    RT.named[cs] = s
    s:setCommsFunction(RT.stationComms)
    return s
end

-- Add scenario-specific comms replies to a station.
-- fn(source, target, info) is called while the menu is built; it may call addCommsReply.
function RT.addStationHook(callsign, fn)
    local info = RT.stations[callsign]
    if info then table.insert(info.hooks, fn) end
end

-- Returns a one-line reputation-flavored aside appended to the station greeting,
-- or nil when standing is neutral. Only Concord and Independent have voiced drift.
local function _repDrift(source, faction)
    local rep = RT.getReputation(faction)
    local cs  = source:getCallSign()
    if faction == "Concord" then
        if     rep >  1000 then return '"Your record here is noted, ' .. cs .. '. We appreciate crews that keep their word."'
        elseif rep >   250 then return '"Welcome, ' .. cs .. '. You\'re known here."'
        elseif rep < -1000 then return '"This channel is monitored, ' .. cs .. '. State your business and go."'
        elseif rep <  -250 then return '"We\'re watching your transponder, ' .. cs .. '. Keep this brief."'
        end
    elseif faction == "Independent" then
        if     rep >  1000 then return '"You\'ve made some friends out here, ' .. cs .. '. That matters."'
        elseif rep >   250 then return '"Word\'s gotten around. Good word, in your case."'
        elseif rep < -1000 then return '"You\'re not exactly popular right now. What do you need?"'
        elseif rep <  -250 then return '"Heard a few things about your crew lately. Not all of them good."'
        end
    end
    return nil
end

function RT.stationComms(source, target)
    local info = RT.stations[target:getCallSign()] or {flavor = "", hooks = {}}
    if source:isEnemy(target) then
        setCommsMessage("Static. Then a click. They've cut the channel.")
        return
    end
    local msg = info.flavor ~= "" and info.flavor or ("This is " .. target:getCallSign() .. ". State your business.")
    local drift = _repDrift(source, target:getFaction())
    if drift then msg = msg .. "\n\n" .. drift end
    if source:isDocked(target) then
        msg = msg .. "\n\nYou're docked. Balance: " .. RT.credits(source) .. " credits."
    end
    setCommsMessage(msg)

    for _, hook in ipairs(info.hooks) do
        local ok, err = pcall(hook, source, target, info)
        if not ok then log("[RT] station hook failed: " .. tostring(err)) end
    end

    if source:isDocked(target) then
        if info.shop then
            addCommsReply("Shipwright: browse upgrades", function(s, t) RT.shipwrightMenu(s, t) end)
        end
        addCommsReply("Restock missiles (15 cr each)", function(s, t) RT.restockMenu(s, t) end)
    end

    addCommsReply("Any news worth hearing?", function(s, t)
        -- Deliver a rumor with cooldown, plus ping the director for dynamic content
        -- RUMORS.get returns nil when the rumors plugin is disabled.
        local rumor = RUMORS and RUMORS.get and RUMORS.get(s:getCallSign(), t:getFaction())
        local rumor_text = "\"" .. (rumor or "Nothing worth repeating right now.") .. "\""
        setCommsMessage(rumor_text)
        if DIR then
            DIR.emit("comms_ask", {station = t:getCallSign(), faction = t:getFaction(), topic = "rumours"}, "normal")
        end
        addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
    end)
end

-- Does this station's shipwright sell the upgrade? shop = true sells everything.
function RT.stocks(info, id)
    if info.shop == true then return true end
    if type(info.shop) ~= "table" then return false end
    for _, s in ipairs(info.shop) do
        if s == id then return true end
    end
    return false
end

function RT.shipwrightMenu(source, target)
    local info = RT.stations[target:getCallSign()] or {shop = true}
    local lines = {"Shipwright. Balance: " .. RT.credits(source) .. " credits.\n"}
    local any = false
    for _, u in ipairs(RT.UPGRADES) do
        if RT.stocks(info, u.id) and not RT.hasUpgrade(u.id) and (u.requires == nil or RT.hasUpgrade(u.requires))
           and (u.available == nil or u.available(source)) then
            any = true
            table.insert(lines, string.format("%s (%d cr): %s", u.name, u.cost, u.desc))
            addCommsReply(string.format("Buy %s (%d)", u.name, u.cost), function(s, t)
                if RT.credits(s) < u.cost then
                    setCommsMessage("\"Come back when you can pay for it.\"")
                else
                    RT.addCredits(-u.cost, "bought " .. u.name, s)
                    table.insert(RT.campaign.upgrades, u.id)
                    RT.applyUpgrade(s, u.id)
                    RT.saveCampaign()
                    setCommsMessage("Installed: " .. u.name .. ". Try not to scratch it.")
                    if DIR then DIR.emit("upgrade", {id = u.id, how = "bought", station = t:getCallSign()}) end
                end
                addCommsReply("Back to shipwright", function(s2, t2) RT.shipwrightMenu(s2, t2) end)
            end)
        end
    end
    if not any then table.insert(lines, "Nothing here I can bolt onto that hull. Try another yard.") end
    -- Point the crew at where else to look.
    local elsewhere = {}
    for cs, other in pairs(RT.stations) do
        if cs ~= target:getCallSign() and other.shop then
            for _, u in ipairs(RT.UPGRADES) do
                if RT.stocks(other, u.id) and not RT.hasUpgrade(u.id) and not RT.stocks(info, u.id) then
                    elsewhere[u.name] = elsewhere[u.name] or cs
                end
            end
        end
    end
    local tips = {}
    for name, cs in pairs(elsewhere) do table.insert(tips, name .. " (" .. cs .. ")") end
    table.sort(tips)
    if #tips > 0 then
        table.insert(lines, "\nHeard you can get elsewhere: " .. table.concat(tips, ", ", 1, math.min(#tips, 6)) .. ".")
    end
    setCommsMessage(table.concat(lines, "\n"))
    addCommsReply("Back", function(s, t) RT.stationComms(s, t) end)
end

function RT.restockMenu(source, target)
    setCommsMessage("Missiles are 15 credits apiece. Balance: " .. RT.credits(source))
    for _, w in ipairs({"Homing", "HVLI"}) do
        local missing = source:getWeaponStorageMax(w) - source:getWeaponStorage(w)
        if missing > 0 then
            addCommsReply(string.format("Fill %s (%d for %d cr)", w, missing, missing * 15), function(s, t)
                local m = s:getWeaponStorageMax(w) - s:getWeaponStorage(w)
                local cost = m * 15
                if RT.credits(s) < cost then
                    setCommsMessage("\"You're short.\"")
                else
                    RT.addCredits(-cost, "restocked " .. w, s)
                    s:setWeaponStorage(w, s:getWeaponStorageMax(w))
                    setCommsMessage("Loaded.")
                end
                addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
            end)
        end
    end
    addCommsReply("Back", function(s, t) RT.stationComms(s, t) end)
end

--------------------------------------------------------------------------------
-- Common GM tools
--------------------------------------------------------------------------------

function RT.addCampaignGMFunctions()
    -- Campaign status / stats / achievements live in the scenario's "Campaign Status" popup.
    -- Credit adjustment buttons removed: scenarios provide their own granular controls

    -- (No "Save campaign" button: the campaign autosaves every 60 s and on every flag,
    -- reputation, credit and job event. Use a backup slot to keep a restore point.)
    addGMFunction("Backup campaign", function() RT.showBackupMenu() end)
    addGMFunction("Restore campaign", function() RT.showRestoreMenu() end)
    addGMFunction("Sounds...", function() RT.showSoundMenu() end)
end

--------------------------------------------------------------------------------
-- Campaign backups: numbered slots in script storage (the GM console has no text input).
-- A slot is a copy of the campaign JSON under "<campaign key>.backup.<n>". Restoring writes the
-- slot over the live save and freezes saving, because the running game would otherwise
-- overwrite it from memory: restart the scenario and choose Continue to load it.
--------------------------------------------------------------------------------

RT.BACKUP_SLOTS = 6

function RT.backupKey(n) return RT.CAMPAIGN_KEY .. ".backup." .. n end

local function _fmtHM(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    return string.format("%dh%02d", seconds // 3600, (seconds % 3600) // 60)
end

-- Button label for a slot: "2: 1h25 4200cr" or "2: empty". Max ~18 characters.
function RT.backupLabel(n)
    local raw = getScriptStorage():get(RT.backupKey(n))
    if type(raw) ~= "string" or raw == "" then return n .. ": empty" end
    local ok, c = pcall(fromJSON, raw)
    if not ok or type(c) ~= "table" then return n .. ": unreadable" end
    local secs = type(c.stats) == "table" and c.stats.play_seconds or 0
    return string.format("%d: %s %dcr", n, _fmtHM(secs), math.floor(tonumber(c.credits) or 0))
end

function RT.backupCampaign(n)
    if RT.campaign == nil then return false end
    if RT._saves_frozen then return false end
    RT.saveCampaign()   -- sync credits and extra ships from the live ships first
    getScriptStorage():set(RT.backupKey(n), toJSON(RT.campaign))
    return true
end

function RT.restoreCampaign(n)
    local raw = getScriptStorage():get(RT.backupKey(n))
    if type(raw) ~= "string" or raw == "" then return false end
    -- Keep what we are about to overwrite, in case the restore was a mistake.
    local live = getScriptStorage():get(RT.CAMPAIGN_KEY)
    if type(live) == "string" and live ~= "" then
        getScriptStorage():set(RT.CAMPAIGN_KEY .. ".before_restore", live)
    end
    getScriptStorage():set(RT.CAMPAIGN_KEY, raw)
    RT._saves_frozen = true
    return true
end

local function _backToMainGM()
    clearGMFunctions()
    if addSessionGMFunctions then addSessionGMFunctions() else RT.addCampaignGMFunctions() end
end

function RT.showBackupMenu()
    clearGMFunctions()
    addGMFunction("← Back to Main", _backToMainGM)
    if RT._saves_frozen then
        addGMFunction("Restart to unfreeze", function()
            addGMMessage("A backup was restored. Restart the scenario and choose Continue; saving is paused until then.")
        end)
        return
    end
    for n = 1, RT.BACKUP_SLOTS do
        addGMFunction(RT.backupLabel(n), function()
            local ok = RT.backupCampaign(n)
            addGMMessage(ok and ("Campaign backed up to slot " .. n .. ".") or "Backup failed: no campaign loaded.")
            RT.showBackupMenu()   -- redraw with the updated label
        end)
    end
end

function RT.showRestoreMenu()
    clearGMFunctions()
    addGMFunction("← Back to Main", _backToMainGM)
    for n = 1, RT.BACKUP_SLOTS do
        local label = RT.backupLabel(n)
        local empty = label:find("empty", 1, true) ~= nil
        addGMFunction(label, function()
            if empty then
                addGMMessage("Slot " .. n .. " is empty.")
                return
            end
            -- Confirmation step: restoring replaces the whole saved campaign.
            clearGMFunctions()
            addGMFunction("Cancel", function() RT.showRestoreMenu() end)
            addGMFunction("Restore slot " .. n, function()
                if RT.restoreCampaign(n) then
                    addGMMessage("Slot " .. n .. " restored. Restart the scenario and choose Continue to load it. "
                        .. "Saving is paused until you restart. (Your previous save is kept under '.before_restore'.)")
                else
                    addGMMessage("Restore failed: slot " .. n .. " is empty or unreadable.")
                end
                RT.showRestoreMenu()
            end)
        end)
    end
end

-- GM submenu: enable/disable toggle, then one test button per cue in RT.SOUNDS
-- (played immediately on the server). Tests work even while cues are disabled.
function RT.showSoundMenu()
    clearGMFunctions()
    addGMFunction("← Back to Main", function()
        clearGMFunctions()
        -- A scenario's addSessionGMFunctions builds the whole main menu (campaign buttons included).
        if addSessionGMFunctions then addSessionGMFunctions() else RT.addCampaignGMFunctions() end
    end)
    addGMFunction("Sound cues: " .. (RT.sound_enabled and "ON" or "OFF"), function()
        RT.sound_enabled = not RT.sound_enabled
        if not RT.sound_enabled then
            RT._sound_queue = {}
            RT._sound_loops = {}
        end
        RT.showSoundMenu()  -- redraw so the label shows the new state
    end)
    local ids = {}
    for id in pairs(RT.SOUNDS) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local entry = RT.SOUNDS[id]
        addGMFunction(string.format("%s (%.1fs)", id, entry.seconds or 0), function()
            local ok, err = pcall(playSoundFile, entry.file)
            if not ok then
                addGMMessage("Could not play " .. entry.file .. ": " .. tostring(err))
            end
            RT._sound_busy_until = getScenarioTime() + (entry.seconds or 2)
        end)
    end
end

--------------------------------------------------------------------------------
-- Per-frame housekeeping. Call from update(delta).
--------------------------------------------------------------------------------

RT._last_save  = 0
RT._hull_marks = {}   -- callsign -> {75=bool, 50=bool, 25=bool}

function RT.update(delta)
    RT.updateTimers()
    RT.updateSounds()
    if STATS then STATS.update(delta) end

    -- Sync RT.players with EmptyEpsilon's active player ships.
    -- Catches ships spawned through GM console or other means outside RT.spawnPlayer().
    local active = getActivePlayerShips()
    for _, ship in ipairs(active) do
        local found = false
        for _, p in ipairs(RT.players) do
            if p == ship then found = true; break end
        end
        if not found then
            -- Set to campaign faction (default: Independent)
            ship:setFaction(RT.PLAYER_FACTION)
            table.insert(RT.players, ship)
            RT.player = RT.players[1]  -- Update backward-compat alias
            -- Apply campaign upgrades but NOT credits (ships are financially independent)
            if RT.campaign then
                for _, id in ipairs(RT.campaign.upgrades) do
                    RT.applyUpgrade(ship, id)
                end
                -- New ships start with 0 credits - they earn their own way
                ship:setReputationPoints(0)
            end
            log("[RT] Registered new player ship: " .. ship:getCallSign() .. " (set to " .. RT.PLAYER_FACTION .. ", 0 credits)")
        end
    end

    local now = getScenarioTime()
    if RT.anyPlayerAlive() then
        -- Autosave credits every 60s so a crash doesn't eat the crew's money.
        if now - RT._last_save > 60 then
            RT._last_save = now
            RT.saveCampaign()
        end
    end
    -- Report hull thresholds once per ship (75/50/25%).
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then
            local cs = p:getCallSign()
            if not RT._hull_marks[cs] then RT._hull_marks[cs] = {} end
            local marks = RT._hull_marks[cs]
            local pct = p:getHull() / p:getHullMax() * 100
            for _, mark in ipairs({75, 50, 25}) do
                if pct < mark and not marks[mark] then
                    marks[mark] = true
                    if DIR then DIR.emit("player_damaged", {hull_pct = math.floor(pct), ship = cs}, mark <= 50 and "high" or "normal") end
                elseif pct > mark + 10 then
                    marks[mark] = nil
                end
            end
        end
    end
end

-- Helpers that extend RT. Loaded last: they only use RT at call time.
require("ragtag/voice.lua")
require("ragtag/stats.lua")
