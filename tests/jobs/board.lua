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

-- ── Pay: every job variant's own multiplier is applied ──────────────────────
-- Each job type's archetypes carry reward_mult (0.8..2.0); the pay formula multiplies the type's
-- multiplier by it. Checked on what each module hands JOBS.calcReward, for every type.
T.step("pay uses each variant's reward_mult", function()
    local seen_type_mult
    local _calc = JOBS.calcReward
    JOBS.calcReward = function(base, type_mult, ...)
        seen_type_mult = type_mult
        return _calc(base, type_mult, ...)
    end
    local ok, err = pcall(function()
        for _, jtype in ipairs({"delivery", "salvage", "hacking", "destroy", "boarding", "escort", "tailing", "tow"}) do
            local mults, wrong = {}, 0
            for _ = 1, 12 do
                seen_type_mult = nil
                local m = T.makeJob(jtype, HOME, 2)
                local want = JOBS.ECONOMY.type_mult[jtype] * m.reward_mult
                if not seen_type_mult or math.abs(seen_type_mult - want) > 1e-9 then wrong = wrong + 1 end
                mults[m.reward_mult] = true
            end
            local kinds = 0
            for _ in pairs(mults) do kinds = kinds + 1 end
            T.eq("pay: " .. jtype .. " multiplies by the variant's reward_mult", wrong, 0)
            T.check("pay: " .. jtype .. " variants pay differently", kinds > 1, kinds)
        end
    end)
    JOBS.calcReward = _calc
    if not ok then error(err) end
end)

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

