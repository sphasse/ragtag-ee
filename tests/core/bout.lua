-- BOUT (ee/ragtag/bout.lua), the fight log, and MATCH (ee/ragtag/match.lua), the time-to-kill model and
-- its three opponents. BOUT: crew numbers kept by callsign, cumulative damage counting (damage repaired
-- in the middle of a fight still counts), one row per ship saved as JSON in script storage, the
-- crews' rating buttons. MATCH: a ship's effective hit points and damage a second, R, every group of
-- up to four, and an easy / good / hard offer in that order. The arena drives both (tests/core/arena.lua).
--
-- Not covered: a real fight (damage is applied by script, and samples are taken with made-up times).

T.suite("core")
require("ragtag/bout.lua")
require("ragtag/match.lua")

BOUT.LOG_KEY = "ragtag.fightlog.test"   -- never the real log
BOUT._log = nil

local A, E, b, row
local home = {}

T.step("in open space, with an empty test log", function()
    A = T.P()
    home.x, home.y = A:getPosition()
    A:setPosition(210000, 200000)
    BOUT.clearLog()
    T.eq("log: empty", #BOUT.rows(), 0)
end)

T.step("MATCH: one ship's numbers", function()
    local pw = MATCH.power(A)
    local shields = 0
    for i = 0, A:getShieldCount() - 1 do shields = shields + A:getShieldMax(i) end
    T.eq("power: EHP = hull + 1.2 x shields", math.floor(pw.ehp + 0.5), math.floor(A:getHullMax() + 1.2 * shields + 0.5))
    T.check("power: damage a second", pw.dps > 0, pw.dps)
    local adder = MATCH.typePower("Adder MK5")
    T.check("type: Adder MK5 measured", adder.ehp > 0 and adder.dps > 0, string.format("%.0f / %.1f", adder.ehp, adder.dps))
    T.eq("type: cached", MATCH.typePower("Adder MK5"), adder)
    local crew = MATCH.crewPower({A})
    local r1 = MATCH.ratio(crew, {"Adder MK5"})
    local r2 = MATCH.ratio(crew, {"Adder MK5", "Adder MK5"})
    T.check("ratio: two Adders are harder than one", r2 < r1, string.format("%.2f vs %.2f", r2, r1))
    T.check("ratio: a better crew (r 1.5) finds it easier", MATCH.ratio(crew, {"Adder MK5"}, 1.5) > r1)
    MATCH.TYPE_FACTOR["Adder MK5"] = 2
    T.check("ratio: a type that fights above its numbers is harder", MATCH.ratio(crew, {"Adder MK5"}) < r1)
    MATCH.TYPE_FACTOR["Adder MK5"] = nil
    T.eq("groups: 1-4 ships from two types", #MATCH.groups({"A", "B"}), 2 + 3 + 4 + 5)
    -- Range: an enemy the crew out-reaches lands fewer of its beam shots (less so when much faster).
    T.check("power: reach and speed", pw.reach > 0 and pw.speed > 0, string.format("%.0f / %.0f", pw.reach, pw.speed))
    local e = {beam_dps = 4, reach = 800, speed = 80}
    T.eq("kite: out-reached", MATCH.kiteFactor({reach = 1400, speed = 75}, e), MATCH.KITE)
    T.eq("kite: not by enough", MATCH.kiteFactor({reach = 900, speed = 75}, e), 1)
    T.eq("kite: a much faster enemy closes", MATCH.kiteFactor({reach = 1400, speed = 50}, e), MATCH.KITE_FAST)
    T.eq("kite: no beams, nothing to dodge", MATCH.kiteFactor({reach = 1400, speed = 75}, {beam_dps = 0, reach = 0, speed = 80}), 1)
    local short = MATCH.ratio({ehp = crew.ehp, dps = crew.dps, reach = 0, speed = crew.speed}, {"Adder MK5"})
    local long = MATCH.ratio({ehp = crew.ehp, dps = crew.dps, reach = 5000, speed = crew.speed}, {"Adder MK5"})
    T.check("ratio: out-reaching them favours the crew", long > short, string.format("%.2f vs %.2f", long, short))
    T.eq("group text", MATCH.groupText({"Phobos T3", "Adder MK5", "Adder MK5"}), "2 x Adder MK5, Phobos T3")
end)

T.step("MATCH: three opponents", function()
    local types = {"Adder MK5", "MT52 Hornet", "Phobos T3", "Piranha F12", "Atlantis X23"}
    local o = MATCH.offer(types, {A}, 1)
    T.eq("offer: three", o and #o, 3)
    if not o or #o < 3 then return end
    T.eq("offer: easy, match, hard", o[1].slot .. "," .. o[2].slot .. "," .. o[3].slot, "easy,match,hard")
    T.check("offer: easy is the easiest, hard the hardest", o[1].r_value > o[2].r_value and o[2].r_value > o[3].r_value,
        string.format("%.2f %.2f %.2f", o[1].r_value, o[2].r_value, o[3].r_value))
    T.check("offer: three different groups", MATCH.groupText(o[1].group) ~= MATCH.groupText(o[2].group)
        and MATCH.groupText(o[2].group) ~= MATCH.groupText(o[3].group))
    for _, x in ipairs(o) do
        T.check("offer: " .. x.slot .. " near its target", math.abs(math.log(x.r_value / x.target)) < 0.5,
            string.format("R %.2f, target %.1f", x.r_value, x.target))
    end
end)

T.step("BOUT: crew numbers", function()
    T.eq("crew: unassigned", BOUT.crewOf(A), 0)
    T.eq("crew: set", BOUT.setCrew(A, 3), 3)
    T.eq("crew: next", BOUT.nextCrew(A), 4)
    T.eq("crew: no more than 10", BOUT.setCrew(A, 11), 10)
    T.eq("crew: 10 wraps to unassigned", BOUT.nextCrew(A), 0)
    BOUT.setCrew(A, 3)
    BOUT._log = nil   -- read it back from script storage
    T.eq("crew: remembered by callsign", BOUT.crewOf(A), 3)
end)

T.step("BOUT: a fight, sampled", function()
    E = CpuShip():setTemplate("Adder MK5"):setFaction("Corsairs"):setPosition(215000, 200000)
    E:orderIdle()
    A:setHull(A:getHullMax())
    b = BOUT.start{source = "test", enemies = {E}, info = {slot = "match", predicted_r = 1.3}}
    local t = b.last_sample
    A:setHull(A:getHull() - 20)
    A:setShields(A:getShieldLevel(0) - 30, A:getShieldLevel(1))
    A:setSystemHealth("impulse", 0.5)
    BOUT.tick(b, t + 1)
    A:setSystemHealth("impulse", 1.0)      -- repaired
    BOUT.tick(b, t + 2)
    A:setSystemHealth("impulse", 0.7)      -- hit again
    E:setHull(E:getHull() - 10)
    BOUT.tick(b, t + 3)
    T.check("tick: too soon is skipped", (function() local n = b.last_sample; BOUT.tick(b, n + 0.1); return b.last_sample == n end)())
    local rows = BOUT.finish(b, "won")
    T.eq("finish: one row", #rows, 1)
    row = rows[1]
    T.eq("row: hull lost", row.hull_lost, 20)
    T.eq("row: shield damage", row.shield_damage, 30)
    T.eq("row: system damage, repaired damage counted", row.system_damage, 0.8)
    T.eq("row: damage dealt", row.damage_dealt, 10)
    T.eq("row: crew", row.crew, 3)
    T.eq("row: outcome", row.outcome, "won")
    T.eq("row: slot from the info", row.slot, "match")
    T.eq("row: predicted R from the info", row.predicted_r, 1.3)
    T.eq("row: the enemy", row.enemy_types, "Adder MK5")
    T.eq("row: this run", row.session, BOUT.session)
    T.check("row: lowest hull %", row.min_hull_pct < 100, row.min_hull_pct)
    T.check("row: not rated yet", row.rating == nil)
    T.check("finish: only once", #BOUT.finish(b, "won") == 0)
end)

T.step("BOUT: saved as JSON in script storage", function()
    local raw = getScriptStorage():get(BOUT.LOG_KEY)
    T.check("storage: a JSON string", type(raw) == "string" and raw:find('"rows"', 1, true) ~= nil)
    BOUT._log = nil
    T.eq("storage: the row is there after a reload", #BOUT.rows(), 1)
    T.eq("storage: with its numbers", BOUT.rows()[1].hull_lost, 20)
    row = BOUT.rows()[1]
end)

local function customs(p, prefix)
    local out = {}
    local f = p.components.custom_ship_functions
    for i = 1, #f do
        if tostring(f[i].name):sub(1, #prefix) == prefix then out[#out + 1] = f[i] end
    end
    return out
end

T.step("BOUT: the crews' rating buttons", function()
    local buttons = customs(A, "bout_rate_relay_")
    T.eq("rate: five on Relay", #buttons, 5)
    local captions = {}
    for _, f in ipairs(buttons) do captions[#captions + 1] = tostring(f.caption) end
    table.sort(captions)
    T.eq("rate: the choices, 1-5", table.concat(captions, " | "),
        "Fight 1 Far too easy | Fight 2 Easy | Fight 3 Good fight | Fight 4 Hard | Fight 5 Far too hard")
    -- The crew's answer (what the button does), and the GM's.
    local last = BOUT.lastRowFor(A)
    T.check("rate: the latest row for the ship", last ~= nil and last.seq == row.seq)
    local told
    BOUT.on_rated[#BOUT.on_rated + 1] = function(r) told = r end
    T.check("rate: recorded", BOUT.rate(last, 3, "crew") and last.rating == 3 and last.rated_by == "crew")
    table.remove(BOUT.on_rated)
    T.eq("rate: the on_rated hooks are told", told, last)
    BOUT.clearRating(A)
    T.eq("rate: the buttons go", #customs(A, "bout_rate_"), 0)
    BOUT._log = nil
    T.eq("rate: saved", BOUT.rows()[1].rating, 3)
    T.eq("row: the 1-5 scale's version", BOUT.rows()[1].v, 2)
    T.check("row text", BOUT.rowText(BOUT.rows()[1]):find("rated 3 Good fight", 1, true) ~= nil, BOUT.rowText(BOUT.rows()[1]))
end)

-- ── Mobility: fixed numbers, arcs, range, missiles ───────────────────────────
local E2, b2, b3
T.step("BOUT: mobility numbers", function()
    local m = BOUT.mobility(A)
    T.check("mobility: speed, turn and acceleration", m.speed > 0 and m.turn > 0 and m.accel > 0,
        string.format("%.0f / %.0f / %.0f", m.speed, m.turn, m.accel))
    T.check("mobility: beam coverage is a share of the circle", m.arc_pct > 0 and m.arc_pct < 100, m.arc_pct)
    T.check("mobility: reach and combat thrusters", m.reach > 0 and m.boost > 0, m.reach .. " / " .. m.boost)
    local e = BOUT.mobility(CpuShip():setTemplate("MT52 Hornet"):setPosition(-800000, -800000))
    T.check("mobility: an AI ship has numbers too", e.speed > 0 and e.turn > 0, e.speed .. " / " .. e.turn)
end)
T.step("BOUT: who can fire on whom", function()
    -- The crew ship faces west, so its aft beams (the Light Freighter's are at 170 and 190 degrees) point east,
    -- at an Adder 0.6U east of it, facing west: each has the other in its arcs.
    A:setPosition(230000, 200000)
    A:setRotation(180)
    E2 = CpuShip():setTemplate("Adder MK5"):setFaction("Corsairs"):setPosition(230600, 200000)
    E2:setRotation(180)
    E2:orderIdle()
    local mine, theirs = {}, {}
    for i = 0, 15 do
        local r = A:getBeamWeaponRange(i)
        if r and r > 0 then mine[#mine + 1] = {dir = A:getBeamWeaponDirection(i), arc = A:getBeamWeaponArc(i), range = r} end
        local r2 = E2:getBeamWeaponRange(i)
        if r2 and r2 > 0 then theirs[#theirs + 1] = {dir = E2:getBeamWeaponDirection(i), arc = E2:getBeamWeaponArc(i), range = r2} end
    end
    T.check("arcs: the Adder can fire on the crew", BOUT.canHit(E2, theirs, A))
    T.check("arcs: the crew's aft beams can fire on the Adder", BOUT.canHit(A, mine, E2))
    E2:setRotation(0)
    T.check("arcs: turned away, the Adder can't", not BOUT.canHit(E2, theirs, A))
    E2:setRotation(180)
    b2 = BOUT.start{source = "test", enemies = {E2}}
    A:setHull(A:getHull() - 5)   -- contact
    BOUT.tick(b2, b2.last_sample + 1)
    BOUT.tick(b2, b2.last_sample + 1)
    local row = BOUT.finish(b2, "stopped")[1]
    T.check("row: exposed (in their arcs)", (row.exposed_pct or 0) > 0, tostring(row.exposed_pct))
    T.check("row: firing (they were in ours)", (row.firing_pct or 0) > 0, tostring(row.firing_pct))
    T.check("row: the range kept", row.avg_range_u and math.abs(row.avg_range_u - 0.6) < 0.05, tostring(row.avg_range_u))
    T.check("row: both sides' mobility", row.my_speed > 0 and row.en_speed > 0 and row.speed_ratio and row.turn_ratio,
        string.format("%s / %s", tostring(row.speed_ratio), tostring(row.turn_ratio)))
    T.check("row: the model's damage rates beside what landed", row.my_dps_model and row.enemy_dps_model)
    T.check("row text: arcs", BOUT.rowText(row):find("in their arcs", 1, true) ~= nil, BOUT.rowText(row))
    BOUT.clearRating(A)
end)

-- A real missile: the crew ship fires a homing missile at the Adder (2U east) from its aft tube.
T.step("missile: load", function()
    E2:setPosition(232000, 200000)
    A:setHull(A:getHullMax())
    A:setWeaponStorage("Homing", 2)
    A:setTubeLoadTime(0, 1)
    A:commandLoadTube(0, "Homing")
end)
T.wait(2.5)
T.step("missile: fire", function()
    b3 = BOUT.start{source = "test", enemies = {E2}}
    A:commandSetTarget(E2)
    A:commandFireTubeAtTarget(0, E2)
end)
T.waitFor("missile: seen in flight", function()
    BOUT.tick(b3, T.now())
    return b3.trackers[1].missiles_out >= 1
end, 5)
T.waitFor("missile: judged when it is gone", function()
    BOUT.tick(b3, T.now())
    return b3.missiles ~= nil and next(b3.missiles) == nil
end, 10)
T.step("missile: counted as fired and landed", function()
    local row = BOUT.finish(b3, "stopped")[1]
    T.eq("missile: fired", row.missiles_out, 1)
    T.eq("missile: hit", row.missiles_landed, 1)
    T.eq("missile: hit rate", row.missile_hit_pct, 100)
    BOUT.clearRating(A)
    if RT.valid(E2) then E2:destroy() end
end)

T.step("tidy up", function()
    if RT.valid(E) then E:destroy() end
    BOUT.clearLog()
    BOUT.log().crews = {}
    BOUT.save()
    A:setHull(A:getHullMax())
    A:setSystemHealth("impulse", 1)
    A:setPosition(home.x, home.y)
end)
