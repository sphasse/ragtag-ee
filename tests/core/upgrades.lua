-- The upgrade catalogue (core/upgrades.lua) and where it is sold: every upgrade belongs to a
-- component line; a station's shipwright is a base for lines and sells every level of them. Each
-- line's levels, applied in order, end where the catalogue says. The Science DB names the bases.
--
-- Not covered: buying through the shipwright's comms (tests/core/records.lua does that), and how
-- the upgraded ship fights.

T.suite("core")

local function station(cs) return RT.stations[cs] end
local B

T.step("the catalogue", function()
    local ids, lines = {}, {}
    for _, l in ipairs(RT.UPGRADE_LINES) do lines[l.id] = true end
    local no_line = {}
    for _, u in ipairs(RT.UPGRADES) do
        ids[u.id] = u
        if not lines[u.line] then no_line[#no_line + 1] = u.id end
    end
    T.eq("catalogue: every upgrade belongs to a known line", table.concat(no_line, ", "), "")
    T.check("catalogue: no warp coil overhaul any more", ids.warp_overhaul == nil)
    local cost = function(id) return ids[id] and ids[id].cost end
    T.eq("sensors 1: 500", cost("sensor_suite"), 500)
    T.eq("sensors 2: 1000", cost("sensor_suite_2"), 1000)
    T.eq("sensors 3: 2000", cost("sensor_suite_3"), 2000)
    T.eq("hull 3: 1100", cost("hull_plating_3"), 1100)
    T.eq("shields 4: 1800", cost("shield_mk4"), 1800)
    T.eq("side tubes: 1350", cost("side_tubes"), 1350)
    T.eq("missiles 2: 450", cost("missile_racks_2"), 450)
    T.eq("engines 2: 1400", cost("engine_tune_2"), 1400)
    T.eq("turn 1: 200", cost("maneuver_thrusters"), 200)
    T.eq("turn 2: 800", cost("maneuver_thrusters_2"), 800)
    T.eq("turn 3: 2000", cost("maneuver_thrusters_3"), 2000)
    T.eq("acceleration 1: 300", cost("impulse_accel"), 300)
    T.eq("acceleration 2: 1000", cost("impulse_accel_2"), 1000)
    T.eq("acceleration 3: 2500", cost("impulse_accel_3"), 2500)
    T.eq("turn levels are thruster upgrades", ids.maneuver_thrusters and ids.maneuver_thrusters.line, "thrusters")
    T.eq("acceleration levels are engine upgrades", ids.impulse_accel and ids.impulse_accel.line, "engines")
    T.check("superconducting coils exist", ids.beam_coils_2 ~= nil)
    -- Every level has its own name, and engineering crew are hired (each level adds two).
    local seen, dup = {}, {}
    for _, u in ipairs(RT.UPGRADES) do
        if seen[u.name] then dup[#dup + 1] = u.name end
        seen[u.name] = true
    end
    T.eq("catalogue: no two upgrades share a name", table.concat(dup, ", "), "")
    -- Probe speed: stock 1000 world units/s (60 a minute), then 90 and 120.
    local function probeSpeed(id)
        local launch, speed
        ids[id].apply({onProbeLaunch = function(_, fn) launch = fn end})
        if launch then launch(nil, {setSpeed = function(_, v) speed = v end}) end
        return speed
    end
    T.eq("probes 1: 90 (1500 units/s)", probeSpeed("fast_probes"), 1500)
    T.eq("probes 2: 120 (2000 units/s)", probeSpeed("ludicrous_probes"), 2000)
    for _, id in ipairs({"repair_crew", "repair_crew_2", "repair_crew_3"}) do
        T.check("crew: " .. id .. " is hired engineering crew", ids[id] and ids[id].crew and ids[id].desc:find("Hire 2 more engineering crew", 1, true) ~= nil)
        T.check("crew: " .. id .. " never says three", ids[id] and not ids[id].name:lower():find("three", 1, true))
    end
    for id, req in pairs({sensor_suite_2 = "sensor_suite", sensor_suite_3 = "sensor_suite_2", hull_plating_3 = "hull_plating_2",
                          shield_mk4 = "shield_mk3", beam_coils_2 = "beam_coils", side_tubes = "front_tube",
                          missile_racks_2 = "missile_racks", engine_tune_2 = "engine_tune",
                          maneuver_thrusters_2 = "maneuver_thrusters", maneuver_thrusters_3 = "maneuver_thrusters_2",
                          impulse_accel_2 = "impulse_accel", impulse_accel_3 = "impulse_accel_2"}) do
        T.eq("requires: " .. id, ids[id] and ids[id].requires, req)
    end
end)

T.step("bases sell whole lines", function()
    T.check("Calder's Reach (hull base) fits all hull levels",
        RT.stocks(station("Calder's Reach"), "hull_plating") and RT.stocks(station("Calder's Reach"), "hull_plating_3"))
    T.check("Ostia Highport (shield base) fits Shield IV", RT.stocks(station("Ostia Highport"), "shield_mk4"))
    T.check("Greywater Depot (tube base) fits the side tubes", RT.stocks(station("Greywater Depot"), "side_tubes"))
    T.check("Calder's Reach (beam base) fits superconducting coils", RT.stocks(station("Calder's Reach"), "beam_coils_2"))
    -- Hob's Landing: the independent science and engineering port, everything Ostia Highport fits.
    for _, id in ipairs({"sensor_suite_3", "engine_tune_2", "impulse_accel_3", "maneuver_thrusters_3", "combat_thrusters",
                         "reactor_overhaul", "shield_mk4", "ludicrous_probes"}) do
        T.check("Hob's Landing (the Hob Works) fits " .. id, RT.stocks(station("Hob's Landing"), id))
    end
    T.check("Hob's Landing no longer sells beams", not RT.stocks(station("Hob's Landing"), "forward_beams"))
    local concord_only = {}
    for _, u in ipairs(RT.UPGRADES) do
        local indep = false
        for cs, info in pairs(RT.stations) do
            local e = info.entity
            if info.shop and RT.valid(e) and e:getFaction() ~= "Concord" and RT.stocks(info, u.id) then indep = true end
        end
        if not indep then concord_only[#concord_only + 1] = u.id end
    end
    T.eq("no upgrade is Concord-only", table.concat(concord_only, ", "), "")
    T.check("Halcyon Rest (sensor base) fits all sensor levels", RT.stocks(station("Halcyon Rest"), "sensor_suite_3"))
    T.check("Port Vesper (engine base) fits the second engine tune", RT.stocks(station("Port Vesper"), "engine_tune_2"))
    T.check("Tamsin Hollow (missile base) fits the second racks", RT.stocks(station("Tamsin Hollow"), "missile_racks_2"))
    T.check("Tamsin Hollow is no hull base", not RT.stocks(station("Tamsin Hollow"), "hull_plating"))
    for _, cs in ipairs({"Ostia Highport", "Hob's Landing"}) do
        T.check(cs .. " (thruster base) fits all turn levels", RT.stocks(station(cs), "maneuver_thrusters") and RT.stocks(station(cs), "maneuver_thrusters_3"))
    end
    for _, cs in ipairs({"Ostia Highport", "Port Vesper", "Hob's Landing"}) do
        T.check(cs .. " (engine base) fits all acceleration levels", RT.stocks(station(cs), "impulse_accel") and RT.stocks(station(cs), "impulse_accel_3"))
    end
    T.check("Calder's Reach sells neither", not RT.stocks(station("Calder's Reach"), "maneuver_thrusters") and not RT.stocks(station("Calder's Reach"), "impulse_accel"))
    local sold = {}
    for _, info in pairs(RT.stations) do
        if info.shop then
            for _, u in ipairs(RT.UPGRADES) do if RT.stocks(info, u.id) then sold[u.id] = true end end
        end
    end
    local unsold = {}
    for _, u in ipairs(RT.UPGRADES) do if not sold[u.id] then unsold[#unsold + 1] = u.id end end
    T.eq("every upgrade is sold somewhere", table.concat(unsold, ", "), "")
    local entry = SCIDB._entries["port_Calder's Reach"]
    local text = entry and entry:getLongDescription() or ""
    T.check("science DB: 'Base for hull, reactor and beam upgrades'", text:find("Base for hull, reactor and beam upgrades", 1, true) ~= nil, text:sub(1, 300))
    T.eq("science DB: the shipwright line", entry and entry:getKeyValue("Shipwright"), "hull, reactor, beam")
    B = T.secondShip()
end)

-- Each line, all levels in order, on a stock ship.
T.step("the levels add up", function()
    for _, id in ipairs({"sensor_suite"}) do RT.grantUpgrade(id, "test", B) end
    T.eq("radar after level 1: 35U", B:getLongRangeRadarRange(), 35000)
    RT.grantUpgrade("sensor_suite_2", "test", B)
    T.eq("radar after level 2: 40U", B:getLongRangeRadarRange(), 40000)
    RT.grantUpgrade("sensor_suite_3", "test", B)
    T.eq("radar after level 3: 45U", B:getLongRangeRadarRange(), 45000)
    for _, id in ipairs({"hull_plating", "hull_plating_2", "hull_plating_3"}) do RT.grantUpgrade(id, "test", B) end
    T.eq("hull: 400", B:getHullMax(), 400)
    for _, id in ipairs({"shield_mk2", "shield_mk3", "shield_mk4"}) do RT.grantUpgrade(id, "test", B) end
    T.eq("shields: 220", B:getShieldMax(0), 220)
    for _, id in ipairs({"forward_beams", "beam_coils", "beam_coils_2"}) do RT.grantUpgrade(id, "test", B) end
    T.eq("forward beam: 6 -> 8 -> 10 damage", B:getBeamWeaponDamage(2), 10)
    for _, id in ipairs({"front_tube", "side_tubes"}) do RT.grantUpgrade(id, "test", B) end
    T.eq("tubes: four", B:getWeaponTubeCount(), 4)
    for _, id in ipairs({"missile_racks", "missile_racks_2"}) do RT.grantUpgrade(id, "test", B) end
    T.eq("missiles: 12 homing", B:getWeaponStorageMax("Homing"), 12)
    T.eq("missiles: 20 HVLI", B:getWeaponStorageMax("HVLI"), 20)
    for _, id in ipairs({"engine_tune", "engine_tune_2"}) do RT.grantUpgrade(id, "test", B) end
    local fwd, rev = B:getImpulseMaxSpeed()
    T.eq("impulse: 90", fwd, 90)
    T.eq("reverse: 45", rev, 45)
    T.eq("stock turn rate: 10", B:getRotationMaxSpeed(), 10)
    T.eq("stock acceleration: 10", B:getAcceleration(), 10)
    local turn = {}
    for _, id in ipairs({"maneuver_thrusters", "maneuver_thrusters_2", "maneuver_thrusters_3"}) do
        RT.grantUpgrade(id, "test", B); turn[#turn + 1] = math.floor(B:getRotationMaxSpeed() + 0.5)
    end
    T.eq("turn rate: 13, 16, then 20 (double)", table.concat(turn, ", "), "13, 16, 20")
    local acc = {}
    for _, id in ipairs({"impulse_accel", "impulse_accel_2", "impulse_accel_3"}) do
        RT.grantUpgrade(id, "test", B); acc[#acc + 1] = math.floor(B:getAcceleration() + 0.5)
    end
    T.eq("acceleration: 13, 16, then 20 (double)", table.concat(acc, ", "), "13, 16, 20")
    T.eq("reverse acceleration doubles too", math.floor(B.components.impulse_engine.acceleration_reverse + 0.5), 20)
end)

-- ── Probes, for real: launched from the ship and timed in flight ─────────────
-- The catalogue check above only shows the upgrade asks for the right speed. Here each probe is
-- launched through the engine (commandLaunchProbe, the Relay/Science launch path, which runs the
-- ship's onProbeLaunch), flies for 2 s, and its distance gives its speed: stock 1000 units/s
-- (60 U a minute on the screen), 1500 with Overcharged probe capacitors, 2000 with the Ludicrous
-- mod, and stock again once both are removed.
local P = {}
local function probesNear(x, y)
    local out = {}
    for _, o in ipairs(getObjectsInRadius(x, y, 3000)) do
        if isObjectType(o, "ScanProbe") then out[o] = true end
    end
    return out
end
local function launchProbe(label)
    T.step("probe launch: " .. label, function()
        B:setPosition(200000, 200000)   -- open space, nothing in the way
        B:setScanProbeCount(B:getMaxScanProbeCount())
        local before = probesNear(200000, 200000)
        commandLaunchProbe(B, 300000, 200000)   -- 100U east: it is still flying when timed
        P.probe = nil
        for o in pairs(probesNear(200000, 200000)) do if not before[o] then P.probe = o end end
        T.check("probe launch: " .. label .. ": a probe is out", P.probe ~= nil)
        if P.probe then P.x0 = P.probe:getPosition(); P.t0 = T.now() end
    end)
    T.wait(2)
    T.step("probe speed: " .. label, function()
        if not (P.probe and P.probe:isValid()) then return T.check("probe speed: " .. label .. ": still flying", false) end
        local x1 = P.probe:getPosition()
        P.speed = (x1 - P.x0) / (T.now() - P.t0)
        P.probe:destroy()
    end)
end
local function expectSpeed(label, want)
    T.step("probe speed: " .. label .. " is " .. want, function()
        T.check(string.format("probe speed: %s: %d units/s (measured %.0f)", label, want, P.speed or -1),
            P.speed and math.abs(P.speed - want) <= want * 0.05)
    end)
end

T.step("probes: stock ship", function()
    for _, id in ipairs({"ludicrous_probes", "fast_probes"}) do RT.revokeUpgrade(id, B) end
end)
launchProbe("stock");                 expectSpeed("stock", 1000)
T.step("probes: capacitors fitted", function() RT.grantUpgrade("fast_probes", "test", B) end)
launchProbe("capacitors");            expectSpeed("Overcharged probe capacitors", 1500)
T.step("probes: ludicrous mod fitted", function() RT.grantUpgrade("ludicrous_probes", "test", B) end)
launchProbe("ludicrous");             expectSpeed("Ludicrous-speed probe mod", 2000)
T.step("probes: both removed", function()
    RT.revokeUpgrade("ludicrous_probes", B); RT.revokeUpgrade("fast_probes", B)
end)
launchProbe("removed");               expectSpeed("both removed (stock again)", 1000)
