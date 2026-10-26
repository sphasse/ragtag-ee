-- spawn_npc: Spawn a single non-combat NPC the crew can talk to.
-- args: role = trader|patrol|derelict|stranger, faction, callsign, near, distance, side, greeting, description
DIR.ACTIONS.spawn_npc = function(a)
    local h = DIR._h
    local role = h.str(a.role, 12, "trader")
    local faction = h.str(a.faction, 30, role == "patrol" and "Concord" or "Independent")
    if not h.factionAllowed(faction) then return false, "faction not allowed" end
    if DIR.config.hostile_factions[faction] and role ~= "derelict" then
        return false, "use spawn_group for hostile factions"
    end
    local cd, left = h.onCooldown("spawn_npc", 45)
    if cd then return false, "npc cooldown, " .. left .. "s left" end
    local tmpl = ({trader = "Flavia", patrol = "Phobos M3", derelict = "Tug", stranger = "Piranha F12"})[role]
    if tmpl == nil then return false, "role must be trader/patrol/derelict/stranger" end
    local x, y = h.resolvePoint(a, 8, 3, 25)
    if x == nil then return false, "no anchor" end
    local s = CpuShip():setTemplate(tmpl):setFaction(faction):setPosition(x, y)
    local cs = h.uniqueCallsign(a.callsign)
    if cs then s:setCallSign(cs) end
    cs = s:getCallSign()
    if a.description then s:setDescription(h.str(a.description, 300, "")) end
    if role == "derelict" then
        s:orderIdle()
        s:setHull(math.max(1, s:getHullMax() * 0.15))
        s:setImpulseMaxSpeed(0)
        s:setShieldsMax(0)
    elseif role == "patrol" then
        s:orderRoaming()
    else
        s:orderIdle()
    end
    DIR.npc_info[cs] = {greeting = h.str(a.greeting, 300, nil), role = role}
    s:setCommsFunction(DIR.npcComms)
    table.insert(DIR.spawned, s)
    DIR.allowControl(s)
    return true, "spawned " .. role .. " " .. cs
end
