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

-- Base reward by tier (rounded to nearest 5 after archetype multiplier)
local _BASE_REWARD = {[0] = 70, [1] = 140, [2] = 230}

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
        short        = arch.cargo .. " → " .. dest_short,
        obj          = "Deliver to " .. dest_short,
        -- brief shown after accepting (lore + contact's words)
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        intercept    = intercept,
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
    if not RT.valid(RT.player) then return end
    local px, py = RT.player:getPosition()
    for _, m in pairs(MISSION._tracked) do
        local ic = m.intercept
        if ic and not ic.fired and m._dist then
            local tdx, tdy = m._dx - px, m._dy - py
            local dist_to_dest = math.sqrt(tdx * tdx + tdy * tdy)
            local progress = 1 - dist_to_dest / m._dist
            if progress >= ic.trigger then
                ic.fired = true
                MISSION._spawnIntercept(m, px, py)
            end
        end
    end
end

-- Spawn an interception group.  Called internally when route trigger fires.
function MISSION._spawnIntercept(m, px, py)
    local ic = m.intercept
    RT.player:addToShipLog("[Route] " .. ic.msg_log, "#FF8080")

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

    local names = {}
    for _, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction(faction)
        s:setPosition(sx + random(-800, 800), sy + random(-800, 800))
        RT.register(s)
        DIR.registerKill(s)
        DIR.allowControl(s)
        local msg = comms_msg
        s:setCommsFunction(function(src, tgt) setCommsMessage(msg) end)
        table.insert(names, s:getCallSign())
    end

    -- Concord patrols (don't immediately attack); pirates and rivals attack on sight
    DIR.orderGroup(names, ic.itype == "concord" and "patrol" or "attack")

    DIR.emit("mission_intercept", {
        mission_id = m.id,
        cargo      = m.cargo,
        itype      = ic.itype,
        strength   = ic.strength,
    }, "normal")
end
