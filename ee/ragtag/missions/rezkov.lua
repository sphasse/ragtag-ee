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
--   m3_data           data wiped from CWS Meridian
--   arc_done          arc complete (value = outcome string)
--
-- Long-term flags (no prefix, available to future arcs):
--   kael_alive        true if Cmdr Kael survived the arc; false if Meridian was destroyed

local _hook_registered   = false  -- guard against double-registration on GM restart

local M = {}
M.id          = "rezkov"
M.name        = "Rezkov Arc"
M.repeatable         = false
M.locks_jobs         = false
M.auto_start         = true
M.start_phase        = "init"
M.no_auto_cancel     = true   -- navigation handled by gm_actions

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
    for _, n in ipairs(st.nebulas or {}) do
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

local function _safeComms(fn)
    return function(src, tgt)
        local ok, err = pcall(fn, src, tgt)
        if not ok then
            log("[RZKOV][COMMS] pcall error: " .. tostring(err))
            setCommsMessage("[Meridian comms error — check server log]")
        end
    end
end

local function _spawnMeridian(st)
    if RT.valid(st.meridian) then return end
    -- Spawn as Concord (neutral to Independent) so she doesn't pick fights with traffic.
    -- Switches to Concord Hostile when player closes to weapons range, making her targetable.
    -- Rep tracking is cancelled before any scripted despawn; the arc handles all rep manually.
    local meridian = CpuShip():setTemplate("Phobos T3"):setFaction("Concord")
    meridian:setCallSign("CWS Meridian"):setTypeName("CpuShip")
    meridian:setWeaponStorage("Nuke", 0):setWeaponStorageMax("Nuke", 0)
    meridian:setPosition(_MX, _MY)
    -- Moderate speed: faster than player impulse so warp is needed to intercept, but slow enough
    -- that the player can get sustained beam fire once alongside.
    meridian:setImpulseMaxSpeed(200):orderFlyTowards(-21000, -27000)
    meridian:setCommsScript(""):setCommsFunction(_safeComms(function(src, tgt)
        setCommsMessage('"CWS Meridian. This is a restricted Concord vessel. Stand clear."')
    end))
    RT.register(meridian)
    st.meridian = meridian
    st.m3_hostile = false
    RT.shipLog("[Intel] CWS Meridian spotted at grid " .. JOBS.gridRef(_MX, _MY) .. ", headed toward Concord Station Arbiter. Disable and board before she gets there.", "#FFAA00")
end

local function _checkMeridianDisabled(st)
    if not RT.valid(st.meridian) or st.m3_disabled then return end
    local ok1, hull     = pcall(function() return st.meridian:getHull() end)
    local ok2, hmax     = pcall(function() return st.meridian:getHullMax() end)
    local ok3, impulse_h = pcall(function() return st.meridian:getSystemHealth("impulse") end)
    local hull_low    = ok1 and ok2 and hmax > 0 and hull / hmax < 0.25
    local impulse_low = ok3 and impulse_h and impulse_h < 0.3
    if not ok1 or not ok2 or not ok3 then
        log(string.format("[RZKOV] _checkMeridianDisabled ERROR: hull_ok=%s hmax_ok=%s impulse_ok=%s",
            tostring(ok1), tostring(ok2), tostring(ok3)))
    end
    if hull_low or impulse_low then
        st.m3_disabled = true
        st.meridian:setCanBeDestroyed(false)
        st.meridian:setImpulseMaxSpeed(0)   -- bleed off the 500u/s transit speed immediately
        st.meridian:setWarpSpeed(0)
        st.meridian:orderIdle()
        st.meridian:setFaction("Independent")
        local ok_dock, dock_err = pcall(function()
            st.meridian.components.docking_bay = {external_dock_classes = {"Frigate"}}
        end)
        log(string.format("[RZKOV] docking_bay set: ok=%s err=%s", tostring(ok_dock), tostring(dock_err)))
        st.meridian:setCommsScript(""):setCommsFunction(_safeComms(function(src, tgt)
            log(string.format("[RZKOV] disabled-comms opened: src=%s tgt_valid=%s faction=%s",
                tostring(src and src:getCallSign()), tostring(RT.valid(tgt)),
                tostring(RT.valid(tgt) and tgt:getFaction())))
            setCommsMessage('"CWS Meridian -- engines are down. We\'re not going anywhere. Close to within 1U and dock to board."')
            addCommsReply("Understood.", function()
                log("[RZKOV] disabled-comms: Understood clicked")
                setCommsMessage('"Meridian out."')
            end)
        end))
        log("[RZKOV] Meridian disabled — faction=Independent, commsFunction set, m3_disabled=true")
        RT.shipLog("[CWS Meridian] Ship disabled. Close to within 1U and dock to board.", "#FFCC80")
        RT.setObjective("Board CWS Meridian", true)
    end
