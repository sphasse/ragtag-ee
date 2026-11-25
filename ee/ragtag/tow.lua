-- ee/ragtag/tow.lua
-- TOW: a tow line. Anything can be offered for towing (a broken-down ship, a comet fragment); a
-- player ship within REACH of it gets an "Attach tow line" button on Engineering (and Single Pilot).
-- Attached, the object hangs LENGTH behind the ship and follows it: the engine's orbit component with
-- period 0 (setOrbit(ship, 0)), which puts it LENGTH from the ship along its bearing every frame, so it
-- trails like a rope and nothing knocks it off the line. While towing:
--   * moving costs energy: up to DRAIN a second at full impulse or at warp (scaled by the throttle);
--   * the line holds up to MAX_SPEED (half of stock warp 1, 15U a minute) and snaps above it,
--     measured as speed: warp 1 is only safe with Engineering's warp power turned down to about half,
--     and Science reads the tow speed off its own screen ("Tow speed"), so the two tune it together.
--     The object is left where it is.
-- Used by the Ice Haul arc and the tow job (jobs/tow.lua). Loaded by core.lua; RT.update runs
-- TOW.update. Test: tests/core/orbit.lua (the line itself), tests/jobs/tow.lua, tests/arcs/icehaul.lua.
--
--   TOW.offer(obj, {ship = <the only ship that may tow it, or nil for any>, name = "the ice",
--                   on_attach = fn(ship, obj), on_release = fn(ship, obj, why)})
--        why: "cast off" (the button), "snapped", "withdrawn", "lost" (the ship is gone), "released"
--   TOW.withdraw(obj)       -- no longer towable (let go first if it is on a line)
--   TOW.release(obj)        -- let it go where it is (it stays offered)
--   TOW.towedBy(obj)        -- the ship towing it, or nil
--   TOW.press(ship)         -- what the button does: attach the nearest in reach, or cast off
--   TOW.buttonLabel(ship)   -- the label the ship's button shows now, or false

TOW = TOW or {}

TOW.REACH     = 2000   -- the button shows within this of a towable object (world units)
TOW.LENGTH    = 1500   -- the line's length
TOW.DRAIN     = 3      -- extra energy a second at full impulse or at warp
TOW.MAX_SPEED = 250    -- the line snaps above this speed (world units/s): half of stock warp 1
TOW.LIMIT_TEXT = "half of warp 1, 15U a minute"   -- MAX_SPEED for the crew
TOW.SLACK     = 1.02   -- a hair over, for rounding

TOW._offers = TOW._offers or {}   -- obj -> offer {obj, ship, name, on_attach, on_release}
TOW._lines  = TOW._lines or {}    -- ship -> offer it is towing
TOW._shown  = TOW._shown or {}    -- ship -> label its button shows (false: none)

local _BUTTON_STATIONS = {"engineering", "engineering+", "singlepilot"}
local _INFO_STATIONS = {"engineering", "engineering+"}
local _SPEED_STATIONS = {"science", "operations", "singlepilot"}   -- the tow speed readout

local function _valid(e) return e ~= nil and RT.valid(e) end

local function _dist(a, b)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function _log(ship, text, color)
    if _valid(ship) then pcall(function() ship:addToShipLog(text, color or "#A0E0FF") end) end
end

local function _warping(p)
    local ok, cur = pcall(function() local w = p.components.warp_drive; return w and w.current or 0 end)
    return ok and (cur or 0) > 0.01
end

-- The ship's speed (world units/s).
function TOW.speed(p)
    local ok, vx, vy = pcall(function() return p:getVelocity() end)
    if not ok or not vx then return 0 end
    return math.sqrt(vx * vx + (vy or 0) * (vy or 0))
end

-- The tow's energy cost a second right now for a ship: DRAIN at warp or at full impulse (either
-- way), scaled by the throttle the engines are actually giving; nothing while stopped.
function TOW.drain(p)
    if _warping(p) then return TOW.DRAIN end
    local ok, actual = pcall(function() local e = p.components.impulse_engine; return e and e.actual or 0 end)
    return TOW.DRAIN * math.min(1, math.abs(ok and actual or 0))
end

local function _info(p, on)
    for _, pos in ipairs(_INFO_STATIONS) do
        pcall(function()
            if on then p:addCustomInfo(pos, "tow_load_" .. pos, string.format("Tow load: up to -%d energy/s", TOW.DRAIN), 5)
            else p:removeCustom("tow_load_" .. pos) end
        end)
    end
    if not on then
        for _, pos in ipairs(_SPEED_STATIONS) do pcall(function() p:removeCustom("tow_speed_" .. pos) end) end
    end
end

-- "Tow speed: 14.2 of 15 U/min" for Science, redrawn when the shown value changes.
TOW._speed_shown = TOW._speed_shown or {}
function TOW.speedText(p)
    return string.format("Tow speed: %.1f of %d U/min", TOW.speed(p) * 60 / 1000, math.floor(TOW.MAX_SPEED * 60 / 1000 + 0.5))
