-- ee/ragtag/core/upgrades.lua
-- The upgrade catalogue and applying upgrades to a ship (RT.UPGRADES, RT.applyUpgrade, ...).
-- Part of core (RT). Loaded by ee/ragtag/core.lua; do not require directly.

--------------------------------------------------------------------------------
-- Upgrades. Each apply() must be idempotent-safe when re-run on a fresh ship
-- (they are re-applied in purchase order at the start of every session).
-- Every upgrade belongs to a component `line`. A station's shipwright is a base for whole lines
-- (drift.lua `shop = {"hull", "reactor"}`): it sells every level of those lines, so a new level
-- is on sale wherever the levels below it are. RT.UPGRADE_LINES names them for the crew.
--------------------------------------------------------------------------------

RT.UPGRADE_LINES = {
    {id = "hull", name = "hull"}, {id = "shields", name = "shield"}, {id = "beams", name = "beam"},
    {id = "missiles", name = "missile rack"}, {id = "tubes", name = "torpedo tube"},
    {id = "engines", name = "engine"}, {id = "thrusters", name = "thruster"}, {id = "reactor", name = "reactor"},
    {id = "repair", name = "repair crew"}, {id = "sensors", name = "sensor"}, {id = "probes", name = "probe"},
}

RT.UPGRADES = {
    {id = "hull_plating", line = "hull", name = "Salvaged hull plating", gm_name = "Hull armor", cost = 200,
     desc = "+50 hull.",
     apply = function(p) p:setHullMax(p:getHullMax() + 50); p:setHull(p:getHullMax()) end},
    {id = "shield_mk2", line = "shields", name = "Mk II shield emitters", gm_name = "Shield II", cost = 250,
     desc = "Shields to 100 / 100.",
     apply = function(p) p:setShieldsMax(100, 100); p:setShields(100, 100) end},
    {id = "forward_beams", line = "beams", name = "Forward beam mount", gm_name = "Fwd beams", cost = 300,
     desc = "Adds a forward-firing beam. Finally something pointing where you're going.",
     apply = function(p) p:setBeamWeapon(2, 50, 0, 1000, 6, 6) end},
    {id = "beam_coils", line = "beams", name = "Overclocked beam coils", gm_name = "Beam coils", cost = 250, requires = "forward_beams",
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
    {id = "beam_coils_2", line = "beams", name = "Superconducting beam coils", gm_name = "Beam coils 2", cost = 800, requires = "beam_coils",
     desc = "+2 more damage on every beam (8 -> 10).",
     apply = function(p)
        for i = 0, 15 do
            local range = p:getBeamWeaponRange(i)
            if range ~= nil and range > 0 then
                p:setBeamWeapon(i, p:getBeamWeaponArc(i), p:getBeamWeaponDirection(i), range,
                    p:getBeamWeaponCycleTime(i), p:getBeamWeaponDamage(i) + 2)
            end
        end
     end},
    {id = "engine_tune", line = "engines", name = "Black-market engine tune", gm_name = "Eng tune", cost = 200,
     desc = "Impulse 60 -> 75.",
     apply = function(p) p:setImpulseMaxSpeed(75, 37) end},
    {id = "engine_tune_2", line = "engines", name = "Redline injector bypass", gm_name = "Eng tune 2", cost = 1400, requires = "engine_tune",
     desc = "Impulse 75 -> 90, reverse 45. The warranty was void two owners ago.",
     apply = function(p) p:setImpulseMaxSpeed(90, 45) end},
    -- Impulse acceleration (forward and reverse), stock 10 on the Light Freighter: three levels to
    -- double it. Absolute values, like the engine tunes.
    {id = "impulse_accel", line = "engines", name = "Rewound impulse coils", gm_name = "Accel I", cost = 300,
     desc = "Impulse acceleration 10 -> 13, forward and reverse.",
     apply = function(p) p:setAcceleration(13, 13) end},
    {id = "impulse_accel_2", line = "engines", name = "High-flow plasma injectors", gm_name = "Accel II", cost = 1000, requires = "impulse_accel",
     desc = "Impulse acceleration 13 -> 16, forward and reverse.",
     apply = function(p) p:setAcceleration(16, 16) end},
    {id = "impulse_accel_3", line = "engines", name = "Courier-grade impulse drive", gm_name = "Accel III", cost = 2500, requires = "impulse_accel_2",
     desc = "Impulse acceleration 16 -> 20: twice the stock freighter's. Built for ships that are paid to arrive first.",
     apply = function(p) p:setAcceleration(20, 20) end},
    {id = "missile_racks", line = "missiles", name = "Extra missile racks", gm_name = "Missiles", cost = 150,
     desc = "+4 homing, +6 HVLI capacity.",
     apply = function(p)
        p:setWeaponStorageMax("Homing", p:getWeaponStorageMax("Homing") + 4)
        p:setWeaponStorageMax("HVLI", p:getWeaponStorageMax("HVLI") + 6)
        p:setWeaponStorage("Homing", p:getWeaponStorageMax("Homing"))
        p:setWeaponStorage("HVLI", p:getWeaponStorageMax("HVLI"))
     end},
    {id = "missile_racks_2", line = "missiles", name = "Even more missile racks", gm_name = "Missiles 2", cost = 450, requires = "missile_racks",
     desc = "+5 homing, +9 HVLI capacity: 12 homing and 20 HVLI in all.",
     apply = function(p)
        p:setWeaponStorageMax("Homing", p:getWeaponStorageMax("Homing") + 5)
        p:setWeaponStorageMax("HVLI", p:getWeaponStorageMax("HVLI") + 9)
        p:setWeaponStorage("Homing", p:getWeaponStorageMax("Homing"))
        p:setWeaponStorage("HVLI", p:getWeaponStorageMax("HVLI"))
     end},
    {id = "front_tube", line = "tubes", name = "Bow torpedo tube", gm_name = "Bow tube", cost = 350,
     desc = "Adds a forward missile tube.",
     apply = function(p)
        -- setWeaponTubeCount rebuilds all tubes, so re-set both directions.
        p:setWeaponTubeCount(2)
        p:setWeaponTubeDirection(0, 180)
        p:setWeaponTubeDirection(1, 0)
     end},
    {id = "side_tubes", line = "tubes", name = "Broadside torpedo tubes", gm_name = "Side tubes", cost = 1350, requires = "front_tube",
     desc = "Adds a tube on each side: four tubes, one facing every way.",
     apply = function(p)
        p:setWeaponTubeCount(4)   -- rebuilds all tubes: set every direction again
        p:setWeaponTubeDirection(0, 180)
        p:setWeaponTubeDirection(1, 0)
        p:setWeaponTubeDirection(2, -90)
        p:setWeaponTubeDirection(3, 90)
     end},
    {id = "repair_crew", line = "repair", name = "Two more hands", gm_name = "Repair crew", gm_label = "Repair 4 crew", cost = 150, crew = true,
     desc = "Hire 2 more engineering crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "repair_crew_2", line = "repair", name = "Another two hands", gm_name = "Repair crew 2", gm_label = "Repair 6 crew", cost = 150, crew = true,
     requires = "repair_crew", desc = "Hire 2 more engineering crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "repair_crew_3", line = "repair", name = "Full crew complement", gm_name = "Repair crew 3", gm_label = "Repair 8 crew", cost = 150, crew = true,
     requires = "repair_crew_2", desc = "Hire 2 more engineering crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "sensor_suite", line = "sensors", name = "Long-range sensor suite", gm_name = "Sensors", cost = 500,
     desc = "Long-range radar 30u -> 35u.",
     apply = function(p) p:setLongRangeRadarRange(35000) end},
    {id = "sensor_suite_2", line = "sensors", name = "Deep-field sensor array", gm_name = "Sensors 2", cost = 1000, requires = "sensor_suite",
     desc = "Long-range radar 35u -> 40u.",
     apply = function(p) p:setLongRangeRadarRange(40000) end},
    {id = "sensor_suite_3", line = "sensors", name = "Survey-grade sensor mast", gm_name = "Sensors 3", cost = 2000, requires = "sensor_suite_2",
     desc = "Long-range radar 40u -> 45u. Built for mapping the Drift; you'll use it to see trouble first.",
     apply = function(p) p:setLongRangeRadarRange(45000) end},
    {id = "fast_probes", line = "probes", name = "Overcharged probe capacitors", gm_name = "Fast probes", cost = 200,
     -- EE's stock probe speed is 1000 world units/s (shown as 60 a minute).
     desc = "Scan probe speed 60 -> 90.",
     apply = function(p) p:onProbeLaunch(function(ship, probe) probe:setSpeed(1500) end) end},
    {id = "ludicrous_probes", line = "probes", name = "Ludicrous-speed probe mod", gm_name = "Ludicrous", cost = 250, requires = "fast_probes",
     desc = "Scan probe speed 90 -> 120: twice stock. They've hit the plaid.",
     apply = function(p) p:onProbeLaunch(function(ship, probe) probe:setSpeed(2000) end) end},
    -- Second tier: what it takes to survive Blackwater, the Boneyard and, eventually, the Maw.
    {id = "reactor_overhaul", line = "reactor", name = "Reactor overhaul", gm_name = "Reactor", cost = 200,
     desc = "+50% energy capacity.",
     apply = function(p) p:setMaxEnergy(p:getMaxEnergy() * 1.5); p:setEnergy(p:getMaxEnergy()) end},
    {id = "combat_thrusters", line = "thrusters", name = "Combat thrusters", gm_name = "Thrusters", cost = 300,
     desc = "Much stronger combat boost and strafe. Gets you out of trouble.",
     apply = function(p) p:setCombatManeuver(450, 300) end},
    -- Maneuvering thrusters: the turn rate, stock 10 degrees/s on the Light Freighter; three levels
    -- to double it. Absolute values.
    {id = "maneuver_thrusters", line = "thrusters", name = "Re-bored maneuvering jets", gm_name = "Turn I", cost = 200,
     desc = "Turn rate 10 -> 13 degrees a second.",
     apply = function(p) p:setRotationMaxSpeed(13) end},
    {id = "maneuver_thrusters_2", line = "thrusters", name = "Twin-nozzle thruster clusters", gm_name = "Turn II", cost = 800, requires = "maneuver_thrusters",
     desc = "Turn rate 13 -> 16 degrees a second.",
     apply = function(p) p:setRotationMaxSpeed(16) end},
    {id = "maneuver_thrusters_3", line = "thrusters", name = "Vectored thruster array", gm_name = "Turn III", cost = 2000, requires = "maneuver_thrusters_2",
     desc = "Turn rate 16 -> 20 degrees a second: twice the stock freighter's. She turns like a fighter now.",
     apply = function(p) p:setRotationMaxSpeed(20) end},
    {id = "hull_plating_2", line = "hull", name = "Armoured hull", gm_name = "Armor II", cost = 450, requires = "hull_plating",
     desc = "+100 hull.",
     apply = function(p) p:setHullMax(p:getHullMax() + 100); p:setHull(p:getHullMax()) end},
    {id = "hull_plating_3", line = "hull", name = "Reinforced bulkheads", gm_name = "Armor III", cost = 1100, requires = "hull_plating_2",
     desc = "+150 hull (400 in all).",
     apply = function(p) p:setHullMax(p:getHullMax() + 150); p:setHull(p:getHullMax()) end},
    {id = "heavy_beams", line = "beams", name = "Heavy beam emitters", gm_name = "Heavy beams", cost = 400, requires = "beam_coils",
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
    {id = "shield_mk3", line = "shields", name = "Military shield generators", gm_name = "Shield III", cost = 600, requires = "shield_mk2",
     desc = "Shields to 160 / 160. Concord military surplus, officially.",
     apply = function(p) p:setShieldsMax(160, 160); p:setShields(160, 160) end},
    {id = "shield_mk4", line = "shields", name = "Capital-grade shield array", gm_name = "Shield IV", cost = 1800, requires = "shield_mk3",
     desc = "Shields to 220 / 220. Meant for a ship three times this size.",
     apply = function(p) p:setShieldsMax(220, 220); p:setShields(220, 220) end},
}

-- The crew-facing name of a component line ("hull" -> "hull"), or the id itself.
function RT.upgradeLineName(line)
    for _, l in ipairs(RT.UPGRADE_LINES) do if l.id == line then return l.name end end
    return line
end

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

-- Upgrades belong to a ship: they are in its record (core.lua, "Per-ship records") and are
-- applied to that ship only. `ship` defaults to the primary ship (for arcs; see core.lua).

-- The ship's upgrade ids, in purchase order. The record's own list: do not modify it.
function RT.upgrades(ship)
    local rec = RT.shipRecord(ship)
    return rec and rec.upgrades or {}
end

function RT.hasUpgrade(id, ship)
    for _, u in ipairs(RT.upgrades(ship)) do
        if u == id then return true end
    end
    return false
end

-- Credits the ship has put into upgrades (list price). Job tiers and arc triggers read it.
function RT.upgradeSpend(ship)
    local total = 0
    for _, id in ipairs(RT.upgrades(ship)) do
        local u = RT.upgradeById(id)
        total = total + (u and u.cost or 0)
    end
    return total
end

-- Record an upgrade on a ship and apply it. No charge, no log line. Saves.
function RT.installUpgrade(id, ship)
    local rec = RT.shipRecord(ship)
    local p = RT.playerShip(ship) or RT.player
    if rec == nil or RT.upgradeById(id) == nil or RT.hasUpgrade(id, p) then return false end
    table.insert(rec.upgrades, id)
    if RT.valid(p) then RT.applyUpgrade(p, id) end
    RT.saveCampaign()
    return true
end

-- Grant an upgrade for free (story reward, GM). Saves.
function RT.grantUpgrade(id, reason, ship)
    local p = RT.playerShip(ship) or RT.player
    if not RT.installUpgrade(id, p) then return false end
    if RT.valid(p) then
        local u = RT.upgradeById(id)
        p:addToShipLog((u.crew and "Crew hired: " or "Upgrade installed: ") .. u.name .. (reason and (" (" .. reason .. ")") or ""), "#80FF80")
    end
    RT.emit("upgrade", {id = id, how = "granted", reason = reason, ship = RT.valid(p) and p:getCallSign() or nil})
    return true
end

-- Take an upgrade off a ship (GM). The hull is rebuilt from its template and the remaining
-- upgrades re-applied, since an upgrade's effect cannot be undone piecemeal. Saves.
-- Rebuild a ship from its template, keeping its name, faction, position and heading: the only
-- way to take upgrades off (an upgrade's effect cannot be undone piece by piece). Hull, shields,
-- energy and missiles go back to the template's; the caller re-applies the upgrades it keeps.
function RT.rebuildHull(p)
    if not RT.valid(p) then return end
    local x, y = p:getPosition()
    local rot, cs, fac, tmpl = p:getRotation(), p:getCallSign(), p:getFaction(), p:getTypeName()
    p:setTemplate(tmpl or RT.PLAYER_TEMPLATE)
    p:setCallSign(cs):setFaction(fac):setPosition(x, y):setRotation(rot)
    RT.provision(p)   -- the stock freighter loadout again (setTemplate brought the nuke back)
    -- setTemplate keeps the probe launcher's on-launch callback, so a removed probe upgrade would
    -- keep launching fast probes: back to stock speed (the upgrades still kept set it again).
    p:onProbeLaunch(function(ship, probe) probe:setSpeed(1000) end)
end

function RT.revokeUpgrade(id, ship)
    local rec = RT.shipRecord(ship)
    local p = RT.playerShip(ship) or RT.player
    if rec == nil or not RT.hasUpgrade(id, p) then return false end
    local kept = {}
    for _, uid in ipairs(rec.upgrades) do
        if uid ~= id then kept[#kept + 1] = uid end
    end
    rec.upgrades = kept
    if RT.valid(p) then
        RT.rebuildHull(p)
        for _, uid in ipairs(kept) do RT.applyUpgrade(p, uid) end
        local u = RT.upgradeById(id)
        if u then p:addToShipLog("Upgrade removed: " .. u.name, "#FF8080") end
    end
    RT.saveCampaign()
    return true
end
