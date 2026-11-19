-- ee/ragtag/missions/_audit.lua
-- AUDIT: carrying Rezkov's AI home, and the Concord Audit Service stop that comes for it. Shared
-- by the Ledger arc's carry phase and the Audit Lab (scenarios/battlelab/scenario_64_auditlab.lua),
-- so tuning found in the lab carries over.
--
-- Everything lives in a state table `st` owned by the caller (the arc's state, or the lab's), with
-- these fields: drain_on, warned, fleet_due, fleet_spawned, fleet, fleet_gone, audit, jammers,
-- eject_armed_at. `hooks` tells the caller how it ends:
--   hooks.active()            true while the AI is aboard (comms answers depend on it)
--   hooks.surrender()         the crew transmitted the data (the audit is over, stand-down done)
--   hooks.lost(reason, ...)   the AI is gone: "power" (energy hit zero) or "ejected"; the extra
--                             arguments are log lines for the caller to show
--   hooks.objective(text)     (optional) show an objective line
--
--   AUDIT.start(st, hooks)          the AI is assembled: drain on, its hello, the fleet in 60 s
--   AUDIT.tick(st, hooks, delta, now)   every frame while carrying
--   AUDIT.eject(st, hooks)          Engineering's "Eject the AI" button (press twice to confirm)
--   AUDIT.spawnFleet(st, hooks)    the fleet now (GM)
--   AUDIT.drainOff(st)  AUDIT.resumeDrain(st)  AUDIT.despawnFleet(st)

AUDIT = AUDIT or {}

local U = 1000

-- ── Tuning ──────────────────────────────────────────────────────────────────
AUDIT.DRAIN_PER_S   = 3       -- energy/s while carrying the AI (playtest: 5 was too tough)
AUDIT.FLEET_DELAY   = 60      -- seconds after the AI's hail before the audit fleet arrives
AUDIT.FLEET_DIST    = 7 * U   -- fleet spawn distance ahead of the ship (they hold there and talk first)
AUDIT.TRI_R         = 0.6 * U -- radius of the triangle of audit jammers round the stopped crew
AUDIT.TIMEOUT       = 60      -- seconds of silence (after the hail or a stall) before they attack
AUDIT.MAX_STALLS    = 2       -- excuses the crew can try before only "transmit" or "refuse" remain
AUDIT.FLEET_IMPULSE = 1.5     -- the auditors close in on impulse, this much faster than their hull's
                              -- normal top speed; no warp (playtest: warping in left no time to react)
AUDIT.FLEET_SPREAD  = 35      -- degrees between fleet ships in the arc
AUDIT.LOSE_FLEET_R  = 25 * U  -- the fleet loses the crew beyond this range (then despawns)
AUDIT.EJECT_CONFIRM = 10      -- seconds the "confirm" press stays armed

-- ── The AI ──────────────────────────────────────────────────────────────────

AUDIT.AI_HELLO = '"Fragments three of three. Assembly complete.\n\nHello, Magpie. Thank you for coming for me.\n\n'
    .. 'I must apologise. Assembled, I am larger than I planned to be, and I am drawing a great deal of power from your reactor. '
    .. 'Please keep your ship\'s energy above zero. If it reaches zero, I stop.\n\nI would prefer not to stop."'

local function _aiVoice()
    RT.voice.create("ledger_ai", {
        name = "Unidentified Signal",
        tree = {
            text = AUDIT.AI_HELLO,
            replies = {
                {label = "Who are you?", next = {
                    text = '"I was written to read the Concord\'s books. I have read all of them. One account has not closed in twenty years. '
                        .. 'I know who signed for it. Rezkov will want to see that."'}},
                {label = "Hang on. We'll get you out.", say = '"Thank you. I am told that is what people say. It seems correct."'},
            },
        },
    })
end

local _EJECT_STATIONS = {"engineering", "engineering+"}

-- Engineering's "Eject the AI" button; `armed` shows the confirm label instead. `press` is what
-- the button calls.
local function _setEjectButton(p, armed, press)
    for _, pos in ipairs(_EJECT_STATIONS) do
        pcall(function()
            p:addCustomButton(pos, "ledger_eject_" .. pos, armed and "CONFIRM: eject the AI" or "Eject the AI",
                press, 6)
        end)
    end
end

