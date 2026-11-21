-- Name: Platform Range (test)
-- Description: Test range for the gun platforms: one barrage and one lance platform. Fly east into them.
---
--- Contributed by Kuri148 (PR #1). Fly toward either platform: they track you and open fire only
--- when you are between point blank and 100% of their range (barrage 6U, lance 8U), sweeping
--- either side of you (barrage 6 degrees, lance 2). Stand-alone: no universe, no campaign save. Parked with the labs
--- (scenarios/_battlelab: not installed or released unless the folder is renamed back).
-- Type: The Drift Universe

require("utils.lua")
require("ragtag/core.lua")              -- loads PLATFORMS (ragtag/platforms.lua)
require("ragtag/verse.lua")             -- factions
require("ragtag/ship_templates.lua")    -- the Light Freighter

function init()
    VERSE.setupFactions()
    RT.useCampaign("platformrange")
    RT.loadCampaign(true)
    RT._saves_frozen = true
    RT.PLAYER_TEMPLATE = "Light Freighter"
    RT.spawnPlayer(0, 0, 90, {callsign = "Test Ship"})

    PLATFORMS.spawn{kind = "barrage", x = 10000, y = -4000, faction = "Corsairs"}
    PLATFORMS.spawn{kind = "lance", x = 10000, y = 6000, faction = "Corsairs", max_range = 8000}

    addGMFunction("Platform info", function()
        local lines = {}
        for _, t in ipairs(PLATFORMS.list) do
            table.insert(lines, string.format("%s: range %.0fU (fires from %.1fU), sweep +/-%d deg",
                t.obj:getCallSign(), t.max_range / 1000, t.max_range * t.min_range_fraction / 1000, t.strafe_degrees))
        end
        addGMMessage(table.concat(lines, "\n"))
    end)
end

function update(delta)
    RT.update(delta)
    PLATFORMS.update(delta)
end
