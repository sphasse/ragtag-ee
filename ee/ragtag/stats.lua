-- ee/ragtag/stats.lua
-- Campaign statistics and achievements. Tracks, persistently (in RT.campaign, saved with the
-- campaign): play time, money earned and spent (and by source), jobs accepted / completed /
-- failed by type, regions visited, story arcs (started / completed / cancelled, status,
-- outcome), free-form counters, and achievements.
--
-- Nothing here shows itself to the crew. Exposure (screens, end-of-session report) comes
-- later; the data and the report builders are ready:
--   STATS.summary()      -> structured table (totals, per-type jobs, regions, arcs, achievements,
--                           plus "this session" deltas)
--   STATS.reportText()   -> the same as a multi-line string
-- GM-only view while testing: campaign GM menu -> "Stats report".
--
-- Hooks (called from the engines, all defensive: a stats error never breaks gameplay):
--   STATS.jobAccepted(m) / jobCompleted(m) / jobFailed(m)     jobs/_engine.lua
--   STATS.regionEntered(name, first_ever)                     verse.lua
--   STATS.arcEvent(id, "started"|"completed"|"cancelled")     missions/_engine.lua
--   STATS.noteCredits(amount, reason)                         RT.addCredits
--   STATS.update(delta)                                       RT.update (play time, credit deltas, achievements)
-- Free-form: STATS.inc("kills_corsair", 1), STATS.get("kills_corsair").
--
-- Achievements: ACH.define{id, name, desc, hidden, category, check = function(S) return bool end}
-- is evaluated every few seconds; ACH.award(id) grants one directly (from an arc or event).
-- Awards persist. ACH.announce (default false) controls whether the crew is told.

STATS = STATS or {}
ACH   = ACH   or {}

STATS.VERSION = 1
ACH.announce  = false   -- set true when the crew-facing UI is designed
ACH.defs      = ACH.defs or {}
ACH.order     = ACH.order or {}

local function _guard(name, fn)
    return function(...)
        local ok, res = pcall(fn, ...)
        if not ok then log("[STATS] " .. name .. " error: " .. tostring(res)) end
        return res
    end
end

local function _tbl(parent, key)
    if type(parent[key]) ~= "table" then parent[key] = {} end
    return parent[key]
end

-- Make sure the persisted tables exist (toJSON/fromJSON can turn empty tables into arrays).
function STATS.ensure()
    local c = RT.campaign
    if not c then return nil end
    local s = _tbl(c, "stats")
    s.version         = s.version or STATS.VERSION
    s.play_seconds    = s.play_seconds    or 0
    s.sessions        = s.sessions        or 0
    s.credits_earned  = s.credits_earned  or 0
    s.credits_spent   = s.credits_spent   or 0
    _tbl(s, "earned_by")     -- source -> credits (jobs, survey, other attributed sources)
    local jobs = _tbl(s, "jobs")
    _tbl(jobs, "accepted"); _tbl(jobs, "completed"); _tbl(jobs, "failed"); _tbl(jobs, "earned")
    s.story_jobs_completed = s.story_jobs_completed or 0
    _tbl(s, "regions")       -- name -> {visits, first_at}
    _tbl(s, "arcs")          -- id -> {started, completed, cancelled, last, outcome}
    _tbl(s, "counters")
    _tbl(c, "achievements")  -- id -> {at, session}
    return s
end

local function _s() return STATS.ensure() end

-- ── Free-form counters ───────────────────────────────────────────────────────
STATS.inc = _guard("inc", function(key, n)
    local s = _s(); if not s then return end
    s.counters[key] = (s.counters[key] or 0) + (n or 1)
end)

function STATS.get(key)
    local s = _s(); if not s then return 0 end
    return s.counters[key] or 0
end

-- ── Money ────────────────────────────────────────────────────────────────────
-- Totals come from watching each player ship's credit balance (positive change = earned,
-- negative = spent), so every source is counted, including pod pickups that bypass
-- RT.addCredits. addCredits also reports a source label so the report can split it.
STATS._bal = STATS._bal or {}   -- callsign -> last seen balance

STATS.noteCredits = _guard("noteCredits", function(amount, reason)
    if not amount or amount <= 0 then return end
    local s = _s(); if not s then return end
    local src = "other"
    if type(reason) == "string" then
        if reason:find("^job") then src = "jobs"
        elseif reason:find("survey") then src = "survey"
        end
    end
    s.earned_by[src] = (s.earned_by[src] or 0) + amount
end)

