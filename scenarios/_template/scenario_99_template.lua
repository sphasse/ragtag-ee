-- Name: Long Haul N: Title Here
-- Description: Session N of 5. One or two sentences the crew sees on the scenario list.
---
--- Built on the ragtag framework (scripts/ragtag/). Install with tools/install.py.
-- Type: The Drift Universe
-- Setting[Campaign]: Use saved campaign progress or start over.
-- Campaign[Continue|Default]: Keep credits, upgrades and story choices from earlier sessions.
-- Campaign[Fresh start]: Wipe campaign progress and start with a stock ship.
-- Setting[Difficulty]: How hard the opposition hits.
-- Difficulty[Easy]: Fewer enemies.
-- Difficulty[Normal|Default]: The intended experience.
-- Difficulty[Hard]: More enemies.
-- Setting[Director]: Whether the scenario talks to the external AI director.
-- Director[On|Default]: Exchange events and actions with the AI director if it is running.
-- Director[Off]: Purely scripted.

require("utils.lua")
require("ragtag/core.lua")
require("ragtag/verse.lua")
require("ragtag/director.lua")
require("ragtag/patrol.lua")

local SESSION_ID = "sN"

-- All mutable session state lives in one table so it's easy to report.
local S = {
    phase = "start",   -- one string per stage of the session
    ending = false,
}

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function init()
    VERSE.setupFactions()   -- must come before anything uses Concord/Corsairs/etc.
    RT.useCampaign("mycampaign")   -- your campaign folder's name; keeps saves separate
    local fresh = getScenarioSetting("Campaign") == "Fresh start"
    RT.loadCampaign(fresh)
    if fresh then RT.saveCampaign() end
    catchUpCampaign()

    local diff = getScenarioSetting("Difficulty")
    DIR.config.max_ai_hostiles = (diff == "Easy" and 3) or (diff == "Hard" and 8) or 5
    DIR.enabled = getScenarioSetting("Director") ~= "Off"

    VERSE.build({session = 99})   -- the shared universe; use this session's number
    -- Every universe place this scenario uses. tools/check.py fails if one disappears.
    VERSE.requirePlaces({"Port Vesper", "Halcyon Rest"})
    PATROL.init()
    buildMap()                          -- session-specific additions only
    local px, py = VERSE.at("Port Vesper", 1.5, 1.5)
    RT.spawnPlayer(px, py, 0)
    RT.addCampaignGMFunctions()
    defineBeats()
    addSessionGMFunctions()

    DIR.addStateProvider(function() return {phase = S.phase} end)
    DIR.init({
        id = SESSION_ID,
        campaign = "mycampaign",       -- director loads scenarios/<campaign>/bible.md
        title = "Title Here",
        premise = "Two or three sentences: the job, the complication, what is secretly going on.",
        tone = "Scrappy frontier western in space. Wry humour, real stakes, never grimdark.",
        cast = {
            {name = "Name", where = "Callsign of their ship or station", role = "role", voice = "how they talk"},
        },
        locations = {
            {name = "Example Wreck", note = "this session's own location; verse places are in the campaign bible"},
        },
        director_guidance = "Which ai beats to fire and when; what to avoid; how hard to push.",
    })
end

-- If a crew skips a session (or the save was lost), give them sensible
-- defaults so this session still works.
function catchUpCampaign()
    local c = RT.campaign
    if c.sessions["s1"] == nil then
        c.credits = math.max(c.credits or 0, 300)
        c.flags.lantern_core = true
    end
    RT.saveCampaign()
end

-- Stations, planets, traffic and salvage already exist (ragtag_verse.lua).
-- Add only this session's objects, positioned relative to named places.
function buildMap()
    local x, y = VERSE.at("Halcyon Rest", 8, 4)
    local wreck = CpuShip():setTemplate("Tug"):setFaction("Derelict"):setCallSign("Example Wreck")
    wreck:setPosition(x, y):orderIdle():setImpulseMaxSpeed(0):setCanBeDestroyed(false)
    RT.register(wreck)
end

--------------------------------------------------------------------------------
-- Beats: every ai=true beat needs a deterministic fallback in update().
--------------------------------------------------------------------------------

function defineBeats()
    DIR.defineBeat("opening", {desc = "Someone hails with the job", fn = function()
        RT.hail(RT.find("Port Vesper"), "We have a job for you.", "Example NPC")
        RT.setObjective("Do the first thing.")
    end})

    DIR.defineBeat("complication", {ai = true, desc = "Something goes wrong mid-job", fn = function(source)
        RT.player:addToShipLog("Something went wrong.", "#FF8080")
    end})
end

function addSessionGMFunctions()
    addGMFunction(SESSION_ID .. ": fire complication", function() DIR.fireBeat("complication", "gm") end)
    addGMFunction(SESSION_ID .. ": end (success)", function() finishSession("success", "GM ended the session.") end)
end

--------------------------------------------------------------------------------
-- Ending
--------------------------------------------------------------------------------

function finishSession(outcome, note)
    if S.ending then return end
    S.ending = true
    S.phase = "done"
    RT.completeSession(SESSION_ID, outcome, note)
    DIR.emit("session_end", {session = SESSION_ID, outcome = outcome, note = note,
        flags = RT.campaign.flags, credits = RT.credits()}, "high")
    globalMessage("Session complete: " .. note, 10)
    -- Give the director a few seconds to read the session_end event.
    RT.after(12, function() victory(RT.PLAYER_FACTION) end, "victory")
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

function update(delta)
    RT.update(delta)
    VERSE.update(delta)
    DIR.update(delta)
    PATROL.update(delta)
    if S.phase == "done" then return end

    if not RT.valid(RT.player) then
        if not S.ending then
            S.ending = true
            RT.completeSession(SESSION_ID, "failed", "The ship was lost.")
            DIR.emit("session_end", {session = SESSION_ID, outcome = "failed"}, "high")
            RT.after(6, function() victory("Corsairs") end, "defeat")
        end
        return
    end
    local now = getScenarioTime()

    if S.phase == "start" and now > 5 then
        DIR.fireBeat("opening", "script")
        S.phase = "underway"
        S.underway_at = now
    elseif S.phase == "underway" then
        -- Fallback: if the director hasn't fired the complication in 6 minutes, fire it.
        if not DIR.beatFired("complication") and now - S.underway_at > 360 then
            DIR.fireBeat("complication", "fallback")
        end
    end
end
