-- The ship-creation list: the ten Magpie-class sister ships (ship_templates.lua) come first, in
-- roster order, and a ship made from one of them carries that name unless a live ship already
-- does (then the next free sister's name). The generic Light Freighter is still offered.
--
-- Not covered: the selection screen itself (the test reads the list the engine asks the script
-- for, getSpawnablePlayerShips, and makes ships from script, which fires the same callback).

T.suite("core")

local ROSTER = {"Magpie", "Raven", "Jackdaw", "Starling", "Wren", "Kestrel", "Harrier", "Merlin", "Osprey", "Swift"}

local function newShip(tmpl) return PlayerSpaceship():setTemplate(tmpl) end
local r1, r2, m2

T.step("the list", function()
    local list = getSpawnablePlayerShips()
    local first, labels = true, {}
    for i, entry in ipairs(list) do labels[i] = entry[2] end
    for i, name in ipairs(ROSTER) do
        if labels[i] ~= name then first = false end
    end
    T.check("list: the Magpie class first, in roster order", first, table.concat(labels, ", "):sub(1, 200))
    local generic = false
    for _, l in ipairs(labels) do if l == "Light Freighter" then generic = true end end
    T.check("list: the Light Freighter is still offered", generic)
    T.check("list: described as Magpie-class", (list[1][3] or ""):find("Magpie-class", 1, true) ~= nil, list[1][3])
    T.eq("list: the primary ship is the Magpie", T.P():getCallSign(), "Magpie")
    r1 = newShip("Raven")
end)
T.wait(1)
T.step("picked by name", function()
    T.eq("raven: named after its template", r1:getCallSign(), "Raven")
    T.check("raven: joined the crew", RT.playerShip(r1) ~= nil)
    T.eq("raven: independent colors", r1:getFaction(), "Independent")
    r2 = newShip("Raven")
    m2 = newShip("Magpie")
end)
T.wait(1)
T.step("names already flying", function()
    T.check("second raven: a different name", r2:getCallSign() ~= "Raven", r2:getCallSign())
    T.check("magpie while the Magpie flies: a different name", m2:getCallSign() ~= "Magpie", m2:getCallSign())
    T.check("all different", r2:getCallSign() ~= m2:getCallSign())
    local roster = {}
    for _, n in ipairs(ROSTER) do roster[n] = true end
    T.check("both still sister-ship names", roster[r2:getCallSign()] and roster[m2:getCallSign()])
    T.check("the primary is unchanged", RT.players[1] == T.P() and T.P():getCallSign() == "Magpie")
end)
