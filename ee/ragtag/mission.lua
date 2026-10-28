-- ee/ragtag/mission.lua
-- Rich delivery mission generation and route interception.
--
-- Usage in a scenario:
--   require("ragtag/mission.lua")   -- after director.lua
--   -- in init(), after VERSE.build():
--   -- (no init needed — uses DIR/RT globals directly)
--   -- when player accepts a delivery mission:
--   MISSION.track(m)
--   -- when player delivers or mission fails:
--   MISSION.untrack(m.id)
--   -- in update(delta):
--   MISSION.update(delta)
--
-- Director action create_delivery pushes missions into MISSION._dynamic_queue.
-- The scenario's job board should check and drain that queue.

MISSION = MISSION or {}

MISSION._tracked        = {}   -- id → mission (active route monitoring)
MISSION._dynamic_queue  = {}   -- missions injected by create_delivery action
MISSION._next_check     = 0
MISSION._check_interval = 5    -- seconds between route-progress checks

-- ---------------------------------------------------------------------------
-- Delivery archetypes
-- Fields:
--   cargo          — what's in the hold
--   lore           — one-line flavor shown on the brief screen
--   accept_msg     — what the contact says when the player takes the job
--   recv_msg       — what the recipient says on successful delivery
--   reward_mult    — multiplier on the base reward for this tier
--   tier_min       — lowest tier this archetype can appear at
--   intercept_types — list of {type, strength, weight, msg}
--                     type: "pirates" | "rival" | "concord"
--   intercept_chance — probability (0–1) that an interception spawns
-- ---------------------------------------------------------------------------

