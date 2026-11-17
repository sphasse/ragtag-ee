-- Destroy jobs: a target that turns hostile when the ship closes to 8U; destroying it earns the
-- certificate; payment back at the origin. Also expiry cleaning up the target. One ship. The
-- kill is scripted (no Weapons station headless).

T.suite("jobs")

local HOME = "Port Vesper"
local m, c0, corsairs0
local function target() return m.target end

T.step("post a destroy job", function() m = T.postJob(T.makeJob("destroy", HOME, 2)) end)
T.takeJob(function() return m end)
T.undock()
T.step("the target", function()
    local t = target()
    T.check("destroy: target spawned", RT.valid(t))
    T.eq("destroy: job renamed after the target", m.short, "Destroy " .. m.target_cs)
    T.eq("destroy: target starts unidentified", t:getFaction(), "Unknown")
    T.check("destroy: not hostile at a distance", not m._attacking)
    T.moveNear(t, 6000)
end)
T.waitFor("destroy: closing to 8U provokes it", function() return m._attacking end, 3)
T.step("kill it", function()
    T.eq("destroy: target turns Corsair", target():getFaction(), "Corsairs")
    corsairs0 = T.rep("Corsairs")
    target():destroy()
end)
T.waitFor("destroy: the kill is noticed", function() return m._destroyed end, 3)
T.step("killed", function() T.eq("destroy: Corsairs -200", T.rep("Corsairs") - corsairs0, -200) end)
T.dock(HOME)
T.step("note credits", function() c0 = T.credits() end)
T.talk(HOME, {function() return "Submit " .. m.cargo end})
T.step("paid", function()
    T.eq("destroy: paid the reward", T.credits() - c0, m.reward)
    T.check("destroy: done", T.activeEntry(m) == nil)
end)
T.closeComms()

local old
T.step("a second job runs out of time", function() m = T.postJob(T.makeJob("destroy", HOME, 2)) end)
T.takeJob(function() return m end)
T.step("expire it", function() old = target(); m._expires_at = T.now() - 1 end)
T.waitFor("expiry: dropped", function() return T.activeEntry(m) == nil end, 3)
T.step("expired", function() T.check("expiry: the target is removed", not RT.valid(old)) end)
T.closeComms()
