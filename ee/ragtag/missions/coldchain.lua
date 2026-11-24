-- ee/ragtag/missions/coldchain.lua
-- Cold Chain: a one-off money job. A fever is spreading through Tamsin Hollow; the cure is in the
-- Concord's medical depot at Ostia Highport, and the Concord won't release it to an Independent port.
-- Dr. Nell Varga pays the crew to take it. GM guide: docs/GM_COLD_CHAIN_MISSION.md
--
-- Structure: init -> hook -> approach -> run -> done ("delivered" | "spoiled" | "lost")
--   hook      seed rumors at Independent ports (the fever, the cure, Varga asking for help); docked at
--             Tamsin Hollow, Varga's request is a [SPECIAL] reply: a three-page brief.
--   approach  fly to Ostia Highport, dock, and Relay hacks the port itself to HACK_AT (a station's
--             shields are hackable systems). Only a hack made while docked counts: away from the dock
--             the port's hack levels are reset. The serum is loaded. Who saw it is decided then:
--             a fake transponder code running = "an unknown freighter" (no standing loss, no chase);
--             otherwise the Magpie is identified (Concord CONCORD_SEEN and a Concord chase until it
--             is out of Concord space).
--   run       SPOIL_TIME s on Relay ("Serum good for 14:59"); deliver at Tamsin Hollow: in time
--             PAY_FRESH cr and Independent +REP_FRESH; spoiled PAY_SPOILED cr.
--   lost      the Magpie lost with the serum aboard.

local M = {}
M.id             = "coldchain"
M.name           = "Cold Chain"
M.repeatable     = false
M.locks_jobs     = false
M.auto_start     = true
M.start_phase    = "init"
M.no_auto_cancel = true

-- ── Tuning ──────────────────────────────────────────────────────────────────
M.JOBS_AFTER_FUNDED = 3      -- board jobs by the primary ship after the Hob Works was funded
M.HACK_AT           = 0.75   -- the port's hack level (Relay's "hacked 75%") that loads the serum
M.SPOIL_TIME        = 900    -- s the serum stays good once loaded
M.PAY_FRESH         = 3000
M.PAY_SPOILED       = 1000
M.REP_FRESH         = 150    -- Independent standing for an in-time delivery
M.CONCORD_SEEN      = -300   -- Concord standing when the Magpie is identified
M.CHASE_COOLDOWN    = 30     -- s between Concord patrols while hunted
M.CHASE_MAX         = 4

local _TAMSIN, _OSTIA = "Tamsin Hollow", "Ostia Highport"
local _CONCORD_ZONES = {"the Concord Core", "the Arbiter Line", "the Escrow Marches"}

function M.init_state()
    return {
        spoil_at   = nil,   -- scenario time the serum spoils
        spoiled    = false,
        chase      = nil,   -- the Concord is hunting the Magpie (identified at the depot)
        timer_text = nil,
        force_load = false, -- GM "Complete hack"
    }
end

-- ── Small helpers ───────────────────────────────────────────────────────────

local function _active(phase)
    return MISSIONS._status["coldchain"] == "active" and (phase == nil or MISSIONS._cur_phase["coldchain"] == phase)
end

