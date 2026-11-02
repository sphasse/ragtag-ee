-- ee/ragtag/CustomObjects/platforms/platforms.lua
-- Stationary gun platforms that aim at enemy player ships and fire HVLI shells.
--
-- Ported from the Barrage and Lance platforms in "Unstable 235" (scenario_69_unstable235.lua,
-- written for EE-2024.12.08). That script used the old HVLI() constructor, which no longer
-- exists in the ECS engine (EE-2026.09.22PR has no Lua HVLI/missile constructors), so the
-- shells here are built from components the same way the engine builds a tube-fired HVLI
-- (src/systems/missilesystem.cpp, MissileSystem::spawnProjectile).
--
-- Behaviour (both kinds):
--   * Track the nearest enemy player ship, turning at `turn_rate` degrees per second.
--   * Hold fire unless that ship is between `min_range_fraction` (default 0%, i.e. point blank) and 100% of
--     `max_range`. `max_range` is also how far the shells fly, so a shell fired at a ship at
--     max range can still reach it.
--   * While firing, sweep the aim back and forth `strafe_degrees` (default 10) either side of
--     the target, one full sweep every `strafe_period` seconds.
--
-- Kinds:
--   "barrage"  several barrels fired together as a tight fan (`fan_spread` degrees apart).
--   "lance"    one barrel, faster cadence: a single stream walked across the target.
--
-- Usage in a scenario:
--   require("ragtag/CustomObjects/platforms/platforms.lua")
--   -- in init(), after factions exist (VERSE.setupFactions()):
--   PLATFORMS.spawn{kind = "barrage", x = x, y = y, faction = "Corsairs"}
--   PLATFORMS.spawn{kind = "lance", x = x2, y = y2, faction = "Corsairs", max_range = 8000}
--   -- in update(delta):
--   PLATFORMS.update(delta)
--
-- With the ragtag universe, place them relative to a universe place:
--   local x, y = VERSE.at("Some Place", 6, -3)   -- 6u east, 3u north of it

PLATFORMS = PLATFORMS or {}

-- Defaults for every platform. Any of these can be overridden per platform in spawn{...}.
PLATFORMS.defaults = {
    template = "Small Station",
    max_range = 6000,           -- firing range and shell travel distance (1u = 1000)
    min_range_fraction = 0,     -- hold fire closer than this fraction of max_range (0 = fire point blank)
    turn_rate = 45,             -- degrees per second the platform turns to track
    strafe_degrees = 10,        -- sweep this far either side of the target while firing
    strafe_period = 3,          -- seconds for one full back-and-forth sweep
    muzzle_offset = 600,        -- shells spawn this far from the platform's center
    shell_speed = 500,          -- stock HVLI speed
    shell_damage = 10,          -- stock HVLI damage
}

PLATFORMS.kinds = {
    barrage = {barrels = 3, fan_spread = 8, interval = 4.8, label = "Barrage Platform",
        description = "A gun platform. Its HVLI barrels fire in a tight fan, sweeping across whatever it targets."},
    lance = {barrels = 1, fan_spread = 0, interval = 2.8, label = "Lance Platform",
        description = "A gun platform. It walks a single fast stream of HVLIs back and forth across its target."},
}

PLATFORMS.list = {}
local _count = 0

-- Signed shortest difference from angle a to angle b, in (-180, 180].
local function angleDiff(a, b)
    return (b - a + 180) % 360 - 180
end

