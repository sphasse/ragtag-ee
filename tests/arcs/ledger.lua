-- Ledger arc: hook -> meet -> relay_run -> carry -> done (full), then both loss paths, the GM
-- states, and "-> Inactive". Not covered: the 60 s fleet timer (forced), a real dock.

T.arc("ledger")

local c0, concord0, indep0

-- ── The gate: three board jobs after the Rezkov arc ──────────────────────────
-- The Rezkov arc ends at Dustmote, where this hook lives: the arc waits until the primary ship has
-- finished three board jobs since then (story contracts do not count).
local gate = MISSIONS._registry.ledger.triggers.custom
local function finishJob(story)
    local m = T.makeJob("delivery", "Port Vesper")
    m.story = story or nil
    JOBS.accept(m, true)
    JOBS.complete(T.activeEntry(m))
end
T.step("the gate", function()
    T.check("gate: closed while Rezkov is unfinished", not gate())
    RT.flag("rezkov_arc_done", "data_delivered")
    T.check("gate: closed right after Rezkov", not gate())
    T.check("gate: the job count is noted", RT.flag("ledger_jobs_base") ~= nil)
    finishJob(); finishJob()
    T.check("gate: two jobs are not enough", not gate())
    finishJob(true)
    T.check("gate: a story contract does not count", not gate())
    finishJob()
    T.check("gate: open after the third board job", gate())
    T.check("gate: listed in the criteria",
        MISSIONS._criteriaText("ledger"):find("3 board jobs done by the primary ship", 1, true) ~= nil)
    RT.clearFlag("rezkov_arc_done")
    T.check("gate: closed again if Rezkov is rewound", not gate())
    T.check("gate: and the count is forgotten", RT.flag("ledger_jobs_base") == nil)
end)

-- ── Hook: rumors, then Thresh at Dustmote ────────────────────────────────────
T.step("hook", function()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three hook rumors", T.rumors("LEDGER_HOOK"), 3)
end)
-- Arcs belong to the primary ship. Another crew docked at Dustmote is not offered the lead.
T.actAs(T.secondShip)
T.dock("Dustmote Salvage")
T.talk("Dustmote Salvage", {})
T.step("a second ship gets the ordinary station menu", function()
    T.check("other ship: station answers", T.hasReply("Any work available?"), table.concat(T.replies(), " | "))
    T.check("other ship: no arc lead on offer", not T.hasReply("Heard someone here was asking about us."))
    T.eq("other ship: arc unmoved", T.phase(), "hook")
end)
T.actAs(nil)

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
local e0, other_e0
T.step("note energy", function()
    e0 = T.P():getEnergy()
    T.secondShip():setEnergyLevel(500)
    other_e0 = T.secondShip():getEnergy()
end)
T.wait(3)
T.step("energy drains", function()
    local used = e0 - T.P():getEnergy()
    T.check("carry: about 3 energy/s drained", used > 6 and used < 14, string.format("%.1f in 3s", used))
    local other_used = other_e0 - T.secondShip():getEnergy()
    T.check("other ship: the AI does not drain it", other_used < 3, string.format("%.1f in 3s", other_used))
    T.st().fleet_due = 0   -- do not wait out the 60 s
end)
T.waitFor("carry: audit fleet arrives", function() return T.st().fleet_spawned end, 5)
T.step("fleet", function()
    local f = T.st().fleet
    T.eq("carry: three audit ships", T.alive(f), 3)
    T.eq("carry: fleet is hostile", f[1]:getFaction(), "Concord Hostile")
    local d = RT.dist(T.P(), f[1])
    T.check("carry: fleet spawns about 10U out", d > 9000 and d < 11000, string.format("%.0f", d))
end)
T.waitFor("carry: the auditors jam warp from where they arrive", function()
    local x, y = T.P():getPosition()
    return T.countType("WarpJammer", x, y, 3000) > 0
end, 3)
T.step("jammed from afar", function()
    local nearest = math.huge
    for _, s in ipairs(T.st().fleet) do
        if RT.valid(s) then nearest = math.min(nearest, RT.dist(T.P(), s)) end
    end
    T.check("carry: still well out when they jam", nearest > 8000, string.format("%.0f", nearest))
    T.moveNear(T.st().fleet[1], 3000)
end)
T.talk(function() return T.st().fleet[1] end, {"Not today."})
T.step("refusing changes nothing", function() T.eq("carry: still carrying", T.phase(), "carry") end)
T.actAs(T.secondShip)
T.talk(function() return T.st().fleet[1] end, {})
T.step("a second ship cannot surrender the AI", function()
    T.check("other ship: auditors wave it off", T.msg():find("does not concern you", 1, true) ~= nil, T.msg())
    T.check("other ship: no surrender on offer", not T.hasReply("Transmit the data."))
end)
T.actAs(T.secondShip)
T.talk(function() return T.st().station end, {})
T.step("a second ship gets nothing from Rezkov's station", function()
    T.check("other ship: no response", T.msg():find("No response", 1, true) ~= nil, T.msg())
end)
T.actAs(nil)

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

