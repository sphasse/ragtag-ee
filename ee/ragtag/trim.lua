-- ee/ragtag/trim.lua
-- TRIM: how hard enemy ships fight, tuned without adding or removing ships and without touching what a crew
-- can see on a scan (hull, shields, beam damage, range and arcs stay as the ship type has them). Each lever
-- is a multiplier on the ship type's own value; above 1 is harder:
--   turn     turn rate              accel    acceleration           speed    top impulse speed
--   boost    combat boost/strafe    fire     beam fire rate (the cycle time is divided by it)
--   reload   tube reload (the load time is divided by it)          missile  missile agility (homing turn
--                                                                            rate, set as each one launches)
-- A lever's factor = overall x that lever x the mercy factor, kept within TRIM.MIN..TRIM.MAX.
--
-- Mercy: as the crew's hull goes, the enemies ease off, so a fight can open harder and still leave room to
-- recover. The factor falls smoothly from 1 at TRIM.MERCY_FROM of the hull lost (the worst-hit crew ship's,
-- since the fight began) to 1 - strength at TRIM.MERCY_FULL; it never rises again within a fight.
--
-- TRIM.capture(ship) records a ship's own values (once); TRIM.apply(ship, settings, mercy) sets them from
-- those, so applying again (a new setting, more mercy) never compounds. Loaded by the scenarios that use it.
-- Test: tests/core/trim.lua.

TRIM = TRIM or {}

TRIM.LEVERS = {
    {id = "turn",    label = "Turn rate"},
    {id = "accel",   label = "Acceleration"},
    {id = "speed",   label = "Top speed"},
    {id = "boost",   label = "Combat boost"},
    {id = "fire",    label = "Beam fire rate"},
    {id = "reload",  label = "Tube reload"},
    {id = "missile", label = "Missile agility"},
}
TRIM.MIN, TRIM.MAX = 0.5, 1.6
TRIM.STEP = 0.05
TRIM.MERCY = {{label = "Off", strength = 0}, {label = "Gentle", strength = 0.15}, {label = "Strong", strength = 0.30}}
TRIM.MERCY_FROM, TRIM.MERCY_FULL = 0.10, 0.50

TRIM._base = TRIM._base or {}   -- ship -> its own values (an entity is the same key however it is reached)

function TRIM.settings()
    return {overall = 1.0, lever = {}, mercy = 0}
end

local function _clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- The factor for one lever.
function TRIM.factor(settings, id, mercy)
    local f = (settings.overall or 1) * (settings.lever[id] or 1) * (mercy or 1)
    return _clamp(f, TRIM.MIN, TRIM.MAX)
end

-- Nudge the overall trim or one lever (id) by `step` (default TRIM.STEP). Returns the new value.
function TRIM.nudge(settings, id, step)
    step = step or TRIM.STEP
    if id == nil or id == "overall" then
        settings.overall = _clamp(math.floor(((settings.overall or 1) + step) * 100 + 0.5) / 100, TRIM.MIN, TRIM.MAX)
        return settings.overall
    end
    local v = _clamp(math.floor(((settings.lever[id] or 1) + step) * 100 + 0.5) / 100, TRIM.MIN, TRIM.MAX)
    if math.abs(v - 1) < 1e-9 then settings.lever[id] = nil else settings.lever[id] = v end   -- 1 is "as built"
    return v
end

function TRIM.mercyLabel(settings)
    for _, m in ipairs(TRIM.MERCY) do if math.abs(m.strength - (settings.mercy or 0)) < 1e-9 then return m.label end end
    return string.format("%.0f%%", (settings.mercy or 0) * 100)
end

