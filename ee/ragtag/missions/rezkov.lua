-- ee/ragtag/missions/rezkov.lua
-- The Rezkov Arc: five missions for the sandbox campaign.
--
-- Trigger: Independent rep >= +500 AND upgrade investment >= 600cr AND Concord rep >= 0 on first contact
-- Structure: hook -> m1_navigate -> m2_active -> m2_deliver -> m3_active -> m4_active -> m5_active -> done
--
-- RT.flag keys used (prefix "rezkov_"):
--   hook              rumor phase active
--   declined          player declined The Fixer (arc ends permanently)
--   m1_done           player met Rezkov and accepted M2
--   m2_done           hack + data delivery complete
--   m3_accepted       The Mule delivery accepted
--   m3_cargo          cargo picked up at Hob's Landing
--   m3_done           The Mule delivery complete
--   m4_accepted       Clean Sweep drone destroy accepted
--   m4_done           drone destroyed
--   m5_accepted       The Reckoning boarding accepted
--   arc_done          all five missions complete (value = outcome string)

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
    "m3_active", "m4_active", "m5_active",
}

function M.init_state()
    return {
        waypoint    = nil,   -- Rezkov's Waypoint entity
        nebulas     = {},    -- nebula cluster entities
        hack_target = nil,   -- CpuShip terminal near Waypoint Galen (atmosphere/cleanup only)
        galen       = nil,   -- Waypoint Galen SpaceStation (actual hack detection target)
        hack_done   = false,
        drone       = nil,   -- M4 monitoring drone
        meridian    = nil,   -- M5 CWS Meridian
        m5_disabled = false,
        m5_boarded  = false,
        _last_jam   = 0,
    }
end

-- ── Coordinates ─────────────────────────────────────────────────────────────

-- Rezkov's Waypoint: between Dustmote (104,-36) and Boneyard (36,-96)
local _RWX = 115000  -- verse ~(115, -72)
local _RWY = -72000

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
local _TERMINAL_X = -72000
local _TERMINAL_Y = -54000

-- ── Spawn helpers ────────────────────────────────────────────────────────────

