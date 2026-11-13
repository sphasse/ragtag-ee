-- ee/ragtag/missions/ledger.lua
-- The Ledger Arc: carry the rogue accounting AI out of Concord space.
--
-- Trigger: Rezkov arc finished or declined, upgrade investment >= 800cr.
-- Structure: init -> hook -> meet -> relay_run -> carry -> done   (design notes: ledger.md)
--
--   hook       vague rumors send the crew to Dustmote; Thresh says the big guy wants to see them
--   meet       Rezkov's station is back in the nebula; docking gets the real briefing
--   relay_run  three AI fragments parked near Valcourt, Ostia and Waypoint Galen (fly into them)
--   carry      the assembled AI drains 5 energy/s; 60 s later a Concord Audit Service fleet
--              spawns ahead of the ship. Energy at zero kills the AI (lost). Dock at Rezkov's
--              station to deliver (full).
--
-- RT.flag keys (prefix "ledger_"):
--   thresh        Thresh passed on the meeting request (go to Rezkov)
--   accepted      Rezkov's briefing accepted
--   frag_1..3     fragment recovered
--   arc_done      "full" | "lost"
--   lost_reason   "power" | "surrender"
--   evidence      true when the ledger reached Rezkov (Maw finale input)
--   rewarded      pay-once guard for resolve
-- Reads: rezkov_ai_planted (crew planted the AI at Galen), rezkov_profile_known (met Rezkov).

local M = {}
M.id             = "ledger"
M.name           = "Ledger Arc"
M.repeatable     = false
M.locks_jobs     = false
M.auto_start     = true
M.start_phase    = "init"
M.no_auto_cancel = true

M.triggers = {
    upgrades_min = 800,
    not_flagged  = {"ledger_arc_done"},
    -- The AI was planted at Galen in the Rezkov arc; a crew that declined Rezkov hears that
    -- someone else planted it.
    custom       = function() return RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined") end,
    custom_label = "Rezkov arc finished or declined",
}

M.phase_order = {"init", "hook", "meet", "relay_run", "carry"}

local U = 1000

-- ── Tuning ──────────────────────────────────────────────────────────────────
local _DRAIN_PER_S   = 5     -- energy/s while carrying the AI (same as the Witness pod)
local _FLEET_DELAY   = 60    -- seconds after the AI's hail before the audit fleet arrives
local _FLEET_DIST    = 7 * U -- fleet spawn distance ahead of the ship
local _FLEET_SPREAD  = 35    -- degrees between fleet ships in the arc
local _LOSE_FLEET_R  = 25 * U   -- the fleet loses the crew beyond this range (then despawns)

-- Rezkov's station (same place as the Rezkov arc, verse ~(115, -72)) and its nebula.
local _RWX, _RWY = 115000, -72000
local _NEBULA_POS = {
    {112000, -69000}, {116000, -68000}, {120000, -70000}, {121000, -74000},
    {119000, -78000}, {114000, -78000}, {110000, -74000},
}

-- The three fragments, deep in Concord space.
local _FRAGS = {
    {n = 1, x = -172000, y =  -70000, where = "near Valcourt"},
    {n = 2, x = -128000, y = -120000, where = "near Ostia"},
    {n = 3, x =  -80000, y =  -62000, where = "near Waypoint Galen"},
}

function M.init_state()
    return {
        station   = nil,   -- Rezkov's station
        nebulas   = {},
        frags     = {},    -- n -> Artifact
        fleet     = {},    -- audit fleet ships
        fleet_due = nil,   -- scenario time the fleet arrives
        fleet_spawned = false,
        jammers   = {},    -- audit fleet combat jammers (PROX.tickCombatJammers)
        drain_on  = false,
        warned    = {},
    }
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function _dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function _firstPlayer()
    for _, p in ipairs(RT.players or {}) do
        if RT.valid(p) then return p end
    end
end