local function _mmss(secs)
    secs = math.max(0, math.floor(secs))
    return string.format("%d:%02d", secs // 60, secs % 60)
end

local function _cr(n)
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then break end
    end
    return s
end

-- The spoil timer on Relay and Operations.
local function _timerLine(st, text)
    if st.timer_text == text then return end
    st.timer_text = text
    ARC.withPlayer(function(p)
        for _, pair in ipairs({{"relay", "coldchain_timer"}, {"operations", "coldchain_timer_ops"}}) do
            if text then
                pcall(function() p:addCustomInfo(pair[1], pair[2], text, 150) end)
            else
                pcall(function() p:removeCustom(pair[2]) end)
            end
        end
    end)
end

-- Ostia Highport's hack level: the higher of its two shield systems (what Relay can hack on a port).
local function _shields()
    local s = RT.find(_OSTIA)
    return RT.valid(s) and s.components.shields or nil
end
function M.portHack()
    local sh = _shields()
    if not sh then return 0 end
    return math.max(sh.front_hacked_level or 0, sh.rear_hacked_level or 0)
end
function M.setPortHack(v)
    local sh = _shields()
    if not sh then return end
    pcall(function() sh.front_hacked_level = v end)
    pcall(function() sh.rear_hacked_level = v end)
end

local function _dockedAtOstia()
    local p, s = ARC.player(), RT.find(_OSTIA)
    if not p or not RT.valid(s) then return false end
    local ok, d = pcall(function() return p:isDocked(s) end)
    return ok and d
end

-- ── The Concord chase (when the Magpie was identified) ───────────────────────

local function _endChase(st)
    for _, z in ipairs(_CONCORD_ZONES) do PROX.endChase(z) end
    if st then st.chase = nil end
end
local function _startChase(st)
    for _, z in ipairs(_CONCORD_ZONES) do PROX.chaseZone(z, M.CHASE_COOLDOWN, M.CHASE_MAX) end
    st.chase = true
end
local function _tickChase(st)
    if st.chase and not ARC.inRegions(_CONCORD_ZONES) then
        _endChase(st)
        ARC.log("[Cold Chain] Out of Concord space. The patrols are back to their usual rounds.", "#A0C0FF")
    end
end

-- ── Rumors ──────────────────────────────────────────────────────────────────

local _SEEDS = {
    "Tamsin Hollow's turning ships away. Some fever in the farm crews, and it's spreading.",
    "The Concord makes the cure for that Tamsin fever. Keeps it in the medical depot at Ostia, they say. Not for Rim folk.",
}
local _ASK = "Dr. Varga at Tamsin Hollow is asking for any crew with a fast ship and a flexible conscience. Says she can pay."

local function _seedRumors()
    RUMORS.removeCategory("COLDCHAIN_SEED")
    if RT.flag("coldchain_briefed") then return end
    for _, text in ipairs(_SEEDS) do
        RUMORS.add({text = text, priority = 3, faction = "Independent", category = "COLDCHAIN_SEED"})
    end
    RUMORS.add({text = _ASK, priority = 3, faction = "Independent", category = "COLDCHAIN_SEED",
        on_heard = function()
            if _active("hook") then RT.setObjective("Dr. Varga at Tamsin", false, "coldchain") end
        end})
end

-- ── The brief ───────────────────────────────────────────────────────────────

local _BRIEF = {
    '"You came. Good. I\'m Nell Varga; I keep this depot\'s crews alive, most years.\n\n'
        .. 'It\'s a fever out of the grain holds. Forty down, three dead, and it\'s spreading. There is a cure. The Concord makes it, '
        .. 'and keeps it in the medical depot at Ostia Highport. They won\'t release it to us: Independent ports must apply through '
        .. 'the proper channels. I applied. Six weeks ago."',
    '"The depot\'s release orders run on Ostia\'s own systems. Dock at Highport and have your Relay officer break into the port: '
        .. 'get it to 75% hacked while you\'re docked, and the depot sees an approved order and loads the serum onto your ship. '
        .. 'Hack it from anywhere else and their security just resets it."',
    '"Once it\'s aboard it\'s cold-packed for fifteen minutes. After that it starts to go. Bring it straight here.\n\n'
        .. 'And if they see who took it, they\'ll come for you. If they don\'t... well. I hear the Hob Works sells a very good '
        .. 'transponder code.\n\nI can pay 3,000 credits. It\'s every credit the depot has."',
}

local function _accept()
    RT.flag("coldchain_briefed", true)
    MISSIONS.phase("coldchain", "approach")
end

local function _brief()
    ARC.meet("coldchain", "varga_profile", "Dr. Nell Varga")
    setCommsMessage(_BRIEF[1])
    addCommsReply("Go on.", function()
        setCommsMessage(_BRIEF[2])
        addCommsReply("Go on.", function()
            setCommsMessage(_BRIEF[3])
            addCommsReply("We'll do it.", function()
                _accept()
                setCommsMessage('"Thank you. Ostia Highport. Go."')
            end)
            addCommsReply("Not right now.", function()
                setCommsMessage('"Then I\'ll keep asking. Don\'t take too long."')
            end)
        end)
    end)
end

-- ── The lift and the delivery ───────────────────────────────────────────────

local function _load(st)
    local p = ARC.player()
    local code = p and RT.transponderLeft(p) > 0
    RT.flag("coldchain_loaded", true)
    RT.flag("coldchain_seen", code and "code" or "seen")
    ARC.log(string.format("[Cold Chain] Release order approved. Ostia's depot is loading the serum: cold-packed for %d minutes.",
        M.SPOIL_TIME // 60), "#80FF80")
    if code then
        ARC.log("[Cold Chain] The depot logged an unknown freighter. Nobody knows it was the Magpie.", "#80FF80")
    else
        ARC.once("coldchain_penalized", function()
            RT.addReputation("Concord", M.CONCORD_SEEN, "Cold Chain: robbed Ostia's medical depot")
        end)
        ARC.log("[Cold Chain] Ostia's security has the Magpie's transponder on the release order. The Concord is hunting the Magpie. Get out of Concord space.", "#FF8080")
        _startChase(st)
    end
    M.setPortHack(0)
    MISSIONS.phase("coldchain", "run")
end

local function _deliver(st)
    local spoiled = st.spoiled
    local pay = spoiled and M.PAY_SPOILED or M.PAY_FRESH
    ARC.once("coldchain_rewarded", function()
        RT.addCredits(pay, "Cold Chain: serum delivered to Tamsin Hollow")
        if not spoiled then RT.addReputation("Independent", M.REP_FRESH, "Cold Chain: the Tamsin fever") end
    end)
    RT.flag("coldchain_arc_done", spoiled and "spoiled" or "delivered")
    if spoiled then
        setCommsMessage('"Varga opens the case and her face falls, then steadies. "Some of it\'s still good. Enough for the worst of them."\n\n'
            .. 'She sends what the depot can spare: ' .. _cr(pay) .. ' credits."')
    else
        setCommsMessage('"Varga opens the cold case right there on the dock. "It\'s good. It\'s all good." She is already calling for her orderlies.\n\n'
            .. '"' .. _cr(pay) .. ' credits, as promised. Every one of them well spent."')
    end
    MISSIONS.phase("coldchain", "done")
end

local function _tamsinHook(src, tgt, info)
    if not ARC.docked(src, tgt) then return end
    if MISSIONS._status["coldchain"] ~= "active" then return end
    local phase = MISSIONS._cur_phase["coldchain"]
    local st = MISSIONS._state["coldchain"]
    if phase == "hook" then
        addCommsReply("[SPECIAL] Dr. Varga's medical run", function() _brief() end)
    elseif phase == "approach" then
        addCommsReply("Talk to Dr. Varga", function()
            setCommsMessage('"Ostia Highport. Dock, hack the port to 75%, and the serum is yours. Every hour counts."')
        end)
    elseif phase == "run" and st then
        addCommsReply("We have the serum.", function() _deliver(st) end)
    end
end

-- The Magpie lost with the serum aboard.
RT.on(function(ev)
    if ev.type ~= "ship_lost" or not ev.data.primary or not _active("run") then return end
    RT.flag("coldchain_arc_done", "lost")
    MISSIONS.phase("coldchain", "done")
end)

-- ── Science database ────────────────────────────────────────────────────────

local function _feverText()
    return table.concat({
        "THE TAMSIN FEVER",
        "A fever out of Tamsin Hollow's grain holds. Forty of the farm crews down and three dead when Dr. Nell Varga asked for help, and spreading.",
        "",
        "THE CURE",
        "The Concord makes it and keeps it in the medical depot at Ostia Highport. It will not release it to Independent ports outside 'the proper channels'.",
        "",
        "VARGA'S PLAN",
        "The depot's release orders run on Ostia's own systems. Dock at Ostia Highport and hack the port to 75% (Relay's hacking screen) while docked: the depot loads the serum as an approved order. A hack from anywhere else is reset.",
        "",
        "WHO SEES IT",
        "With a fake transponder code running when the serum is loaded, the depot logs an unknown freighter. Without one, the Concord knows it was you, and comes looking until you are out of Concord space.",
        "",
        "THE COLD RUN",
        "Cold-packed for " .. (M.SPOIL_TIME // 60) .. " minutes. Delivered in time: " .. _cr(M.PAY_FRESH) .. " cr. Late, some of it is still good: " .. _cr(M.PAY_SPOILED) .. " cr.",
    }, "\n")
end

local function _addFeverEntry()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["coldchain_fever"] then return end
    SCIDB._entries["coldchain_fever"] = SCIDB.addEntry("lore", "The Tamsin fever", _feverText(),
        {["Where"] = "Tamsin Hollow", ["Cure held at"] = "Ostia Highport", ["Pay"] = _cr(M.PAY_FRESH) .. " cr"})
end

-- ── Cleanup / resolve ───────────────────────────────────────────────────────

local function _clearWorld(st)
    _timerLine(st, nil)
    _endChase(st)
    RUMORS.removeCategory("COLDCHAIN_SEED")
    RUMORS.removeCategory("COLDCHAIN_DONE")
    RT.clearObjective("coldchain")
end

function M.resolve(st)
    _timerLine(st, nil)
    RUMORS.removeCategory("COLDCHAIN_SEED")
    RT.clearObjective("coldchain")
    _endChase(st)   -- delivered means out of Concord space already; lost means nobody left to hunt
    if RT.flag("coldchain_arc_done") == "lost" then
        ARC.log("[Cold Chain] The serum went down with the ship. Tamsin Hollow is still waiting.", "#FF8080")
    end
    AFTERMATH.sync()
end

function M.on_cancel(st)
    _clearWorld(st)
end

-- ── Phases ──────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        ARC.stationHook(_TAMSIN, _tamsinHook)
        ARC.route("coldchain", {
            {"coldchain_arc_done", "done"},
            {"coldchain_loaded", "run"},       -- a new session: the serum is fresh again (not saved)
            {"coldchain_briefed", "approach"},
        }, "hook")
    end,
}

M.phases.hook = {
    enter = function(st) _seedRumors() end,
    exit = function(st) RUMORS.removeCategory("COLDCHAIN_SEED") end,
}

M.phases.approach = {
    enter = function(st)
        _addFeverEntry()
        M.setPortHack(0)
        RT.setObjective("Hack Ostia Highport", true, "coldchain")
    end,
    update = function(st, delta, now)
        if st.force_load then st.force_load = false; _load(st); return end
        if _dockedAtOstia() then
            if M.portHack() >= M.HACK_AT then _load(st) end
        elseif M.portHack() > 0 then
            M.setPortHack(0)   -- the depot only accepts a session from a docked ship
        end
    end,
}

M.phases.run = {
    enter = function(st)
        st.spoil_at = getScenarioTime() + M.SPOIL_TIME
        st.spoiled = false
        RT.setObjective("Serum to Tamsin", true, "coldchain")
    end,
    update = function(st, delta, now)
        _tickChase(st)
        local left = st.spoil_at - now
        if left > 0 then
            _timerLine(st, "Serum good for " .. _mmss(left))
        else
            if not st.spoiled then
                st.spoiled = true
                ARC.log("[Cold Chain] The cold pack has run out. The serum is warming: some of it will still be good.", "#FFAA40")
            end
            _timerLine(st, "Serum spoiling")
        end
    end,
    exit = function(st) _timerLine(st, nil) end,
}

-- ── Trigger: the Hob Works funded, then a few board jobs ────────────────────

local function _jobsDone()
    local rec = RT.shipRecord()
    return rec and rec.jobs_done or 0
end

-- Fake transponder codes on sale (the Hob Works funded). Keeps the job count's start
-- (coldchain_jobs_base): noted the first time this holds, forgotten if the GM rewinds it.
local function _available()
    local ok = RT.flag("hob_arc_done") == "funded"
    if not RT.campaign then return ok end
    local base = RT.flag("coldchain_jobs_base")
    if ok and base == nil then
        RT.flag("coldchain_jobs_base", _jobsDone())
    elseif not ok and base ~= nil then
        RT.clearFlag("coldchain_jobs_base")
    end
    return ok
end

M.triggers = {
    not_flagged    = {"coldchain_arc_done"},
    requires       = _available,
    requires_label = "The Hob Works funded (fake transponder codes on sale)",
    custom = function()
        if not _available() then return false end
        return _jobsDone() - (RT.flag("coldchain_jobs_base") or _jobsDone()) >= M.JOBS_AFTER_FUNDED
    end,
    custom_label = function()
        local base = RT.flag("coldchain_jobs_base")
        local n = base ~= nil and math.max(0, _jobsDone() - base) or 0
        local now = n >= M.JOBS_AFTER_FUNDED and (M.JOBS_AFTER_FUNDED .. "+") or tostring(n)
        return M.JOBS_AFTER_FUNDED .. " board jobs done by the primary ship since then  (now: " .. now .. ")"
    end,
}

M.phase_order = {"init", "hook", "approach", "run"}

-- ── GM console ──────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"coldchain_"}

M.flags = {
    coldchain_jobs_base  = "board jobs the primary ship had done when the Hob Works was funded (the hook waits for M.JOBS_AFTER_FUNDED more)",
    coldchain_briefed    = "took Dr. Varga's job (the Tamsin fever Science DB entry)",
    coldchain_loaded     = "the serum was loaded at Ostia Highport",
    coldchain_seen       = 'who the depot saw: "code" (an unknown freighter: a fake code was running) | "seen" (the Magpie)',
    coldchain_penalized  = "the Concord standing loss for being identified was applied (once)",
    coldchain_rewarded   = "Varga paid (once)",
    coldchain_arc_done   = 'outcome: "delivered" (in time) | "spoiled" (late) | "lost" (the Magpie lost with the serum)',
    ["coldchain_met_*"]  = "Science DB profile met in this arc (varga), set by ARC.meet",
}
M.reads = {"hob_arc_done"}
M.keep_flags = {"coldchain_jobs_base"}

M.gm_state_fn = function()
    local st = MISSIONS._state["coldchain"] or {}
    local ph = MISSIONS._cur_phase["coldchain"]
    if MISSIONS._status["coldchain"] == "done" then return "Complete (" .. tostring(RT.flag("coldchain_arc_done")) .. ")" end
    if ph == "approach" then
        return string.format("Port hack %d%%%s", math.floor(M.portHack() * 100 + 0.5), _dockedAtOstia() and " (docked)" or "")
    end
    if ph == "run" and st.spoil_at then
        local left = st.spoil_at - getScenarioTime()
        return (left > 0 and ("Serum good for " .. _mmss(left)) or "Serum spoiling") .. (st.chase and ", hunted" or "")
    end
    return ph or MISSIONS._status["coldchain"]
end

M.gm_reset = function(st, target)
    _clearWorld(st)
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("coldchain", function(name) return false end)
end

M.completed = {
    hook = function(st)
        RT.flag("coldchain_briefed", true)
        ARC.meet("coldchain", "varga_profile", "Dr. Nell Varga")
    end,
    approach = function(st)
        RT.flag("coldchain_loaded", true)
        RT.flag("coldchain_seen", "code")
    end,
}

local _jump = ARC.jumper("coldchain")

M.gm_states = {
    {key = "hook",     label = "→ Hook",     fn = _jump("hook")},
    {key = "approach", label = "→ Approach", fn = _jump("approach")},
    {key = "run",      label = "→ Run",      fn = _jump("run")},
    {key = "done_delivered", label = "→ Done: Delivered", fn = _jump("done", function() RT.flag("coldchain_arc_done", "delivered") end)},
    {key = "done_spoiled",   label = "→ Done: Spoiled",   fn = _jump("done", function() RT.flag("coldchain_arc_done", "spoiled") end)},
    {key = "done_lost",      label = "→ Done: Lost",      fn = _jump("done", function() RT.flag("coldchain_arc_done", "lost") end)},
}

M.gm_actions = {
    ARC.travel("Tamsin", {"hook", "run"}, _TAMSIN),
    ARC.travel("Ostia", {"approach"}, _OSTIA),
    {label = "Satisfy done jobs", phases = {"inactive"}, fn = function(st)
        if not _available() then
            addGMMessage("Cold Chain waits for the Hob Works to be funded (fake transponder codes on sale): the job count starts then.")
            return
        end
        RT.flag("coldchain_jobs_base", _jobsDone() - M.JOBS_AFTER_FUNDED)
    end},
    {label = "Complete hack", phases = {"approach"}, fn = function(st)
        st.force_load = true
    end},
    {label = "Spoil now", phases = {"run"}, fn = function(st)
        st.spoil_at = getScenarioTime()
    end},
}

-- The Science DB follows the flags (SCIDB.sync at session start and after every GM jump).
if SCIDB and SCIDB.rule then
    SCIDB.rule("coldchain_fever", {want = function() return RT.flag("coldchain_briefed") end, add = function() _addFeverEntry() end})
end

if ACH and ACH.define then
    ACH.define{id = "cold_chain", name = "Cold Chain", category = "story", hidden = true,
        desc = "Get the fever cure to Tamsin Hollow before it spoils.",
        check = function(s) return RT.flag("coldchain_arc_done") == "delivered" end}
    ACH.define{id = "no_fingerprints", name = "No Fingerprints", category = "story", hidden = true,
        desc = "Lift the serum from Ostia with a fake transponder code running.",
        check = function(s)
            local d = RT.flag("coldchain_arc_done")
            return RT.flag("coldchain_seen") == "code" and (d == "delivered" or d == "spoiled")
        end}
end

MISSIONS.register(M)
