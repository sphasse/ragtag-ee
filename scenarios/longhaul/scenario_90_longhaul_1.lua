-- Name: Long Haul 1: Cold Cargo
-- Description: Session 1 of 5. The crew of the Magpie, a battered light freighter, takes a simple delivery job from a fixer who never tells the whole story. Concord patrols, Corsair raiders, and a crate that hums. Set in a wide-open verse with traffic, salvage, and places you are not ready for yet.
---
--- Campaign scenario. Progress (credits, upgrades, story flags) is saved in scriptstorage.json on the server.
--- Optional: run the AI director (director/main.py) on another PC for live NPCs and pacing. Plays fine without it.
-- Type: Long Haul Campaign
-- Author: Your game group
-- Setting[Campaign]: Use saved campaign progress or start over.
-- Campaign[Continue|Default]: Keep credits, upgrades and story choices from earlier sessions.
-- Campaign[Fresh start]: Wipe campaign progress and start with a stock Magpie.
-- Setting[Difficulty]: How hard the opposition hits.
-- Difficulty[Easy]: Fewer raiders. Good for a new crew.
-- Difficulty[Normal|Default]: The intended experience.
-- Difficulty[Hard]: More raiders and a tighter AI budget.
-- Setting[Director]: Whether the scenario talks to the external AI director.
-- Director[On|Default]: Exchange events and actions with the AI director if it is running.
-- Director[Off]: Purely scripted. Every story beat still fires on its own.

require("utils.lua")
require("ragtag/core.lua")
require("ragtag/verse.lua")
require("ragtag/director.lua")

-- Map layout (1u = 1000)
local VESPER_X, VESPER_Y = 0, 0
local HALCYON_X, HALCYON_Y = 32000, -18000
local DILIGENCE_X, DILIGENCE_Y = 13000, -9000
local FOLLY_X, FOLLY_Y = 40000, -5000

local S = {
    phase = "start",           -- start, loading, hauling, delivered, salvage, done
    cargo_loaded = false,
    docked_since = nil,
    inspection = "none",       -- none, pending, submitted, bribed, ran, tagged, escaped
    chase_until = nil,
    chase_close_time = 0,
    submit_hold_since = nil,
    payout = 400,
    ambush_ships = {},
    folly_scanned = false,
    core_taken = false,
    ending = false,
}

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function init()
    VERSE.setupFactions()
    RT.useCampaign("longhaul")
    local fresh = getScenarioSetting("Campaign") == "Fresh start"
    RT.loadCampaign(fresh)
    if fresh then RT.saveCampaign() end

    local diff = getScenarioSetting("Difficulty")
    if diff == "Easy" then
        DIR.config.max_ai_hostiles = 3
        S.ambush_templates = {"MT52 Hornet"}
    elseif diff == "Hard" then
        DIR.config.max_ai_hostiles = 7
        S.ambush_templates = {"Adder MK5", "Adder MK5", "MT52 Hornet"}
    else
        DIR.config.max_ai_hostiles = 5
        S.ambush_templates = {"Adder MK5", "MT52 Hornet"}
    end
    DIR.enabled = getScenarioSetting("Director") ~= "Off"

    VERSE.build({session = 1})
    -- Universe places this session depends on (tools/check.py verifies them).
    VERSE.requirePlaces({"Port Vesper", "Halcyon Rest", "Concord Station Arbiter"})
    buildMap()
    RT.spawnPlayer(VESPER_X + 900, VESPER_Y + 1400, 0)
    RT.addCampaignGMFunctions()
    addSessionGMFunctions()
    defineBeats()

    DIR.addStateProvider(function()
        return {phase = S.phase, cargo_loaded = S.cargo_loaded, inspection = S.inspection,
                payout_pending = S.payout, folly_scanned = S.folly_scanned, core_taken = S.core_taken}
    end)

    DIR.init({
        id = "s1",
        campaign = "longhaul",
        title = "Cold Cargo",
        premise = "The Magpie, a battered light freighter with a crew of drifters, takes a delivery job from fixer Mags Oduya: twelve sealed crates from Port Vesper to Halcyon Rest. No questions asked. One crate is not what the manifest says.",
        tone = "Scrappy frontier western in space. Wry humour, real stakes, never grimdark. The crew are underdogs; the Concord is the law, the Corsairs are pirates, and nobody talks about the Hollow.",
        cast = {
            {name = "Mags Oduya", where = "Port Vesper", role = "fixer", voice = "dry, warm, quietly menacing; always owed a favour; calls the crew 'my lambs'"},
            {name = "Lt. Corin Vashti", where = "CPV Diligence", role = "Concord patrol officer", voice = "by-the-book, tired, can be reasoned with; hates paperwork"},
            {name = "Grinning Teeth", where = "Corsair raiders", role = "raider gang", voice = "theatrical, mocking, greedy; PG-13 menace"},
            {name = "Doc Salo", where = "Halcyon Rest", role = "dockmaster and medic", voice = "nervous, honest, talks too fast"},
        },
        locations = {
            {name = "Port Vesper", note = "Independent trading post, shipwright on site"},
            {name = "Halcyon Rest", note = "Independent waystation at the edge of the Shroud nebula, shipwright on site"},
            {name = "Concord Station Arbiter", note = "Concord customs station"},
            {name = "Wren's Folly", note = "Derelict hidden in the Shroud nebula"},
        },
        director_guidance = "Use 'say' as the cast for colour and hints. Fire 'inspection' when the Magpie is underway and near the Diligence, and 'ambush' somewhere mid-route; both have fallbacks, so only fire them when timing feels right. Keep total extra hostiles modest: the Magpie is weak. Reward clever play with small salvage.",
    })
