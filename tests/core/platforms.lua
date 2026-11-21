-- PLATFORMS (ee/ragtag/platforms.lua, contributed by Kuri148, PR #1): stationary gun platforms.
-- The universe places three Relic ones in the Boneyard, away from the Ashgrave Annex; a platform
-- turns to a hostile player ship, fires once it is pointed at it and the ship is in range, its
-- shells damage the ship, it holds fire out of range, and a destroyed one drops off the list.
-- VERSE.update (run by the sandbox every frame) drives PLATFORMS.update.
--
-- Not covered: the strafe sweep's exact angles, the barrage fan, hitting a moving ship.

T.suite("core")

local ANNEX_X, ANNEX_Y = 43000, -104000
local plat, h0, s0

local function dist(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end

T.step("the universe's Boneyard platforms", function()
    local relic = {}
    for _, t in ipairs(PLATFORMS.list) do
        if RT.valid(t.obj) and t.obj:getFaction() == "Relic" then relic[#relic + 1] = t.obj end
    end
    T.eq("universe: three Relic platforms", #relic, 3)
    for _, s in ipairs(relic) do
        local x, y = s:getPosition()
        local r = VERSE.regionAt(x, y)
        T.eq("universe: " .. s:getCallSign() .. " is in the Boneyard", r and r.name, "the Boneyard")
        T.check("universe: " .. s:getCallSign() .. " is over 20U from the Annex", dist(x, y, ANNEX_X, ANNEX_Y) > 20000,
            string.format("%.1fU", dist(x, y, ANNEX_X, ANNEX_Y) / 1000))
        T.check("universe: hostile to the crew", s:isEnemy(T.P()))
    end
    T.eq("universe: VERSE counted them", VERSE.platform_count, 3)
end)

T.step("a lance 4U off the ship, facing away", function()
    T.P():setCanBeDestroyed(false)
    local x, y = T.P():getPosition()
    -- Stock lance settings (playtest: with the old +/-10 degree sweep, in step with the 2.8 s
    -- cadence, a stationary freighter could go half a minute without a hit).
    plat = PLATFORMS.spawn{kind = "lance", x = x + 4000, y = y, faction = "Corsairs", max_range = 6000,
                           aim = 0}   -- the ship is due west of it (180): it must turn first
    T.check("spawn: a platform", RT.valid(plat))
    T.check("spawn: hostile to the crew", plat:isEnemy(T.P()))
    h0, s0 = T.P():getHull(), T.P():getShieldLevel(0)
end)
T.waitFor("fire: it turns, fires and the ship takes damage", function()
    return T.P():getHull() < h0 or T.P():getShieldLevel(0) < s0 - 1
end, 40)   -- about one hit every 7 s at the stock lance settings
T.step("hit", function()
    local t
    for _, e in ipairs(PLATFORMS.list) do if e.obj == plat then t = e end end
    local want = angleRotation(plat, T.P())
    T.check("fire: it turned to face the ship", t and math.abs((t.angle - want + 180) % 360 - 180) < 5, t and t.angle)
    T.check("fire: no engine mismatch", PLATFORMS._fire_error == nil, tostring(PLATFORMS._fire_error))
    -- Out of range: 10U from a 6U platform.
    local x, y = plat:getPosition()
    T.P():setPosition(x - 10000, y)
    T.P():setHull(T.P():getHullMax())
end)
T.wait(1)   -- shells already in flight finish
T.step("out of range", function() h0, s0 = T.P():getHull(), T.P():getShieldLevel(0) end)
T.wait(5)
T.step("holds fire out of range", function()
    T.check("range: no damage at 10U", T.P():getHull() >= h0 and T.P():getShieldLevel(0) >= s0 - 0.5,
        string.format("hull %.1f -> %.1f, shield %.1f -> %.1f", h0, T.P():getHull(), s0, T.P():getShieldLevel(0)))
    plat:destroy()
end)
T.wait(0.5)
T.step("a destroyed platform drops off the list", function()
    local still = false
    for _, e in ipairs(PLATFORMS.list) do if e.obj == plat then still = true end end
    T.check("cleanup: gone from PLATFORMS.list", not still)
end)