-- ── Loss: Engineering ejects the AI ──────────────────────────────────────────
local M_ledger = MISSIONS._registry.ledger
T.step("back to carry; Engineering presses eject once", function()
    T.jump("carry")
    T.P():setEnergyLevel(T.P():getMaxEnergy())
    M_ledger.ejectPressed()
    T.eq("eject: one press only arms it", T.phase(), "carry")
    T.check("eject: armed", T.st().eject_armed_at ~= nil)
    T.st().eject_armed_at = T.now() - M_ledger.EJECT_CONFIRM - 1   -- let the confirm time out
end)
T.wait(1)
T.step("the confirm timed out", function()
    T.check("eject: disarmed after the confirm window", T.st().eject_armed_at == nil)
    M_ledger.ejectPressed()
    T.eq("eject: a press after the timeout only arms again", T.phase(), "carry")
    M_ledger.ejectPressed()
end)
T.step("ejected", function()
    T.eq("eject: status", T.status(), "done")
    T.eq("eject: outcome", T.flag("ledger_arc_done"), "lost")
    T.eq("eject: reason", T.flag("ledger_lost_reason"), "ejected")
    T.check("eject: drain off", not T.st().drain_on)
end)

-- ── Loss: the ship is destroyed with the AI aboard ───────────────────────────
-- (core reports the primary ship's loss as "ship_lost" with primary = true: tests/core/primary.lua)
T.step("back to carry; the ship is lost", function()
    T.jump("carry")
    RT.emit("ship_lost", {ship = "Kestrel", primary = false}, "high")
    T.eq("destroyed: another ship's loss changes nothing", T.phase(), "carry")
    RT.emit("ship_lost", {ship = RT.campaign.ship_name, primary = true}, "high")
end)
T.step("lost with the ship", function()
    T.eq("destroyed: status", T.status(), "done")
    T.eq("destroyed: outcome", T.flag("ledger_arc_done"), "lost")
    T.eq("destroyed: reason", T.flag("ledger_lost_reason"), "destroyed")
    T.P():setEnergyLevel(T.P():getMaxEnergy())
end)

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

-- ── Rewinding the Rezkov arc stops this one ──────────────────────────────────
-- Ledger needs the Rezkov arc finished or declined. When the GM sends Rezkov back to an earlier
-- phase, a running Ledger arc is reset to "never happened" and waits for Rezkov again.
local function rezkovJump(key)
    for _, g in ipairs(MISSIONS._registry.rezkov.gm_states) do
        if g.key == key then g.fn(MISSIONS._state.rezkov) return end
    end
    error("no Rezkov GM state " .. key)
end
T.step("Rezkov finished, Ledger under way", function()
    rezkovJump("done_data")
    T.check("gate: Rezkov finished", RT.flag("rezkov_arc_done") ~= nil)
    T.jump("meet")
    T.eq("gate: Ledger at the meeting", T.phase(), "meet")
end)
T.wait(1)
T.step("the GM sends Rezkov back to its rumors", function()
    rezkovJump("rumors")
    T.check("gate: Rezkov no longer finished", not RT.flag("rezkov_arc_done") and not RT.flag("rezkov_declined"))
end)
T.waitFor("gate: Ledger stops", function() return T.status() ~= "active" end, 3)
T.step("Ledger never happened", function()
    T.eq("gate: waiting again", T.status(), "inactive")
    T.check("gate: its flags cleared", not T.flag("ledger_thresh"))
    T.check("gate: its station removed", T.find("Rezkov's station") == nil)
    T.check("gate: the criteria name the prerequisite",
        MISSIONS._criteriaText("ledger"):find("[ ? ] Rezkov arc finished or declined", 1, true) ~= nil)
    -- A GM jump straight into Ledger, Rezkov unfinished, still works (only a change stops it).
    T.jump("hook")
end)
T.wait(1)
T.step("a GM jump without the prerequisite stays", function()
    T.eq("gate: jumped arc keeps running", T.status(), "active")
    T.eq("gate: in its hook", T.phase(), "hook")
    MISSIONS.cancel("rezkov"); MISSIONS.setEnabled("rezkov", false); MISSIONS.gmClearFlags("rezkov")
end)

-- A crew that already knows Thresh (from the Rezkov arc) asks for him by name.
T.step("back to the hook, Thresh known", function()
    T.jump("hook")
    ARC.meet("rezkov", "thresh_profile", "Thresh")
end)
T.dock("Dustmote Salvage")
T.talk("Dustmote Salvage", {})
T.step("asks for Thresh by name", function()
    T.check("hook: 'Heard Thresh was looking for us again.'", T.hasReply("Heard Thresh was looking for us again."),
        table.concat(T.replies(), " | "))
    T.check("hook: not the stranger's line", not T.hasReply("Heard someone here was asking about us."))
end)
T.talk("Dustmote Salvage", {"Heard Thresh was looking for us again."})
T.step("Thresh does not introduce himself again", function()
    T.check("hook: no 'That was me.'", not T.msg():find("That was me.", 1, true), T.msg())
    T.check("hook: straight to the lead", T.msg():find('"My associate has work', 1, true) ~= nil, T.msg())
    RT.clearFlag("rezkov_met_thresh")
    SCIDB.sync()
end)
T.closeComms()

T.deactivate({
    gone = {"Rezkov's station", "CAS Double Entry", "CAS Debit", "Data core"},
    check = function()
        T.check("inactive: AI voice gone", not RT.voice.exists("ledger_ai"))
        T.check("inactive: Thresh profile forgotten", not SCIDB.known("thresh_profile"))
    end,
})
