-- Ledger arc: hook -> meet -> relay_run -> carry -> done (full), then both loss paths, the GM
-- states, and "-> Inactive". Not covered: the 60 s fleet timer (forced), a real dock.

T.arc("ledger")

local c0, concord0, indep0

-- ── Hook: rumors, then Thresh at Dustmote ────────────────────────────────────
T.step("hook", function()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three hook rumors", T.rumors("LEDGER_HOOK"), 3)
end)
T.dock("Dustmote Salvage")
T.talk("Dustmote Salvage", {"Heard someone here was asking about us."})
T.step("Thresh sends the crew on", function()
    T.eq("meet: phase", T.phase(), "meet")
    T.check("meet: ledger_thresh set", T.flag("ledger_thresh"))
    T.eq("meet: hook rumors removed", T.rumors("LEDGER_HOOK"), 0)
    T.check("meet: Rezkov's station is out", RT.valid(T.st().station))
    T.check("meet: Thresh profile known", SCIDB.known("thresh_profile"))
end)

-- ── Meet: the briefing needs a dock ──────────────────────────────────────────
T.undock()
T.step("fly to Rezkov's station", function() T.moveNear(T.st().station, 3000) end)
T.talk(function() return T.st().station end, {})
T.step("undocked: told to dock", function()
    T.check("meet: no briefing at a distance", T.msg():find("Dock", 1, true) ~= nil, T.msg())
    T.eq("meet: still in meet", T.phase(), "meet")
end)
T.dock(function() return T.st().station end)
T.talk(function() return T.st().station end, {"Where are the fragments?", "We'll bring it home."})
T.step("job accepted", function()
    T.eq("relay_run: phase", T.phase(), "relay_run")
    T.check("relay_run: ledger_accepted set", T.flag("ledger_accepted"))
    T.eq("relay_run: three data cores", T.alive(T.st().frags), 3)
    T.check("relay_run: Rezkov profile known", SCIDB.known("rezkov_profile"))
    T.check("relay_run: objective counts fragments", tostring(RT.objectives.ledger):find("0/3", 1, true) ~= nil, RT.objectives.ledger)
end)

-- ── Relay run: one real pickup, two given ────────────────────────────────────
T.step("fly into the first data core", function() T.moveTo(-172000, -70000) end)
T.waitFor("relay_run: flying into a core picks it up", function() return T.flag("ledger_frag_1") end, 8)
T.step("the other two", function()
    T.eq("relay_run: still collecting", T.phase(), "relay_run")
    T.action("Give fragment")
    T.action("Give fragment")
    T.eq("carry: phase after the third fragment", T.phase(), "carry")
    T.check("carry: drain on", T.st().drain_on)
    T.check("carry: the AI has a voice", RT.voice.exists("ledger_ai"))
    T.eq("carry: no cores left", T.alive(T.st().frags), 0)
end)

-- ── Carry: drain, fleet, jammers ─────────────────────────────────────────────
local e0
T.step("note energy", function() e0 = T.P():getEnergy() end)
T.wait(3)
T.step("energy drains", function()
    local used = e0 - T.P():getEnergy()
    T.check("carry: about 5 energy/s drained", used > 8 and used < 40, string.format("%.1f in 3s", used))
    T.st().fleet_due = 0   -- do not wait out the 60 s
end)
T.waitFor("carry: audit fleet arrives", function() return T.st().fleet_spawned end, 5)
T.step("fleet", function()
    local f = T.st().fleet
    T.eq("carry: three audit ships", T.alive(f), 3)
    T.eq("carry: fleet is hostile", f[1]:getFaction(), "Concord Hostile")
    local d = RT.dist(T.P(), f[1])
    T.check("carry: fleet spawns about 7U out", d > 5500 and d < 8500, string.format("%.0f", d))
    T.moveNear(f[1], 3000)
end)
T.waitFor("carry: a hostile audit ship drops a warp jammer", function()
    local x, y = T.P():getPosition()
    return T.countType("WarpJammer", x, y, 3000) > 0
end, 10)
T.talk(function() return T.st().fleet[1] end, {"Not today."})
T.step("refusing changes nothing", function() T.eq("carry: still carrying", T.phase(), "carry") end)

