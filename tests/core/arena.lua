-- ARENA (ee/ragtag/arena.lua), the Combat Arena's rules: the ship types on offer, the roster, the spawn
-- distance and faction, enemies spawned frozen in front of the crews, START / freeze / clear, the end of a
-- fight and its report, restoring a ship, and the shared Ship Upgrades... menu with the arena's own Back.
--
-- Not covered: the scenario file itself (scenario_65_arena.lua: init and the "Create player ship" list; it
-- was loaded headless by hand), and a real fight to the end (the enemies are removed by script).

T.suite("core")
require("ragtag/ships_used.lua")
require("ragtag/bout.lua")
require("ragtag/match.lua")
require("ragtag/arena.lua")
BOUT.LOG_KEY = "ragtag.fightlog.test"   -- never the real log
BOUT._log = nil

local A
local OPEN_X, OPEN_Y = 200000, 200000   -- open space, away from the Drift's ports and patrols
local home = {}
local pos0 = {}

local function enemies() return ARENA.state.enemies end
local function order(s) local ok, o = pcall(function() return s:getOrder() end); return ok and tostring(o) or "?" end

T.step("the arena, in open space", function()
    A = T.P()
    home.x, home.y = A:getPosition()
    A:setPosition(OPEN_X, OPEN_Y)
    A:setHeading(0)
    ARENA.reset()
end)

