-- gm_note: Private note to the human GM. The crew never sees it, so the model may send it.
-- args: text
DIR.ACTIONS.gm_note = function(a)
    addGMMessage("[AI] " .. DIR._h.str(a.text, 400, ""))
    return true, "noted"
end
