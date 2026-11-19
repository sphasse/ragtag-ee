-- ee/ragtag/core/reputation.lua
-- Faction reputation, threshold notices, and kill tracking (RT.addReputation, RT.onKill, ...).
-- Part of core (RT). Loaded by ee/ragtag/core.lua; do not require directly.

--------------------------------------------------------------------------------
-- Reputation system
--------------------------------------------------------------------------------

-- Threshold table for rep-change notifications.
-- Concord has inspection-specific entries; _default covers job-access thresholds for all factions.
local _REP_THRESHOLDS = {
    Concord = {
        { 500, "Concord will now wave you through inspections without stopping.",
                "Concord will now conduct inspections again." },
        { 200, "Concord now accepts cargo declarations without proof.",
                "Concord no longer accepts cargo declarations without proof." },
        {   0, "Concord patrols give benefit of doubt on ignored hails.",
                "Concord patrols will now turn hostile over ignored inspections." },
        {-200, "More work becoming available at Concord ports.",
                "Very few jobs available at Concord ports." },
        {-400, "Concord ports may offer limited work again.",
                "Concord ports will no longer offer work." },
        {-500, "Concord inspection protocols restored.",
                "Concord patrols will now attack on sight." },
    },
    Corsairs = {
        {   0, "Full job access restored at Corsair-adjacent ports.",
                "Fewer jobs offered at Corsair-adjacent ports." },
        {-200, "Corsair patrol pressure easing — longer intercept intervals.",
                "Corsair patrols becoming more aggressive in their territory." },
        {-400, "Some work returning at Corsair-adjacent ports.",
                "Corsairs are now actively targeting your ship." },
    },
    _default = {
        {   0, "Full job access restored at this faction's ports.",
                "Fewer jobs will be offered at this faction's ports." },
        {-200, "More work becoming available at this faction's ports.",
                "Very limited jobs available at this faction's ports." },
        {-400, "Some jobs may return at this faction's ports.",
                "This faction will no longer offer work." },
    },
}

-- Standing is kept per ship, in the ship's record (core.lua, "Per-ship records"). The primary
-- ship's standing is the one story arcs read; every other player ship starts at zero. Functions
-- take a `ship`; without one they mean the primary ship (for arcs only: check.py requires the
-- ship everywhere else).

local function _repTable(ship)
    local rec = RT.shipRecord(ship)
    return rec and rec.reputation, RT.playerShip(ship) or RT.player
end

-- Modify a ship's reputation with a faction (default: the primary ship). Unbounded.
function RT.addReputation(faction, amount, reason, ship)
    local rtbl, who = _repTable(ship)
    if not rtbl then return end
    local old_rep = rtbl[faction] or 0
    local new_rep = old_rep + amount
    rtbl[faction] = new_rep

    if amount ~= 0 and RT.valid(who) then
        local function say(msg, color) who:addToShipLog(msg, color or "#FFFFFF") end
        -- Line 1: what changed and why
        local sign = amount > 0 and "+" or ""
        local why  = reason and (" — " .. reason) or ""
        say(string.format("%s reputation %s%d%s", faction, sign, amount, why),
            amount > 0 and "#80C0FF" or "#FF8080")

        -- Line 2: current standings for the three main factions
        local function _s(f)
            local r = rtbl[f] or 0
            return f .. ": " .. (r >= 0 and "+" or "") .. r
        end
        say("Current reputation: " .. _s("Independent") .. " | " .. _s("Concord") .. " | " .. _s("Corsairs"), "#888888")

        -- Line 3 (optional): threshold-crossing notification
        local thresholds = _REP_THRESHOLDS[faction] or _REP_THRESHOLDS._default
        for _, t in ipairs(thresholds) do
            local val, msg_up, msg_down = t[1], t[2], t[3]
            if old_rep < val and new_rep >= val then
                say("[Rep] " .. msg_up, "#80FF80")
            elseif old_rep >= val and new_rep < val then
                say("[Rep] " .. msg_down, "#FF8040")
            end
        end
    end

    RT.saveCampaign()
end

-- A ship's current reputation with a faction (default: the primary ship).
function RT.getReputation(faction, ship)
    local rtbl = _repTable(ship)
    if not rtbl then return 0 end
    return rtbl[faction] or 0
end

-- Destruction callbacks. EE's onDestruction holds a single callback per entity,
-- so this dispatcher lets several systems (reputation, director events, loot
-- drops) hook the same ship without clobbering each other.
-- fn(ship, instigator). onDestruction only fires on damage kills, never on a
-- scripted destroy(), and instigator identifies the killer.
RT._kill_cbs      = setmetatable({}, {__mode = "k"})
RT._rep_cancelled = setmetatable({}, {__mode = "k"})

function RT.onKill(ship, fn)
    if not ship or not RT.valid(ship) then return end
    local cbs = RT._kill_cbs[ship]
    if cbs == nil then
        cbs = {}
        RT._kill_cbs[ship] = cbs
        ship:onDestruction(function(s, instigator)
            for _, cb in ipairs(cbs) do
                local ok, err = pcall(cb, s, instigator)
                if not ok then log("[RT] kill callback failed: " .. tostring(err)) end
            end
        end)
    end
    cbs[#cbs + 1] = fn
end

-- Suppress the reputation penalty for a ship an arc is managing itself.
-- (Scripted destroy() never fires onDestruction anyway; this covers arcs that
-- let a ship die to damage but apply their own consequences.)
function RT.cancelKillTracking(ship)
    if ship ~= nil then RT._rep_cancelled[ship] = true end
end

-- The kill penalty: a player ship that destroys a ship loses RT.KILL_PENALTY standing with that
-- ship's faction, judged when it dies (a job target that turned Corsair counts as Corsairs).
-- Presentation-only factions count as the faction they stand for; only the factions with
-- standing (RT.KILL_PENALTY_FACTIONS) are charged. NPC-vs-NPC kills, scripted despawns and
-- ships an arc or job took out of tracking (RT.cancelKillTracking, ARC.register) cost nothing.
RT.KILL_PENALTY = 200
RT.KILL_PENALTY_FACTIONS = {Independent = true, Concord = true, Corsairs = true}
local _REAL_FACTION = {["Concord Hostile"] = "Concord", ["Corsair Friendly"] = "Corsairs"}

function RT.trackShipForReputation(ship)
    if not ship or not RT.valid(ship) then return end
    RT.onKill(ship, function(s, instigator)
        if RT._rep_cancelled[s] then return end
        local killer = RT.playerShip(instigator)
        if not killer then return end
        local ok, fac = pcall(function() return s:getFaction() end)
        if not ok or fac == nil then return end
        fac = _REAL_FACTION[fac] or fac
        if not RT.KILL_PENALTY_FACTIONS[fac] then return end
        local cs = "a ship"
        pcall(function() cs = s:getCallSign() end)
        RT.addReputation(fac, -RT.KILL_PENALTY, "destroyed " .. cs, killer)
    end)
end
