-- The sandbox's "Create player ship" list (its getSpawnablePlayerShips): one "Light Freighter:
-- <name>" entry per named ship, the campaign ship first, then the other (stock) ships; the
-- generic auto-named Light Freighter is not listed. An entry makes a Light Freighter under that
-- name, which brings the record saved under it (credits, standing, upgrades), and its description
-- says what that record holds. A ship already flying is not made twice, and a lost campaign ship
-- is rebuilt by picking its entry. A = the primary ship, W = Wren, N = the rebuilt primary.
--
-- Not covered: the screen itself (the test calls the entries' create functions, which is what
-- the screen's Create button does).

T.suite("core")

local A, W, N
local NAME

local function entry(name)
    for _, e in ipairs(getSpawnablePlayerShips()) do
        if e[2] == "Light Freighter: " .. name then return e end
    end
    return nil
end

T.step("the list", function()
    A = T.P()
    NAME = RT.campaign.ship_name
    local list = getSpawnablePlayerShips()
    T.eq("list: the campaign ship first", list[1] and list[1][2], "Light Freighter: " .. NAME)
    local birds, generic, other = 0, false, false
    for _, e in ipairs(list) do
        if e[2]:find("Light Freighter: ", 1, true) == 1 then birds = birds + 1 end
        if e[2] == "Light Freighter" then generic = true end
        if e[2] == "Concord Enforcer" then other = true end
    end
    T.eq("list: ten named freighters", birds, 10)
    T.check("list: no generic auto-named freighter", not generic)
    T.check("list: the other player ships are still listed", other)
    T.check("list: the campaign ship is described as such", list[1][3]:find("the campaign ship", 1, true) ~= nil, list[1][3])
    T.check("list: and as flying now", list[1][3]:find("Flying now", 1, true) ~= nil, list[1][3])
end)

T.step("descriptions show the saved records", function()
    RT.campaign.extra_ships = RT.campaign.extra_ships or {}
    table.insert(RT.campaign.extra_ships, {name = "Wren", credits = 345, reputation = {}, upgrades = {"hull_plating"}})
    local e = entry("Wren")
    T.check("record: Wren is listed", e ~= nil)
    T.check("record: its credits", e[3]:find("345 credits", 1, true) ~= nil, e[3])
    local u = RT.upgradeById("hull_plating")
    T.check("record: its upgrades", e[3]:find(u.gm_name or u.name, 1, true) ~= nil, e[3])
    T.check("record: a ship never flown has none", entry("Osprey")[3]:find("No saved record", 1, true) ~= nil)
end)

T.step("pick Wren", function() W = entry("Wren")[1]() end)
T.wait(1)
T.step("Wren joins with its record", function()
    T.check("pick: a ship was made", RT.valid(W))
    T.eq("pick: under the picked name", W:getCallSign(), "Wren")
    T.eq("pick: the Light Freighter type", W:getTypeName(), "Light Freighter")
    T.check("pick: registered", RT.playerShip(W) == W)
    T.check("pick: not the primary", RT.players[1] == A)
    T.eq("pick: its saved credits", T.credits(W), 345)
    T.check("pick: its saved upgrade", RT.hasUpgrade("hull_plating", W))
    T.check("pick: listed as flying now", entry("Wren")[3]:find("Flying now", 1, true) ~= nil)
    -- Provisioned like the campaign ship (RT.provision), not as the template comes: no nuke, no
    -- mines, 2 homing, 2 repair crew (playtest: list ships had a nuke and a full crew).
    T.eq("loadout: no nuke rack", W:getWeaponStorageMax("Nuke"), 0)
    T.eq("loadout: no mine rack", W:getWeaponStorageMax("Mine"), 0)
    T.eq("loadout: 2 homing", W:getWeaponStorage("Homing"), 2)
    T.eq("loadout: 2 repair crew", W:getRepairCrewCount(), 2)
    T.eq("loadout: same nuke rack as the primary", W:getWeaponStorageMax("Nuke"), A:getWeaponStorageMax("Nuke"))
end)
T.wait(2.5)   -- the location line is refreshed every 2 s
-- Side-panel lines fit about 20 characters (RT.SIDE_LINE_MAX, playtest).
local function captions(p, prefix)
    local out = {}
    local f = p.components.custom_ship_functions
    for i = 1, #f do
        if tostring(f[i].name):sub(1, #prefix) == prefix then out[#out + 1] = tostring(f[i].caption) end
    end
    return out
end
T.step("every ship shows where it is, in 20 characters", function()
    local loc = captions(W, "rt_region_r")
    T.eq("location: Wren's Relay shows its location", #loc, 1)
    T.check("location: region and grid, no 'Location:'", loc[1] and not loc[1]:find("Location", 1, true), tostring(loc[1]))
    T.check("location: fits 20", loc[1] and #loc[1] <= RT.SIDE_LINE_MAX, tostring(loc[1]))
end)
T.step("one objective, one line, within 20", function()
    RT.setObjective("Deal with the audit", true, "test_obj")
    local shown = captions(W, "rt_objective_test_obj")
    T.eq("objective: one line", #shown, 1)
    T.eq("objective: the text as written, no prefix", shown[1], "Deal with the audit")
    RT.setObjective("Deal with the audit, deliver the AI to Rezkov", true, "test_obj")
    shown = captions(W, "rt_objective_test_obj")
    T.eq("objective: a too-long one is still one line", #shown, 1)
    T.check("objective: cut to 20 on the panel", #shown[1] <= RT.SIDE_LINE_MAX, shown[1])
    T.eq("objective: the full text is kept", RT.objectives.test_obj, "Deal with the audit, deliver the AI to Rezkov")
    RT.clearObjective("test_obj")
    T.eq("objective: cleared", #captions(W, "rt_objective_test_obj"), 0)
end)

T.step("a ship already flying is not made twice", function()
    local n = #RT.players
    T.check("twice: nothing made for Wren", entry("Wren")[1]() == nil)
    T.check("twice: nothing made for the campaign ship", entry(NAME)[1]() == nil)
    T.eq("twice: no new ship", #RT.players, n)
end)

T.step("the campaign ship is lost", function() A:destroy() end)
T.wait(1)
T.step("rebuild it from the list", function() N = entry(NAME)[1]() end)
T.wait(1)
T.step("it is the primary ship again", function()
    T.check("rebuilt: a ship was made", RT.valid(N))
    T.eq("rebuilt: the campaign's name", N:getCallSign(), NAME)
    T.check("rebuilt: first in the list", RT.players[1] == N)
    T.check("rebuilt: the arcs have their ship", ARC.player() == N)
    T.check("rebuilt: its record is the campaign", RT.shipRecord(N) == RT.campaign)
    T.eq("rebuilt: Wren keeps its own credits", T.credits(W), 345)
end)