end

function buildMap()
    -- Stations, the Shroud, asteroid fields, traffic and salvage come from
    -- ragtag_verse.lua. This adds only what belongs to this session.

    -- Wren's Folly: derelict, unscanned until science looks closely.
    local folly = CpuShip():setTemplate("Tug"):setFaction("Independent"):setCallSign("Wren's Folly")
    folly:setPosition(FOLLY_X, FOLLY_Y):orderIdle():setImpulseMaxSpeed(0):setHull(8):setShieldsMax(0)
    folly:setDescriptions("Unpowered hull. No transponder.",
        "Survey tug Wren's Folly, reported lost eight months ago. Emergency log ends mid-sentence: '...the lantern is still singing, we can hear it through the'.")
    folly:setScanningParameters(2, 2)
    folly:setCommsFunction(function(source, target)
        setCommsMessage("Dead air. Then, faintly, a looping tone. Not a voice.")
    end)
    folly:setCanBeDestroyed(false)
    RT.register(folly)
    S.folly = folly

    -- The Concord patrol, idling near the route.
    local dil = CpuShip():setTemplate("Phobos M3"):setFaction("Concord"):setCallSign("CPV Diligence")
    dil:setPosition(DILIGENCE_X, DILIGENCE_Y):orderIdle()
    dil:setCommsFunction(diligenceComms)
    RT.register(dil)
    DIR.allowControl(dil)
    S.diligence = dil
end

--------------------------------------------------------------------------------
-- Story beats
--------------------------------------------------------------------------------

