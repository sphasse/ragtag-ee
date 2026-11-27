-- ee/ragtag/world/pit.lua
-- The Pit: an unsanctioned fighting ring south of the Deep Shroud (the station and region are the
-- universe extension verse/extensions/the_pit.lua). A ring of dense asteroids, 15U across, with one
-- opening on the west side, by the pit boss's station.
--
-- A bout, for one ship at a time (tier 2 and up: JOBS.maxTier):
--   1. Relay talks to the pit boss (the station's comms) and picks one of three opponents: easy, a good
--      match or hard (MATCH.offer, from the Drift's own enemy types). The purse grows with how tough
--      the opponents are. The rules are read out before signing.
--   2. The opponents spawn across the ring from the opening, hostile from the start, holding their
--      ground (they never chase out of the ring). The crew has PIT.COUNTDOWN seconds to get inside.
--      Scanning in the meantime is fine.
--   3. Once the crew is in, the opponents attack. The crew wins when every opponent is destroyed, or
--      when any opponent leaves the ring (it stands down at once). The crew loses if it doesn't get in
--      in time, leaves the ring, yields (to the pit boss) or is destroyed.
--   Nothing that dies in the ring costs standing (the opponents fly for PIT.FACTION, which has none).
--   The winner is paid the purse. Every bout is recorded in the fight log (BOUT, source "pit").
-- Rumors point crews at it, roughly. Test: tests/world/pit.lua.

require("ragtag/bout.lua")
require("ragtag/match.lua")

PIT = PIT or {}
local U = 1000

PIT.REGION      = "the Pit"
PIT.STATION     = "The Pit"
PIT.FACTION     = "Pit Fighters"
PIT.RING_R      = 7.5        -- U: the middle of the asteroid band
PIT.BAND_U      = 0.45       -- U: half the band's width
PIT.ASTEROIDS   = 170        -- dense: a ship that crosses the band hits rock (each one blows for 35)
PIT.OPEN_ANGLE  = 270        -- degrees, 0 = up, clockwise: the opening faces west, towards the station
PIT.OPEN_WIDTH  = 28         -- degrees (about 3.7U of the band)
PIT.INSIDE_U    = 6.8        -- inside the ring: nearer the centre than this
PIT.OUTSIDE_U   = 8.6        -- out of the ring: further than this (the band itself is neither)
PIT.SPAWN_U     = 5          -- the opponents start this far out, across from the opening
PIT.COUNTDOWN   = 60         -- seconds to get inside after signing
PIT.SIGNUP_U    = 20         -- a crew signs up from within this distance of the ring's centre
PIT.COOLDOWN    = 120        -- seconds after a bout before the same ship may fight again
PIT.OFFER_SECS  = 300        -- an offer stands this long (asking again shows the same three)
PIT.MIN_TIER    = 2
-- The opponents: the Drift's own enemy types (Corsairs, Shroud Raiders, Relic drones, Concord).
PIT.TYPES = {"MT52 Hornet", "Adder MK5", "Adder MK8", "Piranha F12", "Phobos T3", "Phobos M3P", "Nirvana R5",
             "WX-Lindworm", "Stalker Q7", "Stalker R7", "Atlantis X23"}
-- The purse: PURSE_RATE x the opponents' threat (EHP + 30 x DPS, MATCH.typePower), times the slot's
-- premium for the risk, rounded to 25 and kept within PURSE_MIN..PURSE_MAX.
PIT.PURSE_RATE  = 0.5
PIT.PREMIUM     = {easy = 1.0, match = 1.15, hard = 1.35}
PIT.PURSE_MIN, PIT.PURSE_MAX = 100, 3000

PIT.RUMORS = {
    "There's money in fighting, if you've got the hull for it. Someone runs bouts south of the Deep Shroud. Purses paid in clean credits.",
    "A crew I know came back from the Pit with a thousand credits and half a ship. Somewhere below the Deep Shroud, they said. Not as far as the Maw.",
    "They call it the Pit. A ring of rock out past the Rim, south of the Shroud's deep end. You fight whoever the pit boss puts in front of you.",
    "Don't take a stock freighter to the Pit. The pit boss won't even talk to you until you've spent real money on that hull.",
}

local P = {id = "pit", name = "The Pit"}

-- The ring's centre: the region's (VERSE.at only knows stations and places, not regions).
function PIT.centre()
    if PIT._cx then return PIT._cx, PIT._cy end
    for _, r in ipairs(VERSE.REGIONS or {}) do
        if r.name == PIT.REGION then
            PIT._cx, PIT._cy = r.x * U, r.y * U
            return PIT._cx, PIT._cy
        end
    end
    error("the Pit: no region named " .. PIT.REGION)
end
local _centre = PIT.centre

local function _distU(e)
    local cx, cy = _centre()
    local x, y = e:getPosition()
    return math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / U
end

-- A point on the ring at `angle` (0 = up, clockwise) and `r_u` from the centre.
local function _at(angle, r_u)
    local cx, cy = _centre()
    local a = math.rad(angle)
    return cx + math.sin(a) * r_u * U, cy - math.cos(a) * r_u * U
end

local function _inOpening(angle)
    local d = math.abs(((angle - PIT.OPEN_ANGLE) + 180) % 360 - 180)
    return d <= PIT.OPEN_WIDTH / 2
end

function PIT.isInside(e) return RT.valid(e) and _distU(e) < PIT.INSIDE_U end
function PIT.isOutside(e) return (not RT.valid(e)) or _distU(e) > PIT.OUTSIDE_U end

-- ── The ring ─────────────────────────────────────────────────────────────────
-- Asteroids blow up when something hits them, so the ring wears down. Between bouts it is filled up
-- again to PIT.ASTEROIDS (never on top of a ship).
function PIT.fillRing(st)
    st.rocks = st.rocks or {}
    local kept = {}
    for _, a in ipairs(st.rocks) do if RT.valid(a) then kept[#kept + 1] = a end end
    st.rocks = kept
    local tries = 0
    while #st.rocks < PIT.ASTEROIDS and tries < PIT.ASTEROIDS * 4 do
        tries = tries + 1
        local angle = math.random() * 360
        if not _inOpening(angle) then
            local x, y = _at(angle, PIT.RING_R + (math.random() * 2 - 1) * PIT.BAND_U)
            local clear = true
            for _, o in ipairs(getObjectsInRadius(x, y, 400)) do
                if o.components and o.components.typename ~= nil then clear = false end   -- a ship or station
            end
            if clear then
                st.rocks[#st.rocks + 1] = Asteroid():setPosition(x, y):setSize(80 + math.random() * 140)
            end
        end
    end
    return #st.rocks
end

-- ── Factions and money ───────────────────────────────────────────────────────
local function _faction()
    local f = getFactionInfo(PIT.FACTION)
    if f == nil then
        f = FactionInfo():setName(PIT.FACTION):setLocaleName(PIT.FACTION)
        f:setGMColor(200, 70, 70)
        f:setDescription("Fighters booked by the Pit. Hostile in the ring, and only in the ring.")
    end
    local ind = getFactionInfo("Independent")
    if ind then f:setEnemy(ind) end
    return f
end

function PIT.purse(offer)
    local threat = 0
    for _, name in ipairs(offer.group) do
        local pw = MATCH.typePower(name)
        threat = threat + pw.ehp + 30 * pw.dps
    end
    local v = PIT.PURSE_RATE * threat * (PIT.PREMIUM[offer.slot] or 1)
    v = math.floor(v / 25 + 0.5) * 25
    return math.max(PIT.PURSE_MIN, math.min(PIT.PURSE_MAX, v))
end

-- The three opponents for a ship: the same three while PIT.OFFER_SECS last (no re-rolling by hailing).
function PIT.offers(st, ship)
    st.offers = st.offers or {}
    local o = st.offers[ship]
    if o and getScenarioTime() - o.at < PIT.OFFER_SECS then return o.list end
    local list = MATCH.offer(PIT.TYPES, {ship}, 1) or {}
    for _, x in ipairs(list) do x.purse = PIT.purse(x) end
    st.offers[ship] = {at = getScenarioTime(), list = list}
    return list
end

-- ── A bout ───────────────────────────────────────────────────────────────────
local function _shipLines(ship, text)
    if not RT.valid(ship) then return end
    for _, pos in ipairs({"relay", "helms", "weapons", "operations", "single"}) do
        pcall(function()
            if text then ship:addCustomInfo(pos, "pit_" .. pos, text, 30) else ship:removeCustom("pit_" .. pos) end
        end)
    end
end

local function _log(ship, text, color)
    if RT.valid(ship) then ship:addToShipLog("[The Pit] " .. text, color or "#E0A060") end
end

-- Why a ship can't sign up now, or nil.
function PIT.whyNot(st, ship)
    if not RT.valid(ship) then return "No ship." end
    if JOBS and JOBS.maxTier(ship) < PIT.MIN_TIER then
        return '"That tub? Come back when you\'ve put a thousand credits of steel on it. I don\'t book funerals."'
    end
    if st.bout then
        return st.bout.ship == ship and '"You\'re already booked. Get in the ring."'
            or '"Ring\'s busy. Watch, bet, or wait your turn."'
    end
    local cd = (st.cooldown or {})[ship]
    if cd and getScenarioTime() < cd then
        return string.format('"Patch up first. I\'ll have another one for you in %d seconds."', math.ceil(cd - getScenarioTime()))
    end
    if _distU(ship) > PIT.SIGNUP_U then return '"Come out to the ring and ask me again. I book crews I can see."' end
    return nil
end

-- Sign `ship` up for `offer`: the opponents appear across the ring, and the countdown starts.
function PIT.signUp(st, ship, offer)
    local why = PIT.whyNot(st, ship)
    if why then return false, why end
    _faction()
    local enemies = {}
    local n = #offer.group
    local opposite = (PIT.OPEN_ANGLE + 180) % 360
    for i, name in ipairs(offer.group) do
        local spread = (i - (n + 1) / 2) * 12   -- degrees apart round the far side
        local x, y = _at(opposite + spread, PIT.SPAWN_U)
        local s = CpuShip():setTemplate(name):setFaction(PIT.FACTION):setPosition(x, y)
        s:setHeading(PIT.OPEN_ANGLE)   -- facing the opening
        s:setCallSign(JOBS and JOBS.corsairName and JOBS.corsairName() or name)
        s:setCommsScript(""):setCommsFunction(function() setCommsMessage('"Save your breath for the ring."') end)
        s:orderStandGround()   -- hostile, but they hold their ground until the crew comes in
        enemies[#enemies + 1] = s
    end
    local b = {ship = ship, enemies = enemies, slot = offer.slot, purse = offer.purse, group = offer.group,
               r_value = offer.r_value, phase = "countdown", signed_at = getScenarioTime(),
               deadline = getScenarioTime() + PIT.COUNTDOWN}
    st.bout = b
    st.offers[ship] = nil
    log(string.format("[PIT] %s booked %s (%s, R %.2f): purse %d", ship:getCallSign(), MATCH.groupText(offer.group),
        offer.slot, offer.r_value or 0, offer.purse))
    _log(ship, string.format("Booked: %s, purse %d cr. You have %d seconds to get inside the ring, through the "
        .. "opening. Leave the ring and you lose.", MATCH.groupText(offer.group), offer.purse, PIT.COUNTDOWN))
    RT.emit("pit_bout", {ship = ship:getCallSign(), phase = "booked", opponents = MATCH.groupText(offer.group),
        slot = offer.slot, purse = offer.purse}, "normal")
    return true
end

-- The opponents stop fighting: no longer hostile, and they fly off and go.
local function _standDown(b)
    for _, s in ipairs(b.enemies) do
        if RT.valid(s) then
            s:setFaction("Independent")
            local x, y = s:getPosition()
            local cx, cy = _centre()
            s:orderFlyTowardsBlind(x + (x - cx) * 3, y + (y - cy) * 3)
        end
    end
    b.leaving_until = getScenarioTime() + 40
end

-- The bout is over. outcome: "won" or "lost"; why: what the crew is told.
function PIT.finish(st, outcome, why)
    local b = st.bout
    if not b then return end
    st.bout = nil
    st.cooldown = st.cooldown or {}
    st.cooldown[b.ship] = getScenarioTime() + PIT.COOLDOWN
    _standDown(b)
    st.leaving = st.leaving or {}
    st.leaving[#st.leaving + 1] = b
    _shipLines(b.ship, nil)
    if b.rec then BOUT.finish(b.rec, outcome) end
    if outcome == "won" then
        RT.addCredits(b.purse, "the Pit: purse", b.ship)
        _log(b.ship, why .. string.format(" The purse is yours: %d cr.", b.purse), "#80FF80")
        if ACH and ACH.award then ACH.award("pit_winner") end
    else
        _log(b.ship, why .. " No purse.", "#FF8080")
    end
    RT.emit("pit_bout", {ship = RT.valid(b.ship) and b.ship:getCallSign() or "?", phase = outcome, why = why,
        purse = b.purse, slot = b.slot}, "normal")
end

local function _liveEnemies(b)
    local out = {}
    for _, s in ipairs(b.enemies) do if RT.valid(s) then out[#out + 1] = s end end
    return out
end

function PIT.tick(st, now)
    -- Opponents of finished bouts go once they are well away.
    for i = #(st.leaving or {}), 1, -1 do
        local b = st.leaving[i]
        if now > (b.leaving_until or 0) then
            for _, s in ipairs(b.enemies) do if RT.valid(s) then s:destroy() end end
            table.remove(st.leaving, i)
        end
    end
    local b = st.bout
    if not b then
        if now > (st.next_fill or 0) then st.next_fill = now + 60; PIT.fillRing(st) end
        return
    end
    if not RT.valid(b.ship) then return PIT.finish(st, "lost", "The ship was lost.") end
    if b.phase == "countdown" then
        local left = math.ceil(b.deadline - now)
        _shipLines(b.ship, string.format("The Pit: get in! %d s", math.max(0, left)))
        if PIT.isInside(b.ship) then
            b.phase, b.entered_at = "fighting", now
            for _, s in ipairs(_liveEnemies(b)) do s:orderAttack(b.ship) end
            b.rec = BOUT.start{source = "pit", ships = {b.ship}, enemies = _liveEnemies(b),
                info = {slot = b.slot, predicted_r = math.floor((b.r_value or 0) * 100 + 0.5) / 100, purse = b.purse}}
            _shipLines(b.ship, "The Pit: FIGHT")
            _log(b.ship, "The gate's shut. Fight!", "#FFD060")
            RT.emit("pit_bout", {ship = b.ship:getCallSign(), phase = "fighting"}, "normal")
        elseif now >= b.deadline then
            return PIT.finish(st, "lost", "You never came into the ring. Forfeit.")
        end
        return
    end
    -- Fighting.
    BOUT.tick(b.rec, now)
    if PIT.isOutside(b.ship) then return PIT.finish(st, "lost", "You left the ring. Forfeit.") end
    for _, s in ipairs(_liveEnemies(b)) do
        if PIT.isOutside(s) then
            return PIT.finish(st, "won", s:getCallSign() .. " ran out of the ring: the bout is yours.")
        end
        -- Keep them on the crew (orders can drift after a target is lost).
        s:orderAttack(b.ship)
    end
    if #_liveEnemies(b) == 0 then return PIT.finish(st, "won", "Every opponent is down.") end
end

-- ── The pit boss (the station's comms) ───────────────────────────────────────
PIT.RULES = "The rules: you get " .. PIT.COUNTDOWN .. " seconds to get inside the ring, and there's one way in, the "
    .. "opening by my station. Rock's dense everywhere else and it bites. Once you're in, you stay in: leave the "
    .. "ring and you lose. They stay in too: if one of mine runs, you win. What dies in there is nobody's "
    .. "business but ours. Win and the purse is yours."

function PIT.hook(source, target)
    if not RT.isPlayer(source) then return end
    local st = WORLD._state["pit"]
    if not st then return end
    local ship = RT.playerShip(source) or source
    if st.bout and st.bout.ship == ship then
        addCommsReply("We yield.", function()
            PIT.finish(st, "lost", "You yielded.")
            setCommsMessage('"Smart. Live to fight another day. No purse, mind."')
            addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
        end)
        return
    end
    addCommsReply("Talk to the pit boss", function()
        local why = PIT.whyNot(st, ship)
        if why then
            setCommsMessage(why)
            addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
            return
        end
        local offers = PIT.offers(st, ship)
        local lines = {'"Looking for work with your fists? I\'ve got three on the card for you."', "", PIT.RULES, ""}
        for _, o in ipairs(offers) do
            lines[#lines + 1] = string.format("%s: %s. Purse %d cr.", o.label, MATCH.groupText(o.group), o.purse)
        end
        setCommsMessage(table.concat(lines, "\n"))
        for _, o in ipairs(offers) do
            local offer = o
            addCommsReply(string.format("%s: %s (%d cr)", offer.label, MATCH.groupText(offer.group), offer.purse), function()
                setCommsMessage(string.format('"%s for %d credits. Last chance to walk away."\n\n%s',
                    MATCH.groupText(offer.group), offer.purse, PIT.RULES))
                addCommsReply("Sign us up.", function()
                    local ok, why2 = PIT.signUp(st, ship, offer)
                    setCommsMessage(ok and string.format('"Booked. They\'re in the ring now. You\'ve got %d seconds. Go."',
                        PIT.COUNTDOWN) or why2)
                end)
                addCommsReply("Not this one.", function(s2, t2) RT.stationComms(s2, t2) end)
            end)
        end
        addCommsReply("Not today.", function(s2, t2) RT.stationComms(s2, t2) end)
    end)
end

-- ── The plugin ───────────────────────────────────────────────────────────────
function P.init(st)
    _faction()
    st.offers, st.cooldown, st.leaving = {}, {}, {}
    PIT.fillRing(st)
    st.next_fill = getScenarioTime() + 60
    RT.addStationHook(PIT.STATION, PIT.hook)
    if RUMORS and RUMORS.add then
        for i, text in ipairs(PIT.RUMORS) do
            RUMORS.add({id = "pit_rumor_" .. i, text = text, priority = 3, category = "PIT"})
        end
    end
end

function P.update(st, delta, now) PIT.tick(st, now) end

function P.cleanup(st)
    if st.bout then PIT.finish(st, "lost", "The Pit closed.") end
    if RUMORS and RUMORS.removeCategory then RUMORS.removeCategory("PIT") end
end

function P.gmMenu(add, showSelf)
    local st = WORLD._state["pit"] or {}
    local b = st.bout
    add(b and string.format("Bout: %s vs %s (%s)", RT.valid(b.ship) and b.ship:getCallSign() or "?",
            MATCH.groupText(b.group), b.phase) or "No bout running", function() end)
    if b then
        add("End bout (no result)", function()
            st.bout = nil
            _standDown(b)
            st.leaving[#st.leaving + 1] = b
            _shipLines(b.ship, nil)
            if b.rec then BOUT.finish(b.rec, "stopped") end
            showSelf()
        end)
    end
    add(string.format("Refill the ring (%d rocks)", #(st.rocks or {})), function() PIT.fillRing(st); showSelf() end)
    RT.forEachPlayer(function(p)
        add(string.format("%s: crew %s", p:getCallSign(), BOUT.crewOf(p) > 0 and tostring(BOUT.crewOf(p)) or "-"),
            function() BOUT.nextCrew(p); showSelf() end)
    end)
end

if ACH and ACH.define then
    ACH.define{id = "pit_winner", name = "Blood on the Rocks", category = "combat",
        desc = "Win a bout in the Pit."}
end

WORLD.register(P)
