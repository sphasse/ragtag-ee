-- Boarding jobs: a target that turns hostile at 8U, surrenders when crippled, and is boarded by
-- docking; payment back at the origin. Also the target destroyed before boarding. One ship.
-- Damage and docking are forced.

T.suite("jobs")

local HOME = "Port Vesper"
local m, c0, rep0, corsairs0
local function target() return m.target end

T.step("post a boarding job", function() m = T.postJob(T.makeJob("boarding", HOME, 2)) end)
T.takeJob(function() return m end)
T.undock()
T.step("the target", function()
    T.check("boarding: target spawned", RT.valid(target()))
    T.eq("boarding: job renamed after the target", m.short, "Disable " .. m.target_cs)
    T.moveNear(target(), 6000)
end)
T.waitFor("boarding: closing to 8U provokes it", function() return m._attacking end, 3)
T.step("cripple it", function()
    T.eq("boarding: target turns Corsair", target():getFaction(), "Corsairs")
    corsairs0 = T.rep("Corsairs")
    target():setHull(target():getHullMax() * 0.2)
end)
T.waitFor("boarding: a crippled target surrenders", function() return m._disabled end, 3)
T.step("surrendered", function()
    T.eq("boarding: Corsairs -100", T.rep("Corsairs") - corsairs0, -100)
    T.eq("boarding: no longer hostile, so it can be docked with", target():getFaction(), "Independent")
    T.check("boarding: not boarded until docked", not m._boarded)
end)
T.dock(target)
T.waitFor("boarding: docking boards it", function() return m._boarded end, 3)
T.dock(HOME)
T.step("note credits", function() c0 = T.credits() end)
T.talk(HOME, {function() return "Deliver " .. m.cargo end})
T.step("paid", function()
    T.eq("boarding: paid the reward", T.credits() - c0, m.reward)
    T.check("boarding: done", T.activeEntry(m) == nil)
    T.check("boarding: target removed", T.find(m.target_cs) == nil)
end)
T.closeComms()

T.step("a second job; the target is destroyed", function() m = T.postJob(T.makeJob("boarding", HOME, 2)) end)
T.takeJob(function() return m end)
T.step("destroy it", function()
    rep0 = T.rep(m.origin_faction)
    target():destroy()
end)
T.waitFor("lost: nothing to board", function() return T.activeEntry(m) == nil end, 3)
T.step("lost", function() T.eq("lost: standing -reward", T.rep(m.origin_faction) - rep0, -m.reward) end)
T.closeComms()
