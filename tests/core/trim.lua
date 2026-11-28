-- TRIM (ee/ragtag/trim.lua): how hard enemy ships fight without adding ships or changing what a scan shows.
-- Each lever on a real ship (from its own values: applying again never compounds; beam damage and range
-- untouched), clamping, the mercy curve, the arena using it (the trim at spawn, mercy easing the enemies as
-- the crew's hull goes, the fight log's trim fields), a real missile's agility, and the arena's Trim menu.
--
-- Not covered: how a trimmed ship flies and fights (orders and numbers only).

T.suite("core")
require("ragtag/ships_used.lua")
require("ragtag/bout.lua")
require("ragtag/match.lua")
require("ragtag/trim.lua")
require("ragtag/arena.lua")
BOUT.LOG_KEY = "ragtag.fightlog.test"
BOUT._log = nil

local A, S, base
local home = {}
local function near(a, b) return math.abs(a - b) < 1e-3 end

T.step("a ship to trim", function()
    A = T.P()
    home.x, home.y = A:getPosition()
    A:setPosition(240000, 240000)
    A:setHeading(0)
    S = CpuShip():setTemplate("Phobos T3"):setFaction("Corsairs"):setPosition(-700000, -700000)
    S:orderIdle()
    base = TRIM.capture(S)
    T.check("capture: turn, accel, speed", base.turn > 0 and base.accel > 0 and base.speed > 0)
    T.check("capture: beams and tubes", next(base.beams) ~= nil and next(base.tubes) ~= nil)
    T.eq("capture: once", TRIM.capture(S), base)
end)

T.step("the levers", function()
    local tr = TRIM.settings()
    tr.overall = 1.2
    TRIM.apply(S, tr)
    T.check("overall: turn x1.2", near(S:getRotationMaxSpeed(), base.turn * 1.2), S:getRotationMaxSpeed())
    T.check("overall: acceleration x1.2", near((S:getAcceleration()), base.accel * 1.2))
    T.check("overall: speed x1.2", near((S:getImpulseMaxSpeed()), base.speed * 1.2))
    local i, bm = next(base.beams)
    T.check("overall: beams fire 1.2x as often", near(S:getBeamWeaponCycleTime(i), bm.cycle / 1.2), S:getBeamWeaponCycleTime(i))
    T.eq("scan-visible: beam damage unchanged", S:getBeamWeaponDamage(i), bm.damage)
    T.eq("scan-visible: beam range unchanged", S:getBeamWeaponRange(i), bm.range)
    T.eq("scan-visible: beam arc unchanged", S:getBeamWeaponArc(i), bm.arc)
    local ti, tl = next(base.tubes)
    T.check("overall: tubes reload 1.2x as fast", near(S:getTubeLoadTime(ti), tl / 1.2))
    TRIM.apply(S, tr)
    T.check("apply again: no compounding", near(S:getRotationMaxSpeed(), base.turn * 1.2))
    tr.overall, tr.lever.turn = 1, 0.8
    TRIM.apply(S, tr)
    T.check("one lever: turn x0.8", near(S:getRotationMaxSpeed(), base.turn * 0.8))
    T.check("one lever: the rest as built", near((S:getAcceleration()), base.accel) and near(S:getBeamWeaponCycleTime(i), bm.cycle))
    TRIM.apply(S, TRIM.settings())
    T.check("as built again", near(S:getRotationMaxSpeed(), base.turn))
    for _ = 1, 30 do TRIM.nudge(tr, "overall", 0.05) end
    T.eq("clamp: no more than the max", tr.overall, TRIM.MAX)
    T.eq("nudge: a lever back to 1 is as built", (function() local t2 = TRIM.settings(); TRIM.nudge(t2, "turn", 0.05); TRIM.nudge(t2, "turn", -0.05); return t2.lever.turn end)(), nil)
end)

T.step("mercy", function()
    local tr = TRIM.settings()
    T.eq("mercy off: no easing", TRIM.mercyFactor(tr, 0.6), 1)
    tr.mercy = 0.3
    T.eq("mercy: none before 10% hull lost", TRIM.mercyFactor(tr, 0.05), 1)
    T.check("mercy: full at 50%", near(TRIM.mercyFactor(tr, 0.5), 0.7))
    T.check("mercy: no further past it", near(TRIM.mercyFactor(tr, 0.9), 0.7))
    local a, b, c = TRIM.mercyFactor(tr, 0.2), TRIM.mercyFactor(tr, 0.3), TRIM.mercyFactor(tr, 0.4)
    T.check("mercy: eases smoothly as the hull goes", 1 > a and a > b and b > c and c > 0.7, string.format("%.3f %.3f %.3f", a, b, c))
    T.eq("mercy: Off, Gentle, Strong", TRIM.mercyLabel(TRIM.settings()) .. "," .. TRIM.mercyLabel({mercy = 0.15}) .. "," .. TRIM.mercyLabel(tr),
        "Off,Gentle,Strong")
    T.eq("text", TRIM.text({overall = 1.1, lever = {turn = 0.9}, mercy = 0.15}), "x1.10, turn 0.90, mercy Gentle")
    S:destroy()
end)

