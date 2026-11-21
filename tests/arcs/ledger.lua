-- Ledger arc: hook -> meet -> relay_run -> carry -> done (full), then both loss paths, the GM
-- states, and "-> Inactive". Not covered: the 60 s fleet timer (forced), a real dock.

T.arc("ledger")

local c0, concord0, indep0

-- ── The gate: two board jobs after the Rezkov arc ────────────────────────────
-- The Rezkov arc ends at Dustmote, where this hook lives: the arc waits until the primary ship has
-- finished two board jobs since then (story contracts do not count).
local gate = MISSIONS._registry.ledger.triggers.custom
local function finishJob(story)
    local m = T.makeJob("delivery", "Port Vesper")
    m.story = story or nil
    JOBS.accept(m, true)
    JOBS.complete(T.activeEntry(m))
end
-- Through the engine, as a crew plays it: the Rezkov arc ends while the ship is still short of
-- 800 cr of upgrades; it does two board jobs; then it buys upgrades. The jobs done before the
-- upgrades count: the arc starts once the upgrades are there. (The count used to be taken only
-- once every other trigger held, so jobs done below 800 cr of upgrades were not counted.)
local saved_upgrades
T.step("Rezkov over, upgrades still short", function()
    saved_upgrades = RT.campaign.upgrades
    RT.campaign.upgrades = {}                      -- 0 cr spent: upgrades_min not met
    RT.clearFlag("ledger_jobs_base")
    RT.flag("rezkov_arc_done", "data_delivered")
end)
T.wait(1)
T.step("two board jobs below 800 cr of upgrades", function()
    T.check("order: the job count is noted as soon as Rezkov is over", RT.flag("ledger_jobs_base") ~= nil)
    T.eq("order: waiting (upgrades short)", T.status(), "inactive")
    finishJob(); finishJob()
    -- Bought, not applied (the spend is all the trigger reads): 200 + 250 + 300 + 250 = 1000.
    RT.campaign.upgrades = {"hull_plating", "shield_mk2", "forward_beams", "beam_coils"}
end)
T.waitFor("order: the arc starts once the upgrades are there", function() return T.status() == "active" end, 3)
T.step("back to the gate checks", function()
    RT.campaign.upgrades = saved_upgrades or {}
    MISSIONS.cancel("ledger")
    RT.clearFlag("rezkov_arc_done")
    RT.clearFlag("ledger_jobs_base")
end)
T.wait(0.5)
T.step("the gate", function()
    T.check("gate: closed while Rezkov is unfinished", not gate())
    RT.flag("rezkov_arc_done", "data_delivered")
    T.check("gate: closed right after Rezkov", not gate())
    T.check("gate: the job count is noted", RT.flag("ledger_jobs_base") ~= nil)
    local function shown(n) return MISSIONS._criteriaText("ledger"):find("(now: " .. n .. ")", 1, true) ~= nil end
    T.check("gate: the criteria show 0 jobs so far", shown("0"), MISSIONS._criteriaText("ledger"))
    finishJob()
    T.check("gate: one job is not enough", not gate())
    T.check("gate: the criteria show 1", shown("1"), MISSIONS._criteriaText("ledger"))
    finishJob(true)
    T.check("gate: a story contract does not count", not gate())
    finishJob()
    T.check("gate: open after the second board job", gate())
    T.check("gate: listed in the criteria",
        MISSIONS._criteriaText("ledger"):find("2 board jobs done by the primary ship", 1, true) ~= nil)
    finishJob()
    T.check("gate: the criteria show 2+ from then on", shown("2+"), MISSIONS._criteriaText("ledger"))
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
T.talk(function() return T.st().station end, {})
T.step("Rezkov's briefing", function()
    T.check("meet: a large and suspicious account", T.msg():find("It found a large and suspicious account that has not closed in twenty years", 1, true) ~= nil, T.msg())
end)
T.reply({"Where are the fragments?"})
T.step("Rezkov's directions", function()
    T.check("meet: the strike force warning", T.msg():find("The Concord accounting unit has a notorious strike force that you really don't want to run across.", 1, true) ~= nil, T.msg())
    T.check("meet: ends 'Bring the assembled AI to me here.' and a line break",
        T.msg():sub(-#'Bring the assembled AI to me here."\n') == 'Bring the assembled AI to me here."\n', T.msg())
end)
T.reply({"We'll bring it home."})
T.step("full energy", function()
    T.check("meet: it runs hot", T.msg():find("You will want full energy when the AI is assembled. It runs hot.", 1, true) ~= nil, T.msg())
end)
T.step("job accepted", function()
    T.eq("relay_run: phase", T.phase(), "relay_run")
    T.check("relay_run: ledger_accepted set", T.flag("ledger_accepted"))
    T.eq("relay_run: three data cores", T.alive(T.st().frags), 3)
    T.check("relay_run: Rezkov profile known", SCIDB.known("rezkov_profile"))
    T.check("relay_run: objective counts fragments", tostring(RT.objectives.ledger):find("0/3", 1, true) ~= nil, RT.objectives.ledger)
    T.eq("relay_run: a power cell near each core", T.alive(T.st().cells), 3)
    local cx, cy = T.st().cells[1]:getPosition()
    T.check("relay_run: the first cell ~2.5U from its core", math.abs(math.sqrt((cx + 172000) ^ 2 + (cy + 70000) ^ 2) - 2500) < 100)
end)

-- ── A power cell: flying into it fills the reactor ───────────────────────────
T.step("low on energy, fly into the first power cell", function()
    T.P():setEnergyLevel(150)
    T.moveTo(T.st().cells[1]:getPosition())
end)
T.waitFor("cell: picked up", function() return T.st().cells_taken[1] end, 8)
T.step("reactor full", function()
    T.check("cell: energy at the maximum", T.P():getEnergy() >= T.P():getMaxEnergy() - 1, T.P():getEnergy())
    T.check("cell: gone", not RT.valid(T.st().cells[1]))
    T.eq("cell: the other two still out", T.alive(T.st().cells), 2)
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
    T.eq("carry: the two untouched power cells stay out", T.alive(T.st().cells), 2)
    -- The "Unidentified Signal" is nowhere: no position, no radar blip (it once sat on the radar
    -- over Port Vesper, at 0, 0).
    local v = RT.voice.get("ledger_ai")
    T.eq("carry: the voice is the Unidentified Signal", v:getCallSign(), "Unidentified Signal")
    T.check("carry: the voice has no position", v.components.transform == nil)
    T.check("carry: and no radar blip", v.components.radar_trace == nil)
    local at_vesper = 0
    for _, o in ipairs(getObjectsInRadius(0, 0, 3000)) do if o == v then at_vesper = at_vesper + 1 end end
    T.eq("carry: nothing of it at Port Vesper", at_vesper, 0)
end)

-- ── Carry: drain, fleet, jammers ─────────────────────────────────────────────
local e0, other_e0
T.step("note energy", function()
    e0 = T.P():getEnergy()
    T.secondShip():setEnergyLevel(500)
    other_e0 = T.secondShip():getEnergy()
end)
T.wait(3)
T.step("the GM's +100 energy", function()
    T.P():setEnergyLevel(200)
    T.action("+100 energy")
    T.check("gm: +100 energy", math.abs(T.P():getEnergy() - 300) < 1, string.format("%.1f", T.P():getEnergy()))
    T.P():setEnergyLevel(T.P():getMaxEnergy() - 40)
    T.action("+100 energy")
    T.eq("gm: never past the maximum", T.P():getEnergy(), T.P():getMaxEnergy())
    T.P():setEnergyLevel(e0)
    e0 = T.P():getEnergy()
end)
T.wait(3)
T.step("energy drains", function()
    local used = e0 - T.P():getEnergy()
    T.check("carry: about 3 energy/s drained", used > 6 and used < 14, string.format("%.1f in 3s", used))
    local other_used = other_e0 - T.secondShip():getEnergy()
    T.check("other ship: the AI does not drain it", other_used < 3, string.format("%.1f in 3s", other_used))
    T.st().fleet_due = 0   -- do not wait out the 60 s
end)
T.closeComms()   -- the AI's hello: the crew is not on another call when the auditors arrive
T.waitFor("carry: audit fleet arrives", function() return T.st().fleet_spawned end, 5)
T.step("fleet", function()
    local f = T.st().fleet
    T.eq("audit: three ships", T.alive(f), 3)
    T.eq("audit: not hostile while they talk", f[1]:getFaction(), "Concord")
    T.check("audit: not an enemy yet", not f[1]:isEnemy(T.P()))
    local d = RT.dist(T.P(), f[1])
    T.check("audit: about 7U out", d > 6000 and d < 8000, string.format("%.0f", d))
    T.check("audit: no warp", not f[1]:hasWarpDrive() and not f[2]:hasWarpDrive())
    local base = CpuShip():setTemplate("Phobos T3")
    local fast = f[1]:getImpulseMaxSpeed() / base:getImpulseMaxSpeed()
    base:destroy()
    T.check("audit: a fast impulse instead (1.5x)", math.abs(fast - 1.5) < 0.01, string.format("%.2f", fast))
end)
T.waitFor("audit: Double Entry's jammer brakes the crew to a stop", function() return T.st().audit.state == "stopped" end, 5)
T.step("boxed in", function()
    local a = T.st().audit
    T.eq("audit: three jammers", T.alive(a.jams), 3)
    local x, y = T.P():getPosition()
    T.eq("audit: all three round the ship", T.countType("WarpJammer", x, y, 1000), 3)
    local side = 600 * math.sqrt(3)
    local tri = true
    for i = 1, 3 do for k = i + 1, 3 do
        if math.abs(RT.dist(a.jams[i], a.jams[k]) - side) > 200 then tri = false end
    end end
    T.check("audit: in a triangle", tri)
    T.eq("audit: still holding fire", T.st().fleet[1]:getFaction(), "Concord")
end)
T.talk(function() return T.st().fleet[1] end, {function() return T.st().audit.excuses[1] end},
    {answer = true, name = "CAS Double Entry"})
T.step("first stall", function()
    local a = T.st().audit
    T.eq("stall: counted", a.stalls, 1)
    T.check("stall: the auditors answer", #T.msg() > 2, T.msg())
    T.check("stall: one more excuse on offer", T.hasReply(a.excuses[2]), table.concat(T.replies(), " | "))
end)
T.talk(function() return T.st().fleet[1] end, {function() return T.st().audit.excuses[2] end}, {name = "CAS Double Entry"})
T.step("second stall", function()
    local a = T.st().audit
    T.eq("stall: two", a.stalls, 2)
    T.check("stall: the final notice", T.msg():find("final notice", 1, true) ~= nil, T.msg())
    T.check("stall: no third excuse", not T.hasReply(a.excuses[3]), table.concat(T.replies(), " | "))
    T.check("stall: transmit or refuse remain", T.hasReply("Transmit the data.") and T.hasReply("Not today."))
    T.eq("stall: still holding fire", T.st().fleet[1]:getFaction(), "Concord")
    T.eq("carry: still carrying", T.phase(), "carry")
end)
T.closeComms()
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
T.step("a minute of silence", function()
    T.check("silence: the second ship's hail did not reset the clock", T.now() - T.st().audit.last < 30)
    T.st().audit.last = T.now() - 61
end)
T.waitFor("silence: the auditors attack", function() return T.st().audit.state == "hostile" end, 3)
T.step("collections", function()
    local f = T.st().fleet
    T.eq("hostile: faction", f[1]:getFaction(), "Concord Hostile")
    T.check("hostile: an enemy now", f[1]:isEnemy(T.P()))
    T.check("hostile: objective changes", (RT.objectives.ledger or ""):find("Escape the audit", 1, true) ~= nil)
    T.eq("hostile: every auditor's jammer cooldown started", #T.st().jammers, 3)
end)
T.step("no combat jammer right away", function()
    local dropped = 0
    for _, r in ipairs(T.st().jammers) do if r.jammer then dropped = dropped + 1 end end
    T.eq("hostile: no combat jammer during the cooldown", dropped, 0)
end)

-- ── Deliver ──────────────────────────────────────────────────────────────────
T.step("refill and fly home", function()
    T.P():setEnergyLevel(T.P():getMaxEnergy())
    T.moveNear(T.st().station, 3000)
end)
T.dock(function() return T.st().station end)
T.step("note credits and standing", function()   -- here, not earlier: new regions pay survey credits
    c0, concord0, indep0 = T.credits(), T.rep("Concord"), T.rep("Independent")
end)
T.talk(function() return T.st().station end, {"You were right, this thing runs hot."})
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

-- ── The stop fails other ways: refusing, shooting a jammer, shooting an auditor ──
local function freshStop(label)
    T.step(label, function()
        T.jump("carry")
        T.P():setEnergyLevel(T.P():getMaxEnergy())
        T.action("Fleet now")
    end)
    T.waitFor(label .. ": stopped", function() return T.st().audit and T.st().audit.state == "stopped" end, 5)
end
freshStop("refuse")
T.talk(function() return T.st().fleet[1] end, {"Not today."}, {name = "CAS Double Entry"})
T.step("refused", function()
    T.eq("refuse: hostile", T.st().audit.state, "hostile")
    T.eq("refuse: still carrying", T.phase(), "carry")
end)
T.closeComms()
freshStop("jammer")
T.step("shoot a jammer", function() T.st().audit.jams[2]:destroy() end)
T.waitFor("jammer: the auditors attack", function() return T.st().audit.state == "hostile" end, 3)
freshStop("fired")
T.step("someone else damages an auditor", function()
    local s = T.st().fleet[2]
    local x, y = s:getPosition()
    applyDamageToEntity(s, 5, {type = "kinetic", x = x + 500, y = y})   -- no instigator: a mine, a collision
    local raider = CpuShip():setTemplate("MT52 Hornet"):setFaction("Corsairs"):setPosition(x + 3000, y)
    applyDamageToEntity(s, 5, {instigator = raider, type = "energy", x = x + 500, y = y})
    raider:destroy()
end)
T.wait(2)
T.step("not the crew: no assault", function()
    local s = T.st().fleet[2]
    T.check("fired: the auditor did take damage", s:getHull() < s:getHullMax() or s:getShieldLevel(0) < s:getShieldMax(0))
    T.check("fired: other fire is not blamed on the crew", T.st().audit.state ~= "hostile")
end)
T.step("the crew shoots an auditor", function()
    local s = T.st().fleet[2]
    local x, y = s:getPosition()
    applyDamageToEntity(s, 5, {instigator = T.P(), type = "energy", x = x + 500, y = y})
end)
T.waitFor("fired: the auditors attack", function() return T.st().audit.state == "hostile" end, 3)

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

-- ── Losing the AI ends the audit at once: no jammers, no attack ──────────────
local held
freshStop("audit, then eject")
T.talk(function() return T.st().fleet[1] end, {"Not today."}, {name = "CAS Double Entry"})
T.closeComms()
T.step("hostile and boxed in; Engineering ejects the AI", function()
    local st = T.st()
    T.eq("stand down: the auditors attack", st.audit.state, "hostile")
    held = {fleet = {}, jams = {}}
    for i, s in ipairs(st.fleet) do held.fleet[i] = s end
    for i, j in ipairs(st.audit.jams) do held.jams[i] = j end
    T.check("stand down: the jammer triangle is out", #held.jams > 0 and RT.valid(held.jams[1]))
    M_ledger.ejectPressed(); M_ledger.ejectPressed()
end)
T.step("the audit stands down", function()
    T.eq("stand down: the arc ends", T.status(), "done")
    T.eq("stand down: reason", T.flag("ledger_lost_reason"), "ejected")
    local jams, hostile = 0, 0
    for _, j in ipairs(held.jams) do if RT.valid(j) then jams = jams + 1 end end
    for _, s in ipairs(held.fleet) do
        if RT.valid(s) and s:getFaction() ~= "Concord" then hostile = hostile + 1 end
    end
    T.eq("stand down: the jammer triangle is gone", jams, 0)
    T.eq("stand down: no auditor still hostile", hostile, 0)
    T.eq("stand down: no combat jammers held", #(T.st().jammers or {}), 0)
    local ok, ord = pcall(function() return held.fleet[1]:getOrder() end)
    T.check("stand down: flying home, not attacking", ok and ord ~= "Attack", ord)
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

-- ── GM Enable/Disable on a finished arc (playtest: the job count started over, and the audit
-- fleet turned up in what should have been the hook) ─────────────────────────────────────────
local toggle = {}
T.step("a finished carry, the fleet standing down", function()
    RT.flag("rezkov_arc_done", "data_delivered")
    RT.campaign.upgrades = {"hull_plating", "shield_mk2", "forward_beams", "beam_coils"}   -- 1000 cr
    T.jump("carry")
    T.P():setEnergyLevel(T.P():getMaxEnergy())
    T.action("Fleet now")
    toggle.fleet = {}
    for i, s in ipairs(T.st().fleet) do toggle.fleet[i] = s end
    M_ledger.ejectPressed(); M_ledger.ejectPressed()
end)
T.step("done, then jobs since Rezkov", function()
    T.eq("toggle: the arc is done", T.status(), "done")
    T.check("toggle: the fleet was out", #toggle.fleet == 3)
    RT.flag("ledger_jobs_base", (RT.shipRecord().jobs_done or 0))
    finishJob(); finishJob()
    toggle.base = RT.flag("ledger_jobs_base")
    T.check("toggle: two jobs since Rezkov", gate())
    MISSIONS.gmToggleEnabled("ledger")   -- GM: Disable arc
end)
T.step("disabled", function()
    T.eq("toggle: the job count's start is kept", RT.flag("ledger_jobs_base"), toggle.base)
    local alive = 0
    for _, s in ipairs(toggle.fleet) do if RT.valid(s) then alive = alive + 1 end end
    T.eq("toggle: the audit fleet is gone", alive, 0)
    MISSIONS.gmToggleEnabled("ledger")   -- GM: Enable arc
end)
T.waitFor("toggle: re-enabled, the gate still met, the arc starts again", function() return T.status() == "active" end, 3)
T.step("in the hook, clean", function()
    T.eq("toggle: in the hook", T.phase(), "hook")
    T.check("toggle: two jobs still count", gate())
    T.check("toggle: the criteria show 2+", MISSIONS._criteriaText("ledger"):find("(now: 2+)", 1, true) ~= nil)
    T.check("toggle: no fragments", not T.flag("ledger_frag_1") and not T.flag("ledger_frag_3"))
    T.check("toggle: no fleet due", T.st().fleet_due == nil and not T.st().fleet_spawned)
    T.check("toggle: no drain", not T.st().drain_on)
end)
T.wait(3)
T.step("still no auditors", function()
    T.eq("toggle: still the hook", T.phase(), "hook")
    T.check("toggle: no audit ship anywhere", T.find("CAS Double Entry") == nil and T.find("CAS Debit") == nil)
end)
-- Every GM way back to the hook from a carry whose fleet is due: the fleet must never come.
local saved_delay = AUDIT.FLEET_DELAY
local function backToHook(label, how)
    T.step(label .. ": carry, the fleet due in 2 s", function()
        AUDIT.FLEET_DELAY = 2
        T.jump("carry")
        T.P():setEnergyLevel(T.P():getMaxEnergy())
        T.check(label .. ": fleet due", T.st().fleet_due ~= nil)
        how()
    end)
    T.wait(4)
    T.step(label .. ": no fleet", function()
        T.check(label .. ": not in the carry", T.phase() ~= "carry", T.phase())
        T.check(label .. ": no audit ship anywhere", T.find("CAS Double Entry") == nil, tostring(T.phase()))
        T.check(label .. ": no fleet due", T.st().fleet_due == nil)
    end)
end
backToHook("jump to the hook", function() T.jump("hook") end)
backToHook("-> Inactive then Enable", function() MISSIONS.gmDeactivate("ledger"); MISSIONS.gmToggleEnabled("ledger") end)
T.step("restore the fleet delay", function() AUDIT.FLEET_DELAY = saved_delay end)
-- The GM's "Satisfy done jobs": the gate's job count is met at once.
T.step("GM: back to waiting, jobs not done", function()
    MISSIONS.gmToggleEnabled("ledger")   -- disable (resets)
    RT.flag("ledger_jobs_base", (RT.shipRecord().jobs_done or 0))
    T.check("satisfy: the gate is closed", not gate())
    T.action("Satisfy done jobs")
    T.check("satisfy: the gate is open", gate())
    T.check("satisfy: the criteria show 2+", MISSIONS._criteriaText("ledger"):find("(now: 2+)", 1, true) ~= nil)
    RT.campaign.upgrades = {}
    RT.clearFlag("rezkov_arc_done")
    MISSIONS.setEnabled("ledger", true)
end)

T.deactivate({
    gone = {"Rezkov's station", "CAS Double Entry", "CAS Debit", "Data core", "Power cell"},
    check = function()
        T.check("inactive: AI voice gone", not RT.voice.exists("ledger_ai"))
        T.check("inactive: Thresh profile forgotten", not SCIDB.known("thresh_profile"))
    end,
})
