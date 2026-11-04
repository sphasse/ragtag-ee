-- ee/ragtag/world/rumors.lua
-- WORLD plugin wrapper for the RUMORS information economy.
-- Loading this file makes RUMORS available as a toggleable world system.
-- Disabling the plugin suppresses all rumor delivery; cleanup flushes injected rumors.
require("ragtag/rumors.lua")

local _P = {}
_P.id      = "rumors"
_P.name    = "Rumors"
_P.defaults = {}

function _P.init(state)   end
function _P.update(state, delta, now) end
function _P.cleanup(state)
    RUMORS._injected = {}
end

WORLD.register(_P)
