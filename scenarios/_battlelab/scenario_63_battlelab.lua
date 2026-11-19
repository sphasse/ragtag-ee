-- Name: Battle Lab
-- Description: A test bed for the campaign's set-piece battles. Annex mode: the Boneyard arc's climax at the Ashgrave Annex, a Concord battle group against swarms of Relic drones. Open-space mode: a Concord battle group against lighter Corsair ships, with the crew on the Corsair side. Tune and trigger it from the GM screen.
---
--- Built on the ragtag framework (scripts/ragtag/). Install with tools/install.py.
--- For balancing the Boneyard and Corsair battles. The battle rules live in ragtag/battle.lua
--- (BATTLE, and BATTLE.annex for the Annex fight), shared with the arcs, so tuning found here carries over.
-- Type: The Drift Universe

require("utils.lua")
require("ragtag/core.lua")        -- also loads ragtag/battle.lua
require("ragtag/verse.lua")
require("ragtag/ship_templates.lua")   -- the Light Freighter

local U = 1000

-- ── Open space: what fights ──────────────────────────────────────────────────
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

-- ── The Annex (the Boneyard, at its real place in the Drift) ─────────────────
local ANNEX_X, ANNEX_Y = 43000, -104000

-- ── Settings (the GM changes these) ──────────────────────────────────────────
local SET = {
    mode            = "annex",   -- "annex" or "open"
    concord_impulse = 1.0,   -- x the normalized impulse (normalization already makes the fastest 120)
    corsair_impulse = 1.0,
    drone_impulse   = 1.0,   -- x the drones' impulse (1.5x the fastest Concord ship)
    spacing_u       = 1.5,   -- open space: distance between neighbouring combat points (applies at once)
    n_concord       = 5,     -- open space (on reset)
    n_corsair       = 12,
    annex_concord   = BATTLE.ANNEX.concord,   -- Annex: ships per "Spawn Concord"
    annex_drones    = BATTLE.ANNEX.drones,    -- Annex: drones per "Spawn drones"
}
local IMPULSE_STEPS = {1.0, 1.25, 1.5, 1.75, 2.0, 2.5}
local SPACING_MIN, SPACING_MAX, SPACING_STEP = 0.5, 6, 0.5
local SPAWN_U = 10   -- open space: both lines start this far from the centre

-- Where the crew starts in each mode (x, y, heading).
local CREW_AT = {
    annex = {ANNEX_X + 1400, ANNEX_Y + 1400, 315},   -- 2U south-east of the Annex, facing north-west
    open  = {(SPAWN_U + 3) * U, 0, 270},             -- behind the Corsair line, facing the centre
}

-- ── State ────────────────────────────────────────────────────────────────────
local B = {battle = nil, started_at = 0, over = false, battles = 0}   -- open space
local A = {annex = nil, fight = nil, started_at = nil, over = false}   -- the Annex

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

-- ── The Annex fight ──────────────────────────────────────────────────────────

-- Ashgrave, the Annex and the Boneyard's nebulae, where the campaign has them (the nebulae come
-- from the universe's seed, so they are the same clouds).
local function buildBoneyard()
    for _, d in ipairs(VERSE.PLANETS) do
        if d.name == "Ashgrave" then VERSE.buildPlanet(d) end
    end
    local zone
    for _, r in ipairs(VERSE.REGIONS) do if r.name == "the Boneyard" then zone = r end end
    for _, n in ipairs(VERSE.nebulaSpots(VERSE.rng(VERSE.SEED))) do
        local f = n.field
        if zone and (f.x - zone.x) ^ 2 + (f.y - zone.y) ^ 2 <= zone.r ^ 2 then Nebula():setPosition(n.x, n.y) end
    end
    local a = SpaceStation():setTemplate("Small Station"):setFaction("Relic"):setCallSign("Ashgrave Annex")
    a:setPosition(ANNEX_X, ANNEX_Y):setCanBeDestroyed(false)
    a:setCommsFunction(function() setCommsMessage("[Ashgrave Annex]\n\nBattle Lab: the GM screen runs this fight.") end)
    A.annex = a
end

local function annexFight()
    if not A.fight then
        A.fight = BATTLE.annex(A.annex)
        A.fight.b.mult.a, A.fight.b.mult.b = SET.concord_impulse, SET.drone_impulse
    end
    return A.fight
end

local function spawnConcord()
    local f = annexFight()
    f:spawnConcord(SET.annex_concord)
    if not A.started_at then A.started_at = getScenarioTime() end
    A.over = false
    log(string.format("[BATTLELAB] Annex: %d Concord ships (impulse x%.2f)", SET.annex_concord, SET.concord_impulse))
