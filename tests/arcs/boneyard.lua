-- Boneyard arc: hook -> annex_hack -> annex_control (download, drone IFF flip) -> extract -> done
-- (full), then the GM states and "-> Inactive". Not covered: the lifeboat rescue job (the other
-- way to reveal the Annex), a real Relay hack (the GM helper sets the level), the fight itself.
-- The 60 s download and 30 s reprogram timers are shortened by moving their start times back.

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
T.step("battle group inbound", function()
    T.eq("annex_control: six Concord ships", T.alive(T.st().concord_group), 6)
    T.eq("annex_control: battle group is hostile", T.st().concord_group[1]:getFaction(), "Concord Hostile")
    T.check("annex_control: Boneyard patrols suspended", PROX._suspended_zones["the Boneyard"])
    T.eq("annex_control: objective", RT.objectives.boneyard, "Defend the Annex")
    local relic = 0
    for _, o in ipairs(getObjectsInRadius(36000, -96000, 32000)) do
        if isObjectType(o, "CpuShip") and o:getFaction() == "Relic" then relic = relic + 1 end
    end
    T.eq("annex_control: no active Relic drones left in the Boneyard", relic, 0)
end)

-- ── Control: one operation at a time ─────────────────────────────────────────
T.talk(annex, {"1) Download research archive"})
T.step("download running", function() T.check("control: downloading", T.st().downloading) end)
T.talk(annex, {})
T.step("reprogram is locked meanwhile", function()
    T.check("control: download shown in progress", T.hasReply("[IN PROGRESS] Downloading archive"), table.concat(T.replies(), " | "))
    T.check("control: reprogram locked during download", T.hasReply("[LOCKED] Reprogram drone IFF"), table.concat(T.replies(), " | "))
    T.check("control: not done early", not T.flag("boneyard_hack_done"))
    T.st().download_start = T.st().download_start - 58
end)
T.waitFor("control: download completes", function() return T.flag("boneyard_hack_done") end, 5)
T.step("research indexed", function()
    T.check("control: Ashgrave research readable", SCIDB._locked.ashgrave_research and SCIDB._locked.ashgrave_research.unlocked)
end)
T.talk(annex, {"2) Reprogram drone IFF targets"})
T.step("reprogram running", function()
    T.check("control: reprogramming", T.st().reprogramming)
    T.st().reprogram_start = T.st().reprogram_start - 28
end)
T.waitFor("control: IFF override completes", function() return T.flag("boneyard_drone_flip") end, 5)
T.step("drones on our side", function()
    T.eq("control: eight reinforcement drones", T.alive(T.st().rein_drones), 8)
    T.eq("control: reinforcements are Relic Active", T.st().rein_drones[1]:getFaction(), "Relic Active")
    T.eq("control: still at the Annex", T.phase(), "annex_control")
end)
T.closeComms()

-- ── Extract and resolve ──────────────────────────────────────────────────────
T.step("pull back 11U (still inside the Boneyard)", function() T.moveTo(ANNEX_X, ANNEX_Y - 11000) end)
T.waitFor("extract: leaving the Annex starts the run out", function() return T.phase() == "extract" end, 3)
T.step("note credits and standing, then leave the Boneyard", function()
    T.eq("extract: objective cleared", RT.objectives.boneyard, nil)
    c0, concord0, corsairs0 = T.credits(), T.rep("Concord"), T.rep("Corsairs")
    T.moveTo(36000, -96000 + 31000)
end)
T.waitFor("done: clearing the Boneyard resolves the arc", function() return T.status() == "done" end, 3)
T.step("resolved", function()
    T.eq("done: boneyard_arc_done", T.flag("boneyard_arc_done"), true)
    T.eq("done: 800 cr (data 600 + drones 200)", T.credits() - c0, 800)
    T.eq("done: Concord -500", T.rep("Concord") - concord0, -500)
    T.eq("done: Corsairs +150", T.rep("Corsairs") - corsairs0, 150)
    T.check("done: Boneyard patrols resumed", not PROX._suspended_zones["the Boneyard"])
    T.eq("done: two aftermath rumors", T.rumors("BONEYARD_DONE"), 2)
end)

-- ── GM states ────────────────────────────────────────────────────────────────
local paid
-- Parked 7.6U from the Annex: inside the Boneyard and within 10U of the Annex (so annex_control
-- and extract do not move on by themselves), but over 8U from Ashgrave (so the hook stays put).
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
        T.eq("GM control: six Concord ships", T.alive(T.st().concord_group), 6)
        T.check("GM control: zone suspended", PROX._suspended_zones["the Boneyard"])
    end},
    {key = "extract", phase = "extract", check = function()
        T.check("GM extract: Annex out", RT.valid(annex()))
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
