-- Custom ship templates for the Drift campaign.
-- Required from scenario_80_sandbox.lua at load time (before init).
-- ShipTemplates must be defined at script load, not during runtime.

-- ── Named freighters ──────────────────────────────────────────────────────────
-- Identical stats to the Flavia P.Falcon; only name and description differ.
-- copy() deep-copies all playership components from the original template.

local _pf = __ship_templates["Flavia P.Falcon"]

local _DRIFT_SHIPS = {
    {
        name = "Magpie",
        desc = "A battered Flavia transport running independent colors. Shows its age but flies true. The crew says she's got a good heart—whatever that means for a ship.",
    },
    {
        name = "Raven",
        desc = "Older than she looks and meaner than she sounds. The Raven's been through half the Drift and back. Someone painted over her registration twice.",
    },
    {
        name = "Jackdaw",
        desc = "Fast for a freighter, and the crew likes it that way. The Jackdaw's had her warp coils replaced three times. She runs hot but she runs.",
    },
    {
        name = "Starling",
        desc = "Small and quick, the Starling moves cargo no one asks questions about. Her hull plating is mismatched; most of it's newer than the frame.",
    },
    {
        name = "Wren",
        desc = "The smallest of the class and proud of it. The Wren can dock where bigger ships can't, which comes in handy more than you'd think.",
    },
    {
        name = "Kestrel",
        desc = "Stripped-down and re-tuned by her last crew, the Kestrel runs hotter than spec. Engineering earns their pay on this one.",
    },
    {
        name = "Harrier",
        desc = "A working ship with working-ship scars. The Harrier's been repaired more times than her manifest shows, and she flies better for it.",
    },
    {
        name = "Merlin",
        desc = "Deceptively quick off the line. The Merlin looks unremarkable—which is exactly how her captain likes it.",
    },
    {
        name = "Osprey",
        desc = "Built for the deep lanes, the Osprey has extra shielding on the bow and a pilot who knows when to run. Experienced crew, worn paint.",
    },
    {
        name = "Swift",
        desc = "Newest of the class and still has that fresh-welded smell. The Swift hasn't earned her scars yet—but she will.",
    },
}

for _, info in ipairs(_DRIFT_SHIPS) do
    local t = _pf:copy(info.name)
    t:setLocaleName(info.name)
    t:setDescription(info.desc)
    -- Register directly: copy already has all playership components from the original.
    -- Calling setType("playership") again would reset reactor/coolant to empty tables,
    -- which is harmless here but we avoid it to stay explicit.
    __player_ship_templates[#__player_ship_templates + 1] = t
end

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
