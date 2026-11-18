-- Escort jobs: a convoy and two fighters wait at the origin for orders; two interceptor waves at
-- a third and two thirds of the way; payment at the destination once the convoy has docked.
-- Also the convoy lost. One ship. The convoy is teleported along its route and its dock forced
-- (the real trip takes many minutes at impulse); it is made indestructible for the test.

T.suite("jobs")

local HOME = "Port Vesper"
local m, c0, rep0
-- Farewell hails from the escort fighters: recorded instead of read off a comms screen.
local farewells = {}
local _hail, _jlog = JOBS.hail, JOBS.log
JOBS.hail = function(job, from, text)
    local ok = _hail(job, from, text)
    if ok and job == m then farewells[#farewells + 1] = {from = from, text = text} end
    return ok
end
JOBS.log = function(job, text, color)
    if job == m and text:find('^%[.-%] "') then farewells[#farewells + 1] = {text = text:gsub("^%[.-%] ", "")} end
    return _jlog(job, text, color)
end
local function convoy() return m.convoy end
local function along(frac) return m.ox + (m.dx - m.ox) * frac, m.oy + (m.dy - m.oy) * frac end

T.step("post an escort job", function()
    local mod = JOBS._registry.escort
    mod.FAREWELL_DELAY, mod.FAREWELL_GAP = 0.5, 1   -- farewells come quickly in the test
    mod.CONVOY_DESPAWN, mod.FIGHTER_DESPAWN = 4, 4   -- and departed ships are removed quickly
    m = T.postJob(T.makeJob("escort", HOME))
    -- The pay is the formula reward plus a flat allowance for the missiles the waves will cost.
    local mod = JOBS._registry.escort
    T.eq("pay: the munitions allowance is 90 cr", mod.MUNITIONS_ALLOWANCE, 90)
    local base = JOBS.calcReward(JOBS.ECONOMY.base_reward[m.tier], JOBS.ECONOMY.type_mult.escort,
        m.distance_u, nil, nil, nil)
    T.check("pay: at least the formula's base plus 90", m.reward >= base + 90, m.reward .. " vs " .. base)
    T.check("pay: the brief says so", m.brief:find("90 cr for the missiles", 1, true) ~= nil)
end)
T.takeJob(function() return m end)
T.step("the convoy waits for orders", function()
    T.check("escort: convoy spawned at the origin", ARC.near(convoy(), m.ox, m.oy, 2000))
    T.eq("escort: two fighters", #m.fighter_cs, 2)
    T.check("escort: fighters spawned", RT.valid(m.fighters[1]) and RT.valid(m.fighters[2]))
    T.check("escort: waiting", m._convoy_waiting)
    convoy():setCanBeDestroyed(false)
end)
T.talk(convoy, {"Proceed to"}, {name = "the convoy"})
T.step("under way", function()
    T.check("escort: released by the order", not m._convoy_waiting)
    T.check("escort: no ambush at the dock", not m._ambush1)
    convoy():setPosition(along(0.4))
end)
T.waitFor("escort: first intercept a third of the way", function() return m._ambush1 end, 3)
T.step("first wave", function()
    T.eq("escort: three interceptors", #m._interceptors, 3)
    T.check("escort: not the second wave yet", not m._ambush2)
    convoy():setPosition(along(0.7))
end)
T.waitFor("escort: second intercept two thirds of the way", function() return m._ambush2 end, 3)
T.step("second wave; bring her in", function()
    T.eq("escort: six interceptors", #m._interceptors, 6)
    local x, y = along(1)
    convoy():setPosition(x + 3000, y)
end)
T.waitFor("escort: the convoy asks to dock inside 5U", function() return m._convoy_docking end, 3)
T.dock(function() return T.find(m.dest) end)
T.talk(function() return T.find(m.dest) end, {})
T.step("no payment before she docks", function()
    T.check("escort: nothing to collect yet", not T.hasReply("Collect escort payment"))
    local dp = convoy().components.docking_port
    dp.target = T.find(m.dest); dp.state = "docked"
end)
T.waitFor("escort: a docked convoy completes the run", function() return m._convoy_arrived end, 3)
T.waitFor("farewell: both fighters say goodbye", function() return #farewells >= 2 end, 5)
T.step("farewells", function()
    local known = {}
    for _, l in ipairs(JOBS._registry.escort.FAREWELLS) do known['"' .. l .. '"'] = true end
    T.check("farewell: lines from the list", known[farewells[1].text] and known[farewells[2].text],
        tostring(farewells[1].text) .. " / " .. tostring(farewells[2].text))
    T.check("farewell: two different lines", farewells[1].text ~= farewells[2].text)
    T.check("farewell: from two different fighters",
        farewells[1].from == nil or farewells[2].from == nil or farewells[1].from ~= farewells[2].from)
end)
T.step("note credits", function() c0 = T.credits() end)
T.talk(function() return T.find(m.dest) end, {"Collect escort payment"})
local done_convoy, done_fighters
T.step("paid", function()
    T.eq("escort: paid the reward", T.credits() - c0, m.reward)
    T.check("escort: done", T.activeEntry(m) == nil)
    done_convoy, done_fighters = convoy(), {m.fighters[1], m.fighters[2]}
    T.check("leaving: the convoy is sent off", m._convoy_departed)
end)
T.closeComms()
T.waitFor("leaving: the convoy undocks", function()
    return RT.valid(done_convoy) and not done_convoy:getDockedWith()
end, 3)
T.waitFor("leaving: the convoy is removed once out of sight", function() return not RT.valid(done_convoy) end, 6)
T.waitFor("leaving: so are the fighters", function()
    return not RT.valid(done_fighters[1]) and not RT.valid(done_fighters[2])
end, 6)

local first = {}
T.step("a second job; the convoy is lost", function()
    first = {m.convoy, m.fighters[1], m.fighters[2]}   -- the first job's ships themselves
    m = T.postJob(T.makeJob("escort", HOME))
end)
T.takeJob(function() return m end)
-- Hold the fighter ships themselves: names come from a small pool, and the first job's dismissed
-- fighters can still be flying off under the same name.
local f1, f2
T.step("destroy the convoy", function()
    rep0 = T.rep(m.origin_faction)
    f1, f2 = m.fighters[1], m.fighters[2]
    T.check("lost: this job's fighters are out", RT.valid(f1) and RT.valid(f2))
    local clash = false
    for _, old in ipairs(first) do          -- a first-job ship still flying under a name now reused
        if RT.valid(old) then
            for _, new in ipairs({m.convoy_cs, m.fighter_cs[1], m.fighter_cs[2]}) do
                if old:getCallSign() == new then clash = true end
            end
        end
    end
    T.check("names: a new job never reuses the name of a ship still flying", not clash)
    convoy():destroy()
end)
T.waitFor("lost: no convoy, no contract", function() return T.activeEntry(m) == nil end, 4)
T.step("lost", function()
    T.eq("lost: standing -2x reward", T.rep(m.origin_faction) - rep0, -2 * m.reward)
    T.check("lost: fighters removed", not RT.valid(f1) and not RT.valid(f2))
end)
T.closeComms()
