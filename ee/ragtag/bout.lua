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
BOUT.on_missile = BOUT.on_missile or {}   -- functions(missile, m): a missile first seen in a fight (m.by.kind: "crew"/"enemy")
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

-- ── Mobility ─────────────────────────────────────────────────────────────────
-- What lets a ship dodge and bring its guns to bear. Fixed numbers (BOUT.mobility), and in the fight,
-- sampled with everything else: whether the crew is inside an enemy's beam envelope (arc and range:
-- it could be fired on) and whether an enemy is inside the crew's, the distance to the nearest enemy,
-- seconds of combat boost or strafe, and every missile seen in flight: who fired it, at whom, and whether
-- it hit (approximate: it vanished within BOUT.MISSILE_HIT_U of its target in a sample where the target
-- took damage; anything else is a miss, dodged, shot down or run out of fuel).
BOUT.MISSILE_HIT_U  = 1.2
BOUT.MISSILE_LOOK_U = 12    -- missiles are looked for this far from each crew ship

local function _beamList(e)
    local out = {}
    for i = 0, 15 do
        local ok, r = pcall(function() return e:getBeamWeaponRange(i) end)
        if ok and r and r > 0 then
            out[#out + 1] = {dir = e:getBeamWeaponDirection(i) or 0, arc = e:getBeamWeaponArc(i) or 0, range = r}
        end
    end
    return out
end

local function _angDiff(a, b) return math.abs((a - b + 180) % 360 - 180) end

-- {speed, turn, accel, boost, strafe, arc_pct, reach}: impulse speed, turn rate (degrees a second),
-- acceleration, combat boost and strafe speeds, the share of the circle round the ship its beams can fire
-- into (5-degree steps, overlaps counted once), and the longest beam's range (world units).
function BOUT.mobility(e)
    local m = {speed = 0, turn = 0, accel = 0, boost = 0, strafe = 0, arc_pct = 0, reach = 0}
    pcall(function() m.speed = (e:getImpulseMaxSpeed()) or 0 end)
    pcall(function() m.turn = e:getRotationMaxSpeed() or 0 end)
    pcall(function() m.accel = (e:getAcceleration()) or 0 end)
    pcall(function()
        local c = e.components.combat_maneuvering_thrusters
        if c then m.boost, m.strafe = c.boost_speed or 0, c.strafe_speed or 0 end
    end)
    local beams, covered = _beamList(e), 0
    for _, bm in ipairs(beams) do m.reach = math.max(m.reach, bm.range) end
    for a = 0, 355, 5 do
        for _, bm in ipairs(beams) do
            if _angDiff(a, bm.dir) <= bm.arc / 2 then covered = covered + 1; break end
        end
    end
    m.arc_pct = covered / 72 * 100
    return m
end

-- Could `from` fire a beam at `to` right now (inside one beam's arc and range)?
function BOUT.canHit(from, beams, to)
    local fx, fy = from:getPosition()
    local tx, ty = to:getPosition()
    local d = math.sqrt((tx - fx) ^ 2 + (ty - fy) ^ 2)
    local bearing = math.deg(math.atan(ty - fy, tx - fx))
    local rot = from:getRotation()
    for _, bm in ipairs(beams) do
        if d <= bm.range and _angDiff(bearing, rot + bm.dir) <= bm.arc / 2 then return true end
    end
    return false
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
        kind = "crew", beams = _beamList(p), mob = BOUT.mobility(p),
        fight_secs = 0, exposed_secs = 0, firing_secs = 0, range_sum = 0, range_n = 0, in_their_reach_secs = 0,
        boost_secs = 0, missiles_at = 0, missiles_hit = 0, missiles_out = 0, missiles_landed = 0,
        dps_model = MATCH and MATCH.power and MATCH.power(p).dps or nil,
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
    t.damaged_now = false
    if not RT.valid(p) then t.destroyed = true; return end
    local h = p:getHull()
    if h < t.last_hull then t.hull_lost = t.hull_lost + (t.last_hull - h); b.contact = true; t.damaged_now = true end
    t.last_hull = h
    if t.hull_max > 0 then t.min_hull_pct = math.min(t.min_hull_pct, h / t.hull_max * 100) end
    local now_sh, down = _shieldLevels(p), false
    for i, s in ipairs(now_sh) do
        local before = t.last_shields[i]
        if before and s[1] < before[1] then
            t.shield_damage = t.shield_damage + (before[1] - s[1]); b.contact = true; t.damaged_now = true
        end
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
        e.damaged_now = false
        if RT.valid(e.ship) then
            local h = e.ship:getHull()
            if h < e.last_hull then b.dealt = b.dealt + (e.last_hull - h); b.contact = true; e.damaged_now = true end
            e.last_hull = h
            local sh = _shieldLevels(e.ship)
            for i, s in ipairs(sh) do
                local before = e.last_shields[i]
                if before and s[1] < before[1] then
                    b.dealt = b.dealt + (before[1] - s[1]); b.contact = true; e.damaged_now = true
                end
            end
            e.last_shields = sh
        elseif not e.gone then
            e.gone = true
            b.kills = b.kills + 1
        end
    end
end

-- Who can fire on whom, how close, and the combat thrusters (from the first damage on).
local function _sampleGeometry(b, dt)
    if not b.contact then return end
    for _, t in ipairs(b.trackers) do
        local p = t.ship
        if RT.valid(p) then
            t.fight_secs = t.fight_secs + dt
            local exposed, firing, nearest, their_reach = false, false, math.huge, 0
            for _, e in ipairs(b.enemies) do
                if RT.valid(e.ship) then
                    local d = RT.dist(p, e.ship)
                    if d < nearest then nearest, their_reach = d, e.mob.reach end
                    if not exposed and BOUT.canHit(e.ship, e.beams, p) then exposed = true end
                    if not firing and BOUT.canHit(p, t.beams, e.ship) then firing = true end
                end
            end
            if exposed then t.exposed_secs = t.exposed_secs + dt end
            if firing then t.firing_secs = t.firing_secs + dt end
            if nearest < math.huge then
                t.range_sum, t.range_n = t.range_sum + nearest, t.range_n + 1
                if nearest <= their_reach then t.in_their_reach_secs = t.in_their_reach_secs + dt end
            end
            pcall(function()
                local c = p.components.combat_maneuvering_thrusters
                if c and ((c.boost_request or 0) ~= 0 or (c.strafe_request or 0) ~= 0) then t.boost_secs = t.boost_secs + dt end
            end)
        end
    end
end

local function _nearestOf(list, x, y)
    local best, bd = nil, math.huge
    for _, r in ipairs(list) do
        if RT.valid(r.ship) then
            local rx, ry = r.ship:getPosition()
            local d = (rx - x) ^ 2 + (ry - y) ^ 2
            if d < bd then best, bd = r, d end
        end
    end
    return best
end

-- Missiles: new ones are counted against the side they were fired at; one that is gone since the last look
-- is judged a hit or a miss (see BOUT.MISSILE_HIT_U).
local function _sampleMissiles(b)
    b.missiles = b.missiles or {}
    local side = {}
    for _, t in ipairs(b.trackers) do if RT.valid(t.ship) then side[t.ship] = t end end
    for _, e in ipairs(b.enemies) do if RT.valid(e.ship) then side[e.ship] = e end end
    local seen = {}
    for _, t in ipairs(b.trackers) do
        if RT.valid(t.ship) then
            local x, y = t.ship:getPosition()
            for _, o in ipairs(getObjectsInRadius(x, y, BOUT.MISSILE_LOOK_U * 1000)) do
                local ok, flying = pcall(function() return o.components.missile_flight ~= nil end)
                if ok and flying and not seen[o] then
                    seen[o] = true
                    local ox, oy = o:getPosition()
                    local m = b.missiles[o]
                    if not m then
                        local owner, target
                        pcall(function() owner = o.components.explode_on_touch.owner end)
                        pcall(function() target = o.components.missile_homing.target end)
                        local by = owner and side[owner]
                        if by then
                            local victims = (by.kind == "crew") and b.enemies or b.trackers
                            local at = (target and side[target] and side[target].kind ~= by.kind) and side[target]
                                or _nearestOf(victims, ox, oy)
                            if at then
                                m = {by = by, at = at}
                                b.missiles[o] = m
                                for _, fn in ipairs(BOUT.on_missile) do
                                    local okh, err = pcall(fn, o, m, b)
                                    if not okh then log("[BOUT] on_missile: " .. tostring(err)) end
                                end
                                if by.kind == "crew" then by.missiles_out = by.missiles_out + 1
                                else at.missiles_at = at.missiles_at + 1 end
                            end
                        end
                    end
                    if m then m.x, m.y = ox, oy end
                end
            end
        end
    end
    for o, m in pairs(b.missiles) do
        if not seen[o] then
            b.missiles[o] = nil
            local hit = false
            if RT.valid(m.at.ship) and m.at.damaged_now and m.x then
                local tx, ty = m.at.ship:getPosition()
                hit = (tx - m.x) ^ 2 + (ty - m.y) ^ 2 <= (BOUT.MISSILE_HIT_U * 1000) ^ 2
            end
            if hit then
                if m.by.kind == "crew" then m.by.missiles_landed = m.by.missiles_landed + 1
                else m.at.missiles_hit = m.at.missiles_hit + 1 end
            end
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
            b.enemies[#b.enemies + 1] = {ship = s, last_hull = s:getHull(), last_shields = _shieldLevels(s),
                kind = "enemy", beams = _beamList(s), mob = BOUT.mobility(s),
                dps_model = MATCH and MATCH.power and MATCH.power(s).dps or nil}
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
    _sampleGeometry(b, dt)
    _sampleMissiles(b)
end

local function _r1(x) return math.floor((x or 0) * 10 + 0.5) / 10 end
local function _r2(x) return math.floor((x or 0) * 100 + 0.5) / 100 end

-- The mobility part of a row (see "Mobility"): the crew ship's fixed numbers (my_*), the enemies' (en_*:
-- averages, en_speed_max and en_reach the largest), their ratios, and what the fight showed.
function BOUT.mobilityFields(row, t, b)
    local m = t.mob
    row.my_speed, row.my_turn, row.my_accel = _r1(m.speed), _r1(m.turn), _r1(m.accel)
    row.my_boost, row.my_strafe, row.my_arc_pct, row.my_reach = _r1(m.boost), _r1(m.strafe), _r1(m.arc_pct), math.floor(m.reach)
    local n, sum = 0, {speed = 0, turn = 0, accel = 0, boost = 0, strafe = 0, arc_pct = 0}
    local speed_max, reach_max, dps_model = 0, 0, 0
    for _, e in ipairs(b.enemies) do
        n = n + 1
        for k in pairs(sum) do sum[k] = sum[k] + (e.mob[k] or 0) end
        speed_max, reach_max = math.max(speed_max, e.mob.speed), math.max(reach_max, e.mob.reach)
        dps_model = dps_model + (e.dps_model or 0)
    end
    if n > 0 then
        row.en_speed, row.en_turn, row.en_accel = _r1(sum.speed / n), _r1(sum.turn / n), _r1(sum.accel / n)
        row.en_boost, row.en_strafe, row.en_arc_pct = _r1(sum.boost / n), _r1(sum.strafe / n), _r1(sum.arc_pct / n)
        row.en_speed_max, row.en_reach = _r1(speed_max), math.floor(reach_max)
        if row.en_speed > 0 then row.speed_ratio = _r2(m.speed / (sum.speed / n)) end
        if row.en_turn > 0 then row.turn_ratio = _r2(m.turn / (sum.turn / n)) end
        if reach_max > 0 then row.reach_ratio = _r2(m.reach / reach_max) end
    end
    local fs = t.fight_secs
    row.fight_sample_secs = _r1(fs)
    if fs > 0 then
        row.exposed_pct = _r1(t.exposed_secs / fs * 100)       -- inside an enemy's beam arc and range
        row.firing_pct = _r1(t.firing_secs / fs * 100)         -- an enemy inside ours
        row.aim_edge = _r1(row.firing_pct - row.exposed_pct)    -- above 0: on them more than they were on us
        row.in_their_reach_pct = _r1(t.in_their_reach_secs / fs * 100)
    end
    if t.range_n > 0 then row.avg_range_u = _r2(t.range_sum / t.range_n / 1000) end
    row.boost_secs = _r1(t.boost_secs)
    row.missiles_at_me, row.missiles_hit_me = t.missiles_at, t.missiles_hit
    if t.missiles_at > 0 then row.dodge_pct = _r1((1 - t.missiles_hit / t.missiles_at) * 100) end
    row.missiles_out, row.missiles_landed = t.missiles_out, t.missiles_landed
    if t.missiles_out > 0 then row.missile_hit_pct = _r1(t.missiles_landed / t.missiles_out * 100) end
    -- Damage that landed for the time each side could fire, against what the model expects.
    if t.exposed_secs > 0 then row.realized_enemy_dps = _r2((t.hull_lost + t.shield_damage) / t.exposed_secs) end
    if t.firing_secs > 0 then row.realized_my_dps = _r2(b.dealt / t.firing_secs) end
    if dps_model > 0 then row.enemy_dps_model = _r2(dps_model) end
    if t.dps_model then row.my_dps_model = _r2(t.dps_model) end
end

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
        BOUT.mobilityFields(row, t, b)
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
    local mob = ""
    if r.exposed_pct then
        mob = string.format(", in their arcs %.0f%% / ours on them %.0f%%", r.exposed_pct, r.firing_pct or 0)
    end
    if (r.missiles_at_me or 0) > 0 then
        mob = mob .. string.format(", missiles dodged %d/%d", r.missiles_at_me - (r.missiles_hit_me or 0), r.missiles_at_me)
    end
    return string.format("%s (crew %s): %s in %d:%02d, hull -%.0f%%, shields -%.0f, systems -%.1f%s, %s",
        tostring(r.ship), (r.crew and r.crew > 0) and tostring(r.crew) or "unassigned", tostring(r.outcome),
        math.floor(r.secs // 60), math.floor(r.secs % 60), r.hull_lost_pct or 0, r.shield_damage or 0,
        r.system_damage or 0, mob, rated)
end
