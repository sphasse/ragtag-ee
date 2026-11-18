-- Corsair arc: hook (Greywater message, defer, Gauntlet contact) -> escort -> briefing -> raid
-- (escort orders, both-lost restart, boarding) -> return -> battle (rearming from the tender) -> done (defended), then the
-- late-decline and Blackwater-falls endings, the GM states, and "-> Inactive". Not covered: the
-- depot fight and the battle themselves (GM helpers remove the Concord ships), the fleet threading
-- the gap, the guide waiting for a slow crew.

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
T.talk(guide, {"Not right now."}, {answer = true, name = "Long Memory"})
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

-- ── Briefing ─────────────────────────────────────────────────────────────────
T.dock("Blackwater")
T.waitFor("briefing: docking at Blackwater moves on", function() return T.phase() == "briefing" end, 3)
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

-- ── Raid: both escorts lost restarts it ──────────────────────────────────────
local first_escort
T.step("lose both escorts", function()
    first_escort = escort()
    for _, s in ipairs(T.st().escorts) do s:destroy() end
end)
T.waitFor("raid: Reva sends two more", function() return T.alive(T.st().escorts) == 2 end, 3)
T.step("restarted", function()
    T.eq("raid: still the raid", T.phase(), "raid")
    T.check("raid: fresh escorts", escort() ~= first_escort)
    T.eq("raid: guards re-crewed", T.alive(T.st().defenders), 2)
end)

-- ── Raid: the orders unlock in turn ──────────────────────────────────────────
T.undock()
T.talk(escort, {}, {name = "an escort"})
T.step("far from the depot: form up only", function()
    T.check("raid: form up on offer", T.hasReply("Form up on me."))
    T.check("raid: no attack order far from the depot", not T.hasReply("Attack the Concord defenders."))
    T.check("raid: no boarding order yet", not T.hasReply("Board the depot"))
    T.moveTo(DEPOT_X, DEPOT_Y + 4000)
    for i, s in ipairs(T.st().escorts) do s:setPosition(DEPOT_X + i * 800, DEPOT_Y + 4500) end
end)
T.talk(escort, {"Attack the Concord defenders."}, {name = "an escort"})
T.step("attacking; then the guards go down", function()
    T.check("raid: escorts attacking", T.st().attacking)
    T.check("raid: no boarding while guards live", not T.hasReply("Board the depot"))
    T.action("Kill defenders")
end)
T.waitFor("raid: guards down is noticed", function() return T.st().defenders_down end, 3)
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
end)

