-- create_delivery: Push a rich delivery job to a station's job board.
-- args: origin, dest, tier (0/1/2), reason_hint (optional cargo keyword)
--
-- Generates a job record with narrative lore, reward, and a probabilistic
-- route interception, then queues it in JOBS._dynamic_queue.
-- The jobs engine drains that queue into the station panel on next refresh.

-- Delivery archetypes used by this action (separate from jobs/delivery.lua).
local _ARCHETYPES = {
    {
        cargo = "medical supplies",
        lore  = "The destination station is short-staffed and someone isn't doing well.",
        accept_msg = '"Move fast. People are waiting on the other end."',
        recv_msg   = '"You got here in time. Thank you."',
        urgent = true,  reward_mult = 1.1, tier_min = 0,
        intercept_types = {}, intercept_chance = 0,
    },
    {
        cargo = "a locked strongbox",
        lore  = "Someone is moving their savings to a safer port. Don't ask how much is inside.",
        accept_msg = '"Don\'t lose it. Don\'t open it. Please."',
        recv_msg   = '"I thought I\'d never see this again."',
        urgent = false, reward_mult = 0.9, tier_min = 0,
        intercept_types = {
            {type="pirates", strength="scout", weight=3,
             msg="Two contacts on an intercept heading. They know what you're carrying."},
        },
        intercept_chance = 0.25,
    },
    {
        cargo = "survey data cores",
        lore  = "Fresh scan data from a prospecting run. A rival outfit would pay well for it.",
        accept_msg = '"Bonded delivery. No stops, no detours."',
        recv_msg   = '"Ahead of schedule. Appreciated."',
        urgent = false, reward_mult = 1.0, tier_min = 0,
        intercept_types = {
            {type="rival", strength="scout", weight=3,
             msg="A courier just lit off after you. They want that data off your ship."},
        },
        intercept_chance = 0.30,
    },
    {
        cargo = "emergency equipment",
        lore  = "Beacon relay parts for an outpost that went dark. No backup comms until you deliver.",
        accept_msg = '"Someone out there is waiting to call for help. Move."',
        recv_msg   = '"We\'re back online. You have no idea what that means to us."',
        urgent = true,  reward_mult = 1.0, tier_min = 0,
        intercept_types = {}, intercept_chance = 0,
    },
    {
        cargo = "a sealed crate",
        lore  = "They said don't ask. The pay says don't argue.",
        accept_msg = '"You didn\'t see this. We never spoke."',
        recv_msg   = '"Quiet and fast. Just how we like it."',
        urgent = false, reward_mult = 1.5, tier_min = 1,
        intercept_types = {
            {type="pirates",  strength="light", weight=2,
             msg="Three ships on intercept. Word got out you're carrying something valuable."},
            {type="concord",  strength="light", weight=2,
             msg="Concord inspection frigate blocking the lane. Could be a tip-off, could be routine."},
        },
        intercept_chance = 0.60,
    },
    {
        cargo = "sealed documents",
        lore  = "Corporate courier contract. The paperwork is above your clearance level.",
        accept_msg = '"Deliver to the named recipient only. Do not break the seal."',
        recv_msg   = '"Intact and on time. Your bond is cleared."',
        urgent = false, reward_mult = 1.2, tier_min = 1,
        intercept_types = {
            {type="rival", strength="light", weight=3,
             msg="Corporate security ship -- not Concord. Someone doesn't want those documents to arrive."},
        },
        intercept_chance = 0.45,
    },
    {
        cargo = "crated ordnance",
        lore  = "Licensed arms transfer, cleared manifest. Concord will still want to look.",
        accept_msg = '"Everything is above board. Mostly. Move fast."',
        recv_msg   = '"All present, no tamper seals broken. Good work."',
        urgent = false, reward_mult = 1.3, tier_min = 2,
        intercept_types = {
            {type="concord", strength="medium", weight=2,
             msg="Concord patrol moving to intercept. Arms manifests get extra scrutiny out here."},
            {type="pirates", strength="medium", weight=2,
             msg="Corsair raiders on an intercept vector. They're after what's in the crates."},
        },
        intercept_chance = 0.55,
    },
}

local _BASE_REWARD = {[0] = 50, [1] = 65, [2] = 80}
local _TYPE_MULT   = 1.0   -- delivery baseline

local function _makeDeliveryJob(opts)
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

    local arch   = pool[math.random(#pool)]
    local urgent = arch.urgent or false
    local reward = JOBS.calcReward(_BASE_REWARD[tier], _TYPE_MULT,
        opts.distance_u, opts.danger_level, opts.distance_min_u, opts.distance_max_u,
        urgent and 1.5 or 1.0)
    local dest_short = JOBS.shortName(opts.dest)
    local prefix = urgent and "URGENT: " or ""

    local intercept = nil
    if #arch.intercept_types > 0 and math.random() < (arch.intercept_chance or 0) then
        local ic = JOBS.weightedPick(arch.intercept_types)
        intercept = {
            itype    = ic.type,
            strength = ic.strength,
            trigger  = 0.40 + math.random() * 0.25,
            msg_log  = ic.msg,
            fired    = false,
        }
    end

    return {
        id           = JOBS.nextId(),
        type         = "delivery",
        tier         = tier,
        origin       = opts.origin,
        dest         = opts.dest,
        cargo        = arch.cargo,
        reward       = reward,
        short        = prefix .. arch.cargo .. " -> " .. dest_short,
        obj          = "Deliver to " .. dest_short,
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        intercept    = intercept,
        urgent       = urgent,
        distance_u   = opts.distance_u or 0,
        region_name  = opts.region_name,
        dest_faction = opts.dest_faction or "Independent",
    }
end

DIR.ACTIONS.create_delivery = function(a)
    local h = DIR._h
    local origin = h.str(a.origin, 40, nil)
    local dest   = h.str(a.dest,   40, nil)
    if not origin or origin == "" then return false, "origin required" end
    if not dest   or dest   == "" then return false, "dest required"   end

    local origin_e = RT.find(origin)
    local dest_e   = RT.find(dest)
    if not RT.valid(origin_e) then return false, "origin not found: " .. origin end
    if not RT.valid(dest_e)   then return false, "dest not found: "   .. dest   end

    local tier   = math.floor(math.max(0, math.min(2, h.num(a.tier, 0, 2, 0))))
    local reason = h.str(a.reason_hint, 40, nil)
    if reason == "" then reason = nil end

    local m = _makeDeliveryJob({
        origin      = origin,
        dest        = dest,
        tier        = tier,
        reason_hint = reason,
    })

    table.insert(JOBS._dynamic_queue, m)

    RT.shipLog("[Board] New job posted at " .. origin .. ": " .. m.short
        .. " (" .. m.reward .. " cr).", "#A0C0FF")

    DIR.emit("delivery_posted", {
        origin        = origin,
        dest          = dest,
        cargo         = m.cargo,
        reward        = m.reward,
        tier          = tier,
        has_intercept = m.intercept ~= nil and 1 or 0,
    }, "normal")

    return true, string.format("delivery posted at %s -> %s (%s, %d cr, tier %d)",
        origin, dest, m.cargo, m.reward, tier)
end
