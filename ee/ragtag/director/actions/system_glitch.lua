-- system_glitch: Knock a ship system's health down (engineering gets something to do).
-- args: system, severity (0.1 - 0.5), reason
DIR.ACTIONS.system_glitch = function(a)
    local h = DIR._h
    if not RT.valid(RT.player) then return false, "no player" end
    local sys = DIR.SYSTEMS[string.lower(h.str(a.system, 20, "") or "")]
    if sys == nil then return false, "unknown system" end
    if not RT.player:hasSystem(sys) then return false, "ship lacks that system" end
    local cd, left = h.onCooldown("system_glitch", DIR.config.glitch_cooldown)
    if cd then return false, "glitch cooldown, " .. left .. "s left" end
    local sev = h.num(a.severity, 0.1, 0.5, 0.25)
    local current = RT.player:getSystemHealth(sys)
    RT.player:setSystemHealth(sys, math.max(-0.3, current - sev))
    if a.reason then RT.player:addToShipLog("Engineering: " .. h.str(a.reason, 120, ""), "#FFA060") end
    return true, sys .. " health " .. math.floor((current - sev) * 100) .. "%"
end