local function _spawnWaypoint(st)
    if RT.valid(st.waypoint) then return end

    for _, pos in ipairs(_NEBULA_POS) do
        local n = Nebula():setPosition(pos[1], pos[2])
        st.nebulas[#st.nebulas + 1] = n
    end

    local wp = CpuShip():setTemplate("Defense platform"):setFaction("Unknown")
    wp:setCallSign("Rezkov's Waypoint")
    wp:setPosition(_RWX, _RWY)
    wp:setCanBeDestroyed(false)
    wp:orderIdle()
    wp:setCommsFunction(function(src, tgt)
        local phase = MISSIONS._cur_phase["rezkov"]
        local art = MISSIONS._state["rezkov"]

        -- M1: initial meeting
        if phase == "m1_navigate" and not RT.flag("rezkov_m1_done") then
            if not src:isDocked(tgt) then
                setCommsMessage('"Approach and dock. We do not do business at a distance."')
                addCommsReply("Back", function() end)
                return
            end
            setCommsMessage('"You found it.\n\nI am Orlan Rezkov. Reputation got you to my door. What you do after the door opens -- that is what matters.\n\nI need something from a Concord station. Not a fleet base, nothing dramatic. Concord Waypoint Galen on the Arbiter Line. I want the traffic log -- ninety days of docking records. I need to know if someone in my organization is talking.\n\nI will tell you this: your name does not raise flags with their patrols. Keep it that way until the job is finished."')
            addCommsReply("We're up for the challenge.", function(s2, t2)
                local concord_rep = RT.getReputation("Concord") or 0
                if concord_rep < 0 then
                    setCommsMessage('"Not yet. The patrols are watching you. When your name stops raising flags, come back."')
                    addCommsReply("Understood.", function(s3, t3) end)
                    return
                end
                RT.shipLog("[Rezkov] Job accepted: Concord Waypoint Galen (-75, -52), Arbiter Line. Hack the station's front shield generator to 100%. Retrieve 90-day traffic log. Deliver storage card to Thresh at Dustmote Salvage. 600cr.", "#A0C0FF")
                RT.setObjective("Hack front shield generator at Waypoint Galen to 100%", true)
                RT.flag("rezkov_m1_done", true)
                MISSIONS.phase("rezkov", "m2_active")
                setCommsMessage('"Waypoint Galen. Small Concord checkpoint, Arbiter Line. Dock, breach their data relay -- the terminal is docked to the station exterior. Get me ninety days of traffic records on this storage card.\n\nThen bring the card to my contact at Dustmote Salvage. Ask for Thresh.\n\n600 credits on delivery. No time limit. Take your other work -- just do not forget this one."')
                addCommsReply("Understood.", function() end)
            end)
            addCommsReply("Not our kind of work.", function(s2, t2)
                setCommsMessage('"The door stays open. Come back when you change your mind."')
                addCommsReply("Back", function() end)
            end)
            return
        end

        -- M2: Rezkov remembers them
        if RT.flag("rezkov_m1_done") then
            local phase2 = MISSIONS._cur_phase["rezkov"]
            if phase2 == "m2_active" then
                setCommsMessage('"Waypoint Galen is not far. I am still waiting."')
            elseif phase2 == "m2_deliver" then
                setCommsMessage('"The job is done. Take the card to Thresh at Dustmote Salvage."')
            else
                setCommsMessage('"I will have more work. Keep flying."')
            end
            addCommsReply("Understood.", function() end)
            return
        end

        setCommsMessage("[Rezkov's Waypoint] No response on this frequency.")
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
    RT.named["Rezkov's Waypoint"] = nil
end

local function _spawnHackTerminal(st)
    if RT.valid(st.hack_target) then return end
    local s = CpuShip():setTemplate("ANT 615"):setFaction("Concord")
    s:setCallSign("Concord Data Terminal"):setTypeName("Station Relay")
    s:setPosition(_TERMINAL_X, _TERMINAL_Y)
    s:orderIdle():setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    s:setHullMax(50):setHull(50):setShieldsMax(0):setShields(0)
    s:setCanBeDestroyed(false)
    s:setSystemHealth("reactor", 1.0)
    s:setSystemHackedLevel("reactor", 0.0)
    s:setBeamWeapon(0, 120,   0, 4000, 6, 4)
    s:setBeamWeapon(1, 120,  90, 4000, 6, 4)
    s:setBeamWeapon(2, 120, 180, 4000, 6, 4)
    s:setBeamWeapon(3, 120, 270, 4000, 6, 4)
    s:setCommsFunction(function(src, tgt)
        setCommsMessage("[Concord Data Terminal] Automated relay. Encrypted. No authorized access.")
    end)
    RT.named["Concord Data Terminal"] = s
    st.hack_target = s

    -- Find Waypoint Galen (the actual station the player docks at and hacks).
    for _, obj in ipairs(getObjectsInRadius(-75000, -52000, 3000)) do
        if isObjectType(obj, "SpaceStation") then
            st.galen = obj
            break
        end
    end

    RT.shipLog("[Scan] Concord Data Terminal relay detected on Waypoint Galen exterior. Hack the station's front shield generator to 100% to access it.", "#A0C0FF")
end

local function _checkHack(st, now)
    if st.hack_done then return end
    local target = st.galen or st.hack_target
    if not RT.valid(target) then return end

    local ok, lvl = pcall(function() return target:getSystemHackedLevel("frontshield") end)
    local hack_lvl = (ok and lvl) and lvl or 0

    if hack_lvl >= 1.0 then
        st.hack_done = true
        if RT.valid(st.hack_target) then st.hack_target:setCanBeDestroyed(true) end
        RT.shipLog("[Hack] Rogue AI successfully installed in the Concord accounting systems.", "#80FF80")
        RT.after(4, function()
            RT.shipLog("[Hack] Station traffic downloaded to the storage card.", "#80FF80")
            RT.shipLog("[Mission] Deliver the storage card to Thresh at Dustmote Salvage.", "#A0C0FF")
            RT.setObjective("Deliver storage card to Thresh at Dustmote Salvage", true)
            MISSIONS.phase("rezkov", "m2_deliver")
        end, "rezkov_hack_msg2")
    end
end

local function _spawnDrone(st)
    if RT.valid(st.drone) then return end
    -- Bearing 040 from Dustmote (104, -36) verse = world (104000, -36000), 8U out
    local dx = 104000 + 8000 * math.sin(math.rad(40))
    local dy = -36000 + 8000 * math.cos(math.rad(40))
    local drone = CpuShip():setTemplate("ANT 615"):setFaction("Concord")
    drone:setCallSign("Concord Monitor 7"):setTypeName("Monitoring Drone")
    drone:setPosition(dx, dy)
    drone:orderIdle():setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    drone:setHullMax(100):setHull(100):setShieldsMax(0):setShields(0)
    drone:setWeaponTubeCount(0)
    drone:setBeamWeapon(0, 0, 0, 0, 0, 0)
    drone:setCommsFunction(function(src, tgt)
        setCommsMessage("[Concord Monitor 7] Automated surveillance platform. No comms interface.")
    end)
    RT.named["Concord Monitor 7"] = drone
    st.drone = drone
    RT.shipLog("[Scan] Concord Monitor 7 detected in Dustmote salvage field. Bearing 040, 8 units.", "#FFAA00")
end

local function _spawnMeridian(st)
    if RT.valid(st.meridian) then return end
    -- 15U from Dustmote at bearing 220 (SW)
    local mx = 104000 + 15000 * math.sin(math.rad(220))
    local my = -36000 + 15000 * math.cos(math.rad(220))
    local meridian = CpuShip():setTemplate("Concord Enforcer"):setFaction("Concord")
    meridian:setCallSign("CWS Meridian"):setTypeName("CpuShip")
    meridian:setPosition(mx, my)
    meridian:orderFlyTowards(mx + 20000, my + 5000)
    RT.register(meridian)
    st.meridian = meridian
    RT.shipLog("[Intel] CWS Meridian is in the sector, running a patrol loop near Dustmote. Standard Concord investigator configuration.", "#FFAA00")
end

local function _checkMeridianDisabled(st)
    if not RT.valid(st.meridian) or st.m5_disabled then return end
    local ok1, hull = pcall(function() return st.meridian:getHull() end)
    local ok2, hmax = pcall(function() return st.meridian:getHullMax() end)
    if ok1 and ok2 and hmax > 0 and hull / hmax < 0.25 then
        st.m5_disabled = true
        st.meridian:setCanBeDestroyed(false)
        st.meridian:orderIdle()
        st.meridian:setImpulseMaxSpeed(5)
        RT.shipLog("[CWS Meridian] Ship disabled. Close to 0.25U and hail to board.", "#FFCC80")
        st.meridian:setCommsFunction(function(src, tgt)
            local tx, ty = tgt:getPosition()
            local sx, sy = src:getPosition()
            local d = math.sqrt((tx-sx)^2 + (ty-sy)^2)
            if d > 250 then
                setCommsMessage(string.format(
                    '"CWS Meridian -- standing by. Close to %.2fU to 0.25U before we talk."',
                    d / 1000))
            elseif not st.m5_boarded then
                st.m5_boarded = true
                setCommsMessage('"Commander Vael, CWS Meridian. You have my ship disabled. I assume this is not a coincidence.\n\nI know what you were hired to do. And I know who hired you. I have been investigating Rezkov\'s network for eight months.\n\nI am going to give you a choice: wipe my investigation files -- Rezkov\'s people go free, and so does the person in his organization who has been feeding me information -- or bring me to whoever sent you, and I will make a deal. The source stays protected either way.\n\nWhat is it going to be?"')
                addCommsReply("Wipe the files.", function(s2, t2)
                    setCommsMessage('"Understood. Doing this under duress is noted in my personal log. The investigation is dead.\n\nGet off my ship."')
                    addCommsReply("Done.", function(s3, t3)
                        RT.addCredits(600, "Rezkov Arc M5: investigation wiped")
                        RT.addReputation("Concord", -30, "Rezkov Arc: boarded Concord vessel, wiped investigation")
                        RT.shipLog("[Rezkov Arc] Done. Investigation wiped. The source inside Rezkov's network is still at large. 600cr. Concord -30.", "#80FF80")
                        RT.flag("rezkov_arc_done", "files_wiped")
                        RT.note("Boarded CWS Meridian (Cmdr Vael), wiped Concord investigation into Rezkov. Unknown informant protected.")
                        if RT.valid(st.meridian) then
                            st.meridian:setFaction("Independent")
                            st.meridian:orderIdle()
                        end
                        MISSIONS.phase("rezkov", "done")
                    end)
                end)
                addCommsReply("We will bring you to Rezkov.", function(s2, t2)
                    setCommsMessage('"Pragmatic. I can work with pragmatic.\n\nI will be cooperative. Tell him I want to negotiate."')
                    addCommsReply("We will get you there.", function(s3, t3)
                        RT.addCredits(600, "Rezkov Arc M5: investigator delivered")
                        RT.addReputation("Concord", -50, "Rezkov Arc: delivered Concord investigator to crime lord")
                        RT.shipLog("[Rezkov Arc] Done. Vael in transit to Rezkov's people. 600cr. Concord -50. The source inside Rezkov's network is still at large.", "#80FF80")
                        RT.flag("rezkov_arc_done", "investigator_delivered")
                        RT.note("Delivered CWS Meridian commander Vael to Rezkov's contact. Unknown informant still active inside Rezkov's organization.")
                        if RT.valid(st.meridian) then
                            local ok, _ = pcall(function() st.meridian:orderFollowTarget(RT.player) end)
                        end
                        MISSIONS.phase("rezkov", "done")
                    end)
                end)
            end
        end)
    end
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
                setCommsMessage('"The associate likes to meet people in person. Doesn\'t do business through go-betweens. If you are interested, he has arranged a meeting.\n\nHead bearing 20 from here until you hit a nebula cluster. What you are looking for is near there.\n\nMind what you say when you get there. He remembers everything."')
                addCommsReply("We\'ll head out.", function(s4, t4)
                    setCommsMessage('"Good. He will be expecting you."\n\nThresh turns back to work.')
                    addCommsReply("Understood.", function() end)
                    RT.shipLog("[Navigation] Bearing 20. Find the nebula cluster. The Waypoint is inside.", "#A0C0FF")
                    RT.setObjective("Follow the directions to the meeting point", true)
                    RT.flag("rezkov_hook", true)
                    MISSIONS.phase("rezkov", "m1_navigate")
                end)
                addCommsReply("Not right now.", function(s4, t4)
                    setCommsMessage('"The offer stays open. Thresh is usually around."')
                    addCommsReply("Back", function() end)
                end)
            end)
            addCommsReply("Not interested.", function(s3, t3)
                setCommsMessage('"Suit yourself."')
                addCommsReply("Back", function(s4, t4)
                    RT.flag("rezkov_declined", true)
                end)
            end)
        end)
        return
    end

    -- M2 delivery: bring data card to Thresh
    if phase == "m2_deliver" then
        addCommsReply("Delivery for Thresh.", function(s2, t2)
            setCommsMessage('"Thresh takes the card and disappears into the back.\n\n...\n\n"Good work. The boss will reach out when he has work. Keep flying."\n\n600 credits transferred."')
            addCommsReply("Understood.", function(s3, t3)
                setCommsMessage("Credits cleared. Thresh nods and walks away.")
                RT.addCredits(600, "Rezkov Arc M2: data delivery")
                RT.shipLog("[Rezkov Arc] M2 complete. 600cr received. Rezkov's Waypoint has gone dark.", "#80FF80")
                RT.flag("rezkov_m2_done", true)
                if st then
                    if RT.valid(st.hack_target) then
                        st.hack_target:setCanBeDestroyed(true)
                        st.hack_target:destroy()
                        st.hack_target = nil
                        RT.named["Concord Data Terminal"] = nil
                    end
                    _despawnWaypoint(st)
                end
                MISSIONS.phase("rezkov", "m3_active")
            end)
        end)
        return
    end

    -- M3 offer: The Mule delivery job
    if phase == "m3_active" and RT.flag("rezkov_m2_done") and not RT.flag("rezkov_m3_accepted") then
        addCommsReply("Thresh -- any word from Rezkov?", function(s2, t2)
            setCommsMessage('"The boss has another job. Simple freight run. Hob\'s Landing to Saint Brennan\'s Mission. Standard cargo -- medical supplies, aid equipment.\n\nNothing complicated. But he wants you on it personally.\n\n400 credits on delivery."')
            addCommsReply("We\'ll take it.", function(s3, t3)
                setCommsMessage('"Hob\'s Landing is expecting you. Pick up the consignment and get it to Saint Brennan\'s. Do not let anyone open the crates."')
                addCommsReply("Understood.", function(s4, t4)
                    setCommsMessage("Thresh disappears into the back.")
                    RT.shipLog("[Rezkov Arc] M3: Freight run, Hob's Landing to Saint Brennan's Mission. 400cr on delivery.", "#A0C0FF")
                    RT.setObjective("Pick up freight at Hob's Landing", true)
                    RT.flag("rezkov_m3_accepted", true)
                end)
            end)
            addCommsReply("Not right now.", function(s3, t3)
                setCommsMessage('"The offer stays open."')
                addCommsReply("Back", function() end)
            end)
        end)
        return
    end

    -- M4 offer: Clean Sweep
    if phase == "m4_active" and RT.flag("rezkov_m3_done") and not RT.flag("rezkov_m4_accepted") then
        addCommsReply("Thresh -- any word from Rezkov?", function(s2, t2)
            setCommsMessage('"Concord planted a monitoring drone in the salvage field. Bearing 040 from here, about 8 units out. Automated scanner -- been logging everything that comes through.\n\nHe wants it gone. 450 credits. Concord will notice when it goes dark, so get clear before they come looking."')
            addCommsReply("We\'ll handle it.", function(s3, t3)
                setCommsMessage('"Bearing 040, 8 units from here. Can\'t miss it."')
                addCommsReply("On it.", function(s4, t4)
                    setCommsMessage("Thresh nods. The comms close.")
                    RT.shipLog("[Rezkov Arc] M4: Destroy Concord Monitor 7, bearing 040, 8U from Dustmote. 450cr.", "#A0C0FF")
                    RT.setObjective("Destroy Concord Monitor 7 near Dustmote", true)
                    RT.flag("rezkov_m4_accepted", true)
                    if st then _spawnDrone(st) end
                end)
            end)
            addCommsReply("Not right now.", function(s3, t3)
                setCommsMessage('"The offer stays open."')
                addCommsReply("Back", function() end)
            end)
        end)
        return
    end

    -- M5 offer: The Reckoning
    if phase == "m5_active" and RT.flag("rezkov_m4_done") and not RT.flag("rezkov_m5_accepted") then
        addCommsReply("Thresh -- any word from Rezkov?", function(s2, t2)
            setCommsMessage('"There is a Concord investigator ship in the sector. CWS Meridian. She has been asking questions about operations in Dustmote.\n\nRezkov wants her boarded. Disable the ship, board it. Then: wipe her investigation files, or bring her back as a passenger. The boss has a use for cooperative Concord officers.\n\n600 credits. The choice is yours when you are aboard."')
            addCommsReply("We\'ll do it.", function(s3, t3)
                setCommsMessage('"The Meridian is running a loop through the Dustmote shipping lane. Find her, disable her, board her. No killing."')
                addCommsReply("Understood.", function(s4, t4)
                    setCommsMessage("Thresh nods. The comms close.")
                    RT.shipLog("[Rezkov Arc] M5: Board CWS Meridian near Dustmote. Disable, board, choose: wipe files or take passenger. 600cr.", "#A0C0FF")
                    RT.setObjective("Find and disable CWS Meridian near Dustmote", true)
                    RT.flag("rezkov_m5_accepted", true)
                    if st then _spawnMeridian(st) end
                end)
            end)
            addCommsReply("Not right now.", function(s3, t3)
                setCommsMessage('"The offer stays open."')
                addCommsReply("Back", function() end)
            end)
        end)
        return
    end
