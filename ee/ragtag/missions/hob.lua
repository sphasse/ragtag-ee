-- ee/ragtag/missions/hob.lua
-- The Hob Works Arc: the Boneyard survivors and the Hob Works can build the cure (the Lullaby
-- beacon) if the crew pays for the parts, and the crew pays for them by robbing a Concord Treasury
-- transfer on its way from Lumen Exchange to Sentinel Fleet Yard. GM guide: docs/GM_HOB_WORKS_MISSION.md
--
-- Structure: init -> hook -> heist -> deliver -> done ("funded" | "abandoned")
--   hook     port news at Independent ports: Mara Quill left a message. Docked at Hob's Landing,
--            Quill and Chief Engineer Marchetti brief the crew (four pages), then the convoy brief.
--   heist    the convoy waits docked at Lumen Exchange for HEIST_DELAY s, then runs to Sentinel at
--            TRANSPORT_SPEED. Escorts spot the Magpie inside SCAN_R (the fake transponder, one use
--            from Engineering, hides it for CODE_TIME s before departure). Disable (impulse and rear
--            shield each HACKED_AT hacked or under HEALTH_AT health) and board: 12,000 cr; destroy
--            it: three 3,000 cr cash boxes.
--   deliver  the cash counts only at Hob's Landing (DELIVER_TIME s); then the crew pays the Works.
--            Late: Independent standing to -100, shaming port news for PESTER_TIME s, late delivery
--            still taken; then the arc ends "abandoned". Paying the Works ends the arc "funded":
--            Lullaby takes time to build, and a later mission picks it up.

local M = {}
M.id             = "hob"
M.name           = "Hob Works Arc"
M.repeatable     = false
M.locks_jobs     = false
M.auto_start     = true
M.start_phase    = "init"
M.no_auto_cancel = true

local U = 1000

-- ── Tuning ──────────────────────────────────────────────────────────────────
M.JOBS_AFTER_PHASE2 = 5      -- board jobs by the primary ship after the last Phase II arc ended
M.HEIST_DELAY       = 900    -- s from the briefing to the convoy's departure
M.TRANSPORT_SPEED   = 125    -- units/s (7.5U a minute): Lumen to Sentinel in about 8 minutes
M.SPEED_STEP        = 25     -- GM "Transport faster / slower"
M.TRANSPORT_ACCEL   = 25     -- units/s^2: up to speed in about five seconds
M.ESCORT_SPEED      = 150    -- the escorts keep up with the transport
M.SCAN_R            = 15 * U -- the escorts' scan range
M.CODE_TIME         = 600    -- s the fake transponder code checks out
-- Disabled: impulse AND rear shield each "down", judged by what the crew can see: Relay's hacking
-- screen at HACKED_AT or more ("hacked 90%"), or Science's health reading under HEALTH_AT.
M.HACKED_AT         = 0.90
M.HEALTH_AT         = 0.10
M.ARRIVE_R          = 3 * U  -- the transport at Sentinel: the money is gone
M.BOX_VALUE         = 3000
M.HAUL_BOARDED      = 4 * M.BOX_VALUE   -- 12,000
M.WRECK_BOXES       = 3                 -- 9,000; the fourth box was lost in the explosion
M.DELIVER_TIME      = 900    -- s to bring the cash to Hob's Landing
M.PESTER_TIME       = 1800   -- s of shaming port news after a missed delivery
M.PRICE             = 10000  -- the Works' price with the Ashgrave archive
M.PRICE_NO_ARCHIVE  = 15000  -- without it (the survivors' own notes)
M.PATROL_PAUSE      = 300    -- s before departure when the Concord patrols stop (normal until then)
M.CHASE_COOLDOWN    = 30     -- s between Concord patrols after the heist, until the Magpie leaves Concord space
M.CHASE_MAX         = 4      -- Concord ships at most per zone during that chase
M.CONCORD_BOARDED   = -800
M.CONCORD_DESTROYED = -1000
M.LATE_INDEPENDENT  = -100   -- Independent standing after a missed delivery, whatever it was

M.INTEL_MAP = "ragtag/img/convoy_route.png"   -- the convoy intel entry's image

local _CONCORD_ZONES ={"the Concord Core", "the Arbiter Line", "the Escrow Marches"}
local _LUMEN, _SENTINEL = "Lumen Exchange", "Sentinel Fleet Yard"
local _TRANSPORT_CS = "CTS Tithe"
local _ESCORT_CS = {"CNS Surety", "CNS Bond"}
local _ENG = {"engineering", "engineering+"}

function M.init_state()
    return {
        transport  = nil,   -- CTS Tithe
        escorts    = {},
        boxes      = {},    -- cash boxes from the wreck
        boxes_got  = 0,
        depart_at  = nil,   -- scenario time the convoy leaves
        departed   = false,
        spotted    = false, -- the escorts have seen the Magpie
        warned     = false, -- their one warning hail
        disabled   = false,
        code_until = nil,   -- the fake code checks out until this time
        code_used  = false,
        speed      = M.TRANSPORT_SPEED,
        tx = nil, ty = nil, -- the transport's last position (the wreck's)
        deliver_due = nil,
        pester_until = nil,
        timer_text = nil,
        code_text  = nil,
        patrols_paused = false, -- the Concord zones are off (PATROL_PAUSE s before departure)
        chase      = nil,   -- after the heist: a patrol every CHASE_COOLDOWN s until out of Concord space
    }
end

-- ── Small helpers ───────────────────────────────────────────────────────────

local function _active(phase)
    return MISSIONS._status["hob"] == "active" and (phase == nil or MISSIONS._cur_phase["hob"] == phase)
end

local function _price()
    return RT.flag("boneyard_hack_done") and M.PRICE or M.PRICE_NO_ARCHIVE
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

local function _mmss(secs)
    secs = math.max(0, math.ceil(secs))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local function _stationXY(cs, fx, fy)
    local s = RT.find(cs)
    if RT.valid(s) then return s:getPosition() end
    return fx, fy
end

-- Effective power of a system, as EE computes it: hacking takes up to 75% off, damage scales the rest.
local function _eff(ship, sys)
    local okh, health = pcall(function() return ship:getSystemHealth(sys) end)
    local okk, hacked = pcall(function() return ship:getSystemHackedLevel(sys) end)
    health = okh and health or 1
    hacked = okk and hacked or 0
    return math.max(0, 1 - 0.75 * hacked) * math.max(0, health)
end
M.effectivePower = _eff

-- A system is down when Relay's hacking screen shows it HACKED_AT or more, or Science shows its health
-- under HEALTH_AT. (Not effective power: no console shows that, and a full hack alone leaves 25%.)
local function _down(ship, sys)
    local okh, health = pcall(function() return ship:getSystemHealth(sys) end)
    local okk, hacked = pcall(function() return ship:getSystemHackedLevel(sys) end)
    return (okk and (hacked or 0) >= M.HACKED_AT) or (okh and (health or 1) < M.HEALTH_AT)
