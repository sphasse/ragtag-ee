-- ee/ragtag/tow.lua
-- TOW: a tow line. Anything can be offered for towing (a broken-down ship, a comet fragment); a
-- player ship within REACH of it gets an "Attach tow line" button on Engineering (and Single Pilot).
-- Attached, the object hangs LENGTH behind the ship and follows it: the engine's orbit component with
-- period 0 (setOrbit(ship, 0)), which puts it LENGTH from the ship along its bearing every frame, so it
-- trails like a rope and nothing knocks it off the line. While towing:
--   * the line shows: a beam (the engine's beam_effect, as weapons fire uses) from the ship to the
--     object, on the main screen and on radar, held lit while towing and fading out when it lets go;
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
--   TOW.intercept(ship, obj, count, {hail = "..."})  -- raiders come for it: returns their ships
--   TOW.breakOff(raiders)   -- they give up and fly off;  TOW.removeRaiders(raiders) -- gone
--
-- Raiders (TOW.intercept): Shroud Raiders posing as rival recovery outfits ("Jake's Towing &
-- Salvage"). The caller spawns them when the line first goes on; they appear INTERCEPT_DIST out,
-- the leader hails the crew to cut the prize loose, and they attack at once, at INTERCEPT_SPEED times
-- the line's limit, so a tow can't outrun them. Used by the tow job (some jobs, by tier) and Ice Haul.

TOW = TOW or {}

TOW.REACH     = 2000   -- the button shows within this of a towable object (world units)
TOW.LENGTH    = 1500   -- the line's length
TOW.DRAIN     = 3      -- extra energy a second at full impulse or at warp
TOW.MAX_SPEED = 250    -- the line snaps above this speed (world units/s): half of stock warp 1
TOW.LIMIT_TEXT = "half of warp 1, 15U a minute"   -- MAX_SPEED for the crew
TOW.SLACK     = 1.02   -- a hair over, for rounding
TOW.BEAM_TEXTURE = "texture/beam_blue.png"   -- the visible line (3D)
TOW.BEAM_COLOR   = {110, 190, 255, 170}      -- and on radar (alpha: how strong the line reads)
TOW.BEAM_FADE    = 2.5                        -- let go: it fades out over 1 / this seconds

TOW.INTERCEPT_DIST  = 10000   -- raiders appear this far from the towing ship
TOW.INTERCEPT_SPEED = 1.2     -- their impulse, as a multiple of MAX_SPEED
TOW.INTERCEPT_ACCEL = 150     -- impulse acceleration (world units/s^2): up to speed in a couple of seconds
TOW.INTERCEPT_TURN  = 25      -- degrees a second
TOW.INTERCEPT_SHIPS = {"Adder MK5", "MT52 Hornet"}   -- the first raider, the second
TOW.INTERCEPT_NAMES = {
    "Jake's Towing & Salvage", "Interspace AAA", "Finders Keepers Recovery", "No Questions Towing",
    "Honest Abe's Salvage", "Repo Rick's", "Grab & Go Recovery", "Second Owner Salvage",
    "24-Hour Hook & Haul", "Bargain Bin Recovery", "Totally Legit Towing", "Lien Machine",
    "Midnight Recovery Co.", "Dibs Salvage", "Cut Rate Towing", "Big Earl's Roadside",
}

TOW._offers = TOW._offers or {}   -- obj -> offer {obj, ship, name, on_attach, on_release}
TOW._lines  = TOW._lines or {}    -- ship -> offer it is towing
TOW._shown  = TOW._shown or {}    -- ship -> label its button shows (false: none)
TOW._beams  = TOW._beams or {}    -- ship -> the beam entity drawing its line

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

-- The visible line: a beam effect from the ship to the object. The engine moves it with both ends
-- every frame and fades it by `lifetime`; fade_speed 0 holds it lit until we let go. It has no
-- physics, so it adds nothing to the combat-music threat estimate (that only counts bodies).
local function _beamOn(ship, obj)
    local ok, e = pcall(function()
        local e = createEntity()
        local x, y = ship:getPosition()
        e.components = {
            transform = {},
            beam_effect = {source = ship, target = obj, lifetime = 1.0, fade_speed = 0, fire_ring = false,
                beam_texture = TOW.BEAM_TEXTURE, beam_color = TOW.BEAM_COLOR},
        }
        e:setPosition(x, y)
        return e
    end)
    if ok and e then TOW._beams[ship] = e else print("[TOW] beam failed: " .. tostring(e)) end
end

local function _beamOff(ship)
    local e = TOW._beams[ship]
    TOW._beams[ship] = nil
    if e and e:isValid() then
        pcall(function() e.components.beam_effect.fade_speed = TOW.BEAM_FADE end)   -- the engine removes it
    end
end

-- The beam drawing `ship`'s line, or nil.
function TOW.beam(ship) return TOW._beams[ship] end

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
    _beamOff(ship)
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
    _beamOn(ship, obj)
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
            local b = TOW._beams[ship]
            if not (b and b:isValid()) then _beamOn(ship, o.obj) end   -- lost somehow: draw it again
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

-- ── Raiders ──────────────────────────────────────────────────────────────────

local function _raiderNames(count)
    local pool = {}
    for _, n in ipairs(TOW.INTERCEPT_NAMES) do pool[#pool + 1] = n end
    for i = #pool, 2, -1 do
        local j = math.random(i); pool[i], pool[j] = pool[j], pool[i]
    end
    return pool
end

-- `count` raiders come for `obj` on `ship`'s line: INTERCEPT_DIST out on a random bearing, attacking at
-- once; the first hails `opts.hail` (or a stock line). Returns the list of their ships.
function TOW.intercept(ship, obj, count, opts)
    opts = opts or {}
    local out = {}
    if not _valid(ship) or (count or 0) <= 0 then return out end
    local px, py = ship:getPosition()
    local a = math.random() * 2 * math.pi
    local dx, dy = math.cos(a), math.sin(a)
    local sx, sy = px + dx * TOW.INTERCEPT_DIST, py + dy * TOW.INTERCEPT_DIST
    local names = _raiderNames(count)
    for i = 1, count do
        local s = CpuShip():setTemplate(TOW.INTERCEPT_SHIPS[i] or TOW.INTERCEPT_SHIPS[#TOW.INTERCEPT_SHIPS])
        s:setFaction("Shroud Raiders"):setCallSign(names[i] or ("Recovery " .. i))
        s:setPosition(sx - dy * (i - 1) * 800, sy + dx * (i - 1) * 800)
        s:setHeading((math.deg(a) + 270) % 360)   -- facing the ship
        s:setImpulseMaxSpeed(TOW.MAX_SPEED * TOW.INTERCEPT_SPEED, 100)
        s:setAcceleration(TOW.INTERCEPT_ACCEL, TOW.INTERCEPT_ACCEL)
        s:setRotationMaxSpeed(TOW.INTERCEPT_TURN)
        s:setDescriptions("Salvage outfit.", "Calls itself a recovery service. Its licence is a Shroud Raider's guns: "
            .. "they hunt the quiet lanes for ships that can't run and claim what they're hauling as salvage.")
        s:setCommsScript(""):setCommsFunction(function()
            setCommsMessage('"Still here? Last chance, tow truck. Cut it loose and run, and you keep your ship."')
        end)
        RT.register(s)
        RT.reportKills(s)
        s:orderAttack(ship)
        out[#out + 1] = s
    end
    local lead = out[1]
    local who = lead:getCallSign() .. (count > 1 and " and friends" or "")
    _log(ship, "[Science] Contacts closing fast, " .. math.floor(TOW.INTERCEPT_DIST / 1000) .. "U out: "
        .. who .. ". They're coming for the tow.", "#FF8040")
    local hail = opts.hail or ('"Well, well. Somebody sent a tow truck. Listen close, friend: what you\'ve got on '
        .. 'that line is ours. Finders keepers, and we found it first. Cut it loose, turn your nose around, and nobody '
        .. 'needs to get scratched."')
    local ok, sent = pcall(function() return lead:sendCommsMessage(ship, hail) end)
    if not (ok and sent) then _log(ship, "[" .. lead:getCallSign() .. "] " .. hail, "#FF8040") end
    return out
end

-- The raiders give up and fly off (whoever is left).
function TOW.breakOff(raiders)
    for _, s in ipairs(raiders or {}) do
        if _valid(s) then
            local x, y = s:getPosition()
            s:orderFlyTowards(x + math.random(-40000, 40000), y + math.random(-40000, 40000))
        end
    end
end

function TOW.removeRaiders(raiders)
    for _, s in ipairs(raiders or {}) do
        if _valid(s) then s:destroy() end
    end
end
