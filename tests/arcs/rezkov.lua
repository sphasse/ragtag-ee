-- Rezkov arc: Thresh -> Rezkov -> the Galen hack -> card to Thresh -> the Meridian -> Kael ->
-- report to Thresh (outcome data_delivered), then the destroyed and concord_won endings, the GM
-- states, and "-> Inactive". Not covered: a real Relay hack (the GM helper sets the level), the
-- fight with the Meridian (hull is set), the Meridian reaching the Arbiter Line, cover jobs.

T.arc("rezkov")

local function meridian() return T.st().meridian end
local c0, concord0, indep0

-- ── Hook: Thresh at Dustmote ─────────────────────────────────────────────────
T.step("hook", function()
    T.jump("rumors")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three hook rumors", T.rumors("REZKOV_HOOK"), 3)
end)
T.dock("Dustmote Salvage")
T.talk("Dustmote Salvage", {"Heard you were looking for an independent operator.", "Sure, what's the job?", "We'll head out."})
T.step("sent to the nebula", function()
    T.eq("m1: phase", T.phase(), "m1_navigate")
    T.check("m1: rezkov_hook set", T.flag("rezkov_hook"))
    T.eq("m1: hook rumors removed", T.rumors("REZKOV_HOOK"), 0)
    T.check("m1: Rezkov's station is out", RT.valid(T.st().waypoint))
    T.check("m1: Thresh profile known", SCIDB.known("thresh_profile"))
end)

-- ── M1: Rezkov only talks docked ─────────────────────────────────────────────
T.undock()
T.step("fly to Rezkov's station", function() T.moveNear(T.st().waypoint, 3000) end)
T.talk(function() return T.st().waypoint end, {})
T.step("undocked: told to dock", function()
    T.check("m1: no business at a distance", T.msg():find("dock", 1, true) ~= nil, T.msg())
    T.eq("m1: still navigating", T.phase(), "m1_navigate")
end)
T.dock(function() return T.st().waypoint end)
T.talk(function() return T.st().waypoint end, {"We're up for the challenge."})
T.step("Galen job accepted", function()
    T.eq("m2: phase", T.phase(), "m2_active")
    T.check("m2: rezkov_m1_done set", T.flag("rezkov_m1_done"))
    T.check("m2: Rezkov profile known", SCIDB.known("rezkov_profile"))
    T.check("m2: Galen found as the hack target", RT.valid(T.st().galen))
    T.eq("m2: objective", RT.objectives.main, "Hack Waypoint Galen")
end)

-- ── M2: the hack, then the card ──────────────────────────────────────────────
T.step("finish the hack", function() T.action("Complete hack") end)
T.waitFor("m2: a finished hack is noticed", function() return T.st().hack_done end, 3)
T.step("AI planted", function() T.check("m2: rezkov_ai_planted set (read by the Ledger arc)", T.flag("rezkov_ai_planted")) end)
T.waitFor("m2: card run starts a few seconds later", function() return T.phase() == "m2_deliver" end, 8)
T.dock("Dustmote Salvage")
T.step("note credits", function() c0 = T.credits() end)
T.talk("Dustmote Salvage", {"Delivery for Thresh.", "Sure."})
T.step("card delivered", function()
    T.eq("m3: phase", T.phase(), "m3_active")
    T.eq("m3: 600 cr for the card", T.credits() - c0, 600)
    T.check("m3: rezkov_m2_done set", T.flag("rezkov_m2_done"))
    T.check("m3: Rezkov's station has gone dark", T.find("Rezkov's station") == nil)
    T.check("m3: the Meridian is flying", RT.valid(meridian()))
    T.check("m3: not accepted yet", not T.flag("rezkov_m3_accepted"))
    T.check("m3: accept is on offer", T.hasReply("We're on it."), table.concat(T.replies(), " | "))
end)
T.step("accept the intercept", function()
    for i, l in ipairs(T.replies()) do
        if l:find("We're on it.", 1, true) then T.P():commandSendComm(i - 1) end
    end
    T.check("m3: rezkov_m3_accepted set", T.flag("rezkov_m3_accepted"))
end)

-- ── M3: disable, board, Kael ─────────────────────────────────────────────────
T.undock()
T.step("close on the Meridian", function() T.moveNear(meridian(), 3000) end)
T.waitFor("m3: she turns hostile inside 5U", function() return T.st().m3_hostile end, 3)
T.step("she is targetable; cripple her", function()
    T.eq("m3: faction when close", meridian():getFaction(), "Concord Hostile")
    T.action("Disable Meridian")
end)
T.waitFor("m3: a crippled Meridian surrenders", function() return T.st().m3_disabled end, 3)
T.step("disabled", function()
    T.eq("m3: disabled Meridian is no longer hostile", meridian():getFaction(), "Independent")
    T.eq("m3: objective", RT.objectives.main, "Board CWS Meridian")
end)
T.dock(meridian)
T.waitFor("m3: docking boards her", function() return T.st().m3_boarded end, 3)
T.step("note standing", function()
    T.check("m3: Kael profile known", SCIDB.known("kael_profile"))
    concord0 = T.rep("Concord")
end)
T.talk(meridian, {"Wipe the data."})
T.step("data wiped", function()
    T.check("kael: signs off without repeating herself", T.msg():find("Until we meet again, Magpie.", 1, true) ~= nil, T.msg())
    T.eq("m3_deliver: phase", T.phase(), "m3_deliver")
    T.check("m3_deliver: rezkov_m3_data set", T.flag("rezkov_m3_data"))
    T.eq("m3_deliver: kael_alive", T.flag("kael_alive"), true)
    T.eq("m3_deliver: Concord -1000", T.rep("Concord") - concord0, -1000)
end)
T.dock("Dustmote Salvage")
T.step("note standing", function() indep0 = T.rep("Independent") end)
T.talk("Dustmote Salvage", {"Thresh -- the Meridian data is wiped."})
T.step("arc complete", function()
    T.eq("done: status", T.status(), "done")
    T.eq("done: outcome", T.flag("rezkov_arc_done"), "data_delivered")
    T.eq("done: Independent +200", T.rep("Independent") - indep0, 200)
end)
T.closeComms()

