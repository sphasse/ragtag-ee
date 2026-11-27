-- ee/ragtag/bout.lua
-- BOUT: records fights for balancing. A bout is one fight between the player ships and a group of
-- enemies (the Combat Arena's, and later the Pit's and the patrols'). While it runs, every player ship
-- in it is sampled twice a second; when it ends there is one row per ship, kept in the fight log with
-- the crew's own verdict when they give it (five buttons on Relay: 1 far too easy ... 5 far too hard).
--
-- The fight log is JSON in EmptyEpsilon's script storage (scriptstorage.json: in the EmptyEpsilon
-- folder on Windows, ~/.emptyepsilon/ elsewhere), under its own key, BOUT.LOG_KEY, apart from any
-- campaign save, so it survives restarts and works without stdout. tools/fight_stats.py reads it.
--
-- Crews: every ship is given a crew number (1-10) by the GM; rows carry it, so different groups'
-- data can be told apart. The numbers are remembered by callsign in the log. 0 means not assigned.
--
--   local b = BOUT.start{source = "arena", enemies = {...entities}, info = {slot = "match", predicted_r = 1.3}}
--   BOUT.tick(b, now)                    -- every frame (samples at BOUT.SAMPLE_SECS)
--   BOUT.finish(b, "won" | "lost" | "stopped")   -- writes the rows; offers the crews the rating buttons
-- Loaded by the scenarios that record fights, not by core. Test: tests/core/bout.lua.

BOUT = BOUT or {}
BOUT.LOG_KEY      = "ragtag.fightlog"
BOUT.VERSION      = 2     -- 2: ratings 1-5 (version 1 rows rated 1-3: too easy / good / too hard)
BOUT.SAMPLE_SECS  = 0.5
BOUT.MAX_ROWS     = 2000      -- the oldest go first
BOUT.HOT          = 0.9       -- a system this hot counts as running hot
BOUT.CREW_MAX     = 10
BOUT.SYSTEMS = {"reactor", "beamweapons", "missilesystem", "maneuver", "impulse", "warp", "jumpdrive",
                "frontshield", "rearshield"}
BOUT.MISSILES = {"Homing", "Nuke", "Mine", "EMP", "HVLI"}
BOUT.RATINGS = {{1, "1 Far too easy"}, {2, "2 Easy"}, {3, "3 Good fight"}, {4, "4 Hard"}, {5, "5 Far too hard"}}
BOUT.on_rated = BOUT.on_rated or {}   -- functions(row): a fight was rated (the Pit learns from it)
BOUT.RATING_STATIONS = {"relay", "operations", "single"}

-- This run of the game: rows from one run share it (scenario Lua has no clock or date).
BOUT.session = BOUT.session or string.format("%08x", math.random(0x10000000, 0x7fffffff))
BOUT._seq = BOUT._seq or 0

-- ── The log ──────────────────────────────────────────────────────────────────
-- {version, crews = {callsign = n}, rows = {...}}. Read once, then kept in memory and written back
-- after each change.
function BOUT.log()
    if BOUT._log then return BOUT._log end
    local raw = getScriptStorage():get(BOUT.LOG_KEY)
    local t
    if type(raw) == "string" and raw ~= "" then
        local ok, v = pcall(fromJSON, raw)
        if ok and type(v) == "table" then t = v end
    end
    t = t or {}
    t.version = BOUT.VERSION
    if type(t.crews) ~= "table" then t.crews = {} end
    if type(t.rows) ~= "table" then t.rows = {} end
    BOUT._log = t
    return t
end

function BOUT.save()
    local t = BOUT.log()
    while #t.rows > BOUT.MAX_ROWS do table.remove(t.rows, 1) end
    getScriptStorage():set(BOUT.LOG_KEY, toJSON(t))
end

function BOUT.rows() return BOUT.log().rows end

-- Empty the log (the crew numbers are kept).
function BOUT.clearLog()
    BOUT.log().rows = {}
    BOUT.save()
end

