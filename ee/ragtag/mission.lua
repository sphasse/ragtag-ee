-- ee/ragtag/mission.lua
-- Mission generation for delivery, salvage, boarding, hacking, and destroy contracts.
--
-- Usage in a scenario:
--   require("ragtag/mission.lua")   -- after director.lua
--   -- (no init needed — uses DIR/RT globals directly)
--
-- Director action create_delivery pushes missions into MISSION._dynamic_queue.
-- The scenario's job board should check and drain that queue.

MISSION = MISSION or {}

MISSION._tracked        = {}   -- kept for backward-compat with MISSION.untrack calls
MISSION._dynamic_queue  = {}   -- missions injected by create_delivery action

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
-- Destroy archetypes (eliminate target completely, no boarding)
-- Extra field: target_template — which ship template to spawn
-- ---------------------------------------------------------------------------

local _DESTROY_ARCHETYPES = {
    {
        cargo  = "a bounty claim",
        short_offer = "Eliminate a wanted fugitive",
        lore   = "A wanted corsair with a dead-or-alive bounty. Last seen operating a fast raider.",
        accept_msg = '"Destroy the target completely. No boarding, no survivors. We want proof."',
        recv_msg   = '"Target eliminated. Bounty posted to your account."',
        target_template = "MT52 Hornet",
        reward_mult = 1.0, tier_min = 0,
        intercept_types = {}, intercept_chance = 0,
    },
    {
        cargo  = "proof of destruction",
        short_offer = "Destroy a rogue AI ship",
        lore   = "An automated patrol ship malfunctioned and is broadcasting corrupted IFF codes. It's firing on friendlies.",
        accept_msg = '"Eliminate the target. Do not attempt boarding — the AI is hostile to all organics."',
        recv_msg   = '"Threat neutralized. Wreckage retrieved for analysis."',
        target_template = "Adder MK5",
        reward_mult = 1.1, tier_min = 0,
        intercept_types = {
            {type="rival", strength="scout", weight=2,
             msg="Another ship on intercept. Someone else wants that bounty."},
        },
        intercept_chance = 0.25,
    },
    {
        cargo  = "a quarantine certificate",
        short_offer = "Destroy a plague ship",
        lore   = "A freighter carrying an unstable bioweapon sample lost containment. The crew is dead or worse.",
        accept_msg = '"Burn it out of space. Do not approach within 1U. Do not board. Complete destruction only."',
        recv_msg   = '"Contaminated hulk destroyed. Medical authority confirms clean burn."',
        target_template = "Flavia P.Falcon",
        reward_mult = 1.2, tier_min = 1,
        intercept_types = {
            {type="rival", strength="scout", weight=2,
             msg="Courier inbound — corporate wants to recover the sample before you burn it."},
        },
        intercept_chance = 0.30,
    },
    {
        cargo  = "combat telemetry",
        short_offer = "Eliminate a pirate captain",
        lore   = "A corsair captain with fifteen raids to their name. Known for heavy armor and refusing surrender.",
        accept_msg = '"No quarter. This one doesn\'t run and doesn\'t dock quietly."',
        recv_msg   = '"Captain confirmed KIA. The lanes just got safer."',
        target_template = "Phobos T3",
        reward_mult = 1.3, tier_min = 1,
        intercept_types = {
            {type="pirates", strength="medium", weight=3,
             msg="Corsair reinforcements breaking off nearby patrol. They're coming for you."},
        },
        intercept_chance = 0.40,
    },
    {
        cargo  = "a black-ops confirmation",
        short_offer = "Destroy a defector's ship",
        lore   = "A former Concord officer stole classified files and is running for Hollow space. Eliminate before they cross the line.",
        accept_msg = '"Target is armed, experienced, and knows you\'re coming. Total destruction. No witnesses."',
        recv_msg   = '"Target eliminated. Files unrecoverable. This conversation never happened."',
        target_template = "Phobos M3P",
        reward_mult = 1.5, tier_min = 2,
        intercept_types = {
            {type="concord", strength="medium", weight=2,
             msg="Concord patrol responding. Official story is they're here to help. Don't believe it."},
            {type="rival", strength="heavy", weight=1,
             msg="Heavy contact inbound — Hollow interceptor. They want the defector alive."},
        },
        intercept_chance = 0.50,
    },
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
local _BASE_REWARD = {[0] = 50, [1] = 75, [2] = 100}

-- Mission type difficulty multipliers (delivery is baseline 1.0)
local _TYPE_MULT = {
    delivery = 1.0,
    salvage  = 1.2,
    hacking  = 1.4,
    tailing  = 1.4,
    destroy  = 1.6,
    boarding = 1.8,
}

-- Calculate final reward with distance and danger modifiers
-- distance_min_u, distance_max_u: range for scaling distance bonus from 0% to 30%
local function _calcReward(base, type_mult, arch_mult, distance_u, danger_level, distance_min_u, distance_max_u)
    local reward = base * type_mult * arch_mult
    -- Distance bonus: 0-30% scaled linearly across the distance range
    if distance_u and distance_min_u and distance_max_u and distance_max_u > distance_min_u then
        local dist_pct = (distance_u - distance_min_u) / (distance_max_u - distance_min_u)
        dist_pct = math.max(0, math.min(1, dist_pct))  -- clamp to 0-1
        reward = reward * (1.0 + dist_pct * 0.30)  -- 0% to 30% bonus
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

-- Format distance/reward suffix for mission short descriptions
-- e.g. " (the Shroud, 45u) (185cr)"
local function _distReward(distance_u, reward, region_name)
    local dist_rounded = math.floor((distance_u / 1000 + 2.5) / 5) * 5
    if region_name then
        return string.format(" (%s, %du) (%dcr)", region_name, dist_rounded, reward)
    end
    return string.format(" (%du) (%dcr)", dist_rounded, reward)
end

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
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.delivery, arch.reward_mult or 1.0, opts.distance_u, opts.danger_level, opts.distance_min_u, opts.distance_max_u)

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
        short        = arch.cargo .. " → " .. dest_short .. " (delivery)" .. _distReward(opts.distance_u or 0, reward, opts.region_name),
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
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.salvage, arch.reward_mult or 1.0, distance_u, danger_level, opts.distance_min_u, opts.distance_max_u)

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
        short        = arch.cargo .. " (salvage)" .. _distReward(opts.distance_u or 0, reward, opts.region_name),
        obj          = "Recover " .. arch.cargo,
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        intercept    = intercept,
        _found       = false,
    }
