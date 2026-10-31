-- Custom ship templates for the Drift campaign.
-- Required from scenario_80_sandbox.lua at load time (before init).
-- ShipTemplates must be defined at script load, not during runtime.

-- ── Named freighters ──────────────────────────────────────────────────────────
-- Identical stats to the Flavia P.Falcon; only name and description differ.
-- copy() deep-copies all playership components from the original template.

local _pf = __ship_templates["Flavia P.Falcon"]

-- ── Independent Freighter ─────────────────────────────────────────────────────
-- Generic Flavia-class transport for the Drift campaign.  The scenario assigns
-- one of the named sister ships (Magpie, Raven, Jackdaw …) at spawn time.
local freighter = _pf:copy("Light Freighter")
freighter:setLocaleName("Light Freighter")
freighter:setDescription(
    "A Flavia-class transport running independent colors. " ..
    "One of the Drift's sister ships—Magpie, Raven, Jackdaw and the rest—" ..
    "will be assigned at spawn. Solid, unglamorous, and surprisingly hard to kill."
)
__player_ship_templates[#__player_ship_templates + 1] = freighter

-- ── Concord Enforcer ──────────────────────────────────────────────────────────
-- Heavy patrol cutter in Concord service colors. Well-armored, forward-biased
-- beam weapons, and enough missiles to mean business. Slower than the Raider
-- but takes considerably more punishment.

local enforcer = ShipTemplate()
enforcer:setName("Concord Enforcer")
enforcer:setLocaleName("Concord Enforcer")
enforcer:setClass("Frigate", "Patrol Cutter")
enforcer:setModel("LightCorvetteRed")
enforcer:setRadarTrace("piranha.png")
enforcer:setDescription(
    "A Concord patrol cutter in service colors. Well-maintained, properly armed, and flying lawful colors. " ..
    "Two forward beam mounts, broadside tubes, and hull plating thick enough to survive a mistake. " ..
    "If you're flying this, you're either law enforcement or a very convincing liar."
)
enforcer:setHull(140)
enforcer:setShields(100, 80)
enforcer:setSpeed(55, 12, 8)
enforcer:setWarpSpeed(500)
enforcer:setCombatManeuver(200, 100)
enforcer:setRepairCrewCount(4)
--                     Arc  Dir   Range  Cycle  Dmg
enforcer:setBeamWeapon(0,  60,   0, 1200, 5.0, 5)   -- wide forward sweep
enforcer:setBeamWeapon(1,  30,   0, 1500, 7.0, 6)   -- narrow long-range bore
enforcer:setBeamWeapon(2,  40, 180,  900, 8.0, 3)   -- rear defense
enforcer:setTubes(2, 15.0)
enforcer:setTubeDirection(0, -90)   -- port broadside
enforcer:setTubeDirection(1,  90)   -- starboard broadside
enforcer:setWeaponStorage("HVLI",   8)
enforcer:setWeaponStorage("Homing", 4)
enforcer:setWeaponStorage("EMP",    2)
enforcer:setWeaponStorage("Nuke",   1)
enforcer:setType("playership")

-- ── Corsair Raider ────────────────────────────────────────────────────────────
-- Fast attack craft running no particular colors. Light armor compensated by
-- speed, aggressive forward beams, and enough missile capacity to start and
-- finish an argument. Warp drive tuned beyond factory spec.

local raider = ShipTemplate()
raider:setName("Corsair Raider")
raider:setLocaleName("Corsair Raider")
raider:setClass("Frigate", "Attack Craft")
raider:setModel("HeavyCorvetteRed")
raider:setRadarTrace("piranha.png")
raider:setDescription(
    "Stripped-down attack ship running no particular colors. Fast, mean, and not much to look at. " ..
    "Twin forward beams, broadside tubes, and a warp drive tuned past what the manual recommends. " ..
    "Fly it lean or don't fly it at all."
)
raider:setHull(80)
raider:setShields(60, 50)
raider:setSpeed(75, 15, 12)
raider:setWarpSpeed(700)
raider:setCombatManeuver(300, 200)
raider:setRepairCrewCount(2)
--                    Arc  Dir   Range  Cycle  Dmg
raider:setBeamWeapon(0,  50,   0, 1200, 4.0, 5)   -- left forward
raider:setBeamWeapon(1,  50,   0, 1000, 5.0, 4)   -- right forward (overlapping = high forward DPS)
raider:setTubes(2, 12.0)
raider:setTubeDirection(0, -90)   -- port broadside
raider:setTubeDirection(1,  90)   -- starboard broadside
raider:setWeaponStorage("HVLI",   10)
raider:setWeaponStorage("Homing",  6)
raider:setWeaponStorage("EMP",     2)
raider:setType("playership")
