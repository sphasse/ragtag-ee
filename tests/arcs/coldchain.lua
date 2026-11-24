-- Cold Chain: the gate (the Hob Works funded + 3 board jobs), the seed rumors (Varga's sets the
-- objective), the three-page brief at Tamsin Hollow, the port hack at Ostia Highport (reset away from
-- the dock; it counts only docked), who saw it (a fake code running: no standing loss, no chase; no
-- code: Concord -300 and a chase that ends out of Concord space), the spoil timer, an in-time
-- delivery (3,000 cr, Independent +150), a spoiled one (1,000 cr), the Magpie lost with the serum,
-- every GM state and "-> Inactive".
-- Not covered: a real Relay hack of the port (hack levels are set), a real dock (forced), the flight.

T.arc("coldchain")

local M_cc = MISSIONS._registry.coldchain
local gate = M_cc.triggers.custom
local c0, ind0, con0

local function finishJob()
    local m = T.makeJob("delivery", "Port Vesper")
    JOBS.accept(m, true)
    JOBS.complete(T.activeEntry(m))
end
local function chasing()
    for _, z in ipairs({"the Concord Core", "the Arbiter Line", "the Escrow Marches"}) do
        if PROX._chase_zones[z] then return true end
    end
    return false
end
local function seedWith(text)
    for _, r in ipairs(RUMORS._injected or {}) do
        if r.category == "COLDCHAIN_SEED" and r.text:find(text, 1, true) then return r end
    end
end

-- ── The gate ─────────────────────────────────────────────────────────────────
T.step("the gate", function()
    RT.clearFlag("coldchain_jobs_base")
    RT.clearFlag("hob_arc_done")
    T.check("gate: closed before the Hob Works is funded", not M_cc.triggers.requires())
    RT.flag("hob_arc_done", "funded")
    T.check("gate: the Hob Works funded", M_cc.triggers.requires())
    T.check("gate: the job count is noted", RT.flag("coldchain_jobs_base") ~= nil)
    finishJob(); finishJob()
    T.check("gate: two board jobs are not enough", not gate())
    T.check("gate: the criteria show 2", MISSIONS._criteriaText("coldchain"):find("(now: 2)", 1, true) ~= nil, MISSIONS._criteriaText("coldchain"))
    finishJob()
    T.check("gate: open after the third", gate())
end)
T.waitFor("gate: the arc starts on its own", function() return T.status() == "active" end, 3)

-- ── Hook: seed rumors, Varga's request ───────────────────────────────────────
T.step("hook", function()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three seed rumors", T.rumors("COLDCHAIN_SEED"), 3)
    T.check("hook: no objective until Varga's rumor is heard", RT.objectives.coldchain == nil)
    local r = seedWith("Dr. Varga at Tamsin Hollow")
    T.check("hook: Varga's rumor", r ~= nil)
    T.eq("hook: Independent ports only", r and r.faction, "Independent")
    r.on_heard()
    T.eq("hook: hearing it sets the objective", RT.objectives.coldchain, "Dr. Varga at Tamsin")
end)
T.dock("Tamsin Hollow")
T.talk("Tamsin Hollow", {"[SPECIAL] Dr. Varga's medical run"})
T.step("page 1: the fever", function()
    T.check("p1: Varga", T.msg():find("I'm Nell Varga", 1, true) ~= nil, T.msg())
    T.check("p1: the proper channels", T.msg():find("I applied. Six weeks ago.", 1, true) ~= nil, T.msg())
    T.check("p1: her profile", SCIDB.known("varga_profile"))
end)
T.reply({"Go on."})
T.step("page 2: the plan", function()
    T.check("p2: dock and hack the port", T.msg():find("get it to 75% hacked while you're docked", 1, true) ~= nil, T.msg())
end)
T.reply({"Go on."})
T.step("page 3: the cold run and the pay", function()
    T.check("p3: fifteen minutes", T.msg():find("cold-packed for fifteen minutes", 1, true) ~= nil, T.msg())
    T.check("p3: the transponder hint", T.msg():find("very good transponder code", 1, true) ~= nil, T.msg())
    T.check("p3: 3,000", T.msg():find("I can pay 3,000 credits", 1, true) ~= nil, T.msg())
end)
T.reply({"Not right now."})
T.step("not right now: still the hook", function() T.eq("decline: hook", T.phase(), "hook") end)
T.talk("Tamsin Hollow", {"[SPECIAL] Dr. Varga's medical run", "Go on.", "Go on.", "We'll do it."})
T.step("accepted", function()
    T.eq("accept: approach", T.phase(), "approach")
    T.check("accept: briefed", T.flag("coldchain_briefed"))
    T.eq("accept: seeds gone", T.rumors("COLDCHAIN_SEED"), 0)
    T.eq("accept: objective", RT.objectives.coldchain, "Hack Ostia Highport")
    T.check("accept: the Tamsin fever entry", SCIDB._entries["coldchain_fever"] ~= nil)
end)
T.closeComms()

