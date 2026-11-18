-- Universe stations: every port (any station that is not Corsair or Hollow) is indestructible,
-- so a job or arc fight that comes to a port cannot take it off the map (playtest 2026-11-17:
-- Dustmote Salvage and Saint Brennan's Mission vanished mid-session). Corsair and Hollow
-- stations can still be destroyed, and a station that dies is reported ("station_destroyed").
--
-- Not covered: a real weapons fight at a port (the test applies damage directly).

T.suite("core")

local heard = {}
local bw
RT.on(function(ev) if ev.type == "station_destroyed" then heard[#heard + 1] = ev.data end end)

local function damage(s, amount)
    if not RT.valid(s) then return end   -- a destructible station can die on the first hit
    local x, y = s:getPosition()
    s:takeDamage(amount, "kinetic", x + 1000, y)
end

T.step("ports", function()
    local ports, protected = 0, 0
    for _, d in ipairs(VERSE.STATIONS) do
        if d.fac ~= "Corsairs" and d.fac ~= "Hollow" then
            ports = ports + 1
            local s = RT.find(d.cs)
            if RT.valid(s) and not s:getCanBeDestroyed() then protected = protected + 1
            else T.check("ports: " .. d.cs .. " is indestructible", false) end
        end
    end
    T.check("ports: the universe has ports", ports > 10, ports)
    T.eq("ports: every one is indestructible", protected, ports)
    for _, cs in ipairs({"Dustmote Salvage", "Saint Brennan's Mission"}) do
        local s = RT.find(cs)
        for _ = 1, 5 do damage(s, 100000) end
    end
end)
T.wait(1)
T.step("they survive a beating", function()
    for _, cs in ipairs({"Dustmote Salvage", "Saint Brennan's Mission"}) do
        T.check("ports: " .. cs .. " still there", RT.valid(RT.find(cs)))
    end
    T.eq("ports: no station reported lost", #heard, 0)
    bw = RT.find("Blackwater")
    T.check("hostile: a Corsair station can still be destroyed", bw:getCanBeDestroyed())
    for _ = 1, 10 do damage(bw, 100000) end
end)
T.waitFor("hostile: Blackwater is destroyed", function() return not RT.valid(bw) end, 3)
T.step("and reported", function()
    T.eq("report: one station lost", #heard, 1)
    T.eq("report: which one", heard[1] and heard[1].station, "Blackwater")
end)
