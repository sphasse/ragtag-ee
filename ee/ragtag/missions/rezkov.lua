-- ee/ragtag/missions/rezkov.lua
-- The Rezkov Arc: three missions for the sandbox campaign.
--
-- Trigger: Independent rep >= +500 AND upgrade investment >= 600cr AND Concord rep >= 0 on first contact
-- Structure: hook -> m1_navigate -> m2_active -> m2_deliver -> m3_active -> m3_deliver -> done
--
-- RT.flag keys used (prefix "rezkov_"):
--   hook              rumor phase active
--   declined          player declined The Fixer (arc ends permanently)
--   m1_done           player met Rezkov and accepted M2
--   m2_done           hack + data delivery complete
--   m3_accepted       intercept accepted
--   m3_data           data card seized from CWS Meridian
--   arc_done          arc complete (value = outcome string)

local M = {}
M.id          = "rezkov"
M.name        = "Rezkov Arc"
M.repeatable  = false
M.locks_jobs  = false
M.auto_start  = true
M.start_phase = "init"

M.triggers = {
    rep_min      = {Independent = 500},
    upgrades_min = 600,
    not_flagged  = {"rezkov_declined", "rezkov_arc_done"},
}

M.phase_order = {
    "init", "hook", "m1_navigate",
    "m2_active", "m2_deliver",
    "m3_active", "m3_deliver",
}

function M.init_state()
    return {
        waypoint    = nil,   -- Rezkov's Waypoint entity
        nebulas     = {},    -- nebula cluster entities
        galen       = nil,   -- Waypoint Galen SpaceStation (hack detection target)
        hack_done   = false,
        meridian    = nil,   -- M3 CWS Meridian
        m3_disabled = false,
        m3_boarded  = false,
    }
end

-- ── Coordinates ─────────────────────────────────────────────────────────────

-- Rezkov's Waypoint: between Dustmote (104,-36) and Boneyard (36,-96)
local _RWX = 115000  -- verse ~(115, -72)
local _RWY = -72000

-- CWS Meridian start: monitoring position between Dustmote (104,-36) and Rezkov's station
local _MX = 110000   -- verse ~(110, -55)
local _MY = -55000

-- Nebula cluster surrounding the waypoint (irregular arrangement, world units)
local _NEBULA_POS = {
    {112000, -69000},
    {116000, -68000},
    {120000, -70000},
    {121000, -74000},
    {119000, -78000},
    {114000, -78000},
    {110000, -74000},
}

-- Concord Waypoint Galen: verse (-75, -52). Terminal spawns slightly NE.


-- ── Spawn helpers ────────────────────────────────────────────────────────────

