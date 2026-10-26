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
        local enemy_str = RT.shipStrength(s)
        s:onDestruction(function(ship, instigator)
            local by_player = instigator ~= nil and instigator == RT.player
            DIR.emit("destroyed", {callsign = ship:getCallSign(), faction = ship:getFaction(),
                by_player = by_player and 1 or 0}, "normal")
            if by_player then
                local player_str = RT.shipStrength(RT.player)
                local ratio = enemy_str.total > 0 and math.floor(player_str.total * 100 / enemy_str.total) / 100 or 0
                DIR.emit("combat_kill", {
                    callsign   = ship:getCallSign(),
                    faction    = ship:getFaction(),
                    enemy_str  = enemy_str,
                    player_str = player_str,
                    ratio      = ratio,
                }, "normal")
            end
        end)
        table.insert(names, s:getCallSign())
    end
    DIR.orderGroup(names, behavior)
    return true, "spawned " .. table.concat(names, ", ")
end
