-- The Bounty: the gate (Rezkov over + 1,000 cr of upgrades), the seed rumors (the notice's sets the
-- objective), Thresh's two pages at Dustmote Salvage, Long Odds and its two escorts in the Deep
-- Shroud (Fugitive, hidden until found within 8U), the run, the disable rule (impulse and rear shield
-- both down), boarding, Ashby's offer, both drops (Dustmote: 3,000 cr and Independent +100; Saint
-- Brennan's: 4,500 cr and Independent -150), the Magpie lost with him aboard, every GM state and
-- "-> Inactive".
-- Not covered: a real fight (hull and system health are set), probes and the nebula's sensor
-- blackout, a real dock (forced), the flight.

T.arc("bounty")

local M_b = MISSIONS._registry.bounty
local c0, ind0, saved_upgrades

local function long() return T.st().long end
local function escorts() return T.st().escorts or {} end
local function seedWith(text)
    for _, r in ipairs(RUMORS._injected or {}) do
        if r.category == "BOUNTY_SEED" and r.text:find(text, 1, true) then return r end
    end
end
local function inShroud(e)
    local x, y = e:getPosition()
    return math.sqrt((x / 1000 - 156) ^ 2 + (y / 1000 + 29) ^ 2) < 42
end

-- ── The gate ─────────────────────────────────────────────────────────────────
T.step("the gate: Rezkov not over", function()
    saved_upgrades = RT.campaign.upgrades
    RT.campaign.upgrades = {}
    RT.clearFlag("rezkov_arc_done")
    RT.clearFlag("rezkov_declined")
    T.check("gate: closed before Rezkov", not M_b.triggers.requires())
    RT.flag("rezkov_arc_done", "data_delivered")
    T.check("gate: Rezkov over", M_b.triggers.requires())
end)
T.wait(1)
T.step("upgrades short", function()
    T.eq("gate: waiting for 1,000 cr of upgrades", T.status(), "inactive")
    -- Bought, not applied (the spend is all the trigger reads): 200 + 250 + 300 + 250 = 1000.
    RT.campaign.upgrades = {"hull_plating", "shield_mk2", "forward_beams", "beam_coils"}
end)
T.waitFor("gate: the arc starts on its own", function() return T.status() == "active" end, 3)
T.step("upgrades back", function() RT.campaign.upgrades = saved_upgrades or {} end)