local function _spawnWaypoint(st)
    if RT.valid(st.waypoint) then return end

    for _, pos in ipairs(_NEBULA_POS) do
        local n = Nebula():setPosition(pos[1], pos[2])
        st.nebulas[#st.nebulas + 1] = n
    end

    local wp = CpuShip():setTemplate("Defense platform"):setFaction("Unknown")
    wp:setCallSign("Rezkov's station")
    wp:setPosition(_RWX, _RWY)
    wp:setCanBeDestroyed(false)
    wp:orderIdle()
    wp:setCommsFunction(function(src, tgt)
        local phase = MISSIONS._cur_phase["rezkov"]
        local art = MISSIONS._state["rezkov"]

        -- Comms are phase-driven so GM can jump to any phase cleanly.
        if phase == "m1_navigate" then
            if not src:isDocked(tgt) then
                setCommsMessage('"Approach and dock. We do not do business at a distance."')
                addCommsReply("Back", function() setCommsMessage("The channel closes.") end)
                return
            end
            setCommsMessage('"You found it.\n\nI am Orlan Rezkov. Reputation got you to my door. What you do after the door opens -- that is what matters.\n\nI need something from a Concord station. Not a fleet base, nothing dramatic. Concord Waypoint Galen on the Arbiter Line. I want the traffic log -- ninety days of docking records. I need to know if someone in my organization is talking.\n\nI will tell you this: your name does not raise flags with their patrols. Keep it that way until the job is finished."')
            addCommsReply("We're up for the challenge.", function(s2, t2)
                local concord_rep = RT.getReputation("Concord") or 0
                if concord_rep < 0 then
                    setCommsMessage('"Not yet. The patrols are watching you. When your name stops raising flags, come back."')
                    addCommsReply("Understood.", function(s3, t3) setCommsMessage("The channel closes.") end)
                    return
                end
                RT.shipLog("[Rezkov] Job accepted: Concord Waypoint Galen (grid " .. JOBS.gridRef(-75000, -52000) .. "), Arbiter Line. Hack the station's front shield generator to 100%. Retrieve 90-day traffic log. Deliver storage card to Thresh at Dustmote Salvage. 600cr.", "#A0C0FF")
                RT.setObjective("Hack Waypoint Galen", true)
                RT.flag("rezkov_m1_done", true)
                MISSIONS.phase("rezkov", "m2_active")
                setCommsMessage('"Waypoint Galen. Small Concord checkpoint, Arbiter Line. Dock with the station and hack their front shield generators to 100% to download the traffic log to the storage card.\n\nThen bring the card to my contact at Dustmote Salvage. Ask for Thresh.\n\n600 credits on delivery. Make your way over there but do not make it look suspicious. Pick up some jobs along the way to get you closer."')
                addCommsReply("Understood.", function() setCommsMessage("Rezkov ends the channel.") end)
            end)
            addCommsReply("Not our kind of work.", function(s2, t2)
                setCommsMessage('"The door stays open. Come back when you change your mind."')
                addCommsReply("Back", function() setCommsMessage("Rezkov ends the channel.") end)
            end)
            return
        elseif phase == "m2_active" then
            setCommsMessage('"Waypoint Galen is not far. I am still waiting."')
            addCommsReply("Understood.", function() setCommsMessage("Rezkov ends the channel.") end)
        elseif phase == "m2_deliver" then
            setCommsMessage('"The job is done. Take the card to Thresh at Dustmote Salvage."')
            addCommsReply("Understood.", function() setCommsMessage("Rezkov ends the channel.") end)
        elseif phase ~= nil then
            setCommsMessage('"I will have more work. Keep flying."')
            addCommsReply("Understood.", function() setCommsMessage("Rezkov ends the channel.") end)
        else
            setCommsMessage("[Rezkov's station] No response on this frequency.")
        end
    end)
    RT.register(wp)
    st.waypoint = wp
end

local function _despawnWaypoint(st)
    for _, n in ipairs(st.nebulas) do
        if n and n:isValid() then n:destroy() end
    end
    st.nebulas = {}
    if RT.valid(st.waypoint) then
        st.waypoint:setCanBeDestroyed(true)
        st.waypoint:destroy()
    end
    st.waypoint = nil
    RT.named["Rezkov's station"] = nil
end

local function _spawnHackTerminal(st)
    if st.galen then return end
    for _, obj in ipairs(getObjectsInRadius(-75000, -52000, 3000)) do
        if isObjectType(obj, "SpaceStation") then
            st.galen = obj
            break
        end
    end
end

local function _checkHack(st, now)
    if st.hack_done then return end
    if not RT.valid(st.galen) then return end

    local ok, lvl = pcall(function() return st.galen:getSystemHackedLevel("frontshield") end)
    local hack_lvl = (ok and lvl) and lvl or 0

    if hack_lvl >= 1.0 then
        st.hack_done = true
        RT.shipLog("[Hack] Rogue AI successfully installed in the Concord accounting systems.", "#80FF80")
        RT.after(4, function()
            RT.shipLog("[Hack] Station traffic downloaded to the storage card.", "#80FF80")
            RT.shipLog("[Mission] Deliver the storage card to Thresh at Dustmote Salvage (grid " .. JOBS.gridRef(104000, -36000) .. ").", "#A0C0FF")
            RT.setObjective("Card to Thresh @ Dustmote", true)
            MISSIONS.phase("rezkov", "m2_deliver")
        end, "rezkov_hack_msg2")
    end
end

local function _spawnMeridian(st)
    if RT.valid(st.meridian) then return end
    local meridian = CpuShip():setTemplate("Concord Enforcer"):setFaction("Concord")
    meridian:setCallSign("CWS Meridian"):setTypeName("CpuShip")
    meridian:setPosition(_MX, _MY)
    -- Fast impulse burn toward Waypoint Galen (Arbiter Line) — catchable by warp but requires urgency
    meridian:setImpulseMaxSpeed(500):orderFlyTowards(-75000, -52000)
    pcall(function() meridian.components.docking_bay = {external_dock_classes = {"Frigate"}} end)
    RT.register(meridian)
    st.meridian = meridian
    RT.shipLog("[Intel] CWS Meridian spotted at grid " .. JOBS.gridRef(_MX, _MY) .. " burning for Concord space. Disable and board before she reaches the Arbiter Line.", "#FFAA00")
end

local function _checkMeridianDisabled(st)
    if not RT.valid(st.meridian) or st.m3_disabled then return end
    local ok1, hull     = pcall(function() return st.meridian:getHull() end)
    local ok2, hmax     = pcall(function() return st.meridian:getHullMax() end)
    local ok3, impulse_h = pcall(function() return st.meridian:getSystemHealth("impulse") end)
    local hull_low    = ok1 and ok2 and hmax > 0 and hull / hmax < 0.25
    local impulse_low = ok3 and impulse_h and impulse_h < 0.3
    if hull_low or impulse_low then
        st.m3_disabled = true
        st.meridian:setCanBeDestroyed(false)
        st.meridian:orderIdle()
        st.meridian:setFaction("Independent")
        st.meridian:setCommsFunction(function(src, tgt)
            setCommsMessage('"CWS Meridian -- engines disabled. We surrender. Close to within 1U and request docking."')
            addCommsReply("Understood. Stand by.", function() setCommsMessage("Channel open.") end)
        end)
        RT.shipLog("[CWS Meridian] Ship disabled. Close to within 1U and dock to board.", "#FFCC80")
        RT.setObjective("Board CWS Meridian", true)
    end
end

local function _setupKaelComms(st)
    st.m3_boarded = true
    RT.shipLog("[CWS Meridian] Docked. Hail Commander Kael.", "#FFCC80")
    RT.setObjective("Speak with Commander Kael", true)
    st.meridian:setCommsFunction(function(src, tgt)
        setCommsMessage('"CWS Meridian -- engines disabled. I\'ll be direct.\n\nI\'m Commander Kael, Concord Intelligence. I\'ve been monitoring traffic out of Dustmote for three months. I have comms intercepts, cargo manifests, ship registrations -- yours is in the file. So is Rezkov\'s.\n\nYou have a choice. Stand down and let us proceed to Concord space. The Concord will remember that you cooperated. Or take the data and run -- but know this won\'t be the last time you see me."')
        addCommsReply("Let the Concord go.", function(s2, t2)
            setCommsMessage('"Wise. The Concord will remember."')
            addCommsReply("Understood.", function(s3, t3)
                RT.addReputation("Independent", -1000, "Rezkov Arc: cooperated with Concord against Rezkov")
                RT.addReputation("Concord", 500, "Rezkov Arc: cooperated with Concord investigator")
                RT.shipLog("[Rezkov Arc] Done. Concord proceeds with investigation. Independent -1000. Concord +500.", "#FF8080")
                RT.flag("rezkov_arc_done", "concord_won")
                RT.note("Let CWS Meridian commander Kael proceed with Rezkov investigation data. Concord file intact.")
                if RT.valid(st.meridian) then
                    st.meridian:setFaction("Concord")
                    st.meridian:setImpulseMaxSpeed(500):orderFlyTowards(-75000, -52000)
                end
                MISSIONS.phase("rezkov", "done")
            end)
        end)
        addCommsReply("Take the data.", function(s2, t2)
            setCommsMessage('"Take it then.\n\nThis won\'t be the last time you see me, Magpie."')
            addCommsReply("We\'re taking the data.", function(s3, t3)
                RT.addReputation("Concord", -1000, "Rezkov Arc: seized Concord investigation data")
                RT.shipLog("[Rezkov Arc] Data seized. Concord -1000. Deliver the data card to Thresh at Dustmote Salvage (grid " .. JOBS.gridRef(104000, -36000) .. ").", "#FFCC80")
                RT.flag("rezkov_m3_data", true)
                RT.setObjective("Deliver data to Thresh @ Dustmote", true)
                if RT.valid(st.meridian) then
                    st.meridian:setFaction("Independent")
                    st.meridian:orderIdle()
                end
                MISSIONS.phase("rezkov", "m3_deliver")
            end)
        end)
    end)
end

-- ── Station hooks ─────────────────────────────────────────────────────────

local function _dustmoteHook(src, tgt, info)
    if not src:isDocked(tgt) then return end
    local phase = MISSIONS._cur_phase["rezkov"]
    local st = MISSIONS._state["rezkov"]

    -- M1 hook phase: The Fixer makes contact
    if phase == "hook" and not RT.flag("rezkov_declined") then
        addCommsReply("Heard you were looking for an independent operator.", function(s2, t2)
            setCommsMessage('"There is someone who wants to meet you. Goes by Thresh -- local contact for a business associate. Word travels in the Drift, and your name has been mentioned.\n\nInterested in hearing more?"')
            addCommsReply("Sure, what\'s the job?", function(s3, t3)
                setCommsMessage('"The associate likes to meet people in person. Doesn\'t do business through go-betweens. If you are interested, he has arranged a meeting.\n\nHead out at bearing 15. You\'ll hit a nebula cloud. You\'ll find what you are looking for there.\n\nMind what you say when you get there. He remembers everything."')
                addCommsReply("We\'ll head out.", function(s4, t4)
                    RT.shipLog("[Navigation] Bearing 15. Nebula field. Find the contact.", "#A0C0FF")
                    RT.setObjective("Find the waypoint", true)
                    RT.flag("rezkov_hook", true)
                    MISSIONS.phase("rezkov", "m1_navigate")
                    setCommsMessage('"Good. He will be expecting you."\n\nThresh turns back to work.')
                    addCommsReply("Understood.", function() setCommsMessage("Thresh turns back to work.") end)
                end)
                addCommsReply("Not right now.", function(s4, t4)
                    setCommsMessage('"The offer stays open. Thresh is usually around."')
                    addCommsReply("Back", function() setCommsMessage("Thresh nods.") end)
                end)
            end)
            addCommsReply("Not interested.", function(s3, t3)
                setCommsMessage('"Suit yourself."')
                addCommsReply("Back", function()
                    RT.flag("rezkov_declined", true)
                    setCommsMessage("Thresh shrugs and goes back to work.")
                end)
            end)
        end)
        return
    end

    -- M2 delivery: bring data card to Thresh
    if phase == "m2_deliver" then
        addCommsReply("Delivery for Thresh.", function(s2, t2)
            setCommsMessage('"Thresh takes the card and disappears into the back.\n\n..."')
            addCommsReply("Understood.", function(s3, t3)
                RT.addCredits(600, "Rezkov Arc M2: data delivery")
                RT.shipLog("[Rezkov Arc] M2 complete. 600cr received. Rezkov's station has gone dark.", "#80FF80")
                RT.flag("rezkov_m2_done", true)
                if st then _despawnWaypoint(st) end
                MISSIONS.phase("rezkov", "m3_active")
                setCommsMessage('"We have a problem.\n\nThe Concord had a monitoring ship running surveillance on Dustmote. They have traffic logs, comms intercepts -- yours and mine both. That ship, the CWS Meridian, is burning for Concord space right now.\n\nWe need to board her and wipe that data before she gets there. No credits for this one -- you\'re doing it to keep yourself out of a Concord cell as much as anything.\n\nShe was spotted at grid " .. JOBS.gridRef(_MX, _MY) .. ". Move fast."')
                addCommsReply("We\'re on it.", function(s4, t4)
                    RT.flag("rezkov_m3_accepted", true)
                    RT.shipLog("[Rezkov Arc] M3: Intercept CWS Meridian. Last spotted at grid " .. JOBS.gridRef(_MX, _MY) .. ", burning for the Arbiter Line. Disable and board before she gets there.", "#A0C0FF")
                    RT.setObjective("Disable and board CWS Meridian", true)
                    setCommsMessage('"Grid " .. JOBS.gridRef(_MX, _MY) .. ". Move fast. She\'s burning hard."')
                    addCommsReply("Understood.", function(s5, t5)
                        setCommsMessage("Thresh disappears into the back.")
                    end)
                end)
                addCommsReply("Not right now.", function(s4, t4)
                    setCommsMessage('"She\'s not waiting. The offer closes when that ship hits Concord space."')
                    addCommsReply("Back", function() setCommsMessage("Thresh shrugs.") end)
                end)
            end)
        end)
        return
    end

    -- M3 re-offer: shown on re-hail if crew said "not right now" after M2 delivery
    if phase == "m3_active" and RT.flag("rezkov_m2_done") and not RT.flag("rezkov_m3_accepted") then
        addCommsReply("Thresh -- that Concord ship.", function(s2, t2)
            setCommsMessage('"She\'s still running. Last grid " .. JOBS.gridRef(_MX, _MY) .. ". You need to move."')
            addCommsReply("We\'re on it.", function(s3, t3)
                RT.flag("rezkov_m3_accepted", true)
                RT.shipLog("[Rezkov Arc] M3: Intercept CWS Meridian before she reaches the Arbiter Line. Disable and board.", "#A0C0FF")
                RT.setObjective("Disable and board CWS Meridian", true)
                setCommsMessage('"Move."')
                addCommsReply("Understood.", function(s4, t4) setCommsMessage("Thresh disappears.") end)
            end)
            addCommsReply("Not yet.", function(s3, t3)
                setCommsMessage('"Clock\'s running."')
                addCommsReply("Back", function() setCommsMessage("Thresh nods.") end)
            end)
        end)
        return
    end

    -- M3 data delivery: return seized Concord data to Thresh
    if phase == "m3_deliver" and RT.flag("rezkov_m3_data") and not RT.flag("rezkov_arc_done") then
        addCommsReply("Thresh -- we have the data from the Meridian.", function(s2, t2)
            setCommsMessage('"Thresh takes the drive and scans it.\n\n\"Good. This is everything.\"\n\nHe leans back.\n\n\"We barely got out of that. I\'m going to lay low for a while -- I suggest you do the same. But you\'ve proved yourselves. More work is headed your way.\""')
            addCommsReply("Understood.", function(s3, t3)
                RT.addReputation("Independent", 200, "Rezkov Arc: delivered seized Concord data")
                RT.shipLog("[Rezkov Arc] Done. Data delivered to Thresh. Independent +200.", "#80FF80")
                RT.flag("rezkov_arc_done", "data_delivered")
                RT.note("Delivered seized CWS Meridian investigation data to Thresh. Rezkov's network protected. Kael's threat noted.")
                MISSIONS.phase("rezkov", "done")
            end)
        end)
        return
    end
end


-- ── Resolve and cancel ────────────────────────────────────────────────────

function M.resolve(st)
    RT.shipLog("[Rezkov Arc] Arc complete. Outcome: " .. tostring(RT.flag("rezkov_arc_done")), "#80FF80")
    globalMessage("Rezkov Arc complete.", 8)
end

function M.on_cancel(st)
    _despawnWaypoint(st)
    if RT.valid(st.meridian) then
        st.meridian:setCanBeDestroyed(true)
        st.meridian:destroy()
        st.meridian = nil
        RT.named["CWS Meridian"] = nil
    end
    RUMORS.removeCategory("REZKOV_HOOK")
end

-- ── GM actions ────────────────────────────────────────────────────────────

M.gm_actions = {
    {label = "Skip to M2", fn = function(st)
        RT.flag("rezkov_m1_done", true)
        MISSIONS.phase("rezkov", "m2_active")
        globalMessage("[GM] Rezkov Arc: skipped to M2 (hack).", 4)
    end},
    {label = "Skip to M3", fn = function(st)
        RT.flag("rezkov_m1_done", true)
        RT.flag("rezkov_m2_done", true)
        RT.flag("rezkov_m3_accepted", true)
        MISSIONS.phase("rezkov", "m3_active")
        globalMessage("[GM] Rezkov Arc: skipped to M3 (intercept).", 4)
    end},
    {label = "Complete hack", phases = {"m2_active"},
     fn = function(st)
        if not st.hack_done and RT.valid(st.galen) then
            st.galen:setSystemHackedLevel("frontshield", 1.0)
        end
    end},
    {label = "Disable Meridian", phases = {"m3_active"},
     fn = function(st)
        if RT.valid(st.meridian) then
            local ok, hmax = pcall(function() return st.meridian:getHullMax() end)
            if ok and hmax then st.meridian:setHull(hmax * 0.1) end
        end
    end},
}

-- ── Phases ─────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        -- Register station hook once per session (safe: each session starts fresh)
        RT.addStationHook("Dustmote Salvage", _dustmoteHook)

        -- Route to the appropriate phase based on saved flags
        if RT.flag("rezkov_arc_done") then
            MISSIONS.phase("rezkov", "done")
        elseif RT.flag("rezkov_m3_data") then
            MISSIONS.phase("rezkov", "m3_deliver")
        elseif RT.flag("rezkov_m3_accepted") or RT.flag("rezkov_m2_done") then
            MISSIONS.phase("rezkov", "m3_active")
        elseif RT.flag("rezkov_m1_done") then
            MISSIONS.phase("rezkov", "m2_active")
        elseif RT.flag("rezkov_hook") then
            MISSIONS.phase("rezkov", "m1_navigate")
        else
            MISSIONS.phase("rezkov", "hook")
        end
    end,
}