local _ARCHETYPES = {
    {
        cargo  = "medical supplies",
        lore   = "The destination station is short-staffed and someone isn't doing well.",
        accept_msg = '"Move fast. People are waiting on the other end."',
        recv_msg   = '"You got here in time. Thank you."',
        reward_mult = 1.1, tier_min = 0,
        intercept_types = {}, intercept_chance = 0,
    },
    {
        cargo  = "a locked strongbox",
        lore   = "Someone is moving their savings to a safer port. Don't ask how much is inside.",
        accept_msg = '"Don\'t lose it. Don\'t open it. Please."',
        recv_msg   = '"I thought I\'d never see this again."',
        reward_mult = 0.9, tier_min = 0,
        intercept_types = {
            {type="pirates", strength="scout", weight=3,
             msg="Two contacts on an intercept heading. They know what you're carrying."},
        },
        intercept_chance = 0.25,
    },
    {
        cargo  = "survey data cores",
        lore   = "Fresh scan data from a prospecting run. A rival outfit would pay well for it.",
        accept_msg = '"Bonded delivery. No stops, no detours."',
        recv_msg   = '"Ahead of schedule. Appreciated."',
        reward_mult = 1.0, tier_min = 0,
        intercept_types = {
            {type="rival", strength="scout", weight=3,
             msg="A courier just lit off after you. They want that data off your ship."},
        },
        intercept_chance = 0.30,
    },
    {
        cargo  = "emergency equipment",
        lore   = "Beacon relay parts for an outpost that went dark. No backup comms until you deliver.",
        accept_msg = '"Someone out there is waiting to call for help. Move."',
        recv_msg   = '"We\'re back online. You have no idea what that means to us."',
        reward_mult = 1.0, tier_min = 0,
        intercept_types = {}, intercept_chance = 0,
    },
    {
        cargo  = "ration crates",
        lore   = "Another crew quoted this run first. Get there before they do.",
        accept_msg = '"Beat them to it and the contract bonus is yours."',
        recv_msg   = '"You got here first. Contract\'s yours."',
        reward_mult = 0.95, tier_min = 0,
        intercept_types = {
            {type="rival", strength="scout", weight=3,
             msg="Competing delivery ship burning hard on your heading."},
        },
        intercept_chance = 0.40,
    },
    {
        cargo  = "a sealed crate",
        lore   = "They said don't ask. The pay says don't argue.",
        accept_msg = '"You didn\'t see this. We never spoke."',
        recv_msg   = '"Quiet and fast. Just how we like it."',
        reward_mult = 1.5, tier_min = 1,
        intercept_types = {
            {type="pirates",  strength="light", weight=2,
             msg="Three ships on intercept. Word got out you're carrying something valuable."},
            {type="concord", strength="light", weight=2,
             msg="Concord inspection frigate blocking the lane. Could be a tip-off, could be routine."},
        },
        intercept_chance = 0.60,
    },
    {
        cargo  = "sealed documents",
        lore   = "Corporate courier contract. The paperwork is above your clearance level.",
        accept_msg = '"Deliver to the named recipient only. Do not break the seal."',
        recv_msg   = '"Intact and on time. Your bond is cleared."',
        reward_mult = 1.2, tier_min = 1,
        intercept_types = {
            {type="rival", strength="light", weight=3,
             msg="Corporate security ship — not Concord. Someone doesn't want those documents to arrive."},
        },
        intercept_chance = 0.45,
    },
    {
        cargo  = "a bonded prisoner",
        lore   = "Alive and secured. Licensed transfer. Don't let them talk to you.",
        accept_msg = '"They\'ll try to negotiate. Standard contract: you don\'t open the bay."',
        recv_msg   = '"Secure, no incidents. The bond transfers to you now."',
        reward_mult = 1.4, tier_min = 1,
        intercept_types = {
            {type="pirates", strength="light", weight=3,
             msg="Fast ships on an intercept heading. Friends of your passenger, most likely."},
        },
        intercept_chance = 0.50,
    },
    {
        cargo  = "crated ordnance",
        lore   = "Licensed arms transfer, cleared manifest. Concord will still want to look.",
        accept_msg = '"Everything is above board. Mostly. Move fast."',
        recv_msg   = '"All present, no tamper seals broken. Good work."',
        reward_mult = 1.3, tier_min = 2,
        intercept_types = {
            {type="concord", strength="medium", weight=2,
             msg="Concord patrol moving to intercept. Arms manifests get extra scrutiny out here."},
            {type="pirates", strength="medium", weight=2,
             msg="Corsair raiders on an intercept vector. They're after what's in the crates."},
        },
        intercept_chance = 0.55,
    },
    {
        cargo  = "collector's cargo",
        lore   = "Rare items. High value. Somebody talked.",
        accept_msg = '"The value is in the pieces, not the container. Be careful."',
        recv_msg   = '"Every piece intact. I\'ll remember your callsign."',
        reward_mult = 1.35, tier_min = 2,
        intercept_types = {
            {type="pirates", strength="medium", weight=3,
             msg="Two ships on a cut-off vector. They know exactly what the cargo is worth."},
        },
        intercept_chance = 0.55,
    },
}

-- ---------------------------------------------------------------------------
-- Salvage archetypes
-- Fields mirror delivery archetypes; no origin/dest — just a site location.
-- Interception fires on proximity (when the site is reached), not en-route.
-- ---------------------------------------------------------------------------

