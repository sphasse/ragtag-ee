-- ee/ragtag/missions/icehaul.lua
-- Ice Haul: a short one-off job, and the first use of a tow line. Hob's Landing's water reclaimers
-- are failing and a comet broke up passing Kestrel; the Landing's water office pays for the biggest
-- piece, towed home. The first time the line goes on, two raiders (TOW.intercept, posing as rival
-- recovery outfits) come for the ice from 10U out. GM guide: docs/GM_ICEHAUL_MISSION.md
--
-- Structure: init -> hook -> haul -> done ("delivered" | "lost")
--   hook     a seed rumor at Independent ports; docked at Hob's Landing, the water office's
--            [SPECIAL] reply.
--   haul     the iceberg drifts round Kestrel (the engine's orbit component). The tow line is TOW
--            (ee/ragtag/tow.lua): within TOW.REACH Engineering attaches it, the berg trails TOW.LENGTH
--            behind, hauling costs energy, faster than half of warp 1 snaps it (the berg stays where it is).
--            The berg within DELIVER_R of Hob's Landing: delivered (PAY, Independent +REP).
--   lost     the Magpie lost while hauling (the berg is still out there; nothing to pay).

local M = {}
M.id             = "icehaul"
M.name           = "Ice Haul"
M.repeatable     = false
M.locks_jobs     = false
M.auto_start     = true
M.start_phase    = "init"
M.no_auto_cancel = true

local U = 1000

-- ── Tuning ──────────────────────────────────────────────────────────────────
M.PAY         = 1500
M.REP         = 75
M.DELIVER_R   = 4000    -- the berg this close to Hob's Landing: delivered
-- The berg drifts round Kestrel (120, 36): ORBIT_R from the sun, starting at ORBIT_START degrees
-- (0 = east, 90 = south), one turn in ORBIT_PERIOD s (about 1.7U a minute).
M.KESTREL      = {x = 120, y = 36}
M.ORBIT_R      = 16
M.ORBIT_START  = 160
M.ORBIT_PERIOD = 3600
M.RAIDERS      = 2      -- raiders who come for the ice when the line first goes on (TOW.intercept)

local _HOB = "Hob's Landing"
local _BERG_CS = "Kestrel Ice"

function M.init_state()
    return {
        berg     = nil,    -- the iceberg (the entity)
        towing   = false,
        tow_ship = nil,    -- the ship it is tied to
        raided   = false,  -- the raiders have come (once a session)
        raiders  = nil,    -- their ships
    }
end

-- ── Small helpers ───────────────────────────────────────────────────────────

local function _active(phase)
    return MISSIONS._status["icehaul"] == "active" and (phase == nil or MISSIONS._cur_phase["icehaul"] == phase)
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

local function _hob()
    local h = RT.find(_HOB)
    return RT.valid(h) and h or nil
end

local function _sector(x, y)
    local ok, s = pcall(getSectorName, x, y)
    return ok and s or "?"
end

-- ── The iceberg ─────────────────────────────────────────────────────────────

-- An asteroid that doesn't explode on touch and that the AI doesn't steer round: a big, pale rock
-- on radar, scannable for its description.
local function _spawnBerg(st)
    if RT.valid(st.berg) then return st.berg end
    local a = math.rad(M.ORBIT_START)
    local kx, ky = M.KESTREL.x * U, M.KESTREL.y * U
    local b = Asteroid():setPosition(kx + math.cos(a) * M.ORBIT_R * U, ky + math.sin(a) * M.ORBIT_R * U)
    b:setSize(400)
    b.components.explode_on_touch = nil
    b.components.avoid_object = nil
    pcall(function()
        b.components.radar_trace = {icon = "radar/blip.png", radius = 600, min_size = 10.0,
                                    color = {170, 220, 255, 255}, rotate = false}
    end)
    b:setCallSign(_BERG_CS)
    pcall(function()
        b:setDescriptions("A large chunk of ice.",
            "A fragment of the comet that broke up passing Kestrel: about forty thousand tonnes of dirty water ice.")
    end)
    b.components.orbit = {center = {kx, ky}, distance = M.ORBIT_R * U, time = M.ORBIT_PERIOD}
    st.berg = b
    return b
end

-- The berg goes on TOW's list for the arc ship (ee/ragtag/tow.lua: the line, the energy it costs,
-- the speed limit, Engineering's button). The state mirrors whether it is on the line.
local function _st() return MISSIONS._state["icehaul"] end

local function _offerTow(st)
    if not RT.valid(st.berg) then return end
    TOW.offer(st.berg, {ship = ARC.player(), name = "The ice",
        on_attach = function(ship, obj)
            local s = _st()
            if s then s.towing, s.tow_ship = true, ship end
            if _active("haul") then RT.setObjective("Tow it to Hob's", true, "icehaul") end
            if s and _active("haul") and not s.raided then
                s.raided = true
                s.raiders = TOW.intercept(ship, obj, M.RAIDERS, {hail =
                    '"That\'s a lot of ice for one little freighter. Here\'s how this goes: you cut it loose, we tow it '
                    .. 'somewhere that pays better than Hob\'s, and you fly home with all your paint. Finders keepers, '
                    .. 'and we saw that comet break up first."'})
            end
        end,
        on_release = function(ship, obj, why)
            local s = _st()
            if s then s.towing, s.tow_ship = false, nil end
            if _active("haul") and (why == "cast off" or why == "snapped") then
                RT.setObjective("Pick up the ice", true, "icehaul")
            end
        end})
end

-- Let go of the berg where it is (it stops drifting round Kestrel: it is out of its orbit now).
function M.release(st)
    if RT.valid(st.berg) then
        TOW.release(st.berg)
        st.berg.components.orbit = nil
    end
    st.towing, st.tow_ship = false, nil
end

-- For tests and the GM: what Engineering's button does, and what it reads.
function M.towPressed() local p = ARC.player(); if p then TOW.press(p) end end
function M.buttonLabel() return TOW.buttonLabel(ARC.player()) end

local function _finish(outcome)
    RT.flag("icehaul_arc_done", outcome)
    MISSIONS.phase("icehaul", "done")
end

local function _tickHaul(st, delta, now)
    if not RT.valid(st.berg) then _spawnBerg(st); _offerTow(st) end
    local h = _hob()
    if h and RT.valid(st.berg) and RT.dist(h, st.berg) <= M.DELIVER_R then
        TOW.withdraw(st.berg)
        M.release(st)
        TOW.breakOff(st.raiders)
        ARC.once("icehaul_rewarded", function()
            RT.addCredits(M.PAY, "Ice Haul: the Kestrel ice delivered")
            RT.addReputation("Independent", M.REP, "Ice Haul: the Kestrel ice delivered")
        end)
        local msg = '"We have it. Tugs are on their way out to take it in." A pause, and somebody cheering in the background. "'
            .. _cr(M.PAY) .. ' credits, and the Landing drinks this month. Thank you, Magpie."'
        if not ARC.hail(h, msg, "Hob's Landing water office") then ARC.log("[Hob's Landing] " .. msg, "#C0C0FF") end
        _finish("delivered")
    end
end

-- ── Rumors ──────────────────────────────────────────────────────────────────

local _SEED = "Hob's Landing is paying for ice. A comet broke up passing Kestrel, and the Landing's reclaimers are failing. Nobody out here owns a tow rig, but they'll fit you one."

local function _seedRumors()
    RUMORS.removeCategory("ICEHAUL_SEED")
    if RT.flag("icehaul_briefed") then return end
    RUMORS.add({text = _SEED, priority = 3, faction = "Independent", category = "ICEHAUL_SEED",
        on_heard = function()
            if _active("hook") then RT.setObjective("Hob's Landing", false, "icehaul") end
        end})
end

-- ── The water office's offer ────────────────────────────────────────────────

local function _offer()
    local a = math.rad(M.ORBIT_START)
    local sx = (M.KESTREL.x + math.cos(a) * M.ORBIT_R) * U
    local sy = (M.KESTREL.y + math.sin(a) * M.ORBIT_R) * U
    setCommsMessage('The water office is a cramped room with a gauge on every wall, all of them low. '
        .. '"Two of our three reclaimers are down and the parts are a month out. We\'re rationing."\n\n'
        .. '"A comet broke up passing Kestrel last week. The biggest piece is drifting round the sun, near '
        .. _sector(sx, sy) .. ', about forty thousand tonnes of ice. Tow it here, within '
        .. math.floor(M.DELIVER_R / U) .. 'U of the Landing, and our tugs take it from there. '
        .. _cr(M.PAY) .. ' credits."')
    addCommsReply("How do we tow it?", function()
        setCommsMessage('"We\'ll fit a tow rig before you leave. Get within ' .. math.floor(TOW.REACH / U)
            .. 'U of the ice and your engineer makes it fast. Hauling it eats power, and the line takes ' .. TOW.LIMIT_TEXT
            .. ', no more: warp 1 with your warp drive at half power, about. Have your science officer watch the speed. '
            .. 'Any faster and it snaps, and you go back for the ice."\n\n"And watch yourselves. Every scavenger '
            .. 'in the Rim saw that comet break up. Once the ice is on your line, somebody\'s going to want it."')
        addCommsReply("We'll fetch it.", function()
            RT.flag("icehaul_briefed", true)
            MISSIONS.phase("icehaul", "haul")
            setCommsMessage('"Rig\'s on. Kestrel\'s the gold one. Don\'t fly into it."')
        end)
        addCommsReply("Not right now.", function()
            setCommsMessage('"It isn\'t going anywhere fast. Neither is our water."')
        end)
    end)
end

local function _hobHook(src, tgt, info)
    if not ARC.docked(src, tgt) then return end
    if not _active("hook") then return end
    addCommsReply("[SPECIAL] The water office", _offer)
end

-- The Magpie lost while hauling.
RT.on(function(ev)
    if ev.type ~= "ship_lost" or not ev.data.primary or not _active("haul") then return end
    _finish("lost")
end)

-- ── Science database ────────────────────────────────────────────────────────

function M._addJobEntry()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["icehaul_job"] then return end
    SCIDB._entries["icehaul_job"] = SCIDB.addEntry("lore", "The Kestrel ice", table.concat({
        "THE JOB",
        "Tow the biggest fragment of the Kestrel comet to Hob's Landing, whose water reclaimers are failing. The water office pays " .. _cr(M.PAY) .. " cr.",
        "",
        "THE ICE",
        "About forty thousand tonnes, drifting round Kestrel " .. M.ORBIT_R .. "U out. It shows pale blue on radar as " .. _BERG_CS .. ".",
        "",
        "THE TOW",
        "Within " .. math.floor(TOW.REACH / U) .. "U of the ice, Engineering attaches the tow line. The ice trails " .. (TOW.LENGTH / U)
            .. "U behind; moving it costs up to " .. TOW.DRAIN .. " energy a second at full impulse. The line's limit is " .. TOW.LIMIT_TEXT .. ": warp 1 with the warp drive at about half power, Science watching the tow speed. Anything faster snaps it. "
            .. "Bring the ice within " .. math.floor(M.DELIVER_R / U) .. "U of Hob's Landing.",
    }, "\n"), {["Pay"] = _cr(M.PAY) .. " cr", ["Where"] = "Round Kestrel", ["Deliver to"] = _HOB})
end

-- ── Cleanup / resolve ───────────────────────────────────────────────────────

local function _clearWorld(st)
    if st.berg then TOW.withdraw(st.berg) end
    M.release(st)
    ARC.kill(st.berg); st.berg = nil
    TOW.removeRaiders(st.raiders); st.raiders = nil
    RUMORS.removeCategory("ICEHAUL_SEED")
    RUMORS.removeCategory("ICEHAUL_DONE")
    RT.clearObjective("icehaul")
end

function M.resolve(st)
    RUMORS.removeCategory("ICEHAUL_SEED")
    RT.clearObjective("icehaul")
    if st.berg then TOW.withdraw(st.berg) end
    M.release(st)
    if RT.flag("icehaul_arc_done") == "delivered" then
        -- Hob's tugs take it in.
        RT.after(20, function()
            local cur = MISSIONS._state["icehaul"]
            if cur then
                ARC.kill(cur.berg); cur.berg = nil
                TOW.removeRaiders(cur.raiders); cur.raiders = nil
            end
        end, "icehaul_cleanup")
    else
        TOW.removeRaiders(st.raiders); st.raiders = nil
    end
    AFTERMATH.sync()
end

function M.on_cancel(st)
    RT.cancelTimer("icehaul_cleanup")
    _clearWorld(st)
end

-- ── Phases ──────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        ARC.stationHook(_HOB, _hobHook)
        ARC.route("icehaul", {
            {"icehaul_arc_done", "done"},
            {"icehaul_briefed", "haul"},   -- the ice is back where it started next session
        }, "hook")
    end,
}

