-- Corsair arc: hook (Greywater message, defer, Gauntlet contact) -> escort -> briefing -> raid
-- (escort orders, a lost escort replaced, boarding) -> return (the mine ring thickened) -> battle
-- (frozen until the crew is near, then BATTLE rules; rearming from the tender) -> done (defended),
-- then the late-decline and crew-lost endings, the GM states, and "-> Inactive". Not covered: the
-- depot fight and the battle themselves (GM helpers remove the Concord ships), the guide waiting
-- for a slow crew.

T.arc("corsair")

local GAUNTLET_X, GAUNTLET_Y = 23000, 69000
local DEPOT_X, DEPOT_Y = -60000, 62000
local function guide() return T.st().guide end
local function escort() return T.st().escorts[1] end
local function hostileAt(cs) local e = T.find(cs) return e and e:getFaction() end
local corsairs0, concord0
local function minesOnMap() return T.countType("Mine", 36000, 97000, 40000) end
local mines0   -- the Gauntlet has minefields of its own

-- ── Hook: the barkeep's message ──────────────────────────────────────────────
T.step("hook", function()
    -- Phase II: the arc needs the Rezkov arc finished or declined (like Ledger and Boneyard).
    T.check("gate: not without Rezkov", not MISSIONS._checkTriggers("corsair"))
    T.check("gate: listed in the criteria",
        MISSIONS._criteriaText("corsair"):find("Rezkov arc finished or declined", 1, true) ~= nil)
    mines0 = minesOnMap()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three rumors point at Greywater", T.rumors("CORSAIR_HOOK"), 3)
    T.eq("hook: Blackwater is hostile", hostileAt("Blackwater"), "Corsairs")
end)
T.dock("Greywater Depot")
T.talk("Greywater Depot", {"Heard you're holding a message for us."})
T.step("the raider is waiting", function()
    T.check("hook: Long Memory staged at the Gauntlet's edge", RT.valid(guide()))
    T.eq("hook: objective", RT.objectives.corsair, "Meet Long Memory at the Gauntlet's edge")
    T.check("hook: no hail until the crew is close", not T.st().hook_hailed)
end)
T.closeComms()
T.undock()
T.step("fly out to meet them", function() T.moveNear(guide(), 3000) end)

-- ── "Not right now": the hook stays open, but not for 10 minutes ─────────────
T.talk(guide, {}, {answer = true, name = "Long Memory"})
T.step("the raider's pitch", function()
    T.check("hook: 'someone who is not intimidated by the Concord'",
        T.msg():find("we know you are someone who is not intimidated by the Concord.", 1, true) ~= nil, T.msg())
end)
T.talk(guide, {"Not right now."}, {name = "Long Memory"})
T.step("deferred", function()
    T.eq("defer: still the hook", T.phase(), "hook")
    T.check("defer: the raider leaves", guide() == nil)
    T.eq("defer: objective cleared", RT.objectives.corsair, nil)
    T.check("defer: re-ask delay set", (T.st().deferred_until or 0) > T.now() + 500)
end)
T.closeComms()
T.dock("Greywater Depot")
T.talk("Greywater Depot", {"Heard you're holding a message for us."})
T.step("the barkeep says wait", function()
    T.check("defer: Greywater does not re-offer yet", T.msg():find("weren't ready", 1, true) ~= nil, T.msg())
    T.check("defer: no raider staged", guide() == nil)
end)
T.closeComms()
T.step("into the Gauntlet during the delay", function() T.moveTo(GAUNTLET_X, GAUNTLET_Y) end)
T.wait(2)
T.step("no contact during the delay; then the delay passes", function()
    T.check("defer: the Gauntlet does not re-offer yet", guide() == nil)
    T.st().deferred_until = 0
end)

