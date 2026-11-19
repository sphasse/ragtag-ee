-- ee/ragtag/core.lua
-- Shared library for the "Long Haul" ragtag campaign.
--
-- Provides:
--   * Campaign persistence across sessions (getScriptStorage, key "ragtag.campaign")
--   * Player ship creation with purchased upgrades re-applied every session
--   * Per-ship records: credits, standing and upgrades of each player ship (RT.shipRecord)
--   * A generic station comms menu with a shipwright (upgrade shop) and rumours
--     (core/stations.lua), reputation (core/reputation.lua), upgrades (core/upgrades.lua),
--     sound cues (core/sound.lua), GM backup tools (core/gm_tools.lua): see the requires at the end
--   * Objective display on Relay / Operations screens
--   * Small helpers (named object registry, distance, timers)
--
-- Usage in a scenario:
--   require("utils.lua")
--   require("ragtag/core.lua")
--   require("ragtag/verse.lua")
--   require("ragtag/director.lua")   -- optional: the AI director's mailbox (observation only)
--
-- Written against the ECS-era EmptyEpsilon scripting API (2024+ releases).

RT = RT or {}
RT.VERSION = "1.0"
RT.CAMPAIGN_KEY = "ragtag.campaign"   -- set per campaign by RT.useCampaign()
RT.SHIP_KEY     = "ragtag.ship"        -- portable ship record, not tied to any campaign
RT.PLAYER_FACTION = "Independent"
RT.PLAYER_TEMPLATE = "Flavia P.Falcon"

RT.named = {}          -- callsign -> entity, for objects addressed by name (see RT.find)
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

function RT.register(entity, callsign)
    if callsign then entity:setCallSign(callsign) end
    RT.named[entity:getCallSign()] = entity

    -- Automatically track CpuShips for reputation on kill
    -- Check if getTypeName exists and is actually a function before calling
    -- KNOWN GAP: getTypeName() returns the ship's TEMPLATE name ("MT52 Hornet"), never
    -- "CpuShip", so this test has never matched and the "destroy any ship: -200" penalty
    -- (docs/REPUTATION.md) does not fire. isObjectType(entity, "CpuShip") would switch it on;
    -- that changes the balance of every fight and arc battle, so it is left for a deliberate
    -- decision. RT.trackShipForReputation itself works and charges the ship that made the kill
    -- (tests/core/records.lua).
    if entity.getTypeName and type(entity.getTypeName) == "function" then
        local ok, typename = pcall(function() return entity:getTypeName() end)
        if ok and typename == "CpuShip" then
            RT.trackShipForReputation(entity)
        end
    end

    return entity
end

-- Find an entity by callsign: the registry first (RT.register / RT.station / RT.spawnPlayer),
-- then one pass over the whole map. The result does not depend on where any player is.
--
-- A callsign is a NAME, not an identity: two ships can carry the same one, and a ship can be
-- renamed. Use RT.find for things that are addressed by name (universe places, a speaker the GM
-- typed); code that spawns a ship keeps the entity it got back and never looks it up again.
RT.MAP_RADIUS = 2000000
function RT.find(callsign)
    if callsign == nil or callsign == "" then return nil end
    local e = RT.named[callsign]
    if RT.valid(e) then return e end
    for _, obj in ipairs(getObjectsInRadius(0, 0, RT.MAP_RADIUS)) do
        if obj.getCallSign and obj:isValid() and obj:getCallSign() == callsign then
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

-- The entry of RT.players equal to `ship` (script calls can hand out different Lua objects for
-- the same ship, so per-ship tables are keyed by the one in RT.players). nil for anything else.
function RT.playerShip(ship)
    if ship == nil then return nil end
    for _, p in ipairs(RT.players) do
        if p == ship then return p end
    end
    return nil
end

function RT.isPlayer(entity)
    if not RT.valid(entity) then return false end
    for _, p in ipairs(RT.players) do
        if p == entity then return true end
    end
    return false
