-- ee/ragtag/missions/holdout.lua
-- The Holdout: a one-off money job. The Shroud Raiders mean to take Breaker's Claim, a mining camp on
-- the southern edge of the Shroud, for good. Foreman Ines Calloway hires the crew to stand with the
-- camp through the raid: three waves out of the nebula. GM guide: docs/GM_HOLDOUT_MISSION.md
--
-- Structure: init -> hook -> defend -> done ("defended" | "fallen" | "lost")
--   hook     seed rumors at Independent ports; docked at Breaker's Claim, Calloway's [SPECIAL] reply
--            (two pages).
--   defend   PREP_TIME to get in position, then WAVES out of the Shroud from two gates north of the
--            Claim; the next wave WAVE_GAP after the last raider of a wave is gone. The Claim is
--            reinforced (OUTPOST_HULL / OUTPOST_SHIELDS) and its cutting lasers fire on the nearest
--            raider in range. Half of each wave goes for the Claim, half fights the Magpie.
--            All waves beaten: defended (PAY, Independent +REP). The Claim's hull at FALL_AT: fallen.
--   lost     the Magpie lost during the raid.

local M = {}
M.id             = "holdout"
M.name           = "The Holdout"
M.repeatable     = false
M.locks_jobs     = false
M.auto_start     = true
M.start_phase    = "init"
M.no_auto_cancel = true

local U = 1000

-- ── Tuning ──────────────────────────────────────────────────────────────────
M.UPGRADES_MIN    = 1500   -- a ship with some fight in it
M.PREP_TIME       = 60     -- seconds from "we'll stay" to the first wave
M.WAVE_GAP        = 45     -- seconds between the end of a wave and the next
M.OUTPOST_HULL    = 500    -- the Claim, reinforced for the raid (stock Small Station: 150)
M.OUTPOST_SHIELDS = 300    -- (stock: 300)
M.FALL_AT         = 0.15   -- the Claim's hull at this fraction: it falls
M.PAY             = 3000
M.REP             = 150
M.LASERS          = {count = 2, range = 3000, cycle = 4, damage = 6}   -- the miners' cutting lasers
-- Each wave's hulls. Odd ships go for the Claim, even ones for the Magpie.
M.WAVES = {
    {"MT52 Hornet", "MT52 Hornet", "Adder MK5"},
    {"Adder MK5", "Adder MK5", "Phobos T3"},
    {"Phobos T3", "Phobos T3", "Adder MK5", "MT52 Hornet"},
}

local _CLAIM = "Breaker's Claim"
-- Where the raiders come out of the Shroud: west and east of the Claim's rocks (78, 16, r 8), inside
-- or at the edge of the nebula, about 19U north of the Claim (universe units).
M.GATES = {{66, 14}, {90, 11}}
local _GATE_SCATTER = 2 * U
local _NAMES = {"Fog Bank", "Blind Corner", "Grey Wolf", "Low Visibility", "Smoke Signal", "Lost Bearing",
    "Static Bite", "The Undertow", "Pale Rider", "Wrong Turn", "Cold Wake", "Mist Walker", "Dead Reckoning"}

function M.init_state()
    return {
        wave      = 0,       -- the wave under way (0: none yet)
        raiders   = {},      -- the current wave's ships
        next_at   = nil,     -- when the next wave comes (nil: a wave is under way)
        lasers_at = 0,
        armed     = false,
        serial    = 0,
    }
end

-- ── Small helpers ───────────────────────────────────────────────────────────

local function _active(phase)
    return MISSIONS._status["holdout"] == "active" and (phase == nil or MISSIONS._cur_phase["holdout"] == phase)
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

local function _claim()
    local c = RT.find(_CLAIM)
    return RT.valid(c) and c or nil
end
M.claim = _claim

-- The Claim's hull as a fraction of its maximum.
function M.claimHull()
    local c = _claim()
    if not c then return 0 end
    local max = c:getHullMax()
    return max > 0 and c:getHull() / max or 0
