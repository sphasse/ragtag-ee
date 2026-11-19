-- Name: Audit Lab
-- Description: A test bed for the Ledger arc's Concord Audit Service attack. Pick up the last AI fragment and carry it: the power drain, the AI's hello, the audit fleet a minute later, the warp jammers, the stop, the stalls and the fight run exactly as in the campaign. Reset and replay from the GM screen.
---
--- Built on the ragtag framework (scripts/ragtag/). Install with tools/install.py.
--- The carry is AUDIT (ragtag/missions/_audit.lua), the same code the Ledger arc runs, so tuning
--- found here carries over. No universe is built: open space at fragment 3's real place, near
--- Waypoint Galen.
-- Type: The Drift Universe

require("utils.lua")
require("ragtag/core.lua")
require("ragtag/verse.lua")                -- factions
require("ragtag/ship_templates.lua")       -- the Light Freighter
require("ragtag/world/_engine.lua")        -- WORLD (proximity.lua registers with it; never ticked here)
require("ragtag/world/proximity.lua")      -- PROX: the warp jammers
require("ragtag/missions/_helpers.lua")    -- ARC
require("ragtag/missions/_audit.lua")      -- AUDIT: the carry and the audit stop

local U = 1000

-- Fragment 3 of the Ledger arc ("near Waypoint Galen"); the crew starts 6U west of it, facing it.
local FRAG_X, FRAG_Y = -80000, -62000
local CREW_X, CREW_Y, CREW_HEADING = FRAG_X - 6000, FRAG_Y, 90

-- ── State ────────────────────────────────────────────────────────────────────
-- L is the carry's state table (AUDIT's fields: drain_on, fleet, audit, ...) plus the lab's own.
local L
local rounds = 0

local function fresh()
    return {fleet = {}, jammers = {}, warned = {}, carrying = false, frag = nil, picked_at = nil, ended = nil}
end

local function crew() local p = RT.players and RT.players[1]; if RT.valid(p) then return p end end