-- Fires one HVLI shell. Mirrors the engine's tube-fired HVLI component set.
-- (The engine also adds destroyed_by_area_damage, which has no Lua binding; the only
-- effect of leaving it out is that EMP/energy blasts don't shoot these shells down.)
local function fireShell(owner, x, y, rotation, speed, range, damage)
    local e = createEntity()
    e.components.transform = {rotation = rotation}
    e:setPosition(x, y)
    e.components.physics = {type = "sensor", size = {10, 30}}
    e.components.missile_flight = {speed = speed}
    e.components.explode_on_touch = {
        damage_at_center = damage, damage_at_edge = damage, blast_range = 20,
        owner = owner, explosion_sfx = "sfx/explosion.wav",
    }
    e.components.lifetime = {lifetime = range / speed}
    e.components.radar_trace = {icon = "radar/missile.png", radius = 32, min_size = 16, max_size = 16,
        color = {200, 200, 200, 255}, rotate = true}
    e.components.radar_signature = {gravity = 0.1}
    e.components.constant_particle_emitter = {}
    e.components.sfx = {sound = "sfx/hvli_fire.wav"}
    local faction = owner:getFaction()
    if faction then e:setFaction(faction) end
    return e
end

-- Nearest valid player ship that is an enemy of `station`, and its distance.
local function nearestEnemyPlayer(station)
    local best, best_d = nil, nil
    for _, p in ipairs(getActivePlayerShips()) do
        if p:isValid() and station:isEnemy(p) then
            local d = distance(station, p)
            if best_d == nil or d < best_d then best, best_d = p, d end
        end
    end
    return best, best_d
end

--- Creates a platform and starts tracking it. Returns the station entity.
-- opts: kind ("barrage"|"lance"), x, y, faction (required); callsign, plus any key from
-- PLATFORMS.defaults or PLATFORMS.kinds[kind] to override it for this platform.
function PLATFORMS.spawn(opts)
    local kind = PLATFORMS.kinds[opts.kind or "barrage"]
    assert(kind, "PLATFORMS.spawn: unknown kind " .. tostring(opts.kind))
    assert(opts.x and opts.y and opts.faction, "PLATFORMS.spawn needs x, y and faction")

    local cfg = {}
    for k, v in pairs(PLATFORMS.defaults) do cfg[k] = v end
    for k, v in pairs(kind) do cfg[k] = v end
    for k, v in pairs(opts) do cfg[k] = v end

    _count = _count + 1
    local station = SpaceStation():setTemplate(cfg.template):setFaction(cfg.faction)
    station:setPosition(cfg.x, cfg.y)
    station:setCallSign(cfg.callsign or string.format("%s %d", cfg.label, _count))
    station:setDescriptions("A weapons platform.", cfg.description)
    station:setCommsFunction(function(comms_source, comms_target)
        setCommsMessage("This platform does not negotiate.")
    end)

    cfg.obj = station
    cfg.angle = cfg.aim or random(0, 360)
    cfg.timer = random(0, cfg.interval)
    cfg.strafe_phase = random(0, 1)
    station:setRotation(cfg.angle)
    table.insert(PLATFORMS.list, cfg)
    return station
end

--- Turns, sweeps and fires every platform. Call from update(delta).
function PLATFORMS.update(delta)
    for i = #PLATFORMS.list, 1, -1 do
        local t = PLATFORMS.list[i]
        local station = t.obj
        if not station:isValid() then
            table.remove(PLATFORMS.list, i)
        else
            local target, d = nearestEnemyPlayer(station)
            local in_band = target ~= nil and d >= t.max_range * t.min_range_fraction and d <= t.max_range

            -- Track the target (within 1.5x range, so the platform is already facing
            -- the ship when it comes into the firing band).
            local on_target = false
            if target ~= nil and d <= t.max_range * 1.5 then
                local want = angleRotation(station, target)
                local diff = angleDiff(t.angle, want)
                local step = t.turn_rate * delta
                if math.abs(diff) <= step then t.angle = want
                else t.angle = (t.angle + (diff > 0 and step or -step)) % 360 end
                on_target = math.abs(angleDiff(t.angle, want)) <= 2
            end
            -- Only fire once actually pointed at the ship, not while still swinging round.
            in_band = in_band and on_target

            local aim = t.angle
            if in_band then
                t.strafe_phase = (t.strafe_phase + delta / t.strafe_period) % 1
                aim = t.angle + t.strafe_degrees * math.sin(t.strafe_phase * 2 * math.pi)
            end
            station:setRotation(aim)

            t.timer = t.timer - delta
            if in_band and t.timer <= 0 then
                t.timer = t.interval
                local x, y = station:getPosition()
                -- Shells start muzzle_offset out and die just past max_range (5% overshoot,
                -- so a ship sitting right at the edge of the band can still be hit).
                local range = t.max_range * 1.05 - t.muzzle_offset
                for b = 0, t.barrels - 1 do
                    local a = aim + (b - (t.barrels - 1) / 2) * t.fan_spread
                    local mx, my = vectorFromAngle(a, t.muzzle_offset)
                    fireShell(station, x + mx, y + my, a, t.shell_speed, range, t.shell_damage)
                end
            end
        end
    end
end
