-- Name: The Short Haul
-- Description: A race against the clock and each other. Every crew starts in a stock Light Freighter with the same money. Take jobs, buy upgrades, keep your standing: when the clock runs out, the richest ship (credits plus what its upgrades cost) wins. A live leaderboard and the clock show on Relay, Operations and the combined stations. Nothing is saved.
---
--- The Drift, one-shot competition. No story arcs, no saved campaign. The job boards never run dry
--- and favour short runs. The GM starts the clock; when it runs out the final standings pop up on
--- every ship and the leaderboard goes away, but the scenario carries on.
-- Type: The Drift Universe
-- Setting[Length]: How long the competition runs once the GM starts the clock.
-- Length[15 minutes]: A sprint: two or three jobs.
-- Length[30 minutes|Default]: Time to work out a route and buy an upgrade or two.
-- Length[1 hour]: A proper shift.

require("utils.lua")
require("ragtag/core.lua")
require("ragtag/verse.lua")
require("ragtag/jobs.lua")
require("ragtag/world.lua")
require("ragtag/gm_console.lua")
require("ragtag/race.lua")
require("ragtag/ship_templates.lua")  -- custom playership templates; must load before init

-- Every crew starts with this much, as a fresh campaign does (The Drift's default).
local START_CREDITS = 200
local LENGTHS = {["15 minutes"] = 15, ["30 minutes"] = 30, ["1 hour"] = 60}

-- The ships on offer, all stock Light Freighters (sister ships, bird names).
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
        local ok, s = pcall(function()
            return PlayerSpaceship():setTemplate("Light Freighter"):setRotation(random(0, 360))
        end)
        _pick_name = nil
        if not ok then error(s) end
        return s
    end
end

-- The "Create player ship" list: Light Freighters only, one entry per name. Everyone races the
-- same ship.
function getSpawnablePlayerShips()
    local result = {}
    if not __allow_new_player_ships then return result end
    local icon
    for _, v in ipairs(__player_ship_templates) do
        if v.typename.type_name == "Light Freighter" then icon = v.radar_trace.icon end
    end
    for _, name in ipairs(ROSTER) do
        result[#result + 1] = {_createNamed(name), "Light Freighter: " .. name,
            name .. ": a stock Light Freighter with " .. START_CREDITS .. " credits. Same as everyone else.", icon}
    end
    return result
end

-- A ship joins: at Port Vesper, Independent, its name, START_CREDITS once (a ship rebuilt after
-- being lost keeps its record, so it keeps what it had left).
local function _joined(ship)
    local rec = RT.shipRecord(ship)
    if rec and not rec.race_joined then
        rec.race_joined = true
        RT.setCredits(START_CREDITS, ship)
    end
end

local function _showGM()
    clearGMFunctions()
    addGMFunction("Start the clock", function()
        if RACE.start() then
            addGMMessage(string.format("%s: the clock is running (%g minutes).", RACE.NAME, RACE.state.minutes))
        end
        _showGM()
    end)
    addGMFunction("Standings", function()
        local s = RACE.state
        local head = (not s.started) and "Not started." or (s.over and "Over." or
            string.format("%d:%02d left.", math.floor(RACE.timeLeft() / 60), math.floor(RACE.timeLeft() % 60)))
        local lines = {RACE.NAME .. ": " .. head}
        for i, e in ipairs(RACE.standings()) do
            lines[#lines + 1] = string.format("%d. %s  %s (credits %s, upgrades %s)", i, e.name, RACE.fmt(e.score),
                RACE.fmt(RT.credits(e.ship)), RACE.fmt(RT.upgradeSpend(e.ship)))
        end
        addGMMessage(table.concat(lines, "\n"))
    end)
    addGMFunction("End the competition now", function()
        if RACE.state.started then RACE.finish() end
        _showGM()
    end)
    -- Reputation..., Jobs..., Ship Upgrades... (no campaign save tools: nothing is saved here)
    GMCONSOLE.add({session = 1})
end

function init()
    VERSE.setupFactions()

    -- A fresh, throwaway campaign every time: its own save key, and saving switched off, so
    -- nothing carries over to the next round (or into The Drift's campaign).
    RT.useCampaign("shorthaul")
    RT.loadCampaign(true)
    RT._saves_frozen = true

    VERSE.build({session = 1})
    VERSE.requirePlaces({"Port Vesper"})

    RT.PLAYER_TEMPLATE = "Light Freighter"
    local px, py = VERSE.at("Port Vesper", 1.5, 1.5)
    RT.spawnPlayer(px, py, 0)
    _joined(RT.player)

    onNewPlayerShip(function(ship)
        local vx, vy = VERSE.at("Port Vesper", 1.5, 1.5)
        ship:setPosition(vx + #RT.players * 4000, vy)
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
        _joined(ship)
    end)

    -- Job boards: never run dry (no cooldown: the list is always full) and favour short runs.
    JOBS.init()
    JOBS.config.work_cooldown_enabled = false
    JOBS.config.mission_distance_mode = "short"
    for _, d in ipairs(VERSE.STATIONS) do
        if d.fac ~= "Corsairs" and d.fac ~= "Hollow" then
            RT.addStationHook(d.cs, JOBS.stationHook)
        end
    end

    RACE.setup({minutes = LENGTHS[getScenarioSetting("Length")] or 30})   -- shuts the boards until the start
    _showGM()
end

function update(delta)
    RT.update(delta)
    VERSE.update(delta)
    JOBS.update()
    WORLD.update(delta)
    RACE.tick(getScenarioTime())
end