end

local function _hobsLandingHook(src, tgt, info)
    if not src:isDocked(tgt) then return end
    local phase = MISSIONS._cur_phase["rezkov"]
    if phase ~= "m3_active" then return end
    if not RT.flag("rezkov_m3_accepted") or RT.flag("rezkov_m3_cargo") then return end

    addCommsReply("Pick up a consignment for Thresh.", function(s2, t2)
        setCommsMessage('"Right, we have it set aside. Twelve crates, sealed. Medical supplies and aid equipment for Saint Brennan\'s Mission. Consignment tag is on the manifest.\n\nHave a smooth run."')
        addCommsReply("Loading now.", function(s3, t3)
            setCommsMessage("The dockhand waves you toward the loading bay.")
            RT.shipLog("[Rezkov Arc] Consignment loaded. Destination: Saint Brennan's Mission.", "#A0C0FF")
            RT.setObjective("Deliver consignment to Saint Brennan's Mission", true)
            RT.flag("rezkov_m3_cargo", true)
        end)
    end)
end

local function _saintBrennansHook(src, tgt, info)
    if not src:isDocked(tgt) then return end
    local phase = MISSIONS._cur_phase["rezkov"]
    if phase ~= "m3_active" then return end
    if not RT.flag("rezkov_m3_cargo") or RT.flag("rezkov_m3_done") then return end

    addCommsReply("Delivery for the Mission -- freight from Hob's Landing.", function(s2, t2)
        setCommsMessage('"We have been waiting on these. Set them down in Bay 3.\n\nThank you for bringing this out here. Saint Brennan\'s depends on runs like this."')
        addCommsReply("Cargo is unloaded.", function(s3, t3)
            setCommsMessage("The Mission worker thanks you and signs off the manifest.")
            RT.addCredits(400, "Rezkov Arc M3: freight delivered")
            RT.shipLog("[Rezkov Arc] M3 complete. Consignment delivered. 400cr.", "#80FF80")
            RT.flag("rezkov_m3_done", true)
            MISSIONS.phase("rezkov", "m4_active")
        end)
    end)
