-- Station traffic: freighters on their routes. How many, where they go, what they say when
-- hailed, what they sell (to the ship that pays), replacement of lost ships (never next to any
-- player ship), the density setting.
--
-- Not covered: the freighters' flying, docking and the stall watchdog (minutes of real travel).

T.suite("world")

local A, B, st
local rec

local function transports() return VERSE.transports end
local function want(density)
    local mult = ({0.5, 1.0, 2.0})[density]
    local n = 0
    for _, route in ipairs(VERSE.ROUTES) do n = n + math.max(1, math.floor(route.count * mult + 0.5)) end
    return n
end
local function living()
    local n = 0
    for _, r in ipairs(transports()) do if RT.valid(r.ship) then n = n + 1 end end
    return n
end
local function pick(pred)
    for _, r in ipairs(transports()) do if RT.valid(r.ship) and pred(r) then return r end end
end

T.step("setup", function()
    A = T.P()
    st = T.world("traffic")
    T.check("setup: the plugin is running", WORLD.isEnabled("traffic") and st and st._initialized)
    T.eq("setup: Medium density", TRAFF.getDensity(), 2)
end)

-- ── The fleet ────────────────────────────────────────────────────────────────
T.step("every route is flown", function()
    T.eq("fleet: ships per the routes", #transports(), want(2))
    T.eq("fleet: all alive", living(), want(2))
    local by_route = {}
    for _, r in ipairs(transports()) do
        by_route[r.route.id] = (by_route[r.route.id] or 0) + 1
        if r.ship:getFaction() ~= r.route.fac then
            T.check("fleet: " .. r.name .. " flies its route's colours", false, r.ship:getFaction())
        end
        local on_route = false
        for _, cs in ipairs(r.route.stations) do
            if RT.valid(r.dest) and r.dest:getCallSign() == cs then on_route = true end
        end
        if not on_route then T.check("fleet: " .. r.name .. " is bound for a station on its route", false) end
    end
    for _, route in ipairs(VERSE.ROUTES) do
        T.eq("fleet: route " .. route.id, by_route[route.id], route.count)
    end
    T.check("fleet: freighters have a warp drive", pick(function() return true end).ship:hasWarpDrive())
end)

-- ── Hails ────────────────────────────────────────────────────────────────────
T.step("pick an Independent freighter", function()
    rec = pick(function(r) return r.route.fac == "Independent" end)
    rec.kind = "Goods"
    rec.ship:orderIdle()            -- hold still: a freighter under warp is out of range in a second
    T.moveNear(rec.ship, 3000)
end)
T.talk(function() return rec.ship end, {"Where are you headed?"}, {name = "a freighter"})
T.step("it says where it is going", function()
    T.check("hail: destination and cargo", T.msg():find("Bound for", 1, true) ~= nil and T.msg():find("trade goods", 1, true) ~= nil, T.msg())
end)
T.talk(function() return rec.ship end, {"Heard any news?"}, {name = "a freighter"})
T.step("it passes on a rumor", function()
    T.check("hail: news", #T.msg() > 10 and T.msg():find("Go ahead, neighbour", 1, true) == nil, T.msg())
    T.check("hail: nothing for sale from a goods hauler", not T.hasReply("Sell us some fuel"))
end)
T.talk(function() return pick(function(r) return r.route.fac == "Concord" end).ship end, {}, {name = "a Concord transport"})
T.step("Concord transports keep their distance", function()
    T.check("hail: Concord greeting", T.msg():find("scheduled run", 1, true) ~= nil, T.msg())
end)

-- ── Trade: the ship that asks is the ship that pays ──────────────────────────
local a0, b0
T.step("a fuel hauler; a second ship with no money", function()
    rec.kind = "Fuel"
    B = T.secondShip()
    RT.setCredits(200, A)
    RT.setCredits(10, B)
    A:setEnergy(100)
    T.moveNear(rec.ship, 3000)
    local ax, ay = A:getPosition()
    B:setPosition(ax, ay + 800)
    a0, b0 = T.credits(A), T.credits(B)
end)
T.actAs(function() return B end)
T.talk(function() return rec.ship end, {"Sell us some fuel"}, {name = "the fuel hauler"})
T.step("B cannot pay", function()
    T.check("fuel: cash first", T.msg():find("Cash first", 1, true) ~= nil, T.msg())
    T.eq("fuel: B's credits untouched", T.credits(B), b0)
    T.eq("fuel: A's credits untouched", T.credits(A), a0)
end)
T.actAs(nil)
T.talk(function() return rec.ship end, {"Sell us some fuel"}, {name = "the fuel hauler"})
T.step("A buys", function()
    T.eq("fuel: 30 credits from A", a0 - T.credits(A), 30)
    T.eq("fuel: none from B", T.credits(B), b0)
    T.eq("fuel: A's energy topped up", A:getEnergy(), A:getMaxEnergy())
end)
T.step("too far away", function()
    local x, y = rec.ship:getPosition()
    T.moveTo(x + 9000, y)
    a0 = T.credits(A)
end)
T.talk(function() return rec.ship end, {"Sell us some fuel"}, {name = "the fuel hauler"})
T.step("no sale at a distance", function()
    T.check("fuel: come alongside", T.msg():find("Come alongside", 1, true) ~= nil, T.msg())
    T.eq("fuel: no charge", T.credits(A), a0)
end)
T.closeComms()

-- ── A lost freighter is replaced ─────────────────────────────────────────────
local n0
T.step("a freighter is lost", function()
    T.moveTo(VERSE.at("Lastchance Outpost", 30, 30))    -- far from every route station
    B:setPosition(VERSE.at("Lastchance Outpost", 34, 30))  -- the second ship too: no ship may watch a respawn
    n0 = #transports()
    rec.ship:destroy()
end)
T.waitFor("lost: off the list", function() return #transports() == n0 - 1 end, 4)
T.step("queued", function()
    T.eq("lost: one replacement queued", #VERSE.respawn_queue, 1)
    T.check("lost: not at once", VERSE.respawn_queue[1].at > T.now() + 100)
    T.eq("lost: for the same route", VERSE.respawn_queue[1].route.id, rec.route.id)
    VERSE.respawn_queue[1].at = T.now()
end)
T.waitFor("lost: the replacement arrives", function() return #transports() == n0 and #VERSE.respawn_queue == 0 end, 4)

-- ── A replacement never appears next to a second ship ────────────────────────
-- The queued replacement is pinned to one station of its route; the second ship waits there.
local home_cs
T.step("another freighter is lost", function()
    rec = pick(function() return true end)
    rec.ship:destroy()
end)
T.waitFor("watched: queued", function() return #VERSE.respawn_queue == 1 end, 4)
T.step("the second ship waits at the station", function()
    local q = VERSE.respawn_queue[1]
    local only = {}
    for k, v in pairs(q.route) do only[k] = v end
    home_cs = q.route.stations[1]
    only.stations = {home_cs}
    q.route = only
    local stn = RT.stations[home_cs] and RT.stations[home_cs].entity or RT.find(home_cs)
    local x, y = stn:getPosition()
    B:setPosition(x + 5000, y)
    pcall(function() B:commandImpulse(0) end)
    T.check("watched: the primary ship is far from it", RT.dist(A, stn) > 10000)
    q.at = T.now()
end)
T.wait(3)
T.step("held back", function()
    T.eq("watched: still queued while the second ship is there", #VERSE.respawn_queue, 1)
    T.check("watched: tried again later", #VERSE.respawn_queue == 1 and VERSE.respawn_queue[1].at > T.now() + 20)
    B:setPosition(VERSE.at("Lastchance Outpost", 34, 30))
    VERSE.respawn_queue[1].at = T.now()
end)
T.waitFor("watched: the replacement arrives once the second ship leaves", function() return #VERSE.respawn_queue == 0 end, 4)

-- ── Density ──────────────────────────────────────────────────────────────────
local old = {}
T.step("density Low", function()
    for _, r in ipairs(transports()) do old[#old + 1] = r.ship end
    TRAFF.setDensity(1)
end)
T.waitFor("density: traffic is rebuilt at the lower count", function() return #transports() == want(1) end, 3)
T.step("the old fleet is gone", function()
    local left = 0
    for _, e in ipairs(old) do if RT.valid(e) then left = left + 1 end end
    T.eq("density: old freighters removed", left, 0)
    T.eq("density: new ones alive", living(), want(1))
    TRAFF.setDensity(3)
end)
T.waitFor("density: High doubles it", function() return #transports() == want(3) end, 3)
T.step("clamped", function()
    TRAFF.setDensity(9)
    T.eq("density: never above High", TRAFF.getDensity(), 3)
    TRAFF.setDensity(0)
    T.eq("density: never below Low", TRAFF.getDensity(), 1)
end)

-- ── Off ──────────────────────────────────────────────────────────────────────
T.wait(1)
T.step("plugin off", function()
    local ships = {}
    for _, r in ipairs(transports()) do ships[#ships + 1] = r.ship end
    WORLD.disable("traffic")
    local left = 0
    for _, e in ipairs(ships) do if RT.valid(e) then left = left + 1 end end
    T.eq("off: every freighter is removed", left, 0)
    T.eq("off: the list is empty", #transports(), 0)
end)
