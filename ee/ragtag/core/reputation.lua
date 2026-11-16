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

-- Modify reputation with a faction. Unbounded.
function RT.addReputation(faction, amount, reason)
    if not RT.campaign or not RT.campaign.reputation then return end
    if not RT.campaign.reputation[faction] then
        RT.campaign.reputation[faction] = 0
    end

    local old_rep = RT.campaign.reputation[faction]
    local new_rep = old_rep + amount
    RT.campaign.reputation[faction] = new_rep

    if amount ~= 0 then
        -- Line 1: what changed and why
        local sign = amount > 0 and "+" or ""
        local why  = reason and (" — " .. reason) or ""
        RT.shipLog(string.format("%s reputation %s%d%s", faction, sign, amount, why),
                   amount > 0 and "#80C0FF" or "#FF8080")

        -- Line 2: current standings for the three main factions
        local rtbl = RT.campaign.reputation
        local function _s(f)
            local r = rtbl[f] or 0
            return f .. ": " .. (r >= 0 and "+" or "") .. r
        end
        RT.shipLog("Current reputation: " .. _s("Independent") .. " | " .. _s("Concord") .. " | " .. _s("Corsairs"), "#888888")

        -- Line 3 (optional): threshold-crossing notification
        local thresholds = _REP_THRESHOLDS[faction] or _REP_THRESHOLDS._default
        for _, t in ipairs(thresholds) do
            local val, msg_up, msg_down = t[1], t[2], t[3]
            if old_rep < val and new_rep >= val then
                RT.shipLog("[Rep] " .. msg_up, "#80FF80")
            elseif old_rep >= val and new_rep < val then
                RT.shipLog("[Rep] " .. msg_down, "#FF8040")
            end
        end
    end

    RT.saveCampaign()
end

-- Get current reputation with a faction
function RT.getReputation(faction)
    if not RT.campaign or not RT.campaign.reputation then return 0 end
    return RT.campaign.reputation[faction] or 0
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

-- Register a ship for a reputation penalty when the PLAYER destroys it.
-- NPC-vs-NPC kills and scripted despawns cost nothing.
function RT.trackShipForReputation(ship)
    if not ship or not RT.valid(ship) then return end
    local faction = ship:getFaction()
    -- Skip player ships, inert factions, and presentation-only pseudo-factions.
    local skip = {
        [RT.PLAYER_FACTION] = true, Derelict = true, Unknown = true,
        ["Concord Hostile"] = true, ["Corsair Friendly"] = true, ["Relic Active"] = true,
    }
    if skip[faction] then return end
    local callsign = ship:getCallSign()   -- capture before entity is destroyed
    RT.onKill(ship, function(s, instigator)
        if RT._rep_cancelled[s] then return end
        if not RT.isPlayer(instigator) then return end
        RT.addReputation(faction, -200, "destroyed " .. callsign)
    end)
end
