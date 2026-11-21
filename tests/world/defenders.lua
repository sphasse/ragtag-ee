-- Station defenders: one fighter per Concord / Independent station, respawned after a death,
-- answering hails and (when the arc flag allows it) taking orders from the ship that asks.
-- Lane pickets: the Concord pickets out on the lanes are named and described as pickets, and
-- walk a slow beat round their post (fly to a corner, hold it, move on), the escort in formation.
--
-- Not covered: the defenders' and pickets' flying and fighting (orders and positions only).

T.suite("world")

local A, B, st
local slot, defender

local function slots() return st.slots end
local function count(pred)
    local n = 0
    for cs, s in pairs(slots()) do if pred(cs, s) then n = n + 1 end end
    return n
end
local function orders(ship)
    local ok, target = pcall(function() return ship:getOrderTarget() end)
    return ok and target or nil
end

T.step("setup", function()
    A = T.P()
    st = T.world("defenders")
    T.check("setup: the plugin is running", WORLD.isEnabled("defenders") and st and st._initialized)
end)

-- ── One per friendly station ─────────────────────────────────────────────────
T.step("every Concord and Independent station has one", function()
    local want = 0
    for _, d in ipairs(VERSE.STATIONS) do
        if d.fac == "Concord" or d.fac == "Independent" then
            want = want + 1
            local s = slots()[d.cs]
            T.check("posted: " .. d.cs, s ~= nil and RT.valid(s.ship), s and tostring(s.ship_name))
            if s and RT.valid(s.ship) then
                T.eq("posted: " .. d.cs .. " defender's faction", s.ship:getFaction(), d.fac)
            end
        else
            T.check("posted: none at " .. d.cs .. " (" .. d.fac .. ")", slots()[d.cs] == nil)
        end
    end
    T.eq("posted: one slot per friendly station", count(function() return true end), want)
    local seen, dup = {}, nil
    for _, s in pairs(slots()) do
        if seen[s.ship_name] then dup = s.ship_name end
        seen[s.ship_name] = true
    end
    T.check("posted: every defender has its own name", dup == nil, dup)
    slot = slots()["Port Vesper"]
    defender = slot.ship
    local sx, sy = T.find("Port Vesper"):getPosition()
    local dx, dy = defender:getPosition()
    T.check("posted: near its station", math.sqrt((sx - dx) ^ 2 + (sy - dy) ^ 2) < 12000)
    T.check("posted: the slot holds the ship itself, not a name", type(slot.ship) ~= "string")
end)

-- ── Hails ────────────────────────────────────────────────────────────────────
T.talk(function() return defender end, {}, {name = "the defender"})
T.step("an Independent defender answers", function()
    T.check("hail: names its post", T.msg():find("on post at Port Vesper", 1, true) ~= nil, T.msg())
    T.check("hail: small talk", T.hasReply("Just checking in."))
    T.check("hail: takes no orders by default", not T.hasReply("Defend our ship."), table.concat(T.replies(), " | "))
end)
T.talk(function() return slots()["Concord Station Arbiter"].ship end, {}, {name = "a Concord defender"})
T.step("a Concord defender answers", function()
    T.check("hail: Concord logs you", T.msg():find("You are being logged", 1, true) ~= nil, T.msg())
    T.check("hail: Concord small talk", T.hasReply("Just passing through."))
end)

-- ── Orders, once an arc has earned them ──────────────────────────────────────
T.step("the crew earns command of Independent defenders; a second ship joins", function()
    RT.flag("defender_cmds_independent", true)
    B = T.secondShip()
end)
T.actAs(function() return B end)
T.talk(function() return defender end, {"Defend our ship."}, {name = "the defender"})
T.step("it defends the ship that asked", function()
    T.check("orders: acknowledged", T.msg():find("On your wing", 1, true) ~= nil, T.msg())
    T.check("orders: escorting the second ship, which asked", orders(defender) == B, tostring(orders(defender)))
end)
T.actAs(nil)
T.talk(function() return defender end, {"Return to your station."}, {name = "the defender"})
T.step("sent home", function()
    T.check("orders: returning", T.msg():find("Returning to post", 1, true) ~= nil, T.msg())
    T.check("orders: defending its station again", orders(defender) == T.find("Port Vesper"), tostring(orders(defender)))
end)
T.talk(function() return slots()["Concord Station Arbiter"].ship end, {}, {name = "a Concord defender"})
T.step("Concord defenders are a separate permission", function()
    T.check("orders: Concord still takes none", not T.hasReply("Defend our ship."), table.concat(T.replies(), " | "))
    RT.clearFlag("defender_cmds_independent")
end)
T.closeComms()

-- ── Death and respawn ────────────────────────────────────────────────────────
local old_name
T.step("another defender takes the same callsign; then ours dies", function()
    old_name = slot.ship_name
    -- A slot must notice its own ship's death even when another ship carries the name.
    slots()["Dustmote Salvage"].ship:setCallSign(old_name)
    defender:destroy()
end)
T.waitFor("respawn: the slot notices its defender is gone", function() return slot.ship == nil end, 3)
T.step("cooling down", function()
    T.check("respawn: not at once", slot.respawn_at and slot.respawn_at > T.now() + 60, tostring(slot.respawn_at))
    T.check("respawn: the namesake is untouched", RT.valid(slots()["Dustmote Salvage"].ship))
    slot.respawn_at = T.now()
end)
T.waitFor("respawn: a new defender is posted", function() return RT.valid(slot.ship) end, 3)
T.step("a new ship", function()
    T.check("respawn: it is a different ship", slot.ship ~= defender)
    T.eq("respawn: same faction", slot.ship:getFaction(), "Independent")
    T.eq("respawn: still one per slot", count(function(_, s) return RT.valid(s.ship) end), count(function() return true end))
end)