end

local function _setupKaelComms(st)
    log(string.format("[RZKOV] _setupKaelComms: called — m3_boarded was %s, meridian_valid=%s",
        tostring(st.m3_boarded), tostring(RT.valid(st.meridian))))
    st.m3_boarded = true
    RT.setObjective("Speak with Commander Kael", true)
    if SCIDB and SCIDB.addKaelProfile then pcall(SCIDB.addKaelProfile) end   -- Science DB: "Commander Kael"
    st.meridian:setCommsScript(""):setCommsFunction(_safeComms(function(src, tgt)
        log(string.format("[RZKOV] kael-comms opened: src=%s tgt_valid=%s faction=%s",
            tostring(src and src:getCallSign()), tostring(RT.valid(tgt)),
            tostring(RT.valid(tgt) and tgt:getFaction())))
        setCommsMessage('"CWS Meridian -- engines disabled. I\'ll be direct.\n\nI\'m Commander Kael, Concord Intelligence. I\'ve been monitoring traffic out of Dustmote for three months. I have comms intercepts, cargo manifests, ship registrations -- yours is in the file. So is Rezkov\'s.\n\nYou have a choice. Stand down and let us proceed to Concord space. The Concord will remember that you cooperated, and Rezkov will take the fall. Or wipe the data and run -- but know this won\'t be the last time you see me."')
        addCommsReply("Let the Concord go.", function(s2, t2)
            log("[RZKOV] kael-comms: 'Let the Concord go' clicked")
            setCommsMessage('"Wise. The Concord will remember."')
            addCommsReply("Understood.", function(s3, t3)
                log("[RZKOV] kael-comms: 'Understood' (let go) clicked")
                RT.addReputation("Independent", -1000, "Rezkov Arc: cooperated with Concord against Rezkov")
                RT.addReputation("Concord", 500, "Rezkov Arc: cooperated with Concord investigator")
                RT.shipLog("[Rezkov Arc] Done. Concord proceeds with investigation.", "#FF8080")
                RT.flag("kael_alive", true)
                RT.flag("rezkov_arc_done", "concord_won")
                if RT.valid(st.meridian) then
                    st.meridian:setFaction("Concord")
                    st.meridian:setImpulseMaxSpeed(500):orderFlyTowards(-21000, -27000)
                end
                setCommsMessage('"Meridian out."')
                MISSIONS.phase("rezkov", "done")
            end)
        end)
        addCommsReply("Wipe the data.", function(s2, t2)
            log("[RZKOV] kael-comms: 'Wipe the data' clicked")
            RT.addReputation("Concord", -1000, "Rezkov Arc: wiped Concord investigation data")
            RT.shipLog("[Rezkov Arc] Data wiped. Let Thresh know at Dustmote Salvage (grid " .. JOBS.gridRef(104000, -36000) .. ").", "#FFCC80")
            RT.flag("kael_alive", true)
            RT.flag("rezkov_m3_data", true)
            RT.setObjective("Report to Thresh @ Dustmote", true)
            if RT.valid(st.meridian) then
                st.meridian:setFaction("Independent")
                st.meridian:orderIdle()
            end
            MISSIONS.phase("rezkov", "m3_deliver")
            setCommsMessage('"Take it then.\n\nThis won\'t be the last time you see me, Magpie."')
            addCommsReply("We like our odds, Kael.", function(s3, t3)
                log("[RZKOV] kael-comms: 'We like our odds Kael' clicked")
                setCommsMessage('"Meridian out."')
                RT.shipLog("[Rezkov Arc] Report the data wipe to Thresh at Dustmote Salvage.", "#FFCC80")
            end)
        end)
    end))
    RT.shipLog("[CWS Meridian] Docked. Hail Commander Kael.", "#FFCC80")