M.phases.hook = {
    enter = function(st) _seedRumors() end,
    exit = function(st) RUMORS.removeCategory("ICEHAUL_SEED") end,
}

M.phases.haul = {
    enter = function(st)
        M._addJobEntry()
        _spawnBerg(st)
        _offerTow(st)
        st.towing = false
        RT.setObjective("Pick up the ice", true, "icehaul")
        local x, y = st.berg:getPosition()
        ARC.log("[Ice Haul] The Kestrel ice is drifting round Kestrel, near " .. _sector(x, y)
            .. ". Get within " .. math.floor(TOW.REACH / U) .. "U; Engineering attaches the line.", "#A0E0FF")
    end,
    update = function(st, delta, now) _tickHaul(st, delta, now) end,
}

-- ── Trigger: Rezkov over ────────────────────────────────────────────────────

M.triggers = {
    not_flagged    = {"icehaul_arc_done"},
    requires       = function() return (RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined")) and true or false end,
    requires_label = "Rezkov over (or declined)",
}

M.phase_order = {"init", "hook", "haul"}

-- ── GM console ──────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"icehaul_"}

M.flags = {
    icehaul_briefed  = "took the water office's job (the Kestrel ice Science DB entry)",
    icehaul_rewarded = "paid (once)",
    icehaul_arc_done = 'outcome: "delivered" (the ice at Hob\'s Landing) | "lost" (the Magpie lost while hauling)',
}
M.reads = {"rezkov_arc_done", "rezkov_declined"}