-- ── Ending: the Meridian destroyed before boarding ───────────────────────────
T.step("intercept again, and destroy her", function()
    T.jump("intercept")
    T.eq("destroyed: back in m3_active", T.phase(), "m3_active")
    concord0 = T.rep("Concord")
    meridian():setCanBeDestroyed(true)
    meridian():destroy()
end)
T.waitFor("destroyed: the arc ends", function() return T.status() == "done" end, 3)
T.step("destroyed", function()
    T.eq("destroyed: outcome", T.flag("rezkov_arc_done"), "meridian_destroyed")
    T.eq("destroyed: kael_alive false", T.flag("kael_alive"), false)
    T.eq("destroyed: Concord -1000", T.rep("Concord") - concord0, -1000)
end)

-- ── Ending: let the Concord go ───────────────────────────────────────────────
T.step("intercept again, cripple her", function()
    T.jump("intercept")
    T.moveNear(meridian(), 3000)
    T.action("Disable Meridian")
end)
T.waitFor("concord_won: disabled", function() return T.st().m3_disabled end, 3)
T.dock(meridian)
T.waitFor("concord_won: boarded", function() return T.st().m3_boarded end, 3)
T.step("note standing", function() concord0, indep0 = T.rep("Concord"), T.rep("Independent") end)
T.talk(meridian, {"Let the Concord go.", "Understood."})
T.step("the Concord wins", function()
    T.eq("concord_won: status", T.status(), "done")
    T.eq("concord_won: outcome", T.flag("rezkov_arc_done"), "concord_won")
    T.eq("concord_won: Concord +500", T.rep("Concord") - concord0, 500)
    T.eq("concord_won: Independent -1000", T.rep("Independent") - indep0, -1000)
end)
T.closeComms()

-- ── GM states ────────────────────────────────────────────────────────────────
T.gmWalk({
    {key = "rumors",    phase = "hook", check = function()
        T.eq("GM rumors: hook rumors", T.rumors("REZKOV_HOOK"), 3)
        T.check("GM rumors: no station", T.find("Rezkov's station") == nil)
    end},
    {key = "meeting",   phase = "m1_navigate", check = function()
        T.check("GM meeting: station out", RT.valid(T.st().waypoint))
        T.check("GM meeting: hook replayed", T.flag("rezkov_hook"))
    end},
    {key = "hacking",   phase = "m2_active", check = function()
        T.check("GM hacking: m1 replayed", T.flag("rezkov_m1_done"))
        T.check("GM hacking: hack not done", not T.st().hack_done)
        T.eq("GM hacking: still hacking a second later", T.phase(), "m2_active")
        T.restart()
        T.eq("next session resumes the hack", T.phase(), "m2_active")
    end},
    {key = "cardrun",   phase = "m2_deliver", check = function()
        T.check("GM cardrun: AI planted replayed", T.flag("rezkov_ai_planted"))
        T.check("GM cardrun: station still up", RT.valid(T.st().waypoint))
    end},
    {key = "intercept", phase = "m3_active", check = function()
        T.check("GM intercept: Meridian out", RT.valid(meridian()))
        T.check("GM intercept: station gone", T.find("Rezkov's station") == nil)
        T.check("GM intercept: accepted", T.flag("rezkov_m3_accepted"))
    end},
    {key = "datarun",   phase = "m3_deliver", check = function()
        T.check("GM datarun: data flag", T.flag("rezkov_m3_data"))
        T.check("GM datarun: Kael profile known", SCIDB.known("kael_profile"))
        T.restart()
        T.eq("next session resumes the data run", T.phase(), "m3_deliver")
    end},
    {key = "done_concord",   done = true, check = function()
        T.eq("GM done_concord: outcome", T.flag("rezkov_arc_done"), "concord_won")
        T.eq("GM done_concord: kael_alive", T.flag("kael_alive"), true)
    end},
    {key = "done_data",      done = true, check = function()
        T.eq("GM done_data: outcome", T.flag("rezkov_arc_done"), "data_delivered")
    end},
    {key = "done_destroyed", done = true, check = function()
        T.eq("GM done_destroyed: outcome", T.flag("rezkov_arc_done"), "meridian_destroyed")
        T.eq("GM done_destroyed: kael_alive", T.flag("kael_alive"), false)
        T.check("GM done_destroyed: never met Kael", not SCIDB.known("kael_profile"))
    end},
    {key = "done_escaped",   done = true, check = function()
        T.eq("GM done_escaped: outcome", T.flag("rezkov_arc_done"), "meridian_escaped")
    end},
    {key = "inactive",  phase = "hook", check = function()
        T.check("GM inactive: suppressed by rezkov_declined", T.flag("rezkov_declined"))
        T.eq("GM inactive: no hook rumors", T.rumors("REZKOV_HOOK"), 0)
    end},
})

-- Rezkov's own "-> Inactive" parks the arc in the hook with rezkov_declined set.
T.deactivate({
    keep_flags = {"rezkov_declined"},
    gone = {"Rezkov's station", "CWS Meridian"},
    objective = "main",
    check = function()
        T.check("inactive: profiles forgotten", not SCIDB.known("thresh_profile") and not SCIDB.known("rezkov_profile"))
    end,
})