end

-- ── Station hooks ─────────────────────────────────────────────────────────

local function _dustmoteHook(src, tgt, info)
    if not src:isDocked(tgt) then return end
    local phase = MISSIONS._cur_phase["rezkov"]
    local st = MISSIONS._state["rezkov"]

    -- M1 hook phase: The Fixer makes contact
    if phase == "hook" and not RT.flag("rezkov_declined") then
        addCommsReply("Heard you were looking for an independent operator.", function(s2, t2)
            setCommsMessage('"Word travels in the Drift, and your name has been mentioned. My name\'s Thresh and I\'m looking for a crew that can take on serious work and keep quiet about it.\n\nInterested in hearing more?"')
            addCommsReply("Sure, what\'s the job?", function(s3, t3)
                setCommsMessage('"My associate likes to meet people in person. Doesn\'t do business through go-betweens. If you are interested, he has arranged a meeting.\n\nHead out at bearing 15. You\'ll hit a nebula cloud. You\'ll find what you are looking for there.\n\nMind what you say when you get there. He remembers everything."')
                addCommsReply("We\'ll head out.", function(s4, t4)
                    RT.shipLog("[Navigation] Bearing 15. Nebula field. Find the contact.", "#A0C0FF")
                    RT.setObjective("Find the waypoint", true)
                    RT.flag("rezkov_hook", true)
                    MISSIONS.phase("rezkov", "m1_navigate")
                    setCommsMessage('"Good. He will be expecting you."\n\nThresh turns back to work.')
                end)
                addCommsReply("Not right now.", function(s4, t4)
                    setCommsMessage('"The offer stays open. I\'m usually around Dustmote."')
                    addCommsReply("Back", function() setCommsMessage("Thresh nods.") end)
                end)
            end)
            addCommsReply("Not interested.", function(s3, t3)
                setCommsMessage('"Suit yourself."')
                addCommsReply("Back", function()
                    RT.flag("rezkov_declined", "player_declined")
                    setCommsMessage("Thresh shrugs and goes back to work.")
                end)
            end)
        end)
        return
    end

    -- M2 delivery: bring data card to Thresh
    if phase == "m2_deliver" then
        addCommsReply("Delivery for Thresh.", function(s2, t2)
            setCommsMessage('"Thresh takes the card and pockets it without looking at it.\n\n"Good. Payment\'s being arranged--"\n\nHis comm unit chirps. He glances at it, expression unreadable.\n\n"Urgent call. Give me a moment. Don\'t go anywhere."')
            addCommsReply("Sure.", function(s3, t3)
                RT.addCredits(600, "Rezkov Arc M2: data delivery")
                RT.shipLog("[Rezkov Arc] M2 complete. 600cr received. Rezkov's station has gone dark.", "#80FF80")
                RT.flag("rezkov_m2_done", true)
                if st then _despawnWaypoint(st) end
                MISSIONS.phase("rezkov", "m3_active")
                setCommsMessage('"Thresh comes back. His jaw is set.\n\n"We have a problem.\n\nThe Concord had a monitoring ship running surveillance on Dustmote. They have traffic logs, comms intercepts -- yours and mine both. That ship, the CWS Meridian, is burning for Concord space right now. If she makes it there we\'re all humped.\n\nWe need to board her and wipe that data before she gets there. No credits for this one -- you\'re doing it to keep yourself out of a Concord cell as much as anything.\n\nShe was spotted at grid ' .. JOBS.gridRef(_MX, _MY) .. ', headed toward Concord Station Arbiter. Move fast."')
                addCommsReply("We\'re on it.", function(s4, t4)
                    RT.flag("rezkov_m3_accepted", true)
                    RT.shipLog("[Rezkov Arc] M3: Intercept CWS Meridian. Last spotted at grid " .. JOBS.gridRef(_MX, _MY) .. ", burning for the Arbiter Line. Disable and board before she gets there.", "#A0C0FF")
                    RT.setObjective("Disable and board CWS Meridian", true)
                    setCommsMessage('"Grid ' .. JOBS.gridRef(_MX, _MY) .. ', headed for Concord Station Arbiter. Move fast. She\'s burning hard."')
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
            setCommsMessage('"She\'s still running. Last grid ' .. JOBS.gridRef(_MX, _MY) .. ', headed for Concord Station Arbiter. You need to move."')
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

    -- M3 report: tell Thresh the Meridian data was wiped
    if phase == "m3_deliver" and RT.flag("rezkov_m3_data") and not RT.flag("rezkov_arc_done") then
        addCommsReply("Thresh -- the Meridian data is wiped.", function(s2, t2)
            RT.addReputation("Independent", 200, "Rezkov Arc: reported Meridian data wipe to Thresh")
            RT.shipLog("[Rezkov Arc] Mission complete.", "#80FF80")
            RT.flag("rezkov_arc_done", "data_delivered")
            MISSIONS.phase("rezkov", "done")
            setCommsMessage('"We barely got out of that. Concord space is going to be tough to navigate for a while. I\'m going to lay low and I suggest you do the same. But you\'ve proved yourself, more work is headed your way. Fly safe Magpie."')
        end)
        return
    end
end


-- ── Resolve and cancel ────────────────────────────────────────────────────

function M.resolve(st)
    RT.shipLog("[Rezkov Arc] Arc complete. Outcome: " .. tostring(RT.flag("rezkov_arc_done")), "#80FF80")
    globalMessage("Rezkov Arc complete.", 8)
    -- Despawn Meridian 90s after arc ends (she may still be flying away on concord_won path)
    RT.after(90, function()
        if RT.valid(st.meridian) then
            RT.cancelKillTracking(st.meridian)
            st.meridian:setCanBeDestroyed(true)
            st.meridian:destroy()
            st.meridian = nil
        end
    end, "rezkov_meridian_despawn")
end

function M.on_cancel(st)
    _despawnWaypoint(st)
    if RT.valid(st.meridian) then
        RT.cancelKillTracking(st.meridian)
        st.meridian:setCanBeDestroyed(true)
        st.meridian:destroy()
        st.meridian = nil
        RT.named["CWS Meridian"] = nil
    end
    RUMORS.removeCategory("REZKOV_HOOK")
end

-- ── GM actions ────────────────────────────────────────────────────────────

local function _gmStateLabel()
    local phase = MISSIONS._cur_phase["rezkov"]
    if not phase or phase == "init" then
        return RT.flag("rezkov_declined") and "Inactive (declined)" or "Inactive"
    elseif phase == "hook" then
        local d = RT.flag("rezkov_declined")
        if d == "gm_inactivated" then return "Inactive (gm_inactivated)"
        elseif d then                  return "Inactive (declined)"
        end
        return "Rumors"
    elseif phase == "m1_navigate"                          then return "Meeting"
    elseif phase == "m2_active" or phase == "m2_deliver"   then return "Hacking"
    elseif phase == "m3_active"                             then return "Intercept"
    elseif phase == "m3_deliver"                            then return "Data Run"
    elseif phase == "done" then
        return "Complete (" .. tostring(RT.flag("rezkov_arc_done")) .. ")"
    end
    return "Unknown (" .. tostring(phase) .. ")"
end

M.gm_state_fn = _gmStateLabel

local function _gmClearFlags(st)
    _despawnWaypoint(st)
    if RT.valid(st.meridian) then
        RT.cancelKillTracking(st.meridian)
        st.meridian:setCanBeDestroyed(true)
        st.meridian:destroy()
        RT.named["CWS Meridian"] = nil
    end
    st.meridian    = nil
    st.hack_done   = false
    st.galen       = nil
    st.m3_disabled = false
    st.m3_boarded  = false
    for _, k in ipairs({"hook","declined","m1_done","m2_done",
                         "m3_accepted","m3_data","arc_done"}) do
        RT.clearFlag("rezkov_" .. k)
    end
    RT.clearFlag("kael_alive")
    RUMORS.removeCategory("REZKOV_HOOK")
end

M.gm_actions = {
    -- ── Info ──────────────────────────────────────────────────────────────
    {label = function(st) return "State: " .. _gmStateLabel():match("^%S+") end, done_ok = true, fn = function(st) end},
    -- ── Skip ──────────────────────────────────────────────────────────────
    {label = "→ Inactive", fn = function(st)
        _gmClearFlags(st)
        RT.flag("rezkov_declined", "gm_inactivated")
        MISSIONS.phase("rezkov", "hook")
        globalMessage("[GM] Rezkov Arc: suppressed. Will not trigger even if criteria are met.", 4)
    end},
    {label = "→ Rumors", fn = function(st)
        _gmClearFlags(st)
        MISSIONS.phase("rezkov", "hook")
        globalMessage("[GM] Rezkov Arc: → Rumors.", 4)
    end},
    {label = "→ Meeting", fn = function(st)
        _gmClearFlags(st)
        RT.flag("rezkov_hook", true)
        MISSIONS.phase("rezkov", "m1_navigate")
        globalMessage("[GM] Rezkov Arc: → Meeting.", 4)
    end},
    {label = "→ Hacking", fn = function(st)
        _gmClearFlags(st)
        RT.flag("rezkov_hook", true)
        RT.flag("rezkov_m1_done", true)
        MISSIONS.phase("rezkov", "m2_active")
        globalMessage("[GM] Rezkov Arc: → Hacking.", 4)
    end},
    {label = "→ Intercept", fn = function(st)
        _gmClearFlags(st)
        RT.flag("rezkov_hook", true)
        RT.flag("rezkov_m1_done", true)
        RT.flag("rezkov_m2_done", true)
        RT.flag("rezkov_m3_accepted", true)
        MISSIONS.phase("rezkov", "m3_active")
        globalMessage("[GM] Rezkov Arc: → Intercept.", 4)
    end},
    {label = "→ Complete", fn = function(st)
        _gmClearFlags(st)
        RT.flag("rezkov_arc_done", "gm_skip")
        MISSIONS.phase("rezkov", "done")
        globalMessage("[GM] Rezkov Arc: → Complete.", 4)
    end},
    {label = "Restart arc", phases = {"done"}, fn = function(_)
        local cur = MISSIONS._state["rezkov"]
        if cur then _gmClearFlags(cur) end
        MISSIONS._status["rezkov"] = "inactive"  -- guarantee start() proceeds
        MISSIONS.start("rezkov")
        globalMessage("[GM] Rezkov Arc: restarted.", 4)
    end},
    -- ── Phase helpers ─────────────────────────────────────────────────────
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
        if not _hook_registered then
            RT.addStationHook("Dustmote Salvage", _dustmoteHook)
            _hook_registered = true
        end

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

-- Lifecycle seeds (loaded while the arc waits for its trigger). Priority 3: vague,
-- never naming Rezkov or the contact. Mixed into the normal rumor rotation.
local _SEED_RUMORS = {
    "I heard there's a station that appears and disappears somewhere around Dustmote. Sensors catch it for a minute, then nothing.",
    "Dustmote's yard crews keep a ship's worth of berth empty. Nobody says who for.",
    "Somebody's been paying cash for sensor logs of the nebula past Dustmote. No questions, no receipts.",
    "A Concord officer went into the nebula off Dustmote last month and filed no flight plan. Nobody's said he came back.",
    "There's a salvage run out of Dustmote that pays three times the going rate. The catch is you never get told what you're carrying.",
    "Dustmote's got a regular who tips well and never gives a name. Keeps asking who's flying independent these days.",
    "If a stranger offers you a quiet job near Dustmote, know a good hacker first.",
    "There's a ship out by Dustmote that Concord pretends not to see. Everyone else sees it fine.",
}

function M.on_load(st)
    RUMORS.removeCategory("REZKOV_SEED")   -- idempotent
    for _, text in ipairs(_SEED_RUMORS) do
        RUMORS.add({text = text, priority = 3, category = "REZKOV_SEED"})
    end
end

function M.on_unload(st)
    RUMORS.removeCategory("REZKOV_SEED")
end

M.phases.hook = {
    no_skip = true,
    enter = function(st)
        if RT.flag("rezkov_declined") then return end
        RUMORS.add({text = "Heard there is a contact at Dustmote Salvage asking for independent crews. Someone with money, looking for a discreet run.", priority = 5, category = "REZKOV_HOOK"})
        RUMORS.add({text = "Word is someone has been spreading credits around Dustmote Salvage. Looking for a crew that knows how to keep quiet.", priority = 5, category = "REZKOV_HOOK"})
        RUMORS.add({text = "If you haven\'t been to Dustmote lately, there might be work. Someone there is looking for independent operators.", priority = 5, category = "REZKOV_HOOK"})
    end,
    exit = function(st)
        RUMORS.removeCategory("REZKOV_HOOK")
    end,
}

M.phases.m1_navigate = {
    no_skip = true,
    enter = function(st)
        RUMORS.removeCategory("REZKOV_HOOK")
        _spawnWaypoint(st)
        RT.shipLog("[Navigation] Bearing 15. Nebula field. Find the contact.", "#A0C0FF")
        RT.setObjective("Find the waypoint", true)
    end,
}

-- M2 cover jobs. Rezkov: "Pick up some jobs along the way to get you closer." While the
-- crew is on the Galen hack, the arc watches for them docking at one of the stations on the
-- way. When they do, an ordinary-looking delivery to Concord Waypoint Galen is added to THAT
-- station's board only (ensure = true: it is on the board when they open "Any work?"). It is
-- deliberately not special: no tag, normal rewards, nothing that says "story". Just a lucky
-- break. One per station per session.
local _COVER_JOBS = {
    ["Halcyon Rest"]            = {cargo = "ration crates",           reward = 100, brief = "Galen's galley keeps running short. Nobody wants the long haul out to the Arbiter Line, so the pay's decent."},
    ["Port Vesper"]             = {cargo = "replacement relay cores", reward =  85, brief = "Galen's comms array has been dropping packets for a month. Concord won't pay for the parts, a private buyer will."},
    ["Calder's Reach"]          = {cargo = "spare filter units",      reward =  75, brief = "Galen's air scrubbers are due. Small station, small order, steady money."},
    ["Concord Station Arbiter"] = {cargo = "sealed legal pouches",    reward =  65, brief = "Arbiter's clerks send paper to Galen by hand. They don't trust the net with it."},
}

local function _addCoverJob(cs)
    local j = _COVER_JOBS[cs]
    JOBS.inject({
        category = "REZKOV_COVER", priority = 3, ensure = true, origin = cs,
        record = function(station)
            return JOBS.build("delivery", {
                id = "rezkov_cover_" .. station, origin = station, dest = "Concord Waypoint Galen",
                cargo = j.cargo, reward = j.reward, brief = j.brief,
            })
        end,
    })
end

-- Called from m2_active.update: when a player ship is docked at a cover station that has not
-- had its job yet, add that station's job. getDockedWith() returns false when undocked.
local function _watchCoverDocks(st)
    st.cover_given = st.cover_given or {}
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then
            local d = p:getDockedWith()
            if d and RT.valid(d) then
                local cs = d:getCallSign()
                if _COVER_JOBS[cs] and not st.cover_given[cs] then
                    st.cover_given[cs] = true
                    _addCoverJob(cs)
                end
            end
        end
    end
end

M.phases.m2_active = {
    no_skip = true,
    exit = function(st)
        JOBS.removeCategory("REZKOV_COVER")
    end,
    enter = function(st)
        st.hack_done = false
        st.cover_given = {}
        JOBS.removeCategory("REZKOV_COVER")   -- idempotent for GM re-entry
        _spawnWaypoint(st)
        _spawnHackTerminal(st)
        RT.setObjective("Hack Waypoint Galen", true)
    end,

    update = function(st, delta, now)
        _checkHack(st, now)
        _watchCoverDocks(st)
    end,
}

M.phases.m2_deliver = {
    no_skip = true,
    -- The Dustmote hook handles the delivery interaction.
    -- This phase persists until the hook fires _despawnWaypoint and transitions to m3_active.
}

M.phases.m3_active = {
    no_skip = true,
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
            RT.shipLog("[Rezkov Arc] CWS Meridian destroyed. All data lost.", "#FF8080")
            RT.flag("kael_alive", false)
            RT.flag("rezkov_arc_done", "meridian_destroyed")
            MISSIONS.phase("rezkov", "done")
            return
        end

        -- Meridian reached Concord Station Arbiter — data delivered to Concord
        if RT.valid(st.meridian) and not st.m3_disabled then
            local mx, my = st.meridian:getPosition()
            local dx, dy = mx - (-21000), my - (-27000)
            if dx * dx + dy * dy < 10000 * 10000 then
                RT.addReputation("Concord", -1000, "Rezkov Arc: Concord investigation data reached Concord space")
                RT.addReputation("Independent", -500, "Rezkov Arc: Concord investigation completed, Rezkov network compromised")
                RT.shipLog("[Rezkov Arc] CWS Meridian reached the Arbiter Line. Data delivered to Concord.", "#FF8080")
                RT.flag("kael_alive", true)
                RT.flag("rezkov_arc_done", "meridian_escaped")
                MISSIONS.phase("rezkov", "done")
                return
            end
        end

        if not RT.flag("rezkov_m3_accepted") then return end

        -- Switch Meridian to hostile faction when player closes to weapons range (~5U).
        -- While Concord she is neutral and ignores all traffic; Concord Hostile makes her targetable.
        if not st.m3_hostile and not st.m3_disabled and RT.valid(st.meridian) then
            local mx, my = st.meridian:getPosition()
            for _, p in ipairs(RT.players) do
                if RT.valid(p) then
                    local px, py = p:getPosition()
                    local dx, dy = px - mx, py - my
                    if dx * dx + dy * dy < 5000 * 5000 then
                        st.m3_hostile = true
                        st.meridian:setFaction("Concord Hostile")
                        st.meridian:setCommsScript(""):setCommsFunction(_safeComms(function(src, tgt)
                            setCommsMessage('"CWS Meridian. We have your ship on record — registration, manifests, comms intercepts going back three months. Stand down and let us proceed.\n\nCooperate now and the Concord will remember that when it matters. Fight us and we file everything. Let\'s make a deal before this gets worse for everyone."')
                            addCommsReply("Not happening.", function()
                                setCommsMessage('"Your choice. The charges will be waiting when you dock anywhere in Concord space."')
                            end)
                        end))
                        log("[RZKOV] Meridian switched to Concord Hostile — player within 5U")
                        break
                    end
                end
            end
        end

        _checkMeridianDisabled(st)

        if st.m3_disabled and not st.m3_boarded and RT.valid(st.meridian) then
            for _, p in ipairs(RT.players) do
                if RT.valid(p) and p:isDocked(st.meridian) then
                    log(string.format("[RZKOV] docking detected: player=%s — calling _setupKaelComms", p:getCallSign()))
                    _setupKaelComms(st)
                    break
                end
            end
        end
    end,
}

M.phases.m3_deliver = {
    no_skip = true,
    -- Dustmote hook handles the data delivery interaction.
}

MISSIONS.register(M)
