-- Hob Works arc: the gate (Phase II over + survivors + 5 board jobs), the hook through real port
-- news, the four-page briefing and the convoy brief, the fake transponder and the escorts' 15U
-- scan, departure and the GM speed buttons, disabling the transport by its systems, boarding,
-- delivery and payment (which ends the arc); then the wreck and its cash boxes, a missed convoy, the Magpie
-- lost, a late delivery and an abandoned one, the briefing variants, the GM states and
-- "-> Inactive". Not covered: a real fight with the escorts (the test ship is indestructible), a
-- real Relay hack (hack levels are set), a real dock (forced), the transport's whole 8-minute run.

T.arc("hob")

local M_hob = MISSIONS._registry.hob
local gate = M_hob.triggers.custom
local c0, concord0

local function finishJob(story)
    local m = T.makeJob("delivery", "Port Vesper")
    m.story = story or nil
    JOBS.accept(m, true)
    JOBS.complete(T.activeEntry(m))
end

local function transport() return T.st().transport end
local function escorts() return T.st().escorts or {} end
local function faction(e) return RT.valid(e) and e:getFaction() or "gone" end
local function distTo(e, cs)
    local s = RT.find(cs)
    local ex, ey = e:getPosition()
    local sx, sy = s:getPosition()
    return math.sqrt((ex - sx) ^ 2 + (ey - sy) ^ 2)
end
-- Put the Magpie `u` units from the first escort, on the far side from Lumen.
local function nearEscort(u)
    local e = escorts()[1]
    local ex, ey = e:getPosition()
    T.moveTo(ex + u, ey)
end