local function _pollCredits()
    local s = _s(); if not s then return end
    for _, p in ipairs(RT.players or {}) do
        if RT.valid(p) then
            local cs = p:getCallSign()
            local bal = math.floor(p:getReputationPoints())
            local last = STATS._bal[cs]
            if last ~= nil then
                if bal > last then s.credits_earned = s.credits_earned + (bal - last)
                elseif bal < last then s.credits_spent = s.credits_spent + (last - bal) end
            end
            STATS._bal[cs] = bal
        end
    end
end

-- ── Jobs ─────────────────────────────────────────────────────────────────────
local function _jobType(m) return (m and m.type) or "unknown" end

STATS.jobAccepted = _guard("jobAccepted", function(m)
    local s = _s(); if not s then return end
    local t = _jobType(m)
    s.jobs.accepted[t] = (s.jobs.accepted[t] or 0) + 1
end)

STATS.jobCompleted = _guard("jobCompleted", function(m)
    local s = _s(); if not s then return end
    local t = _jobType(m)
    s.jobs.completed[t] = (s.jobs.completed[t] or 0) + 1
    s.jobs.earned[t]    = (s.jobs.earned[t] or 0) + (m.reward or 0)
    if m.story then s.story_jobs_completed = s.story_jobs_completed + 1 end
end)

STATS.jobFailed = _guard("jobFailed", function(m)
    local s = _s(); if not s then return end
    local t = _jobType(m)
    s.jobs.failed[t] = (s.jobs.failed[t] or 0) + 1
end)

-- ── Regions ──────────────────────────────────────────────────────────────────
STATS.regionEntered = _guard("regionEntered", function(name, first_ever)
    local s = _s(); if not s or not name then return end
    local r = s.regions[name]
    if not r then
        r = {visits = 0, first_at = math.floor(s.play_seconds)}
        s.regions[name] = r
    end
    r.visits = r.visits + 1
end)

-- ── Story arcs ───────────────────────────────────────────────────────────────
STATS.arcEvent = _guard("arcEvent", function(id, event)
    local s = _s(); if not s then return end
    local a = s.arcs[id]
    if not a then a = {started = 0, completed = 0, cancelled = 0}; s.arcs[id] = a end
    if event == "started" then
        a.started = a.started + 1; a.last = "active"
    elseif event == "completed" then
        a.completed = a.completed + 1; a.last = "completed"
        local f = RT.flag and RT.flag(id .. "_arc_done")
        if f then a.outcome = tostring(f) end
    elseif event == "cancelled" then
        a.cancelled = a.cancelled + 1; a.last = "cancelled"
    end
end)