-- ── In the arena: trimmed at spawn, mercy as the crew's hull goes ────────────
local E, ebase
T.step("arena: a trimmed spawn", function()
    ARENA.reset()
    ARENA.state.trim.overall = 1.2
    ARENA.state.trim.mercy = 0.3
    ARENA.add("Phobos T3", 1)
    ARENA.setDistance(4)
    T.eq("spawn", ARENA.spawn(), 1)
    E = ARENA.state.enemies[1].ship
    ebase = TRIM._base[E]
    T.check("spawn: trimmed at once", ebase and near(E:getRotationMaxSpeed(), ebase.turn * 1.2), E:getRotationMaxSpeed())
    T.check("start", ARENA.start())
    A:setHull(A:getHullMax() * 0.6)   -- 40% of the hull gone
end)
T.waitFor("arena: mercy eases the enemy", function()
    ARENA.tick(T.now())
    return (ARENA.state.mercy or 1) < 0.9
end, 5)
T.step("arena: eased, not compounded", function()
    local m = ARENA.state.mercy
    T.check("mercy: about 0.75 at 40% hull lost (strong)", math.abs(m - TRIM.mercyFactor(ARENA.state.trim, 0.4)) < 0.02, m)
    T.check("mercy: the enemy turns slower", near(E:getRotationMaxSpeed(), ebase.turn * 1.2 * m), E:getRotationMaxSpeed())
    T.check("report: the trim and the mercy", ARENA.report():find("mercy now", 1, true) ~= nil, ARENA.report())
    E:destroy()
    ARENA.tick(T.now())
    local rows = BOUT.rows()
    local r = rows[#rows]
    T.check("fight log: the trim", r and r.trim_overall == 1.2 and r.trim_mercy == 0.3, r and tostring(r.trim_overall))
    T.check("fight log: how far the mercy went", r and r.trim_mercy_min and r.trim_mercy_min < 0.9, r and tostring(r.trim_mercy_min))
    BOUT.clearRating(A)
    A:setHull(A:getHullMax())
end)

-- ── A real missile's agility ─────────────────────────────────────────────────
local M
T.step("missile: load", function()
    A:setRotation(180)
    A:setWeaponStorage("Homing", 2)
    A:setTubeLoadTime(0, 1)
    A:commandLoadTube(0, "Homing")
    E = CpuShip():setTemplate("Adder MK5"):setFaction("Corsairs"):setPosition(244000, 240000)
    E:orderIdle()
end)
T.wait(2.5)
T.step("missile: fire", function() A:commandSetTarget(E); A:commandFireTubeAtTarget(0, E) end)
T.waitFor("missile: in flight", function()
    for _, o in ipairs(getObjectsInRadius(240000, 240000, 6000)) do
        local ok, h = pcall(function() return o.components.missile_homing end)
        if ok and h then M = o; return true end
    end
    return false
end, 3)
T.step("missile: agility trimmed once", function()
    local before = M.components.missile_homing.turn_rate
    local tr = TRIM.settings()
    tr.lever.missile = 0.5
    T.check("missile: tuned", TRIM.onMissile(M, tr))
    T.check("missile: half as agile", near(M.components.missile_homing.turn_rate, before * 0.5), M.components.missile_homing.turn_rate)
    T.check("missile: only once", not TRIM.onMissile(M, tr) and near(M.components.missile_homing.turn_rate, before * 0.5))
end)

-- ── The arena's Trim menu ────────────────────────────────────────────────────
T.step("arena: the Trim menu", function()
    ARENA.reset()
    local buttons = {}
    local add, clear, msg = addGMFunction, clearGMFunctions, addGMMessage
    addGMFunction = function(label, fn) buttons[#buttons + 1] = {label = label, fn = fn} end
    clearGMFunctions = function() buttons = {} end
    addGMMessage = function() end
    local function has(l) for _, b in ipairs(buttons) do if b.label == l then return true end end return false end
    local function press(l)
        for _, b in ipairs(buttons) do if b.label == l then b.fn(); return true end end
        local all = {}
        for _, b in ipairs(buttons) do all[#all + 1] = b.label end
        T.check("gm: button '" .. l .. "'", false, table.concat(all, " | "))
        return false
    end
    local ok, err = pcall(function()
        ARENA.showGM()
        T.check("gm: the Trim button", press("Trim... (as built)"))
        press("Overall + (x1.00)")
        T.eq("gm: overall up a step", ARENA.state.trim.overall, 1.05)
        press("Mercy as hull drops: Off")
        T.check("gm: mercy Gentle", has("Mercy as hull drops: Gentle"))
        press("Turn rate: x1.00")
        press("Turn rate - (easier)")
        T.eq("gm: one lever down a step", ARENA.state.trim.lever.turn, 0.95)
        press("← Trim")
        press("Reset all (as built)")
        T.eq("gm: reset", TRIM.text(ARENA.state.trim), "as built")
        press("← Arena")
        T.check("gm: back on the arena screen", has("Trim... (as built)"))
    end)
    addGMFunction, clearGMFunctions, addGMMessage = add, clear, msg
    T.check("gm: no error", ok, tostring(err))
end)

T.step("tidy up", function()
    if RT.valid(E) then E:destroy() end
    ARENA.clear()
    ARENA.reset()
    BOUT.clearLog()
    A:setPosition(home.x, home.y)
end)
