-- The engine's orbit component as the universe and the arcs use it:
--   * the asteroid ring round the Deep Shroud's black hole (verse.lua, asteroid_fields kind "ring"):
--     its rocks are placed between r1 and r2, keep their distance and move round the centre;
--   * a tow line (setOrbit(ship, 0)): an object held at a fixed distance trails the ship when it
--     flies on impulse, and stays put once let go.
--
-- Not covered: what Helm sees, a towed object brushing asteroids.

T.suite("core")

local BH_X, BH_Y = 177000, -52000
local rock, rock_x, rock_y, rock_d
local berg, P0x, P0y

local function dist(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end

T.step("the ring round the Deep Shroud's black hole", function()
    local ring
    for _, r in ipairs(VERSE.rings or {}) do
        if r.x == 177 and r.y == -52 then ring = r end
    end
    T.check("ring: built", ring ~= nil)
    if not ring then return end
    T.eq("ring: forty rocks", #ring.rocks, 40)
    local inside = 0
    for _, o in ipairs(ring.rocks) do
        if RT.valid(o) then
            local x, y = o:getPosition()
            local d = dist(x, y, BH_X, BH_Y)
            if d >= 6900 and d <= 13100 then inside = inside + 1 end
        end
    end
    T.eq("ring: every rock between 7U and 13U", inside, #ring.rocks)
    rock = ring.rocks[1]
    rock_x, rock_y = rock:getPosition()
    rock_d = dist(rock_x, rock_y, BH_X, BH_Y)
    T.check("ring: a rock has an orbit", rock.components.orbit ~= nil)
    local x, y = rock:getPosition()
    local r = VERSE.regionAt(x, y)
    T.eq("ring: in the Deep Shroud", r and r.name, "the Deep Shroud")
end)

T.wait(5)

T.step("a rock moves round and keeps its distance", function()
    if not RT.valid(rock) then T.check("ring: rock still there", false); return end
    local x, y = rock:getPosition()
    local moved = dist(x, y, rock_x, rock_y)
    T.check("ring: the rock moved", moved > 100, string.format("%.0f", moved))
    T.check("ring: about the speed the period gives (< 1.2U in 5 s)", moved < 1200, string.format("%.0f", moved))
    T.check("ring: same distance from the black hole", math.abs(dist(x, y, BH_X, BH_Y) - rock_d) < 50)
end)

-- ── A tow line ──────────────────────────────────────────────────────────────

T.step("an object on a 1.5U line behind the ship", function()
    T.moveTo(90000, 20000)
    local p = T.P()
    p:setRotation(0):setHeading(90)   -- pointing east
    P0x, P0y = p:getPosition()
    berg = Artifact():setPosition(P0x - 1500, P0y)
    berg:setOrbit(p, 0)
    T.check("tow: has an orbit on the ship", berg.components.orbit ~= nil)
    p:commandImpulse(1.0)
end)

T.wait(15)

T.step("the ship flies east: the object trails 1.5U behind", function()
    local p = T.P()
    local px, py = p:getPosition()
    local bx, by = berg:getPosition()
    T.check("tow: the ship moved", dist(px, py, P0x, P0y) > 500, string.format("%.0f", dist(px, py, P0x, P0y)))
    T.check("tow: still 1.5U away", math.abs(dist(px, py, bx, by) - 1500) < 60, string.format("%.0f", dist(px, py, bx, by)))
    T.check("tow: behind the ship (west of it)", bx < px - 1300)
    p:commandImpulse(0)
    berg:setOrbit(nil)
    berg.tow_x, berg.tow_y = bx, by
end)

T.wait(2)

T.step("let go: the object stays where it was", function()
    local bx, by = berg:getPosition()
    T.check("tow: no orbit after letting go", berg.components.orbit == nil)
    T.check("tow: has not moved", dist(bx, by, berg.tow_x, berg.tow_y) < 10)
    berg:destroy()
end)
