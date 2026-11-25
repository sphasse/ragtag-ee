-- Tow jobs: a broken-down ship out in quiet space (no danger, no patrol zone); the board's text ("We
-- got a call...") and its "We'll get 'em home" button; the ship (no engines, can't be destroyed);
-- Engineering's tow button only for the job's own ship and only within reach; the ship trails on the
-- line; home within 4U of the port (off the line), then paid on docking; the achievements; raiders
-- (none at tier 0, up to one at tier 1, two at tier 2; hazard pay and the warning; two showing up 10U
-- out when the line first goes on, attacking at once; breaking off when the tow is home, removed when
-- paid); expiry;
-- the type's weight tapering with tier. One ship. Movement is teleporting.
-- Not covered: flying the tow by hand (tests/core/orbit.lua), the speed limit and the energy it costs
-- (tests/arcs/icehaul.lua: the same TOW line).

T.suite("jobs")

local HOME = "Port Vesper"
local M_t = JOBS._registry.tow
local m, c0, rep0, beam1

local function dist(a, b)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

T.step("tow jobs are generated in quiet space", function()
    T.check("tow: registered", M_t ~= nil)
    local bad = 0
    for _ = 1, 20 do
        local j = T.makeJob("tow", HOME)
        local r = VERSE.regionAt(j.wx, j.wy)
        if r and ((r.danger or 0) > 0 or PROX.zones[r.name]) then bad = bad + 1 end
        if j.distance_u > 60000 then bad = bad + 1 end
    end
    T.eq("tow: never in danger, a patrol zone or over 60U out", bad, 0)
    m = T.postJob(T.makeJob("tow", HOME))
    T.check("tow: we got a call", m.brief:find('"We got a call.', 1, true) == 1, m.brief)
    T.check("tow: the brief names the ship", m.brief:find(m.target_cs, 1, true) ~= nil)
    T.eq("tow: short", m.short, "Tow " .. m.target_cs .. " home")
end)

-- Taking it: the details, then "We'll get 'em home".
T.takeJob(function() return m end)
T.step("the details", function()
    T.check("details: we got a call", T.msg():find('"We got a call.', 1, true) == 1, T.msg())
    T.check("details: no come-back line", T.msg():find("Come back when it's done", 1, true) == nil)
    T.check("details: the acknowledge button", T.hasReply("We'll get 'em home"))
    T.check("details: no plain Back", not T.hasReply("Back"))
    T.eq("relay: the job's line", JOBS.panelLine(m), ("Tow " .. m.target_cs):sub(1, JOBS.PANEL_MAX))
end)
T.reply({"We'll get 'em home"})
T.closeComms()
T.undock()

T.step("the broken-down ship", function()
    local s = m.target
    T.check("ship: spawned", RT.valid(s))
    T.eq("ship: its name", s:getCallSign(), m.target_cs)
    T.eq("ship: Independent", s:getFaction(), "Independent")
    T.eq("ship: no engines", s:getImpulseMaxSpeed(), 0)
    T.check("ship: no warp", not s:hasWarpDrive())
    local x, y = s:getPosition()
    T.check("ship: where the job says", math.abs(x - m.wx) < 1 and math.abs(y - m.wy) < 1)
    -- Too far: no button.
    T.moveTo(m.wx + 5000, m.wy)
end)
T.wait(0.5)
T.step("far: no button", function()
    T.check("far: no button", not TOW.buttonLabel(T.P()))
    T.moveTo(m.wx + 1500, m.wy)
end)
T.wait(0.5)

