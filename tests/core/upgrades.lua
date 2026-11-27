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
    T.eq("coolant 1: 300", cost("coolant_pump"), 300)
    T.eq("coolant 2: 800", cost("coolant_pump_2"), 800)
    T.eq("coolant is a reactor upgrade", ids.coolant_pump and ids.coolant_pump.line, "reactor")
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
    -- Probe speed: stock 1000 world units/s (60 a minute), then 120 and 180.
    local function probeSpeed(id)
        local launch, speed
        ids[id].apply({onProbeLaunch = function(_, fn) launch = fn end})
        if launch then launch(nil, {setSpeed = function(_, v) speed = v end}) end
        return speed
    end
    T.eq("probes 1: 120 (2000 units/s)", probeSpeed("fast_probes"), 2000)
    T.eq("probes 2: 180 (3000 units/s)", probeSpeed("ludicrous_probes"), 3000)
    T.eq("probes: the catalogue's speeds match", ids.fast_probes.probe_speed .. "," .. ids.ludicrous_probes.probe_speed, "2000,3000")
    for _, id in ipairs({"repair_crew", "repair_crew_2", "repair_crew_3"}) do
        T.check("crew: " .. id .. " is hired engineering crew", ids[id] and ids[id].crew and ids[id].desc:find("Hire 2 more engineering crew", 1, true) ~= nil)
        T.check("crew: " .. id .. " never says three", ids[id] and not ids[id].name:lower():find("three", 1, true))
    end
    for id, req in pairs({sensor_suite_2 = "sensor_suite", sensor_suite_3 = "sensor_suite_2", hull_plating_3 = "hull_plating_2",
                          shield_mk4 = "shield_mk3", beam_coils_2 = "beam_coils", side_tubes = "front_tube",
                          missile_racks_2 = "missile_racks", engine_tune_2 = "engine_tune",
                          maneuver_thrusters_2 = "maneuver_thrusters", maneuver_thrusters_3 = "maneuver_thrusters_2",
                          impulse_accel_2 = "impulse_accel", impulse_accel_3 = "impulse_accel_2",
                          coolant_pump_2 = "coolant_pump"}) do
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
                         "reactor_overhaul", "coolant_pump_2", "shield_mk4", "ludicrous_probes"}) do
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
    -- The GM console's Ship Upgrades menu can grant and remove every upgrade.
    local in_gm = {}
    for _, g in ipairs(GMCONSOLE and GMCONSOLE.UPGRADE_GROUPS or {}) do
        for _, id in ipairs(g.ids) do in_gm[id] = true end
    end
    local not_in_gm = {}
    for _, u in ipairs(RT.UPGRADES) do if not in_gm[u.id] then not_in_gm[#not_in_gm + 1] = u.id end end
    T.eq("GM console: every upgrade in the Ship Upgrades menu", table.concat(not_in_gm, ", "), "")
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
    T.eq("turn rate: 13, 16, then 18 (under the fighters' 20)", table.concat(turn, ", "), "13, 16, 18")
    local acc = {}
    for _, id in ipairs({"impulse_accel", "impulse_accel_2", "impulse_accel_3"}) do
        RT.grantUpgrade(id, "test", B); acc[#acc + 1] = math.floor(B:getAcceleration() + 0.5)
    end
    T.eq("acceleration: 13, 16, then 20 (double)", table.concat(acc, ", "), "13, 16, 20")
    T.eq("reverse acceleration doubles too", math.floor(B.components.impulse_engine.acceleration_reverse + 0.5), 20)
    T.eq("stock coolant: 10 (100%)", B:getMaxCoolant(), 10)
    RT.grantUpgrade("coolant_pump", "test", B)
    T.eq("coolant I: 11 (110%)", B:getMaxCoolant(), 11)
    RT.grantUpgrade("coolant_pump_2", "test", B)
    T.eq("coolant II: 12.5 (125%)", B:getMaxCoolant(), 12.5)
    RT.revokeUpgrade("coolant_pump_2", B)
    T.eq("coolant II removed: back to 11", B:getMaxCoolant(), 11)
    RT.grantUpgrade("coolant_pump_2", "test", B)
end)

-- Levels set absolute values in purchase order. Removing a lower level takes the higher ones with
-- it, so the lower level can't be bought again on top of them and undo them (Shield II after
-- Shield III would put the shields back to 100).
T.step("removing a level removes the levels above it", function()
    local removed = RT.revokeUpgrade("shield_mk2", B)
    T.eq("revoke: Shield II takes III and IV with it", table.concat(removed or {}, ","), "shield_mk2,shield_mk3,shield_mk4")
    T.check("revoke: none of the three left", not RT.hasUpgrade("shield_mk3", B) and not RT.hasUpgrade("shield_mk4", B))
    T.eq("revoke: stock shields", B:getShieldMax(0), 70)
    T.check("revoke: Shield III needs Shield II again", not RT.upgradeOpen(RT.upgradeById("shield_mk3"), B))
    for _, id in ipairs({"shield_mk2", "shield_mk3", "shield_mk4"}) do RT.grantUpgrade(id, "test", B) end
    T.eq("re-fitted: 220", B:getShieldMax(0), 220)
    -- The top level goes alone.
    T.eq("revoke: Turn III alone", table.concat(RT.revokeUpgrade("maneuver_thrusters_3", B) or {}, ","), "maneuver_thrusters_3")
    T.eq("revoke: back to Turn II", math.floor(B:getRotationMaxSpeed() + 0.5), 16)
    RT.grantUpgrade("maneuver_thrusters_3", "test", B)
    -- Without a ship in the game: the list alone.
    local kept, gone = RT.upgradesWithout({"engine_tune", "hull_plating", "engine_tune_2", "hull_plating_2"}, "engine_tune")
    T.eq("upgradesWithout: kept", table.concat(kept, ","), "hull_plating,hull_plating_2")
    T.eq("upgradesWithout: removed", table.concat(gone, ","), "engine_tune,engine_tune_2")
end)

