-- Name: Platform Range (test)
-- Description: Test range for the ragtag gun platforms: one barrage and one lance platform.
---
--- Fly toward either platform. They track you and open fire only when you are between
--- point blank and 100% of their range (barrage 6u, lance 8u), sweeping 10 degrees either side.
--- Stand-alone: doesn't load the universe or touch campaign saves.
-- Type: The Drift Universe

require("utils.lua")
require("ragtag/CustomObjects/platforms/platforms.lua")

function init()
    PlayerSpaceship():setTemplate("Atlantis"):setFaction("Independent"):setCallSign("Test Ship")
        :setPosition(0, 0):setRotation(0)

    PLATFORMS.spawn{kind = "barrage", x = 10000, y = -4000, faction = "Exuari"}
    PLATFORMS.spawn{kind = "lance", x = 10000, y = 6000, faction = "Exuari", max_range = 8000}

    addGMFunction("Platform info", function()
        local lines = {}
        for _, t in ipairs(PLATFORMS.list) do
            table.insert(lines, string.format("%s: range %.0fu (fires from %.1fu), sweep +/-%d deg",
                t.obj:getCallSign(), t.max_range / 1000, t.max_range * t.min_range_fraction / 1000, t.strafe_degrees))
        end
        addGMMessage(table.concat(lines, "\n"))
    end)
end

function update(delta)
    PLATFORMS.update(delta)
end