end

-- ── Resolve and cancel ────────────────────────────────────────────────────

function M.resolve(st)
    RT.shipLog("[Rezkov Arc] Arc complete. Outcome: " .. tostring(RT.flag("rezkov_arc_done")), "#80FF80")
    globalMessage("Rezkov Arc complete.", 8)
end

function M.on_cancel(st)
    _despawnWaypoint(st)
    if RT.valid(st.hack_target) then
        st.hack_target:setCanBeDestroyed(true)
        st.hack_target:destroy()
        st.hack_target = nil
        RT.named["Concord Data Terminal"] = nil
    end
    if RT.valid(st.drone) then
        st.drone:destroy()
        st.drone = nil
        RT.named["Concord Monitor 7"] = nil
    end
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
        MISSIONS.phase("rezkov", "m3_active")
        globalMessage("[GM] Rezkov Arc: skipped to M3 (mule).", 4)
    end},
    {label = "Complete hack", fn = function(st)
        if not st.hack_done then
            local target = st.galen or st.hack_target
            if RT.valid(target) then
                target:setSystemHackedLevel("frontshield", 0.9)
            end
        end
    end},
    {label = "Complete drone", fn = function(st)
        if RT.valid(st.drone) then
            st.drone:setCanBeDestroyed(true)
            st.drone:destroy()
            st.drone = nil
            RT.named["Concord Monitor 7"] = nil
        end
    end},
}

