-- The job board itself: listing, taking, the active-job cap, completion (credits and standing),
-- expiry, story contracts, the reputation gate and the board lock. One ship. Jobs are generated
-- by the delivery module and posted on Port Vesper's board; the random draw of job types is not
-- covered.

T.suite("jobs")

local HOME = "Port Vesper"
local a, b, c, story
local c0, rep0

local function distinct(n)
    local out, seen = {}, {}
    for _ = 1, 60 do
        local m = T.makeJob("delivery", HOME)
        if not seen[m.short] then seen[m.short] = true; out[#out + 1] = m end
        if #out == n then return out end
    end
    error("could not make " .. n .. " distinct deliveries")
end
local function active() return #JOBS._active end

-- ── Listing and taking ───────────────────────────────────────────────────────
T.step("post three deliveries", function()
    local js = distinct(3)
    a, b, c = T.postJob(js[1]), T.postJob(js[2]), T.postJob(js[3])
end)
T.dock(HOME)
T.talk(HOME, {"Any work available?"})
T.step("the board lists them", function()
    T.check("board: header", T.msg():find("Work out of Port Vesper", 1, true) ~= nil, T.msg())
    for _, m in ipairs({a, b, c}) do
        T.check("board: lists " .. m.short, T.hasReply("Take: " .. m.short), table.concat(T.replies(), " | "))
    end
    T.check("board: can walk away", T.hasReply("Nothing for me"))
end)
T.talk(HOME, {"Any work available?", function() return "Take: " .. a.short end})
T.step("took the first", function()
    T.eq("take: one active job", active(), 1)
    T.check("take: the job is active", T.activeEntry(a) ~= nil)
    T.check("take: it has a deadline", a._expires_at and a._expires_at > T.now())
    T.eq("take: origin faction recorded", a.origin_faction, "Independent")
    T.check("take: brief shown", T.msg():find("Transmitting details", 1, true) ~= nil, T.msg())
end)
T.talk(HOME, {"Any work available?"})
T.step("a taken job leaves the board", function()
    T.check("board: taken job not offered again", not T.hasReply("Take: " .. a.short))
    T.check("board: the others still are", T.hasReply("Take: " .. b.short) and T.hasReply("Take: " .. c.short))
end)

-- ── The cap ──────────────────────────────────────────────────────────────────
T.talk(HOME, {"Any work available?", function() return "Take: " .. b.short end})
T.talk(HOME, {"Any work available?", function() return "Take: " .. c.short end})
T.step("two is the limit", function()
    T.eq("cap: still two active", active(), 2)
    T.check("cap: third refused", T.msg():find("pretty busy", 1, true) ~= nil, T.msg())
    T.check("cap: refused job is not active", T.activeEntry(c) == nil)
end)

-- ── Completion ───────────────────────────────────────────────────────────────
T.talk(HOME, {})
T.step("nothing to hand off at the origin", function()
    T.check("complete: no hand-off at the wrong station", not T.hasReply("Hand off " .. a.cargo))
end)
T.dock(function() return T.find(a.dest) end)
T.talk(function() return T.find(a.dest) end, {})
T.step("hand-off on offer at the destination", function()
    T.check("complete: hand-off offered", T.hasReply("Hand off " .. a.cargo), table.concat(T.replies(), " | "))
    c0, rep0 = T.credits(), T.rep(a.origin_faction)
end)
T.talk(function() return T.find(a.dest) end, {function() return "Hand off " .. a.cargo end})
T.step("paid", function()
    T.eq("complete: credits +reward", T.credits() - c0, a.reward)
    T.eq("complete: standing with the origin's faction +reward", T.rep(a.origin_faction) - rep0, a.reward)
    T.check("complete: job no longer active", T.activeEntry(a) == nil)
    T.eq("complete: one active job left", active(), 1)
    T.check("complete: message names the payment", T.msg():find(a.reward .. " credits transferred", 1, true) ~= nil, T.msg())
end)

-- ── Expiry ───────────────────────────────────────────────────────────────────
T.step("let the second run out", function()
    rep0 = T.rep(b.origin_faction)
    b._expires_at = T.now() - 1
end)
T.waitFor("expiry: an overdue job is dropped", function() return T.activeEntry(b) == nil end, 3)
T.step("expired", function()
    T.eq("expiry: standing -reward", T.rep(b.origin_faction) - rep0, -b.reward)
    T.eq("expiry: no active jobs", active(), 0)
end)

-- ── Story contracts ──────────────────────────────────────────────────────────
local fired = {}
T.step("fill the cap, then post a story contract", function()
    -- Slots a job was taken from stay empty for the work cooldown (10 min); free them for the test.
    JOBS.removeCategory("TEST_JOBS")
    for _, slot in pairs(JOBS._station_work[HOME].slots) do
        T.check("cooldown: a slot is either cooling down or holding an offer", slot.taken_at ~= nil or slot.mission ~= nil)
        slot.taken_at, slot.mission = nil, nil
    end
    local js = distinct(2)
    T.postJob(js[1]); T.postJob(js[2]); a, b = js[1], js[2]
    story = JOBS.build("delivery", {
        id = "test_story", origin = HOME, dest = "Calder's Reach", cargo = "test relics", reward = 111,
        story = true, brief = "A test.",
        on_accept = function() fired.accept = true end,
        on_complete = function() fired.complete = true end,
    })
    JOBS.inject({category = "TEST_STORY", priority = 5, origin = HOME, record = story})
end)
T.dock(HOME)
T.talk(HOME, {"Any work available?", function() return "Take: " .. a.short end})
T.talk(HOME, {"Any work available?", function() return "Take: " .. b.short end})
T.talk(HOME, {"Any work available?"})
T.step("story contract is marked", function()
    T.eq("story: cap reached with ordinary jobs", active(), 2)
    T.check("story: listed as [SPECIAL]", T.msg():find("[SPECIAL]", 1, true) ~= nil, T.msg())
    T.check("story: no time limit shown", T.msg():find("no time limit", 1, true) ~= nil)
end)
T.talk(HOME, {"Any work available?", "Take: test relics"})
T.step("story contract ignores the cap", function()
    T.eq("story: three active", active(), 3)
    T.check("story: no deadline", story._expires_at == nil)
    T.check("story: on_accept ran", fired.accept)
end)
T.dock("Calder's Reach")
T.talk("Calder's Reach", {"Hand off test relics"})
T.step("story contract paid", function()
    T.check("story: on_complete ran", fired.complete)
    T.eq("story: two active again", active(), 2)
    JOBS.removeCategory("TEST_STORY")
    JOBS.removeCategory("TEST_JOBS")
end)

-- ── Reputation gate ──────────────────────────────────────────────────────────
T.step("a bad name with the Independents", function()
    RT.addReputation("Independent", -450 - T.rep("Independent"), "test")
    T.check("rep gate: standing is below -400", T.rep("Independent") < -400, T.rep("Independent"))
end)
T.dock(HOME)
T.talk(HOME, {"Any work available?"})
T.step("no work for the untrusted", function()
    T.check("rep gate: turned away", T.msg():find("nothing for someone with your reputation", 1, true) ~= nil, T.msg())
    T.check("rep gate: nothing to take", not T.hasReply("Take: "))
    RT.addReputation("Independent", 100 - T.rep("Independent"), "test")
end)

-- ── Board lock ───────────────────────────────────────────────────────────────
T.step("lock the board (a story arc can)", function() JOBS.config.jobboard_locked = true end)
T.talk(HOME, {})
T.step("locked", function()
    T.check("lock: no work on offer", not T.hasReply("Any work available?"))
    JOBS.config.jobboard_locked = false
end)
T.talk(HOME, {})
T.step("unlocked", function() T.check("lock: work on offer again", T.hasReply("Any work available?")) end)
T.closeComms()
