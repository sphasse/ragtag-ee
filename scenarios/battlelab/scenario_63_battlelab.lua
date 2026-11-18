-- Name: Battle Lab
-- Description: A test bed for the campaign's set-piece battles: a Concord battle group against a larger force of lighter Corsair ships, with the crew on the Corsair side, fought over five points in open space. Tune it from the GM screen.
---
--- Built on the ragtag framework (scripts/ragtag/). Install with tools/install.py.
--- For balancing the Boneyard and Corsair battles: a few tough opponents against ~10 nimble allies
--- plus the player, kept from collapsing into one blob by five combat points on a line through the centre.
-- Type: The Drift Universe

require("utils.lua")
require("ragtag/core.lua")
require("ragtag/verse.lua")
require("ragtag/ship_templates.lua")   -- the Light Freighter

local U = 1000

-- ── What fights ──────────────────────────────────────────────────────────────
-- Hulls by slot, repeated as needed. Edit these to try other mixes.
local CONCORD_HULLS = {"Atlantis X23", "Phobos T3", "Phobos T3", "Atlantis X23", "Phobos T3"}
local CORSAIR_HULLS = {"Adder MK5", "Adder MK5", "Piranha F12"}
local CONCORD_NAMES = {"Retribution", "Remand", "Writ", "Summons", "Levy", "Distraint", "Injunction", "Tariff",
                       "Mandate", "Edict", "Statute", "Decree"}
local CORSAIR_NAMES = {"Hardtack", "Ninth Life", "Long Odds", "Hollis", "Hearthstone", "Second Chance", "Last Laugh",
                       "Scrap Iron", "Old Grudge", "Long Shot", "Lucky Break", "Sweet Revenge", "Rust Bucket",
                       "Bad Habit", "Spare Change", "Short Fuse", "Dead Weight", "Fair Warning", "Low Tide",
                       "Quick Silver", "Hard Luck", "Tin Can", "Iron Will", "Stray Dog"}

-- ── Settings (the GM changes these; a reset applies counts and positions) ────
-- Speeds are normalized: each stat of every hull above is mapped linearly from the range the lab's
-- hulls have stock (slowest .. fastest, measured at start) onto these ranges, so the slowest hull
-- gets the low end and the fastest the high end, everything else in between in the same order.
-- Stock: Atlantis X23 30/3.5/5, Piranha F12 40/6/8, Phobos T3 60/10/10, Adder MK5 80/28/25.
local NORM = {
    impulse = {80, 120},   -- forward impulse
    turn    = {15, 28},    -- degrees per second
    accel   = {15, 25},    -- forward (and reverse) acceleration
}

local SET = {
    concord_impulse = 1.0,   -- x the normalized impulse (normalization already makes the fastest 120)
    corsair_impulse = 1.0,
    spacing_u       = 1.5,   -- distance between neighbouring combat points (Points closer / further)
    n_concord       = 5,
    n_corsair       = 12,
}
local IMPULSE_STEPS = {1.0, 1.25, 1.5, 1.75, 2.0, 2.5}
local SPACING_MIN, SPACING_MAX, SPACING_STEP = 0.5, 6, 0.5
local SPAWN_U       = 10     -- both sides start this far from the centre
local N_POSITIONS   = 5      -- invisible combat points on a north-south line through the centre
local RETARGET_EVERY = 2     -- seconds between checks for ships whose point has no enemies left

