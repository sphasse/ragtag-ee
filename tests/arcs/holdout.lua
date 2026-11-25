-- The Holdout: the gate (Rezkov over + 1,500 cr of upgrades), the seed rumors (the hiring one sets the
-- objective), Calloway's two pages at Breaker's Claim, the Claim fortified (hull, lasers that pick the
-- nearest raider), three waves of Shroud Raiders from the two gates (faction, no warp, half on the
-- Claim and half on the Magpie), the gap between waves, the pay (3,000 cr, Independent +150), the
-- Claim falling, the Magpie lost, every GM state and "-> Inactive".
-- Not covered: a real fight (waves are removed, the Claim's hull is set), who wins, the flight.

T.arc("holdout")

local M_h = MISSIONS._registry.holdout
local c0, ind0, saved_upgrades, raider_hit

local function claim() return T.find("Breaker's Claim") end
local function raiders() return ARC.alive(T.st().raiders or {}) end
local function seedWith(text)
    for _, r in ipairs(RUMORS._injected or {}) do
        if r.category == "HOLDOUT_SEED" and r.text:find(text, 1, true) then return r end
    end
end
local function killWave() for _, r in ipairs(raiders()) do r:destroy() end end
local function nextWaveNow() T.st().next_at = getScenarioTime() end

-- ── The port and the faction ─────────────────────────────────────────────────
T.step("Breaker's Claim and the Shroud Raiders", function()
    T.check("port: Breaker's Claim exists", claim() ~= nil)
    T.eq("port: Independent", claim():getFaction(), "Independent")
    T.eq("port: stock hull", claim():getHullMax(), 150)
    T.check("faction: Shroud Raiders are hostile to the crew", VERSE.HOSTILE_FACTIONS["Shroud Raiders"] == true)
    T.check("faction: no standing to lose", not RT.KILL_PENALTY_FACTIONS["Shroud Raiders"])
end)

-- ── The gate ─────────────────────────────────────────────────────────────────
T.step("the gate: Rezkov not over", function()
    saved_upgrades = RT.campaign.upgrades
    RT.campaign.upgrades = {}
    RT.clearFlag("rezkov_arc_done")
    RT.clearFlag("rezkov_declined")
    T.check("gate: closed before Rezkov", not M_h.triggers.requires())
    RT.flag("rezkov_arc_done", "data_delivered")
    T.check("gate: Rezkov over", M_h.triggers.requires())
    -- 200 + 250 + 300 + 250 = 1000: short of 1,500.
    RT.campaign.upgrades = {"hull_plating", "shield_mk2", "forward_beams", "beam_coils"}
end)
T.wait(1)
T.step("upgrades short", function()
    T.eq("gate: waiting for 1,500 cr of upgrades", T.status(), "inactive")
    RT.campaign.upgrades = {"hull_plating", "shield_mk2", "forward_beams", "beam_coils", "sensor_suite"}
end)
T.waitFor("gate: the arc starts on its own", function() return T.status() == "active" end, 3)
T.step("upgrades back", function() RT.campaign.upgrades = saved_upgrades or {} end)

-- ── Hook: seed rumors, Calloway's offer ──────────────────────────────────────
T.step("hook", function()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three seed rumors", T.rumors("HOLDOUT_SEED"), 3)
    T.check("hook: no objective until the hiring is heard of", RT.objectives.holdout == nil)
    local r = seedWith("Breaker's Claim is hiring guns")
    T.check("hook: the hiring rumor", r ~= nil)
    T.eq("hook: Independent ports only", r and r.faction, "Independent")
    r.on_heard()
    T.eq("hook: hearing it sets the objective", RT.objectives.holdout, "Breaker's Claim")
end)
T.dock("Breaker's Claim")
T.talk("Breaker's Claim", {"[SPECIAL] Calloway's offer"})
T.step("page 1: Calloway", function()
    T.check("p1: Calloway", T.msg():find("Ines Calloway. I run this claim.", 1, true) ~= nil, T.msg())
    T.check("p1: the Shroud Raiders", T.msg():find("Shroud Raiders", 1, true) ~= nil, T.msg())
    T.check("p1: her profile", SCIDB.known("calloway_profile"))
end)
T.reply({"Go on."})
T.step("page 2: the raid and the pay", function()
    T.check("p2: out of the fog", T.msg():find("out of the fog north of us", 1, true) ~= nil, T.msg())
    T.check("p2: the pay", T.msg():find("3,000 credits", 1, true) ~= nil, T.msg())
end)
T.reply({"Not right now."})
T.step("not right now: still the hook", function() T.eq("decline: hook", T.phase(), "hook") end)
T.talk("Breaker's Claim", {"[SPECIAL] Calloway's offer", "Go on.", "We'll stay."})
T.step("defend", function()
    T.eq("defend: phase", T.phase(), "defend")
    T.check("defend: briefed", T.flag("holdout_briefed"))
    T.eq("defend: seeds gone", T.rumors("HOLDOUT_SEED"), 0)
    T.eq("defend: objective", RT.objectives.holdout, "Defend the Claim")
    T.check("defend: the raid entry", SCIDB._entries["holdout_raid"] ~= nil)
    T.eq("defend: the Claim reinforced", claim():getHullMax(), M_h.OUTPOST_HULL)
    T.eq("defend: cutting lasers", claim():getBeamWeaponRange(0), M_h.LASERS.range)
    T.check("defend: Shroud patrols held off", PROX._suspended_zones["the Shroud"] ~= nil)
    T.eq("defend: no wave yet", #raiders(), 0)
    T.check("defend: the first wave comes in about a minute",
        math.abs(T.st().next_at - getScenarioTime() - M_h.PREP_TIME) < 3)
    T.check("defend: no offer now", not T.hasReply("[SPECIAL] Calloway's offer"))
end)
T.closeComms()

-- ── Wave 1 ───────────────────────────────────────────────────────────────────
T.step("wave 1 now", function() T.undock(); nextWaveNow() end)
T.waitFor("wave 1", function() return T.st().wave == 1 end, 3)
T.step("wave 1: the raiders", function()
    local rs = raiders()
    T.eq("wave 1: three raiders", #rs, #M_h.WAVES[1])
    T.eq("wave 1: objective", RT.objectives.holdout, "Hold: wave 1 of 3")
    T.eq("wave 1: Shroud Raiders", rs[1]:getFaction(), "Shroud Raiders")
    T.check("wave 1: enemies of the Magpie", rs[1]:isEnemy(T.P()))
    T.check("wave 1: no warp", not rs[1]:hasWarpDrive())
    T.eq("wave 1: the first goes for the Claim", rs[1]:getOrderTarget(), claim())
    T.eq("wave 1: the second for the Magpie", rs[2]:getOrderTarget(), T.P())
    -- From the two gates, about 19U north of the Claim.
    local cx, cy = claim():getPosition()
    for i, r in ipairs(rs) do
        local g = M_h.GATES[(i - 1) % #M_h.GATES + 1]
        local x, y = r:getPosition()
        T.check("wave 1: raider " .. i .. " at its gate", math.sqrt((x / 1000 - g[1]) ^ 2 + (y / 1000 - g[2]) ^ 2) < 3)
        T.check("wave 1: raider " .. i .. " north of the Claim", y < cy - 10000)
    end
    -- A raider in laser range draws the Claim's fire.
    rs[1]:setPosition(cx + 1500, cy)
    local function hit(_, instigator) if instigator == claim() then raider_hit = true end end
    rs[1]:onTakingDamage(hit)
    rs[1]:onTakingShieldDamage(hit)
end)
T.waitFor("the Claim's lasers pick the raider in range", function()
    return T.st().laser_target == raiders()[1]
end, 3)
T.waitFor("the Claim's lasers hit it", function() return raider_hit end, 10)
T.step("wave 1 beaten", function() killWave() end)
T.waitFor("the gap before wave 2", function() return T.st().next_at ~= nil end, 3)
T.step("the gap", function()
    T.eq("gap: objective", RT.objectives.holdout, "Hold: wave 2 next")
    T.check("gap: about 45 seconds", math.abs(T.st().next_at - getScenarioTime() - M_h.WAVE_GAP) < 3)
    T.eq("gap: still defending", T.phase(), "defend")
    nextWaveNow()
end)

-- ── Waves 2 and 3 ────────────────────────────────────────────────────────────
T.waitFor("wave 2", function() return T.st().wave == 2 end, 3)
T.step("wave 2", function()
    T.eq("wave 2: three raiders", #raiders(), #M_h.WAVES[2])
    killWave()
end)
T.waitFor("the gap before wave 3", function() return T.st().next_at ~= nil end, 3)
T.step("wave 3 now", function() nextWaveNow() end)
T.waitFor("wave 3", function() return T.st().wave == 3 end, 3)
T.step("wave 3", function()
    T.eq("wave 3: four raiders", #raiders(), #M_h.WAVES[3])
    T.eq("wave 3: objective", RT.objectives.holdout, "Hold: wave 3 of 3")
    c0, ind0 = T.credits(), T.rep("Independent")
    killWave()
end)
T.waitFor("defended", function() return T.status() == "done" end, 3)
T.step("defended", function()
    T.eq("defended: outcome", T.flag("holdout_arc_done"), "defended")
    T.eq("defended: +3,000", T.credits() - c0, 3000)
    T.eq("defended: Independent +150", T.rep("Independent") - ind0, 150)
    T.check("defended: no objective", RT.objectives.holdout == nil)
    T.eq("defended: the Claim back to its own hull", claim():getHullMax(), 150)
    T.eq("defended: the lasers down", claim():getBeamWeaponRange(0), 0)
    T.check("defended: Shroud patrols back", PROX._suspended_zones["the Shroud"] == nil)
end)
T.waitFor("achievement: Hold the Line", function() return ACH.has("hold_the_line") end, 7)
T.step("news", function() T.eq("news: two lines", T.rumors("HOLDOUT_DONE"), 2) end)

-- ── The Claim falls ──────────────────────────────────────────────────────────
T.step("defend again, the Claim's hull fails", function()
    T.jump("defend")
    nextWaveNow()
end)
T.waitFor("wave 1 again", function() return T.st().wave == 1 end, 3)
T.step("hull", function() claim():setHull(M_h.OUTPOST_HULL * 0.1) end)
T.waitFor("fallen", function() return T.status() == "done" end, 3)
T.step("fallen", function()
    T.eq("fallen: outcome", T.flag("holdout_arc_done"), "fallen")
    T.eq("fallen: the Claim patched up", claim():getHull(), 150)
    T.check("fallen: no pay flag", not T.flag("holdout_rewarded"))
    T.eq("fallen: the news", T.rumors("HOLDOUT_DONE"), 1)
end)
T.waitFor("fallen: the raiders go back into the fog", function() return #raiders() == 0 end, 95)

-- ── The Magpie lost ──────────────────────────────────────────────────────────
T.step("defend, then the Magpie is lost", function()
    T.jump("defend")
    RT.emit("ship_lost", {ship = T.P():getCallSign(), primary = true, credits_lost = 0, credits = 0}, "high")
end)
T.wait(1)
T.step("lost", function()
    T.eq("lost: outcome", T.flag("holdout_arc_done"), "lost")
    T.eq("lost: done", T.status(), "done")
end)

-- ── GM states ────────────────────────────────────────────────────────────────
T.gmWalk({
    {key = "hook", phase = "hook", check = function()
        T.eq("GM hook: the seeds again", T.rumors("HOLDOUT_SEED"), 3)
        T.eq("GM hook: the Claim not reinforced", claim():getHullMax(), 150)
    end},
    {key = "defend", phase = "defend", check = function()
        T.check("GM defend: briefed replayed", T.flag("holdout_briefed"))
        T.eq("GM defend: reinforced", claim():getHullMax(), M_h.OUTPOST_HULL)
        T.action("Next wave now")
        T.check("GM defend: Next wave now", T.st().next_at <= getScenarioTime())
        T.action("Kill this wave")
        T.eq("GM defend: Kill this wave", #raiders(), 0)
        claim():setHull(200)
        T.action("Repair the Claim")
        T.eq("GM defend: Repair the Claim", claim():getHull(), M_h.OUTPOST_HULL)
        T.restart()
        T.eq("next session: the raid starts over", T.phase(), "defend")
        T.eq("next session: no wave yet", T.st().wave, 0)
        T.eq("next session: reinforced from the Claim's own hull", claim():getHullMax(), M_h.OUTPOST_HULL)
    end},
    {key = "done_defended", done = true, check = function()
        T.eq("GM defended: outcome", T.flag("holdout_arc_done"), "defended")
        T.eq("GM defended: the Claim's own hull", claim():getHullMax(), 150)
    end},
    {key = "done_fallen", done = true, check = function()
        T.eq("GM fallen: outcome", T.flag("holdout_arc_done"), "fallen")
    end},
    {key = "done_lost", done = true, check = function()
        T.eq("GM lost: outcome", T.flag("holdout_arc_done"), "lost")
        T.restart()
        T.eq("next session: done", T.status(), "done")
    end},
})

T.deactivate({
    check = function()
        T.check("inactive: no raid entry", SCIDB._entries["holdout_raid"] == nil)
        T.eq("inactive: no seeds", T.rumors("HOLDOUT_SEED"), 0)
        T.eq("inactive: the Claim's own hull", claim():getHullMax(), 150)
        T.check("inactive: Shroud patrols back", PROX._suspended_zones["the Shroud"] == nil)
    end,
})
