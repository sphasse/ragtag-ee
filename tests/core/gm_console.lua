-- The campaign GM console (gm_console.lua) with several ships: Reputation... and the credit
-- buttons act on the ship the GM picks, never only the primary ship. With one ship in play the
-- menus look as they always did (no ship list, plain "Credits +50").
-- A = the primary ship, B = a second ship.
--
-- Not covered: the rest of the console (Campaign Status, Ship Upgrades: tests/core/records.lua
-- covers the upgrade calls it makes) and the GM screen itself: the test records the buttons the
-- console adds and presses them by calling their functions.

T.suite("core")

local A, B

-- Record the GM buttons and messages instead of reading them off a GM screen.
local buttons, messages = {}, {}
local _add, _clear, _msg = addGMFunction, clearGMFunctions, addGMMessage
addGMFunction = function(label, fn)
    buttons[#buttons + 1] = {label = label, fn = fn}
    return _add(label, fn)
end
clearGMFunctions = function()
    buttons = {}
    return _clear()
end
addGMMessage = function(text)
    messages[#messages + 1] = text
    return _msg(text)
end

local function labels()
    local out = {}
    for i, b in ipairs(buttons) do out[i] = b.label end
    return table.concat(out, " | ")
end
local function find(label)
    for _, b in ipairs(buttons) do
        if b.label:find(label, 1, true) then return b end
    end
end
local function has(label) return find(label) ~= nil end
local function press(label)
    local b = find(label)
    if not b then error("no GM button '" .. label .. "'; on screen: [" .. labels() .. "]") end
    b.fn()
end
local function main()
    clearGMFunctions()
    addSessionGMFunctions()
end

-- ── One ship: the menus as before ────────────────────────────────────────────
local a_rep0, a_c0
T.step("one ship: reputation", function()
    A = T.P()
    T.eq("setup: one ship in play", #RT.players, 1)
    main()
    press("Reputation...")
    T.check("one: straight to the factions, no ship list", has("Concord (") and has("← Back to Main"), labels())
    a_rep0 = T.rep("Concord", A)
    press("Concord (")
    press("↑  +50")
    T.eq("one: +50 on the only ship", T.rep("Concord", A) - a_rep0, 50)
    press("← Back to Factions")
    press("Rep Status")
    T.check("one: status names the ship", messages[#messages]:find(A:getCallSign(), 1, true) ~= nil, messages[#messages])
end)
T.step("one ship: credits", function()
    main()
    press("Jobs...")
    T.check("one: plain credit buttons", has("Credits +50") and not has(A:getCallSign() .. " Credits"), labels())
    a_c0 = T.credits(A)
    press("Credits +50")
    T.eq("one: +50 credits on the only ship", T.credits(A) - a_c0, 50)
end)

-- ── Two ships: the GM picks the ship ─────────────────────────────────────────
local b_rep0, b_c0
T.step("two ships: reputation", function()
    B = T.secondShip()
    main()
    press("Reputation...")
    T.check("two: a ship list", has(A:getCallSign() .. "...") and has(B:getCallSign() .. "..."), labels())
    press(B:getCallSign() .. "...")
    T.check("two: B's factions, back goes to the ship list", has("Concord (") and has("← Back to Ships"), labels())
    a_rep0, b_rep0 = T.rep("Concord", A), T.rep("Concord", B)
    press("Concord (")
    T.check("two: the detail names the ship", has(B:getCallSign() .. " Concord"), labels())
    press("↓  -50")
    T.eq("two: -50 on B", T.rep("Concord", B) - b_rep0, -50)
    T.eq("two: A untouched", T.rep("Concord", A), a_rep0)
    press("← Back to Factions")
    press("Rep Status")
    T.check("two: status is B's", messages[#messages]:find(B:getCallSign(), 1, true) ~= nil, messages[#messages])
    press("← Back to Ships")
    press(A:getCallSign() .. "...")
    press("Concord (")
    press("↑  +50")
    T.eq("two: +50 on A", T.rep("Concord", A) - a_rep0, 50)
    T.eq("two: B unchanged by A's button", T.rep("Concord", B) - b_rep0, -50)
end)
T.step("two ships: credits", function()
    main()
    press("Jobs...")
    T.check("two: credit buttons per ship", has(A:getCallSign() .. " Credits +50") and has(B:getCallSign() .. " Credits -50"), labels())
    a_c0, b_c0 = T.credits(A), T.credits(B)
    press(B:getCallSign() .. " Credits +50")
    T.eq("two: +50 credits on B", T.credits(B) - b_c0, 50)
    T.eq("two: A's credits untouched", T.credits(A), a_c0)
    press(A:getCallSign() .. " Credits -50")
    T.eq("two: -50 credits on A", T.credits(A) - a_c0, -50)
    T.eq("two: B's credits unchanged by A's button", T.credits(B) - b_c0, 50)
end)

T.step("restore the GM functions", function()
    addGMFunction, clearGMFunctions, addGMMessage = _add, _clear, _msg
    main()
end)