M.phases.hook = {
    enter = function(st)
        RUMORS.add({text = "Heard there is a contact at Dustmote Salvage asking for independent crews. Someone with money, looking for a discreet run.", priority = 5, category = "REZKOV_HOOK"})
        RUMORS.add({text = "Word is someone has been spreading credits around Dustmote Salvage. Looking for a crew that knows how to keep quiet.", priority = 5, category = "REZKOV_HOOK"})
        RUMORS.add({text = "If you haven\'t been to Dustmote lately, there might be work. Someone there is looking for independent operators.", priority = 5, category = "REZKOV_HOOK"})
    end,
    exit = function(st)
        RUMORS.removeCategory("REZKOV_HOOK")
    end,
}

M.phases.m1_navigate = {
    enter = function(st)
        RUMORS.removeCategory("REZKOV_HOOK")
        _spawnWaypoint(st)
        RT.shipLog("[Navigation] Bearing 15. Nebula field. Find the contact.", "#A0C0FF")
        RT.setObjective("Find the waypoint", true)
    end,
}

M.phases.m2_active = {
    enter = function(st)
        st.hack_done = false
        _spawnWaypoint(st)
        _spawnHackTerminal(st)
        RT.setObjective("Hack Waypoint Galen", true)
    end,

    update = function(st, delta, now)
        _checkHack(st, now)
    end,
}

