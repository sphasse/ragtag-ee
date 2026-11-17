-- say: Speak to the crew as a named character. GM only: the crew sees it, so the model may not
-- send it (the director is observation-only). The GM sends it from the director console.
-- args: speaker, text, channel = "hail" | "log"
DIR.ACTIONS.say = function(a, cmd)
    local h = DIR._h
    if not h.fromGM(cmd) then return false, "GM only" end
    local text = h.str(a.text, 500, nil)
    if text == nil or text == "" then return false, "text required" end
    if not RT.anyPlayerAlive() then return false, "no player ship" end
    local speaker = h.str(a.speaker, 40, "Unknown")
    local ent = RT.find(speaker)
    if a.channel ~= "log" and RT.valid(ent) and not RT.isPlayer(ent) then
        if RT.valid(RT.player) and ent:sendCommsMessage(RT.player, text) then
            -- Log to secondary ships so no one misses it
            for i = 2, #RT.players do
                if RT.valid(RT.players[i]) then RT.players[i]:addToShipLog("[" .. speaker .. "] " .. text, "#C0E0FF") end
            end
            return true, "hailed as " .. speaker
        end
        table.insert(DIR.pending_hails, {speaker = speaker, text = text, until_t = getScenarioTime() + 30})
        return true, "player comms busy; queued"
    end
    RT.shipLog("[" .. speaker .. "] " .. text, "#C0E0FF")
    return true, "logged as " .. speaker
end