function defineBeats()
    DIR.defineBeat("briefing", {desc = "Mags hails with the job", fn = function()
        RT.hail(RT.find("Port Vesper"), "Morning, my lambs. Twelve sealed crates, Port Vesper to Halcyon Rest, 400 on delivery. " ..
            "Dock with me to load. Don't open them, don't scan them, don't get boarded. Easy money.", "Mags Oduya")
        RT.setObjective("Dock at Port Vesper to load the cargo.")
    end})

    DIR.defineBeat("cargo_loaded", {desc = "Crates loaded at Port Vesper", fn = function()
        S.cargo_loaded = true
        S.phase = "hauling"
        S.loaded_at = getScenarioTime()
        RT.player:addToShipLog("Twelve crates secured in the hold. One reads a few kilos light on the manifest scale.", "#E0E0A0")
        RT.setObjective("Deliver the crates to Halcyon Rest, sector " .. RT.find("Halcyon Rest"):getSectorName() .. ".")
    end})

    DIR.defineBeat("inspection", {ai = true, desc = "CPV Diligence demands to inspect the Magpie (choices: submit, bribe, run)", fn = function()
        S.inspection = "pending"
        S.inspection_started = getScenarioTime()
        local dil = S.diligence
        if not RT.valid(dil) then return end
        dil:orderFlyTowards(RT.player:getPosition())
        RT.hail(dil, "Independent freighter " .. RT.player:getCallSign() .. ", this is Lieutenant Vashti, CPV Diligence. " ..
            "Cut your engines and prepare for a cargo inspection. Hail me to confirm.", "Lt. Corin Vashti")
        RT.setObjective("The Concord wants an inspection. Hail CPV Diligence - or don't.")
    end})

    DIR.defineBeat("ambush", {ai = true, desc = "Corsair raiders ('Grinning Teeth') jump the Magpie for the crates", fn = function()
        local x, y = RT.player:getPosition()
        local h = RT.player:getHeading()
        local dx, dy = vectorFromAngle(h + random(-50, 50), 9000, true)
        for i, tmpl in ipairs(S.ambush_templates) do
            local s = CpuShip():setTemplate(tmpl):setFaction("Corsairs"):setCallSign(i == 1 and "Grinning Teeth" or ("Teeth-" .. i))
            s:setPosition(x + dx + random(-800, 800), y + dy + random(-800, 800)):orderAttack(RT.player)
            s:setCommsFunction(DIR.npcComms)
            DIR.npc_info[s:getCallSign()] = {role = "raider", greeting = "\"Ooh, a freighter with manners. Drop the crates and we'll only take half your hull.\""}
            DIR.allowControl(s)
            RT.register(s)
            s:onDestruction(function(ship, instigator)
                DIR.emit("destroyed", {callsign = ship:getCallSign(), faction = "Corsairs", by_player = instigator == RT.player}, "normal")
            end)
            table.insert(S.ambush_ships, s)
        end
        local lead = S.ambush_ships[1]
        if RT.valid(lead) then
            RT.hail(lead, "Grinning Teeth here! Pretty boat, pretty crates. Let's play.")
        end
        RT.player:addToShipLog("Contacts! Corsair raiders on an intercept course.", "#FF8080")
    end})

    DIR.defineBeat("delivery", {desc = "Crates delivered to Doc Salo at Halcyon Rest; the humming crate is revealed", fn = function()
        S.phase = "delivered"
        RT.addCredits(S.payout, "delivery for Mags")
        local text = "You're the Magpie? Oh thank goodness. Twelve crates, twelve... wait. This one's light, and it's - is it humming? " ..
            "Mags said nothing about - look, there's a matching signal out in the Shroud. A derelict, Wren's Folly. " ..
            "If someone pulled something off that wreck, the rest of it is still out there. I'd pay for a look. Or forget I said it."
        RT.hail(RT.find("Halcyon Rest"), text, "Doc Salo")
        RT.setObjective("Optional: scan the derelict Wren's Folly in the Shroud. Or tell Doc Salo you're done.")
        RT.flag("s1_delivered", true)
    end})

    DIR.defineBeat("folly_secret", {desc = "Scanning Wren's Folly reveals a sealed data core floating nearby", fn = function()
        S.folly_scanned = true
        S.phase = "salvage"
        local fx, fy = S.folly:getPosition()
        local core = Artifact():setPosition(fx + 700, fy - 400):allowPickup(true):setCallSign("Sealed data core")
        core:setDescriptions("Small object, faint emissions", "A sealed data core stamped with a lantern sigil. It is warm, and it hums.")
        core:onPickUp(function()
            S.core_taken = true
            RT.flag("lantern_core", true)
            RT.addCredits(150, "salvage")
            RT.player:addToShipLog("Data core recovered. The hum syncs with the light crate's. Someone will want this.", "#E0C0FF")
            RT.setObjective("Return to Halcyon Rest or Port Vesper.")
            DIR.emit("pickup", {label = "lantern data core", important = true}, "high")
        end)
        RT.player:addToShipLog("Science: debris cloud near Wren's Folly contains a powered object.", "#80C0FF")
        RT.setObjective("Recover the powered object near Wren's Folly.")
    end})

    DIR.defineBeat("watcher", {ai = true, desc = "An unknown Ghost ship watches the Magpie from the Shroud, then vanishes (foreshadowing; not hostile)", fn = function()
        local x, y = RT.player:getPosition()
        local dx, dy = vectorFromAngle(random(0, 360), 11000, true)
        local g = CpuShip():setTemplate("Stalker Q7"):setFaction("Unknown"):setCallSign("UNKNOWN")
        g:setPosition(x + dx, y + dy):orderIdle()
        g:setCommsFunction(function() setCommsMessage("A burst of compressed tone. It sounds like the data core.") end)
        RT.register(g)
        RT.after(75, function()
            if RT.valid(g) then g:destroy() end
            if RT.valid(RT.player) then RT.player:addToShipLog("Science: the unknown contact is gone. No warp signature.", "#80C0FF") end
        end, "watcher_vanish")
    end})
end

--------------------------------------------------------------------------------
-- CPV Diligence comms: the inspection choice
--------------------------------------------------------------------------------

