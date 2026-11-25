-- Proximity spawns: ambient faction patrols by zone. Corsair attack groups (spawn conditions,
-- the leash, suspension), Concord shake-downs (approach, jammer, hail, the outcomes by standing,
-- the timeout) and hostile Concord groups with their combat jammers. With two ships: each patrol
-- hunts one ship and judges it by its own standing, a second ship draws its own patrol, zones
-- send one patrol per cooldown however many ships are in them, and a patrol whose ship leaves
-- takes another ship still in the zone.
--
-- The plugin's own update does the spawning: the test only puts the ship somewhere and brings
-- the next check forward (the real interval is 8 s). Patrol ships are moved next to the player
-- instead of waiting for them to fly there.
--
-- Not covered: the patrols' flying and shooting, the loot a destroyed patrol drops, and the
-- density check against garrisons (the test picks spots with few hostiles around).

T.suite("world", {proximity = true})

local U = 1000
local A, B, st
local group, ship
local c0, rep0

-- Every credit movement while the test runs: {amount, reason, ship}. Credits are checked from
-- this list, not from balances: a ship parked in open space can also drift into a salvage pod.
local paid = {}
local _addCredits = RT.addCredits
RT.addCredits = function(amount, reason, who)
    paid[#paid + 1] = {amount = amount, reason = reason, ship = RT.playerShip(who) or RT.player}
    return _addCredits(amount, reason, who)
end
local function charged(reason, who)
    local total = 0
    for _, p in ipairs(paid) do
        if p.reason == reason and p.ship == who then total = total + p.amount end
    end
    return total
end

local function now() return T.now() end
local function check_now() st.next_check = 0 end
local function groups() return st.active end
local function reset_cooldowns() st.region_cd = {} end

-- A place in a zone where a patrol can spawn: outside every station exclusion (the ship and the
-- spawn point 10U ahead of it), deeper in this zone than in any other, few hostiles around.
local function depth(x, y, r) return 1 - math.sqrt((x - r.x * U) ^ 2 + (y - r.y * U) ^ 2) / (r.r * U) end
local function clear_of_stations(x, y, margin)
    for _, ex in ipairs(st.exclusions) do
        if math.sqrt((x - ex.x) ^ 2 + (y - ex.y) ^ 2) < ex.r + margin then return false end
    end
    return true
end
-- The plugin's grid cell (18U squares): one patrol per cell at a time.
local function cell(x, y) return math.floor(x / (18 * U) + 0.5) .. "," .. math.floor(y / (18 * U) + 0.5) end
local function spot(zone, away)    -- away = {x, y}: in another grid cell, 10U+ from there
    local r = st.regions[zone]
    if not r then error("no such patrol zone: " .. zone) end
    for _, frac in ipairs({0.3, 0.5, 0.15, 0.65}) do
        for ang = 0, 330, 30 do
            local x = r.x * U + math.cos(math.rad(ang)) * r.r * U * frac
            local y = r.y * U + math.sin(math.rad(ang)) * r.r * U * frac
            local ok = clear_of_stations(x, y, 2 * U) and clear_of_stations(x, y - 10 * U, 4 * U)
                       and depth(x, y - 10 * U, r) > 0.15
            for name, other in pairs(st.regions) do
                if name ~= zone and depth(x, y, other) >= depth(x, y, r) then ok = false end
            end
            if ok and away and (cell(x, y) == cell(away[1], away[2])
                                or math.sqrt((x - away[1]) ^ 2 + (y - away[2]) ^ 2) < 10 * U) then ok = false end
            if ok then
                local hostiles = 0
                for _, o in ipairs(getObjectsInRadius(x, y, 12 * U)) do
                    local got, fac = pcall(function() return o:getFaction() end)
                    if got and VERSE.HOSTILE_FACTIONS[fac] then hostiles = hostiles + 1 end
                end
                if hostiles < 2 then return x, y end
            end
        end
    end
    error("no usable spot in " .. zone)
end
local _spots = {}     -- one spot per zone for the whole test, so "coming back" means the same place
local function go(zone)
    if not _spots[zone] then _spots[zone] = {spot(zone)} end
    local x, y = _spots[zone][1], _spots[zone][2]
    T.moveTo(x, y)
    A:setHeading(0)      -- patrols spawn 10U ahead: due "north" of the spot, which spot() checked
end
local function leave() T.moveTo(VERSE.at("Port Vesper", 2, 2)) end
local function alive(g)
    local n = 0
    for _, s in ipairs(g.ships) do if RT.valid(s) then n = n + 1 end end
    return n
end
-- Remove every group (as the watchdog would once its ships are gone) and start clean.
local function wipe()
    for _, g in ipairs(st.active) do
        for _, s in ipairs(g.ships) do if RT.valid(s) then s:destroy() end end
        if RT.valid(g.jammer) then g.jammer:destroy() end
        PROX.clearCombatJammers(g.cjam)
    end
    st.active = {}
    reset_cooldowns()
end
local function set_rep(faction, value, who)
    RT.addReputation(faction, value - T.rep(faction, who), "test", who)
end
-- Put the group's first ship next to a player ship (inside the 5U interception range).
local function close_in(who)
    local x, y = (who or A):getPosition()
    ship:setPosition(x + 3000, y)
end
-- Put any player ship at this zone's test spot (dx east of it), stopped and facing north.
local function place(who, zone, dx)
    if not _spots[zone] then _spots[zone] = {spot(zone)} end
    pcall(function() if who:getDockedWith() then who:commandUndock() end end)
    who:setPosition(_spots[zone][1] + (dx or 0), _spots[zone][2])
    who:setHeading(0)
    pcall(function() who:commandImpulse(0) end)
end
-- The second ship waits out of the way, away from every zone.
local function park(who)
    local x, y = VERSE.at("Port Vesper", -2, -2)
    who:setPosition(x, y)
    pcall(function() who:commandImpulse(0) end)
end
local function order_target(s)
    local ok, t = pcall(function() return s:getOrderTarget() end)
    return ok and t or nil
end

T.step("setup", function()
    A = T.P()
    st = T.world("proximity")
    T.check("setup: the plugin is running", WORLD.isEnabled("proximity") and st and st._initialized)
    for _, zone in ipairs({"the Concord Core", "the Arbiter Line", "the Escrow Marches", "the Shroud", "the Deep Shroud",
                           "the Gauntlet", "Blackwater Reach", "the Boneyard", "the Maw"}) do
        T.check("setup: zone " .. zone, st.regions[zone] ~= nil and PROX.zones[zone] ~= nil)
    end
    T.eq("setup: nothing spawned at Port Vesper", #groups(), 0)
    T.eq("setup: zones start on Medium", PROX.getZoneMode("the Gauntlet"), 3)
    -- The Shroud's own raiders, not Blackwater's Corsairs: hostile whatever the Corsair standing.
    for _, zone in ipairs({"the Shroud", "Halcyon Rest", "the Deep Shroud"}) do
        T.eq("setup: " .. zone .. " sends Shroud Raiders", PROX.zones[zone].faction, "Shroud Raiders")
    end
    T.eq("setup: the Gauntlet sends Corsairs", PROX.zones["the Gauntlet"].faction, "Corsairs")
end)

-- ── The Escrow Marches: Concord space south of the Core and the Arbiter Line ──
T.step("the Escrow Marches", function()
    local U = 1000
    local function at(x, y) return VERSE.regionAt(x * U, y * U).name end
    T.eq("escrow: its middle", at(-155, 32), "the Escrow Marches")
    T.eq("escrow: south of the Core", at(-150, 0), "the Escrow Marches")
    T.eq("escrow: closes the gap where the Core and the Arbiter Line meet", at(-110, -18), "the Escrow Marches")
    T.check("escrow: no open space along the Core / Arbiter edge to the south",
        at(-110, -22) ~= "open space" and at(-105, -15) ~= "open space")
    T.eq("escrow: Sentinel Fleet Yard is still in the Core (the smaller region wins)", at(-159, -22), "the Concord Core")
    T.eq("escrow: Valcourt still in the Core", at(-169, -35), "the Concord Core")
    T.eq("escrow: the Cinder Fields are not in it", at(-70, 50), "the Cinder Fields")
    T.check("escrow: it stops short of the Cinder Fields (open space between)", at(-84, 50) == "open space", at(-84, 50))
    local z, arb = PROX.zones["the Escrow Marches"], PROX.zones["the Arbiter Line"]
    T.check("escrow: patrols like the Arbiter Line", z and z.faction == arb.faction and z.comms == arb.comms
        and z.cooldown == arb.cooldown and z.max_active == arb.max_active)
    T.check("escrow: a Science DB region entry", SCIDB.get("region_escrow") ~= nil)
end)

-- ── No spawn where there should be none ──────────────────────────────────────
T.step("docked at a station", function() check_now() end)
T.wait(1)
T.step("safe space stays quiet", function() T.eq("quiet: no patrol outside the zones", #groups(), 0) end)

T.step("zone switched off by the GM", function()
    PROX.setZoneMode("the Gauntlet", 1)
    go("the Gauntlet"); check_now()
end)
T.wait(1)
T.step("mode None", function()
    T.eq("mode: no patrol in a zone set to None", #groups(), 0)
    PROX.setZoneMode("the Gauntlet", 3)
    PROX.suspendZone("the Gauntlet")
    check_now()
end)
T.wait(1)
T.step("zone suspended by an arc", function()
    T.eq("suspend: no patrol in a suspended zone", #groups(), 0)
    PROX.resumeZone("the Gauntlet")
    JOBS.config.jobboard_locked = true
    check_now()
end)
T.wait(1)
T.step("job board locked", function()
    T.eq("lock: no patrol while the board is locked", #groups(), 0)
    JOBS.config.jobboard_locked = false
    check_now()
end)

-- ── Corsairs: attack on sight ────────────────────────────────────────────────
T.waitFor("corsairs: a patrol spawns in the Gauntlet", function() return #groups() == 1 end, 5)
T.step("the patrol", function()
    group = groups()[1]
    ship = group.ships[1]
    T.eq("corsairs: in the zone the ship is in", group.region_name, "the Gauntlet")
    T.check("corsairs: hunts the ship that drew it", group.target == A)
    T.check("corsairs: the group holds its ships as entities", type(ship) ~= "string" and RT.valid(ship))
    T.eq("corsairs: all its ships are alive", alive(group), #group.ships)
    T.eq("corsairs: faction", ship:getFaction(), "Corsairs")
    T.check("corsairs: hostile to the crew", ship:isEnemy(A))
    T.check("corsairs: not a shake-down", not group.is_shakedown)
    T.check("corsairs: spawned inside the zone", depth(group.spawn_x, group.spawn_y, st.regions["the Gauntlet"]) > 0)
    T.check("corsairs: spawned clear of stations", clear_of_stations(group.spawn_x, group.spawn_y, 0))
    T.check("corsairs: tracked for a kill penalty", RT._kill_cbs[ship] ~= nil)
    reset_cooldowns(); check_now()
end)
T.wait(1)
T.step("one group per area", function()
    T.eq("corsairs: no second group on top of the first", #groups(), 1)
    st.region_cd["the Gauntlet"] = now()     -- back on its normal cooldown for the leash checks
end)

-- ── The leash ────────────────────────────────────────────────────────────────
T.step("the ship leaves the zone", function() leave(); check_now() end)
T.waitFor("leash: the patrol is recalled", function() return group.recalled end, 3)
T.step("the ship comes back", function() go("the Gauntlet"); check_now() end)
T.waitFor("leash: the patrol resumes the hunt", function() return not group.recalled end, 3)
T.step("the ship leaves for good", function() leave(); check_now() end)
T.waitFor("leash: recalled again", function() return group.recalled end, 3)
T.step("two minutes pass", function() group.recalled_at = now() - 200; check_now() end)
T.waitFor("leash: the patrol despawns", function() return #groups() == 0 end, 3)
T.step("gone", function() T.eq("leash: its ships are removed", alive(group), 0) end)

-- ── Two patrols with one name are still two patrols ──────────────────────────
local g1, g2
T.step("first patrol", function() go("the Gauntlet"); reset_cooldowns(); check_now() end)
T.waitFor("names: a patrol in the Gauntlet", function() return #groups() == 1 end, 5)
T.step("second patrol, elsewhere", function()
    g1 = groups()[1]
    st.region_cd["the Gauntlet"] = now()
    go("the Shroud"); check_now()
end)
T.waitFor("names: a patrol in the Shroud", function() return #groups() == 2 end, 5)
T.step("same callsign, then one dies", function()
    g2 = groups()[2]
    T.eq("names: the second is the Shroud's", g2.region_name, "the Shroud")
    T.eq("shroud: a Shroud Raiders patrol", g2.ships[1]:getFaction(), "Shroud Raiders")
    T.check("shroud: hostile to the crew", g2.ships[1]:isEnemy(A))
    local name = g1.ships[1]:getCallSign()
    for _, s in ipairs(g2.ships) do s:setCallSign(name) end
    for _, s in ipairs(g2.ships) do s:destroy() end
    check_now()
end)
T.waitFor("names: the dead patrol is cleared", function() return #groups() == 1 end, 3)
T.step("the other is untouched", function()
    T.check("names: the surviving group is the first one", groups()[1] == g1)
    T.eq("names: its ships are still alive", alive(g1), #g1.ships)
    wipe()
end)

-- ── Concord: a shake-down with a clean record ────────────────────────────────
T.step("into Concord space", function()
    set_rep("Concord", 0, A)
    go("the Concord Core"); check_now()
end)
T.waitFor("shakedown: a Concord patrol spawns", function() return #groups() == 1 end, 5)
T.step("approaching", function()
    group = groups()[1]; ship = group.ships[1]
    T.check("shakedown: it is a shake-down", group.is_shakedown)
    T.eq("shakedown: one ship", #group.ships, 1)
    T.eq("shakedown: faction", ship:getFaction(), "Concord")
    T.check("shakedown: not hostile", not ship:isEnemy(A))
    T.eq("shakedown: approaching", group.shakedown_state, "approaching")
    T.check("shakedown: no jammer yet", group.jammer == nil)
    close_in(); check_now()
end)
T.waitFor("shakedown: a warp jammer is dropped on the ship", function() return RT.valid(group.jammer) end, 3)
T.step("intercepted", function()
    T.eq("shakedown: waiting for the crew", group.shakedown_state, "pending")
    T.check("shakedown: the hailing ship is kept as an entity", group.hailing_ship == ship)
    local jx, jy = group.jammer:getPosition()
    local px, py = A:getPosition()
    T.check("shakedown: the jammer is right behind the ship", math.sqrt((jx - px) ^ 2 + (jy - py) ^ 2) < 600)
    rep0, c0 = T.rep("Concord", A), T.credits(A)
end)
T.talk(function() return ship end, {"Confirmed. Standing by."}, {answer = true, name = "the patrol"})
T.step("clean record", function()
    T.check("clean: nothing flagged", T.msg():find("Nothing flagged", 1, true) ~= nil, T.msg())
    T.check("clean: the stop is over", group.shakedown_done and not group.shakedown_hostile)
    T.eq("clean: standing unchanged", T.rep("Concord", A), rep0)
    T.eq("clean: no fee", charged("Concord inspection fee", A), 0)
    check_now()
end)
T.closeComms()
T.waitFor("clean: the jammer is released", function() return not RT.valid(group.jammer) end, 3)
T.step("the patrol goes home", function()
    T.check("clean: the patrol is due to leave", group.despawn_at ~= nil)
    T.check("clean: still not hostile", not ship:isEnemy(A))
    group.despawn_at = now() - 1; check_now()
end)
T.waitFor("clean: the patrol despawns", function() return #groups() == 0 end, 3)

-- ── Concord: a record with flags on it pays a fine (and only that ship pays) ──
T.step("a poor record, and a second ship in the game", function()
    B = T.secondShip()
    park(B)                          -- out of Concord space: the patrol is A's
    set_rep("Concord", -100, A)
    RT.setCredits(500, A)
    RT.setCredits(500, B)
    reset_cooldowns(); go("the Concord Core"); check_now()
end)
T.waitFor("fine: a patrol spawns", function() return #groups() == 1 end, 5)
T.step("intercept", function()
    group = groups()[1]; ship = group.ships[1]
    T.check("fine: still a shake-down at -100", group.is_shakedown)
    close_in(); check_now()
end)
T.waitFor("fine: jammer dropped", function() return RT.valid(group.jammer) end, 3)
T.talk(function() return ship end, {"Confirmed. Standing by."}, {answer = true, name = "the patrol"})
local b_rep0, b_c0
T.step("the fine is offered", function()
    T.check("fine: fee quoted", T.msg():find("Inspection fee: 100 credits", 1, true) ~= nil, T.msg())
    T.check("fine: can pay", T.hasReply("Pay the fine"))
    T.check("fine: can refuse", T.hasReply("Refuse to pay"))
    rep0, c0 = T.rep("Concord", A), T.credits(A)
    b_rep0, b_c0 = T.rep("Concord", B), T.credits(B)
end)
T.talk(function() return ship end, {"Confirmed. Standing by.", "Pay the fine"}, {name = "the patrol"})
T.step("paid", function()
    T.eq("fine: 100 credits from the inspected ship", charged("Concord inspection fee", A), -100)
    T.eq("fine: its standing +100", T.rep("Concord", A) - rep0, 100)
    T.eq("fine: nothing from the other ship", charged("Concord inspection fee", B), 0)
    T.eq("fine: the other ship's standing untouched", T.rep("Concord", B), b_rep0)
    T.check("fine: the stop is over, peacefully", group.shakedown_done and not group.shakedown_hostile)
    wipe()
end)
T.closeComms()

-- ── Concord: ignoring the hail ───────────────────────────────────────────────
T.step("another stop", function()
    set_rep("Concord", 0, A)
    go("the Concord Core"); check_now()
end)
T.waitFor("ignore: a patrol spawns", function() return #groups() == 1 end, 5)
T.step("intercept", function()
    group = groups()[1]; ship = group.ships[1]
    close_in(); check_now()
end)
T.waitFor("ignore: the crew is hailed", function() return group.shakedown_hailed end, 4)
T.step("a minute of silence", function()
    rep0 = T.rep("Concord", A)
    group.last_comms_activity = now() - 61
    check_now()
end)
T.waitFor("ignore: the patrol turns hostile", function() return group.shakedown_hostile end, 3)
T.step("hostile", function()
    T.eq("ignore: standing -100", T.rep("Concord", A) - rep0, -100)
    T.eq("ignore: faction", ship:getFaction(), "Concord Hostile")
    T.check("ignore: an enemy now", ship:isEnemy(A))
    T.check("ignore: the stop is closed", group.shakedown_done)
    close_in()
end)
T.waitFor("combat jammer: a hostile Concord ship in range drops one", function()
    return group.cjam[1] ~= nil and RT.valid(group.cjam[1].jammer)
end, 3)
local first_jammer
T.step("one at a time", function()
    T.check("combat jammer: recorded against the ship that dropped it", group.cjam[1].ship == ship)
    T.eq("combat jammer: one per ship", #group.cjam, 1)
    first_jammer = group.cjam[1].jammer
    group.cjam[1].at = now() - PROX.JAMMER.lifetime - 1
end)
T.waitFor("combat jammer: it expires after two minutes", function() return not RT.valid(first_jammer) end, 3)
T.step("and the ship may drop the next", function()
    T.eq("combat jammer: still one record for the ship", #group.cjam, 1)
    T.check("combat jammer: a new one, the cooldown being over too", RT.valid(group.cjam[1].jammer) and group.cjam[1].jammer ~= first_jammer)
end)
T.step("wanted status cleared by the GM", function()
    PROX.clearWantedStatus()
    T.eq("clear: hostile Concord patrols removed", #groups(), 0)
    T.check("clear: the ship is gone", not RT.valid(ship))
    T.eq("clear: its combat jammers too", #group.cjam, 0)
end)

-- ── Concord: wanted ──────────────────────────────────────────────────────────
T.step("a wanted ship", function()
    set_rep("Concord", -300, A)
    go("the Concord Core"); check_now()
end)
T.waitFor("wanted: a patrol spawns", function() return #groups() == 1 end, 5)
T.step("no questions asked", function()
    group = groups()[1]; ship = group.ships[1]
    T.check("wanted: not a shake-down", not group.is_shakedown)
    T.eq("wanted: spawned hostile", ship:getFaction(), "Concord Hostile")
    T.check("wanted: an enemy", ship:isEnemy(A))
end)

-- ── Two ships: a second ship alone in a zone draws its own patrol ────────────
T.step("only the second ship in the Gauntlet", function()
    wipe()
    set_rep("Concord", 0, A)
    leave()
    place(B, "the Gauntlet")
    check_now()
end)
T.waitFor("two ships: a patrol spawns for the second ship", function() return #groups() == 1 end, 5)
T.step("it hunts the second ship", function()
    group = groups()[1]; ship = group.ships[1]
    T.eq("two ships: in the second ship's zone", group.region_name, "the Gauntlet")
    T.check("two ships: its target is the second ship", group.target == B)
    T.check("two ships: attacking the second ship", order_target(ship) == B)
    -- The primary ship joins it, then the second ship leaves.
    place(A, "the Gauntlet", 2 * U)
    park(B)
    check_now()
end)
T.waitFor("retarget: the patrol takes the ship still in the zone", function() return group.target == A end, 3)
T.step("on the primary ship now", function()
    T.check("retarget: not recalled", not group.recalled)
    T.check("retarget: attacking the primary ship", order_target(ship) == A)
    leave(); check_now()
end)
T.waitFor("retarget: recalled once no ship is left in the zone", function() return group.recalled end, 3)

-- ── Two ships in one zone draw one patrol per cooldown ───────────────────────
T.step("both ships in the Gauntlet, far apart", function()
    wipe()
    place(A, "the Gauntlet")
    local x, y = spot("the Gauntlet", _spots["the Gauntlet"])
    B:setPosition(x, y); B:setHeading(0)
    local ax, ay = A:getPosition()
    T.check("shared: the ships are in different grid cells", cell(x, y) ~= cell(ax, ay))
    check_now()
end)
T.waitFor("shared: a patrol spawns", function() return #groups() >= 1 end, 5)
T.wait(1)
T.step("only one", function()
    T.eq("shared: one patrol for the zone, not one per ship", #groups(), 1)
    local t = groups()[1].target
    T.check("shared: it hunts one of the two ships", t == A or t == B)
    check_now()
end)
T.wait(1)
T.step("still one while the zone is on cooldown", function()
    T.eq("shared: no second patrol before the cooldown is over", #groups(), 1)
    wipe(); park(B); leave()
end)

-- ── Two ships: a shake-down judges and fights only the ship it stopped ───────
local a_rep0, a_c0
T.step("the second ship alone in Concord space, with flags on its record", function()
    set_rep("Concord", 0, A)
    set_rep("Concord", -100, B)
    RT.setCredits(500, B)
    place(B, "the Concord Core")
    check_now()
end)
T.waitFor("judged: a patrol spawns for the second ship", function() return #groups() == 1 end, 5)
T.step("intercept the second ship", function()
    group = groups()[1]; ship = group.ships[1]
    T.check("judged: a shake-down (the second ship's -100, not the primary's)", group.is_shakedown)
    T.check("judged: its target is the second ship", group.target == B)
    close_in(B); check_now()
end)
T.waitFor("judged: the jammer is dropped on the second ship", function() return RT.valid(group.jammer) end, 3)
T.step("behind the second ship", function()
    local jx, jy = group.jammer:getPosition()
    local bx, by = B:getPosition()
    T.check("judged: the jammer is right behind the second ship", math.sqrt((jx - bx) ^ 2 + (jy - by) ^ 2) < 600)
    a_rep0, a_c0 = T.rep("Concord", A), T.credits(A)
    b_rep0 = T.rep("Concord", B)
end)
T.talk(function() return ship end, {}, {name = "the patrol (from the primary ship)"})
T.step("the primary ship is not part of the stop", function()
    T.check("judged: a bystander is told to keep clear", T.msg():find("not about you", 1, true) ~= nil, T.msg())
    T.check("judged: no fine offered to a bystander", not T.hasReply("Pay the fine"))
end)
T.closeComms()
T.actAs(function() return B end)
T.talk(function() return ship end, {"Confirmed. Standing by."}, {name = "the patrol"})
T.step("the second ship's record", function()
    T.check("judged: the fee is quoted to the second ship", T.msg():find("Inspection fee: 100 credits", 1, true) ~= nil, T.msg())
end)
T.talk(function() return ship end, {"Confirmed. Standing by.", "Refuse to pay", "[Acknowledge.]"}, {name = "the patrol"})
T.step("refused", function()
    T.check("refused: the patrol is hostile", group.shakedown_hostile)
    T.eq("refused: the second ship's standing -150", T.rep("Concord", B) - b_rep0, -150)
    T.eq("refused: the primary ship's standing untouched", T.rep("Concord", A), a_rep0)
    T.eq("refused: the primary ship paid nothing", T.credits(A), a_c0)
    T.check("refused: attacking the second ship", order_target(ship) == B)
end)
T.closeComms()
T.actAs(nil)
T.step("done with two ships", function()
    wipe(); park(B)
    set_rep("Concord", 0, B)
end)

-- ── The stopped ship is destroyed with no other ship in the zone: nobody is charged ──
local orphan_jammer
T.step("stop the second ship once more", function()
    set_rep("Concord", -100, B)
    reset_cooldowns()
    place(B, "the Concord Core")
    check_now()
end)
T.waitFor("orphaned: a patrol spawns for the second ship", function() return #groups() == 1 end, 5)
T.step("intercept", function()
    group = groups()[1]; ship = group.ships[1]
    T.check("orphaned: its target is the second ship", group.target == B)
    close_in(B); check_now()
end)
T.waitFor("orphaned: the second ship is hailed", function() return group.shakedown_hailed end, 4)
T.step("the second ship is destroyed mid-stop", function()
    a_rep0, a_c0 = T.rep("Concord", A), T.credits(A)
    orphan_jammer = group.jammer
    B:destroy()
    group.last_comms_activity = now() - 61   -- the compliance timeout would be due
    check_now()
end)
T.waitFor("orphaned: the stop is closed", function() return group.shakedown_done end, 3)
T.wait(1)
T.step("nobody is charged", function()
    T.check("orphaned: not hostile", not group.shakedown_hostile)
    T.check("orphaned: the jammer is removed", not RT.valid(orphan_jammer))
    T.check("orphaned: the patrol heads home", group.despawn_at ~= nil)
    T.eq("orphaned: the primary ship's standing untouched", T.rep("Concord", A), a_rep0)
    T.eq("orphaned: the primary ship paid nothing", T.credits(A), a_c0)
    wipe()
end)

-- ── A chase (an arc's robbery): a Concord patrol every 30 s ──────────────────
T.step("a wanted ship in the Core", function()
    wipe()
    set_rep("Concord", -300, A)
    go("the Concord Core"); check_now()
end)
T.waitFor("chase: the first patrol", function() return #groups() == 1 end, 5)
T.step("no chase: the zone's own cooldown holds", function()
    st.region_cd["the Concord Core"] = now() - 31
    check_now()
end)
T.wait(1)
T.step("chase on", function()
    T.eq("no chase: still one patrol after 31 s", #groups(), 1)
    PROX.chaseZone("the Concord Core", 30, 8)
    st.region_cd["the Concord Core"] = now() - 31
    check_now()
end)
T.waitFor("chase: a second patrol after 30 s, in the same grid cell", function() return #groups() == 2 end, 5)
T.step("chase off", function()
    PROX.endChase("the Concord Core")
    T.check("chase: ended", PROX._chase_zones["the Concord Core"] == nil)
    st.region_cd["the Concord Core"] = now() - 31
    check_now()
end)
T.wait(1)
T.step("back to normal", function()
    T.eq("chase over: no third patrol after 31 s", #groups(), 2)
    wipe()
    set_rep("Concord", 0, A)
end)

-- ── Switching the plugin off removes everything ──────────────────────────────
T.step("plugin off", function()
    WORLD.disable("proximity")
    T.check("off: the patrol is removed", not RT.valid(ship))
    set_rep("Concord", 0, A)
end)