-- ── Crews ────────────────────────────────────────────────────────────────────
function BOUT.crewOf(ship)
    if not RT.valid(ship) then return 0 end
    return tonumber(BOUT.log().crews[ship:getCallSign()]) or 0
end

function BOUT.setCrew(ship, n)
    if not RT.valid(ship) then return 0 end
    n = math.max(0, math.min(BOUT.CREW_MAX, math.floor(tonumber(n) or 0)))
    BOUT.log().crews[ship:getCallSign()] = (n > 0) and n or nil
    BOUT.save()
    return n
end

-- 0 -> 1 -> ... -> 10 -> 0
function BOUT.nextCrew(ship) return BOUT.setCrew(ship, (BOUT.crewOf(ship) + 1) % (BOUT.CREW_MAX + 1)) end

-- ── Sampling ─────────────────────────────────────────────────────────────────
local function _shieldLevels(e)
    local out = {}
    pcall(function()
        for i = 0, (e:getShieldCount() or 0) - 1 do out[#out + 1] = {e:getShieldLevel(i), e:getShieldMax(i)} end
    end)
    return out
end

local function _missiles(p)
    local out = {}
    for _, w in ipairs(BOUT.MISSILES) do
        local ok, n = pcall(function() return p:getWeaponStorage(w) end)
        out[w] = ok and n or 0
    end
    return out
end

local function _newTracker(p)
    local t = {
        ship = p, name = p:getCallSign(), crew = BOUT.crewOf(p),
        hull0 = p:getHull(), hull_max = p:getHullMax(), last_hull = p:getHull(),
        last_shields = _shieldLevels(p), last_sys = {}, missiles0 = _missiles(p),
        hull_lost = 0, shield_damage = 0, system_damage = 0,
        min_hull_pct = 100, min_shield_pct = 100, shield_down_secs = 0,
        heat_max = 0, hot_secs = 0, energy_min = p:getEnergy(), energy_max = p:getMaxEnergy(),
        destroyed = false, strength = RT.shipStrength(p).total,
    }
    for _, sys in ipairs(BOUT.SYSTEMS) do
        local ok, has = pcall(function() return p:hasSystem(sys) end)
        if ok and has then t.last_sys[sys] = p:getSystemHealth(sys) end
    end
    if t.hull_max > 0 then t.min_hull_pct = t.hull0 / t.hull_max * 100 end
    return t
end

-- One look at a player ship: adds any drop since the last look to the totals (so damage repaired
-- in the middle of the fight still counts), and keeps the lows and highs.
local function _sampleShip(t, dt, b)
    local p = t.ship
    if not RT.valid(p) then t.destroyed = true; return end
    local h = p:getHull()
    if h < t.last_hull then t.hull_lost = t.hull_lost + (t.last_hull - h); b.contact = true end
    t.last_hull = h
    if t.hull_max > 0 then t.min_hull_pct = math.min(t.min_hull_pct, h / t.hull_max * 100) end
    local now_sh, down = _shieldLevels(p), false
    for i, s in ipairs(now_sh) do
        local before = t.last_shields[i]
        if before and s[1] < before[1] then t.shield_damage = t.shield_damage + (before[1] - s[1]); b.contact = true end
        if s[2] > 0 then t.min_shield_pct = math.min(t.min_shield_pct, s[1] / s[2] * 100) end
        if s[1] < 1 then down = true end
    end
    t.last_shields = now_sh
    if down then t.shield_down_secs = t.shield_down_secs + dt end
    local hot = false
    for sys, before in pairs(t.last_sys) do
        local hl = p:getSystemHealth(sys)
        if hl < before then t.system_damage = t.system_damage + (before - hl) end
        t.last_sys[sys] = hl
        local heat = p:getSystemHeat(sys) or 0
        t.heat_max = math.max(t.heat_max, heat)
        if heat >= BOUT.HOT then hot = true end
    end
    if hot then t.hot_secs = t.hot_secs + dt end
    t.energy_min = math.min(t.energy_min, p:getEnergy())
end

-- The enemies: the damage the crews dealt (every drop in hull and shields).
local function _sampleEnemies(b)
    for _, e in ipairs(b.enemies) do
        if RT.valid(e.ship) then
            local h = e.ship:getHull()
            if h < e.last_hull then b.dealt = b.dealt + (e.last_hull - h); b.contact = true end
            e.last_hull = h
            local sh = _shieldLevels(e.ship)
            for i, s in ipairs(sh) do
                local before = e.last_shields[i]
                if before and s[1] < before[1] then b.dealt = b.dealt + (before[1] - s[1]); b.contact = true end
            end
            e.last_shields = sh
        elseif not e.gone then
            e.gone = true
            b.kills = b.kills + 1
        end
    end
end

-- ── A bout ───────────────────────────────────────────────────────────────────
-- opts: source ("arena", "pit", ...), enemies (entities), ships (default: every live player ship),
-- info (anything else for the rows: slot, predicted_r, rating_r, ...). Returns the bout.
function BOUT.start(opts)
    opts = opts or {}
    local now = getScenarioTime()
    local b = {source = opts.source or "arena", info = opts.info or {}, started_at = now, last_sample = now,
               trackers = {}, enemies = {}, dealt = 0, kills = 0, contact = false, contact_at = nil}
    for _, p in ipairs(opts.ships or RT.players) do
        if RT.valid(p) then b.trackers[#b.trackers + 1] = _newTracker(p) end
    end
    local types, e_str = {}, 0
    for _, s in ipairs(opts.enemies or {}) do
        if RT.valid(s) then
            b.enemies[#b.enemies + 1] = {ship = s, last_hull = s:getHull(), last_shields = _shieldLevels(s)}
            local ok, tn = pcall(function() return s:getTypeName() end)
            types[#types + 1] = ok and tn or "?"
            e_str = e_str + RT.shipStrength(s).total
        end
    end
    table.sort(types)
    b.enemy_types, b.enemy_strength = table.concat(types, "+"), e_str
    BOUT.current = b
    return b
end

-- Every frame while the fight runs.
function BOUT.tick(b, now)
    if not b or b.done then return end
    now = now or getScenarioTime()
    local dt = now - b.last_sample
    if dt < BOUT.SAMPLE_SECS then return end
    b.last_sample = now
    local had_contact = b.contact
    for _, t in ipairs(b.trackers) do _sampleShip(t, dt, b) end
    _sampleEnemies(b)
    if b.contact and not had_contact then b.contact_at = now end
end

local function _r1(x) return math.floor((x or 0) * 10 + 0.5) / 10 end

-- The fight is over: one row per player ship, saved. outcome: "won", "lost" or "stopped" (the GM ended
-- it). Offers each crew the rating buttons. Returns the rows.
function BOUT.finish(b, outcome)
    if not b or b.done then return {} end
    local now = getScenarioTime()
    b.last_sample = now - BOUT.SAMPLE_SECS
    BOUT.tick(b, now)   -- a last look
    b.done = true
    if BOUT.current == b then BOUT.current = nil end
    local rows = {}
    for _, t in ipairs(b.trackers) do
        BOUT._seq = BOUT._seq + 1
        local fired = 0
        if RT.valid(t.ship) then
            local m = _missiles(t.ship)
            for w, n0 in pairs(t.missiles0) do fired = fired + math.max(0, n0 - (m[w] or 0)) end
        end
        local row = {
            v = BOUT.VERSION, session = BOUT.session, seq = BOUT._seq, source = b.source,
            crew = t.crew, ship = t.name, outcome = outcome or "stopped",
            destroyed = t.destroyed or not RT.valid(t.ship),
            secs = _r1(now - b.started_at), contact_secs = _r1(b.contact_at and (now - b.contact_at) or 0),
            hull_lost = _r1(t.hull_lost), hull_lost_pct = _r1(t.hull_max > 0 and t.hull_lost / t.hull_max * 100 or 0),
            shield_damage = _r1(t.shield_damage), system_damage = _r1(t.system_damage),
            min_hull_pct = _r1(t.min_hull_pct), min_shield_pct = _r1(t.min_shield_pct),
            shield_down_secs = _r1(t.shield_down_secs), heat_max = _r1(t.heat_max * 100), hot_secs = _r1(t.hot_secs),
            energy_min_pct = _r1(t.energy_max > 0 and t.energy_min / t.energy_max * 100 or 0),
            missiles_fired = fired, damage_dealt = _r1(b.dealt), kills = b.kills, enemies = #b.enemies,
            enemy_types = b.enemy_types, enemy_strength = b.enemy_strength, ship_strength = t.strength,
            ships = #b.trackers, rating = nil,
        }
        for k, v in pairs(b.info) do if row[k] == nil then row[k] = v end end
        rows[#rows + 1] = row
        BOUT.log().rows[#BOUT.log().rows + 1] = row
        if RT.valid(t.ship) then BOUT.offerRating(t.ship, row) end
    end
    BOUT.save()
    log(string.format("[BOUT] %s %s: %d row(s) saved to %s", b.source, outcome or "stopped", #rows, BOUT.LOG_KEY))
    return rows
end

-- ── The crew's verdict ───────────────────────────────────────────────────────
-- Five buttons on Relay (and Operations / single pilot), 1 (far too easy) to 5 (far too hard): pressing one
-- records it in the row and takes the buttons away. A newer bout replaces them. The GM can rate too
-- (BOUT.rate). Every BOUT.on_rated function is told.
local function _ratingKey(station, n) return "bout_rate_" .. station .. "_" .. n end

function BOUT.clearRating(p)
    if not RT.valid(p) then return end
    for _, st in ipairs(BOUT.RATING_STATIONS) do
        for _, r in ipairs(BOUT.RATINGS) do pcall(function() p:removeCustom(_ratingKey(st, r[1])) end) end
    end
end

function BOUT.rate(row, n, by)
    if not row then return false end
    row.rating = n
    row.rated_by = by or "crew"
    BOUT.save()
    for _, fn in ipairs(BOUT.on_rated) do
        local ok, err = pcall(fn, row)
        if not ok then log("[BOUT] on_rated: " .. tostring(err)) end
    end
    return true
end

function BOUT.offerRating(p, row)
    BOUT.clearRating(p)
    for _, st in ipairs(BOUT.RATING_STATIONS) do
        for i, r in ipairs(BOUT.RATINGS) do
            local n, label = r[1], r[2]
            pcall(function()
                p:addCustomButton(st, _ratingKey(st, n), "Fight " .. label, function()
                    BOUT.rate(row, n, "crew")
                    BOUT.clearRating(p)
                    if RT.valid(p) then p:addToShipLog("Fight rated: " .. label .. ". Thanks.", "#C0C0C0") end
                end, 200 + i)
            end)
        end
    end
end

-- The latest row for a ship this run (for the GM's own rating), or nil.
function BOUT.lastRowFor(ship)
    if not RT.valid(ship) then return nil end
    local cs, rows = ship:getCallSign(), BOUT.rows()
    for i = #rows, 1, -1 do
        if rows[i].ship == cs and rows[i].session == BOUT.session then return rows[i] end
    end
    return nil
end

-- One line for the GM: "Raven (crew 3): won in 1:42, hull -12%, shields -180, systems -0.6, rated Good fight".
function BOUT.rowText(r)
    local rated = "not rated"
    for _, x in ipairs(BOUT.RATINGS) do if x[1] == r.rating then rated = "rated " .. x[2] end end
    return string.format("%s (crew %s): %s in %d:%02d, hull -%.0f%%, shields -%.0f, systems -%.1f, %s",
        tostring(r.ship), (r.crew and r.crew > 0) and tostring(r.crew) or "unassigned", tostring(r.outcome),
        math.floor(r.secs // 60), math.floor(r.secs % 60), r.hull_lost_pct or 0, r.shield_damage or 0,
        r.system_damage or 0, rated)
end