end
M.systemDown = _down

-- A countdown line on the arc ship's Relay and Operations (under the objective).
local function _timerLine(st, text)
    if st.timer_text == text then return end
    st.timer_text = text
    ARC.withPlayer(function(p)
        for _, pair in ipairs({{"relay", "hob_timer"}, {"operations", "hob_timer_ops"}}) do
            if text then
                pcall(function() p:addCustomInfo(pair[1], pair[2], text, 150) end)
            else
                pcall(function() p:removeCustom(pair[2]) end)
            end
        end
    end)
end

-- ── Concord patrols ─────────────────────────────────────────────────────────
-- Normal until PATROL_PAUSE s before the convoy leaves; off while it runs; then, from the end of the
-- heist, a chase (a patrol every CHASE_COOLDOWN s) until the Magpie is out of Concord space.

local function _suspendPatrols()
    for _, z in ipairs(_CONCORD_ZONES) do PROX.suspendZone(z) end
end
local function _endChase(st)
    for _, z in ipairs(_CONCORD_ZONES) do PROX.endChase(z) end
    if st then st.chase = nil end
end
local function _resumePatrols(st)
    for _, z in ipairs(_CONCORD_ZONES) do PROX.resumeZone(z) end
    _endChase(st)
end
local function _startChase(st)
    for _, z in ipairs(_CONCORD_ZONES) do
        PROX.resumeZone(z)
        PROX.chaseZone(z, M.CHASE_COOLDOWN, M.CHASE_MAX)
    end
    st.chase = true
end

-- Is the arc ship inside any Concord region?
function M.inConcordSpace() return ARC.inRegions(_CONCORD_ZONES) end

-- The chase ends once the Magpie is out of Concord space (or lost): patrols back to normal.
local function _tickChase(st)
    if st.chase and not M.inConcordSpace() then
        _endChase(st)
        ARC.log("[Hob Works] Out of Concord space. The patrols are back to their usual rounds.", "#A0C0FF")
    end
end

-- ── The fake transponder (Engineering) ──────────────────────────────────────

local function _codeValid(st, now)
    return st.code_until ~= nil and (now or getScenarioTime()) < st.code_until
end

local function _setTransponderUI(st, show_button, code_text)
    ARC.withPlayer(function(p)
        for _, pos in ipairs(_ENG) do
            if show_button then
                pcall(function() p:addCustomButton(pos, "hob_transponder_" .. pos, "Change transponder",
                    function() M.transponderPressed() end, 6) end)
            else
                pcall(function() p:removeCustom("hob_transponder_" .. pos) end)
            end
            if code_text then
                pcall(function() p:addCustomInfo(pos, "hob_code_" .. pos, code_text, 7) end)
            else
                pcall(function() p:removeCustom("hob_code_" .. pos) end)
            end
        end
    end)
    st.code_text = code_text
end