-- ── The port hack: only while docked ─────────────────────────────────────────
T.step("hacked from range", function()
    T.undock()
    T.moveNear("Ostia Highport", 20000)
    M_cc.setPortHack(1.0)
end)
T.wait(1)
T.step("reset away from the dock", function()
    T.eq("range: the depot resets a hack from range", M_cc.portHack(), 0)
    T.eq("range: still approaching", T.phase(), "approach")
end)
T.dock("Ostia Highport")
T.step("docked, a partial hack", function()
    M_cc.setPortHack(0.5)
end)
T.wait(1)
T.step("50% is not enough", function()
    T.check("dock: the hack holds while docked", M_cc.portHack() > 0.45, M_cc.portHack())
    T.eq("dock: still approaching", T.phase(), "approach")
    -- Clean crew, no code: the Magpie is identified.
    RT.addReputation("Concord", 0 - T.rep("Concord"), "test")
    con0 = T.rep("Concord")
    M_cc.setPortHack(0.8)
end)
T.waitFor("75% while docked loads the serum", function() return T.phase() == "run" end, 3)
T.step("seen: the Magpie identified", function()
    T.check("load: loaded", T.flag("coldchain_loaded"))
    T.eq("seen: recorded", T.flag("coldchain_seen"), "seen")
    T.eq("seen: Concord -300", T.rep("Concord") - con0, -300)
    T.check("seen: the Concord chase is on", chasing() and T.st().chase)
    T.eq("run: objective", RT.objectives.coldchain, "Serum to Tamsin")
    T.check("run: fifteen minutes", math.abs(T.st().spoil_at - T.now() - 900) < 2)
    T.eq("run: the port's hack is cleared", M_cc.portHack(), 0)
end)
T.dock("Tamsin Hollow")
T.step("out of Concord space", function()
    T.check("chase: over at Tamsin", not chasing() and not T.st().chase)
    c0, ind0 = T.credits(), T.rep("Independent")
end)
T.talk("Tamsin Hollow", {"We have the serum."})
T.step("delivered in time", function()
    T.check("deliver: her line", T.msg():find("It's good. It's all good.", 1, true) ~= nil, T.msg())
    T.eq("deliver: +3,000", T.credits() - c0, 3000)
    T.eq("deliver: Independent +150", T.rep("Independent") - ind0, 150)
    T.eq("deliver: outcome", T.flag("coldchain_arc_done"), "delivered")
    T.eq("deliver: done", T.status(), "done")
    T.check("deliver: no objective", RT.objectives.coldchain == nil)
end)
T.closeComms()
T.waitFor("achievement: Cold Chain", function() return ACH.has("cold_chain") end, 7)
T.step("news", function()
    T.check("news: the fever broke", T.rumors("COLDCHAIN_DONE") >= 2)
    T.check("no fingerprints: not with the Magpie seen", not ACH.has("no_fingerprints"))
end)