-- ── Phases ─────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        -- Register station hooks once per session (safe: each session starts fresh)
        RT.addStationHook("Dustmote Salvage",       _dustmoteHook)
        RT.addStationHook("Hob's Landing",          _hobsLandingHook)
        RT.addStationHook("Saint Brennan's Mission", _saintBrennansHook)

        -- Route to the appropriate phase based on saved flags
        if RT.flag("rezkov_m5_accepted") then
            MISSIONS.phase("rezkov", "m5_active")
        elseif RT.flag("rezkov_m4_done") then
            MISSIONS.phase("rezkov", "m5_active")
        elseif RT.flag("rezkov_m4_accepted") then
            MISSIONS.phase("rezkov", "m4_active")
        elseif RT.flag("rezkov_m3_done") then
            MISSIONS.phase("rezkov", "m4_active")
        elseif RT.flag("rezkov_m3_accepted") then
            MISSIONS.phase("rezkov", "m3_active")
        elseif RT.flag("rezkov_m2_done") then
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
        RT.shipLog("[Navigation] Bearing 20. Find the nebula cluster. The Waypoint is inside.", "#A0C0FF")
        RT.setObjective("Navigate to the meeting point", true)
    end,
}

M.phases.m2_active = {
    enter = function(st)
        st.hack_done = false
        _spawnWaypoint(st)
        _spawnHackTerminal(st)
        RT.setObjective("Hack front shield generator at Waypoint Galen to 100%", true)
    end,

    update = function(st, delta, now)
        _checkHack(st, now)

        -- Jam scan probes near terminal every 2s
        if now - st._last_jam > 2 then
            st._last_jam = now
            if RT.valid(st.hack_target) then
                local rx, ry = st.hack_target:getPosition()
                for _, obj in ipairs(getObjectsInRadius(rx, ry, 5000)) do
                    if RT.valid(obj) and isObjectType(obj, "ScanProbe") then
                        obj:destroy()
                    end
                end
            end
        end
    end,
}