function TRIM.cycleMercy(settings)
    local i = 1
    for k, m in ipairs(TRIM.MERCY) do if math.abs(m.strength - (settings.mercy or 0)) < 1e-9 then i = k end end
    settings.mercy = TRIM.MERCY[i % #TRIM.MERCY + 1].strength
    return settings.mercy
end

-- The mercy factor for `loss` (0..1: the share of the hull the worst-hit crew ship has lost in this fight).
function TRIM.mercyFactor(settings, loss)
    local s = settings.mercy or 0
    if s <= 0 then return 1 end
    local x = _clamp(((loss or 0) - TRIM.MERCY_FROM) / (TRIM.MERCY_FULL - TRIM.MERCY_FROM), 0, 1)
    x = x * x * (3 - 2 * x)   -- smooth at both ends
    return 1 - s * x
end

-- "x1.10, turn 0.90, mercy Gentle", or "as built".
function TRIM.text(settings)
    local parts = {}
    if math.abs((settings.overall or 1) - 1) > 1e-9 then parts[#parts + 1] = string.format("x%.2f", settings.overall) end
    for _, l in ipairs(TRIM.LEVERS) do
        local v = settings.lever[l.id]
        if v then parts[#parts + 1] = string.format("%s %.2f", l.id, v) end
    end
    if (settings.mercy or 0) > 0 then parts[#parts + 1] = "mercy " .. TRIM.mercyLabel(settings) end
    return #parts > 0 and table.concat(parts, ", ") or "as built"
end

-- The trim as fight-log fields (only what differs from the ship types).
function TRIM.fields(settings, out)
    out = out or {}
    out.trim_overall = settings.overall or 1
    for _, l in ipairs(TRIM.LEVERS) do
        if settings.lever[l.id] then out["trim_" .. l.id] = settings.lever[l.id] end
    end
    out.trim_mercy = settings.mercy or 0
    return out
end

-- ── On a ship ────────────────────────────────────────────────────────────────
function TRIM.capture(ship)
    if not RT.valid(ship) or TRIM._base[ship] then return TRIM._base[ship] end
    local b = {beams = {}, tubes = {}}
    pcall(function() b.speed, b.rev = ship:getImpulseMaxSpeed() end)
    pcall(function() b.turn = ship:getRotationMaxSpeed() end)
    pcall(function() b.accel, b.accel_rev = ship:getAcceleration() end)
    pcall(function()
        local c = ship.components.combat_maneuvering_thrusters
        if c then b.boost, b.strafe = c.boost_speed, c.strafe_speed end
    end)
    for i = 0, 15 do
        local ok, r = pcall(function() return ship:getBeamWeaponRange(i) end)
        if ok and r and r > 0 then
            b.beams[i] = {arc = ship:getBeamWeaponArc(i), dir = ship:getBeamWeaponDirection(i), range = r,
                          cycle = ship:getBeamWeaponCycleTime(i), damage = ship:getBeamWeaponDamage(i)}
        end
    end
    pcall(function()
        for i = 0, (ship:getWeaponTubeCount() or 0) - 1 do b.tubes[i] = ship:getTubeLoadTime(i) end
    end)
    TRIM._base[ship] = b
    return b
end

-- Set a ship's levers from its own values. `mercy` defaults to 1.
function TRIM.apply(ship, settings, mercy)
    local b = TRIM.capture(ship)
    if not b then return false end
    local function f(id) return TRIM.factor(settings, id, mercy) end
    if b.speed then pcall(function() ship:setImpulseMaxSpeed(b.speed * f("speed"), (b.rev or b.speed) * f("speed")) end) end
    if b.turn then pcall(function() ship:setRotationMaxSpeed(b.turn * f("turn")) end) end
    if b.accel then pcall(function() ship:setAcceleration(b.accel * f("accel"), (b.accel_rev or b.accel) * f("accel")) end) end
    if b.boost then
        pcall(function()
            local c = ship.components.combat_maneuvering_thrusters
            if c then c.boost_speed, c.strafe_speed = b.boost * f("boost"), (b.strafe or 0) * f("boost") end
        end)
    end
    for i, bm in pairs(b.beams) do
        pcall(function() ship:setBeamWeapon(i, bm.arc, bm.dir, bm.range, bm.cycle / f("fire"), bm.damage) end)
    end
    for i, t in pairs(b.tubes) do pcall(function() ship:setTubeLoadTime(i, t / f("reload")) end) end
    return true
end

-- An enemy missile just seen in flight: its homing turn rate by the missile lever (once per missile).
TRIM._missiles = TRIM._missiles or {}
function TRIM.onMissile(missile, settings, mercy)
    if TRIM._missiles[missile] then return false end
    TRIM._missiles[missile] = true
    local ok = pcall(function()
        local h = missile.components.missile_homing
        if h and h.turn_rate then h.turn_rate = h.turn_rate * TRIM.factor(settings, "missile", mercy) end
    end)
    return ok
end
