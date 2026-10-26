-- spawn_salvage: A floating crate/pod the crew can pick up for credits.
-- args: near, distance, side, credits, label, description
DIR.ACTIONS.spawn_salvage = function(a)
    local h = DIR._h
    local cd, left = h.onCooldown("spawn_salvage", 120)
    if cd then return false, "salvage cooldown, " .. left .. "s left" end
    local x, y = h.resolvePoint(a, 6, 2, 20)
    if x == nil then return false, "no anchor" end
    local credits = math.floor(h.num(a.credits, 0, 150, 50))
    local label = h.str(a.label, 40, "Drifting cargo pod")
    local art = Artifact():setPosition(x, y):allowPickup(true)
    art:setDescriptions("Unidentified object", h.str(a.description, 200, label))
    art:setCallSign(label)
    art:onPickUp(function(obj, player)
        RT.addCredits(credits, label)
        DIR.emit("pickup", {label = label, credits = credits}, "normal")
    end)
    return true, "salvage placed (" .. credits .. " cr)"
end
