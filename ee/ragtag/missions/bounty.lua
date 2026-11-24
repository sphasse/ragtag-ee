-- ee/ragtag/missions/bounty.lua
-- The Bounty: a one-off money job. Pell Ashby, the Rimward Haulers Guild's bookkeeper, ran with the
-- guild's payroll; the guild posts a bounty at Dustmote Salvage: alive, no exceptions. Ashby hides in
-- the Deep Shroud aboard the Long Odds with two hired escorts. GM guide: docs/GM_BOUNTY_MISSION.md
--
-- Structure: init -> hook -> hunt -> deliver -> done ("bounty" | "released" | "lost")
--   hook     seed rumors at Independent ports; docked at Dustmote Salvage, Thresh's [SPECIAL] reply:
--            the notice and the trail (two pages).
--   hunt     Long Odds and two escorts somewhere in the Deep Shroud (nebula: probes and Science).
--            Within FOUND_R (or scanned) they are found: Long Odds runs, the escorts attack. Long Odds
--            cannot be destroyed: impulse and rear shield both down at once (HACKED_AT hacked or under
--            HEALTH_AT health) disables it; dock to take Ashby. The escorts can be destroyed.
--   deliver  Ashby's offer (crypto credits, the keys in his head). Dock at Dustmote: the bounty
--            (PAY_BOUNTY, Independent +REP_BOUNTY). Dock at Saint Brennan's Mission: his money
--            (PAY_RELEASE, Independent REP_RELEASE).
--   lost     the Magpie lost with Ashby aboard.

local M = {}
M.id             = "bounty"
M.name           = "The Bounty"
M.repeatable     = false
M.locks_jobs     = false
M.auto_start     = true
M.start_phase    = "init"
M.no_auto_cancel = true

local U = 1000

-- ── Tuning ──────────────────────────────────────────────────────────────────
M.UPGRADES_MIN  = 1000   -- boarding jobs unlocked
M.FOUND_R       = 8 * U  -- this close (or a full scan) and Long Odds is found
M.RUN_SPEED     = 55     -- Long Odds' impulse once found (a stock Light Freighter does 60)
M.RUN_LEG       = 20 * U -- how far each leg of its run goes
M.LONG_HULL     = 300
M.LONG_SHIELDS  = 150
M.HACKED_AT     = 0.90   -- Long Odds disabled: impulse and rear shield each this hacked...
M.HEALTH_AT     = 0.10   -- ...or under this health, both at once
M.ESCORT_GIVEUP = 20 * U -- escorts gone this far from the Magpie after the capture are removed
M.PAY_BOUNTY    = 3000
M.PAY_RELEASE   = 4500
M.REP_BOUNTY    = 100
M.REP_RELEASE   = -150

local _DUSTMOTE, _BRENNAN = "Dustmote Salvage", "Saint Brennan's Mission"
local _LONG_CS = "Long Odds"
local _ESCORT_CS = {"Second Thoughts", "Paid in Full"}
-- Where Long Odds hides: inside the Deep Shroud, well clear of the black hole, the rift and the idle
-- Unknown ships (universe units).
local _HIDES = {{145, -20}, {150, -40}, {136, -30}}
local _SHROUD = {x = 156, y = -29, r = 42}

function M.init_state()
    return {
        long     = nil,   -- Long Odds (the entity)
        escorts  = {},
        hide_x   = nil, hide_y = nil,
        found    = false,
        disabled = false,
        leg_x    = nil, leg_y = nil, leg_at = 0,
        force_disable = false,
    }
end

-- ── Small helpers ───────────────────────────────────────────────────────────

local function _active(phase)
    return MISSIONS._status["bounty"] == "active" and (phase == nil or MISSIONS._cur_phase["bounty"] == phase)
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

local function _down(ship, sys) return ARC.systemDown(ship, sys, M.HACKED_AT, M.HEALTH_AT) end
M.systemDown = _down

-- A random point in the Deep Shroud, RUN_LEG from (x, y), kept inside the nebula.
local function _nextLeg(x, y)
    for _ = 1, 12 do
        local a = math.random() * 2 * math.pi
        local nx, ny = x + math.cos(a) * M.RUN_LEG, y + math.sin(a) * M.RUN_LEG
        if ARC.dist(nx, ny, _SHROUD.x * U, _SHROUD.y * U) < (_SHROUD.r - 10) * U then return nx, ny end
    end
    return _SHROUD.x * U - 10 * U, _SHROUD.y * U