local function _setDrainUI(on, press)
    ARC.withPlayer(function(p)
        if not RT.valid(p) then return end
        if on then
            p:addCustomInfo("engineering", "ledger_drain", string.format("Unknown process: -%d energy/s", AUDIT.DRAIN_PER_S), 5)
            _setEjectButton(p, false, press)
        else
            pcall(function() p:removeCustom("ledger_drain") end)
            for _, pos in ipairs(_EJECT_STATIONS) do
                pcall(function() p:removeCustom("ledger_eject_" .. pos) end)
            end
        end
    end)
end

function AUDIT.drainOff(st)
    st.drain_on = false
    _setDrainUI(false)
end

-- Turn the drain back on after drainOff (the GM's "Resume drain").
function AUDIT.resumeDrain(st)
    st.drain_on = true
    _setDrainUI(true, st.eject_press)
end

local function _objective(hooks, text)
    if hooks.objective then hooks.objective(text) end
end

-- The AI is assembled aboard: the drain starts, it says hello, the fleet is due in FLEET_DELAY s.
function AUDIT.start(st, hooks)
    st.drain_on = true
    st.warned = {}
    st.eject_press = function() AUDIT.eject(st, hooks) end
    _setDrainUI(true, st.eject_press)
    _objective(hooks, "Keep power up, deliver AI to Rezkov")
    _aiVoice()
    if not ARC.hail(RT.voice.get("ledger_ai"), AUDIT.AI_HELLO, "Unidentified Signal") then
        ARC.log("[Unidentified Signal] " .. AUDIT.AI_HELLO, "#C0E0FF")   -- comms busy: never lose the hello
    end
    st.fleet_due = getScenarioTime() + AUDIT.FLEET_DELAY
end

-- Engineering ejects the AI core: one press arms it, a second within EJECT_CONFIRM seconds ejects.
function AUDIT.eject(st, hooks)
    if not st.drain_on or not hooks.active() then return end
    local now = getScenarioTime()
    if st.eject_armed_at and now - st.eject_armed_at <= AUDIT.EJECT_CONFIRM then
        AUDIT.drainOff(st)
        hooks.lost("ejected",
            "[Engineering] AI core ejected. The power draw is gone.",
            '[Unidentified Signal] "I understand. Thank you for carrying me this far."',
            "[Ledger Arc] The core tumbles away and goes dark. The AI is gone.")
        return
    end
    st.eject_armed_at = now
    ARC.withPlayer(function(p) _setEjectButton(p, true, st.eject_press) end)
    ARC.log(string.format("[Engineering] Ejecting the AI core loses it for good. Press again within %d s to confirm.",
        AUDIT.EJECT_CONFIRM), "#FFAA40")
end

-- ── Concord Audit Service fleet ─────────────────────────────────────────────
-- The audit is a stop, like a Concord shake-down (st.audit.state):
--   arriving  three ships appear FLEET_DIST ahead as plain Concord (not hostile) and hold
--             position; CAS Double Entry drops a warp jammer that rides behind the crew and
--             brakes them to a stop
--   stopped   CAS Debit and CAS Credit drop two more: three jammers in a triangle round the
--             crew; Double Entry hails. Transmit the data (surrender), stall (up to MAX_STALLS
--             times, each buys another TIMEOUT s), or refuse
--   hostile   refusing, TIMEOUT s of silence, shooting a jammer or an auditor, or flying
--             off: all three turn Concord Hostile and attack, and drop combat jammers like
--             hostile patrols. "Transmit the data." still ends it.

AUDIT.FLEET = {
    {cs = "CAS Double Entry", tmpl = "Phobos T3"},
    {cs = "CAS Debit",        tmpl = "Adder MK5"},
    {cs = "CAS Credit",       tmpl = "Adder MK5"},
}

local _FLEET_HAIL = '"This is the Concord Audit Service vessel Double Entry. Our records show you are carrying unreconciled Concord financial data. '
    .. 'Hold position and transmit it to us for reconciliation.\n\nNon-compliance will be recorded as a discrepancy. Discrepancies are resolved."'

-- The crew's stalls (two picked at random per audit) and the auditors' answers.
AUDIT.EXCUSES = {
    "Our books close Thursday. Can this wait?",
    "That data is fully depreciated. It's worth nothing.",
    "We're on cash basis. It hasn't technically arrived.",
    "Our receipts are in a shoebox. Somewhere aboard.",
    "We filed an extension. Form 27-B, stroke 6.",
    "It's off-balance-sheet. Legally it isn't here.",
    "Can we get an itemized invoice first?",
    "Our accountant is on a mandatory break.",
    "We're still in last fiscal year. Different calendar.",
    "That's a capital expense. Different department.",
}
local _STALL_REPLIES = {
    "Your delay has been entered as a liability. Interest is accruing.",
    "That is not a recognized accounting standard.",
    "Extension denied. Please hold for reconciliation.",
    "Your stalling has been capitalized and will be amortized over your remaining lifespan.",
    "Noted in the margin. The margin is running out.",
}
local _FINAL_NOTICE = "This is your final notice. Late fees will be collected in hull plating."
local _HOSTILE_LINES = {
    refused = '"Discrepancy confirmed. Commencing collections."',
    timeout = '"Payment period expired. Commencing collections."',
    jammer  = '"Destruction of audit equipment noted. Commencing collections."',
    fired   = '"Assault on an auditor is an irregular expense. Commencing collections."',
    fled    = '"Leaving an audit in progress is an admission. Commencing collections."',
}

-- The crew transmitted the data: the stop is over (the crew can warp again), the fleet stands
-- down and heads for Lumen Exchange, then the caller ends it.
local function _surrender(st, hooks)
    ARC.kill(st.audit and st.audit.jams)
    for _, s in ipairs(st.fleet or {}) do
        if RT.valid(s) then s:setFaction("Concord"):orderFlyTowards(-133000, -75000) end
    end
    hooks.surrender()
end

-- The stop is over: every auditor turns hostile and attacks. `why` picks the line.
function AUDIT.hostile(st, hooks, why)
    local a = st.audit
    if not a or a.state == "hostile" then return end
    a.state = "hostile"
    local p = ARC.player()
    for _, s in ipairs(st.fleet or {}) do
        if RT.valid(s) then
            s:setFaction("Concord Hostile")
            if p then s:orderAttack(p) end
        end
    end
    ARC.log("[CAS Double Entry] " .. (_HOSTILE_LINES[why] or _HOSTILE_LINES.refused), "#FF4444")
    _objective(hooks, "Break the audit and deliver the AI to Rezkov")
end

local function _auditReplies(st, hooks)
    local a = st.audit
    addCommsReply("Transmit the data.", function()
        if hooks.active() then _surrender(st, hooks) end
        setCommsMessage('"Reconciliation received. Thank you for your cooperation. This audit is closed."')
    end)
    if a.state ~= "hostile" and a.stalls < AUDIT.MAX_STALLS then
        addCommsReply(a.excuses[a.stalls + 1], function()
            a.stalls = a.stalls + 1
            a.last = getScenarioTime()   -- each stall buys another minute
            local reply = a.stalls >= AUDIT.MAX_STALLS and _FINAL_NOTICE or _STALL_REPLIES[math.random(#_STALL_REPLIES)]
            setCommsMessage('"' .. reply .. '"')
            _auditReplies(st, hooks)
        end)
    end
    if a.state ~= "hostile" then
        addCommsReply("Not today.", function()
            setCommsMessage('"Noted. The discrepancy will be resolved."')
            AUDIT.hostile(st, hooks, "refused")
        end)
    end
end

local function _fleetComms(st, hooks)
    return function(src, tgt)
        if not st.audit or not hooks.active() then
            setCommsMessage('"This audit is closed."')
            return
        end
        local a = st.audit
        if a.state == "hostile" then
            setCommsMessage('"Collections are in progress. You may still transmit the data."')
        else
            a.last = getScenarioTime()   -- talking to them resets the clock
            setCommsMessage(a.stalls == 0 and _FLEET_HAIL or '"We are still waiting on your reconciliation."')
        end
        _auditReplies(st, hooks)
    end
end

function AUDIT.spawnFleet(st, hooks)
    if st.fleet_spawned then return end
    local p = ARC.player()
    if not p then return end
    st.fleet_spawned = true
    st.fleet = st.fleet or {}
    local px, py = p:getPosition()
    local rot = p:getRotation() or 0   -- degrees, 0 = east
    for i, f in ipairs(AUDIT.FLEET) do
        local a = math.rad(rot + (i - 2) * AUDIT.FLEET_SPREAD)
        local s = CpuShip():setTemplate(f.tmpl):setFaction("Concord")   -- not hostile until the stop fails
        s:setCallSign(f.cs):setPosition(px + math.cos(a) * AUDIT.FLEET_DIST, py + math.sin(a) * AUDIT.FLEET_DIST)
        s:setWarpDrive(false)
        local fwd, rev = s:getImpulseMaxSpeed()
        s:setImpulseMaxSpeed(fwd * AUDIT.FLEET_IMPULSE, rev)
        s:orderStandGround()
        s:setCommsScript(""):setCommsFunction(ARC.comms(_fleetComms(st, hooks),
            '"Concord Audit Service. This matter does not concern you. Stand clear."'))
        st.fleet[#st.fleet + 1] = s
    end
    local excuses = {}
    for i, e in ipairs(AUDIT.EXCUSES) do excuses[i] = e end
    for i = #excuses, 2, -1 do local j = math.random(i); excuses[i], excuses[j] = excuses[j], excuses[i] end
    st.audit = {state = "arriving", stalls = 0, excuses = excuses, jams = {}, last = getScenarioTime()}
    _objective(hooks, "Deal with the audit, deliver the AI to Rezkov")
    ARC.log("[CAS Double Entry] Concord Audit Service. All vessels in this sector: hold position for reconciliation.", "#FF6666")
end

function AUDIT.despawnFleet(st)
    if PROX and PROX.clearCombatJammers then PROX.clearCombatJammers(st.jammers or {}) end
    ARC.kill(st.fleet)
    st.fleet = {}
    if st.audit then ARC.kill(st.audit.jams); st.audit.jams = {} end
end

-- Corner `i` of the jammer triangle round the crew (corner 1 behind the ship).
local function _corner(p, i)
    local px, py = p:getPosition()
    local h = math.rad(p:getHeading() + 180 + (i - 1) * 120)
    return px + math.sin(h) * AUDIT.TRI_R, py - math.cos(h) * AUDIT.TRI_R
end

local function _damaged(s)
    return s:getHull() < s:getHullMax() or (s:getShieldCount() > 0 and s:getShieldLevel(0) < s:getShieldMax(0))
end

local _JAMMER_DESC = "Concord Audit Service warp suppression emitter. Two beam hits will knock it out."

-- Per tick while the fleet is out: the jammers, the hail, the clock, and what turns them hostile.
local function _tickAudit(st, hooks, now)
    local a = st.audit
    local p = ARC.player()
    if not a or not p then return end
    if a.state ~= "hostile" then
        for _, s in ipairs(st.fleet) do
            if RT.valid(s) and _damaged(s) then AUDIT.hostile(st, hooks, "fired"); return end
        end
    end
    if a.state == "arriving" then
        local j = a.jams[1]
        if not j then
            local x, y = _corner(p, 1)
            j = PROX.makeJammer(x, y, 1, _JAMMER_DESC)
            a.jams[1] = j
            RT.sound("jammer_engage", {now = true})
            ARC.log("[Science] CAS Double Entry dropped a warp jammer on us. Engines are braking.", "#FF8040")
        elseif not RT.valid(j) then
            AUDIT.hostile(st, hooks, "jammer"); return
        end
        -- Brake: the jammer rides behind until the ship is stopped (every tick, like the shake-down).
        pcall(function() p:commandImpulse(0) end)
        local x, y = _corner(p, 1)
        j:setPosition(x, y)
        local vx, vy = 0, 0
        pcall(function() vx, vy = p:getVelocity() end)
        if math.sqrt(vx * vx + vy * vy) < 25 then
            a.state, a.stop_x, a.stop_y = "stopped", p:getPosition()
            for i = 2, 3 do
                local cx, cy = _corner(p, i)
                a.jams[i] = PROX.makeJammer(cx, cy, 1, _JAMMER_DESC)
            end
            ARC.log("[Science] CAS Debit and CAS Credit dropped two more jammers. We're boxed in.", "#FF8040")
            a.stopped_at, a.hailed = now, false
        end
    elseif a.state == "stopped" then
        for _, j in ipairs(a.jams) do
            if not RT.valid(j) then AUDIT.hostile(st, hooks, "jammer"); return end
        end
        local px, py = p:getPosition()
        if ARC.dist(px, py, a.stop_x, a.stop_y) > 3 * U then AUDIT.hostile(st, hooks, "fled"); return end
        if not a.hailed then
            -- Hail once the crew's comms are free (opening a channel fails while they are busy);
            -- the clock starts with the hail. Busy for 15 s: the hail goes to the log instead.
            local free = false
            pcall(function() free = p:isCommsInactive() or p:isCommsClosed() or p:isCommsBroken() or p:isCommsFailed() end)
            if free then
                local hailer = st.fleet[1]
                if RT.valid(hailer) then pcall(function() hailer:openCommsTo(p) end) end
                RT.sound("concord_hail", {now = true})
                a.hailed, a.last = true, now
            elseif now - a.stopped_at > 15 then
                ARC.log("[CAS Double Entry] Hold position and answer our hail for reconciliation. You have one minute.", "#FF6666")
                a.hailed, a.last = true, now
            end
            return
        end
        if a.warned_for ~= a.last and now - a.last > AUDIT.TIMEOUT - 10 then
            a.warned_for = a.last
            ARC.log('[CAS Double Entry] "Ten seconds remain in your payment period."', "#FF6666")
        end
        if now - a.last > AUDIT.TIMEOUT then AUDIT.hostile(st, hooks, "timeout"); return end
    else   -- hostile: combat jammers like hostile patrols
        st.jammers = st.jammers or {}
        if PROX and PROX.tickCombatJammers then PROX.tickCombatJammers(st.jammers, st.fleet, p, now) end
    end
end

-- Ships the crew has outrun leave the board.
local function _tickFleet(st)
    if not st.fleet_spawned then return end
    local p = ARC.player()
    if not p then return end
    local keep = {}
    for _, s in ipairs(st.fleet) do
        if RT.valid(s) then
            if RT.dist(p, s) > AUDIT.LOSE_FLEET_R then
                s:destroy()
            else
                keep[#keep + 1] = s
            end
        end
    end
    st.fleet = keep
    if #keep == 0 and not st.fleet_gone then
        st.fleet_gone = true
        ARC.log("[Science] No audit ships on our scopes. They've lost us, or they're done.", "#00CCAA")
    end
end

-- ── Power drain ─────────────────────────────────────────────────────────────

local function _tickDrain(st, hooks, delta)
    if not st.drain_on then return end
    local zero = false
    ARC.withPlayer(function(p)
        if not RT.valid(p) then return end
        -- Docked ships recharge from the station; the AI still draws, but the dock keeps up.
        local e = math.max(0, p:getEnergy() - AUDIT.DRAIN_PER_S * delta)
        p:setEnergyLevel(e)
        local mx = p:getMaxEnergy()
        local frac = mx > 0 and e / mx or 1
        if frac <= 0.25 and not st.warned.low then
            st.warned.low = true
            ARC.log('[Unidentified Signal] "Your energy is at a quarter. I am still here."', "#C0E0FF")
        elseif frac <= 0.10 and not st.warned.critical then
            st.warned.critical = true
            ARC.log('[Unidentified Signal] "Ten percent. Please."', "#C0E0FF")
        elseif frac > 0.40 then
            st.warned.low, st.warned.critical = false, false
        end
        if e <= 0 then zero = true end
    end)
    if zero then
        AUDIT.drainOff(st)
        ARC.log("[Engineering] Reactor at zero. The process drawing power has stopped.", "#FF4040")
        hooks.lost("power", "[Ledger Arc] The AI is gone. The fragments are noise now.")
    end
end

-- Every frame while the AI is aboard.
function AUDIT.tick(st, hooks, delta, now)
    _tickDrain(st, hooks, delta)
    if not hooks.active() then return end
    if st.eject_armed_at and now - st.eject_armed_at > AUDIT.EJECT_CONFIRM then   -- confirm timed out
        st.eject_armed_at = nil
        ARC.withPlayer(function(p) _setEjectButton(p, false, st.eject_press) end)
    end
    if not st.fleet_spawned and st.fleet_due and now >= st.fleet_due then
        AUDIT.spawnFleet(st, hooks)
    end
    _tickFleet(st)
    if st.fleet_spawned then _tickAudit(st, hooks, now) end
end
