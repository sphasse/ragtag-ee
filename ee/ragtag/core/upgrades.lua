-- ee/ragtag/core/upgrades.lua
-- The upgrade catalogue and applying upgrades to a ship (RT.UPGRADES, RT.applyUpgrade, ...).
-- Part of core (RT). Loaded by ee/ragtag/core.lua; do not require directly.

--------------------------------------------------------------------------------
-- Upgrades. Each apply() must be idempotent-safe when re-run on a fresh ship
-- (they are re-applied in purchase order at the start of every session).
--------------------------------------------------------------------------------

RT.UPGRADES = {
    {id = "hull_plating", name = "Salvaged hull plating", gm_name = "Hull armor", cost = 200,
     desc = "+50 hull.",
     apply = function(p) p:setHullMax(p:getHullMax() + 50); p:setHull(p:getHullMax()) end},
    {id = "shield_mk2", name = "Mk II shield emitters", gm_name = "Shield II", cost = 250,
     desc = "Shields to 100 / 100.",
     apply = function(p) p:setShieldsMax(100, 100); p:setShields(100, 100) end},
    {id = "forward_beams", name = "Forward beam mount", gm_name = "Fwd beams", cost = 300,
     desc = "Adds a forward-firing beam. Finally something pointing where you're going.",
     apply = function(p) p:setBeamWeapon(2, 50, 0, 1000, 6, 6) end},
    {id = "beam_coils", name = "Overclocked beam coils", gm_name = "Beam coils", cost = 250, requires = "forward_beams",
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
    {id = "engine_tune", name = "Black-market engine tune", gm_name = "Eng tune", cost = 200,
     desc = "Impulse 60 -> 75.",
     apply = function(p) p:setImpulseMaxSpeed(75, 37) end},
    {id = "missile_racks", name = "Extra missile racks", gm_name = "Missiles", cost = 150,
     desc = "+4 homing, +6 HVLI capacity.",
     apply = function(p)
        p:setWeaponStorageMax("Homing", p:getWeaponStorageMax("Homing") + 4)
        p:setWeaponStorageMax("HVLI", p:getWeaponStorageMax("HVLI") + 6)
        p:setWeaponStorage("Homing", p:getWeaponStorageMax("Homing"))
        p:setWeaponStorage("HVLI", p:getWeaponStorageMax("HVLI"))
     end},
    {id = "front_tube", name = "Bow torpedo tube", gm_name = "Bow tube", cost = 350,
     desc = "Adds a forward missile tube.",
     apply = function(p)
        -- setWeaponTubeCount rebuilds all tubes, so re-set both directions.
        p:setWeaponTubeCount(2)
        p:setWeaponTubeDirection(0, 180)
        p:setWeaponTubeDirection(1, 0)
     end},
    {id = "repair_crew", name = "Two more hands", gm_name = "Repair crew", gm_label = "Repair 4 crew", cost = 150, crew = true,
     desc = "+2 repair crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "repair_crew_2", name = "Three more hands", gm_name = "Repair crew 2", gm_label = "Repair 6 crew", cost = 150, crew = true,
     requires = "repair_crew", desc = "+2 repair crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "repair_crew_3", name = "Full crew complement", gm_name = "Repair crew 3", gm_label = "Repair 8 crew", cost = 150, crew = true,
     requires = "repair_crew_2", desc = "+2 repair crew (max 8).",
     available = function(p) return p:getRepairCrewCount() < 8 end,
     apply = function(p) p:setRepairCrewCount(math.min(p:getRepairCrewCount() + 2, 8)) end},
    {id = "sensor_suite", name = "Long-range sensor suite", gm_name = "Sensors", cost = 150,
     desc = "Long-range radar 30u -> 45u.",
     apply = function(p) p:setLongRangeRadarRange(45000) end},
    {id = "fast_probes", name = "Overcharged probe capacitors", gm_name = "Fast probes", cost = 200,
     desc = "Scan probes fly at 2× speed.",
     apply = function(p) p:onProbeLaunch(function(ship, probe) probe:setSpeed(2000) end) end},
    {id = "ludicrous_probes", name = "Ludicrous-speed probe mod", gm_name = "Ludicrous", cost = 250, requires = "fast_probes",
     desc = "Scan probes fly at 4× speed. They've hit the plaid.",
     apply = function(p) p:onProbeLaunch(function(ship, probe) probe:setSpeed(4000) end) end},
    -- Second tier: what it takes to survive Blackwater, the Boneyard and, eventually, the Maw.
    {id = "reactor_overhaul", name = "Reactor overhaul", gm_name = "Reactor", cost = 200,
     desc = "+50% energy capacity.",
     apply = function(p) p:setMaxEnergy(p:getMaxEnergy() * 1.5); p:setEnergy(p:getMaxEnergy()) end},
    {id = "warp_overhaul", name = "Warp coil overhaul", gm_name = "Warp coils", cost = 250,
     desc = "Warp speed +50%.",
     apply = function(p) p:setWarpSpeed(p:getWarpSpeed() * 1.5) end},
    {id = "combat_thrusters", name = "Combat thrusters", gm_name = "Thrusters", cost = 300,
     desc = "Much stronger combat boost and strafe. Gets you out of trouble.",
     apply = function(p) p:setCombatManeuver(450, 300) end},
    {id = "hull_plating_2", name = "Armoured hull", gm_name = "Armor II", cost = 450, requires = "hull_plating",
     desc = "+100 hull.",
     apply = function(p) p:setHullMax(p:getHullMax() + 100); p:setHull(p:getHullMax()) end},
    {id = "heavy_beams", name = "Heavy beam emitters", gm_name = "Heavy beams", cost = 400, requires = "beam_coils",
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
    {id = "shield_mk3", name = "Military shield generators", gm_name = "Shield III", cost = 600, requires = "shield_mk2",
     desc = "Shields to 160 / 160. Concord military surplus, officially.",
     apply = function(p) p:setShieldsMax(160, 160); p:setShields(160, 160) end},
}

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

-- Grant an upgrade for free (story reward). Saves.
function RT.grantUpgrade(id, reason)
    if RT.hasUpgrade(id) or RT.upgradeById(id) == nil then return false end
    table.insert(RT.campaign.upgrades, id)
    RT.forEachPlayer(function(p) RT.applyUpgrade(p, id) end)
    RT.shipLog("Upgrade installed: " .. RT.upgradeById(id).name .. (reason and (" (" .. reason .. ")") or ""), "#80FF80")
    RT.saveCampaign()
    if DIR then DIR.emit("upgrade", {id = id, how = "granted", reason = reason}) end
    return true
end