-- ── Achievements ─────────────────────────────────────────────────────────────
function ACH.define(def)
    assert(def.id and def.name, "ACH.define needs id and name")
    if not ACH.defs[def.id] then ACH.order[#ACH.order + 1] = def.id end
    ACH.defs[def.id] = def
end

function ACH.has(id)
    local c = RT.campaign
    return c ~= nil and type(c.achievements) == "table" and c.achievements[id] ~= nil
end

ACH.award = _guard("award", function(id)
    if ACH.has(id) then return false end
    local s = _s(); if not s then return false end
    local def = ACH.defs[id]
    RT.campaign.achievements[id] = {at = math.floor(s.play_seconds), session = s.sessions}
    log("[ACH] earned: " .. (def and def.name or id))
    if ACH.announce and def then
        RT.shipLog("[Achievement] " .. def.name .. ": " .. (def.desc or ""), "#FFD060")
    end
    if DIR then DIR.emit("achievement", {id = id, name = def and def.name or id}, "low") end
    RT.saveCampaign()
    return true
end)

-- ── Summary / report ─────────────────────────────────────────────────────────
local function _count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
local function _sum(t) local n = 0; for _, v in pairs(t or {}) do n = n + v end; return n end
local function _sortedKeys(t)
    local k = {}; for key in pairs(t or {}) do k[#k + 1] = key end; table.sort(k); return k
end

function STATS.jobsCompleted() local s = _s(); return s and _sum(s.jobs.completed) or 0 end

function STATS.summary()
    local s = _s(); if not s then return nil end
    local sum = {
        play_seconds = s.play_seconds, sessions = s.sessions,
        credits = {earned = s.credits_earned, spent = s.credits_spent, by_source = {}},
        jobs = {by_type = {}, completed = _sum(s.jobs.completed), accepted = _sum(s.jobs.accepted),
                failed = _sum(s.jobs.failed), story_completed = s.story_jobs_completed},
        regions = {visited = {}, total = 0},
        arcs = {}, achievements = {earned = {}, total = #ACH.order},
        counters = s.counters,
    }
    local attributed = 0
    for src, v in pairs(s.earned_by) do sum.credits.by_source[src] = v; attributed = attributed + v end
    if s.credits_earned > attributed then
        sum.credits.by_source.other = (sum.credits.by_source.other or 0) + (s.credits_earned - attributed)
    end
    for _, t in ipairs(_sortedKeys(s.jobs.accepted)) do
        sum.jobs.by_type[t] = {accepted = s.jobs.accepted[t], completed = s.jobs.completed[t] or 0,
                               failed = s.jobs.failed[t] or 0, earned = s.jobs.earned[t] or 0}
    end
    for t in pairs(s.jobs.completed) do   -- completed types never "accepted" (e.g. injected)
        if not sum.jobs.by_type[t] then
            sum.jobs.by_type[t] = {accepted = 0, completed = s.jobs.completed[t], failed = 0, earned = s.jobs.earned[t] or 0}
        end
    end
    for _, n in ipairs(_sortedKeys(s.regions)) do
        sum.regions.visited[#sum.regions.visited + 1] = {name = n, visits = s.regions[n].visits}
    end
    sum.regions.total = (VERSE and VERSE.REGIONS and #VERSE.REGIONS) or 0
    -- Arcs: every registered arc, with its live status.
    if MISSIONS and MISSIONS._order then
        for _, id in ipairs(MISSIONS._order) do
            local M = MISSIONS._registry[id]
            local a = s.arcs[id] or {started = 0, completed = 0, cancelled = 0}
            local live = MISSIONS._status[id]
            local status
            if live == "active" then status = "in progress (" .. tostring(MISSIONS._cur_phase[id]) .. ")"
            elseif live == "done" or a.last == "completed" then status = "completed"
            elseif live == "triggered" then status = "available"
            elseif a.last == "cancelled" then status = "cancelled"
            else status = "not started" end
            sum.arcs[#sum.arcs + 1] = {id = id, name = M and M.name or id, status = status,
                outcome = a.outcome, started = a.started, completed = a.completed, cancelled = a.cancelled}
        end
    end
    for _, id in ipairs(ACH.order) do
        local def = ACH.defs[id]
        if ACH.has(id) then
            sum.achievements.earned[#sum.achievements.earned + 1] = {id = id, name = def.name, desc = def.desc, hidden = def.hidden}
        end
    end
    -- This session
    local b = STATS._s0
    if b then
        sum.session = {
            play_seconds = s.play_seconds - b.play_seconds,
            credits_earned = s.credits_earned - b.credits_earned,
            jobs_completed = sum.jobs.completed - b.jobs_completed,
            regions_new = _count(s.regions) - b.regions,
            achievements_new = _count(RT.campaign.achievements) - b.achievements,
        }
    end
    return sum
end

local function _mmss(sec)
    sec = math.floor(sec or 0)
    return string.format("%dh %02dm", math.floor(sec / 3600), math.floor((sec % 3600) / 60))
end

function STATS.reportText()
    local sum = STATS.summary()
    if not sum then return "No campaign loaded." end
    local L = {}
    L[#L + 1] = "=== Campaign report ==="
    L[#L + 1] = string.format("Play time: %s  (%d session%s)", _mmss(sum.play_seconds), sum.sessions, sum.sessions == 1 and "" or "s")
    if sum.session then
        L[#L + 1] = string.format("This session: %s, +%d cr, %d jobs, %d new regions, %d achievements",
            _mmss(sum.session.play_seconds), sum.session.credits_earned, sum.session.jobs_completed,
            sum.session.regions_new, sum.session.achievements_new)
    end
    L[#L + 1] = ""
    L[#L + 1] = string.format("Money: earned %d, spent %d", sum.credits.earned, sum.credits.spent)
    local srcs = {}
    for _, k in ipairs(_sortedKeys(sum.credits.by_source)) do srcs[#srcs + 1] = k .. " " .. sum.credits.by_source[k] end
    if #srcs > 0 then L[#L + 1] = "  by source: " .. table.concat(srcs, ", ") end
    L[#L + 1] = ""
    L[#L + 1] = string.format("Jobs: %d completed, %d failed, %d accepted (%d story)",
        sum.jobs.completed, sum.jobs.failed, sum.jobs.accepted, sum.jobs.story_completed)
    for _, t in ipairs(_sortedKeys(sum.jobs.by_type)) do
        local j = sum.jobs.by_type[t]
        L[#L + 1] = string.format("  %-10s done %d / taken %d, failed %d, paid %d", t, j.completed, j.accepted, j.failed, j.earned)
    end
    L[#L + 1] = ""
    L[#L + 1] = string.format("Regions visited: %d of %d", #sum.regions.visited, sum.regions.total)
    local names = {}
    for _, r in ipairs(sum.regions.visited) do names[#names + 1] = r.name end
    if #names > 0 then L[#L + 1] = "  " .. table.concat(names, ", ") end
    L[#L + 1] = ""
    L[#L + 1] = "Story arcs:"
    for _, a in ipairs(sum.arcs) do
        L[#L + 1] = string.format("  %s: %s%s", a.name, a.status, a.outcome and (" [" .. a.outcome .. "]") or "")
    end
    L[#L + 1] = ""
    L[#L + 1] = string.format("Achievements: %d of %d", #sum.achievements.earned, sum.achievements.total)
    for _, a in ipairs(sum.achievements.earned) do
        L[#L + 1] = "  * " .. a.name .. (a.desc and (" - " .. a.desc) or "")
    end
    return table.concat(L, "\n")
end

-- ── Per-frame ────────────────────────────────────────────────────────────────
STATS._ach_next = 0
STATS.update = _guard("update", function(delta)
    local s = _s(); if not s then return end
    if not STATS._s0 then   -- first frame of this run: snapshot for "this session" deltas
        s.sessions = s.sessions + 1
        STATS._s0 = {play_seconds = s.play_seconds, credits_earned = s.credits_earned,
                     jobs_completed = _sum(s.jobs.completed), regions = _count(s.regions),
                     achievements = _count(RT.campaign.achievements)}
    end
    s.play_seconds = s.play_seconds + delta
    _pollCredits()
    local now = getScenarioTime()
    if now >= STATS._ach_next then
        STATS._ach_next = now + 5
        for _, id in ipairs(ACH.order) do
            local def = ACH.defs[id]
            if def.check and not ACH.has(id) then
                local ok, res = pcall(def.check, s)
                if ok and res then ACH.award(id) end
            end
        end
    end
end)

-- ── Initial achievements (derived from tracked stats and arc results) ────────
local function _typesCompleted(s)
    local n = 0
    for _, v in pairs(s.jobs.completed) do if v > 0 then n = n + 1 end end
    return n
end

ACH.define{id = "first_contract", name = "First Contract", category = "jobs",
    desc = "Complete your first job.",
    check = function(s) return _sum(s.jobs.completed) >= 1 end}
ACH.define{id = "steady_work", name = "Steady Work", category = "jobs",
    desc = "Complete 10 jobs.",
    check = function(s) return _sum(s.jobs.completed) >= 10 end}
ACH.define{id = "old_hand", name = "Old Hand", category = "jobs",
    desc = "Complete 50 jobs.",
    check = function(s) return _sum(s.jobs.completed) >= 50 end}
ACH.define{id = "jack_of_all_trades", name = "Jack of All Trades", category = "jobs",
    desc = "Complete every type of job at least once.",
    check = function(s)
        local total = JOBS and JOBS._registry and _count(JOBS._registry) or 0
        return total > 0 and _typesCompleted(s) >= total
    end}
ACH.define{id = "pay_day", name = "Pay Day", category = "money",
    desc = "Earn 1,000 credits in total.",
    check = function(s) return s.credits_earned >= 1000 end}
ACH.define{id = "deep_pockets", name = "Deep Pockets", category = "money",
    desc = "Earn 5,000 credits in total.",
    check = function(s) return s.credits_earned >= 5000 end}
ACH.define{id = "cartographer", name = "Cartographer", category = "exploration",
    desc = "Visit every region of the Drift.",
    check = function(s)
        local total = VERSE and VERSE.REGIONS and #VERSE.REGIONS or 0
        return total > 0 and _count(s.regions) >= total
    end}
ACH.define{id = "into_the_teeth", name = "Into the Teeth", category = "exploration",
    desc = "Enter a deadly region.",
    check = function(s)
        if not (VERSE and VERSE.REGIONS) then return false end
        for _, r in ipairs(VERSE.REGIONS) do
            if (r.danger or 0) >= 3 and s.regions[r.name] then return true end
        end
        return false
    end}
ACH.define{id = "fixers_friend", name = "The Fixer's Friend", category = "story", hidden = true,
    desc = "Finish the Rezkov arc.",
    check = function(s) return s.arcs.rezkov ~= nil and (s.arcs.rezkov.completed or 0) > 0 end}
ACH.define{id = "first_on_the_scene", name = "First on the Scene", category = "story", hidden = true,
    desc = "Rescue the lifeboat survivors in the Boneyard.",
    check = function(s) return RT.flag and RT.flag("boneyard_buoy_found") and true or false end}
ACH.define{id = "boneyard_breach", name = "Breaching the Annex", category = "story", hidden = true,
    desc = "Finish the Boneyard arc.",
    check = function(s) return s.arcs.boneyard ~= nil and (s.arcs.boneyard.completed or 0) > 0 end}
