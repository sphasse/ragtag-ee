-- spawn_group: Spawn a group of ships.
-- args: faction, strength, near, distance, side, behavior, callsign
DIR.ACTIONS.spawn_group = function(a)
    local h = DIR._h
    local faction = h.str(a.faction, 30, "Corsairs")
    if not h.factionAllowed(faction) then return false, "faction not allowed" end
    local strength = h.str(a.strength, 10, "light")
    local templates = DIR.GROUPS[strength]
    if templates == nil then return false, "strength must be scout/light/medium/heavy" end
    local hostile = DIR.config.hostile_factions[faction] or false
    if hostile then
        local alive = DIR.countAIHostiles()
        if alive + #templates > DIR.config.max_ai_hostiles then
            return false, string.format("hostile budget exceeded (%d alive, max %d)", alive, DIR.config.max_ai_hostiles)
        end
        local cd, left = h.onCooldown("spawn_group", DIR.config.spawn_cooldown)
        if cd then return false, "spawn cooldown, " .. left .. "s left" end
    end
    local x, y = h.resolvePoint(a, 12, 6, 30)
    if x == nil then return false, "no anchor" end
    local behavior = h.str(a.behavior, 20, hostile and "attack" or "idle")
    local base = h.uniqueCallsign(a.callsign)
    local leader = nil
    local names = {}
    for i, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction(faction)
        local cs = base and (i == 1 and base or (base .. "-" .. i)) or nil
        if cs and RT.find(cs) == nil then s:setCallSign(cs) end
        if leader == nil then
            s:setPosition(x, y)
            leader = s
        else
            s:setPosition(x + random(-600, 600), y + random(-600, 600))
        end
        table.insert(DIR.spawned, s)
        DIR.allowControl(s)
        s:setCommsFunction(DIR.npcComms)
        DIR.registerKill(s)
        table.insert(names, s:getCallSign())
    end
    DIR.orderGroup(names, behavior)
    return true, "spawned " .. table.concat(names, ", ")
end