end

-- ── Long Odds and its escorts ───────────────────────────────────────────────

local function _spawn(st)
    if RT.valid(st.long) then return end
    if not st.hide_x then
        local h = _HIDES[math.random(#_HIDES)]
        st.hide_x = (h[1] + (math.random() * 6 - 3)) * U
        st.hide_y = (h[2] + (math.random() * 6 - 3)) * U
    end
    local x, y = st.hide_x, st.hide_y
    local l = CpuShip():setTemplate("Phobos T3"):setFaction("Fugitive")
    l:setCallSign(_LONG_CS):setPosition(x, y)
    l:setHullMax(M.LONG_HULL):setHull(M.LONG_HULL)
    l:setShieldsMax(M.LONG_SHIELDS, M.LONG_SHIELDS):setShields(M.LONG_SHIELDS, M.LONG_SHIELDS)
    l:setWarpDrive(false):setJumpDrive(false)
    l:setImpulseMaxSpeed(M.RUN_SPEED, M.RUN_SPEED / 2)
    l:setCanBeDestroyed(false)   -- the contract says alive
    l:setScanningParameters(1, 2)
    l:setDescriptions("A fast trader, transponder spoofed.",
        "Long Odds: a modified trader with military shields and a fugitive aboard. Registered to the Rimward Haulers Guild's bookkeeper, Pell Ashby.")
    l:orderIdle()
    l:setCommsScript(""):setCommsFunction(ARC.comms(function(src, tgt)
        if st.disabled then
            setCommsMessage('"All right. All right. I\'m not armed. Come aboard."')
        else
            setCommsMessage('"Whoever you are, I\'m not going back. Turn around."')
        end
    end, '"Not now."'))
    ARC.register(l)
    st.long = l

    st.escorts = {}
    for i, cs in ipairs(_ESCORT_CS) do
        local e = CpuShip():setTemplate("Adder MK5"):setFaction("Fugitive")
        e:setCallSign(cs)
        e:setPosition(x + (i == 1 and 1500 or -1500), y + 800)
        e:setWarpDrive(false):setJumpDrive(false)
        e:setScanningParameters(1, 1)
        e:setDescriptions("A light gunship.", "A hired gun riding with the Long Odds.")
        e:orderDefendTarget(l)
        ARC.register(e)
        st.escorts[#st.escorts + 1] = e
    end
end

local function _despawn(st)
    ARC.kill(st.long); st.long = nil
    ARC.kill(st.escorts); st.escorts = {}
end

local function _found(st)
    if st.found then return end
    st.found = true
    RT.flag("bounty_found", true)
    local p = ARC.player()
    ARC.log("[Bounty] That's the Long Odds. Ashby's running, and his escorts are turning on us.", "#FFAA40")
    RT.setObjective("Disable Long Odds", true, "bounty")
    for _, e in ipairs(st.escorts) do
        if RT.valid(e) and p then e:orderAttack(p) end
    end
    if RT.valid(st.long) then
        ARC.hail(st.long, '"Whoever you are, I\'m not going back. Turn around."', _LONG_CS)
    end
    st.leg_at = 0
end

local function _disable(st)
    local l = st.long
    if st.disabled or not RT.valid(l) then return end
    st.disabled = true
    l:setImpulseMaxSpeed(0, 0)
    l:orderIdle()
    l:setFaction("Independent")   -- nobody's enemy now: it can be docked with
    pcall(function() l.components.docking_bay = {external_dock_classes = {"Frigate"}} end)
    RT.setObjective("Dock with Long Odds", true, "bounty")
    ARC.log("[Bounty] Long Odds is dead in space, engines and rear shield down. Dock with it to take Ashby.", "#FFCC80")
    ARC.hail(l, '"All right. All right. I\'m not armed. Come aboard."', _LONG_CS)
    -- The escorts were paid to fight, not to die.
    for _, e in ipairs(st.escorts) do
        if RT.valid(e) then
            local ex, ey = e:getPosition()
            e:orderFlyTowards(ex + 40 * U, ey - 40 * U)
        end
    end
end

local function _tickHunt(st, now)
    local p = ARC.player()
    local l = st.long
    if not RT.valid(l) then return end
    if st.force_disable then st.force_disable = false; if not st.found then _found(st) end; _disable(st) end
    if not st.found and p then
        local ok, scanned = pcall(function() return l:isFullyScannedBy(p) end)
        if RT.dist(l, p) <= M.FOUND_R or (ok and scanned) then _found(st) end
    end
    if st.found and not st.disabled then
        -- It runs: leg after leg across the nebula.
        local lx, ly = l:getPosition()
        if not st.leg_x or now >= st.leg_at or ARC.dist(lx, ly, st.leg_x, st.leg_y) < 2 * U then
            st.leg_x, st.leg_y = _nextLeg(lx, ly)
            st.leg_at = now + 90
            l:orderFlyTowards(st.leg_x, st.leg_y)
        end
        if _down(l, "impulse") and _down(l, "rearshield") then _disable(st) end
    end
    if st.disabled and p and p:isDocked(l) then
        RT.flag("bounty_captured", true)
        ARC.log("[Bounty] Ashby is aboard, in the brig. He wants to talk.", "#80FF80")
        MISSIONS.phase("bounty", "deliver")
    end
end

-- ── Rumors ──────────────────────────────────────────────────────────────────

local _NOTICE_RUMOR = "There's a guild bounty posted at Dustmote Salvage. Some bookkeeper ran off with a payroll. Alive only, they say."
local _SEEDS = {
    "A ship went into the Deep Shroud last week with two gunships riding along. Nobody takes an escort in there unless they're hiding.",
    "The Rimward Haulers Guild is paying its crews late again. Their haulers say the books never added up.",
}

local function _seedRumors()
    RUMORS.removeCategory("BOUNTY_SEED")
    if RT.flag("bounty_briefed") then return end
    for _, text in ipairs(_SEEDS) do
        RUMORS.add({text = text, priority = 3, faction = "Independent", category = "BOUNTY_SEED"})
    end
    RUMORS.add({text = _NOTICE_RUMOR, priority = 3, faction = "Independent", category = "BOUNTY_SEED",
        on_heard = function()
            if _active("hook") then RT.setObjective("Bounty at Dustmote", false, "bounty") end
        end})
end

-- ── The notice (Thresh, at Dustmote) ────────────────────────────────────────

local function _hideSector(st)
    local ok, s = pcall(getSectorName, st.hide_x or _SHROUD.x * U, st.hide_y or _SHROUD.y * U)
    return ok and s or "the middle of it"
end

local function _accept()
    RT.flag("bounty_briefed", true)
    MISSIONS.phase("bounty", "hunt")
end

local function _notice(st)
    if not st.hide_x then
        local h = _HIDES[math.random(#_HIDES)]
        st.hide_x = (h[1] + (math.random() * 6 - 3)) * U
        st.hide_y = (h[2] + (math.random() * 6 - 3)) * U
    end
    ARC.meet("bounty", "thresh_profile", "Thresh")
    setCommsMessage('Thresh slides a notice across the counter.\n\nBOUNTY: PELL ASHBY, bookkeeper, Rimward Haulers Guild. Ran with the guild payroll. '
        .. _cr(M.PAY_BOUNTY) .. ' credits. ALIVE. NO EXCEPTIONS.\n\n"The guild posted it here because nobody else would take their money," Thresh says. '
        .. '"That should tell you something about the guild."')
    addCommsReply("Go on.", function()
        setCommsMessage('"His ship\'s the Long Odds. He bought two hired guns on the way out, and the three of them went into the Deep Shroud. '
            .. 'Last ping was near ' .. _hideSector(st) .. '. Sensors are no good in there: you\'ll want probes, and your Science officer awake.\n\n'
            .. 'His ship\'s tougher than it looks. Take out its engines and its rear shield together and it\'ll stop. Then dock and collect him. '
            .. 'Bring him here breathing. The guild wants him alive. They didn\'t say in what condition."')
        addCommsReply("We'll take it.", function()
            _accept()
            setCommsMessage('"Good hunting."')
        end)
        addCommsReply("Not right now.", function()
            setCommsMessage('"The notice stays up. Nobody else wants it."')
        end)
    end)
end

-- ── Ashby's offer, and the two drops ────────────────────────────────────────

local _OFFER = '"This is Pell Ashby. Yes, I took the payroll. The guild\'s been skimming its own crews\' pay for years, and I kept the books, so I know exactly how much.\n\n'
    .. 'I moved it all into crypto credits and memorized the keys. They\'re in my head, nowhere else. The Independents can probably beat it out of me, '
    .. 'but none of us want to see that happen...\n\n'
    .. 'Drop me at Saint Brennan\'s Mission instead. The order will take me in, and ' .. _cr(M.PAY_RELEASE) .. ' of those credits are yours."'

local function _offer(st)
    if RT.flag("bounty_offered") then return end
    RT.flag("bounty_offered", true)
    if not RT.voice.exists("bounty_ashby") then
        RT.voice.create("bounty_ashby", {name = "Pell Ashby", tree = {text = _OFFER,
            replies = {{label = "We'll think about it.", say = '"Saint Brennan\'s Mission. The order won\'t ask questions. Neither will I."'}}}})
    end
    if not ARC.hail(RT.voice.get("bounty_ashby"), _OFFER, "Pell Ashby") then ARC.log("[Pell Ashby] " .. _OFFER, "#C0C0FF") end
    M._addAshbyEntry()
end

local function _finish(outcome, pay, rep, why)
    ARC.once("bounty_rewarded", function()
        RT.addCredits(pay, why)
        RT.addReputation("Independent", rep, why)
    end)
    RT.flag("bounty_arc_done", outcome)
    MISSIONS.phase("bounty", "done")
end

local function _dustmoteHook(src, tgt, info)
    if not ARC.docked(src, tgt) then return end
    if MISSIONS._status["bounty"] ~= "active" then return end
    local phase = MISSIONS._cur_phase["bounty"]
    local st = MISSIONS._state["bounty"]
    if phase == "hook" and st then
        addCommsReply("[SPECIAL] Bounty: Pell Ashby, alive", function() _notice(st) end)
    elseif phase == "hunt" and st then
        addCommsReply("Ask Thresh about Ashby", function()
            setCommsMessage('"The Deep Shroud, near ' .. _hideSector(st) .. '. Probes, and patience. And don\'t shoot him to pieces: no pay for a corpse."')
        end)
    elseif phase == "deliver" then
        addCommsReply("Hand Ashby to the guild", function()
            setCommsMessage('The guild\'s agent takes Ashby off your hands, none too gently. Thresh counts out the bounty.\n\n"'
                .. _cr(M.PAY_BOUNTY) .. '. Alive, as ordered. What they do with him now is their business."')
            _finish("bounty", M.PAY_BOUNTY, M.REP_BOUNTY, "The Bounty: Pell Ashby handed to the guild")
        end)
    end
end

local function _brennanHook(src, tgt, info)
    if not ARC.docked(src, tgt) or not _active("deliver") then return end
    addCommsReply("Let Ashby off here", function()
        setCommsMessage('Two sisters of the order meet Ashby at the airlock and take him in without a word. A moment later a transfer lands: '
            .. _cr(M.PAY_RELEASE) .. ' credits, from nowhere in particular.\n\n"Thank you," Ashby says. "Spend it on something good."')
        ARC.log("[Bounty] Word will get back to the guild. They won't thank you for it.", "#FFAA40")
        _finish("released", M.PAY_RELEASE, M.REP_RELEASE, "The Bounty: let Pell Ashby go at Saint Brennan's")
    end)
end

-- The Magpie lost with Ashby aboard.
RT.on(function(ev)
    if ev.type ~= "ship_lost" or not ev.data.primary or not _active("deliver") then return end
    RT.flag("bounty_arc_done", "lost")
    MISSIONS.phase("bounty", "done")
end)

-- ── Science database ────────────────────────────────────────────────────────

local function _noticeText()
    return table.concat({
        "BOUNTY: PELL ASHBY",
        "Bookkeeper, Rimward Haulers Guild. Ran with the guild payroll. " .. _cr(M.PAY_BOUNTY) .. " credits, posted at Dustmote Salvage. ALIVE. NO EXCEPTIONS.",
        "",
        "WHERE",
        "The Deep Shroud, the biggest nebula in the Drift: long-range sensors are useless inside. Launch probes and scan.",
        "",
        "LONG ODDS",
        "A modified trader with military shields, tougher than it looks, running with two hired gunships. Once it is found it runs and the escorts fight. It cannot be destroyed without losing the bounty: take its impulse engines and its rear shield down at the same time (each 90% hacked on Relay's hacking screen, or under 10% health on Science's scan), then dock with it.",
        "",
        "THE ESCORTS",
        "Two light gunships, Second Thoughts and Paid in Full. Hired, and expendable.",
    }, "\n")
end

local function _addNoticeEntry()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["bounty_notice"] then return end
    SCIDB._entries["bounty_notice"] = SCIDB.addEntry("lore", "Bounty: Pell Ashby", _noticeText(),
        {["Wanted"] = "Alive", ["Reward"] = _cr(M.PAY_BOUNTY) .. " cr", ["Last seen"] = "The Deep Shroud"})
end

function M._addAshbyEntry()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["bounty_ashby"] then return end
    SCIDB._entries["bounty_ashby"] = SCIDB.addEntry("lore", "Pell Ashby's side", table.concat({
        "WHAT HE SAYS",
        "The Rimward Haulers Guild has been skimming its own crews' pay for years. Ashby kept the books, so he knows by how much, and he took the payroll.",
        "",
        "THE MONEY",
        "Moved into crypto credits. The keys are memorized: in his head and nowhere else. The guild can only get them out of him the hard way.",
        "",
        "THE CHOICE",
        "Hand him to the guild at Dustmote Salvage: " .. _cr(M.PAY_BOUNTY) .. " cr, and the Independents think well of you. Or drop him at Saint Brennan's Mission, where the order will shelter him: " .. _cr(M.PAY_RELEASE) .. " cr of his money, and the guild hears about it.",
    }, "\n"), {["Offer"] = _cr(M.PAY_RELEASE) .. " cr", ["Drop"] = "Saint Brennan's"})
end

-- ── Cleanup / resolve ───────────────────────────────────────────────────────

local function _clearWorld(st)
    _despawn(st)
    if RT.voice.exists("bounty_ashby") then RT.voice.destroy("bounty_ashby") end
    RUMORS.removeCategory("BOUNTY_SEED")
    RUMORS.removeCategory("BOUNTY_DONE")
    RT.clearObjective("bounty")
end

function M.resolve(st)
    RUMORS.removeCategory("BOUNTY_SEED")
    RT.clearObjective("bounty")
    if RT.voice.exists("bounty_ashby") then RT.voice.destroy("bounty_ashby") end
    if RT.flag("bounty_arc_done") == "lost" then
        ARC.log("[Bounty] Ashby went down with the ship, and the guild's money with him.", "#FF8080")
    end
    -- The empty Long Odds and anything left of its escorts leave the board a little later.
    RT.after(120, function()
        local cur = MISSIONS._state["bounty"]
        if cur then _despawn(cur) end
    end, "bounty_cleanup")
    AFTERMATH.sync()
end

function M.on_cancel(st)
    RT.cancelTimer("bounty_cleanup")
    _clearWorld(st)
end

-- ── Phases ──────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        ARC.stationHook(_DUSTMOTE, _dustmoteHook)
        ARC.stationHook(_BRENNAN, _brennanHook)
        ARC.route("bounty", {
            {"bounty_arc_done", "done"},
            {"bounty_captured", "deliver"},
            {"bounty_briefed", "hunt"},     -- a hunt cut short by the session's end starts over
        }, "hook")
    end,
}

M.phases.hook = {
    enter = function(st) _seedRumors() end,
    exit = function(st) RUMORS.removeCategory("BOUNTY_SEED") end,
}

M.phases.hunt = {
    enter = function(st)
        _addNoticeEntry()
        _spawn(st)
        RT.setObjective("Find Long Odds", true, "bounty")
    end,
    update = function(st, delta, now) _tickHunt(st, now) end,
}

M.phases.deliver = {
    enter = function(st)
        RT.setObjective("Deliver Ashby", true, "bounty")
        RT.after(3, function() if _active("deliver") then _offer(MISSIONS._state["bounty"]) end end, "bounty_offer")
    end,
    update = function(st, delta, now)
        -- The escorts that fled, and the empty Long Odds, leave once the Magpie is well away.
        local p = ARC.player()
        for i, e in ipairs(st.escorts or {}) do
            if RT.valid(e) and (not p or RT.dist(e, p) > M.ESCORT_GIVEUP) then ARC.kill(e); st.escorts[i] = nil end
        end
        if RT.valid(st.long) and (not p or RT.dist(st.long, p) > 10 * U) then ARC.kill(st.long); st.long = nil end
    end,
    exit = function(st) RT.cancelTimer("bounty_offer") end,
}

-- ── Trigger: Rezkov over and boarding jobs unlocked ─────────────────────────

M.triggers = {
    upgrades_min   = M.UPGRADES_MIN,
    not_flagged    = {"bounty_arc_done"},
    requires       = function() return (RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined")) and true or false end,
    requires_label = "Rezkov over (or declined)",
}

M.phase_order = {"init", "hook", "hunt", "deliver"}

-- ── GM console ──────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"bounty_"}

M.flags = {
    bounty_briefed   = "took the bounty from Thresh (the notice Science DB entry)",
    bounty_found     = "found Long Odds in the Deep Shroud",
    bounty_captured  = "Ashby is aboard the Magpie",
    bounty_offered   = "Ashby made his offer (his side of the story Science DB entry)",
    bounty_rewarded  = "paid (once)",
    bounty_arc_done  = 'outcome: "bounty" (handed to the guild at Dustmote) | "released" (dropped at Saint Brennan\'s) | "lost" (the Magpie lost with him aboard)',
    ["bounty_met_*"] = "Science DB profile met in this arc (thresh), set by ARC.meet",
}
M.reads = {"rezkov_arc_done", "rezkov_declined"}

M.gm_state_fn = function()
    local st = MISSIONS._state["bounty"] or {}
    local ph = MISSIONS._cur_phase["bounty"]
    if MISSIONS._status["bounty"] == "done" then return "Complete (" .. tostring(RT.flag("bounty_arc_done")) .. ")" end
    if ph == "hunt" then
        return (st.disabled and "Long Odds disabled" or (st.found and "Long Odds running" or "Hiding near " .. _hideSector(st)))
            .. string.format(", %d escort(s)", #ARC.alive(st.escorts or {}))
    end
    return ph or MISSIONS._status["bounty"]
end

M.gm_reset = function(st, target)
    RT.cancelTimer("bounty_cleanup")
    RT.cancelTimer("bounty_offer")
    _clearWorld(st)
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("bounty", function(name) return false end)
end

M.completed = {
    hook = function(st)
        RT.flag("bounty_briefed", true)
        ARC.meet("bounty", "thresh_profile", "Thresh")
    end,
    hunt = function(st)
        RT.flag("bounty_found", true)
        RT.flag("bounty_captured", true)
    end,
}

local _jump = ARC.jumper("bounty")

M.gm_states = {
    {key = "hook",    label = "→ Hook",    fn = _jump("hook")},
    {key = "hunt",    label = "→ Hunt",    fn = _jump("hunt")},
    {key = "deliver", label = "→ Deliver", fn = _jump("deliver")},
    {key = "done_bounty",   label = "→ Done: Bounty",   fn = _jump("done", function() RT.flag("bounty_arc_done", "bounty") end)},
    {key = "done_released", label = "→ Done: Released", fn = _jump("done", function() RT.flag("bounty_arc_done", "released") end)},
    {key = "done_lost",     label = "→ Done: Lost",     fn = _jump("done", function() RT.flag("bounty_arc_done", "lost") end)},
}

M.gm_actions = {
    ARC.travel("Dustmote", {"hook", "deliver"}, _DUSTMOTE),
    ARC.travel("Long Odds", {"hunt"}, function(st) return st.long end),
    ARC.travel("Brennan's", {"deliver"}, _BRENNAN),
    {label = "Disable Long Odds", phases = {"hunt"}, fn = function(st)
        st.force_disable = true
    end},
    {label = "Kill escorts", phases = {"hunt", "deliver"}, fn = function(st)
        ARC.kill(st.escorts); st.escorts = {}
    end},
}

-- The Science DB follows the flags (SCIDB.sync at session start and after every GM jump).
if SCIDB and SCIDB.rule then
    SCIDB.rule("bounty_notice", {want = function() return RT.flag("bounty_briefed") end, add = function() _addNoticeEntry() end})
    SCIDB.rule("bounty_ashby", {want = function() return RT.flag("bounty_offered") end, add = function() M._addAshbyEntry() end})
end

if ACH and ACH.define then
    ACH.define{id = "bring_him_in", name = "Bring Him In", category = "story", hidden = true,
        desc = "Hand Pell Ashby to the guild, alive.",
        check = function(s) return RT.flag("bounty_arc_done") == "bounty" end}
    ACH.define{id = "everyone_has_a_price", name = "Everyone Has a Price", category = "story", hidden = true,
        desc = "Take Pell Ashby's offer and let him go at Saint Brennan's.",
        check = function(s) return RT.flag("bounty_arc_done") == "released" end}
end

MISSIONS.register(M)
