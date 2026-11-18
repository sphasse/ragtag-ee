-- Name: Battle Lab
-- Description: A test bed for the campaign's set-piece battles: a Concord battle group against a larger force of lighter Corsair ships, with the crew on the Corsair side, fought over five points in open space. Tune it from the GM screen.
---
--- Built on the ragtag framework (scripts/ragtag/). Install with tools/install.py.
--- For balancing the Boneyard and Corsair battles: a few tough opponents against ~10 nimble allies
--- plus the player, kept from collapsing into one blob by five combat points on a line through the centre.
--- The battle rules live in ragtag/battle.lua (BATTLE), shared with the Corsair arc's battle.
-- Type: The Drift Universe

require("utils.lua")
require("ragtag/core.lua")        -- also loads ragtag/battle.lua
require("ragtag/verse.lua")
require("ragtag/ship_templates.lua")   -- the Light Freighter

local U = 1000

-- ── What fights ──────────────────────────────────────────────────────────────
-- Hulls by slot, repeated as needed. Edit these to try other mixes. Speeds are normalized across
-- all of them (BATTLE.NORM, BATTLE.HULL_TWEAKS in ragtag/battle.lua).
local CONCORD_HULLS = {"Atlantis X23", "Phobos T3", "Phobos T3", "Atlantis X23", "Phobos T3"}
local CORSAIR_HULLS = {"Adder MK5", "Adder MK5", "Piranha F12"}
local CONCORD_NAMES = {"Retribution", "Remand", "Writ", "Summons", "Levy", "Distraint", "Injunction", "Tariff",
                       "Mandate", "Edict", "Statute", "Decree"}
local CORSAIR_NAMES = {"Hardtack", "Ninth Life", "Long Odds", "Hollis", "Hearthstone", "Second Chance", "Last Laugh",
                       "Scrap Iron", "Old Grudge", "Long Shot", "Lucky Break", "Sweet Revenge", "Rust Bucket",
                       "Bad Habit", "Spare Change", "Short Fuse", "Dead Weight", "Fair Warning", "Low Tide",
                       "Quick Silver", "Hard Luck", "Tin Can", "Iron Will", "Stray Dog"}

-- ── Settings (the GM changes these) ──────────────────────────────────────────
local SET = {
    concord_impulse = 1.0,   -- x the normalized impulse (normalization already makes the fastest 120)
    corsair_impulse = 1.0,
    spacing_u       = 1.5,   -- distance between neighbouring combat points (applies at once)
    n_concord       = 5,     -- (on reset)
    n_corsair       = 12,
}
local IMPULSE_STEPS = {1.0, 1.25, 1.5, 1.75, 2.0, 2.5}
local SPACING_MIN, SPACING_MAX, SPACING_STEP = 0.5, 6, 0.5
local SPAWN_U = 10   -- both lines start this far from the centre

-- ── State ────────────────────────────────────────────────────────────────────
local B = {battle = nil, started_at = 0, over = false, battles = 0}