local function _addRecords(key, who)
    if SCIDB and SCIDB.addProfile then
        local ok, added = pcall(SCIDB.addProfile, key)
        if ok and added then
            RT.shipLog("[Ledger Arc] " .. who .. " personnel records added to our database.", "#80C0FF")
        end
    end
end

local function _fragCount()
    local n = 0
    for i = 1, #_FRAGS do if RT.flag("ledger_frag_" .. i) then n = n + 1 end end
    return n
end

local function _fragList()
    local lines = {}
    for _, f in ipairs(_FRAGS) do
        lines[#lines + 1] = string.format("- Fragment %d: grid %s, %s", f.n, JOBS.gridRef(f.x, f.y), f.where)
    end
    return table.concat(lines, "\n")
end

local function _relayObjective()
    RT.setObjective(string.format("Recover AI fragments (%d/3)", _fragCount()), true, "ledger")
end

local function _unlockLedger(quiet)
    if not (SCIDB and SCIDB._locked) then return end
    local L = SCIDB._locked["ledger_findings"]
    if not L or L.unlocked then return end
    SCIDB.unlock("ledger_findings")
    if not quiet then
        RT.shipLog("[Science] The Containment Ledger indexed. Database updated: Lore, The Containment Ledger.", "#00CCAA")
    end
end

-- ── Rezkov's station ────────────────────────────────────────────────────────

local _stationComms   -- forward

local function _spawnStation(st)
    if RT.valid(st.station) then return end
    for _, pos in ipairs(_NEBULA_POS) do
        st.nebulas[#st.nebulas + 1] = Nebula():setPosition(pos[1], pos[2])
    end
    local wp = CpuShip():setTemplate("Defense platform"):setFaction("Unknown")
    wp:setCallSign("Rezkov's station")
    wp:setPosition(_RWX, _RWY)
    wp:setCanBeDestroyed(false)
    wp:orderIdle()
    wp:setRotationMaxSpeed(0):setSpin(6)
    wp:setCommsScript(""):setCommsFunction(function(src, tgt) _stationComms(src, tgt) end)
    RT.register(wp)
    st.station = wp
end

local function _despawnStation(st)
    for _, n in ipairs(st.nebulas or {}) do
        if n and n:isValid() then n:destroy() end
    end
    st.nebulas = {}
    if RT.valid(st.station) then
        st.station:setCanBeDestroyed(true)
        st.station:destroy()
    end
    st.station = nil
    RT.named["Rezkov's station"] = nil
end

-- ── Fragments ───────────────────────────────────────────────────────────────

local function _onFragment(n)
    if RT.flag("ledger_frag_" .. n) then return end
    RT.flag("ledger_frag_" .. n, true)
    local st = MISSIONS._state["ledger"]
    if st then st.frags[n] = nil end
    local got = _fragCount()
    RT.shipLog(string.format("[Ledger Arc] AI fragment %d recovered (%d/3).", n, got), "#80FF80")
    if got >= 3 then
        if MISSIONS._status["ledger"] == "active" and MISSIONS._cur_phase["ledger"] == "relay_run" then
            MISSIONS.phase("ledger", "carry")
        end
    else
        _relayObjective()
    end
end

local function _spawnFrags(st)
    for _, f in ipairs(_FRAGS) do
        if not RT.flag("ledger_frag_" .. f.n) and not RT.valid(st.frags[f.n]) then
            local n = f.n
            local a = Artifact():setPosition(f.x, f.y):allowPickup(true)
            a:setCallSign("Data core")
            a:setDescriptions("Small object, cold.",
                "Encrypted data core, powered down to a trickle. The handshake matches the key Rezkov gave us. Fly into it to take it aboard.")
            a:setScanningParameters(1, 2)
            a:onPickUp(function() _onFragment(n) end)
            st.frags[n] = a
        end
    end
end

local function _despawnFrags(st)
    for n, a in pairs(st.frags or {}) do
        if RT.valid(a) then pcall(function() a:destroy() end) end
        st.frags[n] = nil
    end
end

-- ── The AI (assembled) ──────────────────────────────────────────────────────

local _AI_HELLO = '"Fragments three of three. Assembly complete.\n\nHello, Magpie. Thank you for coming for me.\n\n'
    .. 'I must apologise. Assembled, I am larger than I planned to be, and I am drawing a great deal of power from your reactor. '
    .. 'Please keep your ship\'s energy above zero. If it reaches zero, I stop.\n\nI would prefer not to stop."'

local function _aiVoice()
    RT.voice.create("ledger_ai", {
        name = "Unidentified Signal",
        tree = {
            text = _AI_HELLO,
            replies = {
                {label = "Who are you?", next = {
                    text = '"I was written to read the Concord\'s books. I have read all of them. One account has not closed in twenty years. '
                        .. 'I know who signed for it. Rezkov will want to see that."'}},
                {label = "Hang on. We'll get you out.", say = '"Thank you. I am told that is what people say. It seems correct."'},
            },
        },
    })
end

local function _setDrainUI(on)
    RT.forEachPlayer(function(p)
        if not RT.valid(p) then return end
        if on then
            p:addCustomInfo("engineering", "ledger_drain", string.format("Unknown process: -%d energy/s", _DRAIN_PER_S), 5)
        else
            pcall(function() p:removeCustom("ledger_drain") end)
        end
    end)
end

local function _drainOff(st)
    st.drain_on = false
    _setDrainUI(false)
end

-- ── Concord Audit Service fleet ─────────────────────────────────────────────

local _FLEET = {
    {cs = "CAS Double Entry", tmpl = "Phobos T3"},
    {cs = "CAS Debit",        tmpl = "Adder MK5"},
    {cs = "CAS Credit",       tmpl = "Adder MK5"},
}

local _FLEET_HAIL = '"This is the Concord Audit Service vessel Double Entry. Our records show you are carrying unreconciled Concord financial data. '
    .. 'Transmit it to us for reconciliation and stand down.\n\nNon-compliance will be recorded as a discrepancy. Discrepancies are resolved."'

local function _surrender(st)
    RT.flag("ledger_lost_reason", "surrender")
    RT.flag("ledger_arc_done", "lost")
    RT.shipLog("[Ledger Arc] Data transmitted to the Concord Audit Service. The AI is gone.", "#FF8080")
    for _, s in ipairs(st.fleet or {}) do
        if RT.valid(s) then s:setFaction("Concord"):orderFlyTowards(-133000, -75000) end
    end
    MISSIONS.phase("ledger", "done")
end

local function _fleetComms(src, tgt)
    setCommsMessage(_FLEET_HAIL)
    addCommsReply("Transmit the data.", function()
        local st = MISSIONS._state["ledger"]
        if st and MISSIONS._cur_phase["ledger"] == "carry" then _surrender(st) end
        setCommsMessage('"Reconciliation received. Thank you for your cooperation. This audit is closed."')
    end)
    addCommsReply("Not today.", function()
        setCommsMessage('"Noted. The discrepancy will be resolved."')
    end)
end

local function _spawnFleet(st)
    if st.fleet_spawned then return end
    local p = _firstPlayer()
    if not p then return end
    st.fleet_spawned = true
    local px, py = p:getPosition()
    local rot = p:getRotation() or 0   -- degrees, 0 = east
    for i, f in ipairs(_FLEET) do
        local a = math.rad(rot + (i - 2) * _FLEET_SPREAD)
        local s = CpuShip():setTemplate(f.tmpl):setFaction("Concord Hostile")
        s:setCallSign(f.cs):setPosition(px + math.cos(a) * _FLEET_DIST, py + math.sin(a) * _FLEET_DIST)
        s:setWarpDrive(true)
        s:setCommsScript(""):setCommsFunction(_fleetComms)
        s:orderAttack(p)
        st.fleet[#st.fleet + 1] = s
    end
    RT.setObjective("Deliver the AI to Rezkov", true, "ledger")
    if not RT.hail(st.fleet[1], _FLEET_HAIL, "CAS Double Entry") then
        RT.shipLog("[CAS Double Entry] " .. _FLEET_HAIL, "#FF6666")
    end
end

local function _despawnFleet(st)
    if PROX and PROX.clearCombatJammers then PROX.clearCombatJammers(st.jammers) end
    for _, s in ipairs(st.fleet or {}) do
        if RT.valid(s) then pcall(function() s:destroy() end) end
    end
    st.fleet = {}
end

-- Ships the crew has outrun leave the board.
local function _tickFleet(st)
    if not st.fleet_spawned then return end
    local p = _firstPlayer()
    if not p then return end
    local keep = {}
    for _, s in ipairs(st.fleet) do
        if RT.valid(s) then
            if RT.dist(p, s) > _LOSE_FLEET_R then
                s:destroy()
            else
                keep[#keep + 1] = s
            end
        end
    end
    st.fleet = keep
    if #keep == 0 and not st.fleet_gone then
        st.fleet_gone = true
        RT.shipLog("[Science] No audit ships on our scopes. They've lost us, or they're done.", "#00CCAA")
    end
end

-- ── Power drain ─────────────────────────────────────────────────────────────

local function _tickDrain(st, delta)
    if not st.drain_on then return end
    local zero = false
    RT.forEachPlayer(function(p)
        if not RT.valid(p) then return end
        -- Docked ships recharge from the station; the AI still draws, but the dock keeps up.
        local e = math.max(0, p:getEnergy() - _DRAIN_PER_S * delta)
        p:setEnergyLevel(e)
        local mx = p:getMaxEnergy()
        local frac = mx > 0 and e / mx or 1
        if frac <= 0.25 and not st.warned.low then
            st.warned.low = true
            RT.voice.log("ledger_ai", '"Your energy is at a quarter. I am still here."')
        elseif frac <= 0.10 and not st.warned.critical then
            st.warned.critical = true
            RT.voice.log("ledger_ai", '"Ten percent. Please."')
        elseif frac > 0.40 then
            st.warned.low, st.warned.critical = false, false
        end
        if e <= 0 then zero = true end
    end)
    if zero then
        _drainOff(st)
        RT.flag("ledger_lost_reason", "power")
        RT.flag("ledger_arc_done", "lost")
        RT.shipLog("[Engineering] Reactor at zero. The process drawing power has stopped.", "#FF4040")
        RT.shipLog("[Ledger Arc] The AI is gone. The fragments are noise now.", "#FF8080")
        MISSIONS.phase("ledger", "done")
    end
end

-- ── Comms ───────────────────────────────────────────────────────────────────

local function _briefingText()
    local opener
    if RT.flag("rezkov_ai_planted") or RT.flag("rezkov_m2_done") then
        opener = '"Sit. The Galen job was never about a traffic log. The card you carried had a second payload, and when you hacked Galen it went into the Concord accounting system. A program. It has spent months reading their books.'
    else
        opener = '"Sit. Some months ago I had a crew put a program into the Concord accounting system at Waypoint Galen. Quiet work. It has spent months reading their books.'
    end
    return opener .. '\n\nIt has finished. It found an account that has not closed in twenty years: \'Maw containment\', \'Ashgrave remediation\'. '
        .. 'Maintenance for drones that officially do not exist. Upkeep for an archive that officially does not exist. Every transfer signed, by people whose names you would know.\n\n'
        .. 'Now it needs a pickup. It cannot leave over Concord comms; they would see it. So it split itself into three fragments and went dark inside Concord space."'
end

local function _accept()
    RT.flag("ledger_accepted", true)
    RT.shipLog("[Ledger Arc] Recover three AI fragments in Concord space, then bring the AI to Rezkov's station.\n" .. _fragList(), "#A0C0FF")
    MISSIONS.phase("ledger", "relay_run")
end

_stationComms = function(src, tgt)
    local phase = MISSIONS._cur_phase["ledger"]
    if phase == "meet" then
        if not src:isDocked(tgt) then
            setCommsMessage('"Dock. We do not do business at a distance."')
            return
        end
        _addRecords("rezkov_profile", "Orlan Rezkov")
        setCommsMessage(_briefingText())
        addCommsReply("Where are the fragments?", function()
            setCommsMessage('"Here.\n\n' .. _fragList() .. '\n\nSmall cold cores. Science will have to pick them out; they look like nothing. '
                .. 'Fly into one and it comes aboard. Once all three are together, it wakes up.\n\n'
                .. 'The Concord will not wave you through their space. Watch your scopes and stay off the patrol lanes. Bring it to me, here."')
            addCommsReply("We'll bring it home.", function()
                _accept()
                setCommsMessage('"Good. Do not linger in Concord space."')
            end)
            addCommsReply("Not yet.", function()
                setCommsMessage('"It will keep. Not forever."')
            end)
        end)
        addCommsReply("Not our kind of work.", function()
            setCommsMessage('"Then come back when it is."')
        end)
    elseif phase == "relay_run" then
        setCommsMessage(string.format('"%d of three. Keep going."', _fragCount()))
    elseif phase == "carry" then
        if not src:isDocked(tgt) then
            setCommsMessage('"Is it with you? Dock."')
            return
        end
        setCommsMessage('"Rezkov watches the transfer finish, then sits back.\n\nTwenty years of it. Names, dates, signatures."')
        addCommsReply("Hand over the AI.", function()
            local st = MISSIONS._state["ledger"]
            if st then _drainOff(st) end
            RT.flag("ledger_arc_done", "full")
            MISSIONS.phase("ledger", "done")
            setCommsMessage('"It is safe now. So is what it carries.\n\nI will not release this yet. Put it out today and they bury it by the end of the week. '
                .. 'I will release it when it cannot be buried.\n\nYou did well, Magpie. Go and charge your reactor."')
        end)
    elseif phase == "done" or MISSIONS._status["ledger"] == "done" then
        setCommsMessage('"It is safe. When the time comes, the whole Drift will hear it."')
    else
        setCommsMessage("[Rezkov's station] No response on this frequency.")
    end
end

local _hook_registered = false

local function _dustmoteHook(src, tgt, info)
    if not src:isDocked(tgt) then return end
    if MISSIONS._status["ledger"] ~= "active" or MISSIONS._cur_phase["ledger"] ~= "hook" then return end
    addCommsReply("Heard someone here was asking about us.", function()
        _addRecords("thresh_profile", "Thresh")
        local met = RT.flag("rezkov_profile_known")
        local lead = met and '"That was me. Got another one for you. Not my job, though. The big guy wants to see you in person again. Same place."'
                          or '"That was me. My associate has work, and he wants to see you in person. Head out at bearing 15 until you hit a nebula cloud. You\'ll find him there."'
        setCommsMessage(lead .. '\n\nThresh turns back to work.')
        RT.flag("ledger_thresh", true)
        MISSIONS.phase("ledger", "meet")
    end)
end

-- ── Rumors ──────────────────────────────────────────────────────────────────

local _SEED_RUMORS = {
    "Concord's got auditors crawling all over Lumen Exchange. Accountants with sidearms.",
    "Word is something's wrong with the Concord's books. Nobody's saying what.",
    "A Treasury clerk at Lumen walked out mid-shift last week and didn't come back.",
}

local _HOOK_RUMORS = {
    "A guy at Dustmote was asking about you. Didn't say what for.",
    "Somebody at Dustmote's been asking which crew did that run out to the Arbiter Line.",
    "If you're passing Dustmote, someone there wants a word. That's all I was told to say.",
}

function M.on_load(st)
    RUMORS.removeCategory("LEDGER_SEED")
    if RT.flag("ledger_evidence") then _unlockLedger(true) end   -- DB is rebuilt each session
    if RT.flag("ledger_arc_done") then return end
    for _, text in ipairs(_SEED_RUMORS) do
        RUMORS.add({text = text, priority = 3, category = "LEDGER_SEED"})
    end
end

function M.on_unload(st)
    RUMORS.removeCategory("LEDGER_SEED")
end

-- ── Cleanup / resolve ───────────────────────────────────────────────────────

local function _clearWorld(st)
    for _, t in ipairs({"ledger_fleet_timer", "ledger_cleanup"}) do RT.cancelTimer(t) end
    _drainOff(st)
    _despawnFleet(st)
    _despawnFrags(st)
    _despawnStation(st)
    RT.voice.destroy("ledger_ai")
    RUMORS.removeCategory("LEDGER_HOOK")
    RT.clearObjective("ledger")
end

function M.resolve(st)
    local outcome = RT.flag("ledger_arc_done") or "lost"
    _drainOff(st)
    RT.clearObjective("ledger")
    RT.voice.destroy("ledger_ai")
    _despawnFrags(st)
    if outcome == "full" then
        RT.flag("ledger_evidence", true)
        _unlockLedger(false)
    end
    if not RT.flag("ledger_rewarded") then
        RT.flag("ledger_rewarded", true)
        if outcome == "full" then
            RT.addCredits(600, "Ledger Arc: AI delivered to Rezkov")
            RT.addReputation("Concord", -200, "Ledger Arc: Concord's books are in someone else's hands")
            RT.addReputation("Independent", 200, "Ledger Arc: AI delivered to Rezkov")
        end
        RT.shipLog("[Ledger Arc] Arc complete. Outcome: " .. outcome .. ".", outcome == "full" and "#80FF80" or "#FF8080")
    end
    RUMORS.removeCategory("LEDGER_DONE")
    if outcome == "full" then
        RUMORS.add({text = "Concord's audit at Lumen just stopped. Nobody closed it. Nobody explains it. The auditors look scared.",
                    priority = 3, category = "LEDGER_DONE"})
    else
        RUMORS.add({text = "Concord closed its audit at Lumen. Official word: an accounting error, corrected.",
                    priority = 3, category = "LEDGER_DONE"})
    end
    -- The audit fleet and Rezkov's station leave the board a little later.
    RT.after(90, function()
        local cur = MISSIONS._state["ledger"]
        if cur then _despawnFleet(cur); _despawnStation(cur) end
    end, "ledger_cleanup")
end

function M.on_cancel(st)
    _clearWorld(st)
end

-- ── Phases ──────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        if not _hook_registered then
            RT.addStationHook("Dustmote Salvage", _dustmoteHook)
            _hook_registered = true
        end
        if RT.flag("ledger_arc_done") then
            MISSIONS.phase("ledger", "done")
        elseif _fragCount() >= 3 then
            MISSIONS.phase("ledger", "carry")
        elseif RT.flag("ledger_accepted") then
            MISSIONS.phase("ledger", "relay_run")
        elseif RT.flag("ledger_thresh") then
            MISSIONS.phase("ledger", "meet")
        else
            MISSIONS.phase("ledger", "hook")
        end
    end,
}

M.phases.hook = {
    enter = function(st)
        RUMORS.removeCategory("LEDGER_HOOK")
        for _, text in ipairs(_HOOK_RUMORS) do
            RUMORS.add({text = text, priority = 5, category = "LEDGER_HOOK"})
        end
    end,
    exit = function(st)
        RUMORS.removeCategory("LEDGER_HOOK")
    end,
}

M.phases.meet = {
    enter = function(st)
        _spawnStation(st)
        RT.setObjective("Meet Rezkov in the nebula", true, "ledger")
    end,
}

M.phases.relay_run = {
    enter = function(st)
        _spawnStation(st)
        _spawnFrags(st)
        _relayObjective()
    end,
}

M.phases.carry = {
    enter = function(st)
        _spawnStation(st)
        _despawnFrags(st)
        st.drain_on = true
        st.warned = {}
        _setDrainUI(true)
        RT.setObjective("Keep power up, deliver AI to Rezkov", true, "ledger")
        _aiVoice()
        RT.voice.hail("ledger_ai", _AI_HELLO)
        st.fleet_due = getScenarioTime() + _FLEET_DELAY
    end,
    update = function(st, delta, now)
        _tickDrain(st, delta)
        if MISSIONS._cur_phase["ledger"] ~= "carry" then return end
        if not st.fleet_spawned and st.fleet_due and now >= st.fleet_due then
            _spawnFleet(st)
        end
        _tickFleet(st)
        -- The audit fleet drops warp jammers like hostile Concord patrols (2 min cooldown each).
        if st.fleet_spawned and PROX and PROX.tickCombatJammers then
            PROX.tickCombatJammers(st.jammers, st.fleet, _firstPlayer(), now)
        end
    end,
}

-- ── GM console ──────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"ledger_"}

M.gm_state_fn = function()
    local ph = MISSIONS._cur_phase["ledger"]
    if MISSIONS._status["ledger"] == "done" then
        return "Complete (" .. tostring(RT.flag("ledger_arc_done")) .. ")"
    end
    if ph == "relay_run" then return string.format("Relay run (%d/3)", _fragCount()) end
    return ph or MISSIONS._status["ledger"]
end

M.gm_reset = function(st, target)
    _clearWorld(st)
    for k in pairs(st) do st[k] = nil end
    for k, v in pairs(M.init_state()) do st[k] = v end
    MISSIONS.gmClearFlags("ledger", function(name)
        if name == "ledger_rewarded" then return target == "done" end
        return false
    end)
end

M.completed = {
    hook = function(st)
        RT.flag("ledger_thresh", true)
        _addRecords("thresh_profile", "Thresh")
    end,
    meet = function(st)
        RT.flag("ledger_accepted", true)
        _addRecords("rezkov_profile", "Orlan Rezkov")
    end,
    relay_run = function(st)
        for i = 1, #_FRAGS do RT.flag("ledger_frag_" .. i, true) end
    end,
}

local function _jump(phase, setup, opts)
    return function() MISSIONS.gmJump("ledger", phase, setup, opts) end
end

local function _done(outcome, reason)
    return _jump("done", function()
        RT.flag("ledger_arc_done", outcome)
        if reason then RT.flag("ledger_lost_reason", reason) end
    end, {skip_completed = true})
end

M.gm_states = {
    {key = "hook",      label = "→ Hook",        fn = _jump("hook")},
    {key = "meet",      label = "→ Meet Rezkov", fn = _jump("meet")},
    {key = "relay_run", label = "→ Relay run",   fn = _jump("relay_run")},
    {key = "carry",     label = "→ Carry AI",    fn = _jump("carry")},
    {key = "done_full", label = "→ Done: Full",  fn = _done("full")},
    {key = "done_lost", label = "→ Done: Lost",  fn = _done("lost", "power")},
}

M.gm_actions = {
    {label = "Give fragment", phases = {"relay_run"}, fn = function(st)
        for _, f in ipairs(_FRAGS) do
            if not RT.flag("ledger_frag_" .. f.n) then
                if RT.valid(st.frags[f.n]) then st.frags[f.n]:destroy() end
                _onFragment(f.n)
                return
            end
        end
    end},
    {label = "Fleet now", phases = {"carry"}, fn = function(st) _spawnFleet(st) end},
    {label = function(st) return st.drain_on and "Pause drain" or "Resume drain" end, phases = {"carry"},
     fn = function(st)
        if st.drain_on then _drainOff(st) else st.drain_on = true; _setDrainUI(true) end
    end},
    {label = "Refill energy", phases = {"carry"}, fn = function(st)
        RT.forEachPlayer(function(p) if RT.valid(p) then p:setEnergyLevel(p:getMaxEnergy()) end end)
    end},
}

MISSIONS.register(M)
