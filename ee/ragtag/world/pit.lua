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
PIT.BOSS        = "Sione Taufa"   -- the pit boss (tools/portraits: pitboss)
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
-- premium for the risk, rounded to 25 and kept within PURSE_MIN..PURSE_MAX. About 450 / 750 / 1,100 cr
-- for a tier-2 ship (raised x3 2026-11-27: the risk, and missiles at 15 cr each to restock).
-- Docked at the pit boss's station a ship is repaired (1 hull a second), recharged and sold missiles,
-- like at any port.
PIT.PURSE_RATE  = 1.5
PIT.PREMIUM     = {easy = 1.0, match = 1.15, hard = 1.35}
PIT.PURSE_MIN, PIT.PURSE_MAX = 300, 9000

-- Skill: each ship's own rating for the Pit (its record's pit_skill: MATCH's r, the crews' damage scaled
-- by it), so a crew that wins easily is offered tougher cards. After each bout that was fought, how hard it
-- was ("strain", 0 a walkover to 1 lost) is set against what the slot should feel like (PIT.EXPECT), and
-- the skill moves by exp(PIT.LEARN x (expected - strain)), limited to PIT.STEP_MIN..STEP_MAX a bout and
-- PIT.SKILL_MIN..SKILL_MAX in all. Strain is the crew's 1-5 rating when given ((n - 1) / 4); else from the
-- stats, hull above all (a little hull lost is a bad fight): 0.7 x hull lost (all of it at 20% of max)
-- + 0.3 x the worse of shields and energy drawn down. A lost bout is strain 1. A ship with no skill yet
-- replays its Pit bouts in the fight log.
PIT.SKILL_DEFAULT, PIT.SKILL_MIN, PIT.SKILL_MAX = 1.0, 0.5, 4.0
PIT.LEARN = 0.8
PIT.STEP_MIN, PIT.STEP_MAX = 0.8, 1.3
PIT.EXPECT = {easy = 0.25, match = 0.55, hard = 0.8}
PIT.HULL_FULL_PCT = 20

PIT.RUMORS = {
    "There's money in fighting, if you've got the hull for it. Someone runs bouts south of the Deep Shroud. Purses paid in clean credits.",
    "A crew I know came back from the Pit with a thousand credits and half a ship. Somewhere below the Deep Shroud, they said. Not as far as the Maw.",
    "They call it the Pit. A ring of rock out past the Rim, south of the Shroud's deep end. You fight whoever the pit boss puts in front of you.",
    "Don't take a stock freighter to the Pit. The pit boss won't even talk to you until you've spent real money on that hull.",
}