-- ── Gauntlet contact, "Lead the way" ─────────────────────────────────────────
T.waitFor("hook: entering the Gauntlet brings the raider", function() return RT.valid(guide()) end, 3)
T.talk(guide, {"Lead the way."}, {answer = true, name = "Long Memory"})
T.step("escorted in", function()
    T.eq("escort: phase", T.phase(), "escort")
    T.check("escort: corsair_hook set", T.flag("corsair_hook"))
    T.eq("escort: hook rumors removed", T.rumors("CORSAIR_HOOK"), 0)
    T.eq("escort: Blackwater turns friendly", hostileAt("Blackwater"), "Corsair Friendly")
    T.check("escort: Gauntlet patrols suspended", PROX._suspended_zones["the Gauntlet"])
    T.check("escort: Blackwater Reach patrols suspended", PROX._suspended_zones["Blackwater Reach"])
end)
T.closeComms()

-- ── Arrival: Long Memory hands over, then leaves once the crew docks ─────────
T.step("in sight of Blackwater", function() T.moveNear("Blackwater", 4000) end)
T.waitFor("escort: within 5U, Long Memory hails", function() return T.st().arrival_hailed end, 3)
T.talk(guide, {}, {answer = true, name = "Long Memory"})
T.step("handed over", function()
    T.check("escort: 'I got you here safe. Dock with Blackwater to meet Reva'",
        T.msg():find("I got you here safe. Dock with Blackwater to meet Reva and she'll fill you in.", 1, true) ~= nil, T.msg())
end)
T.closeComms()

-- ── Briefing ─────────────────────────────────────────────────────────────────
T.dock("Blackwater")
T.waitFor("briefing: docking at Blackwater moves on", function() return T.phase() == "briefing" end, 3)
T.step("Long Memory leaves", function()
    T.check("briefing: the guide is no longer escorting", T.st().guide == nil)
    T.check("briefing: it flies off (removed a minute later)", RT.valid(T.st().guide_leaving))
end)
T.talk("Blackwater", {})
T.step("Reva introduces herself", function()
    T.check("briefing: \"I'm Reva Okonkwo.\"", T.msg():find("I'm Reva Okonkwo.", 1, true) ~= nil, T.msg())
    T.check("briefing: \"... settle the account for good, and we need help.\"",
        T.msg():find("settle the account for good, and we need help.", 1, true) ~= nil, T.msg())
end)
T.talk("Blackwater", {"What do you need from us?"})
T.step("the depot", function()
    T.check("briefing: the depot line", T.msg():find("The Concord has provisioned a forward depot in preparation for their invasion of Blackwater", 1, true) ~= nil, T.msg())
end)
T.talk("Blackwater", {"What do you need from us?", "We'll take the depot."})
T.step("raid on", function()
    T.eq("raid: phase", T.phase(), "raid")
    T.check("raid: corsair_arrived and corsair_briefed set", T.flag("corsair_arrived") and T.flag("corsair_briefed"))
    T.check("raid: Reva profile known", SCIDB.known("reva_profile"))
    T.check("raid: depot out", RT.valid(T.st().depot))
    T.eq("raid: two guards", T.alive(T.st().defenders), 2)
    T.eq("raid: two escorts", T.alive(T.st().escorts), 2)
end)
T.closeComms()