-- ── Deliver ──────────────────────────────────────────────────────────────────
T.step("refill and fly home", function()
    T.P():setEnergyLevel(T.P():getMaxEnergy())
    T.moveNear(T.st().station, 3000)
end)
T.dock(function() return T.st().station end)
T.step("note credits and standing", function()   -- here, not earlier: new regions pay survey credits
    c0, concord0, indep0 = T.credits(), T.rep("Concord"), T.rep("Independent")
end)
T.talk(function() return T.st().station end, {"Hand over the AI."})
T.step("delivered", function()
    T.eq("done: status", T.status(), "done")
    T.eq("done: outcome full", T.flag("ledger_arc_done"), "full")
    T.check("done: evidence flag", T.flag("ledger_evidence"))
    T.check("done: drain off", not T.st().drain_on)
    T.check("done: the Containment Ledger is readable", SCIDB._locked.ledger_findings and SCIDB._locked.ledger_findings.unlocked)
    T.eq("done: 600 cr", T.credits() - c0, 600)
    T.eq("done: Concord -200", T.rep("Concord") - concord0, -200)
    T.eq("done: Independent +200", T.rep("Independent") - indep0, 200)
    T.eq("done: objective cleared", RT.objectives.ledger, nil)
    local line
    for _, a in ipairs(STATS.summary().arcs) do if a.id == "ledger" then line = a end end
    T.check("done: statistics report lists the arc as completed", line and line.status == "completed" and line.name == "Ledger Arc",
        line and line.status)
end)
T.closeComms()

-- ── Loss: the reactor hits zero ──────────────────────────────────────────────
T.step("back to carry, drain the reactor", function()
    T.jump("carry")
    T.eq("replay: carry", T.phase(), "carry")
    T.check("replay: evidence gone", not T.flag("ledger_evidence"))
    T.check("replay: the Ledger is locked again", not SCIDB._locked.ledger_findings.unlocked)
    c0 = T.credits()
    T.P():setEnergyLevel(1)
end)
T.waitFor("lost: zero energy ends the arc", function() return T.status() == "done" end, 5)
T.step("lost to power", function()
    T.eq("lost: outcome", T.flag("ledger_arc_done"), "lost")
    T.eq("lost: reason power", T.flag("ledger_lost_reason"), "power")
    T.check("lost: no evidence", not T.flag("ledger_evidence"))
    T.eq("lost: no payout", T.credits(), c0)
    T.P():setEnergyLevel(T.P():getMaxEnergy())
end)

-- ── Loss: surrender to the auditors ──────────────────────────────────────────
T.step("back to carry, bring the fleet", function()
    T.jump("carry")
    T.action("Fleet now")
    T.eq("surrender: fleet out", T.alive(T.st().fleet), 3)
end)
T.talk(function() return T.st().fleet[1] end, {"Transmit the data."})
T.step("surrendered", function()
    T.eq("surrender: status", T.status(), "done")
    T.eq("surrender: outcome", T.flag("ledger_arc_done"), "lost")
    T.eq("surrender: reason", T.flag("ledger_lost_reason"), "surrender")
    T.eq("surrender: fleet stands down", T.st().fleet[1]:getFaction(), "Concord")
    T.P():setEnergyLevel(T.P():getMaxEnergy())
end)
T.closeComms()

-- ── GM states ────────────────────────────────────────────────────────────────
T.gmWalk({
    {key = "hook",      phase = "hook"},
    {key = "meet",      phase = "meet", check = function()
        T.check("GM meet: station out", RT.valid(T.st().station))
        T.check("GM meet: thresh flag replayed", T.flag("ledger_thresh"))
        T.restart()
        T.eq("next session resumes at the meeting", T.phase(), "meet")
    end},
    {key = "relay_run", phase = "relay_run", check = function()
        T.eq("GM relay_run: three cores", T.alive(T.st().frags), 3)
        T.check("GM relay_run: accepted replayed", T.flag("ledger_accepted"))
        T.restart()
        T.eq("next session resumes the relay run", T.phase(), "relay_run")
        T.eq("next session: cores are back out", T.alive(T.st().frags), 3)
    end},
    {key = "carry",     phase = "carry", check = function()
        T.check("GM carry: fragments replayed", T.flag("ledger_frag_3"))
        T.check("GM carry: drain on", T.st().drain_on)
        T.P():setEnergyLevel(T.P():getMaxEnergy())
    end},
    {key = "done_full", done = true, check = function()
        T.eq("GM done_full: outcome", T.flag("ledger_arc_done"), "full")
        T.check("GM done_full: Ledger readable", SCIDB._locked.ledger_findings.unlocked)
    end},
    {key = "done_lost", done = true, check = function()
        T.eq("GM done_lost: outcome", T.flag("ledger_arc_done"), "lost")
        T.check("GM done_lost: Ledger locked", not SCIDB._locked.ledger_findings.unlocked)
    end},
})

T.deactivate({
    gone = {"Rezkov's station", "CAS Double Entry", "CAS Debit", "Data core"},
    check = function()
        T.check("inactive: AI voice gone", not RT.voice.exists("ledger_ai"))
        T.check("inactive: Thresh profile forgotten", not SCIDB.known("thresh_profile"))
    end,
})