-- ── Return and the wall ──────────────────────────────────────────────────────
T.dock("Blackwater")
T.talk("Blackwater", {"Good work.", "We'll hold the wall with you."})
T.step("the battle", function()
    local s = T.st()
    T.eq("battle: phase", T.phase(), "battle")
    T.check("battle: corsair_joined set", T.flag("corsair_joined"))
    T.eq("battle: six Concord ships", T.alive(s.fleet), 6)
    T.eq("battle: two trap jammers", T.alive(s.trap_jammers), 2)
    T.check("battle: four allies plus raid survivors", T.alive(s.allies) == 4 and T.alive(s.escorts) == 2)
    T.eq("battle: four mines in the crew's rack", T.P():getWeaponStorage("Mine"), 4)
    -- The wall: neighbours never more than 0.7U apart (a mine triggers at 0.6U), except the gap.
    local worst, gaps = 0, 0
    for i = 2, #s.mines do
        local x1, y1 = s.mines[i - 1]:getPosition()
        local x2, y2 = s.mines[i]:getPosition()
        local d = math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
        if d > 2500 then gaps = gaps + 1 elseif d > worst then worst = d end
    end
    T.check("battle: a wall of mines", #s.mines > 60, #s.mines)
    T.check("battle: no hole in the wall over 0.7U", worst <= 700, string.format("%.0f", worst))
    T.eq("battle: exactly one gap", gaps, 1)
    T.eq("battle: wall mines use the narrow AI avoid range", s.mines[1].components.avoid_object.range, 800)
    T.check("tender: CSR Magazine behind the wall", RT.valid(s.tender))
    T.eq("tender: friendly", s.tender:getFaction(), "Corsair Friendly")
    T.eq("tender: three loads aboard", s.reloads, 3)
    T.check("tender: no call while the racks are full", not s.low_called)
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
    T.check("tender: a rearm objective with its grid", (RT.objectives["corsair_rearm"] or ""):find("CSR Magazine", 1, true) ~= nil,
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
T.talk(function() return T.st().tender end, {}, {name = "CSR Magazine"})
T.step("the tender says so", function()
    T.check("tender: 'the haul is gone'", T.msg():find("haul is gone", 1, true) ~= nil, T.msg())
    corsairs0, concord0 = T.rep("Corsairs"), T.rep("Concord")
    T.action("Kill fleet")
end)
T.waitFor("done: the last Concord ship ends the battle", function() return T.status() == "done" end, 3)
T.step("defended", function()
    T.eq("defended: outcome", T.flag("corsair_arc_done"), "defended")
    T.check("defended: no rearm objective left", RT.objectives["corsair_rearm"] == nil)
    T.check("defended: corsair_ally and battlegroup flags", T.flag("corsair_ally") and T.flag("corsair_battlegroup_destroyed"))
    T.eq("defended: Corsairs +400", T.rep("Corsairs") - corsairs0, 400)
    T.eq("defended: Concord -300", T.rep("Concord") - concord0, -300)
    T.eq("defended: Blackwater stays friendly", hostileAt("Blackwater"), "Corsair Friendly")
    T.eq("defended: trap jammers removed at once", T.alive(T.st().trap_jammers), 0)
    T.eq("defended: one aftermath rumor", T.rumors("CORSAIR_DONE"), 1)
end)
T.closeComms()

-- ── Ending: declining at the wall counts as failed ───────────────────────────
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

-- ── Ending: Blackwater falls ─────────────────────────────────────────────────
T.step("back to the battle; Blackwater takes a beating", function()
    T.jump("battle")
    local bw = T.find("Blackwater")
    bw:setHull(bw:getHullMax() * 0.1)
end)
T.waitFor("failed: Blackwater under 20% hull ends the battle", function() return T.status() == "done" end, 3)
T.step("fallen", function()
    T.eq("failed: outcome", T.flag("corsair_arc_done"), "failed")
    T.check("failed: no ally flag", not T.flag("corsair_ally"))
    local bw = T.find("Blackwater")
    T.check("failed: Blackwater survives as a station", RT.valid(bw))
    bw:setHull(bw:getHullMax())
end)

-- ── GM states ────────────────────────────────────────────────────────────────
T.gmWalk({
    {key = "hook",     phase = "hook", check = function()
        T.eq("GM hook: Blackwater hostile", hostileAt("Blackwater"), "Corsairs")
        T.eq("GM hook: no mines left", #T.st().mines, 0)
    end},
    {key = "escort",   phase = "escort", check = function()
        T.check("GM escort: guide out", RT.valid(guide()))
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
        T.eq("GM battle: fleet out", T.alive(T.st().fleet), 6)
        T.check("GM battle: wall built", #T.st().mines > 60)
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
    gone = {"Long Memory", "Forward Depot Anvil", "CNS Warden", "CSR Hardtack", "CNS Retribution", "CSR Long Odds", "Hearthstone"},
    check = function()
        T.eq("inactive: Blackwater hostile", hostileAt("Blackwater"), "Corsairs")
        T.check("inactive: patrols resume", not PROX._suspended_zones["the Gauntlet"] and not PROX._suspended_zones["Blackwater Reach"])
        -- "<=": ships moving through the Gauntlet during the test can set off one of its own mines.
        T.check("inactive: no wall mines left on the map", minesOnMap() <= mines0, minesOnMap() .. " now, " .. tostring(mines0) .. " before")
        T.eq("inactive: no rumors", T.rumors("CORSAIR_HOOK") + T.rumors("CORSAIR_DONE"), 0)
    end,
})
