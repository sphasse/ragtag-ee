-- tools/dump_verse.lua
-- Load the universe data exactly as the game does (schema + drift + extensions)
-- and print it as JSON. Used by the Python tools; needs plain Lua 5.4.
--   lua5.4 tools/dump_verse.lua ee/ragtag
local root = arg[1] or "ee/ragtag"

-- The game's require() resolves "ragtag/..." under scripts/; emulate that.
function require(path)
    local rel = path:gsub("^ragtag/", "")
    dofile(root .. "/" .. rel)
end

dofile(root .. "/verse/schema.lua")
dofile(root .. "/verse/drift.lua")
for i = 2, #arg do dofile(arg[i]) end   -- extension files, in order

local problems, places = VERSE.validate()

local function enc(v, indent)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return tostring(v)
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return (math.type(v) == "integer") and tostring(v) or string.format("%.6g", v)
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            local map = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
            return map[c] or string.format("\\u%04x", c:byte())
        end) .. '"'
    elseif t == "table" then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        if n == #v then
            local parts = {}
            for _, x in ipairs(v) do table.insert(parts, enc(x)) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do table.insert(keys, tostring(k)) end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do table.insert(parts, enc(k) .. ":" .. enc(v[k])) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local out = {extensions = VERSE.extensions, problems = problems, places = places}
for key, T in pairs(VERSE.LISTS) do out[key] = VERSE[T] end
print(enc(out))
