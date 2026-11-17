-- Station defenders: one fighter per Concord / Independent station, respawned after a death,
-- answering hails and (when the arc flag allows it) taking orders from the ship that asks.
--
-- Not covered: the defenders' flying and fighting.

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

-- ── Off and on ───────────────────────────────────────────────────────────────
local before = {}
T.step("plugin off", function()
    for cs, s in pairs(slots()) do before[cs] = s.ship end
    WORLD.disable("defenders")
    local left = 0
    for _, e in pairs(before) do if RT.valid(e) then left = left + 1 end end
    T.eq("off: every defender is removed", left, 0)
    WORLD.enable("defenders")
end)
T.waitFor("on: defenders are posted again", function()
    st = T.world("defenders")
    return st.slots ~= nil and st.slots["Port Vesper"] ~= nil and RT.valid(st.slots["Port Vesper"].ship)
end, 3)