local function fmtTime(t)
    t = math.max(0, math.floor(t))
    return string.format("%d:%02d", t // 60, t % 60)
end

-- The round is over: say how, stop the drain, leave the field as it is until Reset.
local function endRound(how, ...)
    if not L.carrying then return end
    L.carrying = false
    L.ended = how
    AUDIT.drainOff(L)
    for _, line in ipairs({...}) do ARC.log(line, "#FF8080") end
    local msg = string.format("Round %d over after %s: %s.", rounds, fmtTime(getScenarioTime() - (L.picked_at or 0)), how)
    globalMessage(msg, 10)
    addGMMessage(msg .. "\n\nReset the round to go again.")
    log("[AUDITLAB] " .. msg)
end

local HOOKS = {
    active = function() return L.carrying end,
    surrender = function()
        ARC.log("[Ledger Arc] Data transmitted to the Concord Audit Service. The AI is gone.", "#FF8080")
        endRound("the crew transmitted the data")
    end,
    lost = function(reason, ...)
        endRound(reason == "power" and "the reactor hit zero, the AI is gone" or "the crew ejected the AI", ...)
    end,
    objective = function(text) RT.setObjective(text, true, "audit") end,
}

-- The last fragment: picking it up assembles the AI and starts the carry.
local function placeFragment()
    if RT.valid(L.frag) then L.frag:destroy() end
    local a = Artifact():setPosition(FRAG_X, FRAG_Y):allowPickup(true)
    a:setCallSign("Data core")
    a:setDescriptions("Small object, cold.",
        "Encrypted data core, powered down to a trickle. The handshake matches the key Rezkov gave us. Fly into it to take it aboard.")
    a:setScanningParameters(1, 2)
    a:onPickUp(function()
        if L.carrying or L.ended then return end
        ARC.log("[Ledger Arc] AI fragment 3 recovered (3/3).", "#80FF80")
        L.carrying, L.picked_at = true, getScenarioTime()
        AUDIT.start(L, HOOKS)
        log("[AUDITLAB] round " .. rounds .. ": fragment picked up")
    end)
    L.frag = a
end

local function reset()
    if L then
        AUDIT.drainOff(L)
        AUDIT.despawnFleet(L)
        if RT.valid(L.frag) then L.frag:destroy() end
    end
    RT.voice.destroy("ledger_ai")
    RT.clearObjective("audit")
    L = fresh()
    rounds = rounds + 1
    local p = crew()
    if p then
        p:setPosition(CREW_X, CREW_Y):setHeading(CREW_HEADING)
        pcall(function() p:commandImpulse(0) end)
        p:setEnergyLevel(p:getMaxEnergy())
        p:setHull(p:getHullMax())
        local full = {}
        for i = 0, p:getShieldCount() - 1 do full[#full + 1] = p:getShieldMax(i) end
        if #full > 0 then p:setShields(table.unpack(full)) end
    end
    placeFragment()
    RT.setObjective("Pick up the data core (fragment 3)", true, "audit")
end

local function status()
    local now = getScenarioTime()
    local lines = {string.format("=== AUDIT LAB, round %d ===", rounds)}
    if L.ended then
        lines[#lines + 1] = "Over: " .. L.ended
    elseif not L.carrying then
        lines[#lines + 1] = "Waiting: the data core is 6U east of the crew's start."
    else
        lines[#lines + 1] = "Carrying the AI for " .. fmtTime(now - L.picked_at)
    end
    local p = crew()
    if p then
        lines[#lines + 1] = string.format("Energy %.0f / %.0f (drain %s, -%d/s)", p:getEnergy(), p:getMaxEnergy(),
            L.drain_on and "on" or "off", AUDIT.DRAIN_PER_S)
    end
    if L.carrying and not L.fleet_spawned and L.fleet_due then
        lines[#lines + 1] = "Audit fleet due in " .. fmtTime(L.fleet_due - now)
    end
    local a = L.audit
    if a then
        lines[#lines + 1] = string.format("Audit: %s, stalls %d / %d", a.state, a.stalls, AUDIT.MAX_STALLS)
        if a.state == "stopped" and a.hailed then
            lines[#lines + 1] = "  attack in " .. fmtTime(AUDIT.TIMEOUT - (now - a.last)) .. " unless they talk or stall"
        end
        local jams = 0
        for _, j in ipairs(a.jams or {}) do if RT.valid(j) then jams = jams + 1 end end
        lines[#lines + 1] = "  jammers up: " .. jams
    end
    for _, s in ipairs(L.fleet or {}) do
        if RT.valid(s) then
            lines[#lines + 1] = string.format("  %s (%s): hull %.0f / %.0f, %.1fU away", s:getCallSign(), s:getFaction(),
                s:getHull(), s:getHullMax(), p and RT.dist(p, s) / U or 0)
        end
    end
    return table.concat(lines, "\n")
end

-- ── GM console ───────────────────────────────────────────────────────────────

local showGM
showGM = function()
    clearGMFunctions()
    addGMFunction("Status", function() addGMMessage(status()) end)
    addGMFunction("Reset the round", function() reset(); showGM() end)
    addGMFunction("Pick up the core now", function()
        if L.carrying or L.ended then return end
        local p = crew()
        if p and RT.valid(L.frag) then L.frag:setPosition(p:getPosition()) end   -- the pickup fires on contact
    end)
    addGMFunction("Fleet now", function() if L.carrying then AUDIT.spawnFleet(L, HOOKS) end end)
    addGMFunction("Auditors hostile now", function() if L.audit then AUDIT.hostile(L, HOOKS, "refused") end end)
    addGMFunction("Pause / resume drain", function()
        if not L.carrying then return end
        if L.drain_on then AUDIT.drainOff(L) else AUDIT.resumeDrain(L) end
    end)
    addGMFunction("Refill energy", function()
        local p = crew()
        if p then p:setEnergyLevel(p:getMaxEnergy()) end
    end)
end

-- ── Scenario ─────────────────────────────────────────────────────────────────

function init()
    VERSE.setupFactions()             -- Concord, Concord Hostile (no universe is built)
    RT.useCampaign("auditlab")        -- its own save, never the campaign's
    RT.loadCampaign(true)
    RT.PLAYER_TEMPLATE = "Light Freighter"
    RT.spawnPlayer(CREW_X, CREW_Y, CREW_HEADING)
    onNewPlayerShip(function(ship)
        ship:setPosition(CREW_X, CREW_Y + (#RT.players + 1) * 2 * U)
        ship:setFaction(RT.PLAYER_FACTION)
        RT.adoptPlayer(ship)
    end)
    -- The crew's ship destroyed with the AI aboard: the AI dies with it.
    RT.on(function(ev)
        if ev.type == "ship_lost" and ev.data.primary and L and L.carrying then
            endRound("the ship was destroyed with the AI aboard")
        end
    end)
    reset()
    showGM()
end

function update(delta)
    RT.update(delta)
    if not L or not L.carrying then return end
    local now = getScenarioTime()
    AUDIT.tick(L, HOOKS, delta, now)
    if not L.carrying then return end
    -- Not arc endings, but worth a report: the fleet destroyed, or the crew got away.
    if L.fleet_spawned and not L.fleet_report then
        local alive = 0
        for _, s in ipairs(L.fleet) do if RT.valid(s) then alive = alive + 1 end end
        if L.fleet_gone or alive == 0 then
            L.fleet_report = true
            local msg = string.format("Round %d: the audit fleet is gone after %s (%s). The AI is still aboard.",
                rounds, fmtTime(now - L.picked_at), L.audit and L.audit.state or "?")
            addGMMessage(msg)
            log("[AUDITLAB] " .. msg)
        end
    end
end
