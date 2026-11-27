-- The Pit (ee/ragtag/world/pit.lua; the station and region: verse/extensions/the_pit.lua): the asteroid
-- ring with its one opening, the rumors, the pit boss's tier gate, three offers with purses, signing up
-- (opponents across the ring, hostile, a countdown), and every way a bout ends: not getting in (lost),
-- every opponent down (won, the purse, no standing lost), an opponent leaving the ring (won), the crew
-- leaving it (lost), and yielding (lost). Each bout leaves a row in the fight log. The ring refills.
--
-- Not covered: a real fight (opponents are destroyed or moved by script; the crew is moved by teleport).

T.suite("world")

local A, st
local cx, cy
local opp

local function dist(e)
    local x, y = e:getPosition()
    return math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / 1000
end
local function lastRow() local r = BOUT.rows(); return r[#r] end
local function pitLine(p)
    local f = p.components.custom_ship_functions
    for i = 1, #f do if tostring(f[i].name) == "pit_relay" then return tostring(f[i].caption) end end
    return nil
end
local function nearStation() local sx, sy = T.find(PIT.STATION):getPosition(); T.moveTo(sx - 1500, sy) end
local function book(slot)
    st.cooldown[A] = nil
    st.offers[A] = nil
    for _, o in ipairs(PIT.offers(st, A)) do
        if o.slot == (slot or "easy") then return PIT.signUp(st, A, o) end
    end
    return false
end

T.step("setup", function()
    A = T.P()
    st = T.world("pit")
    T.check("setup: the plugin is running", WORLD.isEnabled("pit") and st and st._initialized)
    cx, cy = PIT.centre()
    T.eq("setup: the ring's centre is the region's", cx .. "," .. cy, "158000,32000")
    BOUT.LOG_KEY = "ragtag.fightlog.test"
    BOUT._log = nil
end)

T.step("the ring", function()
    local st_e = T.find(PIT.STATION)
    T.check("ring: the pit boss's station", RT.valid(st_e))
    T.check("ring: the station sits outside the ring, by the opening (west)", st_e and dist(st_e) > PIT.OUTSIDE_U
        and select(1, st_e:getPosition()) < cx)
    T.eq("ring: dense", #st.rocks, PIT.ASTEROIDS)
    local off_band, in_gap = 0, 0
    for _, a in ipairs(st.rocks) do
        local d = dist(a)
        if math.abs(d - PIT.RING_R) > PIT.BAND_U + 0.01 then off_band = off_band + 1 end
        local x, y = a:getPosition()
        local ang = math.deg(math.atan(x - cx, -(y - cy))) % 360
        if math.abs(((ang - PIT.OPEN_ANGLE) + 180) % 360 - 180) < PIT.OPEN_WIDTH / 2 - 1 then in_gap = in_gap + 1 end
    end
    T.eq("ring: every rock in the band (15U across)", off_band, 0)
    T.eq("ring: the opening is clear", in_gap, 0)
    T.eq("rumors: four seeds point the way", T.rumors("PIT"), 4)
    local named = false
    for _, r in ipairs(RUMORS._injected) do
        if r.category == "PIT" and r.text:find("south of the Deep Shroud", 1, true) then named = true end
    end
    T.check("rumors: a rough location, no coordinates", named)
end)

T.step("the spectators", function()
    T.eq("yachts: eight", #st.spectators, #PIT.SPECTATORS)
    local ind, con = 0, 0
    local by_party, dists = {}, {}
    for i, s in ipairs(st.spectators) do
        local d = PIT.SPECTATORS[i]
        by_party[d.party] = by_party[d.party] or {}
        table.insert(by_party[d.party], s)
        dists[#dists + 1] = dist(s)
        T.check(d.cs .. ": round the outside of the ring", dist(s) >= PIT.SPECTATOR_U - 0.01 and dist(s) <= PIT.SPECTATOR_FAR + 0.01, dist(s))
        local x, y = s:getPosition()
        local to_centre = math.deg(math.atan(cx - x, -(cy - y))) % 360
        local off = math.abs(((s:getHeading() - to_centre) + 180) % 360 - 180)
        T.check(d.cs .. ": roughly facing the ring", off <= PIT.FACING_JITTER + 1, string.format("%.0f degrees off", off))
        T.eq(d.cs .. ": a luxury yacht", s:getTypeName(), PIT.YACHT)
        T.check(d.cs .. ": here to watch and bet (scan)", s:getDescription("fullscan"):find("bet", 1, true) ~= nil,
            s:getDescription("fullscan"))
        T.check(d.cs .. ": can't be destroyed", not s:getCanBeDestroyed())
        T.check(d.cs .. ": not hostile", not s:isEnemy(A))
        if s:getFaction() == "Independent" then ind = ind + 1 elseif s:getFaction() == "Concord" then con = con + 1 end
        local x, y = s:getPosition()
        local ang = math.deg(math.atan(x - cx, -(y - cy))) % 360
        T.check(d.cs .. ": clear of the opening", math.abs(((ang - PIT.OPEN_ANGLE) + 180) % 360 - 180) > 30, ang)
    end
    T.check("yachts: Independent and Concord", ind > 0 and con > 0, ind .. " / " .. con)
    local sizes = {}
    for _, p in ipairs(PIT.PARTIES) do sizes[#sizes + 1] = #(by_party[p.id] or {}) end
    T.eq("parties: three, two, two and one on her own", table.concat(sizes, ","), "3,2,2,1")
    local function gap(a, b)
        local ax, ay = a:getPosition(); local bx, by = b:getPosition()
        return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) / 1000
    end
    local all = st.spectators
    local closest = math.huge
    for i = 1, #all do for j = i + 1, #all do closest = math.min(closest, gap(all[i], all[j])) end end
    T.check("parties: no two yachts on top of each other", closest >= PIT.YACHT_GAP - 0.01, closest)
    for id, members in pairs(by_party) do
        for i = 2, #members do
            T.check("party " .. id .. ": parked together", gap(members[1], members[i]) <= 2 * PIT.PARTY_SPREAD + 0.01,
                gap(members[1], members[i]))
        end
    end
    T.check("parties: apart from each other", gap(by_party.high_rollers[1], by_party.officials[1]) > 4
        and gap(by_party.traders[1], by_party.veteran[1]) > 4)
    table.sort(dists)
    T.check("parties: not all at one distance", dists[#dists] - dists[1] > 0.2, dists[#dists] - dists[1])
    local gone = st.spectators[1]
    gone:destroy()
    T.eq("yachts: a missing one comes back", PIT.placeSpectators(st), #PIT.SPECTATORS)
    T.check("yachts: a new one", RT.valid(st.spectators[1]) and st.spectators[1] ~= gone)
end)

T.step("too small a ship", function()
    T.eq("gate: a stock freighter is tier 0", JOBS.maxTier(A), 0)
    nearStation()
end)
T.talk(PIT.STATION, {"Talk to the pit boss"})
T.step("the pit boss won't book it", function()
    T.check("gate: turned away", T.msg():find("thousand credits", 1, true) ~= nil, T.msg())
    for _, id in ipairs({"hull_plating", "shield_mk2", "shield_mk3"}) do RT.grantUpgrade(id, "test", A) end
    T.eq("gate: now tier 2", JOBS.maxTier(A), 2)
    A:setHull(A:getHullMax())
end)

T.talk(PIT.STATION, {"Talk to the pit boss"})
T.step("three offers, with purses", function()
    T.check("offers: the rules are read out", T.msg():find("leave the ring and you lose", 1, true) ~= nil, T.msg())
    T.check("offers: easy, good match, hard", T.hasReply("Easy:") and T.hasReply("Good match:") and T.hasReply("Hard:"),
        table.concat(T.replies(), " | "))
    local o = PIT.offers(st, A)
    T.eq("offers: the same three when asked again", PIT.offers(st, A), o)
    T.check("offers: a purse for each", o[1].purse >= PIT.PURSE_MIN and o[3].purse <= PIT.PURSE_MAX)
    T.check("offers: worth the risk (the easy one pays 300+)", o[1].purse >= 300, o[1].purse)
    T.check("offers: the hard one pays more than the easy one", o[3].purse > o[1].purse,
        string.format("%d / %d / %d", o[1].purse, o[2].purse, o[3].purse))
end)
T.talk(PIT.STATION, {"Talk to the pit boss", "Good match:", "Sign us up."})
T.step("signed up: the opponents are in the ring", function()
    local b = st.bout
    T.check("book: a bout", b and b.ship == A and b.phase == "countdown")
    if not b then return end
    T.eq("book: the good match", b.slot, "match")
    for _, s in ipairs(b.enemies) do
        T.check("book: " .. s:getCallSign() .. " inside the ring", dist(s) < PIT.INSIDE_U, dist(s))
        T.check("book: " .. s:getCallSign() .. " across from the opening (east)", select(1, s:getPosition()) > cx)
        T.eq("book: " .. s:getCallSign() .. " flies for the Pit", s:getFaction(), PIT.FACTION)
        T.check("book: " .. s:getCallSign() .. " is hostile", s:isEnemy(A))
    end
    T.check("book: the countdown on Relay", (pitLine(A) or ""):find("get in", 1, true) ~= nil, tostring(pitLine(A)))
    T.check("book: one bout at a time", PIT.whyNot(st, A) ~= nil)
    opp = b.enemies
end)

-- ── Never got in: lost ───────────────────────────────────────────────────────
local c0
T.step("the clock runs out", function()
    c0 = T.credits(A)
    st.bout.deadline = T.now() - 1
end)
T.waitFor("forfeit: the bout ends", function() return st.bout == nil end, 3)
T.step("forfeit", function()
    T.eq("forfeit: no purse", T.credits(A), c0)
    T.eq("forfeit: the countdown goes", pitLine(A), nil)
    for _, s in ipairs(opp) do
        if RT.valid(s) then T.check("forfeit: the opponents stand down", not s:isEnemy(A)) end
    end
    T.check("forfeit: a cooldown", PIT.whyNot(st, A) and PIT.whyNot(st, A):find("Patch up", 1, true) ~= nil)
    local r = lastRow()
    T.check("forfeit: not in the fight log (they never fought)", not (r and r.source == "pit"))
end)
-- The sign-up channel is still open, so the hail waits for it: close it and the hail comes through.
T.step("the hail waits while the channel is open", function()
    T.check("hail: queued, not dropped", #PIT._hails == 1 and PIT._hails[1].ship == A, #PIT._hails)
end)
T.closeComms()
T.talk(PIT.STATION, {}, {answer = true, name = "the pit boss"})
T.step("the pit boss hails: a no-show is a forfeit", function()
    T.check("hail: a no-show is a forfeit", T.msg():find('never came through the gate', 1, true) ~= nil, T.msg())
end)
T.closeComms()

-- ── Every opponent down: won ─────────────────────────────────────────────────
local rep0 = {}
T.step("book again, and go in", function()
    T.check("win: booked", book("easy"))
    for _, f in ipairs({"Independent", "Concord", "Corsairs"}) do rep0[f] = T.rep(f, A) end
    c0 = T.credits(A)
    T.moveTo(cx, cy)
end)
T.waitFor("win: the fight starts once inside", function() return st.bout and st.bout.phase == "fighting" end, 3)
T.step("destroy them", function()
    T.eq("fight: the line on Relay", pitLine(A), "The Pit: FIGHT")
    T.check("fight: recorded", st.bout.rec ~= nil)
    for _, s in ipairs(st.bout.enemies) do
        local x, y = s:getPosition()
        applyDamageToEntity(s, 100000, {instigator = A, type = "kinetic", x = x + 100, y = y})
    end
end)
T.waitFor("win: the bout ends", function() return st.bout == nil end, 3)
T.step("won: the purse, and no standing lost", function()
    local purse = (lastRow() or {}).purse or 0
    T.check("won: paid the purse", purse > 0 and T.credits(A) - c0 == purse, string.format("%d (purse %d)", T.credits(A) - c0, purse))
    for f, v in pairs(rep0) do T.eq("won: " .. f .. " standing untouched", T.rep(f, A), v) end
    T.check("won: an achievement", ACH.has("pit_winner"))
    local r = lastRow()
    T.check("won: in the fight log", r and r.source == "pit" and r.outcome == "won" and r.slot == "easy", r and BOUT.rowText(r))
end)
T.talk(PIT.STATION, {}, {answer = true, name = "the pit boss"})
T.step("the pit boss hails: a fight well won, and the purse", function()
    T.check("hail: a fight well won, and the purse", T.msg():find('credits on your account', 1, true) ~= nil, T.msg())
end)
T.closeComms()

-- ── An opponent leaves the ring: won ─────────────────────────────────────────
T.step("book, and go in", function()
    T.check("run: booked", book("hard"))
    c0 = T.credits(A)
    T.moveTo(cx, cy)
end)
T.waitFor("run: fighting", function() return st.bout and st.bout.phase == "fighting" end, 3)
T.step("one of them runs", function()
    opp = st.bout.enemies
    opp[1]:setPosition(cx + 11000, cy)
end)
T.waitFor("run: the bout ends", function() return st.bout == nil end, 3)
T.step("won by default", function()
    T.check("run: paid", T.credits(A) > c0)
    T.check("run: the runner is no longer hostile", not opp[1]:isEnemy(A))
    T.eq("run: won", lastRow().outcome, "won")
end)
T.talk(PIT.STATION, {}, {answer = true, name = "the pit boss"})
T.step("the pit boss hails: the runner, and the purse", function()
    T.check("hail: the runner, and the purse", T.msg():find('ran out of my ring', 1, true) ~= nil, T.msg())
end)
T.closeComms()

-- ── The crew leaves the ring: lost ───────────────────────────────────────────
T.step("book, go in, then out", function()
    T.check("leave: booked", book("easy"))
    c0 = T.credits(A)
    T.moveTo(cx, cy)
end)
T.waitFor("leave: fighting", function() return st.bout and st.bout.phase == "fighting" end, 3)
T.step("out through the rocks", function() T.moveTo(cx - 10000, cy - 3000) end)
T.waitFor("leave: the bout ends", function() return st.bout == nil end, 3)
T.step("lost by leaving", function()
    T.eq("leave: no purse", T.credits(A), c0)
    T.eq("leave: lost", lastRow().outcome, "lost")
end)
T.talk(PIT.STATION, {}, {answer = true, name = "the pit boss"})
T.step("the pit boss hails: leaving the ring is a forfeit", function()
    T.check("hail: leaving the ring is a forfeit", T.msg():find('You left the ring', 1, true) ~= nil, T.msg())
end)
T.closeComms()

-- ── Yield ────────────────────────────────────────────────────────────────────
T.step("book, and think better of it", function()
    T.check("yield: booked", book("easy"))
    nearStation()
end)
T.talk(PIT.STATION, {"We yield."})
T.step("yielded", function()
    T.check("yield: the bout is over", st.bout == nil)
    T.check("yield: the pit boss says so", T.msg():find("No purse", 1, true) ~= nil, T.msg())
end)
T.closeComms()

-- ── Between bouts: the pit boss's station is a port ─────────────────────────
local hull0, energy0
T.step("battered, low on missiles", function()
    A:setHull(A:getHullMax() - 60)
    A:setEnergy(A:getMaxEnergy() * 0.3)
    A:setWeaponStorage("Homing", 0)
    hull0, energy0 = A:getHull(), A:getEnergy()
end)
T.dock(PIT.STATION)
T.talk(PIT.STATION, {})
T.step("docked at the Pit: missiles for sale", function()
    T.check("port: restock on offer", T.hasReply("Restock missiles"), table.concat(T.replies(), " | "))
end)
T.talk(PIT.STATION, {"Restock missiles", "Fill Homing"})
T.wait(3)
T.step("docked at the Pit: repaired, recharged, restocked", function()
    T.eq("port: homing racks full", A:getWeaponStorage("Homing"), A:getWeaponStorageMax("Homing"))
    T.check("port: hull being repaired", A:getHull() > hull0, string.format("%.1f -> %.1f", hull0, A:getHull()))
    T.check("port: energy recharging", A:getEnergy() > energy0, string.format("%.0f -> %.0f", energy0, A:getEnergy()))
end)
T.closeComms()

T.step("the ring wears down and fills up again", function()
    for i = 1, 10 do if RT.valid(st.rocks[i]) then st.rocks[i]:destroy() end end
    T.eq("refill: back to full", PIT.fillRing(st), PIT.ASTEROIDS)
end)

T.step("the GM's menu", function()
    local labels = {}
    WORLD._registry.pit.gmMenu(function(label) labels[#labels + 1] = label end, function() end)
    local all = table.concat(labels, " | ")
    T.check("gm: bout status", all:find("No bout running", 1, true) ~= nil, all)
    T.check("gm: refill", all:find("Refill the ring", 1, true) ~= nil, all)
    T.check("gm: crew numbers", all:find(A:getCallSign() .. ": crew", 1, true) ~= nil, all)
    BOUT.clearLog()
end)
