-- Name: Combat Arena
-- Description: A balancing range for the Drift's fights. The GM fits the crews' Light Freighters with any upgrades, picks the enemies (type and number, from the ships the Drift uses) and how far away they appear, spawns them frozen, and starts the fight when everyone is ready. A report gives both sides' strength, the time taken and what was left. Restore puts the crews back to full between rounds. Nothing is saved.
---
--- The Drift, a test range for multiplayer sessions: work out what a fair encounter is for one, two or more crews
--- with a given set of upgrades. Open space, no universe, no jobs or arcs. Everything is on the GM screen
--- (ARENA, ee/ragtag/arena.lua).
-- Type: The Drift Universe

require("utils.lua")
require("ragtag/core.lua")
require("ragtag/verse.lua")           -- the factions
require("ragtag/gm_console.lua")      -- Ship Upgrades... (GMCONSOLE.addUpgradesButton, on the arena's GM screen)
require("ragtag/ships_used.lua")      -- SCIDB.SHIPS_USED: the ship types the Drift uses
require("ragtag/arena.lua")
require("ragtag/ship_templates.lua")  -- custom playership templates; must load before init

-- The ships on offer: stock Light Freighters, the Drift's sister ships.
local ROSTER = {"Magpie", "Raven", "Jackdaw", "Starling", "Wren", "Kestrel", "Harrier", "Merlin", "Osprey", "Swift"}

local _pick_name = nil   -- the name chosen on the "Create player ship" list while its ship is made

local function _liveShipNamed(name)
    for _, p in ipairs(RT.players) do
        if RT.valid(p) and p:getCallSign() == name then return p end
    end
    return nil
end

local function _createNamed(name)
    return function()
        if _liveShipNamed(name) then
            pcall(addGMMessage, name .. " is already flying: no ship was made.")
            return nil
        end
        _pick_name = name
        local ok, s = pcall(function() return PlayerSpaceship():setTemplate("Light Freighter") end)
        _pick_name = nil
        if not ok then error(s) end
        return s
    end
end

-- The "Create player ship" list: one Light Freighter per name. A ship lost in a fight and made again
-- under the same name gets the upgrades the GM gave it (its record is found by its name).
function getSpawnablePlayerShips()
    local result = {}
    if not __allow_new_player_ships then return result end
    local icon
    for _, v in ipairs(__player_ship_templates) do
        if v.typename.type_name == "Light Freighter" then icon = v.radar_trace.icon end
    end
    for _, name in ipairs(ROSTER) do
        result[#result + 1] = {_createNamed(name), "Light Freighter: " .. name,
            name .. ": a Light Freighter for the arena. The GM fits its upgrades.", icon}
    end
    return result
end

-- GMCONSOLE's submenus come back through this global (as in the campaign scenarios).
function addSessionGMFunctions() ARENA.showGM() end

function init()
    VERSE.setupFactions()

    -- A throwaway campaign: its own save key, saving switched off. Upgrades the GM grants last the session.
    RT.useCampaign("arena")
    RT.loadCampaign(true)
    RT._saves_frozen = true

    RT.PLAYER_TEMPLATE = "Light Freighter"
    RT.spawnPlayer(0, 0, 0)

    onNewPlayerShip(function(ship)
        ship:setPosition(#RT.players * 1500, 0)
        ship:setFaction(RT.PLAYER_FACTION)
        if _pick_name then
            ship:setCallSign(_pick_name)
        else
            local used = {}
            for _, p in ipairs(RT.players) do
                if RT.valid(p) and p ~= ship then used[p:getCallSign()] = true end
            end
            for _, name in ipairs(ROSTER) do
                if not used[name] then ship:setCallSign(name); break end
            end
        end
        RT.adoptPlayer(ship)
    end)

    ARENA.reset()
    ARENA.showGM()
end

function update(delta)
    RT.update(delta)
    ARENA.tick(getScenarioTime())
end