-- ── Hook: seed rumors, Thresh's notice ───────────────────────────────────────
T.step("hook", function()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three seed rumors", T.rumors("BOUNTY_SEED"), 3)
    T.check("hook: no objective until the notice is heard of", RT.objectives.bounty == nil)
    local r = seedWith("guild bounty posted at Dustmote Salvage")
    T.check("hook: the notice rumor", r ~= nil)
    T.eq("hook: Independent ports only", r and r.faction, "Independent")
    r.on_heard()
    T.eq("hook: hearing it sets the objective", RT.objectives.bounty, "Bounty at Dustmote")
end)
T.dock("Dustmote Salvage")
T.talk("Dustmote Salvage", {"[SPECIAL] Bounty: Pell Ashby, alive"})
T.step("page 1: the notice", function()
    T.check("p1: the notice", T.msg():find("BOUNTY: PELL ASHBY", 1, true) ~= nil, T.msg())
    T.check("p1: alive", T.msg():find("ALIVE. NO EXCEPTIONS.", 1, true) ~= nil, T.msg())
    T.check("p1: Thresh's profile", SCIDB.known("thresh_profile"))
end)
T.reply({"Go on."})
T.step("page 2: the trail", function()
    T.check("p2: the Deep Shroud", T.msg():find("went into the Deep Shroud", 1, true) ~= nil, T.msg())
    T.check("p2: the sector", T.msg():find("Last ping was near " .. getSectorName(T.st().hide_x, T.st().hide_y), 1, true) ~= nil, T.msg())
    T.check("p2: how to stop it", T.msg():find("engines and its rear shield together", 1, true) ~= nil, T.msg())
end)
T.reply({"Not right now."})
T.step("not right now: still the hook", function() T.eq("decline: hook", T.phase(), "hook") end)
T.talk("Dustmote Salvage", {"[SPECIAL] Bounty: Pell Ashby, alive", "Go on.", "We'll take it."})
T.step("the hunt", function()
    T.eq("hunt: phase", T.phase(), "hunt")
    T.check("hunt: briefed", T.flag("bounty_briefed"))
    T.eq("hunt: seeds gone", T.rumors("BOUNTY_SEED"), 0)
    T.eq("hunt: objective", RT.objectives.bounty, "Find Long Odds")
    T.check("hunt: the notice entry", SCIDB._entries["bounty_notice"] ~= nil)
    T.check("hunt: Long Odds", RT.valid(long()))
    T.eq("hunt: two escorts", #ARC.alive(escorts()), 2)
    T.eq("hunt: Long Odds is a fugitive", long():getFaction(), "Fugitive")
    T.eq("hunt: an escort is a fugitive", escorts()[1]:getFaction(), "Fugitive")
    T.check("hunt: in the Deep Shroud", inShroud(long()))
    T.check("hunt: hiding where Thresh said", math.abs(long():getPosition() - T.st().hide_x) < 100)
    T.eq("hunt: tough hull", long():getHullMax(), 300)
    T.check("hunt: the hunted ship is a fugitive, not a player kill to punish", T.find("Long Odds") ~= nil)
end)
T.closeComms()

-- ── Found ────────────────────────────────────────────────────────────────────
T.step("20U away", function()
    T.undock()
    local x, y = long():getPosition()
    T.moveTo(x - 20000, y)
end)
T.wait(1)
T.step("not found at 20U", function()
    T.check("found: not yet", not T.st().found)
    local x, y = long():getPosition()
    T.moveTo(x - 6000, y)
end)
T.waitFor("found within 8U", function() return T.st().found end, 3)
T.wait(1)
T.step("it runs, the escorts attack", function()
    T.check("found: flagged", T.flag("bounty_found"))
    T.eq("found: objective", RT.objectives.bounty, "Disable Long Odds")
    T.eq("run: Long Odds flies", long():getOrder(), "Fly towards")
    local tx, ty = long():getOrderTargetLocation()
    T.check("run: a leg inside the nebula", math.sqrt((tx / 1000 - 156) ^ 2 + (ty / 1000 + 29) ^ 2) < 42)
    T.eq("escorts: attack", escorts()[1]:getOrder(), "Attack")
    T.eq("escorts: the Magpie", escorts()[1]:getOrderTarget(), T.P())
    -- It cannot be destroyed: the contract says alive.
    long():setHull(1)
    long():takeDamage(500, "kinetic", long():getPosition())
end)
T.wait(1)
T.step("cannot be destroyed", function()
    T.check("alive: Long Odds survives", RT.valid(long()))
    long():setHull(300)
    long():setSystemHackedLevel("impulse", 1.0)
end)
T.wait(1)
T.step("one system down is not enough", function()
    T.check("disable: impulse alone is not enough", not T.st().disabled)
    long():setSystemHackedLevel("impulse", 1.0)
    long():setSystemHealth("rearshield", 0.05)
end)
T.waitFor("both down: disabled", function() return T.st().disabled end, 3)
T.step("disabled", function()
    T.eq("disabled: nobody's enemy now", long():getFaction(), "Independent")
    T.eq("disabled: objective", RT.objectives.bounty, "Dock with Long Odds")
    T.eq("disabled: the escorts break off", escorts()[1]:getOrder(), "Fly towards")
end)
T.dock(function() return T.st().long end)
T.waitFor("boarded: Ashby aboard", function() return T.phase() == "deliver" end, 3)
T.waitFor("Ashby's offer", function() return T.flag("bounty_offered") end, 6)
T.step("the offer", function()
    T.check("deliver: captured", T.flag("bounty_captured"))
    T.eq("deliver: objective", RT.objectives.bounty, "Deliver Ashby")
    T.check("offer: his side in the Science DB", SCIDB._entries["bounty_ashby"] ~= nil)
    local e = SCIDB._entries["bounty_ashby"]
    T.check("offer: the keys in his head", e and e:getLongDescription():find("The keys are memorized", 1, true) ~= nil)
    T.check("offer: the voice", RT.voice.exists("bounty_ashby"))
end)

-- ── Handed to the guild ──────────────────────────────────────────────────────
T.dock("Dustmote Salvage")
T.step("credits before", function() c0, ind0 = T.credits(), T.rep("Independent") end)
T.talk("Dustmote Salvage", {"Hand Ashby to the guild"})
T.step("the bounty", function()
    T.check("bounty: Thresh pays", T.msg():find("Alive, as ordered.", 1, true) ~= nil, T.msg())
    T.eq("bounty: +3,000", T.credits() - c0, 3000)
    T.eq("bounty: Independent +100", T.rep("Independent") - ind0, 100)
    T.eq("bounty: outcome", T.flag("bounty_arc_done"), "bounty")
    T.eq("bounty: done", T.status(), "done")
    T.check("bounty: no objective", RT.objectives.bounty == nil)
    T.check("bounty: the voice is gone", not RT.voice.exists("bounty_ashby"))
end)
T.closeComms()
T.waitFor("achievement: Bring Him In", function() return ACH.has("bring_him_in") end, 7)
T.step("news", function() T.eq("news: two lines", T.rumors("BOUNTY_DONE"), 2) end)

-- ── Let go at Saint Brennan's ────────────────────────────────────────────────
T.step("deliver again", function() T.jump("deliver") end)
T.dock("Saint Brennan's Mission")
T.wait(3)   -- a first visit's survey pay (the region check runs every few seconds) lands first
T.step("credits before", function() c0, ind0 = T.credits(), T.rep("Independent") end)
T.talk("Saint Brennan's Mission", {"Let Ashby off here"})
T.step("released", function()
    T.check("released: the order takes him in", T.msg():find("Two sisters of the order", 1, true) ~= nil, T.msg())
    T.eq("released: +4,500", T.credits() - c0, 4500)
    T.eq("released: Independent -150", T.rep("Independent") - ind0, -150)
    T.eq("released: outcome", T.flag("bounty_arc_done"), "released")
end)
T.closeComms()
T.waitFor("achievement: Everyone Has a Price", function() return ACH.has("everyone_has_a_price") end, 7)
T.dock("Dustmote Salvage")
T.talk("Dustmote Salvage", {})
T.step("nothing to hand over now", function()
    T.check("done: no hand-over at Dustmote", not T.hasReply("Hand Ashby to the guild"))
end)
T.closeComms()

-- ── The Magpie lost with Ashby aboard ────────────────────────────────────────
T.step("deliver, then the Magpie is lost", function()
    T.jump("deliver")
    RT.emit("ship_lost", {ship = T.P():getCallSign(), primary = true, credits_lost = 0, credits = 0}, "high")
end)
T.wait(1)
T.step("lost", function()
    T.eq("lost: outcome", T.flag("bounty_arc_done"), "lost")
    T.eq("lost: done", T.status(), "done")
end)

-- ── GM states ────────────────────────────────────────────────────────────────
T.gmWalk({
    {key = "hook", phase = "hook", check = function()
        T.eq("GM hook: the seeds again", T.rumors("BOUNTY_SEED"), 3)
        T.check("GM hook: no Long Odds", not RT.valid(long()))
    end},
    {key = "hunt", phase = "hunt", check = function()
        T.check("GM hunt: briefed replayed", T.flag("bounty_briefed"))
        T.check("GM hunt: Long Odds", RT.valid(long()))
        T.eq("GM hunt: two escorts", #ARC.alive(escorts()), 2)
        T.action("Kill escorts")
        T.eq("GM hunt: escorts gone", #ARC.alive(escorts()), 0)
        T.action("Disable Long Odds")
        T.restart()
        T.eq("next session: the hunt starts over", T.phase(), "hunt")
        T.check("next session: Long Odds back", RT.valid(long()))
    end},
    {key = "deliver", phase = "deliver", check = function()
        T.check("GM deliver: captured", T.flag("bounty_captured"))
        T.check("GM deliver: no Long Odds", not RT.valid(long()))
        T.restart()
        T.eq("next session: still delivering", T.phase(), "deliver")
    end},
    {key = "done_bounty", done = true, check = function()
        T.eq("GM bounty: outcome", T.flag("bounty_arc_done"), "bounty")
    end},
    {key = "done_released", done = true, check = function()
        T.eq("GM released: outcome", T.flag("bounty_arc_done"), "released")
    end},
    {key = "done_lost", done = true, check = function()
        T.eq("GM lost: outcome", T.flag("bounty_arc_done"), "lost")
        T.restart()
        T.eq("next session: done", T.status(), "done")
    end},
})

T.deactivate({
    gone = {"Long Odds", "Second Thoughts", "Paid in Full"},
    check = function()
        T.check("inactive: no notice entry", SCIDB._entries["bounty_notice"] == nil)
        T.check("inactive: no Ashby entry", SCIDB._entries["bounty_ashby"] == nil)
        T.eq("inactive: no seeds", T.rumors("BOUNTY_SEED"), 0)
        T.check("inactive: no voice", not RT.voice.exists("bounty_ashby"))
    end,
})