-- Spectators: luxury yachts parked round the outside of the ring in small parties (three, two, two and one
-- on her own), there to watch and bet. Each session a party settles somewhere near its usual spot (`angle`,
-- give or take PIT.PARTY_JITTER degrees, PIT.SPECTATOR_U to PIT.SPECTATOR_FAR out) and its yachts park
-- loosely round that point, each pointing at the ring give or take PIT.FACING_JITTER degrees. Always clear
-- of the opening and the station. Indestructible and idle; one that goes missing comes back to its party.
PIT.SPECTATOR_U, PIT.SPECTATOR_FAR = 10.0, 11.8
PIT.PARTY_JITTER  = 12      -- degrees round the ring
PIT.PARTY_SPREAD  = 0.9     -- U: how far a yacht parks from its party's point
PIT.YACHT_GAP     = 0.45    -- U: no two yachts closer than this
PIT.FACING_JITTER = 15      -- degrees off pointing straight at the ring
PIT.OPENING_CLEAR = 35      -- degrees either side of the opening kept free of yachts
PIT.YACHT = "Luxury Yacht"   -- ship_templates.lua; a Flavia stands in where that is not loaded
PIT.PARTIES = {
    {id = "high_rollers", angle = 40},    -- three
    {id = "officials",    angle = 140},   -- two
    {id = "traders",      angle = 205},   -- two
    {id = "veteran",      angle = 330},   -- one, on her own
}
PIT.SPECTATORS = {
    {party = "high_rollers", fac = "Independent", cs = "Gilded Wake",
     scan = "Registered to a Lumen shipping family. Here to watch the fights and bet on them: the observation lounge is full, and so is the bar."},
    {party = "high_rollers", fac = "Independent", cs = "Lady Fortune",
     scan = "A gambling syndicate's yacht. It takes bets from the other spectators and has never been known to lose money on a night."},
    {party = "high_rollers", fac = "Concord",     cs = "Off the Record",
     scan = "Registered to a Concord official, here to watch the fights and bet on them. Officially, it is not here. Unofficially, it has a large bet on the next bout."},
    {party = "officials",    fac = "Concord",     cs = "Recess",
     scan = "Concord-registered, transponder dimmed. Senate staff on a 'fact-finding' trip, here to watch and betting heavily on the house."},
    {party = "officials",    fac = "Concord",     cs = "Discretion",
     scan = "A Concord diplomatic yacht that has filed no flight plan. Here to watch, bet, and not be seen doing either."},
    {party = "traders",      fac = "Independent", cs = "Silk Margin",
     scan = "A trader's yacht, out to watch and bet. Its owner keeps a book on every crew that fights here."},
    {party = "traders",      fac = "Independent", cs = "Golden Hour",
     scan = "A Rim magnate's yacht, here to watch the fights and bet on them; the magnate's private bookmaker is aboard."},
    {party = "veteran",      fac = "Independent", cs = "Second Wind",
     scan = "A retired fighter's yacht. She fought here once; now she watches, bets, and heckles over open comms."},
}
PIT.SPECTATOR_LINES = {
    '"Ten thousand on the next bout. Don\'t make me regret it."',
    '"We\'re here for the show. Make it a good one."',
    '"Odds are against you, friend. That\'s what makes it interesting."',
    '"Win or lose, the drinks are on the house. The house always wins."',
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

-- The bearing (0 = up, clockwise) from the ring's centre to (x, y), and the distance in U.
local function _bearingFromCentre(x, y)
    local cx, cy = _centre()
    return math.deg(math.atan(x - cx, -(y - cy))) % 360, math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / U
end

local function _nearOpening(angle, clear)
    return math.abs(((angle - PIT.OPEN_ANGLE) + 180) % 360 - 180) < clear
end

-- Where a party settles this session: near its usual angle, at a random distance in the spectator band.
local function _partyPoint(st, party)
    st.party_at = st.party_at or {}
    local p = st.party_at[party.id]
    if p then return p.x, p.y end
    local angle = party.angle + (math.random() * 2 - 1) * PIT.PARTY_JITTER
    local x, y = _at(angle, PIT.SPECTATOR_U + 0.4 + math.random() * (PIT.SPECTATOR_FAR - PIT.SPECTATOR_U - 0.8))
    st.party_at[party.id] = {x = x, y = y}
    return x, y
end

-- A parking spot for one yacht of `party`: loosely round the party's point, in the spectator band, clear of
-- the opening and at least PIT.YACHT_GAP from every other yacht.
local function _yachtSpot(st, party)
    local px, py = _partyPoint(st, party)
    local fallback
    for _ = 1, 40 do
        local a, r = math.random() * 2 * math.pi, (0.3 + math.random() * 0.7) * PIT.PARTY_SPREAD * U
        local x, y = px + math.cos(a) * r, py + math.sin(a) * r
        local ang, d = _bearingFromCentre(x, y)
        fallback = fallback or {x, y}
        if d >= PIT.SPECTATOR_U and d <= PIT.SPECTATOR_FAR and not _nearOpening(ang, PIT.OPENING_CLEAR) then
            local clear = true
            for _, o in pairs(st.spectators) do
                if RT.valid(o) then
                    local ox, oy = o:getPosition()
                    if (ox - x) ^ 2 + (oy - y) ^ 2 < (PIT.YACHT_GAP * U) ^ 2 then clear = false end
                end
            end
            if clear then return x, y end
        end
    end
    return fallback[1], fallback[2]
end

-- The spectators: placed once, and any that went missing put back with their party (between bouts).
function PIT.placeSpectators(st)
    st.spectators = st.spectators or {}
    local tmpl = (__ship_templates and __ship_templates[PIT.YACHT]) and PIT.YACHT or "Flavia"
    local parties = {}
    for _, p in ipairs(PIT.PARTIES) do parties[p.id] = p end
    local n = 0
    for i, d in ipairs(PIT.SPECTATORS) do
        if not RT.valid(st.spectators[i]) then
            local x, y = _yachtSpot(st, parties[d.party])
            local s = CpuShip():setTemplate(tmpl):setFaction(d.fac):setCallSign(d.cs):setPosition(x, y)
            local from = _bearingFromCentre(x, y)
            s:setHeading((from + 180 + (math.random() * 2 - 1) * PIT.FACING_JITTER) % 360)   -- roughly at the ring
            s:setCanBeDestroyed(false)
            s:setScanningParameters(1, 1)
            s:setDescriptions("A luxury yacht, parked by the ring.", d.scan)
            s:orderIdle()
            s:setCommsScript(""):setCommsFunction(function()
                setCommsMessage(PIT.SPECTATOR_LINES[math.random(#PIT.SPECTATOR_LINES)])
            end)
            st.spectators[i] = s
        end
        n = n + 1
    end
    return n
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

-- ── Skill (see PIT.SKILL_DEFAULT) ────────────────────────────────────────────
-- How hard a fight was, 0 (a walkover) to 1 (lost): the crew's rating when it has one, else the stats.
function PIT.strain(row)
    if row.rating then
        local n = tonumber(row.rating) or 3
        if (row.v or 1) < 2 then n = n + 1 end   -- version 1 rows were rated 1-3
        return math.max(0, math.min(1, (n - 1) / 4))
    end
    if row.outcome ~= "won" then return 1 end
    local hull = math.min(1, (row.hull_lost_pct or 0) / PIT.HULL_FULL_PCT)
    local drawn = math.max((100 - (row.min_shield_pct or 100)) / 100, (100 - (row.energy_min_pct or 100)) / 100)
    return math.max(0, math.min(1, 0.7 * hull + 0.3 * drawn))
end

-- The skill after one more bout (`row`), from `r` before it.
function PIT.nextSkill(r, row)
    local expect = PIT.EXPECT[row.slot] or PIT.EXPECT.match
    local step = math.exp(PIT.LEARN * (expect - PIT.strain(row)))
    step = math.max(PIT.STEP_MIN, math.min(PIT.STEP_MAX, step))
    return math.max(PIT.SKILL_MIN, math.min(PIT.SKILL_MAX, r * step))
end

-- A ship's skill. The first time, its Pit bouts in the fight log are replayed (by callsign).
function PIT.skill(ship)
    local rec = RT.shipRecord(ship)
    if not rec then return PIT.SKILL_DEFAULT end
    if rec.pit_skill then return rec.pit_skill end
    local r, name = PIT.SKILL_DEFAULT, RT.valid(ship) and ship:getCallSign() or nil
    for _, row in ipairs(BOUT.rows()) do
        if row.source == "pit" and row.ship == name and (row.outcome == "won" or row.outcome == "lost") then
            r = PIT.nextSkill(r, row)
        end
    end
    rec.pit_skill = r
    return r
end

-- A bout was fought (or rated): move the ship's skill. A rating after the fact re-does that bout's step
-- from the skill it had before (only for the ship's latest bout).
function PIT.learn(ship, row)
    local rec = RT.shipRecord(ship)
    if not rec or not row then return end
    if row.skill_before == nil then
        row.skill_before = PIT.skill(ship)
        rec.pit_last = row.session .. ":" .. row.seq
    elseif rec.pit_last ~= row.session .. ":" .. row.seq then
        return   -- an older bout: too late to change the skill by it
    end
    rec.pit_skill = PIT.nextSkill(row.skill_before, row)
    row.skill_after = math.floor(rec.pit_skill * 100 + 0.5) / 100
    BOUT.save()
    RT.saveCampaign()
end

BOUT.on_rated[#BOUT.on_rated + 1] = function(row)
    if row.source ~= "pit" then return end
    for _, p in ipairs(RT.players) do
        if RT.valid(p) and p:getCallSign() == row.ship then PIT.learn(p, row) end
    end
end

-- The three opponents for a ship: the same three while PIT.OFFER_SECS last (no re-rolling by hailing).
function PIT.offers(st, ship)
    st.offers = st.offers or {}
    local o = st.offers[ship]
    if o and getScenarioTime() - o.at < PIT.OFFER_SECS then return o.list end
    local list = MATCH.offer(PIT.TYPES, {ship}, PIT.skill(ship)) or {}
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

-- What the pit boss says when a bout is over, by how it ended (`b` the bout, `name` the opponent who ran).
-- No hail for a yield (the crew is on the line already) or a lost ship (nobody to hail).
PIT.BOSS_SAYS = {
    beaten  = function(b) return string.format('"Now THAT is a fight. The crowd\'s on its feet and the books are a mess. '
        .. '%d credits on your account. Dock and patch up; I\'ll have another card for you."', b.purse) end,
    ran     = function(b, name) return string.format('"%s turned tail and ran out of my ring. Coward\'s purse is yours: '
        .. '%d credits. They won\'t be fighting here again."', name or "Your opponent", b.purse) end,
    left    = function() return '"You left the ring. Rules are rules: that\'s a forfeit, and no purse. '
        .. 'The crowd paid to see a fight, not a retreat. Come back when you mean it."' end,
    no_show = function() return '"Clock ran out and you never came through the gate. Forfeit. My fighters got paid '
        .. 'to stand there, and you made me look bad in front of the yachts."' end,
}

-- The pit boss hails the crew with the result. A hail can't get through while the crew has a channel open
-- (often still the sign-up talk with the pit boss), so it is tried again every second for
-- PIT.HAIL_RETRY_SECS; only then does it go to the ship log. Returns whether a hail is on its way.
PIT.HAIL_RETRY_SECS = 30
PIT._hails = PIT._hails or {}

local function _trySend(h)
    local boss = RT.find(PIT.STATION)
    return RT.valid(boss) and RT.valid(h.ship) and boss:sendCommsMessage(h.ship, h.text) and true or false
end

function PIT.hailResult(b, reason, name)
    local say = PIT.BOSS_SAYS[reason]
    if not say or not RT.valid(b.ship) then return false end
    local h = {ship = b.ship, text = say(b, name), give_up = getScenarioTime() + PIT.HAIL_RETRY_SECS}
    if not _trySend(h) then PIT._hails[#PIT._hails + 1] = h end
    return true
end

-- Every frame: the hails still waiting for the crew's comms to be free.
function PIT.tickHails(now)
    for i = #PIT._hails, 1, -1 do
        local h = PIT._hails[i]
        if not RT.valid(h.ship) then
            table.remove(PIT._hails, i)
        elseif now >= (h.next_try or 0) then
            h.next_try = now + 1
            if _trySend(h) then
                table.remove(PIT._hails, i)
            elseif now >= h.give_up then
                _log(h.ship, "Pit boss: " .. h.text, "#E0A060")
                table.remove(PIT._hails, i)
            end
        end
    end
end

-- The bout is over. outcome: "won" or "lost"; why: the ship-log line; reason: how it ended (PIT.BOSS_SAYS:
-- the pit boss hails the crew with it), name: the opponent who ran.
function PIT.finish(st, outcome, why, reason, name)
    local b = st.bout
    if not b then return end
    st.bout = nil
    st.cooldown = st.cooldown or {}
    st.cooldown[b.ship] = getScenarioTime() + PIT.COOLDOWN
    _standDown(b)
    st.leaving = st.leaving or {}
    st.leaving[#st.leaving + 1] = b
    _shipLines(b.ship, nil)
    if b.rec then
        -- The fight log, and the ship's skill moves by it (a bout never fought, or ended by the GM, teaches nothing).
        for _, row in ipairs(BOUT.finish(b.rec, outcome)) do
            if RT.valid(b.ship) and (outcome == "won" or outcome == "lost") then PIT.learn(b.ship, row) end
        end
    end
    if outcome == "won" then
        RT.addCredits(b.purse, "the Pit: purse", b.ship)
        if ACH and ACH.award then ACH.award("pit_winner") end
    end
    -- The pit boss hails with the result (the hail is in the ship log too); without a hail, a log line.
    if not PIT.hailResult(b, reason, name) and not PIT.BOSS_SAYS[reason] then
        if outcome == "won" then _log(b.ship, why .. string.format(" The purse is yours: %d cr.", b.purse), "#80FF80")
        else _log(b.ship, why .. " No purse.", "#FF8080") end
    end
    RT.emit("pit_bout", {ship = RT.valid(b.ship) and b.ship:getCallSign() or "?", phase = outcome, why = why,
        reason = reason, purse = b.purse, slot = b.slot}, "normal")
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
        if now > (st.next_fill or 0) then st.next_fill = now + 60; PIT.fillRing(st); PIT.placeSpectators(st) end
        return
    end
    if not RT.valid(b.ship) then return PIT.finish(st, "lost", "The ship was lost.", "destroyed") end
    if b.phase == "countdown" then
        local left = math.ceil(b.deadline - now)
        _shipLines(b.ship, string.format("The Pit: get in! %d s", math.max(0, left)))
        if PIT.isInside(b.ship) then
            b.phase, b.entered_at = "fighting", now
            for _, s in ipairs(_liveEnemies(b)) do s:orderAttack(b.ship) end
            b.rec = BOUT.start{source = "pit", ships = {b.ship}, enemies = _liveEnemies(b),
                info = {slot = b.slot, predicted_r = math.floor((b.r_value or 0) * 100 + 0.5) / 100, purse = b.purse,
                        skill_r = math.floor(PIT.skill(b.ship) * 100 + 0.5) / 100}}
            _shipLines(b.ship, "The Pit: FIGHT")
            _log(b.ship, "The gate's shut. Fight!", "#FFD060")
            RT.emit("pit_bout", {ship = b.ship:getCallSign(), phase = "fighting"}, "normal")
        elseif now >= b.deadline then
            return PIT.finish(st, "lost", "You never came into the ring. Forfeit.", "no_show")
        end
        return
    end
    -- Fighting.
    BOUT.tick(b.rec, now)
    if PIT.isOutside(b.ship) then return PIT.finish(st, "lost", "You left the ring. Forfeit.", "left") end
    for _, s in ipairs(_liveEnemies(b)) do
        if PIT.isOutside(s) then
            return PIT.finish(st, "won", s:getCallSign() .. " ran out of the ring: the bout is yours.", "ran", s:getCallSign())
        end
        -- Keep them on the crew (orders can drift after a target is lost).
        s:orderAttack(b.ship)
    end
    if #_liveEnemies(b) == 0 then return PIT.finish(st, "won", "Every opponent is down.", "beaten") end
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
            PIT.finish(st, "lost", "You yielded.", "yield")
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
        local lines = {'"Sione Taufa. I run the Pit. Looking for work with your fists? I\'ve got three on the card '
            .. 'for you."', "", PIT.RULES, ""}
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
    PIT.placeSpectators(st)
    st.next_fill = getScenarioTime() + 60
    RT.addStationHook(PIT.STATION, PIT.hook)
    if RUMORS and RUMORS.add then
        for i, text in ipairs(PIT.RUMORS) do
            RUMORS.add({id = "pit_rumor_" .. i, text = text, priority = 3, category = "PIT"})
        end
    end
end

function P.update(st, delta, now)
    PIT.tick(st, now)
    PIT.tickHails(now)
end

function P.cleanup(st)
    if st.bout then PIT.finish(st, "lost", "The Pit closed.", "closed") end
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
        -- The ship's skill, and the GM's 1-5 verdict on its last Pit fight (for a GM playing alone, too).
        local row
        for _, r in ipairs(BOUT.rows()) do
            if r.source == "pit" and r.ship == p:getCallSign() and r.session == BOUT.session then row = r end
        end
        add(string.format("%s: skill %.2f%s", p:getCallSign(), PIT.skill(p),
            row and (row.rating and string.format(" (last fight rated %d)", row.rating) or " (rate last fight)") or ""), function()
            if not row then return end
            clearGMFunctions()
            addGMFunction("← The Pit", showSelf)
            for _, rt in ipairs(BOUT.RATINGS) do
                local n = rt[1]
                addGMFunction(rt[2] .. (row.rating == n and " ■" or ""), function()
                    BOUT.rate(row, n, "gm")
                    BOUT.clearRating(p)
                    showSelf()
                end)
            end
        end)
    end)
end

if ACH and ACH.define then
    ACH.define{id = "pit_winner", name = "Blood on the Rocks", category = "combat",
        desc = "Win a bout in the Pit."}
end

WORLD.register(P)
