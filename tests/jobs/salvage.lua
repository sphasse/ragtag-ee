-- Salvage jobs: a cluster of unidentified pods; scanning one turns it into a container; flying
-- into the target container collects the cargo; payment back at the origin. Also a decoy
-- pickup, cargo destroyed, and expiry. One ship. Scans are forced (no Science station headless).

T.suite("jobs")

local HOME = "Port Vesper"
local m, c0, rep0
local function target() for _, ce in ipairs(m._cluster) do if ce.is_target then return ce end end end
local function decoy()  for _, ce in ipairs(m._cluster) do if not ce.is_target then return ce end end end
-- One Science scan: the "simple" state (a second scan would make it "full"); that is enough.
local function scan(ce) ce.marker:setScanStateByFaction("Independent", "simple") end
local function markersLeft()
    local n = 0
    for _, ce in ipairs(m._cluster or {}) do if not ce._materialized and RT.valid(ce.marker) then n = n + 1 end end
    return n
end

T.step("post a salvage job", function() m = T.postJob(T.makeJob("salvage", HOME)) end)
T.takeJob(function() return m end)
T.undock()
T.step("the cluster", function()
    local n, targets = #m._cluster, 0
    for _, ce in ipairs(m._cluster) do if ce.is_target then targets = targets + 1 end end
    T.check("salvage: three to five pods", n >= 3 and n <= 5, n)
    T.eq("salvage: exactly one holds the cargo", targets, 1)
    T.eq("salvage: pods are unidentified", target().marker:getCallSign(), "Unknown Salvage")
    T.check("salvage: nothing to collect before a scan", m.cargo_obj == nil)
    scan(decoy())
end)

-- A decoy: scanning identifies it, picking it up pays a little.
local d
T.waitFor("salvage: a scanned decoy becomes a container", function() d = decoy(); return d._materialized end, 3)
T.step("fly into the decoy", function()
    local drop = T.find(d.cargo)
    T.check("salvage: decoy container is on the map", drop ~= nil, d.cargo)
    c0 = T.credits()
    T.moveTo(drop:getPosition())
end)
T.waitFor("salvage: a decoy is worth a few credits", function() return T.credits() > c0 end, 8)
T.step("decoy value", function()
    local got = T.credits() - c0
    T.check("salvage: decoy pays 25 to 50", got >= 25 and got <= 50, got)
    T.check("salvage: a decoy is not the cargo", not m._found)
    scan(target())
end)

-- The cargo.
T.waitFor("salvage: the scanned target becomes the cargo container", function() return RT.valid(m.cargo_obj) end, 3)
T.dock(HOME)
T.talk(HOME, {})
T.step("not before pickup", function()
    T.check("salvage: no payment before the cargo is aboard", not T.hasReply("Deliver " .. m.cargo))
end)
T.undock()
T.step("fly into the cargo", function() T.moveTo(m.cargo_obj:getPosition()) end)
T.waitFor("salvage: flying into the container collects the cargo", function() return m._found end, 8)
T.dock(HOME)
T.step("note credits", function() c0 = T.credits() end)
T.talk(HOME, {function() return "Deliver " .. m.cargo end})
T.step("paid", function()
    T.eq("salvage: paid the reward", T.credits() - c0, m.reward)
    T.check("salvage: done", T.activeEntry(m) == nil)
    T.eq("salvage: unscanned pods cleaned up", markersLeft(), 0)
end)
T.closeComms()

-- Cargo destroyed before pickup.
T.step("a second job; its cargo is destroyed", function()
    m = T.postJob(T.makeJob("salvage", HOME))
end)
T.takeJob(function() return m end)
T.step("identify the cargo", function() scan(target()) end)
T.waitFor("lost: cargo container out", function() return RT.valid(m.cargo_obj) end, 3)
T.step("destroy it", function()
    rep0 = T.rep(m.origin_faction)
    m.cargo_obj:destroy()
end)
T.waitFor("lost: a destroyed cargo ends the contract", function() return T.activeEntry(m) == nil end, 3)
T.step("lost", function()
    T.eq("lost: standing -reward", T.rep(m.origin_faction) - rep0, -m.reward)
    T.eq("lost: pods cleaned up", markersLeft(), 0)
end)

-- Expiry costs double.
T.step("a third job runs out of time", function() m = T.postJob(T.makeJob("salvage", HOME)) end)
T.takeJob(function() return m end)
T.step("expire it", function()
    rep0 = T.rep(m.origin_faction)
    m._expires_at = T.now() - 1
end)
T.waitFor("expiry: dropped", function() return T.activeEntry(m) == nil end, 3)
T.step("expired", function()
    T.eq("expiry: standing -2x reward", T.rep(m.origin_faction) - rep0, -2 * m.reward)
    T.eq("expiry: pods cleaned up", markersLeft(), 0)
end)
T.closeComms()
