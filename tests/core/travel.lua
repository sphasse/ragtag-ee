-- GM travel shortcuts: every story arc's "Ship → ..." helpers (ARC.travel / ARC.shipTo). Each arc is
-- jumped to each of its GM states; every travel button offered in that phase is pressed, and the arc
-- ship must land 5U from the place it names, undocked. Every travel button must be offered (and
-- pressed) in at least one phase. Not covered: what the arcs then do with a ship that arrived
-- (their own tests cover the real triggers).

T.suite("core")

local pressed, offered = {}, {}

local function travels(M)
    local out = {}
    for _, a in ipairs(M.gm_actions or {}) do
        if a.travel then out[#out + 1] = a end
    end
    return out
end

local function inPhase(a, ph)
    for _, p in ipairs(a.phases or {}) do if p == ph then return true end end
    return false
end

for _, id in ipairs(MISSIONS._order) do
    local M = MISSIONS._registry[id]
    local acts = travels(M)
    for _, a in ipairs(acts) do offered[#offered + 1] = id .. ": " .. a.label end
    for _, g in ipairs(M.gm_states or {}) do
        if #acts > 0 and g.key ~= "inactive" and not g.key:find("^done") then
            T.step(id .. " → " .. g.key, function()
                g.fn(MISSIONS._state[id])
                local ph = MISSIONS._cur_phase[id]
                for _, a in ipairs(acts) do
                    if inPhase(a, ph) then
                        -- Start docked at Port Vesper, far from everything.
                        local pv = RT.find("Port Vesper")
                        local x, y = pv:getPosition()
                        T.P():setPosition(x + 300, y)
                        local dp = T.P().components.docking_port
                        dp.target = pv
                        dp.state = "docked"
                        ARC.lastShipTo = nil
                        a.fn(MISSIONS._state[id])
                        local to = ARC.lastShipTo
                        local name = string.format("%s %s in %s", id, a.label, ph)
                        T.check(name .. ": undocked", not T.P():isDocked(pv))
                        if T.check(name .. ": moved the ship", to ~= nil) then
                            local px, py = T.P():getPosition()
                            local d = math.sqrt((px - to.x) ^ 2 + (py - to.y) ^ 2)
                            T.check(name .. ": 5U from it", math.abs(d - 5000) < 50, d)
                            pressed[id .. ": " .. a.label] = true
                        end
                    end
                end
            end)
            T.wait(0.2)
        end
    end
    T.step(id .. ": back to inactive", function() MISSIONS.gmDeactivate(id) end)
end

T.step("every travel button was offered somewhere", function()
    T.check("there are travel buttons", #offered >= 15, #offered)
    for _, key in ipairs(offered) do
        T.check("pressed: " .. key, pressed[key])
    end
end)

T.step("labels fit the GM console", function()
    for _, id in ipairs(MISSIONS._order) do
        for _, a in ipairs(travels(MISSIONS._registry[id])) do
            local n = select(2, a.label:gsub("[^\128-\191]", ""))
            T.check(id .. ": " .. a.label .. " fits", n <= MISSIONS.GM_LABEL_MAX, n)
        end
    end
end)

T.step("nothing to fly to: the ship stays put", function()
    local x, y = T.P():getPosition()
    T.check("shipTo: no target", not ARC.shipTo(nil))
    T.check("shipTo: unknown callsign", not ARC.shipTo("No Such Place"))
    local nx, ny = T.P():getPosition()
    T.check("shipTo: not moved", nx == x and ny == y)
end)
