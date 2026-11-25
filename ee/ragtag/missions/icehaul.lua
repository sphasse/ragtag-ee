-- ee/ragtag/missions/icehaul.lua
-- Ice Haul: a short one-off job, and the first use of a tow line. Hob's Landing's water reclaimers
-- are failing and a comet broke up passing Kestrel; the Landing's water office pays for the biggest
-- piece, towed home. No resistance: the job is the tow. GM guide: docs/GM_ICEHAUL_MISSION.md
--
-- Structure: init -> hook -> haul -> done ("delivered" | "lost")
--   hook     a seed rumor at Independent ports; docked at Hob's Landing, the water office's
--            [SPECIAL] reply.
--   haul     the iceberg drifts round Kestrel (the engine's orbit component). Within TOW_REACH,
--            Engineering attaches a tow line: the berg trails TOW_LENGTH behind (setOrbit(ship, 0)),
--            and moving it costs energy (TOW_DRAIN a second at full impulse). Spinning up the warp drive snaps the line (the berg stays
--            where it is). The berg within DELIVER_R of Hob's Landing: delivered (PAY, Independent +REP).
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
M.TOW_REACH   = 2000    -- Engineering can attach the line within this of the berg
M.TOW_LENGTH  = 1500    -- the line's length: the berg trails this far behind
M.TOW_DRAIN   = 3       -- extra energy a second while towing at full impulse (less at part throttle, none stopped)
M.DELIVER_R   = 4000    -- the berg this close to Hob's Landing: delivered
-- The berg drifts round Kestrel (120, 36): ORBIT_R from the sun, starting at ORBIT_START degrees
-- (0 = east, 90 = south), one turn in ORBIT_PERIOD s (about 1.7U a minute).
M.KESTREL      = {x = 120, y = 36}
M.ORBIT_R      = 16
M.ORBIT_START  = 160
M.ORBIT_PERIOD = 3600

local _HOB = "Hob's Landing"
local _BERG_CS = "Kestrel Ice"
local _BUTTON_STATIONS = {"engineering", "engineering+", "singlepilot"}

function M.init_state()
    return {
        berg     = nil,    -- the iceberg (the entity)
        towing   = false,
        tow_ship = nil,    -- the ship it is tied to
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

-- The tow's energy cost a second right now: TOW_DRAIN at full impulse (either way), scaled by the
-- throttle the engines are actually giving; nothing while stopped.
function M.towDrain(p)
    local ok, actual = pcall(function() local e = p.components.impulse_engine; return e and e.actual or 0 end)
    return M.TOW_DRAIN * math.min(1, math.abs(ok and actual or 0))
end

local function _drainInfo(p, on)
    for _, pos in ipairs({"engineering", "engineering+"}) do
        pcall(function()
            if on then p:addCustomInfo(pos, "icehaul_load_" .. pos, string.format("Tow load: up to -%d energy/s", M.TOW_DRAIN), 5)
            else p:removeCustom("icehaul_load_" .. pos) end
        end)
    end
end

function M.attach(st)
    local p, b = ARC.player(), st.berg
    if not p or not RT.valid(b) or st.towing then return false end
    b.components.orbit = {target = p, center = {p:getPosition()}, distance = M.TOW_LENGTH, time = 0}
    st.towing, st.tow_ship = true, p
    _drainInfo(p, true)
    ARC.log(string.format("[Engineering] Tow line fast. The ice trails %.1fU behind. Hauling it costs up to %d energy a second "
        .. "on impulse; don't spin up the warp drive with the line on.", M.TOW_LENGTH / U, M.TOW_DRAIN), "#A0E0FF")
    RT.setObjective("Tow it to Hob's", true, "icehaul")
    return true
end

-- Let go of the berg where it is (it stops drifting round Kestrel: it is out of its orbit now).
function M.release(st, why)
    local b = st.berg
    if RT.valid(b) then b.components.orbit = nil end
    if st.tow_ship and RT.valid(st.tow_ship) then _drainInfo(st.tow_ship, false) end
    local was = st.towing
    st.towing, st.tow_ship = false, nil
    if was and why then
        ARC.log(why, "#FFAA40")
        if _active("haul") then RT.setObjective("Pick up the ice", true, "icehaul") end
    end
end

local function _bergNear(p, st)
    if not p or not RT.valid(st.berg) then return false end
    return RT.dist(p, st.berg) <= M.TOW_REACH
end

-- Engineering's button: attach when close, release when towing.
function M.towPressed()
    local st = MISSIONS._state["icehaul"]
    if not st or not _active("haul") then return end
    if st.towing then
        M.release(st, "[Engineering] Tow line cast off. The ice is adrift.")
    elseif _bergNear(ARC.player(), st) then
        M.attach(st)
    end
end

local _shown = {}   -- the label each ship's button shows (false: none)

local function _setButton(p, label)
    if _shown[p] == label then return end
    _shown[p] = label
    for _, pos in ipairs(_BUTTON_STATIONS) do
        pcall(function()
            if label then p:addCustomButton(pos, "icehaul_tow_" .. pos, label, M.towPressed, 6)
            else p:removeCustom("icehaul_tow_" .. pos) end
        end)
    end
end

local function _updateButton(st)
    local p = ARC.player()
    if not p then return end
    local label = false
    if _active("haul") then
        if st.towing then label = "Release tow line"
        elseif _bergNear(p, st) then label = "Attach tow line" end
    end
    _setButton(p, label)
end
M.buttonLabel = function() local p = ARC.player(); return p and _shown[p] or false end

local function _clearButtons()
    for p, label in pairs(_shown) do
        if label and RT.valid(p) then _setButton(p, false) end
    end
    _shown = {}
end

local function _warping(p)
    local ok, cur = pcall(function() local w = p.components.warp_drive; return w and w.current or 0 end)
    return ok and (cur or 0) > 0.01
end

local function _finish(outcome)
    RT.flag("icehaul_arc_done", outcome)
    MISSIONS.phase("icehaul", "done")
end

local function _tickHaul(st, delta, now)
    if not RT.valid(st.berg) then _spawnBerg(st) end
    if st.towing then
        local p = st.tow_ship
        if not RT.valid(p) or p ~= ARC.player() then
            M.release(st)
        elseif _warping(p) then
            M.release(st, "[Engineering] The tow line snapped when the warp drive spun up. The ice is adrift: go back for it.")
        else
            local d = M.towDrain(p) * (delta or 0)
            if d > 0 then p:setEnergyLevel(math.max(0, p:getEnergy() - d)) end
        end
    end
    local h = _hob()
    if h and RT.valid(st.berg) and RT.dist(h, st.berg) <= M.DELIVER_R then
        M.release(st)
        ARC.once("icehaul_rewarded", function()
            RT.addCredits(M.PAY, "Ice Haul: the Kestrel ice delivered")
            RT.addReputation("Independent", M.REP, "Ice Haul: the Kestrel ice delivered")
        end)
        local msg = '"We have it. Tugs are on their way out to take it in." A pause, and somebody cheering in the background. "'
            .. _cr(M.PAY) .. ' credits, and the Landing drinks this month. Thank you, Magpie."'
        if not ARC.hail(h, msg, "Hob's Landing water office") then ARC.log("[Hob's Landing] " .. msg, "#C0C0FF") end
        _finish("delivered")
        return
    end
    _updateButton(st)
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
        setCommsMessage('"We\'ll fit a tow rig before you leave. Get within ' .. math.floor(M.TOW_REACH / U)
            .. 'U of the ice and your engineer makes it fast. Hauling it eats power, and don\'t touch the warp drive '
            .. 'with the line on: it snaps, and you go back for the ice."')
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
        "Within " .. math.floor(M.TOW_REACH / U) .. "U of the ice, Engineering attaches the tow line. The ice trails " .. (M.TOW_LENGTH / U)
            .. "U behind; moving it costs up to " .. M.TOW_DRAIN .. " energy a second at full impulse. Spinning up the warp drive snaps the line. "
            .. "Bring the ice within " .. math.floor(M.DELIVER_R / U) .. "U of Hob's Landing.",
    }, "\n"), {["Pay"] = _cr(M.PAY) .. " cr", ["Where"] = "Round Kestrel", ["Deliver to"] = _HOB})