local function allHulls()
    local t = {}
    for _, h in ipairs(CONCORD_HULLS) do t[#t + 1] = h end
    for _, h in ipairs(CORSAIR_HULLS) do t[#t + 1] = h end
    return t
end

local function startBattle()
    if B.battle then B.battle:clear() end
    local b = BATTLE.new{x = 0, y = 0, points = 5, spacing_u = SET.spacing_u, hulls = allHulls(), topup = {"b"}}
    b.mult.a, b.mult.b = SET.concord_impulse, SET.corsair_impulse
    -- Side a, Concord: a line SPAWN_U west of the centre, 2U apart, facing east (no nukes).
    for i = 1, SET.n_concord do
        local s = b:spawn("a", CONCORD_HULLS[(i - 1) % #CONCORD_HULLS + 1], "Concord Hostile",
            "CNS " .. CONCORD_NAMES[(i - 1) % #CONCORD_NAMES + 1], -SPAWN_U * U, (i - (SET.n_concord + 1) / 2) * 2 * U, 90)
        s:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
    end
    -- Side b, Corsairs: a line SPAWN_U east, 2U apart, facing west.
    for i = 1, SET.n_corsair do
        b:spawn("b", CORSAIR_HULLS[(i - 1) % #CORSAIR_HULLS + 1], "Corsair Friendly",
            CORSAIR_NAMES[(i - 1) % #CORSAIR_NAMES + 1], SPAWN_U * U, (i - (SET.n_corsair + 1) / 2) * 2 * U, 270)
    end
    b:start()
    B.battle, B.started_at, B.over = b, getScenarioTime(), false
    B.battles = B.battles + 1
    log(string.format("[BATTLELAB] battle %d: %d Concord (x%.2f) vs %d Corsairs (x%.2f), %d points %.1fU apart",
        B.battles, SET.n_concord, SET.concord_impulse, SET.n_corsair, SET.corsair_impulse, b.n_points, SET.spacing_u))
end

local function statusText()
    local b = B.battle
    local t = math.floor(getScenarioTime() - B.started_at)
    local lines = {string.format("=== BATTLE %d  (%d:%02d) ===", B.battles, t // 60, t % 60),
        string.format("Concord: %d / %d alive   (impulse x%.2f)", b:alive("a"), #b.sides.a, SET.concord_impulse),
        string.format("Corsairs: %d / %d alive  (impulse x%.2f)", b:alive("b"), #b.sides.b, SET.corsair_impulse),
        string.format("Combat points: %d on a north-south line, %.1fU apart (invisible)", b.n_points, SET.spacing_u),
        string.format("Ships moved to a new point: %d", b.retargets),
        string.format("Corsair missile top-ups: %d", b.topups), "", "Hull speeds, normalized (impulse / turn / accel):"}
    local names = {}
    for hull in pairs(b.stock.hulls) do names[#names + 1] = hull end
    table.sort(names, function(p, q) return b.stock.hulls[p].impulse < b.stock.hulls[q].impulse end)
    for _, hull in ipairs(names) do
        local v = b.stock.hulls[hull]
        lines[#lines + 1] = string.format("  %s: %.0f / %.1f / %.1f  (stock %.0f / %.1f / %.0f)%s", hull,
            b:stat(hull, "impulse"), b:stat(hull, "turn"), b:stat(hull, "accel"), v.impulse, v.turn, v.accel,
            BATTLE.HULL_TWEAKS[hull] and "  tweaked" or "")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Ships targeting each point, north to south (Concord / Corsairs):"
    for k = 1, b.n_points do
        local c, s = 0, 0
        for _, r in ipairs(b.sides.a) do if r.pos == k and r.ship:isValid() then c = c + 1 end end
        for _, r in ipairs(b.sides.b) do if r.pos == k and r.ship:isValid() then s = s + 1 end end
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
    addGMFunction("Re-deal points by position", function() B.battle:assign("a"); B.battle:assign("b") end)
    addGMFunction(string.format("Concord impulse x%.2f", SET.concord_impulse), function()
        SET.concord_impulse = nextStep(IMPULSE_STEPS, SET.concord_impulse)
        B.battle:setImpulse("a", SET.concord_impulse)   -- applies at once
        showGM()
    end)
    addGMFunction(string.format("Corsair impulse x%.2f", SET.corsair_impulse), function()
        SET.corsair_impulse = nextStep(IMPULSE_STEPS, SET.corsair_impulse)
        B.battle:setImpulse("b", SET.corsair_impulse)
        showGM()
    end)
    addGMFunction(string.format("Points %.1fU apart: closer", SET.spacing_u), function()
        SET.spacing_u = math.max(SPACING_MIN, SET.spacing_u - SPACING_STEP); B.battle:setSpacing(SET.spacing_u); showGM()
    end)
    addGMFunction(string.format("Points %.1fU apart: further", SET.spacing_u), function()
        SET.spacing_u = math.min(SPACING_MAX, SET.spacing_u + SPACING_STEP); B.battle:setSpacing(SET.spacing_u); showGM()
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
    RT.spawnPlayer((SPAWN_U + 3) * U, 0, 270)   -- behind the Corsair line, facing the centre
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
    local b = B.battle
    if not b then return end
    b:tick(getScenarioTime())
    if not B.over and #b.sides.a > 0 then
        local c, s = b:alive("a"), b:alive("b")
        if c == 0 or s == 0 then
            B.over = true
            local t = math.floor(getScenarioTime() - B.started_at)
            local msg = string.format("Battle %d over in %d:%02d: %s. Corsairs left: %d of %d; Concord left: %d of %d.",
                B.battles, t // 60, t % 60, c == 0 and "the Corsairs hold" or "the Concord wins",
                s, #b.sides.b, c, #b.sides.a)
            globalMessage(msg, 10)
            addGMMessage(msg .. string.format("\nShips moved to a new point: %d. Corsair missile top-ups: %d.\n\nReset battle to go again.",
                b.retargets, b.topups))
            log("[BATTLELAB] " .. msg)
        end
    end
end
