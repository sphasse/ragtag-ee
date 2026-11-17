-- Hacking jobs: an armed relay; any system hacked to 75% extracts the data; payment back at the
-- origin. Also the relay destroyed before extraction. One ship. The hack level is set directly
-- (no Relay station headless) and the ship stays out of the relay's beam range.

T.suite("jobs")

local HOME = "Port Vesper"
local m, c0, rep0
local function relay() return m.target end

T.step("post a hacking job", function() m = T.postJob(T.makeJob("hacking", HOME, 1)) end)
T.takeJob(function() return m end)
T.step("the relay", function()
    local r = relay()
    T.check("hack: relay spawned", RT.valid(r))
    T.check("hack: job renamed after its beacon", m.short == "Hack " .. m.target_cs and m.target_cs:find("^Beacon ") ~= nil, m.short)
    T.eq("hack: relay is hostile (Relic)", r:getFaction(), "Relic")
    T.check("hack: relay is about where the job said", ARC.near(r, m.wx, m.wy, 100))
    r:setSystemHackedLevel("reactor", 0.5)
end)
T.wait(1)
T.step("half is not enough", function()
    T.check("hack: 50% does not breach", not m._hacked)
    relay():setSystemHackedLevel("maneuver", 0.8)
end)
T.waitFor("hack: any system at 75% breaches the datastore", function() return m._hacked end, 3)
T.step("note credits", function()
    T.check("hack: the relay can be destroyed once breached", RT.valid(relay()))
    c0 = T.credits()
end)
T.talk(HOME, {function() return "Deliver " .. m.cargo end})
T.step("paid", function()
    T.eq("hack: paid the reward", T.credits() - c0, m.reward)
    T.check("hack: done", T.activeEntry(m) == nil)
    T.check("hack: relay removed", T.find(m.target_cs) == nil)
end)
T.closeComms()

T.step("a second job; the relay is destroyed first", function() m = T.postJob(T.makeJob("hacking", HOME, 1)) end)
T.takeJob(function() return m end)
T.step("destroy the relay", function()
    rep0 = T.rep(m.origin_faction)
    relay():setCanBeDestroyed(true)
    relay():destroy()
end)
T.waitFor("lost: no relay, no contract", function() return T.activeEntry(m) == nil end, 3)
T.step("lost", function() T.eq("lost: standing -reward", T.rep(m.origin_faction) - rep0, -m.reward) end)
T.closeComms()