end

-- Generate a boarding mission record.
-- opts: {origin, wx, wy, tier, nearby_stations, distance_u, danger_level}
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

    -- Calculate distance and danger
    local distance_u = opts.distance_u or 0
    local danger_level = opts.danger_level or 0
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.boarding, arch.reward_mult or 1.0, distance_u, danger_level, opts.distance_min_u, opts.distance_max_u)

    local templates = _BOARDING_TEMPLATES[tier] or _BOARDING_TEMPLATES[0]
    local target_template = templates[math.random(#templates)]

    -- Pick destination station for target
    local target_dest = nil
    if opts.nearby_stations and #opts.nearby_stations > 0 then
        target_dest = opts.nearby_stations[math.random(#opts.nearby_stations)]
    end

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
        short           = arch.short_offer .. " (boarding)" .. _distReward(opts.distance_u or 0, reward, opts.region_name),
        obj             = "Locate and disable target",
        brief           = arch.lore .. "\n\n" .. arch.accept_msg
                          .. "\n\nTarget propulsion with beam weapons (Weapons station → system target: impulse) to disable without destroying.",
        complete_msg    = arch.recv_msg,
        target_template = target_template,
        target_dest     = target_dest,
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
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.destroy, arch.reward_mult or 1.0, distance_u, danger_level, opts.distance_min_u, opts.distance_max_u)

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
        short           = arch.short_offer .. " (destroy)" .. _distReward(opts.distance_u or 0, reward, opts.region_name),
        obj             = "Locate and destroy target",
        brief           = arch.lore .. "\n\n" .. arch.accept_msg
                          .. "\n\nTarget must be completely destroyed. No boarding, no salvage.",
        complete_msg    = arch.recv_msg,
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
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.hacking, arch.reward_mult or 1.0, distance_u, danger_level, opts.distance_min_u, opts.distance_max_u)

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
        short          = arch.short_offer .. " (hacking)" .. _distReward(opts.distance_u or 0, reward, opts.region_name),
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

-- ---------------------------------------------------------------------------
-- Tailing archetypes  (Science-led surveillance — observe a covert meeting)
-- Target spawns as Unknown and flies toward a rendezvous point.
-- Mission completes when the player is within scan range when ships meet.
-- ---------------------------------------------------------------------------

local _TAILING_ARCHETYPES = {
    {
        cargo       = "traffic analysis",
        short_offer = "Surveil a suspected courier",
        lore        = "Someone is moving information through this sector on an irregular route. We need to know who they're meeting.",
        accept_msg  = '"Locate the ship and shadow it to the meeting. Stay back — they\'re watching for tails."',
        recv_msg    = '"Contact identified. This is more than we hoped for."',
        reward_mult = 1.0, tier_min = 0,
    },
    {
        cargo       = "a contact identification",
        short_offer = "Identify a meeting contact",
        lore        = "A ship operating without a registered route has been spotted twice. Someone is meeting it out here.",
        accept_msg  = '"Get close enough when it meets its contact. We\'ll need the scan data. Don\'t spook it early."',
        recv_msg    = '"Got the ID. You\'ve answered a question we\'ve been asking for months."',
        reward_mult = 1.0, tier_min = 0,
    },
    {
        cargo       = "rendezvous confirmation",
        short_offer = "Confirm a covert rendezvous",
        lore        = "Intelligence points to a handoff happening in deep space. We need confirmation — no intercept, just eyes on.",
        accept_msg  = '"Stay back until the meeting starts, then close for a scan. Keep your probes stowed."',
        recv_msg    = '"Confirmed. This closes the loop on a three-month investigation."',
        reward_mult = 1.1, tier_min = 1,
    },
    {
        cargo       = "a defector sighting",
        short_offer = "Locate a missing operative",
        lore        = "A former Concord analyst went dark six weeks ago. Last known heading puts them somewhere in this sector.",
        accept_msg  = '"Find their ship and scan it during the meeting — we need both names. Don\'t approach early or they\'ll run."',
        recv_msg    = '"Both names confirmed. This is sensitive — we\'ll handle it from here."',
        reward_mult = 1.3, tier_min = 1,
    },
    {
        cargo       = "supply chain evidence",
        short_offer = "Trace a contraband supply run",
        lore        = "Someone is running contraband through unregistered drops. We\'ve traced the route to this sector.",
        accept_msg  = '"Shadow the courier to the drop and scan the receiving ship. That\'s all we need. Silent approach."',
        recv_msg    = '"Supply chain mapped. This reaches further up than we thought."',
        reward_mult = 1.4, tier_min = 2,
    },
}

local _TAILING_TEMPLATES = {
    [0] = {"Flavia P.Falcon"},
    [1] = {"Flavia P.Falcon", "Phobos T3"},
    [2] = {"Phobos T3", "Phobos M3P"},
}

-- Generate a tailing mission record.
-- opts: {origin, wx, wy, mx, my, tier, distance_u, danger_level}
--   wx/wy — target spawn position
--   mx/my — meeting point (pre-calculated by the scenario)
function MISSION.newTailing(opts)
    local tier = opts.tier or 0
    local pool = {}
    for _, a in ipairs(_TAILING_ARCHETYPES) do
        if a.tier_min <= tier then pool[#pool + 1] = a end
    end
    if #pool == 0 then pool = _TAILING_ARCHETYPES end
    local arch = pool[math.random(#pool)]

    local distance_u   = opts.distance_u   or 0
    local danger_level = opts.danger_level or 0
    local reward = _calcReward(_BASE_REWARD[tier], _TYPE_MULT.tailing, arch.reward_mult or 1.0,
        distance_u, danger_level, opts.distance_min_u, opts.distance_max_u)

    local templates = _TAILING_TEMPLATES[tier] or _TAILING_TEMPLATES[0]
    local target_template = templates[math.random(#templates)]

    return {
        id               = _nextId(),
        type             = "tailing",
        tier             = tier,
        origin           = opts.origin,
        wx               = opts.wx,
        wy               = opts.wy,
        mx               = opts.mx,      -- meeting point
        my               = opts.my,
        cargo            = arch.cargo,
        reward           = reward,
        short            = arch.short_offer .. " (tailing)" .. _distReward(distance_u, reward, opts.region_name),
        obj              = "Locate target",
        brief            = arch.lore .. "\n\n" .. arch.accept_msg
                           .. "\n\nThey'll detect a probe signature or any ship within weapons range — spook them before the meeting and the contract is lost.",
        complete_msg     = arch.recv_msg,
        target_template  = target_template,
        _spawned         = false,
        _meeting         = false,
        _meeting_at      = nil,
        _scanned         = false,
        target_cs        = nil,
        rendezvous_cs    = nil,
    }
end

-- No-op stub kept for call sites that haven't been updated.
function MISSION.untrack(mission_id)
    MISSION._tracked[mission_id] = nil
end