-- Another ship in reach gets no button: the job's ship tows it.
local B
T.step("another ship in reach", function()
    B = T.secondShip()
    B:setPosition(m.wx - 1500, m.wy)
end)
T.wait(0.5)
T.step("reach", function()
    T.check("other ship: no button", not TOW.buttonLabel(B))
    T.eq("own ship: the button", TOW.buttonLabel(T.P()), "Attach tow line")
    TOW.press(T.P())
    T.eq("attach: on the job's ship's line", TOW.towedBy(m.target), T.P())
    B:setPosition(m.wx - 40000, m.wy)
end)
T.wait(0.5)
T.step("the line", function()
    T.check("line: trails at the line's length", math.abs(dist(T.P(), m.target) - TOW.LENGTH) < 60,
        string.format("%.0f", dist(T.P(), m.target)))
    T.eq("line: the button", TOW.buttonLabel(T.P()), "Release tow line")
    local b = TOW.beam(T.P())
    T.check("line: visible (a beam)", b ~= nil and b:isValid())
    if b and b:isValid() then
        local be = b.components.beam_effect
        T.check("beam: from the ship", be.source == T.P())
        T.check("beam: to the towed ship", be.target == m.target)
        T.eq("beam: held lit", be.fade_speed, 0)
        T.check("beam: lit", be.lifetime > 0.9, tostring(be.lifetime))
    end
    beam1 = b
    -- Not home yet: 8U from the port.
    local hx, hy = T.find(HOME):getPosition()
    T.moveTo(hx + 8000, hy)
end)
T.wait(1)
T.step("not home yet", function()
    T.check("8U out: not home", not m._found)
    T.check("8U out: still on the line", TOW.towedBy(m.target) == T.P())
    local hx, hy = T.find(HOME):getPosition()
    T.moveTo(hx + 2000, hy)   -- the ship trails 1.5U further out: 3.5U
end)
T.waitFor("home: within 4U of the port", function() return m._found end, 3)
T.step("home", function()
    T.check("home: off the line", TOW.towedBy(m.target) == nil)
    T.check("home: no beam on the ship", TOW.beam(T.P()) == nil)
    T.check("home: the beam fading", beam1 and beam1:isValid() and beam1.components.beam_effect.fade_speed > 0)
    T.check("home: the line's button gone", not TOW.buttonLabel(T.P()))
    T.eq("relay: back to the port", JOBS.panelLine(m), "Return to Vesper")
end)
T.wait(1)
T.step("the beam faded out", function() T.check("home: the beam gone", not (beam1 and beam1:isValid())) end)
T.dock(HOME)
T.step("note credits", function() c0 = T.credits() end)
T.talk(HOME, {function() return string.format("Got 'em home (+%d cr)", m.reward) end})
T.step("paid", function()
    T.eq("paid: the reward", T.credits() - c0, m.reward)
    T.check("paid: done", T.activeEntry(m) == nil)
    T.check("paid: the ship taken in", not RT.valid(m.target))
end)
T.closeComms()
T.waitFor("achievement: We Got a Call", function() return ACH.has("we_got_a_call") end, 7)
T.step("not yet Recovery Crew", function() T.check("one tow: no Recovery Crew yet", not ACH.has("recovery_crew")) end)

-- Raiders: none before the first upgrade tier, up to one at tier 1, up to two at tier 2.
T.step("raider odds by tier", function()
    local most, some = {[0] = 0, [1] = 0, [2] = 0}, {[0] = 0, [1] = 0, [2] = 0}
    for tier = 0, 2 do
        for _ = 1, 300 do
            local n = M_t.rollRaiders(tier)
            if n > most[tier] then most[tier] = n end
            if n > 0 then some[tier] = some[tier] + 1 end
        end
    end
    T.eq("tier 0: never raiders", most[0], 0)
    T.eq("tier 1: at most one", most[1], 1)
    T.eq("tier 2: up to two", most[2], 2)
    T.check("tier 1: sometimes none", some[1] < 300 and some[1] > 0, tostring(some[1]))
    T.check("tier 2: more often than tier 1", some[2] > some[1], some[2] .. " vs " .. some[1])
    T.eq("no ship tier: no raiders", M_t.rollRaiders(nil), 0)
    T.eq("the first tow drew none", m.raider_ships, nil)
end)

