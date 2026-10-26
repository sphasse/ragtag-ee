-- comms_tree: Pre-load a reply tree onto a director NPC so comms hail is instant.
-- args: callsign, opening, options = [{label, reply}]
DIR.ACTIONS.comms_tree = function(a)
    local h = DIR._h
    local cs = h.str(a.callsign, 24, "")
    if cs == "" then return false, "callsign required" end
    if type(a.options) ~= "table" or #a.options == 0 then return false, "options required" end
    DIR.npc_info[cs] = DIR.npc_info[cs] or {}
    if a.opening then DIR.npc_info[cs].greeting = h.str(a.opening, 300, nil) end
    local opts = {}
    for i, opt in ipairs(a.options) do
        if i > 4 then break end
        if type(opt) == "table" then
            local label = h.str(opt.label, 80, nil)
            local reply = h.str(opt.reply, 300, nil)
            if label and reply then table.insert(opts, {label = label, reply = reply}) end
        end
    end
    if #opts == 0 then return false, "no valid options" end
    DIR.npc_info[cs].tree = opts
    return true, "comms tree set for " .. cs .. " (" .. #opts .. " options)"
end
