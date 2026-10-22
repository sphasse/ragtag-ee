-- ee/ragtag/verse/drift.lua
-- The base universe ("the Drift"). Pure data: no engine calls in this file.
--
-- It goes through the same VERSE.extend() as community extensions in
-- verse/extensions/. To add to the universe, prefer a new extension file;
-- edit this file only to change the base map itself. Every scenario depends
-- on it, so run `python tools/check.py` after any change.
--
-- Coordinates are in units (u); 1u = 1000 world units. Port Vesper is at 0, 0.

VERSE.extend({
    id = "drift",
    title = "The Drift (base universe)",

    -- Background the AI director is given (via tools/gen_world.py).
    lore = {
        "The Drift: a cluster of five suns at the edge of settled space. Money is tight, law is far away, and everyone owes someone. Twenty years ago the Settlement War ended with the Concord in charge; the Border and the Rim remember losing it.",
        "The white sun Lumen anchors the rich Concord Core. The Border worlds sit around Port Vesper and the red sun Cinder. The Rim runs east to the Shroud nebula, and beyond Lastchance Outpost the blue Pale Sun marks Hollow space.",
    },

    -- Suns are planets with the star texture.
    stars = {
        {name = "Lumen", x = -115, y = -72, r = 4.0, color = {1.0, 1.0, 1.0}},        -- the Core's white sun
        {name = "Cardinal", x = -40, y = -6, r = 3.0, color = {1.0, 0.92, 0.65}},     -- border, yellow
        {name = "Cinder", x = -55, y = 50, r = 3.0, color = {1.0, 0.45, 0.30}},       -- border, cold red
        {name = "Kestrel", x = 92, y = 28, r = 3.5, color = {1.0, 0.80, 0.45}},       -- the Rim, gold
        {name = "Pale Sun", x = 132, y = 96, r = 3.0, color = {0.55, 0.70, 1.0}},     -- the edge, blue
    },

    planets = {
        {name = "Ostia", x = -92, y = -86, r = 3.0, tex = "planets/planet-earth.png", clouds = "planets/clouds-1.png", atmo = {0.3, 0.5, 1.0},
         desc = "Ostia, jewel of the Core and seat of the Concord. Clean, rich, and very well policed."},
        {name = "Valcourt", x = -130, y = -46, r = 2.2, tex = "planets/planet-2.png", atmo = {0.4, 0.6, 1.0},
         desc = "Valcourt, a Core manufacturing world. Shipyards and smokestacks."},
        {name = "Tamsin", x = -36, y = 43, r = 2.2, tex = "planets/planet-1.png", clouds = "planets/clouds-2.png", atmo = {0.4, 0.8, 0.5},
         desc = "Tamsin, a farming world under the red light of Cinder. Grain, cattle, and long memories."},
        {name = "Shale", x = -31, y = 21, r = 1.5, tex = "planets/moon-2.png",
         desc = "Shale, a mined-out moon. Calder's Reach refines what's left of it."},
        {name = "Ashgrave", x = 30, y = -74, r = 2.6, tex = "planets/moon-3.png", atmo = {0.7, 0.3, 0.2},
         desc = "Ashgrave. Bombed to glass in the first week of the Settlement War. Nothing lives there and nothing ever will."},
        {name = "Hob", x = 75, y = 42, r = 2.4, tex = "planets/planet-3.png", atmo = {0.8, 0.7, 0.4},
         desc = "Hob, a dusty Rim world. Ranches, mines, and a sheriff who is usually somewhere else."},
        {name = "Corvid", x = 112, y = 4, r = 4.5, tex = "planets/gas-2.png", atmo = {0.6, 0.5, 0.8},
         desc = "Corvid, a gas giant at the edge of the Shroud. Skimmers say it sings on some frequencies."},
        {name = "Bleak", x = 124, y = 72, r = 2.0, tex = "planets/planet-5.png", atmo = {0.6, 0.1, 0.1},
         desc = "Bleak. The last charted world before the Pale Sun. Its colony went quiet eleven years ago."},
    },

    -- shop: list of upgrade ids sold there (see RT.UPGRADES). concord = refuses service if the crew is wanted.
    stations = {
        -- The Core (Concord)
        {cs = "Ostia Highport", tmpl = "Huge Station", fac = "Concord", x = -84, y = -79, concord = true,
         shop = {"shield_mk3", "sensor_suite", "engine_tune", "warp_overhaul", "combat_thrusters", "reactor_overhaul"},
         flavor = "Ostia Highport traffic control. Transponders on, weapons cold, and welcome to civilisation.",
         desc = "The largest port in the Core. Everything is for sale here, at Core prices, to people with clean records."},
        {cs = "Lumen Exchange", tmpl = "Large Station", fac = "Concord", x = -102, y = -58, concord = true,
         shop = {"shield_mk2", "shield_mk3", "repair_crew", "missile_racks"},
         flavor = "Lumen Exchange. Commodities, contracts and customs. Please have your manifest ready.",
         desc = "The Core's trading floor, in the light of the white sun Lumen."},
        {cs = "Sentinel Fleet Yard", tmpl = "Large Station", fac = "Concord", x = -122, y = -36, concord = true,
         flavor = "Sentinel Fleet Yard. This is a military facility. State your business or move along.",
         desc = "Concord fleet base. Warships come and go."},
        {cs = "Concord Waypoint Galen", tmpl = "Small Station", fac = "Concord", x = -58, y = -40, concord = true,
         flavor = "Waypoint Galen, Arbiter Line checkpoint. Hold for transponder verification.",
         desc = "A customs checkpoint on the Arbiter Line between the Core and the Border."},
        {cs = "Concord Station Arbiter", tmpl = "Medium Station", fac = "Concord", x = -16, y = -21, concord = true,
         flavor = "Concord Station Arbiter, customs and patrol. Transmit your manifest.",
         desc = "Concord customs station, watching the Border trade lanes."},

        -- The Border (Independent)
        {cs = "Port Vesper", tmpl = "Medium Station", fac = "Independent", x = 0, y = 0,
         shop = {"hull_plating", "missile_racks", "repair_crew", "engine_tune", "forward_beams"},
         flavor = "Port Vesper traffic control. Mind the dock clamps, they bite.",
         desc = "A crowded independent trading post built around an old ore refinery."},
        {cs = "Calder's Reach", tmpl = "Medium Station", fac = "Independent", x = -22, y = 14,
         shop = {"hull_plating", "hull_plating_2", "reactor_overhaul", "forward_beams"},
         flavor = "Calder's Reach. If you're not buying ore, you're in the way.",
         desc = "A refinery working the asteroids around the dead moon Shale."},
        {cs = "Tamsin Hollow", tmpl = "Small Station", fac = "Independent", x = -29, y = 36,
         shop = {"repair_crew", "missile_racks"},
         flavor = "Tamsin Hollow. Fresh bread, honest prices, no Concord inspectors. Usually.",
         desc = "Agricultural depot orbiting Tamsin. Feeds half the Border."},
        {cs = "Greywater Depot", tmpl = "Small Station", fac = "Independent", x = 20, y = 28,
         shop = {"front_tube", "missile_racks", "beam_coils"},
         flavor = "Greywater Depot. Fuel, parts, and a bar with no windows.",
         desc = "A fuel depot on the lane south toward the Gauntlet."},

        -- The Rim (Independent)
        {cs = "Halcyon Rest", tmpl = "Small Station", fac = "Independent", x = 32, y = -18,
         shop = {"shield_mk2", "sensor_suite", "repair_crew", "reactor_overhaul"},
         flavor = "Halcyon Rest. Fuel, food, and no questions. Mostly.",
         desc = "A waystation clinging to the edge of the Shroud nebula."},
        {cs = "Hob's Landing", tmpl = "Medium Station", fac = "Independent", x = 66, y = 34,
         shop = {"beam_coils", "combat_thrusters", "warp_overhaul", "shield_mk2"},
         flavor = "Hob's Landing. Dock where you like, pay what you owe, settle disputes outside.",
         desc = "The biggest town on the Rim, orbiting the dusty world Hob."},
        {cs = "Dustmote Salvage", tmpl = "Small Station", fac = "Independent", x = 80, y = -28,
         shop = {"jump_drive", "heavy_beams", "front_tube", "hull_plating_2"},
         flavor = "Dustmote Salvage. We buy anything. We sell everything. We ask nothing.",
         desc = "A scrapyard and black market. Half its stock fell off the back of a Concord freighter."},
        {cs = "Saint Brennan's Mission", tmpl = "Small Station", fac = "Independent", x = 55, y = -48,
         flavor = "Saint Brennan's Mission. Whoever you are, whatever you've done, you're welcome here.",
         desc = "A clinic and shelter run by a quiet order. Neutral ground; even Corsairs leave it alone."},
        {cs = "Lastchance Outpost", tmpl = "Small Station", fac = "Independent", x = 104, y = 50,
         shop = {"heavy_beams", "missile_racks"},
         flavor = "Lastchance Outpost. Last fuel before the Pale Sun. Turn back while you still can.",
         desc = "The last inhabited station before the Maw. The people here keep their guns loaded."},

        -- Hostile
        {cs = "Blackwater", tmpl = "Medium Station", fac = "Corsairs", x = 42, y = 76,
         desc = "The Corsairs' haven. Fortified, mined, and full of stolen cargo."},
        {cs = "The Maw", tmpl = "Large Station", fac = "Hollow", x = 116, y = 88,
         desc = "Something was built here, out of other things. Hollow ships cluster around it like wasps."},
    },

    -- Named regions. The smallest region containing the ship wins.
    -- danger: 0 safe, 1 risky, 2 dangerous, 3 deadly
    regions = {
        {name = "the Concord Core", x = -105, y = -62, r = 42, danger = 0,
         desc = "The Core: Concord worlds around the white sun Lumen. Rich, safe, and watched."},
        {name = "the Arbiter Line", x = -48, y = -32, r = 16, danger = 0,
         desc = "The Arbiter Line, where Concord checkpoints watch traffic between the Core and the Border."},
        {name = "Vesper Drift", x = 6, y = -4, r = 15, danger = 0,
         desc = "Vesper Drift: busy lanes, loose rock, and Port Vesper at the centre of it all."},
        {name = "Calder's Reach", x = -24, y = 16, r = 11, danger = 0,
         desc = "Calder's Reach: asteroid mining around the dead moon Shale. Watch the rocks."},
        {name = "the Cinder Fields", x = -45, y = 44, r = 19, danger = 0,
         desc = "The Cinder Fields: farming worlds under a cold red sun."},
        {name = "Greywater", x = 20, y = 28, r = 9, danger = 0,
         desc = "Greywater: a fuel stop on the edge of the Gauntlet."},
        {name = "the Gauntlet", x = 18, y = 53, r = 22, danger = 1,
         desc = "The Gauntlet: an asteroid belt where Corsair crews wait for freighters. Rich pickings, if you can keep them."},
        {name = "Blackwater Reach", x = 42, y = 76, r = 16, danger = 2,
         desc = "Blackwater Reach: the Corsairs' home, wrapped in dark nebula and minefields."},
        {name = "the Shroud", x = 52, y = -6, r = 26, danger = 0,
         desc = "The Shroud: a vast nebula where sensors fail and ships go missing. Spacers tell stories."},
        {name = "Halcyon Rest", x = 32, y = -18, r = 7, danger = 0,
         desc = "Halcyon Rest, a waystation at the edge of the Shroud."},
        {name = "the Deep Shroud", x = 120, y = -22, r = 34, danger = 1,
         desc = "The Deep Shroud. Uncharted. Your sensors pick up tones that aren't quite noise."},
        {name = "the Rim", x = 76, y = 16, r = 44, danger = 0,
         desc = "The Rim: frontier worlds, long lanes, and law that arrives late or not at all."},
        {name = "Saint Brennan's", x = 55, y = -48, r = 7, danger = 0,
         desc = "Saint Brennan's Mission: neutral ground. Even Corsairs keep the peace here."},
        {name = "Dustmote", x = 80, y = -28, r = 9, danger = 0,
         desc = "Dustmote: a scrapyard in a cloud of wreckage. Everything here is for sale."},
        {name = "Hob's Landing", x = 68, y = 36, r = 11, danger = 0,
         desc = "Hob's Landing, the biggest town on the Rim."},
        {name = "the Boneyard", x = 28, y = -74, r = 22, danger = 2,
         desc = "The Boneyard: the Settlement War battlefield around dead Ashgrave. Wrecks everywhere, and the drones never stopped fighting."},
        {name = "the Maw", x = 120, y = 84, r = 30, danger = 3,
         desc = "The Maw. Hollow space. Nobody comes back from here in a ship like yours."},
    },

    nebula_fields = {
        {x = 52, y = -6, r = 24, count = 26},     -- the Shroud
        {x = 120, y = -22, r = 32, count = 30},   -- the Deep Shroud
        {x = 42, y = 76, r = 13, count = 9},      -- the Veil around Blackwater
        {x = 28, y = -74, r = 18, count = 6},     -- Boneyard smoke
        {x = -45, y = 20, r = 10, count = 3},     -- border pockets
        {x = 15, y = 12, r = 8, count = 2},
        {x = -75, y = -15, r = 10, count = 3},
    },

    -- Asteroid fields: kind = "blob" (around a point) or "belt" (along a line)
    asteroid_fields = {
        {kind = "blob", x = -24, y = 18, r = 9, count = 60, visual = 40},              -- Calder's Reach
        {kind = "belt", x1 = -10, y1 = 46, x2 = 48, y2 = 58, width = 6, count = 150, visual = 80},  -- the Gauntlet
        {kind = "blob", x = 80, y = -28, r = 7, count = 35, visual = 30},              -- Dustmote debris
        {kind = "blob", x = 28, y = -74, r = 18, count = 45, visual = 30},             -- Boneyard debris
        {kind = "blob", x = 120, y = 84, r = 22, count = 70, visual = 40},             -- the Maw
        {kind = "belt", x1 = 6, y1 = -16, x2 = 22, y2 = 4, width = 3, count = 25, visual = 30},    -- Vesper Drift
        {kind = "blob", x = -70, y = 5, r = 8, count = 25, visual = 15},
        {kind = "blob", x = 96, y = 60, r = 8, count = 25, visual = 15},
        {kind = "blob", x = 60, y = 12, r = 6, count = 18, visual = 10},
    },

    -- Garrisons hold a location (orderDefendLocation) and don't wander.
    garrisons = {
        -- The Gauntlet: Corsair ambush packs (beatable early, with care)
        {fac = "Corsairs", x = 4, y = 49, ships = {"MT52 Hornet", "Adder MK5"}},
        {fac = "Corsairs", x = 22, y = 56, ships = {"Adder MK5", "Adder MK5"}},
        {fac = "Corsairs", x = 38, y = 53, ships = {"MT52 Hornet", "MT52 Hornet", "Adder MK5"}},
        -- Blackwater Reach: needs a few upgrades
        {fac = "Corsairs", x = 42, y = 70, ships = {"Phobos T3", "Adder MK5", "Adder MK5"}},
        {fac = "Corsairs", x = 48, y = 80, ships = {"Phobos T3", "Piranha F12", "MT52 Hornet"}},
        -- The Boneyard: relic war drones
        {fac = "Relic", x = 18, y = -66, ships = {"WX-Lindworm", "WX-Lindworm", "WX-Lindworm"}},
        {fac = "Relic", x = 36, y = -80, ships = {"Stalker Q7", "WX-Lindworm"}},
        {fac = "Relic", x = 26, y = -90, ships = {"Stalker R7", "Stalker Q7"}},
        {fac = "Relic", x = 30, y = -68, ships = {"Defense platform"}},
        -- The Maw: Hollow. Deadly without a heavily upgraded ship.
        {fac = "Hollow", x = 116, y = 82, ships = {"Atlantis X23", "Stalker R7", "Stalker R7"}},
        {fac = "Hollow", x = 106, y = 72, ships = {"Phobos T3", "Phobos T3", "Nirvana R5"}},
        {fac = "Hollow", x = 128, y = 92, ships = {"Starhammer II", "Fiend G4", "Ranus U"}},
        {fac = "Hollow", x = 110, y = 90, ships = {"Defense platform"}},
        {fac = "Hollow", x = 122, y = 78, ships = {"Defense platform"}},
        -- Concord pickets (neutral to the crew unless a session says otherwise)
        {fac = "Concord", x = -54, y = -30, ships = {"Phobos M3"}, callsign = "CPV Vigilant"},
        {fac = "Concord", x = -42, y = -44, ships = {"Phobos M3"}, callsign = "CPV Temperance"},
        {fac = "Concord", x = -100, y = -66, ships = {"Atlantis X23", "Phobos M3"}, callsign = "CNS Lawgiver"},
        -- Watchers in the Deep Shroud (neutral, silent)
        {fac = "Unknown", x = 128, y = -18, ships = {"Stalker Q7"}, idle = true},
        {fac = "Unknown", x = 108, y = -38, ships = {"Stalker Q7"}, idle = true},
    },

    -- Minefields: rings with a gap (gap_angle = where the way in is, degrees, 0 = up)
    minefields = {
        {x = 42, y = 76, r = 7, count = 26, gap_angle = 0, gap_width = 50},
        {x = 116, y = 88, r = 9, count = 34, gap_angle = 300, gap_width = 40},
    },

    -- Hazards
    hazards = {
        {kind = "blackhole", x = 136, y = -40},
        {kind = "wormhole", x = 132, y = -2, tx = 100, ty = 64,
         desc = "A spatial rift. Its far end reads like Hollow space."},
    },

    -- Wrecks: scanning one fully reveals salvage nearby (once per session).
    wreck_fields = {
        {x = 28, y = -74, r = 16, count = 12, tier = 2, templates = {"Atlantis X23", "Starhammer II", "Phobos T3", "Nirvana R5", "Stalker R7"},
         names = {"CWS Bulwark", "Free Ship Defiance", "CWS Morningside", "Free Ship Hollis", "CWS Anvil", "Free Ship Tallow",
                  "CWS Equity", "Free Ship Long Odds", "CWS Clarion", "Free Ship Harrow", "CWS Mercy", "Free Ship Whistler"},
         desc = "Settlement War wreck, {name}. Scorched hull, reactor cold for twenty years."},
        {x = 87, y = -35, r = 4, count = 4, tier = 0, templates = {"Goods Freighter 3", "Tug", "Flavia"},
         names = {"Hulk 7", "Hulk 12", "Hulk 19", "Hulk 23"},
         desc = "A stripped hull in the Dustmote yard, {name}. Somebody might have missed something."},
        {x = 112, y = -16, r = 20, count = 3, tier = 1, templates = {"Flavia", "Tug", "Personnel Freighter 2"},
         names = {"Penny Dreadful", "Calloway's Luck", "Seventh Son"},
         desc = "Missing freighter {name}. Logged lost in the Shroud. The airlock is open."},
    },

    -- Salvage clusters. tier: 0 safe, 1 risky, 2 dangerous, 3 deadly
    salvage = {
        {x = 9, y = -10, tier = 0}, {x = -18, y = 25, tier = 0}, {x = -42, y = 30, tier = 0}, {x = 26, y = 14, tier = 0},
        {x = 44, y = -30, tier = 0}, {x = 62, y = -14, tier = 0}, {x = 70, y = 2, tier = 0}, {x = 86, y = -36, tier = 0},
        {x = 58, y = 48, tier = 0}, {x = -62, y = -20, tier = 0}, {x = 14, y = -32, tier = 0}, {x = 96, y = 22, tier = 0},
        {x = 2, y = 52, tier = 1}, {x = 22, y = 50, tier = 1}, {x = 40, y = 57, tier = 1},
        {x = 112, y = -30, tier = 1}, {x = 126, y = -8, tier = 1},
        {x = 38, y = 70, tier = 2}, {x = 48, y = 82, tier = 2},
        {x = 20, y = -70, tier = 2}, {x = 34, y = -84, tier = 2}, {x = 26, y = -62, tier = 2},
        {x = 112, y = 80, tier = 3}, {x = 124, y = 92, tier = 3}, {x = 104, y = 74, tier = 3},
    },

    -- Freight routes. Transports dock, linger, then fly to another station on their route.
    routes = {
        {id = "core", fac = "Concord", count = 4,
         stations = {"Ostia Highport", "Lumen Exchange", "Sentinel Fleet Yard", "Concord Waypoint Galen", "Concord Station Arbiter", "Port Vesper"},
         names = {"CTS Provision", "CTS Steadfast", "CTS Tribute", "CTS Ordinance", "CTS Plenty", "CTS Accord"}},
        {id = "border", fac = "Independent", count = 6,
         stations = {"Port Vesper", "Calder's Reach", "Tamsin Hollow", "Greywater Depot", "Halcyon Rest", "Concord Station Arbiter"},
         names = {"Tin Kettle", "Molly Brannock", "Slow Dancer", "Three Wishes", "Bad Penny", "Good Intentions", "Iron Mule", "Halfmoon Rose"}},
        {id = "rim", fac = "Independent", count = 5,
         stations = {"Halcyon Rest", "Hob's Landing", "Dustmote Salvage", "Saint Brennan's Mission", "Lastchance Outpost", "Greywater Depot"},
         names = {"Borrowed Time", "Hardscrabble", "Pilgrim's Due", "Dandelion", "Old Faithful", "Kettle Black", "Cassowary"}},
    },

    rumors = {
        "Corsairs are working the Gauntlet again. Three crews, maybe four. Go round, or go fast.",
        "Dustmote Salvage has a jump drive for sale. Don't ask whose it was.",
        "The Boneyard drones are still shooting at a war that ended twenty years ago. There's good salvage between the wrecks, if you're quick.",
        "Freighter came back from beyond Lastchance with half her crew. Wouldn't say what they saw. Wouldn't say anything.",
        "There's a rift somewhere deep in the Shroud. Ships go in. I've never heard of one coming out where it went in.",
        "Concord's tightening the Arbiter Line. They're checking manifests twice now.",
        "Blackwater's sitting on a fortune in stolen cargo. Of course, so are its minefields.",
        "Hob's Landing sells combat thrusters, if you can afford them. Handy for getting out of trouble.",
        "If you see red running lights out past Lastchance, you didn't see them. Turn around. Don't hail.",
        "Folk on Tamsin say the Shroud hums at night. Folk on Tamsin say a lot of things.",
        "Calder's Reach pays bonuses for hull plating installs this month. Miners know armour.",
        "Somebody saw a ship with no transponder near Corvid. Just sat there. Watching.",
    },

})