M.gm_state_fn = function()
    local st = MISSIONS._state["icehaul"] or {}
    local ph = MISSIONS._cur_phase["icehaul"]
    if MISSIONS._status["icehaul"] == "done" then return "Complete (" .. tostring(RT.flag("icehaul_arc_done")) .. ")" end
    if ph == "haul" then
        local h = _hob()
        local d = (h and RT.valid(st.berg)) and string.format("%.0fU", RT.dist(h, st.berg) / U) or "?"
        return (st.towing and "Towing, " or "Adrift, ") .. d
    end
    return ph or MISSIONS._status["icehaul"]
end

M.gm_reset = function(st, target)
    RT.cancelTimer("icehaul_cleanup")
    _clearWorld(st)
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("icehaul", function(name) return false end)
end

M.completed = {
    hook = function(st) RT.flag("icehaul_briefed", true) end,
}

local _jump = ARC.jumper("icehaul")

M.gm_states = {
    {key = "hook", label = "→ Hook", fn = _jump("hook")},
    {key = "haul", label = "→ Haul", fn = _jump("haul")},
    {key = "done_delivered", label = "→ Done: Delivered", fn = _jump("done", function() RT.flag("icehaul_arc_done", "delivered") end)},
    {key = "done_lost",      label = "→ Done: Lost",      fn = _jump("done", function() RT.flag("icehaul_arc_done", "lost") end)},
}