function diligenceComms(source, target)
    if S.inspection ~= "pending" then
        if S.inspection == "submitted" or S.inspection == "bribed" then
            setCommsMessage("\"You're cleared, " .. source:getCallSign() .. ". Fly safe. Fly legal.\"")
        elseif S.inspection == "ran" or S.inspection == "tagged" then
            setCommsMessage("\"You've got some nerve hailing me.\"")
        else
            setCommsMessage("\"Concord patrol. Keep your transponder on and your nose clean.\"")
            addCommsReply("Anything we should know about out here?", function(s, t)
                setCommsMessage("\"Raiders working the lanes toward the Shroud. Don't make me fish you out.\"")
                DIR.emit("npc_hailed", {callsign = "CPV Diligence", topic = "advice", role = "patrol"}, "normal")
            end)
        end
        return
    end
    setCommsMessage("\"Lieutenant Vashti. Cut your engines and open your hold. Standard inspection.\"")
    addCommsReply("Submit to inspection", function(s, t)
        S.inspection = "submitted"
        S.submit_hold_since = getScenarioTime()
        setCommsMessage("\"Good. Hold position within two units while my scanners do their work.\"")
        RT.setObjective("Hold still near CPV Diligence for the inspection.")
        DIR.emit("choice", {beat = "inspection", choice = "submit"}, "high")
    end)
    if RT.credits() >= 100 then
        addCommsReply("Offer a 'processing fee' (100 cr)", function(s, t)
            S.inspection = "bribed"
            RT.addCredits(-100, "processing fee")
            RT.flag("bribed_concord", true)
            setCommsMessage("\"...Your paperwork appears to be in order. Move along.\"")
            t:orderIdle()
            RT.setObjective("Deliver the crates to Halcyon Rest.")
            DIR.emit("choice", {beat = "inspection", choice = "bribe"}, "high")
        end)
    end
    addCommsReply("\"Sorry, you're breaking up...\" (run)", function(s, t)
        startChase()
        setCommsMessage("\"Don't you dare--\"")
    end)
end

function startChase()
    S.inspection = "ran"
    S.chase_until = getScenarioTime() + 90
    RT.flag("ran_from_concord", true)
    RT.setObjective("Shake the Concord patrol, then deliver the crates.")
    DIR.emit("choice", {beat = "inspection", choice = "run"}, "high")
end

function updateInspection(delta)
    local dil = S.diligence
    if not RT.valid(dil) or not RT.valid(RT.player) then return end
    local now = getScenarioTime()
    local d = RT.dist(dil, RT.player)

    if S.inspection == "pending" then
        if d > 14000 and now - S.inspection_started > 20 then
            -- They ignored the hail and kept flying: that's running.
            startChase()
        elseif now - (S.last_follow or 0) > 4 then
            S.last_follow = now
            dil:orderFlyTowards(RT.player:getPosition())
        end
    elseif S.inspection == "submitted" then
        if d < 2500 then
            S.submit_hold_since = S.submit_hold_since or now
            if now - S.submit_hold_since > 25 then
                S.inspection = "cleared"
                S.payout = S.payout - 100
                RT.flag("inspected", true)
                dil:orderIdle()
                RT.hail(dil, "\"One crate's... unusual. I'm impounding a sample. You're cleared, " ..
                    "but your client won't be happy.\" (Payout reduced by 100.)")
                RT.setObjective("Deliver the crates to Halcyon Rest.")
                DIR.emit("choice", {beat = "inspection", choice = "submit_complete"}, "normal")
            end
        else
            S.submit_hold_since = nil
            if now - (S.last_follow or 0) > 4 then
                S.last_follow = now
                dil:orderFlyTowards(RT.player:getPosition())
            end
        end
    elseif S.inspection == "ran" then
        if now - (S.last_follow or 0) > 3 then
            S.last_follow = now
            dil:orderFlyTowardsBlind(RT.player:getPosition())
        end
        if d < 2000 then S.chase_close_time = S.chase_close_time + delta end
        if S.chase_close_time >= 20 then
            S.inspection = "tagged"
            RT.flag("wanted", true)
            RT.addCredits(-150, "Concord fine")
            dil:orderIdle()
            RT.hail(dil, "\"Transponder tagged. You're in the system now, " .. RT.player:getCallSign() .. ". Enjoy the fine.\"")
            RT.setObjective("Deliver the crates to Halcyon Rest.")
            DIR.emit("choice", {beat = "inspection", choice = "tagged"}, "high")
        elseif now > S.chase_until or d > 20000 then
            S.inspection = "escaped"
            dil:orderIdle()
            RT.player:addToShipLog("CPV Diligence has broken off pursuit.", "#A0FFA0")
            RT.setObjective("Deliver the crates to Halcyon Rest.")
            DIR.emit("choice", {beat = "inspection", choice = "escaped"}, "high")
        end
    end
end

--------------------------------------------------------------------------------
-- Halcyon Rest hooks (delivery wrap-up)
--------------------------------------------------------------------------------