end

-- ── The Claim: reinforced for the raid, its cutting lasers ──────────────────

-- The Claim's own hull and shields (by entity), noted the first time it is fortified and restored
-- after the raid. Kept outside the arc state so a GM jump or a restart never notes the fortified values.
local _stock = {}

local function _fortify(st)
    local c = _claim()
    if not c or st.armed then return end
    st.armed = true
    if not _stock[c] then
        _stock[c] = {hull = c:getHullMax(), front = c:getShieldMax(0), rear = c:getShieldMax(1)}
    end
    c:setHullMax(M.OUTPOST_HULL):setHull(M.OUTPOST_HULL)
    c:setShieldsMax(M.OUTPOST_SHIELDS, M.OUTPOST_SHIELDS):setShields(M.OUTPOST_SHIELDS, M.OUTPOST_SHIELDS)
    local L = M.LASERS
    for i = 0, L.count - 1 do
        c:setBeamWeapon(i, 360, i * 360 / L.count, L.range, L.cycle, L.damage)
        pcall(function() c:setBeamWeaponHeatPerFire(i, 0); c:setBeamWeaponEnergyPerFire(i, 0) end)
    end
end

-- After the raid: the lasers come down and the Claim is patched up to its own hull.
local function _standDown(st)
    local c = _claim()
    st.armed = false
    if not c then return end
    pcall(function()
        c.components.weapons_target = nil
        c.components.beam_weapons = nil
    end)
    local s = _stock[c]
    if s then
        c:setHullMax(s.hull):setHull(s.hull)
        c:setShieldsMax(s.front, s.rear):setShields(s.front, s.rear)
    else
        c:setHull(c:getHullMax())
    end
end

local function _aimLasers(st)
    local c = _claim()
    if not c or not st.armed then return end
    local best, best_d = nil, M.LASERS.range
    for _, r in ipairs(ARC.alive(st.raiders)) do
        local d = RT.dist(c, r)
        if d <= best_d then best, best_d = r, d end
    end
    st.laser_target = best
    pcall(function() c.components.weapons_target = best and {entity = best} or nil end)
end

-- ── The raiders ─────────────────────────────────────────────────────────────

