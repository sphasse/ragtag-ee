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

-- ── New delivery: the GM writes a job and posts it, or hands it to a ship ───────────────────
-- getGMSelection is stubbed the same way: the test says what the GM has selected on the map.
local HOME, DEST = "Port Vesper", nil
local gm_m, sug_pay, sug_secs, b_c1
local _sel = getGMSelection
local function gmJobs()
    local out = {}
    for _, e in ipairs(JOBS._injected) do if e.category == "GM_JOBS" then out[#out + 1] = e end end
    return out
end
local function onBoard(cs, ship, m)
    for _, o in ipairs(JOBS.board(cs, ship).offers) do if o == m then return true end end
    return false
end
T.step("new delivery: draft", function()
    for _, s in ipairs(VERSE.STATIONS) do
        if not DEST and s.cs ~= HOME and s.fac == "Independent" and RT.valid(RT.find(s.cs)) then DEST = s.cs end
    end
    main()
    press("Jobs...")
    press("New delivery...")
    T.check("draft: starts empty", has("From: (pick)") and has("To: (pick)") and has("Cargo: Random"), labels())
    press("From:")
    getGMSelection = function() return {} end
    press("Use map selection")
    T.check("draft: nothing selected says so", messages[#messages]:find("Select one port", 1, true) ~= nil, messages[#messages])
    getGMSelection = function() return {RT.find(HOME)} end
    press("Use map selection")
    getGMSelection = _sel
    T.check("draft: the selected port is the start", has("From: " .. HOME), labels())
    press("To:")
    if not has(DEST) then press("Next ▶") end
    press(DEST)
    T.check("draft: the picked port is the end", has("To: " .. DEST), labels())
    press("Cargo:")
    press("medical supplies")
    T.check("draft: picked cargo, urgent with it", has("Cargo: medical supplies") and has("Urgent: yes"), labels())
    T.check("draft: time and pay suggested", has("(suggested)...") and has("Pay: ") , labels())
    local del = JOBS._registry["delivery"]
    sug_pay, sug_secs = del.suggest{origin = HOME, dest = DEST, urgent = true, arch = del.archetypes()[1]}
    T.check("draft: the suggestion is board pay", sug_pay and sug_pay > 0 and sug_pay % 5 == 0, sug_pay)
    press("Pay:")
    press("+100cr")
    press("+25cr")
    press("← Done")
    T.check("draft: a changed pay shows the suggestion beside it", has("(sugg. " .. sug_pay .. "cr)"), labels())
    press("Time:")
    press("+5 min")
    press("← Done")
    press("For: ")
    T.check("draft: For cycles to the second ship", has("For: " .. B:getCallSign()), labels())
    press("Post at")
    T.check("post: the GM sees it", messages[#messages]:find("Posted at " .. HOME, 1, true) ~= nil, messages[#messages])
    local list = gmJobs()
    T.eq("post: one GM job", #list, 1)
    gm_m = list[1] and list[1].record
    T.eq("post: pay as set", gm_m.reward, sug_pay + 125)
    T.eq("post: time as set", gm_m.time_limit, sug_secs + 300)
    T.check("post: [SPECIAL] by default", gm_m.special and gm_m.story, gm_m.short)
    T.check("post: on the start's board for B", onBoard(HOME, B, gm_m))
    T.check("post: not for A", not onBoard(HOME, A, gm_m))
    T.check("post: not at the end port", not onBoard(DEST, B, gm_m))
end)
T.actAs(function() return B end)
T.takeJob(function() return gm_m end)
T.step("taken by B", function()
    T.check("taken: B owns it", gm_m.ship == B)
    T.eq("taken: B's time limit is the GM's", gm_m._time_limit, sug_secs + 300)
    main(); press("Jobs..."); press("Posted GM jobs (1)")
    T.check("taken: listed as taken", has("Taken (" .. B:getCallSign() .. ")"), labels())
end)
T.dock(function() return T.find(DEST) end)
T.wait(1.5)
T.step("note B's credits", function() b_c1 = T.credits(B) end)
T.talk(function() return T.find(DEST) end, {"Hand off"})
T.step("delivered", function()
    T.eq("delivered: B paid the GM's pay", T.credits(B) - b_c1, sug_pay + 125)
    T.eq("delivered: off the GM list", #gmJobs(), 0)
end)
T.closeComms()
T.actAs(nil)
T.step("normal work for any ship, withdrawn", function()
    main(); press("Jobs..."); press("New delivery...")
    T.check("again: the draft is kept", has("From: " .. HOME), labels())
    press("Kind:")
    press("For: ")
    T.check("again: normal work for any ship", has("Kind: normal work") and has("For: any ship"), labels())
    T.check("again: no assign for any ship", not has("Assign now"), labels())
    press("Post at")
    local m2 = gmJobs()[1].record
    T.check("again: not [SPECIAL]", not m2.special and not m2.story, m2.short)
    T.check("again: on the board for A and B", onBoard(HOME, A, m2) and onBoard(HOME, B, m2))
    press("← Back to Jobs")
    press("Posted GM jobs (1)")
    press("Withdraw:")
    T.eq("withdrawn: gone from the list", #gmJobs(), 0)
    T.check("withdrawn: gone from the board", not onBoard(HOME, A, m2))
end)
T.step("assign now", function()
    main(); press("Jobs..."); press("New delivery...")
    press("For: ")
    T.check("assign: For back to A", has("For: " .. A:getCallSign()), labels())
    local before = #JOBS.activeFor(A)
    press("Assign now to " .. A:getCallSign())
    T.check("assign: the GM sees it", messages[#messages]:find("Given to " .. A:getCallSign(), 1, true) ~= nil, messages[#messages])
    local act = JOBS.activeFor(A)
    T.eq("assign: A has it", #act, before + 1)
    T.eq("assign: nothing posted", #gmJobs(), 0)
    press("Clear draft")
    T.check("clear: empty again", has("From: (pick)"), labels())
end)

T.step("restore the GM functions", function()
    getGMSelection = _sel
    addGMFunction, clearGMFunctions, addGMMessage = _add, _clear, _msg
    main()
end)