-- ── Lane pickets ─────────────────────────────────────────────────────────────
local law   -- the CNS Lawgiver group
local function dist(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end
T.step("the lane pickets", function()
    T.eq("pickets: three groups with a beat", #st.pickets, 3)
    for _, p in ipairs(st.pickets) do
        if p.ships[1]:getCallSign() == "CNS Lawgiver" then law = p end
    end
    T.check("pickets: CNS Lawgiver found", law ~= nil)
    T.eq("pickets: its escort has a name", law.ships[2]:getCallSign(), "CPV Forbearance")
    T.eq("pickets: described as a lane picket", law.ships[1]:getDescription("simplescan"),
        "Concord lane picket. Holds this stretch of the lanes.")
    T.check("pickets: not a base posting", not law.ships[1]:getDescription("fullscan"):find("defense posting", 1, true))
    T.eq("pickets: a 4U beat", law.r, 4000)
    -- On its beat: the lead flies to a corner 4U from the post, the escort keeps formation.
    T.eq("beat: the lead flies", law.ships[1]:getOrder(), "Fly towards")
    local tx, ty = law.ships[1]:getOrderTargetLocation()
    T.check("beat: to a corner 4U from its post", math.abs(dist(tx, ty, law.x, law.y) - 4000) < 50, string.format("%.0f", dist(tx, ty, law.x, law.y)))
    T.eq("beat: the escort flies in formation", law.ships[2]:getOrder(), "Fly in formation")
    T.eq("beat: on the lead", law.ships[2]:getOrderTarget(), law.ships[1])
    law.ships[1]:setPosition(tx, ty)   -- arrive
end)
local corner1
T.waitFor("beat: at the corner it holds a while", function() return law.holding_until ~= nil end, 3)
T.step("holding", function()
    T.eq("hold: defends the corner", law.ships[1]:getOrder(), "Defend Location")
    corner1 = law.k
    law.holding_until = T.now()   -- the wait is over
end)
T.waitFor("beat: then on to the next corner", function() return law.k ~= corner1 and law.holding_until == nil end, 3)
T.step("next corner", function()
    T.eq("next: flying again", law.ships[1]:getOrder(), "Fly towards")
    local tx, ty = law.ships[1]:getOrderTargetLocation()
    T.check("next: a different corner of the same beat", math.abs(dist(tx, ty, law.x, law.y) - 4000) < 50)
end)

-- ── Off and on ───────────────────────────────────────────────────────────────
local before = {}
T.step("plugin off", function()
    for cs, s in pairs(slots()) do before[cs] = s.ship end
    WORLD.disable("defenders")
    local left = 0
    for _, e in pairs(before) do if RT.valid(e) then left = left + 1 end end
    T.eq("off: every defender is removed", left, 0)
    T.eq("off: the pickets stay", RT.valid(law.ships[1]), true)
    T.eq("off: and hold their post", law.ships[1]:getOrder(), "Defend Location")
    WORLD.enable("defenders")
end)
T.waitFor("on: defenders are posted again", function()
    st = T.world("defenders")
    return st.slots ~= nil and st.slots["Port Vesper"] ~= nil and RT.valid(st.slots["Port Vesper"].ship)
end, 3)

-- The universe's Corsair garrisons (the Gauntlet packs, Blackwater's port defenders) have Corsair
-- names, not EmptyEpsilon's automatic ones ("CV12"). Playtest 2026-11-21.
T.step("Corsair garrisons have names", function()
    local named, auto, seen = 0, {}, {}
    for _, g in ipairs(VERSE.GARRISONS) do
        if g.fac == "Corsairs" then
            for _, o in ipairs(getObjectsInRadius(g.x * 1000, g.y * 1000, 2500)) do
                if isObjectType(o, "CpuShip") and not seen[o] then
                    seen[o] = true
                    local cs = o:getCallSign()
                    if cs:match("^%u%u%d+$") then auto[#auto + 1] = cs else named = named + 1 end
                end
            end
        end
    end
    T.eq("garrisons: no automatic Corsair callsigns near the posts", table.concat(auto, ", "), "")
    -- Every name in the data is a ship in the game (they may have wandered off their post).
    local missing, n = {}, 0
    for _, g in ipairs(VERSE.GARRISONS) do
        if g.fac == "Corsairs" then
            T.eq("garrisons: a name for every ship at (" .. g.x .. ", " .. g.y .. ")", #(g.callsigns or {}), #g.ships)
            for _, cs in ipairs(g.callsigns or {}) do
                n = n + 1
                if T.find(cs) == nil then missing[#missing + 1] = cs end
            end
        end
    end
    T.eq("garrisons: thirteen named Corsair ships", n, 13)
    T.eq("garrisons: every named ship is in the game", table.concat(missing, ", "), "")
end)