-- The forward mount is a choice: the forward beam mount or the sniper beam, never both.
T.step("the sniper beam: a choice with the forward beam", function()
    local sn = RT.upgradeById("sniper_beam")
    T.check("sniper: in the beam line", sn and sn.line == "beams")
    T.check("sniper: ruled out by the forward beam", RT.upgradeExcludedBy(sn, B) == RT.upgradeById("forward_beams"))
    T.check("sniper: not open with the forward beam", not RT.upgradeOpen(sn, B))
    T.check("sniper: not granted alongside it", not RT.grantUpgrade("sniper_beam", "test", B))
    T.check("sniper: not in the record", not RT.hasUpgrade("sniper_beam", B))
    T.eq("forward beam still 50 degrees", B:getBeamWeaponArc(2), 50)
    T.eq("coils need either mount", RT.upgradeNeedsText(RT.upgradeById("beam_coils")), "Forward beam mount or Sniper beam")
    T.check("shipwright: sniper sold where beams are", RT.stocks(station("Port Vesper") or {shop = true}, "sniper_beam")
        == RT.stocks(station("Port Vesper") or {shop = true}, "forward_beams"))
    -- Taking the only mount off takes the coils with it: they need a mount.
    local removed = RT.revokeUpgrade("forward_beams", B)
    T.eq("forward beam off: the coils go with it", table.concat(removed or {}, ","), "forward_beams,beam_coils,beam_coils_2")
    T.check("forward beam off: sniper open", RT.upgradeOpen(sn, B))
    T.check("forward beam off: no coils without a mount", not RT.upgradeOpen(RT.upgradeById("beam_coils"), B))
    T.check("sniper: granted", RT.grantUpgrade("sniper_beam", "test", B))
    T.eq("sniper: 5 degree arc", B:getBeamWeaponArc(2), 5)
    T.eq("sniper: 3U range", B:getBeamWeaponRange(2), 3000)
    T.check("coils count with either mount", RT.upgradeOpen(RT.upgradeById("beam_coils"), B))
    for _, id in ipairs({"beam_coils", "beam_coils_2"}) do RT.grantUpgrade(id, "test", B) end
    T.eq("sniper with both coils: 12 damage", B:getBeamWeaponDamage(2), 12)
    local stock0 = B:getBeamWeaponDamage(0)
    RT.grantUpgrade("heavy_beams", "test", B)
    T.eq("heavy emitters: sniper 3.4U", B:getBeamWeaponRange(2), 3400)
    T.eq("heavy emitters: stock beam damage unchanged", B:getBeamWeaponDamage(0), stock0)
    -- A rebuild (a removal re-applies the rest) keeps it: beam upgrades go on after the mounts.
    RT.revokeUpgrade("heavy_beams", B)
    T.eq("rebuilt: sniper still 12 damage", B:getBeamWeaponDamage(2), 12)
    T.eq("rebuilt: sniper back to 3U", B:getBeamWeaponRange(2), 3000)
    T.eq("rebuilt: stock beam damage unchanged", B:getBeamWeaponDamage(0), stock0)
    T.eq("sniper: dead ahead", B:getBeamWeaponDirection(2), 0)
    T.check("forward beam now ruled out", not RT.upgradeOpen(RT.upgradeById("forward_beams"), B))
    T.check("forward beam: not granted alongside", not RT.grantUpgrade("forward_beams", "test", B))
    RT.revokeUpgrade("sniper_beam", B)
    T.check("both off: no forward beam", (B:getBeamWeaponRange(2) or 0) == 0,
        string.format("arc %s range %s", tostring(B:getBeamWeaponArc(2)), tostring(B:getBeamWeaponRange(2))))
end)

-- ── Probes, for real: launched from the ship and timed in flight ─────────────
-- The catalogue check above only shows the upgrade asks for the right speed. Here each probe is
-- launched through the engine (commandLaunchProbe, the Relay/Science launch path, which runs the
-- ship's onProbeLaunch), flies for 2 s, and its distance gives its speed: stock 1000 units/s
-- (60 U a minute on the screen), 2000 with Overcharged probe capacitors, 3000 with the Ludicrous
-- mod, and stock again once both are removed. Level 1 keeps pace with the ship at full warp (warp 4:
-- 4 x 500 = 2000 units/s on the Light Freighter); level 2 outruns it.
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
launchProbe("capacitors");            expectSpeed("Overcharged probe capacitors", 2000)
T.step("probes: ludicrous mod fitted", function() RT.grantUpgrade("ludicrous_probes", "test", B) end)
launchProbe("ludicrous");             expectSpeed("Ludicrous-speed probe mod", 3000)
T.step("probes: faster than the ship at full warp", function()
    local warp4 = B.components.warp_drive.speed_per_level * 4
    T.eq("warp 4 on the Light Freighter", warp4, 2000)
    T.check("probes: level 1 keeps pace with warp 4", RT.upgradeById("fast_probes").probe_speed >= warp4)
    T.check("probes: level 2 outruns warp 4", RT.upgradeById("ludicrous_probes").probe_speed > warp4)
end)
T.step("probes: both removed", function()
    RT.revokeUpgrade("ludicrous_probes", B); RT.revokeUpgrade("fast_probes", B)
end)
launchProbe("removed");               expectSpeed("both removed (stock again)", 1000)