-- ── The gate, from the other arcs' GM "→ Done" buttons (how a GM sets up a playtest) ──
T.step("the gate opens from every Phase II arc's GM end states", function()
    local function doneStates(id)
        local out = {}
        for _, g in ipairs(MISSIONS._registry[id].gm_states or {}) do
            if g.key:sub(1, 5) == "done_" then out[#out + 1] = g end
        end
        return out
    end
    local arcs = {"rezkov", "ledger", "boneyard", "corsair"}
    for _, id in ipairs(arcs) do
        local g = doneStates(id)[1]
        g.fn(MISSIONS._state[id] or {})
    end
    T.check("GM done: the Phase II arcs are over", M_hob.triggers.requires())
    for _, id in ipairs(arcs) do
        for _, g in ipairs(doneStates(id)) do
            g.fn(MISSIONS._state[id] or {})
            T.check("GM done: gate open after " .. id .. " " .. g.key, M_hob.triggers.requires())
        end
        doneStates(id)[1].fn(MISSIONS._state[id] or {})
    end
    T.action("Satisfy done jobs")
    T.check("GM done: Satisfy done jobs sets the count", gate())
    RT.clearFlag("boneyard_buoy_found")   -- the next step checks the gate without them
    RT.clearFlag("hob_jobs_base")
end)

-- ── The gate ─────────────────────────────────────────────────────────────────
T.step("the gate", function()
    RT.clearFlag("hob_jobs_base")
    RT.flag("rezkov_arc_done", "data_delivered")
    RT.flag("ledger_arc_done", "full")
    RT.flag("boneyard_arc_done", true)
    RT.flag("corsair_arc_done", "defended")
    T.check("gate: closed without the lifeboat survivors", not M_hob.triggers.requires())
    T.check("gate: no job count yet", RT.flag("hob_jobs_base") == nil)
    RT.flag("boneyard_buoy_found", true)
    T.check("gate: the Phase II arcs are over", M_hob.triggers.requires())
    T.check("gate: the job count is noted", RT.flag("hob_jobs_base") ~= nil)
    T.check("gate: closed right after", not gate())
    for _ = 1, 4 do finishJob() end
    finishJob(true)
    T.check("gate: four board jobs (and a story contract) are not enough", not gate())
    T.check("gate: the criteria show 4", MISSIONS._criteriaText("hob"):find("(now: 4)", 1, true) ~= nil, MISSIONS._criteriaText("hob"))
    finishJob()
    T.check("gate: open after the fifth", gate())
    RT.flag("boneyard_hack_done", true)   -- the archive came out: the 10,000 cr price
end)
T.waitFor("gate: the arc starts on its own", function() return T.status() == "active" end, 3)

-- ── Hook: port news at Independent ports ─────────────────────────────────────
T.step("hook", function()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: Quill's message is news", T.rumors("HOB_HOOK"), 1)
    T.check("hook: no objective until the message is heard", RT.objectives.hob == nil)
    local said = RUMORS.get("Hob Test Concord", "Concord")
    T.check("hook: a Concord port does not pass it on", not tostring(said):find("Mara Quill", 1, true), said)
end)
T.dock("Port Vesper")
T.talk("Port Vesper", {"Any news worth hearing?"})
T.step("Port Vesper passes on Quill's message", function()
    T.check("hook: the message", T.msg():find("Mara Quill left a message for your crew. Something about a breakthrough at the Works.", 1, true) ~= nil, T.msg())
    T.eq("hook: hearing it sets the objective", RT.objectives.hob, "Meet Quill at Hob's")
end)
T.closeComms()

-- Another crew at Hob's Landing gets the ordinary station menu.
T.actAs(T.secondShip)
T.dock("Hob's Landing")
T.talk("Hob's Landing", {})
T.step("a second ship is not offered the meeting", function()
    T.check("other ship: no meeting", not T.hasReply("We got Mara Quill's message."), table.concat(T.replies(), " | "))
end)
T.actAs(nil)

-- ── The meeting: four pages ──────────────────────────────────────────────────
T.dock("Hob's Landing")
T.talk("Hob's Landing", {"We got Mara Quill's message."})
T.step("page 1: Quill, the context", function()
    T.check("p1: Quill", T.msg():find("Mara Quill", 1, true) ~= nil, T.msg())
    T.check("p1: the program", T.msg():find("ran a program to make the Pale Sun colonists docile", 1, true) ~= nil, T.msg())
    T.check("p1: Quill's profile", SCIDB.known("quill_profile"))
end)
T.reply({"Go on."})
T.step("page 2: Marchetti, the breakthrough", function()
    T.check("p2: Quill speaks of Marchetti", T.msg():find("We've been working with Anton Marchetti, the Works' chief engineer.", 1, true) ~= nil, T.msg())
    T.check("p2: Lullaby", T.msg():find("We call it Lullaby", 1, true) ~= nil, T.msg())
    T.check("p2: Marchetti's profile", SCIDB.known("marchetti_profile"))
end)
T.reply({"Go on."})
T.step("page 3: the goal and the price", function()
    T.check("p3: 10,000 credits", T.msg():find("10,000 credits", 1, true) ~= nil, T.msg())
end)
T.reply({"Go on."})
T.step("page 4: the pitch", function()
    T.check("p4: the pitch", T.msg():find("Which brings us to you. We think we've got a creative way to get the cash. Your friend Rezkov", 1, true) ~= nil, T.msg())
    T.check("p4: met", T.flag("hob_met"))
    T.check("p4: the Lullaby entry", SCIDB._entries["hob_lullaby"] ~= nil)
    T.eq("p4: the message is delivered (no more news)", T.rumors("HOB_HOOK"), 0)
    for _, p in ipairs({T.msg()}) do T.check("pages fit: page 4 is short", #p < 520, #p) end
end)
T.reply({"Not right now."})
T.step("not right now: still the hook", function() T.eq("decline: still hook", T.phase(), "hook") end)
T.closeComms()

-- ── The convoy brief, then the heist ─────────────────────────────────────────
T.talk("Hob's Landing", {"About Lullaby and the cash...", "Interested."})
T.step("brief 1: the transfer", function()
    T.check("b1: 15 minutes", T.msg():find("leaving Lumen Exchange for Sentinel in 15 minutes", 1, true) ~= nil, T.msg())
    -- The first step pressed Boneyard's and Corsair's GM "→ Done" buttons: both battle groups are gone.
    T.check("b1: two battle groups lost", T.msg():find("The Concord has lost two battle groups, one in the Boneyard and one at Blackwater, and it is trying to rebuild at Sentinel Fleet Yard.", 1, true) ~= nil, T.msg())
end)
T.reply({"Go on."})
T.step("brief 2: the transport", function()
    T.check("b2: board it", T.msg():find("hack each one to 90% or shoot it below 10%. Then you can board it.", 1, true) ~= nil, T.msg())
end)
T.reply({"Go on."})
T.step("brief 3: the escorts", function()
    T.check("b3: 15U", T.msg():find("Their sensors reach about 15U", 1, true) ~= nil, T.msg())
    T.check("b3: the port guards' 5U", T.msg():find("The ships guarding the Concord ports don't go far, but once you're wanted, if they see the Magpie within 5U they will come after you.", 1, true) ~= nil, T.msg())
end)
T.reply({"Go on."})
T.step("brief 4: the transponder", function()
    T.check("b4: ten minutes, once", T.msg():find("good for ten minutes from when you throw the switch, and only once", 1, true) ~= nil, T.msg())
    T.check("b4: wired into the ship", T.msg():find("Our engineers can wire a fake transponder into your ship, enabled when needed by your Engineering station.", 1, true) ~= nil, T.msg())
    T.check("b4: the way out", T.msg():find("the gig is up, and you'll have to get creative to get back out of Concord space.", 1, true) ~= nil, T.msg())
    T.check("b4: more in the database", T.msg():find("We've put more info in your database. You've got a long haul ahead and need to get going, so you can review it and make a plan on the way.", 1, true) ~= nil, T.msg())
    T.check("b4: the price, extra is theirs", T.msg():find("We need the 10,000. Any extra credits are yours for the trouble.", 1, true) ~= nil, T.msg())
end)
T.reply({"We'll do it."})
T.step("the heist starts", function()
    T.eq("heist: phase", T.phase(), "heist")
    T.check("heist: briefed", T.flag("hob_briefed"))
    T.check("heist: the convoy intel entry", SCIDB._entries["hob_intel"] ~= nil)
    local intel = SCIDB._entries["hob_intel"] and SCIDB._entries["hob_intel"]:getLongDescription() or ""
    T.check("heist: intel names the port guards' 5U", intel:find("if they see the Magpie within 5U they will come after you", 1, true) ~= nil, intel)
    T.check("heist: and the lane pickets' 10U", intel:find("The lane pickets", 1, true) ~= nil and intel:find("see 10U", 1, true) ~= nil, intel)
    T.check("heist: the transport is out", RT.valid(transport()))
    T.eq("heist: two escorts", T.alive(escorts()), 2)
    T.check("heist: waiting at Lumen Exchange", distTo(transport(), "Lumen Exchange") < 4000)
    T.eq("heist: the transport is plain Concord until it leaves", faction(transport()), "Concord")
    T.check("heist: departs in 15 minutes", math.abs(T.st().depart_at - T.now() - 900) < 2)
    T.eq("heist: objective", RT.objectives.hob, "Rob the convoy")
    for _, z in ipairs({"the Concord Core", "the Arbiter Line", "the Escrow Marches"}) do
        T.check("heist: Concord patrols suspended in " .. z, PROX._suspended_zones[z])
    end
    T.check("heist: the transponder button on Engineering", T.st().code_used == false)
end)
T.closeComms()

-- ── The escorts' scan and the fake transponder ───────────────────────────────
T.step("outside 15U", function() nearEscort(20000) end)
T.wait(1)
T.step("not seen at 20U", function() T.check("scan: not spotted at 20U", not T.st().spotted) end)
-- Another player ship is just traffic.
T.step("a second ship inside 15U", function()
    local s = T.secondShip()
    local ex, ey = escorts()[1]:getPosition()
    s:setPosition(ex + 5000, ey)
end)
T.wait(1)
T.step("the escorts ignore it", function()
    T.check("scan: a second ship is not spotted", not T.st().spotted)
    T.secondShip():setPosition(-30000, 40000)
    M_hob.transponderPressed()
    T.check("code: used", T.st().code_used)
    T.check("code: good for 10 minutes", math.abs(T.st().code_until - T.now() - 600) < 2)
    local until1 = T.st().code_until
    M_hob.transponderPressed()
    T.eq("code: one use only", T.st().code_until, until1)
    nearEscort(5000)
end)
T.wait(1)
T.step("inside 15U with a good code", function()
    T.check("code: not spotted at 5U", not T.st().spotted)
    T.check("code: Engineering shows the countdown", tostring(T.st().code_text):find("Code valid 9:", 1, true) ~= nil, T.st().code_text)
    T.st().code_until = T.now() - 1   -- the Concord rotates its keys
end)
T.wait(1)
T.step("the code lapses inside 15U", function()
    T.check("scan: spotted", T.st().spotted)
    T.check("scan: one warning", T.st().warned)
    T.eq("scan: escort 1 hostile", faction(escorts()[1]), "Concord Hostile")
    T.eq("scan: escort 2 hostile", faction(escorts()[2]), "Concord Hostile")
    local ok, ord = pcall(function() return escorts()[1]:getOrder() end)
    T.eq("scan: they come for the Magpie", ok and ord, "Attack")
    T.eq("code: Engineering says it expired", T.st().code_text, "Code expired")
    T.eq("scan: the transport stays put until departure", faction(transport()), "Concord")
end)

-- ── Departure and the run ────────────────────────────────────────────────────
local d0
T.step("depart now (GM)", function()
    T.action("Depart now")
end)
T.wait(1)
T.step("the run", function()
    T.check("run: departed", T.st().departed)
    T.eq("run: the transport can be fought", faction(transport()), "Concord Hostile")
    T.eq("run: objective", RT.objectives.hob, "Stop CTS Tithe")
    T.eq("run: 125 u/s", T.st().speed, 125)
    T.action("Transport faster")
    T.eq("GM faster: 150", T.st().speed, 150)
    T.action("Transport slower"); T.action("Transport slower")
    T.eq("GM slower: 100", T.st().speed, 100)
    T.action("Transport faster")
    T.eq("back to 125", T.st().speed, 125)
    T.check("run: no transponder after departure", T.st().code_text == nil)
    d0 = distTo(transport(), "Sentinel Fleet Yard")
end)
T.wait(8)
T.step("it heads for Sentinel at about 125 u/s", function()
    local moved = d0 - distTo(transport(), "Sentinel Fleet Yard")
    -- 8 s: about 5 s to get up to speed, then 125 u/s: roughly 600 to 1000 units.
    T.check("run: closer to Sentinel, at speed", moved > 500 and moved < 1100, moved)
end)

-- ── Disabling it: engines AND rear shield, each 90% hacked or under 10% health ─
T.step("a system is down at 90% hacked (Relay) or under 10% health (Science)", function()
    local t = transport()
    t:setSystemHackedLevel("impulse", 0.85)
    T.check("down: 85% hacked is not down", not M_hob.systemDown(t, "impulse"))
    t:setSystemHackedLevel("impulse", 1.0)   -- two successful hacks; it fades below 90% in ~18 s
    T.check("down: 100% hacked is down", M_hob.systemDown(t, "impulse"))
    T.check("down: an undamaged rear shield is up", not M_hob.systemDown(t, "rearshield"))
    t:setSystemHealth("rearshield", 0.15)
    T.check("down: 15% health is not down", not M_hob.systemDown(t, "rearshield"))
end)
T.wait(1)
T.step("engines hacked, shield at 15%: still running", function()
    T.check("disable: not with the rear shield up", not T.st().disabled)
    transport():setSystemHealth("rearshield", 0.05)   -- shot below 10%
end)
T.wait(1)
T.step("engines and rear shield down: disabled", function()
    T.check("disable: disabled", T.st().disabled)
    T.eq("disable: surrendered (dockable, nobody's enemy)", faction(transport()), "Concord Surrendered")
    T.eq("disable: objective", RT.objectives.hob, "Board CTS Tithe")
    T.eq("disable: still the heist until boarded", T.phase(), "heist")
    concord0 = T.rep("Concord")
end)
T.dock(function() return T.st().transport end)
T.wait(1)
T.step("boarded", function()
    T.eq("board: result", T.flag("hob_heist"), "boarded")
    T.eq("board: four boxes, 12,000 cr", T.flag("hob_haul"), 12000)
    T.eq("board: Concord -800", T.rep("Concord") - concord0, -800)
    T.eq("board: deliver", T.phase(), "deliver")
    T.eq("board: objective", RT.objectives.hob, "Cash to Hob's")
    T.check("board: 15 minutes to deliver", math.abs(T.st().deliver_due - T.now() - 900) < 2)
    for _, z in ipairs({"the Concord Core", "the Arbiter Line", "the Escrow Marches"}) do
        T.check("board: Concord patrols back in " .. z, not PROX._suspended_zones[z])
    end
end)

-- ── Delivery and payment ─────────────────────────────────────────────────────
T.dock("Hob's Landing")
T.step("credits before", function() c0 = T.credits() end)
T.talk("Hob's Landing", {"We have the cash."})
T.step("delivered", function()
    T.eq("deliver: +12,000 cr", T.credits() - c0, 12000)
    T.check("deliver: delivered", T.flag("hob_delivered"))
    T.check("deliver: no more countdown", T.st().deliver_due == nil)
    T.check("deliver: the pay button", T.hasReply("Deliver 10,000 cr to the engineers"), table.concat(T.replies(), " | "))
    T.check("deliver: the extra is theirs", T.msg():find("12,000 credits. We need 10,000 of it for Lullaby's parts; the other 2,000 is yours for the trouble.", 1, true) ~= nil, T.msg())
    c0 = T.credits()
end)
T.reply({"Deliver 10,000 cr to the engineers"})
T.step("paid", function()
    T.eq("pay: -10,000 cr", T.credits() - c0, -10000)
    T.check("pay: paid", T.flag("hob_paid"))
    T.check("pay: it will take time", T.msg():find("These credits will get us what we need, but it is going to take some time. We'll reach out again when we have results.", 1, true) ~= nil, T.msg())
    T.eq("pay: the arc is done", T.status(), "done")
end)
T.closeComms()
T.step("funded", function()
    T.eq("done: funded", T.flag("hob_arc_done"), "funded")
    T.eq("done: news of the robbery", T.rumors("HOB_DONE"), 3)
    T.check("done: no objective", RT.objectives.hob == nil)
end)

-- ── The wreck: three cash boxes ──────────────────────────────────────────────
T.step("heist again, then destroy the transport", function()
    T.jump("heist")
    T.action("Depart now")
end)
T.wait(1)
T.step("shoot it to pieces", function()
    concord0 = T.rep("Concord")
    local t = transport()
    local x, y = t:getPosition()
    applyDamageToEntity(t, 2000, {instigator = T.P(), type = "kinetic", x = x + 500, y = y})
end)
T.wait(1)
T.step("the wreck", function()
    T.check("wreck: gone", not RT.valid(T.find("CTS Tithe")))
    T.eq("wreck: three cash boxes", T.alive(T.st().boxes), 3)
    T.eq("wreck: Concord -1000", T.rep("Concord") - concord0, -1000)
    T.eq("wreck: objective", RT.objectives.hob, "Cash boxes 0/3")
    T.moveTo(T.st().boxes[1]:getPosition())
end)
T.waitFor("wreck: flying into a box picks it up", function() return T.st().boxes_got == 1 end, 8)
T.step("the other two", function()
    T.eq("wreck: objective 1/3", RT.objectives.hob, "Cash boxes 1/3")
    T.moveTo(T.st().boxes[2]:getPosition())
end)
T.waitFor("wreck: second box", function() return T.st().boxes_got == 2 end, 8)
T.step("the last box", function() T.moveTo(T.st().boxes[3]:getPosition()) end)
T.waitFor("wreck: third box ends the heist", function() return T.phase() == "deliver" end, 8)
T.step("9,000 cr to deliver", function()
    T.eq("wreck: result", T.flag("hob_heist"), "destroyed")
    T.eq("wreck: 9,000 cr", T.flag("hob_haul"), 9000)
end)

-- ── Late: Independent to -100, shaming news, late delivery taken ─────────────
T.step("the deadline passes", function()
    RT.addReputation("Independent", 350 - (T.rep("Independent") or 0), "test")
    T.st().deliver_due = T.now() - 1
end)
T.wait(1)
T.step("late", function()
    T.check("late: flagged", T.flag("hob_late"))
    T.eq("late: Independent set to -100", T.rep("Independent"), -100)
    T.eq("late: shaming port news", T.rumors("HOB_SHAME"), 3)
    T.check("late: 30 minutes of it", math.abs(T.st().pester_until - T.now() - 1800) < 2)
    local said = RUMORS.get("Hob Test Late", "Independent")
    T.check("late: Independent ports say it", tostring(said):find("Magpie", 1, true) ~= nil, said)
    c0 = T.credits()
end)
T.dock("Hob's Landing")
T.talk("Hob's Landing", {"We have the cash."})
T.step("a late delivery is accepted", function()
    T.check("late: better late", T.msg():find("Better late", 1, true) ~= nil, T.msg())
    T.eq("late: +9,000", T.credits() - c0, 9000)
    T.check("late: 1,000 short of the price", T.msg():find("9,000 credits. Lullaby's parts cost 10,000, so that leaves us 1,000 short. Can you cover the rest?", 1, true) ~= nil, T.msg())
    T.eq("late: the shaming stops", T.rumors("HOB_SHAME"), 0)
    T.check("late: no abandon timer", T.st().pester_until == nil)
end)
T.closeComms()

-- ── Abandoned: the cash never comes ──────────────────────────────────────────
T.step("deliver with the cash, late, and the 30 minutes run out", function()
    T.jump("deliver")
    T.st().deliver_due = T.now() - 1
end)
T.wait(1)
T.step("the pestering ends", function()
    T.check("abandon: late", T.flag("hob_late"))
    T.st().pester_until = T.now() - 1
end)
T.waitFor("abandon: done", function() return T.status() == "done" end, 3)
T.step("abandoned", function()
    T.eq("abandon: outcome", T.flag("hob_arc_done"), "abandoned")
end)

-- ── Missed: it reaches Sentinel ──────────────────────────────────────────────
T.step("heist, the transport near Sentinel", function()
    T.jump("heist")
    T.action("Depart now")
end)
T.wait(1)
T.step("teleport it to Sentinel", function()
    local s = RT.find("Sentinel Fleet Yard")
    local x, y = s:getPosition()
    transport():setPosition(x + 1500, y)
end)
T.waitFor("missed: over", function() return T.phase() == "deliver" end, 3)
T.step("missed", function()
    T.eq("missed: result", T.flag("hob_heist"), "missed")
    T.check("missed: no haul", T.flag("hob_haul") == nil)
    T.eq("missed: objective", RT.objectives.hob, "Pay the Works")
    T.check("missed: no countdown", T.st().deliver_due == nil)
    RT.addCredits(-T.credits(), "test: broke")
end)
T.dock("Hob's Landing")
T.talk("Hob's Landing", {"Talk to Quill and Marchetti"})
T.step("short of the price", function()
    T.check("missed: told how short", T.msg():find("short. Take some work and come back.", 1, true) ~= nil, T.msg())
    T.check("missed: no pay button", not T.hasReply("Deliver 10,000 cr to the engineers"))
    RT.addCredits(10000, "test: job work")
end)
T.talk("Hob's Landing", {"Talk to Quill and Marchetti", "Deliver 10,000 cr to the engineers"})
T.step("paid from job credits", function()
    T.eq("missed: paid, done", T.status(), "done")
    T.eq("missed: funded", T.flag("hob_arc_done"), "funded")
end)
T.closeComms()

-- ── The Magpie lost during the heist ─────────────────────────────────────────
T.step("heist, then the Magpie is lost", function()
    T.jump("heist")
    RT.emit("ship_lost", {ship = T.P():getCallSign(), primary = true, credits_lost = 0, credits = 0}, "high")
end)
T.step("lost", function()
    T.eq("lost: result", T.flag("hob_heist"), "lost")
    T.eq("lost: deliver (pay from credits)", T.phase(), "deliver")
end)

-- ── Variants: no archive, the crew sold Rezkov out, the Ledger lost ──────────
T.step("variants", function()
    T.jump("hook")
    RT.clearFlag("boneyard_hack_done")
    RT.flag("rezkov_arc_done", "concord_won")
    RT.flag("ledger_arc_done", "lost")
end)
T.dock("Hob's Landing")
T.talk("Hob's Landing", {"We got Mara Quill's message.", "Go on.", "Go on."})
T.step("no archive: 15,000", function()
    T.check("variant: 15,000 credits", T.msg():find("15,000 credits", 1, true) ~= nil, T.msg())
end)
T.reply({"Go on."})
T.step("Rezkov sold out, Ledger lost", function()
    T.check("variant: the Meridian business", T.msg():find("Rezkov hasn't forgotten the Meridian business", 1, true) ~= nil, T.msg())
    T.check("variant: the Lumen business", T.msg():find("even after the Lumen business", 1, true) ~= nil, T.msg())
    RT.flag("boneyard_hack_done", true)
    RT.flag("rezkov_arc_done", "data_delivered")
    RT.flag("ledger_arc_done", "full")
end)
T.closeComms()

-- ── GM states ────────────────────────────────────────────────────────────────
T.gmWalk({
    {key = "hook",    phase = "hook", check = function()
        T.eq("GM hook: the message is news again", T.rumors("HOB_HOOK"), 1)
        T.check("GM hook: no convoy", T.find("CTS Tithe") == nil)
    end},
    {key = "heist",   phase = "heist", check = function()
        T.check("GM heist: convoy out", RT.valid(transport()))
        T.check("GM heist: briefed replayed", T.flag("hob_briefed"))
        T.restart()
        T.eq("next session: the heist starts over", T.phase(), "heist")
        T.check("next session: a fresh countdown", T.st().depart_at - T.now() > 890)
    end},
    {key = "deliver", phase = "deliver", check = function()
        T.eq("GM deliver: carrying 12,000", T.flag("hob_haul"), 12000)
        T.check("GM deliver: countdown", T.st().deliver_due ~= nil)
        T.restart()
        T.eq("next session: still delivering", T.phase(), "deliver")
    end},
    {key = "done_funded", done = true, check = function()
        T.eq("GM funded: outcome", T.flag("hob_arc_done"), "funded")
        T.check("GM funded: paid replayed", T.flag("hob_paid"))
        RT.clearFlag("hob_arc_done")
        T.restart()
        T.eq("next session: paid but not closed is funded", T.flag("hob_arc_done"), "funded")
        T.eq("next session: done", T.status(), "done")
    end},
    {key = "done_abandoned", done = true, check = function()
        T.eq("GM abandoned: outcome", T.flag("hob_arc_done"), "abandoned")
        T.check("GM abandoned: not paid", not T.flag("hob_paid"))
    end},
})

-- The GM's "Satisfy done jobs": the gate's job count is met at once.
T.step("satisfy done jobs", function()
    MISSIONS.gmToggleEnabled("hob")   -- disable (resets)
    RT.flag("hob_jobs_base", (RT.shipRecord().jobs_done or 0))
    T.check("satisfy: the gate is closed", not gate())
    T.action("Satisfy done jobs")
    T.check("satisfy: the gate is open", gate())
    MISSIONS.setEnabled("hob", true)
end)

T.deactivate({
    gone = {"CTS Tithe", "CNS Surety", "CNS Bond", "Cash box"},
    keep_flags = {"hob_jobs_base"},
    check = function()
        T.check("inactive: Quill forgotten", not SCIDB.known("quill_profile"))
        T.check("inactive: no Lullaby entry", SCIDB._entries["hob_lullaby"] == nil)
        for _, z in ipairs({"the Concord Core", "the Arbiter Line", "the Escrow Marches"}) do
            T.check("inactive: patrols on in " .. z, not PROX._suspended_zones[z])
        end
    end,
})