M.gm_actions = {
    ARC.travel("Hob's", {"hook"}, _HOB),
    ARC.travel("Ice", {"haul"}, function(st) return st.berg end),
    {label = "Attach the line", phases = {"haul"}, fn = function(st)
        local p = ARC.player()
        if not p or not RT.valid(st.berg) then return end
        if not st.towing then
            local bx, by = st.berg:getPosition()
            local px, py = p:getPosition()
            local d = math.max(1, ARC.dist(px, py, bx, by))
            if d > TOW.REACH then st.berg:setPosition(px + (bx - px) / d * TOW.LENGTH, py + (by - py) / d * TOW.LENGTH) end
            TOW.attach(p, st.berg)
        end
    end},
}

-- The Science DB follows the flags (SCIDB.sync at session start and after every GM jump).
if SCIDB and SCIDB.rule then
    SCIDB.rule("icehaul_job", {want = function() return RT.flag("icehaul_briefed") end, add = function() M._addJobEntry() end})
end

if ACH and ACH.define then
    ACH.define{id = "water_bearer", name = "Water Bearer", category = "story", hidden = true,
        desc = "Tow forty thousand tonnes of comet ice to Hob's Landing.",
        check = function(s) return RT.flag("icehaul_arc_done") == "delivered" end}
end

MISSIONS.register(M)