local _SALVAGE_ARCHETYPES = {
    {
        cargo  = "a drifting cargo pod",
        lore   = "A sealed container came off a freighter in the belt. Transponder's still pinging.",
        accept_msg = '"Finder\'s fee. Bring it back intact."',
        recv_msg   = '"Container secured. That\'s what we were hoping for."',
        reward_mult = 1.0, tier_min = 0,
        intercept_types = {
            {type="pirates", strength="scout", weight=2,
             msg="Another ship is burning hard for the same beacon. They want the pod."},
        },
        intercept_chance = 0.20,
    },
    {
        cargo  = "an emergency beacon kit",
        lore   = "Evac pod came down in the field. No crew — just the kit. Still useful to someone.",
        accept_msg = '"Salvage rights are clear. Just go get it."',
        recv_msg   = '"That kit will save someone\'s life eventually."',
        reward_mult = 0.9, tier_min = 0,
        intercept_types = {}, intercept_chance = 0,
    },
    {
        cargo  = "a lost survey drone",
        lore   = "Mapping probe went dark after passing through a debris cloud. Data core may still be intact.",
        accept_msg = '"If the core is readable, there\'s a bonus in it."',
        recv_msg   = '"Data core intact. The bonus is yours."',
        reward_mult = 1.1, tier_min = 0,
        intercept_types = {
            {type="rival", strength="scout", weight=2,
             msg="Competing salvager just changed heading. They know about the drone."},
        },
        intercept_chance = 0.20,
    },
    {
        cargo  = "a corporate flight recorder",
        lore   = "A wreck that nobody is officially looking for. The flight recorder is worth more than the hull.",
        accept_msg = '"Don\'t look at what\'s on it. Just bring it back."',
        recv_msg   = '"We\'ll take it from here. You didn\'t find this."',
        reward_mult = 1.3, tier_min = 1,
        intercept_types = {
            {type="rival", strength="light", weight=3,
             msg="Corporate security ship just appeared on sensors. Someone tipped them off."},
        },
        intercept_chance = 0.40,
    },
    {
        cargo  = "a sealed courier pouch",
        lore   = "A courier ran into trouble. The ship is gone, but the pouch is hardened and should have survived.",
        accept_msg = '"Delivery contract is intact if the pouch is. Same rate."',
        recv_msg   = '"Seal\'s unbroken. Contract honoured."',
        reward_mult = 1.2, tier_min = 1,
        intercept_types = {
            {type="pirates", strength="light", weight=3,
             msg="Whoever took out the courier is still in the area."},
        },
        intercept_chance = 0.50,
    },
    {
        cargo  = "a weapons locker",
        lore   = "Patrol ship went down hard. The armory container ejected clean. Concord will want it, but finders keep it.",
        accept_msg = '"Manifest says it\'s unsecured. Move fast."',
        recv_msg   = '"Secured. We\'ll keep this one quiet."',
        reward_mult = 1.4, tier_min = 2,
        intercept_types = {
            {type="concord", strength="medium", weight=2,
             msg="Concord patrol is moving to secure the site. They want that locker."},
            {type="pirates", strength="medium", weight=2,
             msg="Corsair raider closing fast. They're after the weapons locker."},
        },
        intercept_chance = 0.55,
    },
}

-- ---------------------------------------------------------------------------
-- Boarding archetypes
-- Player must disable a target ship (beam weapons, impulse system targeted)
-- then dock with it to recover cargo or a person.
-- Interception fires after the disable (player is heading back with the asset).
-- ---------------------------------------------------------------------------