M.phases.m2_deliver = {
    -- The Dustmote hook handles the delivery interaction.
    -- This phase persists until the hook fires _despawnWaypoint and transitions to m3_active.
}

M.phases.m3_active = {
    enter = function(st)
        -- Spawn Meridian immediately — she's already burning whether the crew accepts or not
        _spawnMeridian(st)
        if RT.flag("rezkov_m3_accepted") then
            RT.setObjective("Disable and board CWS Meridian", true)
        end
    end,

    update = function(st, delta, now)
        if RT.flag("rezkov_arc_done") then return end

        -- Meridian destroyed before boarding
        if st.meridian and not RT.valid(st.meridian) and not st.m3_disabled then
            RT.addReputation("Concord", -1000, "Rezkov Arc: destroyed Concord investigation vessel")
            RT.addReputation("Independent", 200, "Rezkov Arc: destroyed Concord investigation vessel")
            RT.shipLog("[Rezkov Arc] CWS Meridian destroyed. All data lost. Concord -1000. Independent +200.", "#FF8080")
            RT.flag("rezkov_arc_done", "meridian_destroyed")
            MISSIONS.phase("rezkov", "done")
            return
        end

        if not RT.flag("rezkov_m3_accepted") then return end

        _checkMeridianDisabled(st)

        if st.m3_disabled and not st.m3_boarded and RT.valid(st.meridian) then
            for _, p in ipairs(RT.players) do
                if RT.valid(p) and p:isDocked(st.meridian) then
                    _setupKaelComms(st)
                    break
                end
            end
        end
    end,
}

M.phases.m3_deliver = {
    -- Dustmote hook handles the data delivery interaction.
}

MISSIONS.register(M)
