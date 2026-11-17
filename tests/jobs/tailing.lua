-- Tailing jobs: two ships fly to a rendezvous; both must be scanned during the meeting without
-- the ship coming within 10U; payment back at the origin. Also the target spooked. One ship. The
-- two ships are teleported to the meeting point and the scans are forced.

T.suite("jobs")

local HOME = "Port Vesper"
local m, c0, rep0
local function tgt() return m.target end
local function rdv() return m.rendezvous end

T.step("post a tailing job", function() m = T.postJob(T.makeJob("tailing", HOME, 1)) end)
T.takeJob(function() return m end)
T.step("two ships on their way", function()
    T.check("tailing: target and contact spawned", RT.valid(tgt()) and RT.valid(rdv()))
    T.eq("tailing: job renamed after the target", m.short, "Surveil " .. m.target_cs)
    T.check("tailing: the target starts well clear of the ship", RT.dist(T.P(), tgt()) > 10000, RT.dist(T.P(), tgt()))
    T.check("tailing: not meeting yet", not m._meeting)
    tgt():setPosition(m.mx, m.my)
    rdv():setPosition(m.mx + 800, m.my)
end)
T.waitFor("tailing: the meeting starts when they are 1.5U apart", function() return m._meeting end, 3)
T.step("scan one", function()
    T.check("tailing: still active during the meeting", T.activeEntry(m) ~= nil)
    tgt():setScannedByFaction("Independent", true)
end)
T.wait(1)
T.step("one is not enough", function()
    T.check("tailing: target identified", m._tgt_scanned)
    T.check("tailing: not complete with one scan", not m._scanned)
    rdv():setScannedByFaction("Independent", true)
end)
T.waitFor("tailing: both scanned completes the surveillance", function() return m._scanned end, 3)
T.step("note credits", function() c0 = T.credits() end)
T.talk(HOME, {function() return "Deliver " .. m.cargo end})
T.step("paid", function()
    T.eq("tailing: paid the reward", T.credits() - c0, m.reward)
    T.check("tailing: done", T.activeEntry(m) == nil)
end)
T.closeComms()

T.step("a second job; the ship gets too close", function() m = T.postJob(T.makeJob("tailing", HOME, 1)) end)
T.takeJob(function() return m end)
T.undock()
T.step("blunder in", function()
    rep0 = T.rep(m.origin_faction)
    T.moveNear(tgt(), 8000)
end)
T.waitFor("spooked: inside 10U the contract is lost", function() return T.activeEntry(m) == nil end, 3)
T.step("spooked", function() T.eq("spooked: standing -reward", T.rep(m.origin_faction) - rep0, -m.reward) end)
T.closeComms()