local R   -- a tow with two raiders
T.step("a tow with raiders", function()
    for _ = 1, 20 do
        local ctx = JOBS.offerContext(HOME)
        ctx.tier, ctx.max_tier = 0, 2
        local opts = M_t.prepareOpts(ctx)
        if opts then
            opts.raiders = 2
            R = M_t.generate(opts)
            local plain = JOBS.calcReward(JOBS.ECONOMY.base_reward[0], JOBS.ECONOMY.type_mult.tow * R.reward_mult,
                opts.distance_u, 2, opts.distance_min_u, opts.distance_max_u, 1.0)
            T.eq("raiders: hazard pay (+15% a raider) and 100 cr for missiles", R.reward, plain + 100)
            break
        end
    end
    T.check("raiders: the brief warns", R.brief:find("expect company", 1, true) ~= nil, R.brief)
    T.check("raiders: the brief names the missile money", R.brief:find("100 cr for the missiles", 1, true) ~= nil, R.brief)
    T.check("raiders: the board says so", M_t.offerText(R, ""):find("Raiders about.", 1, true) ~= nil)
    T.check("no raiders: the board doesn't", M_t.offerText(m, ""):find("Raiders", 1, true) == nil)
    m = T.postJob(R)
end)
T.takeJob(function() return m end)
T.step("no raiders before the line goes on", function()
    T.undock()
    T.moveTo(m.wx + 1500, m.wy)
end)
T.wait(1)
T.step("in reach, no line: no raiders yet", function()
    T.eq("before the line: no raiders", m.raider_ships, nil)
    TOW.press(T.P())
    T.check("line on", TOW.towedBy(m.target) == T.P())
end)
T.step("the line goes on: raiders, 10U out, attacking", function()
    T.eq("raiders: two", #(m.raider_ships or {}), 2)
    for i, s in ipairs(m.raider_ships or {}) do
        T.eq("raider " .. i .. ": Shroud Raiders", s:getFaction(), "Shroud Raiders")
        T.check("raider " .. i .. ": hostile", s:isEnemy(T.P()))
        T.check("raider " .. i .. ": about 10U out", math.abs(dist(T.P(), s) - TOW.INTERCEPT_DIST) < 1000,
            string.format("%.0f", dist(T.P(), s)))
        T.eq("raider " .. i .. ": attacking", s:getOrder(), "Attack")
        T.eq("raider " .. i .. ": 20% over the tow limit (300)", s:getImpulseMaxSpeed(), 300)
    end
    T.eq("raiders: the first an Adder", m.raider_ships[1]:getTypeName(), "Adder MK5")
    -- Casting off and back on brings no more.
    TOW.press(T.P())
    TOW.press(T.P())
    T.eq("re-attach: still two", #m.raider_ships, 2)
    local hx, hy = T.find(HOME):getPosition()
    T.moveTo(hx + 2000, hy)
end)
T.waitFor("raiders: home", function() return m._found end, 3)
T.step("home: raiders break off", function()
    for i, s in ipairs(m.raider_ships) do
        T.check("raider " .. i .. ": breaks off", RT.valid(s) and s:getOrder() == "Fly towards", s:getOrder())
    end
    R = m.raider_ships
end)
T.dock(HOME)
T.talk(HOME, {function() return string.format("Got 'em home (+%d cr)", m.reward) end})
T.step("paid: raiders gone", function()
    T.check("paid: done", T.activeEntry(m) == nil)
    for i, s in ipairs(R) do T.check("raider " .. i .. ": removed", not RT.valid(s)) end
end)
T.closeComms()

-- Expiry: the ship is removed and the line let go.
T.step("a second job runs out of time", function() m = T.postJob(T.makeJob("tow", HOME)) end)
T.takeJob(function() return m end)
T.step("tow it, then expire", function()
    T.undock()
    T.moveTo(m.wx + 1500, m.wy)
    TOW.attach(T.P(), m.target)
    rep0 = T.rep(m.origin_faction)
    m._expires_at = T.now() - 1
end)
T.waitFor("expiry: dropped", function() return T.activeEntry(m) == nil end, 3)
T.step("expired", function()
    T.eq("expiry: standing -reward", T.rep(m.origin_faction) - rep0, -m.reward)
    T.check("expiry: the ship is gone", not RT.valid(m.target))
    T.check("expiry: the line let go", not TOW._lines[T.P()])
end)
T.wait(0.5)
T.step("expired: no button", function() T.check("expiry: no button", not TOW.buttonLabel(T.P())) end)

-- Ten tows: Recovery Crew.
T.step("ten tows", function()
    local s = STATS.ensure()
    s.jobs.completed.tow = 10
end)
T.waitFor("achievement: Recovery Crew", function() return ACH.has("recovery_crew") end, 7)

-- The board: common early, tapering off with tier.
T.step("weights taper with tier", function()
    local function share(tier)
        local saved = JOBS.maxTier
        JOBS.maxTier = function() return tier end
        local n, tows = 400, 0
        for _ = 1, n do if JOBS.pickType(T.P()) == "tow" then tows = tows + 1 end end
        JOBS.maxTier = saved
        return tows / n
    end
    local s0, s1, s2 = share(0), share(1), share(2)
    T.check("tier 0: some tows, fewer than deliveries", s0 > 0.1 and s0 < 0.4, string.format("%.2f", s0))
    T.check("tier 1: fewer", s1 < s0, string.format("%.2f vs %.2f", s1, s0))
    T.check("tier 2: fewer still", s2 < s1, string.format("%.2f vs %.2f", s2, s1))
end)

-- Jack of All Trades counts the board's types only, towing included.
T.step("jack of all trades needs a tow", function()
    local s = STATS.ensure()
    RT.campaign.achievements.jack_of_all_trades = nil
    for t in pairs(JOBS._registry) do s.jobs.completed[t] = 1 end
    s.jobs.completed.tow = 0
    s.jobs.completed.some_old_type = 3   -- a type no longer on the board doesn't stand in for one
end)
T.wait(6)
T.step("not without a tow", function()
    T.check("jack: not earned without a tow", not ACH.has("jack_of_all_trades"))
    STATS.ensure().jobs.completed.tow = 1
end)
T.waitFor("achievement: Jack of All Trades with every type", function() return ACH.has("jack_of_all_trades") end, 7)
