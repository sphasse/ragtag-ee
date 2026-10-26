-- main_screen: Short banner on every main screen.
-- args: text
DIR.ACTIONS.main_screen = function(a)
    local text = DIR._h.str(a.text, 120, nil)
    if text == nil or text == "" then return false, "text required" end
    globalMessage(text, 8)
    return true, "shown"
end
