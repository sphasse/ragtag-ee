-- Name: Battle Lab
-- Description: A test bed for the campaign's set-piece battles: a Concord battle group against a larger force of lighter Corsair ships, with the crew on the Corsair side, fought around six positions in open space. Tune it from the GM screen.
---
--- Built on the ragtag framework (scripts/ragtag/). Install with tools/install.py.
--- For balancing the Boneyard and Corsair battles: a few tough opponents against ~10 nimble allies
--- plus the player, kept from collapsing into one blob by six battle positions around a centre.
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
local SET = {
    concord_impulse = 1.5,   -- x the hull's normal impulse
    corsair_impulse = 1.5,
    radius_u        = 3,     -- battle positions' distance from the centre
    n_concord       = 5,
    n_corsair       = 12,
}
local IMPULSE_STEPS = {1.0, 1.25, 1.5, 1.75, 2.0, 2.5}
local RADIUS_STEPS  = {2, 3, 4, 5, 6, 8}
local SPAWN_U       = 10     -- both sides start this far from the centre
local N_POSITIONS   = 6

-- ── State ────────────────────────────────────────────────────────────────────
local B = {
    concord = {},   -- {ship, fwd, rev, pos}  (fwd/rev: the hull's own impulse)
    corsair = {},
    positions = {}, -- {x, y}
    started_at = 0,
    over = false,
    battles = 0,
}

local function alive(list)
    local n = 0
    for _, r in ipairs(list) do if r.ship and r.ship:isValid() then n = n + 1 end end
    return n
end

local function positions()
    local out = {}
    for k = 1, N_POSITIONS do
        local a = math.rad((k - 1) * 360 / N_POSITIONS)
        out[k] = {math.cos(a) * SET.radius_u * U, math.sin(a) * SET.radius_u * U}
    end
    return out
end

local function shuffled(n)
    local t = {}
    for i = 1, n do t[i] = i end
    for i = n, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
    return t
end

-- Each side's ships defend the six positions, spread out: a random order of the positions, dealt
-- round-robin, so no position gets everyone and each side is spread over all six.
local function assign(list)
    local order = shuffled(N_POSITIONS)
    local k = 0
    for _, r in ipairs(list) do
        if r.ship:isValid() then
            k = k + 1
            r.pos = order[(k - 1) % N_POSITIONS + 1]
            local p = B.positions[r.pos]
            r.ship:orderDefendLocation(p[1], p[2])
        end
    end
end

local function applyImpulse(list, mult)
    for _, r in ipairs(list) do
        if r.ship:isValid() then r.ship:setImpulseMaxSpeed(r.fwd * mult, r.rev) end
    end
end

local function spawnShip(hull, faction, name, x, y, heading)
    local s = CpuShip():setTemplate(hull):setFaction(faction):setCallSign(name)
    s:setPosition(x, y):setHeading(heading)
    s:setWarpDrive(false)
    pcall(function() s:setJumpDrive(false) end)
    s:setScanningParameters(1, 1)
    local fwd, rev = s:getImpulseMaxSpeed()
    return {ship = s, fwd = fwd, rev = rev}
end

local function clearBattle()
    for _, side in ipairs({B.concord, B.corsair}) do
        for _, r in ipairs(side) do if r.ship:isValid() then r.ship:destroy() end end
    end
    B.concord, B.corsair = {}, {}
end

local function startBattle()
    clearBattle()
    B.positions = positions()
    B.started_at, B.over = getScenarioTime(), false
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
    log(string.format("[BATTLELAB] battle %d: %d Concord (x%.2f) vs %d Corsairs (x%.2f), positions at %dU",
        B.battles, SET.n_concord, SET.concord_impulse, SET.n_corsair, SET.corsair_impulse, SET.radius_u))
end

local function statusText()
    local t = math.floor(getScenarioTime() - B.started_at)
    local lines = {string.format("=== BATTLE %d  (%d:%02d) ===", B.battles, t // 60, t % 60),
        string.format("Concord: %d / %d alive   (impulse x%.2f)", alive(B.concord), #B.concord, SET.concord_impulse),
        string.format("Corsairs: %d / %d alive  (impulse x%.2f)", alive(B.corsair), #B.corsair, SET.corsair_impulse),
        string.format("Positions: %d at %dU from the centre", N_POSITIONS, SET.radius_u), "", "By position (Concord / Corsairs):"}
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
    addGMFunction(string.format("Positions at %dU (on reset)", SET.radius_u), function()
        SET.radius_u = nextStep(RADIUS_STEPS, SET.radius_u)
        showGM()
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
    if not B.over and #B.concord > 0 then
        local c, s = alive(B.concord), alive(B.corsair)
        if c == 0 or s == 0 then
            B.over = true
            local t = math.floor(getScenarioTime() - B.started_at)
            local msg = string.format("Battle %d over in %d:%02d: %s. Corsairs left: %d of %d; Concord left: %d of %d.",
                B.battles, t // 60, t % 60, c == 0 and "the Corsairs hold" or "the Concord wins",
                s, #B.corsair, c, #B.concord)
            globalMessage(msg, 10)
            addGMMessage(msg .. "\n\nReset battle to go again.")
            log("[BATTLELAB] " .. msg)
        end
    end
end
