-- RACE (ee/ragtag/race.lua), The Short Haul's competition: the board stays shut until the clock
-- starts; score = credits + upgrade list price; a live leaderboard on the combined consoles
-- (clock, top 5, your own place); at zero the final standings pop up on every console, the lines
-- go away and the board stays open.
--
-- Not covered: the scenario file itself (scenario_81_shorthaul.lua: settings, ship list,
-- starting credits), which the smoke test does not load.

T.suite("core")
require("ragtag/race.lua")

local A, B

-- The text of every custom line/pop-up of a kind on a ship, by key prefix.
local function customs(p, prefix, kind)
    local out = {}
    pcall(function()
        local f = p.components.custom_ship_functions
        for i = 1, #f do
            local name = tostring(f[i].name)
            if name:sub(1, #prefix) == prefix and (kind == nil or tostring(f[i].type) == kind) then
                out[#out + 1] = tostring(f[i].caption)
            end
        end
    end)
    return out
end
local function has(list, text)
    for _, l in ipairs(list) do if l:find(text, 1, true) then return true end end
    return false
end

T.step("set up: shut until the start", function()
    A = T.P()
    B = T.secondShip()
    T.eq("fmt: 1234567", RACE.fmt(1234567), "1,234,567")
    T.eq("fmt: 999", RACE.fmt(999), "999")
    T.eq("fmt: 1000", RACE.fmt(1000), "1,000")
    RACE.setup({minutes = 0.05})   -- 3 seconds
    T.check("setup: the job boards are shut", JOBS.config.jobboard_locked)
    RT.setCredits(500, A)
    RT.setCredits(400, B)
    RT.grantUpgrade("hull_plating", "test", B)   -- 200 cr list price
    T.eq("score: credits only", RACE.score(A), 500)
    T.eq("score: credits + upgrades at list price", RACE.score(B), 400 + RT.upgradeById("hull_plating").cost)
    RACE.draw(T.now())
    T.check("before: the clock waits", has(customs(A, "race_relay_"), "waiting for the start"), table.concat(customs(A, "race_relay_"), " | "))
end)
T.step("start", function()
    T.check("start: starts once", RACE.start(T.now()))
    T.check("start: not twice", not RACE.start(T.now()))
    T.check("start: the boards open", not JOBS.config.jobboard_locked)
    local st = RACE.standings()
    T.eq("standings: the upgraded ship leads", st[1].name, B:getCallSign())
    local mine = customs(A, "race_relay_")
    T.check("lines: the clock runs", has(mine, "left"), table.concat(mine, " | "))
    T.check("lines: the leader", has(mine, "1. " .. B:getCallSign() .. "  600"), table.concat(mine, " | "))
    T.check("lines: you", has(mine, "2. " .. A:getCallSign() .. "  500  (you)"), table.concat(mine, " | "))
    for _, pos in ipairs({"operations", "tactical", "engineering+", "singlepilot"}) do
        T.check("lines: on " .. pos, #customs(A, "race_" .. pos .. "_") > 0)
    end
    T.check("lines: not on Helms", #customs(A, "race_helms_") == 0)
end)
T.waitFor("the clock runs out", function() RACE.tick(T.now()); return RACE.state.over end, 8)
T.step("the result", function()
    T.eq("over: no leaderboard lines left", #customs(A, "race_relay_"), 0)
    local res = customs(A, "race_result_")
    T.check("over: the final standings pop up on every console", #res >= 8, #res)
    T.check("over: the result names the winner first", has(res, "1. " .. B:getCallSign() .. "  600"), table.concat(res, " | "))
    T.check("over: the board stays open", not JOBS.config.jobboard_locked)
    T.check("over: finishing twice does nothing", RACE.finish() == nil)
    for _, p in ipairs({A, B}) do
        for _, pos in ipairs(RACE.ALL_POSITIONS) do p:removeCustom("race_result_" .. pos) end
    end
    RT.revokeUpgrade("hull_plating", B)
end)