-- ── With a fake code running: an unknown freighter, then spoiled ─────────────
T.step("again, with a code", function()
    T.jump("approach")
    RT.addTransponderCodes(1)
    RT.addReputation("Concord", -400 - T.rep("Concord"), "test")
    con0 = T.rep("Concord")
end)
T.dock("Ostia Highport")
T.step("swap the transponder, then hack", function()
    T.check("code: running", RT.useTransponder(T.P()))
    M_cc.setPortHack(1.0)
end)
T.waitFor("loaded", function() return T.phase() == "run" end, 3)
T.step("unknown freighter", function()
    T.eq("code: recorded", T.flag("coldchain_seen"), "code")
    T.eq("code: no standing loss", T.rep("Concord"), con0)
    T.check("code: no chase", not chasing() and not T.st().chase)
    T.st().spoil_at = T.now() - 1
end)
T.wait(1)
T.step("the cold pack runs out", function()
    T.check("spoiled: flagged", T.st().spoiled)
    T.eq("spoiled: the timer line", T.st().timer_text, "Serum spoiling")
    RT.addReputation("Concord", 0 - T.rep("Concord"), "test")
end)
T.dock("Tamsin Hollow")
T.step("credits before", function() c0, ind0 = T.credits(), T.rep("Independent") end)
T.talk("Tamsin Hollow", {"We have the serum."})
T.step("delivered spoiled", function()
    T.check("spoiled: her line", T.msg():find("Some of it's still good.", 1, true) ~= nil, T.msg())
    T.eq("spoiled: +1,000", T.credits() - c0, 1000)
    T.eq("spoiled: no Independent standing", T.rep("Independent"), ind0)
    T.eq("spoiled: outcome", T.flag("coldchain_arc_done"), "spoiled")
end)
T.closeComms()
T.waitFor("achievement: No Fingerprints", function() return ACH.has("no_fingerprints") end, 7)

-- ── The Magpie lost with the serum ───────────────────────────────────────────
T.step("run, then the Magpie is lost", function()
    T.jump("run")
    RT.emit("ship_lost", {ship = T.P():getCallSign(), primary = true, credits_lost = 0, credits = 0}, "high")
end)
T.wait(1)
T.step("lost", function()
    T.eq("lost: outcome", T.flag("coldchain_arc_done"), "lost")
    T.eq("lost: done", T.status(), "done")
    T.check("lost: no chase left", not chasing())
end)

-- ── GM states ────────────────────────────────────────────────────────────────
T.gmWalk({
    {key = "hook", phase = "hook", check = function()
        T.eq("GM hook: the seeds again", T.rumors("COLDCHAIN_SEED"), 3)
        T.check("GM hook: not briefed", not T.flag("coldchain_briefed"))
    end},
    {key = "approach", phase = "approach", check = function()
        T.check("GM approach: briefed replayed", T.flag("coldchain_briefed"))
        T.eq("GM approach: objective", RT.objectives.coldchain, "Hack Ostia Highport")
        T.action("Complete hack")
    end},
    {key = "run", phase = "run", check = function()
        T.check("GM run: loaded", T.flag("coldchain_loaded"))
        T.check("GM run: spoil timer", T.st().spoil_at ~= nil)
        T.action("Spoil now")
        T.restart()
        T.eq("next session: still running", T.phase(), "run")
    end},
    {key = "done_delivered", done = true, check = function()
        T.eq("GM delivered: outcome", T.flag("coldchain_arc_done"), "delivered")
    end},
    {key = "done_spoiled", done = true, check = function()
        T.eq("GM spoiled: outcome", T.flag("coldchain_arc_done"), "spoiled")
    end},
    {key = "done_lost", done = true, check = function()
        T.eq("GM lost: outcome", T.flag("coldchain_arc_done"), "lost")
        T.restart()
        T.eq("next session: done", T.status(), "done")
    end},
})

T.deactivate({
    keep_flags = {"coldchain_jobs_base"},
    check = function()
        T.check("inactive: Varga forgotten", not SCIDB.known("varga_profile"))
        T.check("inactive: no fever entry", SCIDB._entries["coldchain_fever"] == nil)
        T.eq("inactive: no seeds", T.rumors("COLDCHAIN_SEED"), 0)
        T.check("inactive: no chase", not chasing())
    end,
})