end

-- Nearest valid player ship to (x, y), and its distance. Returns nil (and math.huge) when no
-- players are alive.
function RT.nearestPlayer(x, y)
    local best, best_dist = nil, math.huge
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then
            local px, py = p:getPosition()
            local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
            if d < best_dist then best, best_dist = p, d end
        end
    end
    return best, best_dist
end

-- True when any player ship is within `r` of `obj` (several ships: not only the primary one).
function RT.playerWithin(obj, r)
    local x, y = obj:getPosition()
    local _, d = RT.nearestPlayer(x, y)
    return d <= r
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
        -- The primary ship's record (see "Per-ship records"): credits, upgrades, reputation.
        credits = 150,
        upgrades = {},    -- list of upgrade ids, applied in purchase order
        extra_ships = {}, -- [{name, credits, reputation, upgrades}, ...] one record per other ship
        sessions = {},   -- "s1" -> {outcome="success", at=...}
        flags = {},      -- story flags: string -> bool/number/string
        notes = {},      -- short human-readable campaign log lines
        discovered = {}, -- names of charted regions (see ragtag_verse.lua)
        stats = {},      -- statistics (see ragtag/stats.lua)
        achievements = {}, -- id -> {at, session} (see ragtag/stats.lua)
        reputation = {   -- the primary ship's standing with each faction (unbounded; thresholds at ±200/±400/±500)
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
    -- Ship records ARE the save (see "Per-ship records"); only the name a returning crew is
    -- found by needs refreshing, in case a ship was renamed. Ships not in this session keep
    -- their saved record.
    for _, st in ipairs(RT._ship_state) do
        if st.rec and st.campaign == RT.campaign and st.ship ~= RT.player and RT.valid(st.ship) then
            st.rec.name = st.ship:getCallSign()
        end
    end
    getScriptStorage():set(RT.CAMPAIGN_KEY, toJSON(RT.campaign))
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

-- Mark a session finished and persist. outcome: "success", "partial", "failed"
function RT.completeSession(session_id, outcome, note)
    RT.campaign.sessions[session_id] = {outcome = outcome, at = math.floor(getScenarioTime())}
    if note then RT.note(session_id .. ": " .. note) end
    RT.saveCampaign()
end

--------------------------------------------------------------------------------
-- Per-ship records
--------------------------------------------------------------------------------

-- Everything a player ship owns is in ONE record with the same three fields for every ship:
--   credits     number
--   reputation  faction -> standing
--   upgrades    list of upgrade ids, in purchase order
-- The primary ship's record is the campaign table itself (campaign.credits / .reputation /
-- .upgrades, where saves have always kept them); every other ship's is an entry of
-- campaign.extra_ships, which also carries `name`. RT.shipRecord(ship) returns the right one, and
-- RT.credits / RT.addReputation / RT.hasUpgrade and friends are thin wrappers over it. There are
-- no side tables to copy into the save: changing a record changes the save.
--
-- Identity: a record is bound to the ship ENTITY the first time it is asked for and stays with
-- it for the session, whatever the ship is renamed to. The callsign is only how a crew that
-- rejoins in a later session finds its record again (saveCampaign refreshes `name`).
--
-- "No ship given" means the primary ship. That default exists for story arcs, which belong to
-- the primary ship; everything else (stations, jobs, world plugins, scenarios, GM tools) knows
-- which ship it is dealing with and must pass it. tools/check.py rejects RT.addCredits /
-- RT.addReputation / RT.grantUpgrade without a ship outside ee/ragtag/missions/.

-- Session state per player ship: {ship, rec, campaign, shown, outfitted, hull_marks}, one entry
-- per ship ever seen this session (destroyed ones included), found with `==` on the entity.
RT._ship_state = {}

