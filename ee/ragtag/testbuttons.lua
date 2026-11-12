-- ee/ragtag/testbuttons.lua
-- TESTBTN: temporary test buttons on the crew stations, to see how custom buttons, info labels
-- and messages look and behave on each console. Nothing game-meaningful. Toggle from the GM menu
-- ("Test buttons: ON/OFF"); remove this file and its require in core.lua when done.
--
-- Each station gets:
--   * a button  "Test: <Station>"   (addCustomButton)  - pressed: a dismissable message on that station
--   * an info line "Test info: <Station>" (addCustomInfo)
-- Applied to every player ship, including ships added later (checked every 3 s).

TESTBTN = TESTBTN or {}
TESTBTN.enabled = true
TESTBTN._ships  = setmetatable({}, {__mode = "k"})   -- ship -> true once buttons are on it
TESTBTN._next   = 0
TESTBTN.presses = 0

-- EmptyEpsilon crew-position keys (lowercase) and a display name.
TESTBTN.STATIONS = {
    {"helms",       "Helm"},
    {"weapons",     "Weapons"},
    {"engineering", "Engineering"},
    {"science",     "Science"},
    {"relay",       "Relay"},
    {"operations",  "Operations"},
}

local function _keys(station)
    return "rt_test_btn_" .. station, "rt_test_info_" .. station, "rt_test_msg_" .. station
end

function TESTBTN.apply(p)
    for i, s in ipairs(TESTBTN.STATIONS) do
        local station, name = s[1], s[2]
        local btn, info, msg = _keys(station)
        pcall(function()
            p:addCustomButton(station, btn, "Test: " .. name, function()
                TESTBTN.presses = TESTBTN.presses + 1
                pcall(function()
                    p:addCustomMessage(station, msg, string.format(
                        "Test button pressed on %s (press #%d).\n\nThis message stays until dismissed.",
                        name, TESTBTN.presses))
                end)
                log("[TESTBTN] pressed on " .. name .. " (#" .. TESTBTN.presses .. ")")
            end, 90 + i)
            p:addCustomInfo(station, info, "Test info: " .. name, 90 + i)
        end)
    end
    TESTBTN._ships[p] = true
    log("[TESTBTN] buttons added to " .. tostring(p:getCallSign()))
end

function TESTBTN.remove(p)
    for _, s in ipairs(TESTBTN.STATIONS) do
        local btn, info, msg = _keys(s[1])
        for _, key in ipairs({btn, info, msg}) do
            pcall(function() p:removeCustom(key) end)
        end
    end
    TESTBTN._ships[p] = nil
end

function TESTBTN.setEnabled(on)
    TESTBTN.enabled = on and true or false
    TESTBTN._next = 0   -- apply on the next update
end

function TESTBTN.update()
    local now = getScenarioTime()
    if now < TESTBTN._next then return end
    TESTBTN._next = now + 3
    for _, p in ipairs(RT.players or {}) do
        if RT.valid(p) then
            if TESTBTN.enabled and not TESTBTN._ships[p] then
                TESTBTN.apply(p)
            elseif not TESTBTN.enabled and TESTBTN._ships[p] then
                TESTBTN.remove(p)
            end
        end
    end
end