end
local function _showSpeed(p)
    local text = TOW.speedText(p)
    if TOW._speed_shown[p] == text then return end
    TOW._speed_shown[p] = text
    for _, pos in ipairs(_SPEED_STATIONS) do
        pcall(function() p:addCustomInfo(pos, "tow_speed_" .. pos, text, 5) end)
    end
end

local function _setButton(p, label)
    if TOW._shown[p] == label then return end
    TOW._shown[p] = label
    for _, pos in ipairs(_BUTTON_STATIONS) do
        pcall(function()
            if label then p:addCustomButton(pos, "tow_line_" .. pos, label, function() TOW.press(p) end, 6)
            else p:removeCustom("tow_line_" .. pos) end
        end)
    end
end

function TOW.buttonLabel(p) return p and TOW._shown[p] or false end

function TOW.offer(obj, opts)
    if not _valid(obj) then return nil end
    opts = opts or {}
    local o = TOW._offers[obj] or {}
    o.obj, o.ship, o.name = obj, opts.ship, opts.name or obj:getCallSign()
    o.on_attach, o.on_release = opts.on_attach, opts.on_release
    TOW._offers[obj] = o
    return o
end

function TOW.towedBy(obj)
    for ship, o in pairs(TOW._lines) do
        if o.obj == obj then return ship end
    end
    return nil
end

-- Let go of whatever `ship` is towing. `why` is passed to on_release.
local function _letGo(ship, why)
    local o = TOW._lines[ship]
    if not o then return end
    TOW._lines[ship] = nil
    if _valid(o.obj) then o.obj.components.orbit = nil end
    TOW._speed_shown[ship] = nil
    if _valid(ship) then _info(ship, false) end
    if o.on_release then
        local ok, err = pcall(o.on_release, ship, o.obj, why)
        if not ok then print("[TOW] on_release error: " .. tostring(err)) end
    end
end

function TOW.release(obj)
    local ship = TOW.towedBy(obj)
    if ship then _letGo(ship, "released") end
end

function TOW.withdraw(obj)
    local ship = obj and TOW.towedBy(obj)
    if ship then _letGo(ship, "withdrawn") end
    if obj then TOW._offers[obj] = nil end
end

function TOW.attach(ship, obj)
    local o = TOW._offers[obj]
    if not o or not _valid(ship) or not _valid(obj) or TOW._lines[ship] or TOW.towedBy(obj) then return false end
    obj.components.orbit = {target = ship, center = {ship:getPosition()}, distance = TOW.LENGTH, time = 0}
    TOW._lines[ship] = o
    _info(ship, true)
    _log(ship, string.format("[Engineering] Tow line fast: %s trails %.1fU behind. Hauling costs up to %d energy a second. "
        .. "The line takes up to %s: warp 1 only with the warp drive's power at about half. Science has the tow speed. "
        .. "Any faster and it snaps.", o.name, TOW.LENGTH / 1000, TOW.DRAIN, TOW.LIMIT_TEXT))
    if o.on_attach then
        local ok, err = pcall(o.on_attach, ship, obj)
        if not ok then print("[TOW] on_attach error: " .. tostring(err)) end
    end
    return true
end

-- The nearest object `ship` may tow within REACH (not already on a line).
local function _inReach(ship)
    local best, best_d = nil, TOW.REACH
    for obj, o in pairs(TOW._offers) do
        if not _valid(obj) then
            TOW._offers[obj] = nil
        elseif (o.ship == nil or o.ship == ship) and not TOW.towedBy(obj) then
            local d = _dist(ship, obj)
            if d <= best_d then best, best_d = obj, d end
        end
    end
    return best
end

function TOW.press(ship)
    if not _valid(ship) then return end
    if TOW._lines[ship] then
        local o = TOW._lines[ship]
        _log(ship, "[Engineering] Tow line cast off. " .. o.name .. " is adrift.", "#FFAA40")
        _letGo(ship, "cast off")
    else
        local obj = _inReach(ship)
        if obj then TOW.attach(ship, obj) end
    end
end

function TOW.update(delta)
    for ship, o in pairs(TOW._lines) do
        if not _valid(ship) or not _valid(o.obj) or TOW._offers[o.obj] ~= o then
            _letGo(ship, "lost")
        elseif TOW.speed(ship) > TOW.MAX_SPEED * TOW.SLACK then
            _log(ship, "[Engineering] The tow line snapped: faster than " .. TOW.LIMIT_TEXT .. ", is more than it can take. "
                .. o.name .. " is adrift: go back for it.", "#FFAA40")
            _letGo(ship, "snapped")
        else
            local d = TOW.drain(ship) * (delta or 0)
            if d > 0 then ship:setEnergyLevel(math.max(0, ship:getEnergy() - d)) end
            _showSpeed(ship)
        end
    end
    for _, p in ipairs(RT.players or {}) do
        if _valid(p) then
            local label = false
            if TOW._lines[p] then label = "Release tow line"
            elseif _inReach(p) then label = "Attach tow line" end
            _setButton(p, label)
        end
    end
end