function RT.shipState(ship)
    local p = RT.playerShip(ship)
    if p == nil then return nil end
    for _, st in ipairs(RT._ship_state) do
        if st.ship == p then return st end
    end
    local st = {ship = p, hull_marks = {}}
    RT._ship_state[#RT._ship_state + 1] = st
    return st
end

local function _normalise(rec)
    rec.credits = math.max(0, math.floor(tonumber(rec.credits) or 0))
    if type(rec.reputation) ~= "table" then rec.reputation = {} end
    if type(rec.upgrades) ~= "table" then rec.upgrades = {} end
    return rec
end

-- The record of a player ship (default, and for anything that is not a player ship: the primary
-- ship). nil when there is no campaign or no such ship yet.
function RT.shipRecord(ship)
    local c = RT.campaign
    local p = RT.playerShip(ship) or RT.player
    if c == nil or p == nil then return nil end
    if p == RT.player then return _normalise(c) end
    local st = RT.shipState(p)
    if st.rec and st.campaign == c then return st.rec end
    if not RT.valid(p) then return nil end
    if type(c.extra_ships) ~= "table" then c.extra_ships = {} end
    -- A returning crew: the saved record under this callsign, unless another live ship has it.
    -- (A destroyed ship's record is free: the crew's rebuilt ship under that name takes it over.)
    local name, rec = p:getCallSign(), nil
    for _, e in ipairs(c.extra_ships) do
        if type(e) == "table" and e.name == name then
            local taken = false
            for _, other in ipairs(RT._ship_state) do
                if other.rec == e and other.campaign == c and other.ship ~= p and RT.valid(other.ship) then
                    taken = true
                end
            end
            if not taken then rec = e; break end
        end
    end
    if rec == nil then
        rec = {name = name}
        c.extra_ships[#c.extra_ships + 1] = rec
    end
    st.rec, st.campaign = _normalise(rec), c
    return rec
end

--------------------------------------------------------------------------------
-- Credits
--------------------------------------------------------------------------------

-- Credits are kept in the ship's record, one balance per player ship, and shown on each ship's
-- Relay and Operations screens as a "Credits: N" line.
--
-- They are NOT EmptyEpsilon's "reputation points": the engine keeps those per FACTION, so every
-- Independent player ship would share one number (and any ship could overwrite it). The engine
-- number is unused and held at 0 (RT.update); the stock "Reputation" readout therefore reads 0.
-- Nothing outside this file may call the ReputationPoints methods (check.py enforces it).

local function _showCredits(p)
    local st = RT.shipState(p)
    if st == nil or not RT.valid(p) then return end
    local rec = RT.shipRecord(p)
    local n = rec and rec.credits or 0
    if st.shown == n then return end
    st.shown = n
    local txt = "Credits: " .. n
    pcall(function()
        p:addCustomInfo("relay", "rt_credits_relay", txt, 0)
        p:addCustomInfo("operations", "rt_credits_ops", txt, 0)
    end)
end

-- A ship's credit balance (default: the primary ship).
function RT.credits(ship)
    local rec = RT.shipRecord(ship)
    return rec and rec.credits or 0
end

-- Set a ship's balance outright (ship creation, GM tools). Default: the primary ship.
function RT.setCredits(amount, ship)
    local rec = RT.shipRecord(ship)
    if rec == nil then return end
    rec.credits = math.max(0, math.floor(tonumber(amount) or 0))
    _showCredits(RT.playerShip(ship) or RT.player)
end

-- Add (or with a negative amount, take) credits. Default: the primary ship. Balances never go
-- below zero.
function RT.addCredits(amount, reason, ship)
    ship = RT.playerShip(ship) or RT.player
    local rec = RT.shipRecord(ship)
    if rec == nil or not RT.valid(ship) then return end
    amount = math.floor(amount)
    rec.credits = math.max(0, rec.credits + amount)
    _showCredits(ship)
    local sign = amount >= 0 and "+" or ""
    ship:addToShipLog(string.format("Credits %s%d (%s). Balance: %d", sign, amount, reason or "misc", rec.credits), "#E0C060")
    if STATS then STATS.noteCredits(amount, reason) end
    RT.saveCampaign()
end

-- Per frame: make sure every ship has its record bound and its balance shown, and hold the
-- engine's shared number at 0 so nothing (a stock script, a GM action) can create a second,
-- phantom balance.
function RT.updateCredits()
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then
            _showCredits(p)
            if (p:getReputationPoints() or 0) ~= 0 then p:setReputationPoints(0) end
        end
    end
end

--------------------------------------------------------------------------------
-- Player ship
--------------------------------------------------------------------------------

-- Add a ship to RT.players (once). For ships the engine created (the "Create player ship"
-- screen): the scenario names it in onNewPlayerShip and calls this; its record is bound and its
-- upgrades applied on the next RT.update, by the callsign it has then.
function RT.adoptPlayer(ship)
    if RT.playerShip(ship) == nil then table.insert(RT.players, ship) end
    RT.player = RT.players[1]   -- backward-compat alias always points to first ship
    RT.promotePrimary()
    return ship
end

-- The primary ship (RT.players[1]) owns the campaign record and the story arcs. When it has been
-- destroyed and a live ship carries the campaign's ship name (a rebuilt ship that joined under
-- it, or a ship renamed to it), that ship becomes the primary: the dead entry leaves slot 1, and
-- the campaign record (credits, standing, upgrades) and the arcs go to the new ship. Called from
-- RT.adoptPlayer and every RT.update.
function RT.promotePrimary()
    local c = RT.campaign
    if c == nil or c.ship_name == nil or #RT.players == 0 or RT.valid(RT.players[1]) then return end
    for i = 2, #RT.players do
        local p = RT.players[i]
        if RT.valid(p) and p:getCallSign() == c.ship_name then
            RT.chargeLoss(RT.players[1])   -- before the dead primary leaves the list
            table.remove(RT.players, i)
            RT.players[1] = p            -- replaces the dead primary
            RT.player = p
            -- Forget any record this ship was given as a second ship; drop it from the save when
            -- nothing was put in it. The ship now reads the campaign record and gets its upgrades.
            for _, st in ipairs(RT._ship_state) do
                if st.ship == p then
                    local rec = st.rec
                    if rec and type(c.extra_ships) == "table" and (rec.credits or 0) == 0
                       and #(rec.upgrades or {}) == 0 and next(rec.reputation or {}) == nil then
                        for k = #c.extra_ships, 1, -1 do
                            if c.extra_ships[k] == rec then table.remove(c.extra_ships, k) end
                        end
                    end
                    st.rec, st.campaign, st.outfitted, st.shown = nil, nil, false, nil
                end
            end
            RT.outfit(p)
            log("[RT] " .. c.ship_name .. " is back: it is the primary ship again.")
            p:addToShipLog("Registry: " .. c.ship_name .. " is back on the books. The crew's accounts and contracts are yours.", "#E0C060")
            RT.emit("primary_restored", {ship = c.ship_name}, "normal")
            return
        end
    end
end

-- Losing a ship costs its crew a share of their credits (RT.DEATH_PENALTY, half). Charged once,
-- to the dead ship's own record (the primary ship's is the campaign), when RT.update first sees
-- a ship that was alive gone, or when a rebuilt ship takes the dead primary's place. Upgrades
-- and standing are kept. The rebuilt ship's log says what the loss cost (RT.outfit).
-- Note: a ship the GM deletes counts as lost too.
RT.DEATH_PENALTY = 0.5