-- ── State ────────────────────────────────────────────────────────────────────
local B = {
    concord = {},   -- {ship, fwd, rev, pos}  (fwd/rev: the hull's own impulse)
    corsair = {},
    positions = {}, -- {x, y}
    started_at = 0,
    over = false,
    battles = 0,
    retargets = 0,      -- moves to a new point this battle
    next_retarget = 0,
}

local function alive(list)
    local n = 0
    for _, r in ipairs(list) do if r.ship and r.ship:isValid() then n = n + 1 end end
    return n
end

-- The combat points: N_POSITIONS on a vertical (north-south) line through the centre, spacing_u
-- apart, the middle one on the centre. Point 1 is the northernmost.
local function positions()
    local out = {}
    for k = 1, N_POSITIONS do
        out[k] = {0, (k - (N_POSITIONS + 1) / 2) * SET.spacing_u * U}
    end
    return out
end

local function shuffled(n)
    local t = {}
    for i = 1, n do t[i] = i end
    for i = n, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
    return t
end

-- Every ship defends one combat point; r.pos records which (the tracking the retargeting uses).
local function defend(r)
    local p = B.positions[r.pos]
    r.ship:orderDefendLocation(p[1], p[2])
end

-- Each side's ships start spread over the points: a random order of the points, dealt round-robin,
-- so no point gets everyone and each side covers all of them.
local function assign(list)
    local order = shuffled(N_POSITIONS)
    local k = 0
    for _, r in ipairs(list) do
        if r.ship:isValid() then
            k = k + 1
            r.pos = order[(k - 1) % N_POSITIONS + 1]
            defend(r)
        end
    end
end

-- Does point k still have a living enemy (from `enemies`) targeting it?
local function hasEnemies(k, enemies)
    for _, e in ipairs(enemies) do
        if e.pos == k and e.ship:isValid() then return true end
    end
    return false
end

-- Ships whose point has no living enemies left move to a random point that has some.
local function retarget(list, enemies)
    local live = {}
    for k = 1, N_POSITIONS do if hasEnemies(k, enemies) then live[#live + 1] = k end end
    if #live == 0 then return end
    for _, r in ipairs(list) do
        if r.ship:isValid() and not hasEnemies(r.pos, enemies) then
            r.pos = live[math.random(#live)]
            defend(r)
            B.retargets = B.retargets + 1
        end
    end
end

-- New spacing at once: every ship goes to its point's new place.
local function movePoints()
    B.positions = positions()
    for _, side in ipairs({B.concord, B.corsair}) do
        for _, r in ipairs(side) do if r.ship:isValid() and r.pos then defend(r) end end
    end
end

local function applyImpulse(list, mult)
    for _, r in ipairs(list) do
        if r.ship:isValid() then r.ship:setImpulseMaxSpeed(r.fwd * mult, r.rev) end
    end
end

-- Stock stats of every hull the lab uses, and their min / max (measured once, from throwaway ships).
local STOCK = nil
local function measureHulls()
    STOCK = {hulls = {}, impulse = {math.huge, -math.huge}, turn = {math.huge, -math.huge}, accel = {math.huge, -math.huge}}
    local seen = {}
    for _, list in ipairs({CONCORD_HULLS, CORSAIR_HULLS}) do
        for _, hull in ipairs(list) do
            if not seen[hull] then
                seen[hull] = true
                local s = CpuShip():setTemplate(hull):setPosition(0, -500000)
                local imp = s:getImpulseMaxSpeed()
                local v = {impulse = imp, turn = s:getRotationMaxSpeed(), accel = s:getAcceleration()}
                s:destroy()
                STOCK.hulls[hull] = v
                for stat, x in pairs(v) do
                    STOCK[stat][1] = math.min(STOCK[stat][1], x)
                    STOCK[stat][2] = math.max(STOCK[stat][2], x)
                end
            end
        end
    end
end

local function norm(stat, x)
    local lo, hi = STOCK[stat][1], STOCK[stat][2]
    local a, b = NORM[stat][1], NORM[stat][2]
    if hi <= lo then return b end
    return a + (x - lo) / (hi - lo) * (b - a)
end

local function spawnShip(hull, faction, name, x, y, heading)
    local s = CpuShip():setTemplate(hull):setFaction(faction):setCallSign(name)
    s:setPosition(x, y):setHeading(heading)
    s:setWarpDrive(false)
    pcall(function() s:setJumpDrive(false) end)
    s:setScanningParameters(1, 1)
    local stock = STOCK.hulls[hull]
    local _, rev = s:getImpulseMaxSpeed()
    local fwd = norm("impulse", stock.impulse)
    s:setRotationMaxSpeed(norm("turn", stock.turn))
    local acc = norm("accel", stock.accel)
    s:setAcceleration(acc, acc)
    return {ship = s, fwd = fwd, rev = rev}   -- fwd: the normalized impulse the multiplier scales
end

local function clearBattle()
    for _, side in ipairs({B.concord, B.corsair}) do
        for _, r in ipairs(side) do if r.ship:isValid() then r.ship:destroy() end end
    end
    B.concord, B.corsair = {}, {}
end

local function startBattle()
    if not STOCK then measureHulls() end
    clearBattle()
    B.positions = positions()
    B.started_at, B.over, B.retargets = getScenarioTime(), false, 0
    B.battles = B.battles + 1
    -- Concord: a line SPAWN_U west of the centre, 2U apart, facing east.
    for i = 1, SET.n_concord do
        local y = (i - (SET.n_concord + 1) / 2) * 2 * U
        local r = spawnShip(CONCORD_HULLS[(i - 1) % #CONCORD_HULLS + 1], "Concord Hostile",
            "CNS " .. CONCORD_NAMES[(i - 1) % #CONCORD_NAMES + 1], -SPAWN_U * U, y, 90)
        r.ship:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
        B.concord[#B.concord + 1] = r
    end
    -- Corsairs: a 120 degree arc SPAWN_U east of the centre, facing west.
    for i = 1, SET.n_corsair do
        local f = SET.n_corsair > 1 and (i - 1) / (SET.n_corsair - 1) or 0.5
        local a = math.rad(-60 + 120 * f)
        local r = spawnShip(CORSAIR_HULLS[(i - 1) % #CORSAIR_HULLS + 1], "Corsair Friendly",
            CORSAIR_NAMES[(i - 1) % #CORSAIR_NAMES + 1], math.cos(a) * SPAWN_U * U, math.sin(a) * SPAWN_U * U, 270)
        B.corsair[#B.corsair + 1] = r
    end
    applyImpulse(B.concord, SET.concord_impulse)
    applyImpulse(B.corsair, SET.corsair_impulse)
    assign(B.concord)
    assign(B.corsair)
    log(string.format("[BATTLELAB] battle %d: %d Concord (x%.2f) vs %d Corsairs (x%.2f), %d points %.1fU apart",
        B.battles, SET.n_concord, SET.concord_impulse, SET.n_corsair, SET.corsair_impulse, N_POSITIONS, SET.spacing_u))
end

local function statusText()
    local t = math.floor(getScenarioTime() - B.started_at)
    local lines = {string.format("=== BATTLE %d  (%d:%02d) ===", B.battles, t // 60, t % 60),
        string.format("Concord: %d / %d alive   (impulse x%.2f)", alive(B.concord), #B.concord, SET.concord_impulse),
        string.format("Corsairs: %d / %d alive  (impulse x%.2f)", alive(B.corsair), #B.corsair, SET.corsair_impulse),
        string.format("Combat points: %d on a north-south line, %.1fU apart (invisible)", N_POSITIONS, SET.spacing_u),
        string.format("Ships moved to a new point: %d", B.retargets), "", "Hull speeds, normalized (impulse / turn / accel):"}
    local names = {}
    for hull in pairs(STOCK.hulls) do names[#names + 1] = hull end
    table.sort(names, function(a, b) return STOCK.hulls[a].impulse < STOCK.hulls[b].impulse end)
    for _, hull in ipairs(names) do
        local v = STOCK.hulls[hull]
        lines[#lines + 1] = string.format("  %s: %.0f / %.1f / %.1f  (stock %.0f / %.1f / %.0f)", hull,
            norm("impulse", v.impulse), norm("turn", v.turn), norm("accel", v.accel), v.impulse, v.turn, v.accel)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Ships targeting each point, north to south (Concord / Corsairs):"
    for k = 1, N_POSITIONS do
        local c, s = 0, 0
        for _, r in ipairs(B.concord) do if r.pos == k and r.ship:isValid() then c = c + 1 end end
        for _, r in ipairs(B.corsair) do if r.pos == k and r.ship:isValid() then s = s + 1 end end
        lines[#lines + 1] = string.format("  %d: %d / %d", k, c, s)
    end
    return table.concat(lines, "\n")
end

-- ── GM console ───────────────────────────────────────────────────────────────

local function nextStep(steps, cur)
    for i, v in ipairs(steps) do
        if math.abs(v - cur) < 1e-6 then return steps[i % #steps + 1] end
    end
    return steps[1]
end

local showGM
showGM = function()
    clearGMFunctions()
    addGMFunction("Battle status", function() addGMMessage(statusText()) end)
    addGMFunction("Reset battle (apply settings)", function() startBattle(); showGM() end)
    addGMFunction("Reshuffle positions", function() assign(B.concord); assign(B.corsair) end)
    addGMFunction(string.format("Concord impulse x%.2f", SET.concord_impulse), function()
        SET.concord_impulse = nextStep(IMPULSE_STEPS, SET.concord_impulse)
        applyImpulse(B.concord, SET.concord_impulse)   -- applies at once
        showGM()
    end)
    addGMFunction(string.format("Corsair impulse x%.2f", SET.corsair_impulse), function()
        SET.corsair_impulse = nextStep(IMPULSE_STEPS, SET.corsair_impulse)
        applyImpulse(B.corsair, SET.corsair_impulse)
        showGM()
    end)
    addGMFunction(string.format("Points %.1fU apart: closer", SET.spacing_u), function()
        SET.spacing_u = math.max(SPACING_MIN, SET.spacing_u - SPACING_STEP); movePoints(); showGM()
    end)
    addGMFunction(string.format("Points %.1fU apart: further", SET.spacing_u), function()
        SET.spacing_u = math.min(SPACING_MAX, SET.spacing_u + SPACING_STEP); movePoints(); showGM()
    end)
    addGMFunction(string.format("Concord ships: %d (on reset)", SET.n_concord), function() end)
    addGMFunction("  Concord +1", function() SET.n_concord = math.min(12, SET.n_concord + 1); showGM() end)
    addGMFunction("  Concord -1", function() SET.n_concord = math.max(1, SET.n_concord - 1); showGM() end)
    addGMFunction(string.format("Corsair ships: %d (on reset)", SET.n_corsair), function() end)
    addGMFunction("  Corsairs +1", function() SET.n_corsair = math.min(24, SET.n_corsair + 1); showGM() end)
    addGMFunction("  Corsairs -1", function() SET.n_corsair = math.max(1, SET.n_corsair - 1); showGM() end)
end

-- ── Scenario ─────────────────────────────────────────────────────────────────

function init()
    VERSE.setupFactions()            -- Concord Hostile, Corsair Friendly (no universe is built)
    RT.useCampaign("battlelab")      -- its own save, never the campaign's
    RT.loadCampaign(true)
    RT.PLAYER_TEMPLATE = "Light Freighter"
    RT.spawnPlayer((SPAWN_U + 3) * U, 0, 270)   -- behind the Corsair arc, facing the centre
    -- Ships made on the "Create player ship" screen join the Corsair side too.
    onNewPlayerShip(function(ship)
        ship:setPosition((SPAWN_U + 3) * U, (#RT.players + 1) * 2 * U)
        ship:setFaction(RT.PLAYER_FACTION)
        RT.adoptPlayer(ship)
    end)
    startBattle()
    showGM()
end

function update(delta)
    RT.update(delta)
    local now = getScenarioTime()
    if not B.over and now >= B.next_retarget then
        B.next_retarget = now + RETARGET_EVERY
        retarget(B.concord, B.corsair)
        retarget(B.corsair, B.concord)
    end
    if not B.over and #B.concord > 0 then
        local c, s = alive(B.concord), alive(B.corsair)
        if c == 0 or s == 0 then
            B.over = true
            local t = math.floor(getScenarioTime() - B.started_at)
            local msg = string.format("Battle %d over in %d:%02d: %s. Corsairs left: %d of %d; Concord left: %d of %d.",
                B.battles, t // 60, t % 60, c == 0 and "the Corsairs hold" or "the Concord wins",
                s, #B.corsair, c, #B.concord)
            globalMessage(msg, 10)
            addGMMessage(msg .. string.format("\nShips moved to a new point: %d.\n\nReset battle to go again.", B.retargets))
            log("[BATTLELAB] " .. msg)
        end
    end
end