-- Engineering's pop-up when the heist's button appears: what it is for.
local function _explainHeistTransponder()
    local text = "The Hob Works wired a fake transponder into the ship.\n\nPress \"Change transponder\" "
        .. "to swap it in. For " .. (M.CODE_TIME // 60) .. " minutes the convoy's escorts read the Magpie "
        .. "as an ordinary ship, so you can get close and scan the convoy while it waits at Lumen Exchange. "
        .. "It works once: then the Concord rotates its keys. Once the convoy leaves, the escorts know you."
    ARC.withPlayer(function(p)
        for _, pos in ipairs(_ENG) do
            pcall(function() p:addCustomMessage(pos, "hob_transponder_help_" .. pos, text) end)
        end
    end)
end

-- Engineering's "Change transponder": immediate, one use, good for CODE_TIME seconds.
function M.transponderPressed()
    local st = MISSIONS._state["hob"]
    if not st or not _active("heist") or st.code_used or st.departed then return end
    st.code_used = true
    st.code_until = getScenarioTime() + M.CODE_TIME
    if STATS then STATS.inc("transponder_swaps", 1) end   -- the "Nothing to See Here" achievement
    _setTransponderUI(st, false, "Code valid " .. _mmss(M.CODE_TIME))
    ARC.log(string.format("[Engineering] Transponder swapped. The Works' code will check out for %d minutes, until the Concord rotates its keys.",
        M.CODE_TIME // 60), "#80FF80")
end

local function _tickTransponder(st, now)
    if st.departed then
        if st.code_text then _setTransponderUI(st, false, nil) end
        return
    end
    if not st.code_used then return end
    local left = st.code_until - now
    local text = left > 0 and ("Code valid " .. _mmss(left)) or "Code expired"
    if text ~= st.code_text then
        if left <= 0 and st.code_text ~= "Code expired" then
            ARC.log("[Engineering] The Concord has rotated its keys. The fake code no longer checks out.", "#FFAA40")
        end
        _setTransponderUI(st, false, text)
    end
end

-- ── The convoy ──────────────────────────────────────────────────────────────

local function _spawnConvoy(st)
    if RT.valid(st.transport) then return end
    local lx, ly = _stationXY(_LUMEN, -133000, -75000)
    local sx, sy = _stationXY(_SENTINEL, -159000, -22000)
    local dx, dy = sx - lx, sy - ly
    local d = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / d, dy / d
    local px, py = -dy, dx                       -- across the lane
    local tx, ty = lx + dx * 2500, ly + dy * 2500 -- alongside Lumen, on the Sentinel side

    local t = CpuShip():setTemplate("Equipment Freighter 5"):setFaction("Concord")
    t:setCallSign(_TRANSPORT_CS)
    t:setPosition(tx, ty):setRotation(math.deg(math.atan(dy, dx)))
    t:setHullMax(100):setHull(100)
    t:setShieldsMax(50, 50):setShields(50, 50)
    t:setBeamWeapon(0, 60, 180, 1000, 6, 3)      -- one weak rear beam
    t:setWarpDrive(false):setJumpDrive(false)
    t:setImpulseMaxSpeed(st.speed, st.speed / 2)
    t:setAcceleration(M.TRANSPORT_ACCEL, M.TRANSPORT_ACCEL)   -- stock 10: twelve seconds to get going
    t:setScanningParameters(1, 2)
    t:setDescriptions("Large Concord transport.",
        "Concord Treasury transport CTS Tithe. Armoured cargo hold; a single light beam aft. Manifest sealed.")
    t:orderIdle()
    t:setCommsScript(""):setCommsFunction(ARC.comms(function(src, tgt)
        if st.disabled then
            setCommsMessage('"We\'re dead in space. Come aboard and take it. Nobody here is paid enough to die for it."')
        else
            setCommsMessage('"CTS Tithe, Concord Treasury. Keep your distance."')
        end
    end, '"CTS Tithe, Concord Treasury. Keep your distance."'))
    ARC.register(t)
    RT.onKill(t, function(ship) M._transportDestroyed() end)
    st.transport = t
    st.tx, st.ty = tx, ty

    st.escorts = {}
    for i, cs in ipairs(_ESCORT_CS) do
        local side = (i == 1) and 1 or -1
        local e = CpuShip():setTemplate("Adder MK8"):setFaction("Concord")
        e:setCallSign(cs)
        e:setPosition(tx + px * 1200 * side - dx * 600, ty + py * 1200 * side - dy * 600)
        e:setHullMax(100):setHull(100)
        e:setWarpDrive(false):setJumpDrive(false)
        e:setImpulseMaxSpeed(M.ESCORT_SPEED, M.ESCORT_SPEED / 2)
        e:setWeaponStorage("Nuke", 0):setWeaponStorageMax("Nuke", 0)
        e:setScanningParameters(1, 2)
        e:orderIdle()
        e:setCommsScript(""):setCommsFunction(function(src, tgt)
            setCommsMessage('"Concord Navy escort. Keep clear of the convoy."')
        end)
        ARC.register(e)
        st.escorts[i] = e
    end
end

local function _despawnConvoy(st)
    ARC.kill(st.transport); st.transport = nil
    ARC.kill(st.escorts);   st.escorts = {}
    ARC.kill(st.boxes);     st.boxes = {}
end

-- The escorts have seen the Magpie: one warning, then they come for it.
local function _spot(st, p)
    if st.spotted then return end
    st.spotted = true
    local escorts = ARC.alive(st.escorts)
    for _, e in ipairs(escorts) do
        e:setFaction("Concord Hostile")
        e:orderAttack(p)
    end
    if not st.warned then
        st.warned = true
        local line = string.format('"We see you, %s. Head the other direction or you are in for trouble. This is a fight you cannot win."', p:getCallSign())
        if not (escorts[1] and ARC.hail(escorts[1], line, escorts[1]:getCallSign())) then
            ARC.log("[" .. (escorts[1] and escorts[1]:getCallSign() or "CNS escort") .. "] " .. line, "#FF8080")
        end
    end
    ARC.log("[Heist] The escorts have spotted us.", "#FF8080")
end

local function _depart(st)
    if st.departed then return end
    st.departed = true
    local t = st.transport
    if RT.valid(t) and not st.disabled then
        local sx, sy = _stationXY(_SENTINEL, -159000, -22000)
        t:setFaction("Concord Hostile")   -- the run is on: it can be fought, and it fights back aft
        t:setImpulseMaxSpeed(st.speed, st.speed / 2)
        t:orderFlyTowardsBlind(sx, sy)
        for i, e in ipairs(ARC.alive(st.escorts)) do
            if not st.spotted then
                e:orderFlyFormation(t, (i == 1 and 1 or -1) * 1200, -600)
            end
        end
    end
    _setTransponderUI(st, false, nil)
    RT.setObjective("Stop " .. _TRANSPORT_CS, true, "hob")
    ARC.log(string.format("[Heist] %s has left Lumen Exchange for Sentinel Fleet Yard. Stop it.", _TRANSPORT_CS), "#FFAA40")
end

-- ── The end of the heist ────────────────────────────────────────────────────

local function _heistOver(st, result, haul)
    if RT.flag("hob_heist") then return end
    RT.flag("hob_heist", result)
    if haul and haul > 0 then RT.flag("hob_haul", haul) end
    _startChase(st)   -- the way home: a Concord patrol every 30 s until out of Concord space
    ARC.log("[Heist] The Concord is hunting the Magpie. Get out of Concord space.", "#FF8080")
    _setTransponderUI(st, false, nil)
    if _active("heist") then MISSIONS.phase("hob", "deliver") end
end

local function _disable(st)
    local t = st.transport
    if st.disabled or not RT.valid(t) then return end
    st.disabled = true
    t:setImpulseMaxSpeed(0, 0)
    t:orderIdle()
    t:setFaction("Concord Surrendered")   -- nobody's enemy: it can be docked with and is left alone
    t:setCanBeDestroyed(false)
    pcall(function() t.components.docking_bay = {external_dock_classes = {"Frigate"}} end)
    RT.setObjective("Board " .. _TRANSPORT_CS, true, "hob")
    ARC.log(string.format("[Heist] %s is dead in space, engines and rear shield down. Dock with it to board.", _TRANSPORT_CS), "#FFCC80")
    local line = '"All right! We\'re dead in the water. Come aboard and take it, just don\'t shoot."'
    if not ARC.hail(t, line, _TRANSPORT_CS) then ARC.log("[" .. _TRANSPORT_CS .. "] " .. line, "#FFCC80") end
end

local function _board(st)
    ARC.once("hob_penalized", function()
        RT.addReputation("Concord", M.CONCORD_BOARDED, "Hob Works Arc: robbed a Treasury transport")
    end)
    ARC.log(string.format("[Heist] Four cash boxes aboard: %s cr. It only counts once it is at Hob's Landing.", _cr(M.HAUL_BOARDED)), "#80FF80")
    _heistOver(st, "boarded", M.HAUL_BOARDED)
end

local function _onBox(n)
    local st = MISSIONS._state["hob"]
    if not st or not _active("heist") then return end
    st.boxes[n] = nil
    st.boxes_got = st.boxes_got + 1
    ARC.log(string.format("[Heist] Cash box aboard (%d/%d).", st.boxes_got, M.WRECK_BOXES), "#80FF80")
    if st.boxes_got >= M.WRECK_BOXES then
        _heistOver(st, "destroyed", st.boxes_got * M.BOX_VALUE)
    else
        RT.setObjective(string.format("Cash boxes %d/%d", st.boxes_got, M.WRECK_BOXES), true, "hob")
    end
end

-- The transport destroyed (damage kill): three cash boxes in the wreck, the fourth lost.
function M._transportDestroyed()
    local st = MISSIONS._state["hob"]
    if not st or not _active("heist") then return end
    st.transport = nil
    ARC.once("hob_penalized", function()
        RT.addReputation("Concord", M.CONCORD_DESTROYED, "Hob Works Arc: destroyed a Treasury transport")
    end)
    local x, y = st.tx or 0, st.ty or 0
    st.boxes = {}
    for n = 1, M.WRECK_BOXES do
        local a = math.rad(n * 120)
        local b = Artifact():setPosition(x + math.cos(a) * 800, y + math.sin(a) * 800):allowPickup(true)
        b:setCallSign("Cash box")
        b:setDescriptions("Small object, armoured.",
            "A Concord Treasury cash box, scorched but sealed. Fly into it to take it aboard.")
        b:setScanningParameters(1, 1)
        b:onPickUp(function() _onBox(n) end)
        st.boxes[n] = b
    end
    RT.setObjective(string.format("Cash boxes 0/%d", M.WRECK_BOXES), true, "hob")
    ARC.log(string.format("[Heist] %s is gone. Three cash boxes are tumbling in the wreckage; the fourth went up with the ship.", _TRANSPORT_CS), "#FFAA40")
end

-- The Magpie lost during the heist: the one chance is gone.
RT.on(function(ev)
    if ev.type ~= "ship_lost" or not ev.data.primary or not _active("heist") then return end
    local st = MISSIONS._state["hob"]
    if st then
        ARC.kill(st.boxes); st.boxes = {}
        _heistOver(st, "lost", 0)
    end
end)

local function _tickHeist(st, now)
    local p = ARC.player()
    if not st.departed then
        local left = (st.depart_at or now) - now
        if left <= M.PATROL_PAUSE and not st.patrols_paused then
            st.patrols_paused = true
            _suspendPatrols()   -- the Concord keeps the lanes clear for the convoy
        end
        _timerLine(st, "Departs in " .. _mmss(left))
        if left <= 0 then _depart(st) end
    else
        _timerLine(st, nil)
    end
    _tickTransponder(st, now)

    local t = st.transport
    if RT.valid(t) then st.tx, st.ty = t:getPosition() end

    -- The escorts see the Magpie inside SCAN_R: before departure unless the fake code checks out,
    -- after departure always (the gig is up). Only the Magpie: other ships are just traffic.
    if p and not st.spotted then
        for _, e in ipairs(ARC.alive(st.escorts)) do
            if RT.dist(e, p) < M.SCAN_R and (st.departed or not _codeValid(st, now)) then
                _spot(st, p)
                break
            end
        end
    end

    if st.departed and RT.valid(t) and not st.disabled then
        t:setImpulseMaxSpeed(st.speed, st.speed / 2)
        if _down(t, "impulse") and _down(t, "rearshield") then
            _disable(st)
        else
            local sx, sy = _stationXY(_SENTINEL, -159000, -22000)
            if ARC.near(t, sx, sy, M.ARRIVE_R) then
                ARC.log(string.format("[Heist] %s has reached Sentinel Fleet Yard. The money is gone.", _TRANSPORT_CS), "#FF8080")
                ARC.kill(t); st.transport = nil
                _heistOver(st, "missed", 0)
                return
            end
        end
    end

    if st.disabled and RT.valid(t) and p and p:isDocked(t) then _board(st) end
end

-- ── Hob's Landing: the briefing, the delivery, the payment ──────────────────

local function _pitchLine()
    local s = '"...Which brings us to you. We think we\'ve got a creative way to get the cash. '
    if RT.flag("rezkov_arc_done") == "concord_won" then
        s = s .. 'Rezkov hasn\'t forgotten the Meridian business, but he still says your crew is one of the few capable of pulling off this job'
    else
        s = s .. 'Your friend Rezkov is a supporter of our research and he said your crew is one of the few capable of pulling off this job'
    end
    if RT.flag("ledger_arc_done") == "lost" then s = s .. ', even after the Lumen business' end
    return s .. '. Interested in learning more?"'
end

local function _briefPages()
    local archive = RT.flag("boneyard_hack_done")
    local p1 = archive
        and '"Magpie, it\'s Mara Quill. Thank you for coming.\n\nWe\'ve been through every file you brought out of the Annex. The Maw was no accident. Twenty years ago the Concord ran a program to make the Pale Sun colonists docile, and it worked far better than anyone meant. That is what the Hollow are: those colonists."'
        or  '"Magpie, it\'s Mara Quill. Thank you for coming.\n\nThe Annex archive never came out, so we rebuilt what we could from our own notes. It is enough. The Maw was no accident. Twenty years ago the Concord ran a program to make the Pale Sun colonists docile, and it worked far better than anyone meant. That is what the Hollow are: those colonists."'
    local p2 = '"We\'ve been working with Anton Marchetti, the Works\' chief engineer. He\'s young, and the most brilliant engineer I have ever worked with. His father died in the Settlement War, and he grew up in the Works\' test bays. He looked at our numbers for one night and said it can be undone.\n\nA station broadcasting the right frequency throughout the Maw, held there long enough, puts the Hollow to sleep and then starts to bring them back. The archive calls it the Phase II reversal. We call it Lullaby."'
    local p3 = '"The Concord was very close to building one. It wasn\'t the engineering that stopped them, it was what building it would have admitted.\n\nWe can build it here. The problem is parts: '
        .. _cr(_price()) .. ' credits of components nobody sells on credit'
        .. (archive and '' or ', more than it would be with the archive, since we are working from notes')
        .. ', and the work has stalled."'
    return p1, p2, p3, _pitchLine()
end

local function _convoyPages()
    local boneyard = RT.flag("boneyard_battlegroup_destroyed") or RT.flag("boneyard_fleet_beaten")
    local corsair = RT.flag("corsair_battlegroup_destroyed")
    local why = (boneyard and corsair) and 'The Concord has lost two battle groups, one in the Boneyard and one at Blackwater, and it is trying to rebuild at Sentinel Fleet Yard.'
        or boneyard and 'The Concord lost a battle group in the Boneyard, and it is trying to rebuild at Sentinel Fleet Yard.'
        or corsair and 'The Concord lost a battle group at Blackwater, and it is trying to rebuild at Sentinel Fleet Yard.'
        or 'The Concord is reinforcing its fleet at Sentinel Fleet Yard.'
    local b1 = '"' .. why .. ' The money is going there the old-fashioned way: a one-time Treasury transfer, cash boxes in a transport, leaving Lumen Exchange for Sentinel in '
        .. (M.HEIST_DELAY // 60) .. ' minutes. Take it, and Lullaby gets built and the yard goes without. There is only the one transfer: miss it and it is gone."'
    local b2 = '"What you are up against. CTS Tithe, the Treasury transport: a big, slow-turning hauler, armoured like a vault and about as nimble. One small beam aft to discourage tailgaters. '
        .. 'It won\'t stop for anything: steady speed, all the way to Sentinel. Kill its engines and drop its rear shield, both at once: '
        .. 'hack each one to 90% or shoot it below 10%. Then you can board it. '
        .. 'Blow it up and you\'ll be picking cash boxes out of the wreckage, if they survive."'
    local b3 = '"Two Navy escorts, CNS Surety and CNS Bond: fast, well shielded for their size, a heavy forward beam each. They hunt in a pair and they\'ll break off the convoy to come for you. '
        .. 'Don\'t let them pin you while the transport gets away. Their sensors reach about 15U: sit inside that without a good code and they\'ll see you.\n\n'
        .. 'The ships guarding the Concord ports don\'t go far, but once you\'re wanted, if they see the Magpie within 5U they will come after you."'
    local b4 = '"One more thing. The Concord is really on the lookout for the Magpie. Our engineers can wire a fake transponder into your ship, enabled when needed by your Engineering station. '
        .. 'The Concord rotates its encryption keys, so the code is good for ten minutes from when you throw the switch, and only once. '
        .. 'Use it to get close and scan the convoy before it leaves. Once the shooting starts, the gig is up, and you\'ll have to get creative to get back out of Concord space.\n\n'
        .. 'Bring the cash here. It only counts once it is in our hands. We need the ' .. _cr(_price()) .. '. Any extra credits are yours for the trouble.\n\n'
        .. 'We\'ve put more info in your database. You\'ve got a long haul ahead and need to get going, so you can review it and make a plan on the way."'
    return b1, b2, b3, b4
end

local function _startHeist()
    RT.flag("hob_briefed", true)
    RUMORS.removeCategory("HOB_HOOK")
    MISSIONS.phase("hob", "heist")
end

-- The convoy brief, page by page; "We'll do it." starts the heist.
local function _convoyBrief()
    local b1, b2, b3, b4 = _convoyPages()
    setCommsMessage(b1)
    addCommsReply("Go on.", function()
        setCommsMessage(b2)
        addCommsReply("Go on.", function()
            setCommsMessage(b3)
            addCommsReply("Go on.", function()
                setCommsMessage(b4)
                addCommsReply("We'll do it.", function()
                    _startHeist()
                    setCommsMessage('"Then go. The clock is already running."')
                end)
                addCommsReply("Not right now.", function()
                    setCommsMessage('"Don\'t take long. We\'ll be here."')
                end)
            end)
        end)
    end)
end

local function _meeting()
    local p1, p2, p3, p4 = _briefPages()
    ARC.meet("hob", "quill_profile", "Mara Quill")
    setCommsMessage(p1)
    addCommsReply("Go on.", function()
        ARC.meet("hob", "marchetti_profile", "Anton Marchetti")
        setCommsMessage(p2)
        addCommsReply("Go on.", function()
            setCommsMessage(p3)
            addCommsReply("Go on.", function()
                if not RT.flag("hob_met") then
                    RT.flag("hob_met", true)
                    RUMORS.removeCategory("HOB_HOOK")   -- the message has been delivered
                    ARC.log("[Science] The Works' notes on Lullaby received.", "#00CCAA")   -- SCIDB announces the entry
                    M._addLullabyEntry()
                end
                setCommsMessage(p4)
                addCommsReply("Interested.", function() _convoyBrief() end)
                addCommsReply("Not right now.", function()
                    setCommsMessage('"The offer stands. We\'ll be here."')
                end)
            end)
        end)
    end)
end

local function _pay(price)
    RT.addCredits(-price, "Hob Works Arc: parts for Lullaby")
    RT.flag("hob_paid", true)
    RUMORS.removeCategory("HOB_SHAME")
    RT.flag("hob_arc_done", "funded")
    MISSIONS.phase("hob", "done")
end

local function _paymentReply()
    local price = _price()
    local have = RT.credits()
    if have >= price then
        addCommsReply("Deliver " .. _cr(price) .. " cr to the engineers", function()
            _pay(price)
            setCommsMessage('"These credits will get us what we need, but it is going to take some time. We\'ll reach out again when we have results.\n\nThank you, Magpie. All of you."'
                .. '\n\nAnton Marchetti leans into the channel, grinning. "That transponder of mine worked, didn\'t it? If you ever need one of these for a future job, stop by and I\'ll hook you up for '
                .. RT.TRANSPONDER.cost .. '."')
        end)
    end
end

local function _deliverCash()
    local haul = RT.flag("hob_haul") or 0
    RT.addCredits(haul, "Hob Works Arc: the Treasury cash")
    RT.flag("hob_delivered", true)
    RUMORS.removeCategory("HOB_SHAME")
    local st = MISSIONS._state["hob"]
    if st then st.deliver_due, st.pester_until = nil, nil; _timerLine(st, nil) end
    RT.setObjective("Pay the Works", true, "hob")
end

local function _hobHook(src, tgt, info)
    if not ARC.docked(src, tgt) then return end
    local phase = MISSIONS._cur_phase["hob"]
    if MISSIONS._status["hob"] ~= "active" then return end
    if phase == "hook" then
        if not RT.flag("hob_met") then
            addCommsReply("We got Mara Quill's message.", function() _meeting() end)
        else
            addCommsReply("About Lullaby and the cash...", function()
                setCommsMessage(_pitchLine())
                addCommsReply("Interested.", function() _convoyBrief() end)
                addCommsReply("Not right now.", function() setCommsMessage('"The offer stands."') end)
            end)
        end
    elseif phase == "heist" then
        addCommsReply("Talk to Quill and Marchetti", function()
            setCommsMessage('"What are you doing here? The convoy, Magpie. Go."')
        end)
    elseif phase == "deliver" then
        local haul = RT.flag("hob_haul") or 0
        local price = _price()
        if haul > 0 and not RT.flag("hob_delivered") then
            addCommsReply("We have the cash.", function()
                local late = RT.flag("hob_late")
                _deliverCash()
                setCommsMessage((late and '"Quill looks at the cash boxes for a long moment.\n\n"Better late. Not by much."' or '"Quill counts it twice and laughs.\n\n"You actually did it."')
                    .. '\n\n' .. _cr(haul) .. ' credits. ' .. (haul >= price
                        and ('We need ' .. _cr(price) .. ' of it for Lullaby\'s parts; the other ' .. _cr(haul - price) .. ' is yours for the trouble."')
                        or ('Lullaby\'s parts cost ' .. _cr(price) .. ', so that leaves us ' .. _cr(price - haul) .. ' short. Can you cover the rest?"')))
                _paymentReply()
            end)
        else
            addCommsReply("Talk to Quill and Marchetti", function()
                local have = RT.credits()
                if have >= price then
                    setCommsMessage('"Lullaby needs ' .. _cr(price) .. ' credits of parts. Say the word."')
                    _paymentReply()
                else
                    setCommsMessage('"Lullaby needs ' .. _cr(price) .. ' credits of parts. You are ' .. _cr(price - have)
                        .. ' short. Take some work and come back. We\'re not going anywhere."')
                end
            end)
        end
    end
end

-- ── Science database ────────────────────────────────────────────────────────

local function _lullabyText()
    return table.concat({
        "LULLABY (PHASE II REVERSAL TRANSMITTER)",
        "The Hob Works' name for a broadcast station that reverses the Ashgrave Synthesis. Formally the Phase II reversal transmitter, after the reversal protocol in the Concord's own archive. They call it Lullaby because the first thing it does is put the Hollow to sleep.",
        "",
        "WHAT THE MAW IS",
        "Twenty years ago the Concord ran a program to make the Pale Sun colonists docile. It worked far better than anyone meant. The Hollow are those colonists.",
        "",
        "WHAT IT DOES",
        "Broadcast at the right frequency throughout the Maw, held there long enough, it induces dormancy in the Hollow, then starts to bring them back.",
        "",
        "WHY THE CONCORD NEVER BUILT IT",
        "They were very close. The engineering did not stop them; the political fallout of building and deploying it would have been too great.",
        "",
        "WHAT IT NEEDS",
        "It has to be carried into the Maw, set running within range, and protected for some minutes while it takes hold.",
        "",
        "THE PRICE",
        "Parts the Works cannot get on credit: " .. _cr(M.PRICE) .. " cr with the Ashgrave archive, " .. _cr(M.PRICE_NO_ARCHIVE) .. " cr working from the survivors' notes alone.",
    }, "\n")
end

local function _intelText()
    return table.concat({
        "CONVOY INTEL (from the Hob Works)",
        "A one-time Treasury transfer from Lumen Exchange to Sentinel Fleet Yard: cash boxes in a transport, two Navy escorts.",
        "",
        "CTS TITHE, TREASURY TRANSPORT",
        "Big and slow-turning, armoured like a vault. One small beam aft. It will not stop: steady speed all the way to Sentinel. To board it, its impulse drive and its rear shield must both be down at once: each one hacked to 90% (Relay's hacking screen) or damaged below 10% health (Science's scan). A hack fades, so hack and shoot together. Destroyed, its cash boxes may survive in the wreckage.",
        "",
        "CNS SURETY AND CNS BOND, ESCORTS",
        "Fast, well shielded for their size, a heavy forward beam each. They hunt in a pair and will break off the convoy to come for you.",
        "",
        "SENSORS",
        "The escorts see about 15U. Inside that without a good code, they will see you.",
        "",
        "CONCORD GUARDS",
        "Once the Concord wants you (standing below -200, which the robbery will do): the ships guarding the Concord ports don't go far, but if they see the Magpie within 5U they will come after you, and chase you up to 10U from their port. The lane pickets (CPV Vigilant, CPV Temperance, CNS Lawgiver and CPV Forbearance) see 10U and chase up to 20U from their post.",
        "",
        "THE FAKE TRANSPONDER",
        "On Engineering. Good for ten minutes from the switch (the Concord rotates its keys), once.",
    }, "\n")
end

function M._addLullabyEntry()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["hob_lullaby"] then return end
    SCIDB._entries["hob_lullaby"] = SCIDB.addEntry("lore", "Lullaby (Phase II reversal beacon)", _lullabyText(),
        {["Builder"] = "The Hob Works", ["Effect"] = "Hollow dormancy, reversal", ["Status"] = "Stalled: parts"})
end

local function _addIntelEntry()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["hob_intel"] then return end
    local e = SCIDB.addEntry("lore", "Convoy intel: CTS Tithe", _intelText(),
        {["Route"] = "Lumen to Sentinel", ["Ships"] = "1 transport, 2 escorts", ["Escort sensors"] = "About 15U"})
    SCIDB._entries["hob_intel"] = e
    -- The route map (tools/make_convoy_map.py; EmptyEpsilon reads images from scripts/).
    if e then pcall(function() e:setImage(M.INTEL_MAP) end) end
end

-- ── Rumors ──────────────────────────────────────────────────────────────────

local _SEED_RUMORS = {
    "The Hob Works took in some Concord archive refugees. Quill, the lead one's called. Keeps odd hours with the chief engineer.",
    "Somebody at Hob's Landing has been buying test transmitters. Big ones.",
}

local _HOOK_TEXT = "Mara Quill left a message for your crew. Something about a breakthrough at the Works. She asked you to come by Hob's Landing when you can."

local _SHAME_RUMORS = {
    "Mara Quill says the Works are still waiting on the Magpie. Twenty years those people have been Hollow, and the Magpie is sitting on their cure money.",
    "The Hob Works crew are telling anyone who'll listen that the Magpie took the Treasury's money and kept it.",
    "Word from Hob's Landing: the Magpie can still do the right thing. Quill's waiting.",
}

function M.on_load(st)
    RUMORS.removeCategory("HOB_SEED")
    if RT.flag("hob_arc_done") then return end
    for _, text in ipairs(_SEED_RUMORS) do
        RUMORS.add({text = text, priority = 3, category = "HOB_SEED"})
    end
end

function M.on_unload(st)
    RUMORS.removeCategory("HOB_SEED")
end

local function _hookRumor()
    RUMORS.removeCategory("HOB_HOOK")
    if RT.flag("hob_met") then return end
    RUMORS.add({text = _HOOK_TEXT, priority = 5, faction = "Independent", category = "HOB_HOOK",
        on_heard = function()
            if _active("hook") and not RT.flag("hob_met") then RT.setObjective("Meet Quill at Hob's", false, "hob") end
        end})
end

local function _shame()
    RUMORS.removeCategory("HOB_SHAME")
    for _, text in ipairs(_SHAME_RUMORS) do
        RUMORS.add({text = text, priority = 5, faction = "Independent", category = "HOB_SHAME"})
    end
end

-- ── Cleanup / resolve ───────────────────────────────────────────────────────

local function _clearUI(st)
    _timerLine(st, nil)
    st.timer_text = nil
    _setTransponderUI(st, false, nil)
end

local function _clearWorld(st)
    RT.cancelTimer("hob_cleanup")
    _despawnConvoy(st)
    _clearUI(st)
    _resumePatrols(st)
    RUMORS.removeCategory("HOB_HOOK")
    RUMORS.removeCategory("HOB_SHAME")
    RUMORS.removeCategory("HOB_DONE")
    RT.clearObjective("hob")
end

function M.resolve(st)
    local outcome = RT.flag("hob_arc_done") or "abandoned"
    _clearUI(st)
    _resumePatrols(st)
    RUMORS.removeCategory("HOB_SHAME")
    RUMORS.removeCategory("HOB_HOOK")
    RT.clearObjective("hob")
    if outcome == "funded" then
        ARC.log("[Hob Works] The Works have what they need for Lullaby. Quill will be in touch when they have results.", "#80FF80")
        RT.unlockTransponder()   -- Marchetti's offer: fake transponder codes at the Hob Works shipwright
    else
        ARC.log("[Hob Works] The Works have given up on the Magpie. Lullaby will not be built.", "#FF8080")
    end
    AFTERMATH.sync()
    -- Whatever is left of the convoy leaves the board a little later.
    RT.after(120, function()
        local cur = MISSIONS._state["hob"]
        if cur then _despawnConvoy(cur) end
    end, "hob_cleanup")
end

function M.on_cancel(st)
    _clearWorld(st)
end

-- ── Phases ──────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        ARC.stationHook("Hob's Landing", _hobHook)
        -- Funded before the transponder was for sale (a save from before 2026-11-24): sell it now.
        if RT.flag("hob_arc_done") == "funded" then RT.unlockTransponder(true) end
        -- Paid but the arc never closed (a crash between paying and done): it is funded.
        if RT.flag("hob_paid") and not RT.flag("hob_arc_done") then
            RT.flag("hob_arc_done", "funded")
        end
        ARC.route("hob", {
            {"hob_arc_done", "done"},
            {"hob_heist", "deliver"},
            {"hob_briefed", "heist"},   -- a heist cut short by the session's end starts over
        }, "hook")
    end,
}

M.phases.hook = {
    enter = function(st)
        _hookRumor()
        if RT.flag("hob_met") then RT.setObjective("Meet Quill at Hob's", true, "hob") end
    end,
    exit = function(st)
        RUMORS.removeCategory("HOB_HOOK")
    end,
}

M.phases.heist = {
    enter = function(st)
        st.depart_at = getScenarioTime() + M.HEIST_DELAY
        _spawnConvoy(st)
        _addIntelEntry()
        _setTransponderUI(st, true, nil)
        _explainHeistTransponder()
        RT.setObjective("Rob the convoy", true, "hob")
        ARC.log(string.format("[Heist] The Treasury convoy leaves Lumen Exchange (grid %s) for Sentinel Fleet Yard in %d minutes. Its escorts see about 15U. The fake transponder is on Engineering: ten minutes, once.",
            JOBS.gridRef(_stationXY(_LUMEN, -133000, -75000)), M.HEIST_DELAY // 60), "#A0C0FF")
    end,
    update = function(st, delta, now)
        _tickHeist(st, now)
    end,
    exit = function(st)
        _timerLine(st, nil)
        _setTransponderUI(st, false, nil)
    end,
}

M.phases.deliver = {
    enter = function(st)
        local haul = RT.flag("hob_haul") or 0
        local now = getScenarioTime()
        if haul > 0 and not RT.flag("hob_delivered") then
            if RT.flag("hob_late") then
                st.pester_until = now + M.PESTER_TIME
                _shame()
                RT.setObjective("Cash to Hob's", true, "hob")
            else
                st.deliver_due = now + M.DELIVER_TIME
                RT.setObjective("Cash to Hob's", true, "hob")
                ARC.log(string.format("[Hob Works] Bring the cash to Hob's Landing within %d minutes. It only counts once it is in the Works' hands.",
                    M.DELIVER_TIME // 60), "#A0C0FF")
            end
        else
            RT.setObjective("Pay the Works", true, "hob")
            if haul == 0 and not RT.flag("hob_delivered") then
                ARC.log(string.format("[Hob Works] No cash from the convoy. Lullaby still needs %s cr: the job boards will have to pay for it.",
                    _cr(_price())), "#FFAA40")
            end
        end
    end,
    update = function(st, delta, now)
        _tickChase(st)
        -- Escorts still out there lose the Magpie once it is well away; the emptied transport is
        -- towed off once the Magpie has left it.
        local p = ARC.player()
        for i, e in ipairs(st.escorts or {}) do
            if RT.valid(e) and (not p or RT.dist(e, p) > 20 * U) then ARC.kill(e); st.escorts[i] = nil end
        end
        if RT.valid(st.transport) and (not p or RT.dist(st.transport, p) > 10 * U) then
            ARC.kill(st.transport); st.transport = nil
        end
        if st.deliver_due then
            local left = st.deliver_due - now
            _timerLine(st, "Deliver by " .. _mmss(left))
            if left <= 0 then
                st.deliver_due = nil
                RT.flag("hob_late", true)
                local ind = RT.getReputation("Independent") or 0
                RT.addReputation("Independent", M.LATE_INDEPENDENT - ind, "Hob Works Arc: kept the Treasury cash")
                ARC.log("[Hob Works] The cash never reached Hob's Landing. Word is spreading. The Works will still take it, for now.", "#FF8080")
                st.pester_until = now + M.PESTER_TIME
                _shame()
            end
        elseif st.pester_until then
            _timerLine(st, nil)
            if now >= st.pester_until then
                st.pester_until = nil
                RT.flag("hob_arc_done", "abandoned")
                MISSIONS.phase("hob", "done")
            end
        else
            _timerLine(st, nil)
        end
    end,
    exit = function(st)
        _timerLine(st, nil)
        RUMORS.removeCategory("HOB_SHAME")
    end,
}

-- ── Trigger: the three Phase II arcs over, then five board jobs ─────────────

local function _jobsDone()
    local rec = RT.shipRecord()
    return rec and rec.jobs_done or 0
end

-- Rezkov over, and Ledger, Boneyard (with the survivors rescued) and Corsair finished. Also keeps the
-- job count's starting point (hob_jobs_base): noted the first time this holds, forgotten if the GM
-- rewinds one of them (the Ledger arc's pattern: requires runs every frame).
local function _phaseTwoOver()
    local over = (RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined"))
        and RT.flag("ledger_arc_done") and RT.flag("boneyard_arc_done") and RT.flag("boneyard_buoy_found")
        and RT.flag("corsair_arc_done")
    over = over and true or false
    if not RT.campaign then return over end
    local base = RT.flag("hob_jobs_base")
    if over and base == nil then
        RT.flag("hob_jobs_base", _jobsDone())
    elseif not over and base ~= nil then
        RT.clearFlag("hob_jobs_base")
    end
    return over
end

M.triggers = {
    not_flagged    = {"hob_arc_done"},
    requires       = _phaseTwoOver,
    requires_label = "Rezkov over; Ledger, Boneyard (survivors rescued) and Corsair arcs finished",
    custom = function()
        if not _phaseTwoOver() then return false end
        return _jobsDone() - (RT.flag("hob_jobs_base") or _jobsDone()) >= M.JOBS_AFTER_PHASE2
    end,
    custom_label = function()
        local base = RT.flag("hob_jobs_base")
        local n = base ~= nil and math.max(0, _jobsDone() - base) or 0
        local now = n >= M.JOBS_AFTER_PHASE2 and (M.JOBS_AFTER_PHASE2 .. "+") or tostring(n)
        return M.JOBS_AFTER_PHASE2 .. " board jobs done by the primary ship since then  (now: " .. now .. ")"
    end,
}

M.phase_order = {"init", "hook", "heist", "deliver"}

-- ── GM console ──────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"hob_"}

M.flags = {
    hob_jobs_base    = "board jobs the primary ship had done when the Phase II arcs were first all over (the hook waits for M.JOBS_AFTER_PHASE2 more)",
    hob_met          = "the crew met Quill and Marchetti at Hob's Landing (the Lullaby Science DB entry)",
    hob_briefed      = "took the heist (the convoy intel Science DB entry)",
    hob_heist        = 'how the heist ended: "boarded" | "destroyed" | "missed" (reached Sentinel) | "lost" (the Magpie was lost)',
    hob_haul         = "credits the crew took from the convoy (12000 boarded, 9000 from the wreck); counts once delivered",
    hob_penalized    = "the Concord standing loss for the robbery was applied (once)",
    hob_delivered    = "the cash was handed over at Hob's Landing",
    hob_late         = "the delivery deadline passed (Independent standing set to -100; the Works pester the crew)",
    hob_paid         = "the crew paid the Works for Lullaby's parts",
    hob_arc_done     = 'outcome: "funded" (paid; Lullaby is picked up in a later mission) | "abandoned" (the cash never reached the Works)',
    ["hob_met_*"]    = "Science DB profile met in this arc (quill, marchetti), set by ARC.meet",
}
M.reads = {"rezkov_arc_done", "rezkov_declined", "ledger_arc_done", "boneyard_arc_done", "boneyard_buoy_found",
           "boneyard_hack_done", "boneyard_battlegroup_destroyed", "boneyard_fleet_beaten", "corsair_arc_done", "corsair_battlegroup_destroyed"}
M.keep_flags = {"hob_jobs_base"}

M.gm_state_fn = function()
    local st = MISSIONS._state["hob"] or {}
    local ph = MISSIONS._cur_phase["hob"]
    if MISSIONS._status["hob"] == "done" then return "Complete (" .. tostring(RT.flag("hob_arc_done")) .. ")" end
    if ph == "heist" then
        if not st.departed then
            return string.format("Convoy departs in %s", _mmss((st.depart_at or 0) - getScenarioTime()))
        end
        return string.format("Convoy running, transport %d u/s%s", st.speed or 0, st.disabled and " (disabled)" or "")
    end
    if ph == "deliver" then return string.format("Deliver (haul %s cr)", _cr(RT.flag("hob_haul") or 0)) end
    return ph or MISSIONS._status["hob"]
end

M.gm_reset = function(st, target)
    _clearWorld(st)
    RT.lockTransponder()   -- "→ Done: Funded" unlocks it again when it resolves
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("hob", function(name)
        if name == "hob_penalized" then return target == "done" end
        return false
    end)
end

M.completed = {
    hook = function(st)
        RT.flag("hob_met", true)
        RT.flag("hob_briefed", true)
        ARC.meet("hob", "quill_profile", "Mara Quill")
        ARC.meet("hob", "marchetti_profile", "Anton Marchetti")
    end,
    heist = function(st)
        RT.flag("hob_heist", "boarded")
        RT.flag("hob_haul", M.HAUL_BOARDED)
    end,
    deliver = function(st)
        RT.flag("hob_delivered", true)
        RT.flag("hob_paid", true)
    end,
}

local _jump = ARC.jumper("hob")

M.gm_states = {
    {key = "hook",    label = "→ Hook",    fn = _jump("hook")},
    {key = "heist",   label = "→ Heist",   fn = _jump("heist")},
    {key = "deliver", label = "→ Deliver", fn = _jump("deliver")},
    {key = "done_funded",    label = "→ Done: Funded",    fn = _jump("done", function() RT.flag("hob_arc_done", "funded") end)},
    {key = "done_abandoned", label = "→ Done: Abandoned", fn = _jump("done", function()
        RT.flag("hob_late", true)
        RT.flag("hob_arc_done", "abandoned")
    end, {skip = {deliver = true}})},
}

M.gm_actions = {
    -- Travel shortcuts for playtesting (the arc ship to 5U from where the phase sends it).
    ARC.travel("Hob's", {"hook", "deliver"}, "Hob's Landing"),
    ARC.travel("Lumen", {"heist"}, _LUMEN),
    ARC.travel("Tithe", {"heist"}, function(st) return st.transport end),
    {label = "Satisfy done jobs", phases = {"inactive"}, fn = function(st)
        if not _phaseTwoOver() then
            local missing = {}
            if not (RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined")) then missing[#missing + 1] = "Rezkov not over" end
            if not RT.flag("ledger_arc_done") then missing[#missing + 1] = "Ledger not done" end
            if not RT.flag("boneyard_arc_done") then missing[#missing + 1] = "Boneyard not done" end
            if not RT.flag("boneyard_buoy_found") then
                missing[#missing + 1] = "Boneyard survivors not rescued (Boneyard → Report or → Done sets it)"
            end
            if not RT.flag("corsair_arc_done") then missing[#missing + 1] = "Corsair not done" end
            addGMMessage("The job count starts when the Phase II arcs are all over. Missing: "
                .. table.concat(missing, "; ") .. ".")
            return
        end
        RT.flag("hob_jobs_base", _jobsDone() - M.JOBS_AFTER_PHASE2)
    end},
    {label = "Depart now", phases = {"heist"}, fn = function(st)
        if not st.departed then st.depart_at = getScenarioTime() end
    end},
    {label = "Transport faster", phases = {"heist"}, fn = function(st)
        st.speed = st.speed + M.SPEED_STEP
        addGMMessage(string.format("CTS Tithe: %d u/s (%.1fU a minute).", st.speed, st.speed * 60 / 1000))
    end},
    {label = "Transport slower", phases = {"heist"}, fn = function(st)
        st.speed = math.max(M.SPEED_STEP, st.speed - M.SPEED_STEP)
        addGMMessage(string.format("CTS Tithe: %d u/s (%.1fU a minute).", st.speed, st.speed * 60 / 1000))
    end},
    {label = "Disable transport", phases = {"heist"}, fn = function(st)
        if not st.departed then _depart(st) end
        _disable(st)
    end},
    {label = "Kill escorts", phases = {"heist", "deliver"}, fn = function(st)
        ARC.kill(st.escorts); st.escorts = {}
    end},
    {label = "Give cash", phases = {"heist"}, fn = function(st)
        ARC.kill(st.transport); st.transport = nil
        _heistOver(st, "boarded", M.HAUL_BOARDED)
    end},
}

-- The Science DB follows the flags (SCIDB.sync at session start and after every GM jump).
if SCIDB and SCIDB.rule then
    SCIDB.rule("hob_lullaby", {want = function() return RT.flag("hob_met") end, add = function() M._addLullabyEntry() end})
    SCIDB.rule("hob_intel",   {want = function() return RT.flag("hob_briefed") end, add = function() _addIntelEntry() end})
end

if ACH and ACH.define then
    ACH.define{id = "train_job", name = "The Train Job", category = "story", hidden = true,
        desc = "Rob the Treasury convoy and pay for Lullaby.",
        check = function(s) return s.arcs.hob ~= nil and (s.arcs.hob.completed or 0) > 0 and RT.flag("hob_arc_done") == "funded" end}
end

MISSIONS.register(M)