-- ── Raid: an escort lost is replaced, and Reva says so ───────────────────────
local first_escort, first_name
T.step("lose an escort", function()
    first_escort, first_name = escort(), T.st().escort_cs[1]
    T.eq("raid: escorts are named", first_name, "Hardtack")
    first_escort:destroy()
end)
T.waitFor("raid: Reva sends another", function()
    return T.alive(T.st().escorts) == 2 and T.st().escorts[1] ~= first_escort
end, 3)
T.step("replaced", function()
    T.eq("raid: still the raid", T.phase(), "raid")
    T.eq("raid: guards untouched", T.alive(T.st().defenders), 2)
    local names = table.concat(T.st().escort_cs, ", ")
    T.check("raid: Ninth Life still flying", names:find("Ninth Life", 1, true) ~= nil, names)
    T.check("raid: a new ship, not Hardtack", not names:find("Hardtack", 1, true), names)
end)
T.talk("Blackwater", {}, {answer = true, name = "Reva (Blackwater)"})
T.step("Reva's word", function()
    local new = T.st().escort_cs[#T.st().escort_cs]
    T.check("raid: Reva names the lost ship and the new one",
        T.msg():find("We lost Hardtack. I'm sending " .. new .. " out to you.", 1, true) ~= nil, T.msg())
end)
T.closeComms()

-- ── Raid: the orders unlock in turn ──────────────────────────────────────────
T.undock()
T.talk(escort, {}, {name = "an escort"})
T.step("far from the depot: the three standing orders", function()
    T.check("raid: no CSR prefix on the escorts", not escort():getCallSign():find("CSR", 1, true), escort():getCallSign())
    T.check("raid: form up on offer", T.hasReply("Form up on me."))
    T.check("raid: head to the depot on offer", T.hasReply("Head to the depot."))
    T.check("raid: head back to Blackwater on offer", T.hasReply("Head back to Blackwater."))
    T.check("raid: hold position on offer", T.hasReply("Hold position."))
    T.check("raid: no attack order far from the depot", not T.hasReply("Attack the Concord defenders."))
    T.check("raid: no boarding order yet", not T.hasReply("Board the depot"))
    T.moveTo(DEPOT_X, DEPOT_Y + 4000)
    for i, s in ipairs(T.st().escorts) do s:setPosition(DEPOT_X + i * 800, DEPOT_Y + 4500) end
end)
T.talk(escort, {"Hold position."}, {name = "an escort"})
T.step("holding", function()
    local held = 0
    for _, s in ipairs(T.st().escorts) do
        local ok, ord = pcall(function() return s:getOrder() end)
        if ok and ord == "Stand Ground" then held = held + 1 end
    end
    T.eq("raid: both escorts hold position", held, 2)
end)
T.talk(escort, {"Attack the Concord defenders."}, {name = "an escort"})
T.step("attacking; then the guards go down", function()
    T.check("raid: escorts attacking", T.st().attacking)
    T.check("raid: no boarding while guards live", not T.hasReply("Board the depot"))
    T.action("Kill defenders")
end)
T.waitFor("raid: guards down is noticed", function() return T.st().defenders_down end, 3)
T.step("the depot surrenders", function()
    T.eq("raid: the depot turns neutral", T.st().depot:getFaction(), "Derelict")
    T.check("raid: the escorts are no enemies of it", not escort():isEnemy(T.st().depot))
end)
T.talk(escort, {"Board the depot and take the weapons."}, {name = "an escort"})
T.step("boarding", function()
    T.check("raid: escorts boarding", T.st().boarding)
    T.check("raid: loading has not started at 4U", not T.st().load_t0)
    for i, s in ipairs(T.st().escorts) do s:setPosition(DEPOT_X + i * 500, DEPOT_Y + 800) end
end)
T.waitFor("raid: loading starts alongside the depot", function() return T.st().load_t0 end, 3)
T.step("finish loading", function()
    T.eq("raid: not done until loaded", T.phase(), "raid")
    T.action("Finish loading")
end)
T.waitFor("return: the haul is loaded", function() return T.phase() == "return" end, 3)
T.step("haul loaded", function()
    T.check("return: corsair_raid_done set", T.flag("corsair_raid_done"))
    T.eq("return: no trap before the debrief", #T.st().mines, 0)
    -- The escorts head for the Blackwater approach (north of the ring), never inside the ring.
    local routed = 0
    for _, r in ipairs(T.st().routes or {}) do
        if math.abs(r.steps[1][1] - 55000) < 1 and math.abs(r.steps[1][2] - 87000) < 1 then routed = routed + 1 end
    end
    T.eq("return: both escorts sent to the Blackwater approach", routed, 2)
end)

-- ── Return: the haul's mines thicken Blackwater's ring ───────────────────────
local BW_X, BW_Y = 55000, 99000
T.dock("Blackwater")
T.talk("Blackwater", {})
T.step("the debrief", function()
    T.check("return: no jammers in the haul", not T.msg():lower():find("jammer", 1, true), T.msg())
    T.check("return: no mines for the crew's rack", not T.msg():find("your own rack", 1, true), T.msg())
    T.eq("return: the crew's rack takes no mines", T.P():getWeaponStorageMax("Mine"), 0)
    local mines = T.st().mines
    T.check("ring: the haul's mines are laid round Blackwater", #mines > 60, #mines)
    local out_of_band, in_lane, rmin, rmax = 0, 0, math.huge, 0
    for _, m in ipairs(mines) do
        local x, y = m:getPosition()
        local d = math.sqrt((x - BW_X) ^ 2 + (y - BW_Y) ^ 2)
        rmin, rmax = math.min(rmin, d), math.max(rmax, d)
        if d < 8000 or d > 10000 then out_of_band = out_of_band + 1 end
        local a = (math.deg(math.atan(y - BW_Y, x - BW_X)) + 90) % 360   -- heading: 0 = north
        for _, lane in ipairs({{0, 25}, {103.85, 6.9}, {256.15, 6.9}}) do
            if math.abs(((a - lane[1]) + 180) % 360 - 180) < lane[2] then in_lane = in_lane + 1 end
        end
    end
    T.eq("ring: about 9U out, like the old ring", out_of_band, 0)
    T.eq("ring: three lanes left open (north, east-south-east, west-south-west)", in_lane, 0)
    T.check("ring: laid in a hurry, not a perfect circle", rmax - rmin > 300, string.format("%.0f", rmax - rmin))
end)
T.talk("Blackwater", {"Good work.", "We'll stand with you."})
T.step("Reva's advice before the battle", function()
    T.check("battle: hack their big ships", T.msg():find("I've heard your hackers are second to none. If you can hack their big ships", 1, true) ~= nil, T.msg())
    T.check("battle: their missiles are limited", T.msg():find("once they run out they'll be sitting ducks", 1, true) ~= nil, T.msg())
    T.check("battle: then on to the line", T.hasReply("Understood. We're on our way."), table.concat(T.replies(), " | "))
end)
T.reply({"Understood. We're on our way."})
T.step("the rendezvous", function()
    T.check("battle: Reva gives the line's grid", T.msg():find("Our line is forming west of the ring", 1, true) ~= nil, T.msg())
end)
local killed_by = {}
T.step("the battle", function()
    local s = T.st()
    T.eq("battle: phase", T.phase(), "battle")
    T.check("battle: corsair_joined set", T.flag("corsair_joined"))
    T.eq("battle: seven Concord ships", T.alive(s.fleet), 7)
    T.eq("battle: twelve Corsairs", T.alive(s.allies), 12)
    T.check("battle: frozen until the crew comes near", not s.battle.started)
    T.eq("battle: frozen ships do not move", s.fleet[1]:getImpulseMaxSpeed(), 0)
    local cx, ax = s.fleet[1]:getPosition(), s.allies[1]:getPosition()
    T.check("battle: the Concord line 10U west of the points", math.abs(cx - 20000) < 100, cx)
    T.check("battle: the Corsair line 10U east, outside the ring", math.abs(ax - 40000) < 100, ax)
    local docking = 0
    for _, r in ipairs(s.routes or {}) do if r.dock then docking = docking + 1 end end
    T.eq("battle: the raid escorts go home and dock, sitting it out", docking, T.alive(s.escorts))
    for _, a in ipairs(s.allies) do
        local cs = a:getCallSign()
        RT.onKill(a, function(self, inst)
            local who = "?"
            pcall(function() who = inst:getCallSign() end)
            killed_by[#killed_by + 1] = cs .. " by " .. who
        end)
    end
    T.check("tender: Magazine behind the Corsair line", RT.valid(s.tender))
    T.eq("tender: friendly", s.tender:getFaction(), "Corsair Friendly")
    T.eq("tender: three loads aboard", s.reloads, 3)
    T.check("tender: no call while the racks are full", not s.low_called)
    T.moveTo(91000, 99000)   -- far from the Corsair line
end)
T.wait(1)
T.step("frozen while the crew is away", function()
    T.check("battle: not started yet", not T.st().battle.started)
    T.check("battle: no Corsair lost to a mine", T.alive(T.st().allies) == 12, table.concat(killed_by, "; "))
    -- Another ship coming up on the Concord line does not start the arc's battle.
    local k = T.secondShip()
    local fx, fy = T.st().fleet[1]:getPosition()
    k:setPosition(fx - 3000, fy)
end)
T.wait(1)
T.step("not for another ship", function()
    T.check("battle: another ship near the Concord line does not start it", not T.st().battle.started)
    T.secondShip():setPosition(VERSE.at("Port Vesper", -3, -3))
    -- The crew coming in from the west reaches the Concord line first.
    T.moveNear(T.st().fleet[1], 3000)
end)
T.waitFor("battle: starts once the crew is within 5U of any battle ship (here a Concord one)", function() return T.st().battle.started end, 3)
T.step("the battle begins", function()
    local s = T.st()
    local adder, atlantis
    for _, a in ipairs(s.allies) do if a:getTypeName() == "Adder MK5" then adder = a; break end end
    for _, f in ipairs(s.fleet) do if f:getTypeName() == "Atlantis X23" then atlantis = f; break end end
    T.check("battle: normalized speeds (Adder 120)", math.abs(adder:getImpulseMaxSpeed() - 120) < 0.5, adder:getImpulseMaxSpeed())
    T.check("battle: normalized speeds (Atlantis 80)", math.abs(atlantis:getImpulseMaxSpeed() - 80) < 0.5, atlantis:getImpulseMaxSpeed())
    T.check("battle: no warp", not atlantis:hasWarpDrive() and not adder:hasWarpDrive())
    local per = {0, 0, 0, 0, 0}
    for _, r in ipairs(s.battle.sides.b) do if r.pos then per[r.pos] = per[r.pos] + 1 end end
    T.eq("battle: Corsairs mapped onto the five points, north to south", table.concat(per, "/"), "2/3/2/3/2")
    T.check("battle: objective", (RT.objectives.corsair or ""):find("Destroy Battle Group Two", 1, true) ~= nil, tostring(RT.objectives.corsair))
end)

-- ── Rearming from the tender ─────────────────────────────────────────────────
local function empty_racks()
    local p = T.P()
    for _, w in ipairs({"Homing", "HVLI", "Mine", "EMP"}) do p:setWeaponStorage(w, 0) end
end
local function racks_full()
    local p = T.P()
    for _, w in ipairs({"Homing", "HVLI", "Mine", "EMP"}) do
        if p:getWeaponStorage(w) < p:getWeaponStorageMax(w) then return false end
    end
    return true
end
T.step("the crew fires off its missiles", function()
    T.check("tender: the crew carries missiles", T.P():getWeaponStorageMax("Homing") + T.P():getWeaponStorageMax("HVLI") > 0)
    empty_racks()
end)
T.waitFor("tender: running low brings a call", function() return T.st().low_called end, 3)
T.step("called in", function()
    T.check("tender: a rearm objective with its grid", (RT.objectives["corsair_rearm"] or ""):find("Magazine", 1, true) ~= nil,
        tostring(RT.objectives["corsair_rearm"]))
    T.moveNear(T.st().tender, 800)
end)
T.waitFor("tender: alongside starts the transfer", function() return T.st().reload_t0 ~= nil end, 3)
T.step("eight seconds alongside", function() T.st().reload_t0 = T.now() - 8 end)
T.waitFor("tender: the racks are full", racks_full, 3)
T.step("reloaded", function()
    local s = T.st()
    T.eq("tender: one load used", s.reloads, 2)
    T.check("tender: the objective is cleared", RT.objectives["corsair_rearm"] == nil)
    T.check("tender: ready to call again", not s.low_called)
    s.reloads = 0
    empty_racks()
end)
T.wait(2)
T.step("the haul is gone", function()
    local s = T.st()
    T.check("tender: no call once the haul is gone", not s.low_called)
    T.check("tender: no transfer either", s.reload_t0 == nil)
    T.eq("tender: the racks stay empty", T.P():getWeaponStorage("Homing"), 0)
end)
T.talk(function() return T.st().tender end, {}, {name = "Magazine"})
T.step("the tender says so", function()
    T.check("tender: 'the haul is gone'", T.msg():find("haul is gone", 1, true) ~= nil, T.msg())
end)
T.closeComms()
T.step("the last Concord ships go down (Corsair standing below zero)", function()
    RT.addReputation("Corsairs", -100 - T.rep("Corsairs"), "test")
    concord0 = T.rep("Concord")
    T.action("Kill fleet")
end)
T.waitFor("done: the last Concord ship ends the battle", function() return T.status() == "done" end, 3)
T.step("defended", function()
    T.eq("defended: outcome", T.flag("corsair_arc_done"), "defended")
    T.check("defended: no rearm objective left", RT.objectives["corsair_rearm"] == nil)
    T.check("defended: corsair_ally and battlegroup flags", T.flag("corsair_ally") and T.flag("corsair_battlegroup_destroyed"))
    T.eq("defended: Corsair standing up to +500 from below zero", T.rep("Corsairs"), 500)
    T.eq("defended: Concord -300", T.rep("Concord") - concord0, -300)
    T.eq("defended: Blackwater stays friendly", hostileAt("Blackwater"), "Corsair Friendly")
    T.eq("defended: one aftermath rumor", T.rumors("CORSAIR_DONE"), 1)
    local home = 0
    for _, r in ipairs(T.st().routes or {}) do
        if not r.dock and math.abs(r.steps[1][1] - 55000) < 1 and math.abs(r.steps[1][2] - 87000) < 1 then home = home + 1 end
    end
    T.eq("defended: the surviving Corsairs head for Blackwater", home, T.alive(T.st().allies))
    local cleanup
    for _, tm in ipairs(RT.timers) do if tm.name:find("cleanup", 1, true) then cleanup = tm.at - T.now() end end   -- the arc's cleanup timer
    T.check("defended: they are removed after 5 minutes", cleanup and cleanup > 290 and cleanup <= 300, tostring(cleanup))
end)
T.talk("Blackwater", {}, {answer = true, name = "Blackwater's victory hail"})
T.step("Blackwater's thanks", function()
    T.check("defended: the victory hail", T.msg():find("The Concord battle group is destroyed! Victory is ours, but at a great cost.", 1, true) ~= nil, T.msg())
    T.check("defended: it names the crew's ship", T.msg():find("Safe flying and see you around, " .. T.P():getCallSign() .. "!", 1, true) ~= nil, T.msg())
end)
T.closeComms()

-- ── Ending: declining the battle counts as failed ───────────────────────────
T.step("back to the debrief", function()
    T.jump("return")
    T.eq("late decline: return", T.phase(), "return")
    T.check("late decline: ally flag cleared by the jump", not T.flag("corsair_ally"))
end)
T.dock("Blackwater")
T.talk("Blackwater", {"Good work.", "This isn't our fight."})
T.step("walked away", function()
    T.eq("late decline: status", T.status(), "done")
    T.eq("late decline: outcome failed", T.flag("corsair_arc_done"), "failed")
    T.eq("late decline: Blackwater hostile again", hostileAt("Blackwater"), "Corsairs")
    T.check("late decline: patrols resume", not PROX._suspended_zones["the Gauntlet"])
end)
T.closeComms()

-- ── Ending: the crew's ship is lost (nothing else fails it) ─────────────────
local lost_tender
T.step("back to the battle; the Corsairs are all lost", function()
    T.jump("battle")
    for _, a in ipairs(T.st().allies) do a:destroy() end
    RT.emit("ship_lost", {ship = "Kestrel", primary = false}, "high")
end)
T.wait(1)
T.step("still fighting", function()
    T.eq("crew lost: losing every Corsair is not defeat", T.phase(), "battle")
    T.eq("crew lost: nor is another ship's loss", T.status(), "active")
    lost_tender = T.st().tender
    T.check("crew lost: the tender is out", RT.valid(lost_tender))
    RT.emit("ship_lost", {ship = RT.campaign.ship_name, primary = true}, "high")
end)
T.step("lost", function()
    T.eq("crew lost: the arc ends", T.status(), "done")
    T.eq("crew lost: outcome failed", T.flag("corsair_arc_done"), "failed")
    T.check("crew lost: no ally flag", not T.flag("corsair_ally"))
    T.eq("crew lost: the arc's own tender keeps its colours", RT.valid(lost_tender) and lost_tender:getFaction(), "Corsair Friendly")
end)

-- ── Victory again, the Corsairs already friendly: +500 on top ─────────────────
T.step("back to the battle, Corsair standing +200", function()
    T.jump("battle")
    RT.addReputation("Corsairs", 200 - T.rep("Corsairs"), "test")
    T.action("Kill fleet")
end)
T.waitFor("again: defended", function() return T.status() == "done" end, 3)
T.step("+500 on top", function()
    T.eq("again: Corsair standing +200 -> +700", T.rep("Corsairs"), 700)
end)
T.closeComms()

-- ── GM states ────────────────────────────────────────────────────────────────
T.gmWalk({
    {key = "hook",     phase = "hook", check = function()
        T.eq("GM hook: Blackwater hostile", hostileAt("Blackwater"), "Corsairs")
        T.eq("GM hook: no mines left", #T.st().mines, 0)
    end},
    {key = "escort",   phase = "escort", check = function()
        -- Still docked at Blackwater, the arc moves straight on to the briefing and Long Memory leaves.
        T.check("GM escort: guide out (or already leaving)", RT.valid(guide()) or RT.valid(T.st().guide_leaving))
        T.eq("GM escort: Blackwater friendly", hostileAt("Blackwater"), "Corsair Friendly")
    end},
    {key = "briefing", phase = "briefing"},
    {key = "raid",     phase = "raid", check = function()
        T.check("GM raid: depot, guards, escorts", RT.valid(T.st().depot) and T.alive(T.st().defenders) == 2 and T.alive(T.st().escorts) == 2)
        T.check("GM raid: Reva met", SCIDB.known("reva_profile"))
        T.restart()
        T.eq("next session resumes the raid", T.phase(), "raid")
        T.eq("next session: Blackwater still friendly", hostileAt("Blackwater"), "Corsair Friendly")
    end},
    {key = "return",   phase = "return", check = function()
        T.check("GM return: raid flag replayed", T.flag("corsair_raid_done"))
        T.restart()
        T.eq("next session resumes at the debrief", T.phase(), "return")
    end},
    {key = "battle",   phase = "battle", check = function()
        T.check("GM battle: the ring is thickened", #T.st().mines > 60)
        T.eq("GM battle: the Concord line is out", T.alive(T.st().fleet), 7)
    end},
    {key = "done_def",  done = true, check = function()
        T.eq("GM done_def: outcome", T.flag("corsair_arc_done"), "defended")
        T.eq("GM done_def: Blackwater friendly", hostileAt("Blackwater"), "Corsair Friendly")
    end},
    {key = "done_fail", done = true, check = function()
        T.eq("GM done_fail: outcome", T.flag("corsair_arc_done"), "failed")
        T.eq("GM done_fail: Blackwater hostile", hostileAt("Blackwater"), "Corsairs")
    end},
    {key = "done_decl", done = true, check = function()
        T.eq("GM done_decl: outcome", T.flag("corsair_arc_done"), "declined")
        T.check("GM done_decl: never met Reva", not SCIDB.known("reva_profile"))
    end},
})

T.deactivate({
    gone = {"Long Memory", "Forward Depot Anvil", "CNS Warden", "Hardtack", "CNS Retribution", "Long Odds", "Hearthstone"},
    check = function()
        T.eq("inactive: Blackwater hostile", hostileAt("Blackwater"), "Corsairs")
        T.check("inactive: patrols resume", not PROX._suspended_zones["the Gauntlet"] and not PROX._suspended_zones["Blackwater Reach"])
        -- "<=": ships moving through the Gauntlet during the test can set off one of its own mines.
        T.check("inactive: no wall mines left on the map", minesOnMap() <= mines0, minesOnMap() .. " now, " .. tostring(mines0) .. " before")
        T.eq("inactive: no rumors", T.rumors("CORSAIR_HOOK") + T.rumors("CORSAIR_DONE"), 0)
    end,
})
