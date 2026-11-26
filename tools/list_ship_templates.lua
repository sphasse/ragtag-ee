-- tools/list_ship_templates.lua <EmptyEpsilon scripts dir>
-- Prints the name of every ship template EmptyEpsilon defines (not stations, not hidden ones), one per line:
-- "<template name>\t<name shown in the Science database>". Runs EE's own scripts/shipTemplates.lua with a stub
-- ShipTemplate API, so loops and copies come out right. tools/ship_templates.py writes the result to
-- tools/ee_ship_templates.txt; check.py reads that list to find the ships the game uses.
local dir = assert(arg[1], "usage: lua5.4 list_ship_templates.lua <EmptyEpsilon scripts dir>")

local all = {}
local T = {}
T.__index = function(self, k)
    return T[k] or function(s) return s end      -- every other setter: chainable no-op
end
local function new(name)
    local t = setmetatable({name = name, locale = name}, T)
    all[#all + 1] = t
    return t
end
function T.setName(self, n) self.name = n; self.locale = rawget(self, "locale") or n; return self end
function T.setLocaleName(self, n) self.locale = n; return self end
function T.setType(self, t) self.type = t; return self end
function T.hidden(self) self.is_hidden = true; return self end
function T.setHidden(self) self.is_hidden = true; return self end
function T.copy(self, n)
    local c = new(n)
    c.type = rawget(self, "type")
    return c
end

ShipTemplate = function() return new(nil) end
_ = function(a, b) return b or a end
__ship_templates = setmetatable({}, {__index = function() return new("?") end})
require = function(path) dofile(dir .. "/" .. path) end

dofile(dir .. "/shipTemplates.lua")

local seen, out = {}, {}
for _, t in ipairs(all) do
    local name, typ, hid = rawget(t, "name"), rawget(t, "type"), rawget(t, "is_hidden")   -- (no __index fallbacks)
    if name and name ~= "?" and typ ~= "station" and not hid and not seen[name] then
        seen[name] = true
        out[#out + 1] = name .. "\t" .. tostring(rawget(t, "locale") or name)
    end
end
table.sort(out)
for _, l in ipairs(out) do print(l) end