local _BOARDING_ARCHETYPES = {
    {
        cargo  = "a stolen data core",
        short_offer = "Disable a Corsair runner",
        lore   = "A Corsair runner lifted survey data from a prospecting team. The owner wants it back quietly.",
        accept_msg = '"Disable the ship and take back the core. Don\'t destroy it — the data might not survive the hull breach."',
        recv_msg   = '"Data core intact. You\'ve got a friend in this business."',
        reward_mult = 1.2, tier_min = 0,
        intercept_types = {}, intercept_chance = 0,
    },
    {
        cargo  = "a hijacked courier",
        short_offer = "Board a captured courier",
        lore   = "An independent courier was pulled off their route — ship taken, crew stuck aboard. Someone wants them back.",
        accept_msg = '"They\'re still alive. Disable the ship and get them out before the Corsairs move them again."',
        recv_msg   = '"I thought that was it for me. Thank you."',
        reward_mult = 1.4, tier_min = 0,
        intercept_types = {
            {type="pirates", strength="scout", weight=2,
             msg="Corsair support ship is responding. They don't want to lose their prize."},
        },
        intercept_chance = 0.25,
    },
    {
        cargo  = "a locked evidence container",
        short_offer = "Intercept a smuggling run",
        lore   = "Smuggler running contraband for a connected outfit. Concord wants the evidence container — not the ship, not the crew.",
        accept_msg = '"Disable them cleanly. Destroy the ship and the evidence chain breaks."',
        recv_msg   = '"Chain of custody intact. Well done."',
        reward_mult = 1.1, tier_min = 1,
        intercept_types = {
            {type="pirates", strength="scout", weight=2,
             msg="Second ship just altered course toward you. Someone tipped off the outfit."},
        },
        intercept_chance = 0.30,
    },
    {
        cargo  = "a Corsair lieutenant",
        short_offer = "Capture a Corsair officer",
        lore   = "Mid-level Corsair officer moving between cells. Intelligence wants them alive for questioning.",
        accept_msg = '"Disable the escort — they\'ll be running a light ship, fast. Board carefully."',
        recv_msg   = '"We\'ll take custody from here. What they know is worth more than you\'d guess."',
        reward_mult = 1.5, tier_min = 1,
        intercept_types = {
            {type="pirates", strength="light", weight=3,
             msg="Two Corsair ships just lit up on sensors. Responding to the escort's distress call."},
        },
        intercept_chance = 0.45,
    },
    {
        cargo  = "a corporate defector",
        short_offer = "Stop a fleeing operative",
        lore   = "A corporate operative who knows too much tried to disappear. The parent company wants them back with the financial records intact.",
        accept_msg = '"Disable the ship before they can vent the data. Board fast."',
        recv_msg   = '"Asset secured and records intact. Discretion noted."',
        reward_mult = 1.6, tier_min = 2,
        intercept_types = {
            {type="rival", strength="medium", weight=3,
             msg="Corporate security ship on an intercept heading. They have the same contract."},
        },
        intercept_chance = 0.50,
    },
}

-- Target ship templates by tier (light → heavy)
local _BOARDING_TEMPLATES = {
    [0] = {"Adder MK5", "MT52 Hornet"},
    [1] = {"Phobos T3", "Adder MK5"},
    [2] = {"Phobos M3P", "Phobos T3"},
}