local function finishSession(outcome, note)
    if S.ending then return end
    S.ending = true
    S.phase = "done"
    RT.completeSession("s1", outcome, note)
    DIR.emit("session_end", {session = "s1", outcome = outcome, note = note,
        flags = RT.campaign.flags, credits = RT.credits()}, "high")
    globalMessage("Session complete: " .. note, 10)
    RT.after(12, function() victory(RT.PLAYER_FACTION) end, "victory")
end

function addHalcyonHooks()
    RT.addStationHook("Halcyon Rest", function(source, target)
        if S.phase == "delivered" or S.phase == "salvage" then
            addCommsReply("\"We're done here, Doc.\" (end session)", function(s, t)
                setCommsMessage("\"Right. Of course. Safe travels. I never saw that crate.\"")
                finishSession("success", "Delivered the cargo and left the Shroud alone.")
            end)
        end
        if S.core_taken and source:isDocked(target) then
            addCommsReply("Show Doc Salo the data core (end session)", function(s, t)
                setCommsMessage("\"That sigil... that's a lantern. Keep it hidden. Keep it SAFE. And maybe don't tell Mags.\"")
                RT.flag("salo_knows", true)
                finishSession("success", "Delivered the cargo and recovered the lantern core.")
            end)
        end
    end)
    RT.addStationHook("Port Vesper", function(source, target)
        if S.core_taken and source:isDocked(target) then
            addCommsReply("Tell Mags about the data core (end session)", function(s, t)
                setCommsMessage("\"Well now. My lambs found a lantern. Keep it close and keep it quiet. We'll talk.\"")
                RT.flag("mags_knows", true)
                finishSession("success", "Recovered the lantern core and told Mags.")
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- GM tools for this session
--------------------------------------------------------------------------------

function addSessionGMFunctions()
    addGMFunction("S1: fire inspection", function() DIR.fireBeat("inspection", "gm") end)
    addGMFunction("S1: fire ambush", function() DIR.fireBeat("ambush", "gm") end)
    addGMFunction("S1: fire watcher", function() DIR.fireBeat("watcher", "gm") end)
    addGMFunction("S1: end (success)", function() finishSession("success", "GM ended the session.") end)
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

function update(delta)
    RT.update(delta)
    VERSE.update(delta)
    DIR.update(delta)

    if S.phase == "done" then return end
    local p = RT.player
    if not RT.valid(p) then
        if not S.ending then
            S.ending = true
            RT.completeSession("s1", "failed", "The Magpie was lost.")
            DIR.emit("session_end", {session = "s1", outcome = "failed"}, "high")
            RT.after(6, function() victory("Corsairs") end, "defeat")
        end
        return
    end
    local now = getScenarioTime()

    if S.phase == "start" then
        if now > 5 then
            DIR.fireBeat("briefing", "script")
            addHalcyonHooks()
            S.phase = "loading"
        end
        return
    end

    if S.phase == "loading" then
        local vesper = RT.find("Port Vesper")
        if p:isDocked(vesper) then
            S.docked_since = S.docked_since or now
            if now - S.docked_since > 8 then DIR.fireBeat("cargo_loaded", "script") end
        else
            S.docked_since = nil
        end
        return
    end

    if S.phase == "hauling" then
        updateInspection(delta)
        local halcyon = RT.find("Halcyon Rest")
        -- Fallbacks so the session works without the director.
        if not DIR.beatFired("inspection") and RT.valid(S.diligence) and RT.dist(p, S.diligence) < 7000 then
            DIR.fireBeat("inspection", "fallback")
        end
        if not DIR.beatFired("ambush") and (RT.dist(p, halcyon) < 18000 or now - S.loaded_at > 420) then
            if S.inspection ~= "pending" and S.inspection ~= "submitted" then
                DIR.fireBeat("ambush", "fallback")
            end
        end
        if p:isDocked(halcyon) then
            if S.inspection == "pending" then startChase() end
            DIR.fireBeat("delivery", "script")
        end
        return
    end

    if S.phase == "delivered" or S.phase == "salvage" then
        updateInspection(delta)
        if not S.folly_scanned and RT.valid(S.folly) and S.folly:isFullyScannedBy(p) then
            DIR.fireBeat("folly_secret", "script")
        end
        if S.folly_scanned and not S.core_taken and not DIR.beatFired("watcher") and RT.dist(p, S.folly) < 6000 then
            if now - (S.folly_close_since or now) > 40 then DIR.fireBeat("watcher", "fallback") end
            S.folly_close_since = S.folly_close_since or now
        end
    end
end