end

local function spawnDrones()
    local f = annexFight()
    f:spawnDrones(SET.annex_drones)
    log(string.format("[BATTLELAB] Annex: %d drones (impulse %.0f x%.2f)",
        SET.annex_drones, f.drone_impulse, SET.drone_impulse))
end

local function armLasers()
    annexFight():armAnnex()
    log("[BATTLELAB] Annex: lasers armed")
end

local function clearAnnex()
    if A.fight then A.fight:clear() end
    A.fight, A.started_at, A.over = nil, nil, false
end

local function annexStatus()
    local f = A.fight
    if not f then return "=== ANNEX ===\nNothing spawned. Start, or spawn the Concord and the drones separately." end
    local t = A.started_at and math.floor(getScenarioTime() - A.started_at) or 0
    local lines = {string.format("=== ANNEX  (%d:%02d since the Concord spawned) ===", t // 60, t % 60),
        string.format("Concord: %d / %d alive   (impulse x%.2f)%s", f:concordAlive(), #f.concord, SET.concord_impulse,
            f.cmd and f.cmd:isValid() and string.format("; CNS Vanguard hull %.0f", f.cmd:getHull()) or ""),
        string.format("Drones: %d alive, %d / %d per nebula (NE / SW)   (impulse %.0f x%.2f)", f:dronesAlive(),
            f.quota[1], f.quota[2], f.drone_impulse, SET.drone_impulse),
        string.format("Drones replaced so far: %d", f.replaced),
        string.format("Annex lasers: %s%s", f.armed and "armed" or "not armed",
            f.laser_target and f.laser_target:isValid() and (", firing on " .. f.laser_target:getCallSign()) or ""),
        "", "Ships targeting each point, south-west to north-east (Concord / drones):"}
    for k = 1, f.b.n_points do
        local c, s = 0, 0
        for _, r in ipairs(f.b.sides.a) do if r.pos == k and r.ship:isValid() then c = c + 1 end end
        for _, r in ipairs(f.b.sides.b) do if r.pos == k and r.ship:isValid() then s = s + 1 end end
        lines[#lines + 1] = string.format("  %d: %d / %d", k, c, s)
    end
    return table.concat(lines, "\n")
end

local function statusText()
    local b = B.battle
    if not b then return "=== OPEN SPACE ===\nNo battle yet: Reset battle to start one." end
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

-- Move every player ship to the mode's starting place.
local function placeCrew()
    local at = CREW_AT[SET.mode]
    for i, p in ipairs(RT.players) do
        if p:isValid() then
            p:setPosition(at[1], at[2] + (i - 1) * 2 * U):setHeading(at[3])
            pcall(function() p:commandImpulse(0) end)
        end
    end
end

-- ── GM console ───────────────────────────────────────────────────────────────

local function nextStep(steps, cur)
    for i, v in ipairs(steps) do
        if math.abs(v - cur) < 1e-6 then return steps[i % #steps + 1] end
    end
    return steps[1]
end

local showGM

local function annexMenu()
    addGMFunction("Battle status", function() addGMMessage(annexStatus()) end)
    addGMFunction("Start (Concord + drones)", function() clearAnnex(); spawnConcord(); spawnDrones() end)
    addGMFunction(string.format("Spawn Concord (%d)", SET.annex_concord), spawnConcord)
    addGMFunction(string.format("Spawn drones (%d)", SET.annex_drones), spawnDrones)
    addGMFunction("Arm the Annex's lasers", armLasers)
    addGMFunction("Clear the battle", clearAnnex)
    addGMFunction("  Concord +1", function() SET.annex_concord = math.min(12, SET.annex_concord + 1); showGM() end)
    addGMFunction("  Concord -1", function() SET.annex_concord = math.max(1, SET.annex_concord - 1); showGM() end)
    addGMFunction("  Drones +2", function() SET.annex_drones = math.min(48, SET.annex_drones + 2); showGM() end)
    addGMFunction("  Drones -2", function() SET.annex_drones = math.max(2, SET.annex_drones - 2); showGM() end)
    addGMFunction(string.format("Concord impulse x%.2f", SET.concord_impulse), function()
        SET.concord_impulse = nextStep(IMPULSE_STEPS, SET.concord_impulse)
        if A.fight then A.fight.b:setImpulse("a", SET.concord_impulse) end
        showGM()
    end)
    addGMFunction(string.format("Drone impulse x%.2f", SET.drone_impulse), function()
        SET.drone_impulse = nextStep(IMPULSE_STEPS, SET.drone_impulse)
        if A.fight then A.fight.b:setImpulse("b", SET.drone_impulse) end
        showGM()
    end)
    addGMFunction("Mode: Annex -> open space", function()
        clearAnnex()
        SET.mode = "open"
        placeCrew()
        startBattle()
        showGM()
    end)
end

local function openMenu()
    addGMFunction("Battle status", function() addGMMessage(statusText()) end)
    addGMFunction("Reset battle (apply settings)", function() startBattle(); showGM() end)
    addGMFunction("Re-deal points by position", function()
        if B.battle then B.battle:assign("a"); B.battle:assign("b") end
    end)
    addGMFunction(string.format("Concord impulse x%.2f", SET.concord_impulse), function()
        SET.concord_impulse = nextStep(IMPULSE_STEPS, SET.concord_impulse)
        if B.battle then B.battle:setImpulse("a", SET.concord_impulse) end   -- applies at once
        showGM()
    end)
    addGMFunction(string.format("Corsair impulse x%.2f", SET.corsair_impulse), function()
        SET.corsair_impulse = nextStep(IMPULSE_STEPS, SET.corsair_impulse)
        if B.battle then B.battle:setImpulse("b", SET.corsair_impulse) end
        showGM()
    end)
    addGMFunction(string.format("Points %.1fU apart: closer", SET.spacing_u), function()
        SET.spacing_u = math.max(SPACING_MIN, SET.spacing_u - SPACING_STEP)
        if B.battle then B.battle:setSpacing(SET.spacing_u) end
        showGM()
    end)
    addGMFunction(string.format("Points %.1fU apart: further", SET.spacing_u), function()
        SET.spacing_u = math.min(SPACING_MAX, SET.spacing_u + SPACING_STEP)
        if B.battle then B.battle:setSpacing(SET.spacing_u) end
        showGM()
    end)
    addGMFunction(string.format("Concord ships: %d (on reset)", SET.n_concord), function() end)
    addGMFunction("  Concord +1", function() SET.n_concord = math.min(12, SET.n_concord + 1); showGM() end)
    addGMFunction("  Concord -1", function() SET.n_concord = math.max(1, SET.n_concord - 1); showGM() end)
    addGMFunction(string.format("Corsair ships: %d (on reset)", SET.n_corsair), function() end)
    addGMFunction("  Corsairs +1", function() SET.n_corsair = math.min(24, SET.n_corsair + 1); showGM() end)
    addGMFunction("  Corsairs -1", function() SET.n_corsair = math.max(1, SET.n_corsair - 1); showGM() end)
    addGMFunction("Mode: open space -> Annex", function()
        if B.battle then B.battle:clear() end
        B.battle = nil
        SET.mode = "annex"
        placeCrew()
        showGM()
    end)
end

showGM = function()
    clearGMFunctions()
    if SET.mode == "annex" then annexMenu() else openMenu() end
end

-- ── Scenario ─────────────────────────────────────────────────────────────────

function init()
    VERSE.setupFactions()            -- Concord Hostile, Corsair Friendly, Relic Active (no universe is built)
    RT.useCampaign("battlelab")      -- its own save, never the campaign's
    RT.loadCampaign(true)
    RT.PLAYER_TEMPLATE = "Light Freighter"
    buildBoneyard()
    local at = CREW_AT[SET.mode]
    RT.spawnPlayer(at[1], at[2], at[3])
    -- Ships made on the "Create player ship" screen join beside it.
    onNewPlayerShip(function(ship)
        local p = CREW_AT[SET.mode]
        ship:setPosition(p[1], p[2] + (#RT.players + 1) * 2 * U)
        ship:setFaction(RT.PLAYER_FACTION)
        RT.adoptPlayer(ship)
    end)
    showGM()
end

local function checkOpenSpace()
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

local function checkAnnex()
    local f = A.fight
    if not f then return end
    f:tick(getScenarioTime())
    if not A.over and #f.concord > 0 and f:concordAlive() == 0 then
        A.over = true
        local t = math.floor(getScenarioTime() - (A.started_at or 0))
        local msg = string.format("The Concord group is gone after %d:%02d. Drones lost: %d; drones left: %d.",
            t // 60, t % 60, f.replaced, f:dronesAlive())
        globalMessage(msg, 10)
        addGMMessage(msg .. "\n\nClear the battle, or spawn more Concord.")
        log("[BATTLELAB] Annex: " .. msg)
    end
end

function update(delta)
    RT.update(delta)
    checkOpenSpace()
    checkAnnex()
end