M.phases.m2_deliver = {
    -- The Dustmote hook handles the delivery interaction.
    -- This phase persists until the hook fires _despawnWaypoint and transitions to m3_active.
}

M.phases.m3_active = {
    enter = function(st)
        if RT.flag("rezkov_m3_cargo") and not RT.flag("rezkov_m3_done") then
            RT.setObjective("Deliver consignment to Saint Brennan's Mission", true)
        elseif RT.flag("rezkov_m3_accepted") and not RT.flag("rezkov_m3_cargo") then
            RT.setObjective("Pick up freight at Hob's Landing", true)
        end
    end,
}

M.phases.m4_active = {
    enter = function(st)
        if RT.flag("rezkov_m4_accepted") and not RT.flag("rezkov_m4_done") then
            _spawnDrone(st)
            RT.setObjective("Destroy Concord Monitor 7 near Dustmote", true)
        end
    end,

    update = function(st, delta, now)
        if not RT.flag("rezkov_m4_accepted") or RT.flag("rezkov_m4_done") then return end
        if st.drone and not RT.valid(st.drone) then
            RT.addCredits(450, "Rezkov Arc M4: drone destroyed")
            RT.addReputation("Concord", -50, "Rezkov Arc: destroyed Concord monitoring drone")
            RT.shipLog("[Rezkov Arc] M4 complete. Concord Monitor 7 destroyed. 450cr. Concord -50. Get clear of Dustmote.", "#80FF80")
            RT.flag("rezkov_m4_done", true)
            st.drone = nil
            RT.named["Concord Monitor 7"] = nil
            MISSIONS.phase("rezkov", "m5_active")
        end
    end,
}

M.phases.m5_active = {
    enter = function(st)
        if RT.flag("rezkov_m5_accepted") and not RT.flag("rezkov_arc_done") then
            _spawnMeridian(st)
            RT.setObjective("Find and disable CWS Meridian near Dustmote", true)
        end
    end,

    update = function(st, delta, now)
        if not RT.flag("rezkov_m5_accepted") or RT.flag("rezkov_arc_done") then return end
        if st.meridian and not RT.valid(st.meridian) and not st.m5_disabled then
            -- Meridian was destroyed before boarding
            RT.shipLog("[Rezkov Arc] CWS Meridian destroyed. That was not what Rezkov wanted.", "#FF8080")
            RT.flag("rezkov_arc_done", "meridian_destroyed")
            MISSIONS.phase("rezkov", "done")
            return
        end
        _checkMeridianDisabled(st)
    end,
}

MISSIONS.register(M)
