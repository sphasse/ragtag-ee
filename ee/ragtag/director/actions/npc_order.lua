-- npc_order: Give an order to a director-controllable NPC.
-- args: callsign, order = attack|flee|idle|follow|patrol|dock, target
DIR.ACTIONS.npc_order = function(a)
    local h = DIR._h
    local cs = h.str(a.callsign, 40, "")
    if not DIR.controllable[cs] then return false, "not a controllable NPC" end
    local s = RT.find(cs)
    if not RT.valid(s) then return false, "NPC gone" end
    local order = h.str(a.order, 12, "idle")
    if order == "dock" then
        local t = RT.find(h.str(a.target, 40, ""))
        if not RT.valid(t) then return false, "dock target not found" end
        s:orderDock(t)
    else
        DIR.orderGroup({cs}, order)
    end
    return true, cs .. " -> " .. order
end
