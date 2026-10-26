-- fire_beat: Trigger a scenario story beat marked ai=true.
-- args: beat
DIR.ACTIONS.fire_beat = function(a, cmd)
    local id = DIR._h.str(a.beat, 40, "")
    local b = DIR.beats[id]
    if b == nil then return false, "no such beat" end
    if not b.ai and cmd.source ~= "gm" then return false, "beat is not AI-triggerable" end
    return DIR.fireBeat(id, cmd.source == "gm" and "gm" or "ai")
end
