-- Boneyard arc: hook -> annex_hack -> annex_control (download, drone IFF flip, Annex lasers) -> done
-- (full), then the GM states and "-> Inactive". Not covered: the lifeboat rescue job (the other
-- way to reveal the Annex), a real Relay hack (the GM helper sets the level), how the fight plays
-- out (the Battle Lab's Annex mode is for that); covered: who spawns where, how fast, with what
-- lasers, drone replacement from the same nebula, and the Annex's lasers picking a Concord ship.
-- The 4 min download and the 60 s reprogram and laser timers are shortened by moving their start times back.

T.arc("boneyard")

local ANNEX_X, ANNEX_Y = 43000, -104000
local function annex() return T.st().annex end
local c0, concord0, corsairs0

-- Ships in and around the Boneyard by faction, e.g. "Derelict=3 Relic=14".
local function census()
    local n = {}
    for _, o in ipairs(getObjectsInRadius(36000, -96000, 60000)) do
        if isObjectType(o, "CpuShip") then
            local f = o:getFaction()
            if f == "Concord Hostile" or f == "Relic Active" or f == "Derelict" or f == "Relic" then n[f] = (n[f] or 0) + 1 end
        end
    end
    local keys = {}
    for k in pairs(n) do keys[#keys + 1] = k end
    table.sort(keys)
    for i, k in ipairs(keys) do keys[i] = k .. "=" .. n[k] end
    return table.concat(keys, " ")
end
local census0

-- ── Hook: rumors and the rescue job; flying to Ashgrave reveals the Annex ────
T.step("hook", function()
    census0 = census()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three hook rumors", T.rumors("BONEYARD_HOOK"), 3)
    T.eq("hook: the rescue job is on offer", T.jobs("BONEYARD_SPECIAL"), 1)
    T.check("hook: no Annex yet", not RT.valid(annex()))
    T.moveTo(39000, -102500)   -- 6.5U from Ashgrave (clear of the planet), 4U from the Annex
end)
T.waitFor("hook: the Annex shows up near Ashgrave", function() return RT.valid(annex()) end, 3)
T.step("lead paid off", function()
    T.eq("hook: rumors removed once found", T.rumors("BONEYARD_HOOK"), 0)
    T.eq("hook: rescue job withdrawn", T.jobs("BONEYARD_SPECIAL"), 0)
    T.eq("hook: still the hook at 4U", T.phase(), "hook")
    T.moveTo(ANNEX_X, ANNEX_Y + 2000)
end)
T.waitFor("annex_hack: closing to 2.5U starts the hack", function() return T.phase() == "annex_hack" end, 3)

-- ── Hack ─────────────────────────────────────────────────────────────────────
T.talk(annex, {})
T.step("locked down", function()
    T.check("annex_hack: comms say to hack", T.msg():find("hack any system", 1, true) ~= nil, T.msg())
    T.eq("annex_hack: objective", RT.objectives.boneyard, "Hack the Annex")
    T.action("Complete hack")
end)
T.waitFor("annex_control: a finished hack opens the Annex", function() return T.phase() == "annex_control" end, 3)
local function dist(s, x, y) local sx, sy = s:getPosition(); return math.sqrt((sx - x) ^ 2 + (sy - y) ^ 2) end
T.step("battle group inbound", function()
    local g = T.st().concord_group
    T.eq("annex_control: seven Concord ships", T.alive(g), 7)
    T.eq("annex_control: battle group is hostile", g[1]:getFaction(), "Concord Hostile")
    T.eq("annex_control: the middle ship is the command ship", g[4], T.st().concord_cmd)
    T.eq("annex_control: CNS Vanguard", g[4]:getCallSign(), "CNS Vanguard")
    -- A line 15U north-west of the Annex, running north-east / south-west (ends 12U apart).
    local mx, my = g[4]:getPosition()
    T.check("annex_control: line centre 15U north-west", math.abs(dist(g[4], ANNEX_X, ANNEX_Y) - 15000) < 300
        and mx < ANNEX_X and my < ANNEX_Y, string.format("%.0f, %.0f", mx, my))
    local x1, y1 = g[1]:getPosition()
    local x7, y7 = g[7]:getPosition()
    T.check("annex_control: the line runs at 45 degrees", math.abs(math.abs(x7 - x1) - math.abs(y7 - y1)) < 300
        and math.abs(dist(g[1], x7, y7) - 12000) < 300, string.format("(%.0f,%.0f) (%.0f,%.0f)", x1, y1, x7, y7))
    T.check("annex_control: no warp", not g[1]:hasWarpDrive() and not g[4]:hasWarpDrive())
    T.eq("annex_control: Phobos T3 at the lab's 104 impulse", math.floor(g[4]:getImpulseMaxSpeed() + 0.5), 104)
    T.eq("annex_control: Atlantis X23 at the lab's 80 impulse", math.floor(g[1]:getImpulseMaxSpeed() + 0.5), 80)
    local p = T.st().annex_battle.b.points
    T.check("annex_control: combat points 3U north-west of the Annex",
        math.abs(math.sqrt((p[3][1] - ANNEX_X) ^ 2 + (p[3][2] - ANNEX_Y) ^ 2) - 3000) < 50 and p[3][1] < ANNEX_X and p[3][2] < ANNEX_Y)
    T.check("annex_control: the Annex is not armed yet", annex():getBeamWeaponRange(0) == 0)
    T.check("annex_control: Boneyard patrols suspended", PROX._suspended_zones["the Boneyard"])
    T.eq("annex_control: objective", RT.objectives.boneyard, "Defend the Annex")
    local relic = 0
    for _, o in ipairs(getObjectsInRadius(36000, -96000, 32000)) do
        if isObjectType(o, "CpuShip") and o:getFaction() == "Relic" then relic = relic + 1 end
    end
    T.eq("annex_control: no active Relic drones left in the Boneyard", relic, 0)
end)

-- ── Control: one operation at a time ─────────────────────────────────────────
T.talk(annex, {})
T.step("three operations on offer", function()
    T.check("control: download, 4 min", T.hasReply("1) Download research archive (4 min)"), table.concat(T.replies(), " | "))
    T.check("control: reprogram, 60 s", T.hasReply("2) Reprogram drone IFF targets (60s)"), table.concat(T.replies(), " | "))
    T.check("control: lasers, 60 s", T.hasReply("3) Enable station defense lasers (60s)"), table.concat(T.replies(), " | "))
end)
T.talk(annex, {"1) Download research archive"})
T.step("download running", function() T.check("control: downloading", T.st().download_start ~= nil) end)
T.talk(annex, {})
T.step("the others are locked meanwhile", function()
    T.check("control: download shown in progress", T.hasReply("[IN PROGRESS] Downloading archive"), table.concat(T.replies(), " | "))
    T.check("control: reprogram locked during download", T.hasReply("[LOCKED] Reprogram drone IFF"), table.concat(T.replies(), " | "))
    T.check("control: lasers locked during download", T.hasReply("[LOCKED] Enable station defense lasers"), table.concat(T.replies(), " | "))
    T.check("control: not done early", not T.flag("boneyard_hack_done"))
    T.st().download_start = T.st().download_start - 238
end)
T.waitFor("control: download completes", function() return T.flag("boneyard_hack_done") end, 5)
T.step("research indexed", function()
    T.check("control: Ashgrave research readable", SCIDB._locked.ashgrave_research and SCIDB._locked.ashgrave_research.unlocked)
end)
T.talk(annex, {"2) Reprogram drone IFF targets"})
T.step("reprogram running", function()
    T.check("control: reprogramming", T.st().reprogram_start ~= nil)
    T.check("control: no drones before the override finishes", #T.st().rein_drones == 0)
    T.st().reprogram_start = T.st().reprogram_start - 58
end)
T.waitFor("control: IFF override completes", function() return T.flag("boneyard_drone_flip") end, 5)
local G = BATTLE.ANNEX.gates
local function gateOf(s)
    for k, g in ipairs(G) do
        if dist(s, ANNEX_X + g[1] * 1000, ANNEX_Y + g[2] * 1000) < 4000 then return k end
    end
end
local victim, victim_gate
T.step("drones on our side", function()
    local d = T.st().rein_drones
    T.eq("control: 24 drones", T.alive(d), 24)
    T.eq("control: drones are Relic Active", d[1]:getFaction(), "Relic Active")
    T.eq("control: small ships (MT52 Hornet)", d[1]:getTypeName(), "MT52 Hornet")
    T.eq("control: drone lasers hit for 18 (1.5x the first 12)", d[1]:getBeamWeaponDamage(0), 18)
    T.eq("control: 1.5x the fastest Concord impulse (156)", math.floor(d[1]:getImpulseMaxSpeed() + 0.5), 156)
    T.check("control: drones have no warp", not d[1]:hasWarpDrive())
    local at = {0, 0}
    for _, s in ipairs(d) do local k = gateOf(s); if k then at[k] = at[k] + 1 end end
    T.eq("control: 12 out of the north-east nebula, 12 out of the south-west one", at[1] .. "/" .. at[2], "12/12")
    local ax, ay = ANNEX_X + G[2][1] * 1000, ANNEX_Y + G[2][2] * 1000
    T.check("control: the south-west gate is clear of Ashgrave", math.sqrt((ax - 39000) ^ 2 + (ay + 96000) ^ 2) > 5000)
    T.check("control: the drone override does not arm the Annex", annex():getBeamWeaponRange(0) == 0)
    T.eq("control: still at the Annex", T.phase(), "annex_control")
    -- A drone dies: a new one comes out of the same nebula.
    victim = d[2]
    victim_gate = gateOf(victim)
    victim:destroy()
end)
T.waitFor("control: a dead drone is replaced", function() return T.alive(T.st().rein_drones) == 24 end, 3)
T.step("from the same nebula", function()
    local d = T.st().rein_drones
    T.eq("control: the replacement came from the dead drone's nebula", gateOf(d[#d]), victim_gate)
end)
T.talk(annex, {"3) Enable station defense lasers"})
T.step("lasers booting", function()
    T.check("control: laser boot running", T.st().lasers_start ~= nil)
    T.st().lasers_start = T.st().lasers_start - 58
end)
T.waitFor("control: the lasers come online", function() return T.st().lasers_done end, 5)
T.step("the Annex is armed", function()
    T.eq("control: the Annex takes the drones' side", annex():getFaction(), "Relic Active")
    T.eq("control: the Annex has lasers", annex():getBeamWeaponRange(0), BATTLE.ANNEX.lasers.range)
    -- A Concord ship in laser range of the Annex draws its fire.
    local s = T.st().concord_group[2]
    s:setPosition(ANNEX_X - 2000, ANNEX_Y - 2000)
end)
T.waitFor("control: the Annex's lasers pick the Concord ship in range", function()
    return T.st().annex_battle.laser_target == T.st().concord_group[2]
end, 3)
T.step("annex lasers hit hard; the Concord group dies", function()
    T.eq("control: Annex lasers hit for 32", annex():getBeamWeaponDamage(0), 32)
    for _, s in ipairs(T.st().concord_group) do if s:isValid() then s:destroy() end end
end)
T.waitFor("control: with the Concord gone, the drones guard the Annex", function()
    local d = T.st().annex_battle.b:ships("b")
    if #d == 0 then return false end
    for _, s in ipairs(d) do if s:getOrderTarget() ~= annex() then return false end end
    return true
end, 4)
T.step("no more replacements once the Concord is gone", function()
    T.check("control: the crew is told the battle group is destroyed", T.st().concord_beaten)
    T.eq("control: still 24 drones", T.alive(T.st().rein_drones), 24)
end)
T.closeComms()

-- ── Leave the Boneyard: resolve ───────────────────────────────────────────────
T.step("pull back 15U from the Annex (still inside the Boneyard)", function() T.moveTo(ANNEX_X, ANNEX_Y - 15000) end)
T.step("no extract phase: still at the Annex fight", function()
    T.eq("control: 15U out is still the fight", T.phase(), "annex_control")
    c0, concord0, corsairs0 = T.credits(), T.rep("Concord"), T.rep("Corsairs")
    T.moveTo(36000, -96000 + 31000)
end)
T.waitFor("done: clearing the Boneyard resolves the arc", function() return T.status() == "done" end, 3)
T.step("resolved", function()
    T.eq("done: boneyard_arc_done", T.flag("boneyard_arc_done"), true)
    T.eq("done: objective cleared", RT.objectives.boneyard, nil)
    T.eq("done: 800 cr (data 600 + drones 200)", T.credits() - c0, 800)
    T.eq("done: Concord -500", T.rep("Concord") - concord0, -500)
    T.eq("done: Corsairs +150", T.rep("Corsairs") - corsairs0, 150)
    T.check("done: Boneyard patrols resumed", not PROX._suspended_zones["the Boneyard"])
    T.eq("done: two aftermath rumors", T.rumors("BONEYARD_DONE"), 2)
    T.check("done: the arc's achievement is defined and earned", ACH.defs.boneyard_breach and ACH.defs.boneyard_breach.check(STATS.ensure()))
end)

-- ── GM states ────────────────────────────────────────────────────────────────
local paid
-- Parked 7.6U from the Annex: inside the Boneyard (so annex_control does not end by itself), but
-- over 8U from Ashgrave (so the hook stays put).
T.step("park the ship near the Annex", function() T.moveTo(ANNEX_X + 7000, ANNEX_Y - 3000) end)
T.gmWalk({
    {key = "hook",    phase = "hook", check = function()
        T.check("GM hook: no Annex", not RT.valid(annex()))
        T.check("GM hook: no Concord group", T.alive(T.st().concord_group) == 0)
        T.eq("GM hook: rumors back", T.rumors("BONEYARD_HOOK"), 3)
    end},
    {key = "hack",    phase = "annex_hack", check = function()
        T.check("GM hack: Annex out", RT.valid(annex()))
        T.eq("GM hack: still hacking a second later", T.phase(), "annex_hack")
    end},
    {key = "control", phase = "annex_control", check = function()
        T.eq("GM control: seven Concord ships", T.alive(T.st().concord_group), 7)
        T.check("GM control: zone suspended", PROX._suspended_zones["the Boneyard"])
    end},
    {key = "done_full", done = true, check = function()
        T.check("GM done_full: both objectives", T.flag("boneyard_hack_done") and T.flag("boneyard_drone_flip"))
        T.check("GM done_full: world left clean", not RT.valid(annex()) and T.alive(T.st().concord_group) == 0)
        paid = T.credits()
    end},
    {key = "done_data", done = true, check = function()
        T.check("GM done_data: data only", T.flag("boneyard_hack_done") and not T.flag("boneyard_drone_flip"))
        T.eq("GM done_data: an end state does not pay twice", T.credits(), paid)
    end},
    {key = "done_drones", done = true, check = function()
        T.check("GM done_drones: drones only", not T.flag("boneyard_hack_done") and T.flag("boneyard_drone_flip"))
        T.check("GM done_drones: research locked again", not SCIDB._locked.ashgrave_research.unlocked)
    end},
    {key = "done_minimal", done = true, check = function()
        T.check("GM done_minimal: neither", not T.flag("boneyard_hack_done") and not T.flag("boneyard_drone_flip"))
    end},
})

T.deactivate({
    gone = {"Ashgrave Annex"},
    check = function()
        T.check("inactive: Boneyard patrols resumed", not PROX._suspended_zones["the Boneyard"])
        T.eq("inactive: no rumors", T.rumors("BONEYARD_HOOK") + T.rumors("BONEYARD_DONE"), 0)
        T.eq("inactive: drones back as they were, no battle group left", census(), census0)
    end,
})
