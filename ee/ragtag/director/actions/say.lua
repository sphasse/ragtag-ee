-- say: Speak to the crew as a named character.
-- args: speaker, text, channel = "hail" | "log"
DIR.ACTIONS.say = function(a)
    local h = DIR._h
    local text = h.str(a.text, 500, nil)
    if text == nil or text == "" then return false, "text required" end
    if not RT.valid(RT.player) then return false, "no player ship" end
    local speaker = h.str(a.speaker, 40, "Unknown")
    local ent = RT.find(speaker)
    if a.channel ~= "log" and RT.valid(ent) and ent ~= RT.player then
        if ent:sendCommsMessage(RT.player, text) then return true, "hailed as " .. speaker end
        table.insert(DIR.pending_hails, {speaker = speaker, text = text, until_t = getScenarioTime() + 30})
        return true, "player comms busy; queued"
    end
    RT.player:addToShipLog("[" .. speaker .. "] " .. text, "#C0E0FF")
    return true, "logged as " .. speaker
end

-- say_sequence: Queue several lines from one speaker at timed intervals.
-- args: speaker, lines = [{text, delay}] (delay = seconds after previous line)
DIR.ACTIONS.say_sequence = function(a)
    local h = DIR._h
    if not RT.valid(RT.player) then return false, "no player" end
    local speaker = h.str(a.speaker, 40, "Unknown")
    if type(a.lines) ~= "table" or #a.lines == 0 then return false, "lines required" end
    local seq_id = "dir_seq_" .. DIR.seq
    local cum = 0
    local count = 0
    for i, line in ipairs(a.lines) do
        if i > 8 then break end
        local text = type(line) == "table" and h.str(line.text, 500, nil) or nil
        if text and text ~= "" then
            local d = type(line) == "table" and h.num(line.delay or 0, 0, 120, 0) or 0
            cum = cum + d
            count = count + 1
            if cum <= 0 then
                DIR.ACTIONS.say({speaker = speaker, text = text})
            else
                local cap = {spk = speaker, txt = text}
                RT.after(cum, function()
                    DIR.ACTIONS.say({speaker = cap.spk, text = cap.txt})
                end, seq_id .. "_" .. i)
            end
        end
    end
    return count > 0, count > 0 and ("queued " .. count .. " lines") or "no valid lines"
end