-- ---------------------------------------------------------------------------
-- Hacking archetypes  (Relay station cracks a stationary buoy's reactor)
-- Extra field: system — which ship system to hack (always "reactor" for now)
-- ---------------------------------------------------------------------------

local _HACKING_ARCHETYPES = {
    {
        cargo       = "an encrypted nav log",
        short_offer = "Hack a relay for nav logs",
        lore        = "Someone has been running routes they don't want on record. The log lives in a relay buoy.",
        accept_msg  = '"Get Relay in position and crack it before anyone notices the uplink."',
        recv_msg    = '"Routes confirmed. This is exactly what we needed."',
        system      = "reactor", reward_mult = 1.0, tier_min = 0,
        intercept_types = {}, intercept_chance = 0,
    },
    {
        cargo       = "a comms archive",
        short_offer = "Extract comms from a dark relay",
        lore        = "Months of unencrypted traffic between two stations — someone paid to keep this relay dark from Concord.",
        accept_msg  = '"Pull the archive intact. Partial data is worthless to us."',
        recv_msg    = '"Everything\'s here. Good clean extraction."',
        system      = "reactor", reward_mult = 1.0, tier_min = 0,
        intercept_types = {
            {type="rival", strength="scout", weight=2,
             msg="Courier on intercept heading — someone else wants that archive."},
        },
        intercept_chance = 0.20,
    },
    {
        cargo       = "a contraband manifest",
        short_offer = "Crack a smuggler's relay cache",
        lore        = "A smuggling outfit uses relay buoys to cache their cargo schedules. Concord wants the manifest.",
        accept_msg  = '"Crack it quietly. If they notice the uplink they\'ll wipe the buffer."',
        recv_msg    = '"Manifest intact. Half a dozen ships just had a very bad week."',
        system      = "reactor", reward_mult = 1.1, tier_min = 0,
        intercept_types = {
            {type="pirates", strength="scout", weight=3,
             msg="Two contacts breaking off a nearby lane. They're watching this relay."},
        },
        intercept_chance = 0.30,
    },
    {
        cargo       = "docking access codes",
        short_offer = "Pull codes from a relay buffer",
        lore        = "Station authority codes rotate weekly but the old set sits in a relay buffer. Someone needs a back door.",
        accept_msg  = '"In and out before the rotation. You have a narrow window."',
        recv_msg    = '"Codes are live. We\'ll use them once — don\'t ask what for."',
        system      = "reactor", reward_mult = 1.3, tier_min = 1,
        intercept_types = {
            {type="concord", strength="scout", weight=2,
             msg="Concord patrol just changed heading. They may have flagged the uplink attempt."},
        },
        intercept_chance = 0.35,
    },
    {
        cargo       = "a black ledger fragment",
        short_offer = "Break into a hardened relay",
        lore        = "Corporate financial records split across relay nodes throughout the Drift. One fragment is enough to bring down a board.",
        accept_msg  = '"This relay is hardened. It will resist. Don\'t stop until you\'re through."',
        recv_msg    = '"Fragment verified. You just changed some very powerful people\'s plans."',
        system      = "reactor", reward_mult = 1.5, tier_min = 2,
        intercept_types = {
            {type="rival", strength="medium", weight=3,
             msg="Corporate security responding. They know what you're pulling."},
        },
        intercept_chance = 0.50,
    },
}

-- Base reward by tier (rounded to nearest 5 after all multipliers)
local _BASE_REWARD = {[0] = 70, [1] = 140, [2] = 230}

-- Mission type difficulty multipliers (delivery is baseline 1.0)
local _TYPE_MULT = {
    delivery = 1.0,
    salvage  = 1.2,
    hacking  = 1.4,
    destroy  = 1.6,
    boarding = 1.8,
}

-- Calculate final reward with distance and danger modifiers
local function _calcReward(base, type_mult, arch_mult, distance_u, danger_level)
    local reward = base * type_mult * arch_mult
    -- Distance bonus: +1% per U beyond 10U
    if distance_u and distance_u > 10000 then
        local extra_dist_u = (distance_u - 10000) / 1000
        reward = reward * (1.0 + extra_dist_u * 0.01)
    end
    -- Danger bonus: +15% per danger level
    if danger_level and danger_level > 0 then
        reward = reward * (1.0 + danger_level * 0.15)
    end
    return math.floor(reward / 5 + 0.5) * 5  -- round to nearest 5
end

-- Returns the in-game sector label (e.g. "F5") matching the Relay map grid.
function MISSION.gridRef(wx, wy)
    return getSectorName(wx, wy)
end

local _SHORT_NAMES = {
    ["Concord Station Arbiter"] = "C.S. Arbiter",
    ["Concord Waypoint Galen"]  = "Waypoint Galen",
    ["Saint Brennan's Mission"] = "St. Brennan's",
    ["Lastchance Outpost"]      = "Lastchance",
    ["Dustmote Salvage"]        = "Dustmote",
    ["Greywater Depot"]         = "Greywater",
}
local function _short(cs) return _SHORT_NAMES[cs] or cs end

local _id_seq = 0
local function _nextId()
    _id_seq = _id_seq + 1
    return "dm_" .. _id_seq
end

local function _weightedPick(list)
    local total = 0
    for _, e in ipairs(list) do total = total + (e.weight or 1) end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - (e.weight or 1)
        if r <= 0 then return e end
    end
    return list[#list]
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Generate a rich delivery mission record.
-- opts: {origin, dest, tier, reason_hint (optional — matches partial cargo name)}
function MISSION.newDelivery(opts)
    local tier = opts.tier or 0
    local pool = {}
    for _, a in ipairs(_ARCHETYPES) do
        if a.tier_min <= tier then
            if not opts.reason_hint or a.cargo:find(opts.reason_hint, 1, true) then
                pool[#pool + 1] = a
            end
        end
    end
    if #pool == 0 then
        for _, a in ipairs(_ARCHETYPES) do
            if a.tier_min <= tier then pool[#pool + 1] = a end
        end
    end
    if #pool == 0 then pool = _ARCHETYPES end

    local arch = pool[math.random(#pool)]
    local dest_short = _short(opts.dest)
    local reward = math.floor(_BASE_REWARD[tier] * (arch.reward_mult or 1) / 5 + 0.5) * 5

    -- Decide interception for this instance
    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = _weightedPick(arch.intercept_types)
        intercept = {
            itype    = ic.type,
            strength = ic.strength,
            -- trigger: fraction of route traveled before intercept fires (40–65%)
            trigger  = 0.40 + math.random() * 0.25,
            msg_log  = ic.msg,
            fired    = false,
        }
    end

    return {
        id           = _nextId(),
        type         = "delivery",
        tier         = tier,
        origin       = opts.origin,
        dest         = opts.dest,
        cargo        = arch.cargo,
        reward       = reward,
        short        = arch.cargo .. " → " .. dest_short .. " (delivery)",
        obj          = "Deliver to " .. dest_short,
        -- brief shown after accepting (lore + contact's words)
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        intercept    = intercept,
    }
end

-- Generate a salvage mission record.
-- opts: {origin, wx, wy, tier}
--   wx/wy — world-unit coordinates of the salvage site (set by the caller)
-- Interception fires on proximity when the site is reached (handled by scenario).
function MISSION.newSalvage(opts)
    local tier = opts.tier or 0
    local pool = {}
    for _, a in ipairs(_SALVAGE_ARCHETYPES) do
        if a.tier_min <= tier then pool[#pool + 1] = a end
    end
    if #pool == 0 then pool = _SALVAGE_ARCHETYPES end
    local arch   = pool[math.random(#pool)]

    -- Calculate distance and danger
    local distance_u = opts.distance_u or 0
    local danger_level = opts.danger_level or 0
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.salvage, arch.reward_mult or 1.0, distance_u, danger_level)

    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = _weightedPick(arch.intercept_types)
        intercept = {
            itype    = ic.type,
            strength = ic.strength,
            trigger  = 0,   -- fires on proximity, not route progress
            msg_log  = ic.msg,
            fired    = false,
        }
    end

    return {
        id           = _nextId(),
        type         = "salvage",
        tier         = tier,
        origin       = opts.origin,
        wx           = opts.wx,
        wy           = opts.wy,
        cargo        = arch.cargo,
        reward       = reward,
        short        = arch.cargo .. " (salvage)",
        obj          = "Recover " .. arch.cargo,
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        intercept    = intercept,
        _found       = false,
    }
end

-- Generate a boarding mission record.
-- opts: {origin, wx, wy, tier}
--   wx/wy — world-unit coordinates where the target ship patrols
-- The scenario spawns the target on accept and tracks disable/board phases.
function MISSION.newBoarding(opts)
    local tier = opts.tier or 0
    local pool = {}
    for _, a in ipairs(_BOARDING_ARCHETYPES) do
        if a.tier_min <= tier then pool[#pool + 1] = a end
    end
    if #pool == 0 then pool = _BOARDING_ARCHETYPES end
    local arch = pool[math.random(#pool)]
    local reward = math.floor(_BASE_REWARD[tier] * (arch.reward_mult or 1) / 5 + 0.5) * 5

    local templates = _BOARDING_TEMPLATES[tier] or _BOARDING_TEMPLATES[0]
    local target_template = templates[math.random(#templates)]

    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = _weightedPick(arch.intercept_types)
        intercept = {
            itype    = ic.type,
            strength = ic.strength,
            trigger  = 0,   -- fires after boarding (on return leg)
            msg_log  = ic.msg,
            fired    = false,
        }
    end

    return {
        id              = _nextId(),
        type            = "boarding",
        tier            = tier,
        origin          = opts.origin,
        wx              = opts.wx,
        wy              = opts.wy,
        cargo           = arch.cargo,
        reward          = reward,
        short           = arch.short_offer .. " (boarding)",
        obj             = "Locate and disable target",
        brief           = arch.lore .. "\n\n" .. arch.accept_msg
                          .. "\n\nTarget propulsion with beam weapons (Weapons station → system target: impulse) to disable without destroying.",
        complete_msg    = arch.recv_msg,
        target_template = target_template,
        intercept       = intercept,
        _spawned        = false,
        _disabled       = false,
        _boarded        = false,
        target_cs       = nil,
    }
end

-- Generate a destroy mission record.
-- opts: {origin, wx, wy, tier, nearby_stations}
--   wx/wy — world-unit coordinates where the target ship patrols
-- The scenario spawns the target on accept and tracks destroy phase.
function MISSION.newDestroy(opts)
    local tier = opts.tier or 0
    local pool = {}
    for _, a in ipairs(_DESTROY_ARCHETYPES) do
        if a.tier_min <= tier then pool[#pool + 1] = a end
    end
    if #pool == 0 then pool = _DESTROY_ARCHETYPES end
    local arch   = pool[math.random(#pool)]

    -- Calculate distance and danger
    local distance_u = opts.distance_u or 0
    local danger_level = opts.danger_level or 0
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.destroy, arch.reward_mult or 1.0, distance_u, danger_level)

    -- Pick destination station for target
    local target_dest = nil
    if opts.nearby_stations and #opts.nearby_stations > 0 then
        target_dest = opts.nearby_stations[math.random(#opts.nearby_stations)]
    end

    -- Intercept fires when target is destroyed (handled by scenario)
    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = _weightedPick(arch.intercept_types)
        intercept = {
            itype    = ic.type,
            strength = ic.strength,
            trigger  = 0,  -- fires on approach, not route progress
            msg_log  = ic.msg,
            fired    = false,
        }
    end

    return {
        id              = _nextId(),
        type            = "destroy",
        tier            = tier,
        origin          = opts.origin,
        wx              = opts.wx,
        wy              = opts.wy,
        cargo           = arch.cargo,
        reward          = reward,
        short           = arch.short_offer .. " (destroy)",
        obj             = "Locate and destroy target",
        brief           = arch.lore .. "\n\n" .. arch.accept_msg
                          .. "\n\nTarget must be completely destroyed. No boarding, no salvage.",
        complete_msg    = arch.rev_msg,
        target_template = arch.target_template,
        target_dest     = target_dest,
        intercept       = intercept,
        _spawned        = false,
        _destroyed      = false,
        target_cs       = nil,
    }
end

-- Generate a hacking mission record.
-- opts: {origin, wx, wy, tier}
--   wx/wy — world-unit coordinates where the relay buoy will be spawned
function MISSION.newHacking(opts)
    local tier = opts.tier or 0
    local pool = {}
    for _, a in ipairs(_HACKING_ARCHETYPES) do
        if a.tier_min <= tier then pool[#pool + 1] = a end
    end
    if #pool == 0 then pool = _HACKING_ARCHETYPES end
    local arch   = pool[math.random(#pool)]

    -- Calculate distance and danger
    local distance_u = opts.distance_u or 0
    local danger_level = opts.danger_level or 0
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.hacking, arch.reward_mult or 1.0, distance_u, danger_level)

    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = _weightedPick(arch.intercept_types)
        intercept = {
            itype    = ic.type,
            strength = ic.strength,
            trigger  = 0,   -- fires on return leg after hack completes
            msg_log  = ic.msg,
            fired    = false,
        }
    end

    return {
        id             = _nextId(),
        type           = "hacking",
        tier           = tier,
        origin         = opts.origin,
        wx             = opts.wx,
        wy             = opts.wy,
        cargo          = arch.cargo,
        system         = arch.system or "reactor",
        hack_threshold = 0.75,
        reward         = reward,
        short          = arch.short_offer .. " (hacking)",
        obj            = "Hack relay near " .. opts.origin,
        brief          = arch.lore .. "\n\n" .. arch.accept_msg
                         .. "\n\nHack any of the relay's systems to 75% to breach its datastore.",
        complete_msg   = arch.recv_msg,
        intercept      = intercept,
        _spawned       = false,
        _hacked        = false,
        target_cs      = nil,
    }
end

-- Register a delivery mission for route interception monitoring.
-- Call when the player accepts the mission.
function MISSION.track(m)
    if not m.intercept then return end
    local os = RT.find(m.origin)
    local ds = RT.find(m.dest)
    if not RT.valid(os) or not RT.valid(ds) then return end
    local ox, oy = os:getPosition()
    local dx, dy = ds:getPosition()
    local ddx, ddy = dx - ox, dy - oy
    local dist = math.sqrt(ddx * ddx + ddy * ddy)
    if dist < 5000 then return end   -- route too short to bother
    m._ox, m._oy = ox, oy
    m._dx, m._dy = dx, dy
    m._dist      = dist
    MISSION._tracked[m.id] = m
end

-- Remove a mission from route monitoring (on delivery or failure).
function MISSION.untrack(mission_id)
    MISSION._tracked[mission_id] = nil
end

-- Call from scenario update(delta).
function MISSION.update(delta)
    local now = getScenarioTime()
    if now < MISSION._next_check then return end
    MISSION._next_check = now + MISSION._check_interval
    if not RT.anyPlayerAlive() then return end
    for _, m in pairs(MISSION._tracked) do
        local ic = m.intercept
        if ic and not ic.fired and m._dist then
            -- Trigger when ANY player has traveled far enough along the route.
            for _, p in ipairs(RT.players) do
                if RT.valid(p) then
                    local px, py = p:getPosition()
                    local tdx, tdy = m._dx - px, m._dy - py
                    local dist_to_dest = math.sqrt(tdx * tdx + tdy * tdy)
                    local progress = 1 - dist_to_dest / m._dist
                    if progress >= ic.trigger then
                        ic.fired = true
                        MISSION._spawnIntercept(m, px, py)
                        break
                    end
                end
            end
        end
    end
end

-- Spawn an interception group.  Called internally when route trigger fires.
function MISSION._spawnIntercept(m, px, py)
    local ic = m.intercept
    local templates = DIR.GROUPS[ic.strength]
    if not templates then return end

    -- Aim spawn 12u ahead toward destination
    local dx, dy = m._dx - px, m._dy - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then dx, dy = dx / len, dy / len else dx, dy = 1, 0 end
    local sx, sy = px + dx * 12000, py + dy * 12000

    local faction   = "Corsairs"
    local comms_msg = '"Hand over the cargo and you can go."'
    if ic.itype == "rival" then
        comms_msg = '"That contract should\'ve been ours. Hand over the cargo."'
    elseif ic.itype == "concord" then
        faction   = "Concord"
        comms_msg = '"Independent vessel, this is a Concord inspection. Heave to."'
    end

    -- Spawn 2-3 ships instead of full group (early-game balance)
    local spawn_count = math.min(#templates, math.random(2, 3))
    local names = {}
    for i = 1, spawn_count do
        local tmpl = templates[math.min(i, #templates)]
        local s = CpuShip():setTemplate(tmpl):setFaction(faction)
        s:setPosition(sx + random(-800, 800), sy + random(-800, 800))
        RT.register(s)
        DIR.registerKill(s)
        DIR.allowControl(s)
        local msg = comms_msg
        s:setCommsFunction(function(src, tgt) setCommsMessage(msg) end)
        table.insert(names, s:getCallSign())
    end

    RT.shipLog("[Route] " .. ic.msg_log .. " — " .. table.concat(names, ", ")
        .. " at grid " .. MISSION.gridRef(sx, sy) .. ".", "#FF8080")

    -- Concord patrols (don't immediately attack); pirates and rivals attack on sight
    DIR.orderGroup(names, ic.itype == "concord" and "patrol" or "attack")

    DIR.emit("mission_intercept", {
        mission_id = m.id,
        cargo      = m.cargo,
        itype      = ic.itype,
        strength   = ic.strength,
    }, "normal")
end
