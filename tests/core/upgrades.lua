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
    T.check("superconducting coils exist", ids.beam_coils_2 ~= nil)
    for id, req in pairs({sensor_suite_2 = "sensor_suite", sensor_suite_3 = "sensor_suite_2", hull_plating_3 = "hull_plating_2",
                          shield_mk4 = "shield_mk3", beam_coils_2 = "beam_coils", side_tubes = "front_tube",
                          missile_racks_2 = "missile_racks", engine_tune_2 = "engine_tune"}) do
        T.eq("requires: " .. id, ids[id] and ids[id].requires, req)
    end
end)

T.step("bases sell whole lines", function()
    T.check("Calder's Reach (hull base) fits all hull levels",
        RT.stocks(station("Calder's Reach"), "hull_plating") and RT.stocks(station("Calder's Reach"), "hull_plating_3"))
    T.check("Ostia Highport (shield base) fits Shield IV", RT.stocks(station("Ostia Highport"), "shield_mk4"))
    T.check("Greywater Depot (tube base) fits the side tubes", RT.stocks(station("Greywater Depot"), "side_tubes"))
    T.check("Hob's Landing (beam base) fits superconducting coils", RT.stocks(station("Hob's Landing"), "beam_coils_2"))
    T.check("Halcyon Rest (sensor base) fits all sensor levels", RT.stocks(station("Halcyon Rest"), "sensor_suite_3"))
    T.check("Port Vesper (engine base) fits the second engine tune", RT.stocks(station("Port Vesper"), "engine_tune_2"))
    T.check("Tamsin Hollow (missile base) fits the second racks", RT.stocks(station("Tamsin Hollow"), "missile_racks_2"))
    T.check("Tamsin Hollow is no hull base", not RT.stocks(station("Tamsin Hollow"), "hull_plating"))
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
    T.eq("science DB: the shipwright line", entry and entry:getKeyValue("Shipwright"), "base for hull, reactor and beam upgrades")
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
end)