function RT.chargeLoss(ship)
    local st = RT.shipState(ship)
    if st == nil or st.loss_charged or not st.was_alive or RT.valid(st.ship) then return end
    st.loss_charged = true
    local rec = RT.shipRecord(st.ship)
    if rec == nil then return end
    local name = (rec == RT.campaign and rec.ship_name) or rec.name or "a player ship"
    local lost = math.floor((rec.credits or 0) * RT.DEATH_PENALTY)
    rec.credits = (rec.credits or 0) - lost
    rec.loss_note = (rec.loss_note or 0) + lost
    if STATS then STATS.noteCredits(-lost, "ship lost") end
    log(string.format("[RT] %s was lost: -%d credits (balance %d)", name, lost, rec.credits))
    RT.emit("ship_lost", {ship = name, credits_lost = lost, credits = rec.credits, primary = (rec == RT.campaign)}, "high")
    RT.saveCampaign()
end

-- Apply the upgrades in a ship's record, once per ship per session; and tell a crew whose last
-- ship was lost what that cost them.
function RT.outfit(ship)
    local st = RT.shipState(ship)
    if st == nil or st.outfitted then return end
    st.outfitted = true
    for _, id in ipairs(RT.upgrades(ship)) do RT.applyUpgrade(st.ship, id) end
    local rec = RT.shipRecord(st.ship)
    if rec and rec.loss_note and RT.valid(st.ship) then
        st.ship:addToShipLog(string.format("Insurance didn't cover it: losing the last hull cost %d credits. Balance: %d",
            rec.loss_note, rec.credits or 0), "#E0C060")
        rec.loss_note = nil
    end