local function _spawnWave(st, n)
    local c = _claim()
    if not c then return end
    local cx, cy = c:getPosition()
    local p = ARC.player()
    st.raiders = {}
    for i, hull in ipairs(M.WAVES[n]) do
        local g = M.GATES[(i - 1) % #M.GATES + 1]
        local x = g[1] * U + (math.random() * 2 - 1) * _GATE_SCATTER
        local y = g[2] * U + (math.random() * 2 - 1) * _GATE_SCATTER
        st.serial = st.serial + 1
        local s = CpuShip():setTemplate(hull):setFaction("Shroud Raiders")
        s:setCallSign(_NAMES[(st.serial - 1) % #_NAMES + 1]):setPosition(x, y)
        s:setHeading((math.deg(math.atan(cy - y, cx - x)) + 90) % 360)
        s:setWarpDrive(false)
        pcall(function() s:setJumpDrive(false) end)
        s:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
        s:setDescriptions("Raider.", "A Shroud Raider, out of the fog for Breaker's Claim.")
        s:setCommsScript(""):setCommsFunction(function()
            setCommsMessage('"The Claim\'s ours now. Fly off, or stay and burn with it."')
        end)
        if i % 2 == 1 or not p then s:orderAttack(c) else s:orderAttack(p) end
        ARC.register(s)
        st.raiders[#st.raiders + 1] = s
    end
    st.wave, st.next_at = n, nil
    ARC.log(string.format("[Holdout] Wave %d of %d: %d raiders out of the Shroud, north of the Claim.", n, #M.WAVES, #st.raiders), "#FFAA40")
    RT.setObjective(string.format("Hold: wave %d of %d", n, #M.WAVES), true, "holdout")
end

local function _finish(outcome)
    RT.flag("holdout_arc_done", outcome)
    MISSIONS.phase("holdout", "done")
end

local function _tickDefend(st, now)
    if now >= st.lasers_at then
        st.lasers_at = now + 1
        _aimLasers(st)
    end
    if M.claimHull() <= M.FALL_AT then
        ARC.log("[Holdout] Breaker's Claim is burning. Calloway's ordering the crews into the lifeboats.", "#FF8080")
        _finish("fallen")
        return
    end
    local alive = ARC.alive(st.raiders)
    if st.next_at == nil and #alive == 0 then
        if st.wave >= #M.WAVES then
            ARC.once("holdout_rewarded", function()
                RT.addCredits(M.PAY, "The Holdout: Breaker's Claim held")
                RT.addReputation("Independent", M.REP, "The Holdout: Breaker's Claim held")
            end)
            local c = _claim()
            local msg = '"That\'s the last of them. They\'re running for the fog." Calloway sounds hoarse. "'
                .. _cr(M.PAY) .. ' credits, as promised, and a name on our list. Breaker\'s Claim doesn\'t forget."'
            if not (c and ARC.hail(c, msg, "Ines Calloway")) then ARC.log("[Ines Calloway] " .. msg, "#C0C0FF") end
            _finish("defended")
            return
        end
        st.next_at = now + M.WAVE_GAP
        ARC.log(string.format("[Holdout] Wave %d beaten. The next one is coming: %d seconds.", st.wave, M.WAVE_GAP), "#80FF80")
        RT.setObjective(string.format("Hold: wave %d next", st.wave + 1), true, "holdout")
    end
    if st.next_at and now >= st.next_at then _spawnWave(st, st.wave + 1) end
end

-- ── Rumors ──────────────────────────────────────────────────────────────────

local _HIRING = "Breaker's Claim is hiring guns. The Shroud Raiders have hit them twice this year, and this time they mean to stay."
local _SEEDS = {
    "The raiders in the Shroud never did take Blackwater's terms. They take whatever they like, and lately what they like is Breaker's Claim.",
    "The miners at Breaker's Claim bolted cutting lasers to their hull. Brave. Won't be enough, I hear.",
}

local function _seedRumors()
    RUMORS.removeCategory("HOLDOUT_SEED")
    if RT.flag("holdout_briefed") then return end
    for _, text in ipairs(_SEEDS) do
        RUMORS.add({text = text, priority = 3, faction = "Independent", category = "HOLDOUT_SEED"})
    end
    RUMORS.add({text = _HIRING, priority = 3, faction = "Independent", category = "HOLDOUT_SEED",
        on_heard = function()
            if _active("hook") then RT.setObjective("Breaker's Claim", false, "holdout") end
        end})
end

-- ── Calloway's offer ────────────────────────────────────────────────────────

local function _offer()
    ARC.meet("holdout", "calloway_profile", "Ines Calloway")
    setCommsMessage('A broad woman with a cutting torch on her belt meets you at the airlock. "Ines Calloway. I run this claim."\n\n'
        .. '"The Shroud Raiders have hit us twice this year. They took a cut and left. This time they sent word: they\'re coming for the whole claim, '
        .. 'rocks, crews and all. We\'ve got cutting lasers on the hull and one fighter. That won\'t hold them."')
    addCommsReply("Go on.", function()
        setCommsMessage('"They\'ll come out of the fog north of us, in waves, round both sides of the rocks. Some will go for the Claim, '
            .. 'some for whoever\'s defending it. Stay with us until they\'re done, keep the Claim standing, and you get '
            .. _cr(M.PAY) .. ' credits. It\'s every credit we\'ve got."\n\n"They\'re close. Once you say yes, you\'ll have about a minute to get in position."')
        addCommsReply("We'll stay.", function()
            RT.flag("holdout_briefed", true)
            MISSIONS.phase("holdout", "defend")
            setCommsMessage('"Then get out there. And thank you."')
        end)
        addCommsReply("Not right now.", function()
            setCommsMessage('"Don\'t take too long. They won\'t."')
        end)
    end)
end

local function _claimHook(src, tgt, info)
    if not ARC.docked(src, tgt) then return end
    if not _active("hook") then return end
    addCommsReply("[SPECIAL] Calloway's offer", _offer)
end

-- The Magpie lost during the raid.
RT.on(function(ev)
    if ev.type ~= "ship_lost" or not ev.data.primary or not _active("defend") then return end
    _finish("lost")
end)

-- ── Science database ────────────────────────────────────────────────────────

function M._addRaidEntry()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["holdout_raid"] then return end
    SCIDB._entries["holdout_raid"] = SCIDB.addEntry("briefings", "The raid on Breaker's Claim", table.concat({
        "THE JOB",
        "Stand with Breaker's Claim until the Shroud Raiders give up. Foreman Ines Calloway pays " .. _cr(M.PAY) .. " cr: everything the camp has.",
        "",
        "THE RAID",
        #M.WAVES .. " waves out of the Shroud, north of the Claim, round both sides of its rocks. About half of each wave goes for the Claim, the rest for the ship defending it. The next wave comes " .. M.WAVE_GAP .. " seconds after the last raider of a wave is gone.",
        "",
        "THE CLAIM",
        "Reinforced for the raid, with cutting lasers that fire on the nearest raider within 3U and one fighter. If its hull fails, the camp is lost.",
        "",
        "THE RAIDERS",
        "Shroud Raiders: Corsairs who never answered to Blackwater. No standing is lost for destroying them.",
    }, "\n"), {["Pay"] = _cr(M.PAY) .. " cr", ["Waves"] = tostring(#M.WAVES), ["From"] = "The Shroud, north"})
end

-- ── Cleanup / resolve ───────────────────────────────────────────────────────

local function _clearWorld(st)
    ARC.kill(st.raiders); st.raiders = {}
    _standDown(st)
    PROX.resumeZone("the Shroud")
    RUMORS.removeCategory("HOLDOUT_SEED")
    RUMORS.removeCategory("HOLDOUT_DONE")
    RT.clearObjective("holdout")
end

function M.resolve(st)
    RUMORS.removeCategory("HOLDOUT_SEED")
    RT.clearObjective("holdout")
    _standDown(st)
    PROX.resumeZone("the Shroud")
    local outcome = RT.flag("holdout_arc_done")
    if outcome == "lost" then
        ARC.log("[Holdout] With the Magpie gone, the raiders took Breaker's Claim.", "#FF8080")
    end
    -- Raiders still out there go back into the fog.
    for _, r in ipairs(ARC.alive(st.raiders or {})) do
        local x, y = r:getPosition()
        r:orderFlyTowards(x, y - 30 * U)
    end
    RT.after(90, function()
        local cur = MISSIONS._state["holdout"]
        if cur then ARC.kill(cur.raiders); cur.raiders = {} end
    end, "holdout_cleanup")
    AFTERMATH.sync()
end

function M.on_cancel(st)
    RT.cancelTimer("holdout_cleanup")
    _clearWorld(st)
end

-- ── Phases ──────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        ARC.stationHook(_CLAIM, _claimHook)
        ARC.route("holdout", {
            {"holdout_arc_done", "done"},
            {"holdout_briefed", "defend"},   -- a raid cut short by the session's end starts over
        }, "hook")
    end,
}

M.phases.hook = {
    enter = function(st) _seedRumors() end,
    exit = function(st) RUMORS.removeCategory("HOLDOUT_SEED") end,
}

M.phases.defend = {
    enter = function(st)
        M._addRaidEntry()
        PROX.suspendZone("the Shroud")
        _fortify(st)
        st.wave, st.raiders = 0, {}
        st.next_at = getScenarioTime() + M.PREP_TIME
        RT.setObjective("Defend the Claim", true, "holdout")
        ARC.log(string.format("[Holdout] The raiders are coming out of the Shroud, north of the Claim. About %d seconds.", M.PREP_TIME), "#FFAA40")
    end,
    update = function(st, delta, now) _tickDefend(st, now) end,
}

-- ── Trigger: Rezkov over and a ship with some fight in it ───────────────────

M.triggers = {
    upgrades_min   = M.UPGRADES_MIN,
    not_flagged    = {"holdout_arc_done"},
    requires       = function() return (RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined")) and true or false end,
    requires_label = "Rezkov over (or declined)",
}

M.phase_order = {"init", "hook", "defend"}

-- ── GM console ──────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"holdout_"}

M.flags = {
    holdout_briefed   = "agreed to defend Breaker's Claim (the raid Science DB entry)",
    holdout_rewarded  = "paid (once)",
    holdout_arc_done  = 'outcome: "defended" (every wave beaten) | "fallen" (the Claim\'s hull failed) | "lost" (the Magpie lost in the raid)',
    ["holdout_met_*"] = "Science DB profile met in this arc (calloway), set by ARC.meet",
}
M.reads = {"rezkov_arc_done", "rezkov_declined"}

M.gm_state_fn = function()
    local st = MISSIONS._state["holdout"] or {}
    local ph = MISSIONS._cur_phase["holdout"]
    if MISSIONS._status["holdout"] == "done" then return "Complete (" .. tostring(RT.flag("holdout_arc_done")) .. ")" end
    if ph == "defend" then
        local hull = math.floor(M.claimHull() * 100 + 0.5)
        if st.next_at then return string.format("Wave %d next, Claim %d%%", (st.wave or 0) + 1, hull) end
        return string.format("Wave %d: %d left, Claim %d%%", st.wave or 0, #ARC.alive(st.raiders or {}), hull)
    end
    return ph or MISSIONS._status["holdout"]
end

M.gm_reset = function(st, target)
    RT.cancelTimer("holdout_cleanup")
    _clearWorld(st)
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("holdout", function(name) return false end)
end

M.completed = {
    hook = function(st)
        RT.flag("holdout_briefed", true)
        ARC.meet("holdout", "calloway_profile", "Ines Calloway")
    end,
}

local _jump = ARC.jumper("holdout")

M.gm_states = {
    {key = "hook",   label = "→ Hook",   fn = _jump("hook")},
    {key = "defend", label = "→ Defend", fn = _jump("defend")},
    {key = "done_defended", label = "→ Done: Defended", fn = _jump("done", function() RT.flag("holdout_arc_done", "defended") end)},
    {key = "done_fallen",   label = "→ Done: Fallen",   fn = _jump("done", function() RT.flag("holdout_arc_done", "fallen") end)},
    {key = "done_lost",     label = "→ Done: Lost",     fn = _jump("done", function() RT.flag("holdout_arc_done", "lost") end)},
}

M.gm_actions = {
    ARC.travel("Claim", {"hook", "defend"}, _CLAIM),
    {label = "Next wave now", phases = {"defend"}, fn = function(st)
        if st.next_at then st.next_at = getScenarioTime() end
    end},
    {label = "Kill this wave", phases = {"defend"}, fn = function(st)
        ARC.kill(st.raiders); st.raiders = {}
    end},
    {label = "Repair the Claim", phases = {"defend"}, fn = function(st)
        local c = _claim()
        if c then c:setHull(c:getHullMax()) end
    end},
}

-- The Science DB follows the flags (SCIDB.sync at session start and after every GM jump).
if SCIDB and SCIDB.rule then
    SCIDB.rule("holdout_raid", {want = function() return RT.flag("holdout_briefed") end, add = function() M._addRaidEntry() end})
end

if ACH and ACH.define then
    ACH.define{id = "hold_the_line", name = "Hold the Line", category = "story", hidden = true,
        desc = "Stand with Breaker's Claim until the Shroud Raiders give up.",
        check = function(s) return RT.flag("holdout_arc_done") == "defended" end}
end

MISSIONS.register(M)