end

-- ── Cleanup / resolve ───────────────────────────────────────────────────────

local function _clearWorld(st)
    M.release(st)
    _clearButtons()
    ARC.kill(st.berg); st.berg = nil
    RUMORS.removeCategory("ICEHAUL_SEED")
    RUMORS.removeCategory("ICEHAUL_DONE")
    RT.clearObjective("icehaul")
end

function M.resolve(st)
    RUMORS.removeCategory("ICEHAUL_SEED")
    RT.clearObjective("icehaul")
    M.release(st)
    _clearButtons()
    if RT.flag("icehaul_arc_done") == "delivered" then
        -- Hob's tugs take it in.
        RT.after(20, function()
            local cur = MISSIONS._state["icehaul"]
            if cur then ARC.kill(cur.berg); cur.berg = nil end
        end, "icehaul_cleanup")
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
        st.towing = false
        RT.setObjective("Pick up the ice", true, "icehaul")
        local x, y = st.berg:getPosition()
        ARC.log("[Ice Haul] The Kestrel ice is drifting round Kestrel, near " .. _sector(x, y)
            .. ". Get within " .. math.floor(M.TOW_REACH / U) .. "U; Engineering attaches the line.", "#A0E0FF")
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
            if d > M.TOW_REACH then st.berg:setPosition(px + (bx - px) / d * M.TOW_LENGTH, py + (by - py) / d * M.TOW_LENGTH) end
            M.attach(st)
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