T.step("the ship types on offer", function()
    local list = ARENA.templates()
    local has = {}
    for _, n in ipairs(list) do has[n] = true end
    T.check("types: some", #list >= 5, #list)
    T.check("types: the Drift's warships (Adder MK5, Phobos T3, Atlantis X23)",
        has["Adder MK5"] and has["Phobos T3"] and has["Atlantis X23"], table.concat(list, ", "))
    T.check("types: no player ships", not has["Flavia P.Falcon"] and not has["Light Freighter"])
    T.check("types: no unarmed ships (tugs, freighters)", not has["Tug"] and not has["Goods Freighter 3"])
    local sorted = true
    for i = 2, #list do if list[i - 1] > list[i] then sorted = false end end
    T.check("types: in name order", sorted)
    T.check("types: info reads a type", ARENA.templateInfo("Adder MK5"):find("Hull", 1, true) ~= nil, ARENA.templateInfo("Adder MK5"))
end)

T.step("the roster, the distance and the faction", function()
    T.eq("roster: starts empty", ARENA.rosterSize(), 0)
    T.eq("roster: +2 Adder", ARENA.add("Adder MK5", 2), 2)
    T.eq("roster: +1 Phobos", ARENA.add("Phobos T3", 1), 1)
    T.eq("roster: three", ARENA.rosterSize(), 3)
    T.eq("roster: text", ARENA.rosterText(), "2 x Adder MK5, 1 x Phobos T3")
    T.eq("roster: never below none", ARENA.add("Phobos T3", -5), 0)
    T.eq("roster: never above the cap", ARENA.add("Phobos T3", 99), ARENA.MAX_PER_TYPE)
    ARENA.add("Phobos T3", -ARENA.MAX_PER_TYPE); ARENA.add("Phobos T3", 1)
    T.eq("distance: default", ARENA.state.dist_u, ARENA.DIST_DEFAULT)
    T.eq("distance: no nearer than 2U", ARENA.setDistance(1), 2)
    T.eq("distance: no further than 10U", ARENA.setDistance(15), 10)
    T.eq("distance: a step in", ARENA.nudgeDistance(-1), 9)
    local first, seen = ARENA.state.faction, {}
    for _ = 1, #ARENA.FACTIONS do seen[ARENA.cycleFaction()] = true end
    T.eq("faction: round the list and back", ARENA.state.faction, first)
    for _, f in ipairs(ARENA.FACTIONS) do
        T.check("faction: " .. f .. " is hostile to the crews", VERSE.HOSTILE_FACTIONS[f] == true)
    end
end)

T.step("spawned frozen, ahead of the crews", function()
    ARENA.setDistance(4)
    local n = ARENA.spawn()
    T.eq("spawn: three", n, 3)
    T.eq("spawn: frozen", ARENA.state.phase, "frozen")
    local cx, cy = ARENA.centre()
    for i, e in ipairs(enemies()) do
        local s = e.ship
        local x, y = s:getPosition()
        local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / 1000
        T.check("spawn: " .. e.template .. " about 4U out", d > 3.8 and d < 4.5, string.format("%.2fU", d))
        T.check("spawn: " .. e.template .. " ahead (north)", y < cy - 3500, y - cy)
        T.eq("spawn: " .. e.template .. " flies for the Corsairs", s:getFaction(), "Corsairs")
        T.eq("spawn: " .. e.template .. " is idle", order(s), "Idle")
        T.check("spawn: " .. e.template .. " strength noted", (e.strength or 0) > 0)
        pos0[i] = {x, y}
    end
    pos0.hull = A:getHull()
    local r = ARENA.report()
    T.check("report: both sides' strength", r:find("Strength: enemies", 1, true) ~= nil, r)
    T.check("report: not started", r:find("frozen, not started", 1, true) ~= nil, r)
end)
T.wait(3)
T.step("frozen means frozen", function()
    for i, e in ipairs(enemies()) do
        local x, y = e.ship:getPosition()
        T.check("frozen: " .. e.template .. " has not moved", math.abs(x - pos0[i][1]) < 50 and math.abs(y - pos0[i][2]) < 50)
    end
    T.eq("frozen: nobody fired at the crew", A:getHull(), pos0.hull)
end)

T.step("START, freeze, START again", function()
    T.check("start: released", ARENA.start())
    T.eq("start: fighting", ARENA.state.phase, "fighting")
    for _, e in ipairs(enemies()) do T.eq("start: " .. e.template .. " hunts", order(e.ship), "Roaming") end
    T.check("start: not twice", not ARENA.start())
    T.check("freeze: paused", ARENA.freeze())
    for _, e in ipairs(enemies()) do T.eq("freeze: " .. e.template .. " idle again", order(e.ship), "Idle") end
    T.check("start: again after a freeze", ARENA.start())
    T.check("start: the crew's hull at the start is noted", ARENA.state.crews and ARENA.state.crews[1] and ARENA.state.crews[1].ship == A)
end)

T.step("every enemy gone: the crews won", function()
    for _, e in ipairs(enemies()) do e.ship:destroy() end
    ARENA.tick(T.now())
    T.eq("end: over", ARENA.state.phase, "over")
    T.eq("end: won", ARENA.state.result, "won")
    local r = ARENA.report()
    T.check("end: the report says so", r:find("OVER in", 1, true) ~= nil and r:find("won", 1, true) ~= nil, r)
    T.check("end: and lists the crew", r:find(A:getCallSign(), 1, true) ~= nil, r)
    local rows = BOUT.rows()
    local last = rows[#rows]
    T.check("fight log: a row for the crew", last and last.source == "arena" and last.ship == A:getCallSign()
        and last.outcome == "won", last and BOUT.rowText(last) or "none")
    T.check("fight log: the enemies and the predicted R", last and last.enemies == 3 and last.predicted_r and last.predicted_r > 0
        and last.slot == "custom", last and tostring(last.predicted_r) or "none")
    T.check("fight log: the crews are asked", #(function()
        local out, f = {}, A.components.custom_ship_functions
        for i = 1, #f do if tostring(f[i].name):find("^bout_rate_relay_") then out[#out + 1] = 1 end end
        return out end)() == #BOUT.RATINGS)
    BOUT.clearRating(A)
    T.check("end: with its shields", r:find(string.format("shields %d/%d", math.floor(A:getShieldLevel(0)),
        math.floor(A:getShieldLevel(1))), 1, true) ~= nil, r)
end)

T.step("clear, and an empty roster", function()
    T.check("respawn", ARENA.spawn() == 3)
    local first = enemies()[1].ship
    ARENA.clear()
    T.eq("clear: none left", #enemies(), 0)
    T.check("clear: removed from the game", not RT.valid(first))
    T.eq("clear: empty", ARENA.state.phase, "empty")
    ARENA.clearRoster()
    local n, why = ARENA.spawn()
    T.check("empty roster: nothing spawned, and why", n == nil and why and why:find("empty", 1, true) ~= nil, tostring(why))
end)

T.step("restore a battered ship", function()
    A:setHull(10)
    A:setShields(0, 0)
    A:setEnergy(5)
    A:setSystemHealth("impulse", 0.1)
    A:setSystemHeat("beamweapons", 0.9)
    A:setSystemPower("impulse", 0.3)
    A:setWeaponStorage("Homing", 0)
    A:setScanProbeCount(0)
    T.check("restore: done", ARENA.restore(A))
    T.eq("restore: hull", A:getHull(), A:getHullMax())
    T.eq("restore: front shield", A:getShieldLevel(0), A:getShieldMax(0))
    T.eq("restore: energy", A:getEnergy(), A:getMaxEnergy())
    T.eq("restore: impulse repaired", A:getSystemHealth("impulse"), 1)
    T.eq("restore: beams cool", A:getSystemHeat("beamweapons"), 0)
    T.eq("restore: impulse power 100%", A:getSystemPower("impulse"), 1)
    T.eq("restore: homing racks full", A:getWeaponStorage("Homing"), A:getWeaponStorageMax("Homing"))
    T.eq("restore: probes", A:getScanProbeCount(), A:getMaxScanProbeCount())
    T.check("restore: every ship", ARENA.restoreAll() >= 1)
end)

-- The campaign's Ship Upgrades... menu, shared: its Back goes where the arena says.
T.step("Ship Upgrades... with the arena's Back", function()
    local buttons, back_pressed = {}, false
    local add, clear, msg = addGMFunction, clearGMFunctions, addGMMessage
    addGMFunction = function(label, fn) buttons[#buttons + 1] = {label = label, fn = fn} end
    clearGMFunctions = function() buttons = {} end
    addGMMessage = function() end
    local ok, err = pcall(function()
        local function press(label)
            for _, b in ipairs(buttons) do if b.label == label then b.fn(); return true end end
            return false
        end
        GMCONSOLE.addUpgradesButton(function() back_pressed = true end)
        T.check("upgrades: the button", press("Ship Upgrades..."))
        T.check("upgrades: the ship listed", press(A:getCallSign()))
        T.check("upgrades: its status sheet", press("Ship Status"))
        T.check("upgrades: back to the ships", press("← Ships"))
        T.check("upgrades: Back", press("← Back"))
        T.check("upgrades: Back went to the arena", back_pressed)
    end)
    addGMFunction, clearGMFunctions, addGMMessage = add, clear, msg
    T.check("upgrades: no error", ok, tostring(err))
end)

-- The arena's GM screen (ARENA.showGM, which scenario_65_arena.lua shows), pressed button by button.
T.step("the arena's GM screen", function()
    local arena_gm = ARENA.showGM
    ARENA.reset()
    local buttons, msgs = {}, {}
    local add, clear, msg = addGMFunction, clearGMFunctions, addGMMessage
    addGMFunction = function(label, fn) buttons[#buttons + 1] = {label = label, fn = fn} end
    clearGMFunctions = function() buttons = {} end
    addGMMessage = function(m) msgs[#msgs + 1] = tostring(m) end
    local function has(label) for _, b in ipairs(buttons) do if b.label == label then return true end end return false end
    local function press(label)
        for _, b in ipairs(buttons) do if b.label == label then b.fn(); return true end end
        T.check("gm: button '" .. label .. "'", false, "on screen: " .. (function()
            local l = {} for _, b in ipairs(buttons) do l[#l + 1] = b.label end return table.concat(l, " | ") end)())
        return false
    end
    local function lastMsg() return msgs[#msgs] or "" end
    local ok, err = pcall(function()
        arena_gm()
        T.check("gm: the arena screen", has("Enemies... (0)") and has("Distance - (6U)") and has("Faction: Corsairs")
            and has("Spawn enemies (frozen)") and has("START COMBAT") and has("Restore player ships") and has("Ship Upgrades..."))
        press("Spawn enemies (frozen)")
        T.check("gm: spawning nothing says why", lastMsg():find("empty", 1, true) ~= nil, lastMsg())
        press("Enemies... (0)")
        T.check("gm: the picker", has("← Arena") and has("Clear roster") and has("Adder MK5: 0"))
        press("Adder MK5: 0")
        press("+1"); press("+5"); press("-1")
        T.eq("gm: +1 +5 -1 is five", ARENA.count("Adder MK5"), 5)
        press("Adder MK5: 5 (info)")
        T.check("gm: the type's info", lastMsg():find("Hull", 1, true) ~= nil, lastMsg())
        press("← Enemies")
        T.check("gm: the count on the list", has("Adder MK5: 5"))
        local pages = #ARENA.templates() > 10
        if pages then
            T.check("gm: a second page", press("Next page > (1/2)") and has("< Previous page"))
            press("< Previous page")
        end
        press("← Arena")
        T.check("gm: the roster on the main screen", has("Enemies... (5)"))
        press("Distance - (6U)")
        T.check("gm: distance down a step", has("Distance - (5U)"))
        press("Faction: Corsairs")
        T.check("gm: next faction", has("Faction: " .. ARENA.FACTIONS[2]))
        ARENA.state.faction = "Corsairs"
        press("START COMBAT")
        T.check("gm: START before a spawn says why", lastMsg():find("Spawn enemies first", 1, true) ~= nil, lastMsg())
        press("Spawn enemies (frozen)")
        T.eq("gm: five spawned", #ARENA.state.enemies, 5)
        T.check("gm: the report pops up", lastMsg():find("COMBAT ARENA", 1, true) ~= nil, lastMsg())
        press("START COMBAT")
        T.eq("gm: fighting", ARENA.state.phase, "fighting")
        press("Freeze enemies")
        T.eq("gm: frozen again", ARENA.state.phase, "frozen")
        press("Report")
        T.check("gm: report", lastMsg():find("frozen at", 1, true) ~= nil, lastMsg())
        press("Restore player ships")
        T.check("gm: restored", lastMsg():find("Restored", 1, true) ~= nil, lastMsg())
        local n_rows = #BOUT.rows()
        press("Clear enemies")
        T.eq("gm: cleared", #ARENA.state.enemies, 0)
        T.eq("gm: a fight the GM ends is logged as stopped", BOUT.rows()[#BOUT.rows()].outcome, "stopped")
        T.eq("gm: one row for it", #BOUT.rows(), n_rows + 1)
        BOUT.clearRating(A)
        -- Three opponents, and taking one.
        press("Offer three opponents")
        T.check("gm: the offer is shown", lastMsg():find("Good match:", 1, true) ~= nil, lastMsg())
        local take
        for _, b in ipairs(buttons) do if b.label:find("^Take Good match") then take = b end end
        T.check("gm: a Take button for the good match", take ~= nil)
        if take then
            take.fn()
            T.eq("gm: the roster is the offer", ARENA.state.taken and ARENA.state.taken.slot, "match")
            T.check("gm: back on the arena screen", has("Spawn enemies (frozen)"))
            press("Spawn enemies (frozen)")
            T.eq("gm: spawned as the good match", ARENA.state.spawn_slot, "match")
            press("Clear enemies")
        end
        -- Crew numbers and the fight log.
        press("Crews... (1 unassigned)")
        press(A:getCallSign() .. ": crew -")
        T.eq("gm: crew set", BOUT.crewOf(A), 1)
        T.check("gm: shown", has(A:getCallSign() .. ": crew 1"))
        press("← Arena")
        T.check("gm: none unassigned", has("Crews..."))
        press("Fight log...")
        press(string.format("Show (%d rows)", #BOUT.rows()))
        T.check("gm: the log's summary", lastMsg():find("scriptstorage.json", 1, true) ~= nil, lastMsg())
        press("← Arena")
        press("Ship Upgrades...")
        press("← Back")
        T.check("gm: Ship Upgrades... comes back to the arena", has(string.format("Enemies... (%d)", ARENA.rosterSize())))
    end)
    addGMFunction, clearGMFunctions, addGMMessage = add, clear, msg
    T.check("gm: no error", ok, tostring(err))
    ARENA.clear()
    ARENA.reset()
end)

T.step("reset positions", function()
    local n = ARENA.resetPositions()
    local x, y = A:getPosition()
    T.check("reset: the ships counted", n >= 1)
    T.check("reset: back on the centre line", math.abs(y) < 1 and math.abs(x) <= 1500 * n, string.format("%.0f, %.0f", x, y))
    T.eq("reset: facing north", math.floor(A:getHeading() + 0.5) % 360, 0)
end)

T.step("tidy up", function()
    ARENA.clear()
    ARENA.reset()
    BOUT.clearRating(A)
    BOUT.clearLog()
    BOUT.log().crews = {}
    BOUT.save()
    A:setPosition(home.x, home.y)
end)