-- ── JOBS.board: what a station offers, decided without a comms window ────────
-- The listing above goes through comms; these call the deciding half directly.
T.step("clear the board", function()
    for _, e in ipairs({table.unpack(JOBS._active)}) do JOBS.complete(e) end
    JOBS.removeCategory("TEST_JOBS"); JOBS.removeCategory("TEST_STORY")
    JOBS._station_work = {}
    JOBS.config.jobboard_locked = false
    RT.addReputation("Independent", 100 - T.rep("Independent", T.P()), "test", T.P())
end)
local first
T.step("a station fills its slots", function()
    local slots = JOBS.stationSlots(HOME)
    local b = JOBS.board(HOME, T.P())
    first = b.offers
    T.check("decide: no more offers than the station has slots", #first >= 1 and #first <= slots, #first .. " of " .. slots)
    T.check("decide: nothing is said about a good standing", b.nag == nil and not b.closed)
    local seen, dup = {}, false
    for _, m in ipairs(first) do
        local k = m.type .. "|" .. m.short
        if seen[k] then dup = true end
        seen[k] = true
        if not (m.id and m.reward and m.reward > 0 and m.origin == HOME) then
            T.check("decide: an offer is a complete job record", false, tostring(m.short))
        end
    end
    T.check("decide: no two offers with the same summary", not dup)
end)
T.step("the same jobs are there on the next visit", function()
    local again = JOBS.board(HOME, T.P()).offers
    T.check("cache: at least as many (a slot that failed to fill may fill now)", #again >= #first, #again .. " vs " .. #first)
    for _, m in ipairs(first) do
        local found = false
        for _, o in ipairs(again) do if o == m then found = true end end
        if not found then T.check("cache: " .. m.short .. " still offered", false) end
    end
end)
T.step("a taken slot stays empty until it cools down", function()
    local taken = first[1]
    T.check("slot: taken", JOBS.accept(taken, true, T.P()))
    local b = JOBS.board(HOME, T.P())
    local offered = false
    for _, o in ipairs(b.offers) do if o == taken then offered = true end end
    T.check("slot: the taken job is off the board", not offered)
    T.check("slot: its slot stays empty", #b.offers <= JOBS.stationSlots(HOME) - 1, #b.offers)
    T.check("slot: the board says when to come back", b.wait and b.wait > 0 and b.wait <= JOBS.config.work_cooldown_secs, tostring(b.wait))
    -- The crew hears a rough time, never minutes and seconds.
    T.eq("check back: over 5 min", JOBS.checkBackText(301), '"No new contracts right now. Check back in a while."')
    T.eq("check back: over 2 min", JOBS.checkBackText(121), '"No new contracts right now. Check back in a few."')
    T.eq("check back: 2 min or less", JOBS.checkBackText(120), '"No new contracts right now. Check back in a bit."')
    T.eq("check back: 5 min exactly is a few", JOBS.checkBackText(300), '"No new contracts right now. Check back in a few."')
    for _, slot in pairs(JOBS._station_work[HOME].slots) do
        if slot.taken_at then slot.taken_at = T.now() - JOBS.config.work_cooldown_secs - 1 end
    end
    b = JOBS.board(HOME, T.P())
    T.check("slot: refilled after the cooldown", #b.offers >= #first, #b.offers .. " vs " .. #first)
    T.check("slot: nothing left cooling down", b.wait == nil)
    JOBS.complete(T.activeEntry(taken))
end)
T.step("an ensured job takes a slot on a full board", function()
    local m = T.postJob(T.makeJob("delivery", HOME))
    local b = JOBS.board(HOME, T.P())
    local found = false
    for _, o in ipairs(b.offers) do if o == m then found = true end end
    T.check("ensure: the posted job is offered", found)
    T.check("ensure: within the station's slots", #b.offers <= JOBS.stationSlots(HOME), #b.offers)
    JOBS.removeCategory("TEST_JOBS")
end)
T.step("standing decides how much is shown", function()
    local slots = JOBS.stationSlots(HOME)
    RT.addReputation("Independent", -100 - T.rep("Independent", T.P()), "test", T.P())
    local b = JOBS.board(HOME, T.P())
    T.check("gate: one offer fewer below 0", #b.offers <= slots - 1 and b.nag ~= nil and not b.closed, #b.offers)
    RT.addReputation("Independent", -450 - T.rep("Independent", T.P()), "test", T.P())
    b = JOBS.board(HOME, T.P())
    T.check("gate: closed below -400", #b.offers == 0 and b.closed and b.nag ~= nil)
    RT.addReputation("Independent", 100 - T.rep("Independent", T.P()), "test", T.P())
end)
-- The Short Haul: a taken slot refills at once (refill_secs = 0), but untaken offers still stand:
-- hailing again does not re-roll the board.
T.step("refill_secs 0: a taken job is replaced at once, the rest stand", function()
    JOBS.config.refill_secs = 0
    JOBS._station_work = {}
    local b1 = JOBS.board(HOME, T.P()).offers
    T.check("refill: at least two offers to work with", #b1 >= 2, #b1)
    local again = JOBS.board(HOME, T.P()).offers
    local same = #again == #b1
    for i, m in ipairs(b1) do
        local found = false
        for _, o in ipairs(again) do if o == m then found = true end end
        same = same and found
    end
    T.check("refill: hailing again shows the same offers (no re-roll)", same)
    local taken, kept = b1[1], b1[2]
    T.check("refill: taken", JOBS.accept(taken, true, T.P()))
    local b2 = JOBS.board(HOME, T.P())
    local has_taken, has_kept = false, false
    for _, o in ipairs(b2.offers) do
        if o == taken then has_taken = true end
        if o == kept then has_kept = true end
    end
    T.check("refill: the taken job is gone", not has_taken)
    T.check("refill: the other offer still stands", has_kept)
    T.eq("refill: the board is full again at once", #b2.offers, #b1)
    T.check("refill: nothing to wait for", b2.wait == nil, tostring(b2.wait))
    JOBS.complete(T.activeEntry(taken))
    JOBS.config.refill_secs = nil
end)
-- The Relay job lines fit the 20-character side panel and say what to do next.
T.step("job lines fit the side panel", function()
    local cases = {
        {{type = "delivery", dest = "Saint Brennan's Mission", origin = HOME}, "Deliver to Brennan's"},
        {{type = "delivery", dest = "Halcyon Rest", origin = HOME}, "Deliver to Halcyon"},
        {{type = "escort", dest = "Port Vesper", origin = HOME}, "Escort to Vesper"},
        {{type = "salvage", wx = 0, wy = 0, origin = HOME}, nil},
        {{type = "salvage", origin = "Concord Station Arbiter", _found = true}, "Return to Arbiter"},
        {{type = "hacking", target_cs = "Relay K-7", origin = HOME}, "Hack Relay K-7"},
        {{type = "destroy", target_cs = "Iron Gull", origin = HOME}, "Destroy Iron Gull"},
        {{type = "destroy", target_cs = "Iron Gull", origin = "Port Vesper", _destroyed = true}, "Return to Vesper"},
        {{type = "boarding", target_cs = "An Extremely Long Ship Name", origin = HOME}, nil},
        {{type = "tailing", target_cs = "Grey Heron", origin = HOME}, "Tail Grey Heron"},
        {{type = "tow", target_cs = "Old Reliable", origin = HOME}, "Tow Old Reliable"},
        {{type = "tow", target_cs = "Old Reliable", origin = "Port Vesper", _found = true}, "Return to Vesper"},
    }
    for _, c in ipairs(cases) do
        local line = JOBS.panelLine(c[1])
        T.check("panel: fits 20: " .. line, #line <= 20, #line)
        if c[2] then T.eq("panel: " .. c[1].type, line, c[2]) end
    end
    T.eq("panel: a tiny name is the first word", JOBS.tinyName("Calder's Reach"), "Calder's")
    -- An accepted job shows on Relay.
    local m = T.makeJob("delivery", HOME)
    T.check("panel: taken", JOBS.accept(m, true, T.P()))
    JOBS.refreshPanel()
    local f, shown = T.P().components.custom_ship_functions, nil
    for i = 1, #f do if tostring(f[i].name) == "rt_job_1" then shown = tostring(f[i].caption) end end
    T.eq("panel: Relay shows the job line", shown, JOBS.panelLine(m))
    T.check("panel: it fits", shown and #shown <= 20, tostring(shown))
    local function caption(key)
        local fs = T.P().components.custom_ship_functions
        for i = 1, #fs do if tostring(fs[i].name) == key then return tostring(fs[i].caption) end end
    end
    local timer = caption("rt_job_1_time")
    T.check("panel: a countdown under the job", timer and timer:match("^Time left %d+:%d%d$"), tostring(timer))
    T.check("panel: the countdown fits", timer and #timer <= 20, tostring(timer))
    T.eq("panel: the time limit is whole minutes", m._time_limit % 60, 0)
    T.check("panel: the countdown starts at whole minutes",
        timer:match(":(%d%d)$") == "00" or timer:match(":(%d%d)$") == "59", tostring(timer))
    local secs = m._expires_at - T.now()
    T.check("panel: the countdown is the time left",
        timer == string.format("Time left %d:%02d", math.floor(secs / 60), math.floor(secs) % 60)
        or timer == JOBS.timerLine(m), tostring(timer))
    JOBS.complete(T.activeEntry(m))
    JOBS.refreshPanel()
    T.eq("panel: the countdown goes with the job", caption("rt_job_1_time"), nil)
    T.eq("panel: the slot is empty again", caption("rt_job_1"), "Job 1: (none)")
    -- A job with no time limit (a story job without one) has no countdown.
    local s = T.makeJob("delivery", HOME)
    s.story = true
    T.check("panel: story job taken", JOBS.accept(s, true, T.P()))
    JOBS.refreshPanel()
    T.eq("panel: no countdown without a time limit", caption("rt_job_1_time"), nil)
    JOBS.complete(T.activeEntry(s))
    JOBS.refreshPanel()
end)
T.wait(2.5)
T.step("the countdown ticks", function()
    local m = T.makeJob("delivery", HOME)
    T.check("tick: taken", JOBS.accept(m, true, T.P()))
    JOBS.refreshPanel()
    local before = JOBS.timerLine(m)
    T.check("tick: a countdown", before ~= nil)
    _G.__tick_m, _G.__tick_before = m, before
end)
T.wait(2.5)
T.step("the countdown went down", function()
    local m = _G.__tick_m
    local fs, now_shown = T.P().components.custom_ship_functions, nil
    for i = 1, #fs do if tostring(fs[i].name) == "rt_job_1_time" then now_shown = tostring(fs[i].caption) end end
    T.check("tick: Relay's countdown moved on by itself", now_shown and now_shown ~= _G.__tick_before,
        tostring(_G.__tick_before) .. " -> " .. tostring(now_shown))
    JOBS.complete(T.activeEntry(m))
    JOBS.refreshPanel()
end)
T.step("with the cooldown off the board is rebuilt each visit", function()
    JOBS.config.work_cooldown_enabled = false
    JOBS._station_work = {}
    local b = JOBS.board(HOME, T.P())
    T.check("no cooldown: offers", #b.offers >= 1)
    for _, slot in pairs(JOBS._station_work[HOME].slots) do
        if slot.mission then T.check("no cooldown: nothing is cached in the slots", false) end
    end
    T.check("no cooldown: nothing to wait for", b.wait == nil)
    JOBS.config.work_cooldown_enabled = true
end)
