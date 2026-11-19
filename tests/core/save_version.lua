-- Save format versions (RT.SAVE_VERSION, RT.MIGRATIONS, RT.migrateCampaign, core.lua). A save at
-- the current format is left alone; an older one runs every missing step in order and is written
-- back; one written by a newer framework is loaded but saving is frozen for the session. Upgrade
-- ids the catalogue does not know are reported in the log. The steps here are made up for the
-- test (and removed again): this is also the pattern for writing a real one.
--
-- Not covered: a real restart of the game (the test writes the save and calls RT.loadCampaign).

T.suite("core")

local V, MIG
local order = {}

T.step("a save at the current format", function()
    V, MIG = RT.SAVE_VERSION, RT.MIGRATIONS
    T.eq("current: the running campaign is at the current format", RT.campaign.version, V)
    T.eq("current: nothing to do", RT.migrateCampaign({version = V}), "current")
end)

T.step("two new formats, each with its step", function()
    RT.SAVE_VERSION = V + 2
    RT.MIGRATIONS = {
        [V + 1] = function(c, say)
            order[#order + 1] = c.version
            c.renamed, c.old_field = c.old_field, nil         -- a field renamed
            say("old_field -> renamed")
        end,
        [V + 2] = function(c)
            order[#order + 1] = c.version
            local kept = {}                                    -- an upgrade id taken out of the catalogue
            for _, id in ipairs(c.upgrades or {}) do if id ~= "retired_upgrade" then kept[#kept + 1] = id end end
            c.upgrades = kept
            c.credits = (c.credits or 0) + 100                 -- ... with a refund
        end,
    }
    local c = {version = V, old_field = "x", credits = 5, upgrades = {"hull_plating", "retired_upgrade"}}
    T.eq("older: migrated", RT.migrateCampaign(c), "migrated")
    T.eq("older: every step, in order", table.concat(order, ","), V .. "," .. (V + 1))
    T.eq("older: now at the new format", c.version, V + 2)
    T.eq("older: the renamed field", c.renamed, "x")
    T.check("older: the old field is gone", c.old_field == nil)
    T.eq("older: the retired upgrade is gone", table.concat(c.upgrades, ","), "hull_plating")
    T.eq("older: and refunded", c.credits, 105)
end)

T.step("through the loader: the migrated save is written back", function()
    local key, keep, camp = RT.CAMPAIGN_KEY, getScriptStorage():get(RT.CAMPAIGN_KEY), RT.campaign
    getScriptStorage():set(key, toJSON({version = V + 1, ship_name = "Magpie", credits = 7, upgrades = {}}))
    local c = RT.loadCampaign(false)
    T.eq("loader: migrated on load", c.version, V + 2)
    T.eq("loader: the step ran", c.credits, 107)
    local stored = fromJSON(getScriptStorage():get(key))
    T.eq("loader: written back at the new format", stored and stored.version, V + 2)
    getScriptStorage():set(key, keep)
    RT.campaign = camp
end)

T.step("a save from a newer framework", function()
    local r
    local lines = T.expectLogged(function() r = RT.migrateCampaign({version = RT.SAVE_VERSION + 1}) end)
    T.eq("newer: recognised", r, "newer")
    T.check("newer: saving is frozen for the session", RT._saves_frozen == true)
    T.check("newer: and the log says so", #lines == 1 and lines[1]:find("nothing will be saved", 1, true) ~= nil, lines[1])
    RT._saves_frozen = nil
    RT.SAVE_VERSION, RT.MIGRATIONS = V, MIG
end)

T.step("unknown upgrade ids are reported", function()
    local unknown
    local lines = T.expectLogged(function()
        unknown = RT.warnUnknownUpgrades({ship_name = "Magpie", upgrades = {"hull_plating", "warp_overhaul"},
            extra_ships = {{name = "Wren", upgrades = {"no_such_thing"}}}})
    end)
    T.eq("unknown: both found", unknown and #unknown, 2)
    T.check("unknown: named with their ship", lines[1] and lines[1]:find("Magpie: warp_overhaul", 1, true) ~= nil
        and lines[1]:find("Wren: no_such_thing", 1, true) ~= nil, lines[1])
    T.eq("unknown: none in a clean save", #RT.warnUnknownUpgrades({upgrades = {"hull_plating"}}), 0)
end)