end

-- opts (optional 4th arg): {callsign, template, faction, credits}
-- First call creates the primary ship (RT.player alias). Subsequent calls add
-- another ship. Extra ships get their own callsign (opts.callsign or
-- primary_name.."-2", "-3", …) and their own credits (opts.credits, default 0) and standing.
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
    -- onNewPlayerShip fires during setTemplate above and may have already registered
    -- the ship (e.g. to preserve a non-Independent faction). Guard against duplicates.
    RT.adoptPlayer(p)
    -- The ship's own upgrades (its record, found by the callsign set above), then wear.
    RT.outfit(p)
    if is_primary and c.ship_condition then
        local cond = c.ship_condition
        local cm_f, cm_r = p:getShieldsMax()
        p:setHull(p:getHullMax() * cond.hull_pct)
        p:setShields(cm_f * cond.front_shield_pct, cm_r * cond.rear_shield_pct)
        p:setEnergy(p:getMaxEnergy() * cond.energy_pct)
    end
    -- Credits (see "Credits"): an explicit amount, else what the save holds for this ship.
    if opts.credits ~= nil then RT.setCredits(opts.credits, p) end
    RT.named[cs] = p
    return p
end

--------------------------------------------------------------------------------
-- Objectives (shown on Relay and Operations, logged to ship's log)
--------------------------------------------------------------------------------

-- Several objectives can be active at once, each under its own key. The default key "main"
-- is the arc/job objective everything already uses (and RT.objective mirrors it for
-- observers); an arc can add a second line under its own key, e.g. RT.setObjective("Hack the
-- Annex", true, "boneyard"), and remove just that line with RT.clearObjective("boneyard").
-- Each shows as its own "Objective: ..." line on Relay and Operations.
RT.objectives      = {}   -- key -> text
RT._objective_keys = {}   -- insertion order, for the display order

local function _objKeys(key)
    if key == "main" then return "rt_objective", "rt_objective_ops" end
    return "rt_objective_" .. key, "rt_objective_ops_" .. key
end

function RT.setObjective(text, silent, key)
    key = key or "main"
    local clean = RT.cleanText(text, 160)
    if RT.objectives[key] == nil and key ~= "main" then
        RT._objective_keys[#RT._objective_keys + 1] = key
    end
    RT.objectives[key] = clean
    if key == "main" then RT.objective = clean end
    local order = 0
    for i, k in ipairs(RT._objective_keys) do if k == key then order = i end end
    local relay_key, ops_key = _objKeys(key)
    RT.forEachPlayer(function(p)
        p:addCustomInfo("relay", relay_key, "Objective: " .. clean, order)
        p:addCustomInfo("operations", ops_key, "Objective: " .. clean, order)
        if not silent then p:addToShipLog("New objective: " .. clean, "#80C0FF") end
    end)
    RT.emit("objective", {text = clean, key = key})
end

-- Remove one objective line (by key), or all of them when no key is given (used when a GM
-- jump lands in a state that has no objective).
function RT.clearObjective(key)
    local keys
    if key then
        keys = {key}
    else
        keys = {"main"}
        for _, k in ipairs(RT._objective_keys) do keys[#keys + 1] = k end
    end
    for _, k in ipairs(keys) do
        RT.objectives[k] = nil
        if k == "main" then RT.objective = "" end
        local relay_key, ops_key = _objKeys(k)
        RT.forEachPlayer(function(p)
            pcall(function() p:removeCustom(relay_key) end)
            pcall(function() p:removeCustom(ops_key) end)
        end)
    end
    if not key then RT._objective_keys = {} end
end

--------------------------------------------------------------------------------
-- Per-frame housekeeping. Call from update(delta).
--------------------------------------------------------------------------------

RT._last_save  = 0

function RT.update(delta)
    RT.updateTimers()
    RT.updateSounds()
    if STATS then STATS.update(delta) end

    -- Sync RT.players with EmptyEpsilon's active player ships.
    -- Catches ships spawned through GM console or other means outside RT.spawnPlayer().
    local active = getActivePlayerShips()
    for _, ship in ipairs(active) do
        if RT.playerShip(ship) == nil then
            -- Set to campaign faction (default: Independent)
            ship:setFaction(RT.PLAYER_FACTION)
            RT.adoptPlayer(ship)
            log("[RT] Registered new player ship: " .. ship:getCallSign() .. " (set to " .. RT.PLAYER_FACTION .. ")")
        end
    end
    -- A ship lost since the last frame pays for it (RT.chargeLoss), before anything replaces it.
    for _, p in ipairs(RT.players) do
        local st = RT.shipState(p)
        if RT.valid(p) then st.was_alive = true else RT.chargeLoss(p) end
    end
    RT.promotePrimary()   -- a ship renamed to the lost primary's name takes its place
    -- Credits, standing and upgrades are per ship: each ship's record is found by its callsign
    -- the first time it is needed (a new record, with nothing in it, for a ship never seen).
    if RT.campaign then
        for _, p in ipairs(RT.players) do
            if RT.valid(p) then RT.outfit(p) end
        end
    end

    RT.updateCredits()

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
            local marks = RT.shipState(p).hull_marks
            local pct = p:getHull() / p:getHullMax() * 100
            for _, mark in ipairs({75, 50, 25}) do
                if pct < mark and not marks[mark] then
                    marks[mark] = true
                    RT.emit("player_damaged", {hull_pct = math.floor(pct), ship = cs}, mark <= 50 and "high" or "normal")
                elseif pct > mark + 10 then
                    marks[mark] = nil
                end
            end
        end
    end
end

-- The rest of core, one file per concern. Loaded here because they only use RT at call time.
require("ragtag/core/events.lua")       -- RT.emit / RT.on (event bus), scripted beats, state providers
require("ragtag/core/sound.lua")        -- RT.sound, RT.soundLoop, the GM "Sounds..." menu
require("ragtag/core/reputation.lua")   -- RT.addReputation, RT.getReputation, RT.onKill, kill tracking
require("ragtag/core/upgrades.lua")     -- RT.UPGRADES, RT.applyUpgrade, RT.grantUpgrade
require("ragtag/core/stations.lua")     -- RT.station, station hooks, RT.stationComms, shipwright, restock
require("ragtag/core/gm_tools.lua")     -- RT.addCampaignGMFunctions, campaign backup / restore

-- Helpers that extend RT. Loaded last: they only use RT at call time.
require("ragtag/voice.lua")
require("ragtag/stats.lua")
require("ragtag/battle.lua")   -- BATTLE: set-piece battles over combat points (Battle Lab, Corsair arc)
