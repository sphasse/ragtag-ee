-- ee/ragtag/missions/whistleblower.lua
-- The Whistleblower: hack a Concord docking terminal at Arbiter to expose
-- a corrupt customs inspector, then decide what to do with the evidence.
-- Phases: offer -> transit -> hacking -> extracted -> deliver -> done

local M = {}
M.id          = "whistleblower"
M.name        = "The Whistleblower"
M.repeatable  = false
M.locks_jobs  = false
M.auto_start  = false
M.start_phase = "offer"

-- Trigger: available after some early investment (crew has had a few sessions).
-- auto_start is false, so "triggered" only lights up the GM button.
M.triggers = {
    not_flagged  = {"whistleblower_complete"},
    upgrades_min = 100,
}

M.phase_order = {"offer", "transit", "hacking", "extracted", "deliver"}

function M.init_state()
    return {
        phase_entered  = 0,
        offer_hail_at  = nil,
        marta_cs       = nil,   -- Marta Yuen's ship callsign
        relay_cs       = nil,   -- post-hack relay burst for choice comms
        terminal_cs    = nil,   -- Arbiter Records Terminal
        hacked         = false,
        choice         = nil,   -- "merchant" | "concord" | "burned"
        _last_jam      = 0,
    }
end

-- Custom GM action: force hack threshold while in hacking phase.
M.gm_actions = {
    {label = "Force: hack complete", fn = function(st)
        local t = RT.find(st.terminal_cs or "")
        if RT.valid(t) then
            t:setSystemHackedLevel("reactor", 0.76)
            RT.shipLog("[GM] Arbiter terminal hack threshold forced.", "#FF4040")
        end
    end},
}

-- ── Beacon helpers (mirrors hacking job pattern) ──────────────────────────

local _SYSTEMS = {
    "reactor","beamweapons","missilesystem","maneuver","impulse",
    "warp","jumpdrive","frontshield","rearshield",
}

local function _spawnTerminal(st)
    local ax, ay = VERSE.at("Concord Station Arbiter", 8, -4)
    local t = CpuShip():setTemplate("ANT 615"):setFaction("Concord")
    t:setCallSign("Arbiter Records Terminal"):setTypeName("Data Terminal")
    t:setPosition(ax, ay)
    t:orderIdle():setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    t:setHullMax(50):setHull(50):setShieldsMax(0):setShields(0)
    t:setCanBeDestroyed(false)
    t:setSystemHealth("reactor", 1.0)
    t:setSystemHealth("beamweapons", 1.0)
    t:setBeamWeapon(0, 120,   0, 4000, 6, 4)
    t:setBeamWeapon(1, 120,  90, 4000, 6, 4)
    t:setBeamWeapon(2, 120, 180, 4000, 6, 4)
    t:setBeamWeapon(3, 120, 270, 4000, 6, 4)
    t:setSystemHackedLevel("reactor", 0.0)
    t:setCommsFunction(function(src, tgt)
        setCommsMessage("[Concord Secure Data Node] Unauthorized access detected. Alert transmitted.")
    end)
    RT.register(t)
    st.terminal_cs = t:getCallSign()
end

local function _checkHacked(st)
    local t = RT.find(st.terminal_cs or "")
    if not RT.valid(t) then return false end
    local max_hack = 0
    for _, sys in ipairs(_SYSTEMS) do
        local has = false
        local ok1 = pcall(function() has = t:hasSystem(sys) end)
        if ok1 and has then
            local ok2, lvl = pcall(function() return t:getSystemHackedLevel(sys) end)
            if ok2 and lvl and lvl > max_hack then max_hack = lvl end
        end
    end
    return max_hack >= 0.75
end

-- ── Resolve ────────────────────────────────────────────────────────────────

function M.resolve(st)
    local choice = st.choice or "burned"
    local reward = 0
    local msg, outcome

    if choice == "merchant" then
        reward  = 400
        outcome = "sold_merchant"
        msg     = "Marta Yuen has her evidence. Commander Rask will answer for what he took from Independent traders."
        RT.addReputation("Independent", 300, "Whistleblower: exposed corrupt Concord inspector through Border channels")
    elseif choice == "concord" then
        reward  = 600
        outcome = "sold_concord"
        msg     = "Concord Internal Affairs paid well. Rask will face an audit. The Border contact won't forget you chose the money."
        RT.addReputation("Concord", 150, "Whistleblower: evidence handed to Internal Affairs")
        RT.addReputation("Independent", -100, "Whistleblower: sold data to Concord over Border contact")
    else
        outcome = "burned"
        msg     = "The data is gone. Rask keeps his position and his operation. Some things stay buried."
        RT.flag("wb_burned_data", true)
    end

    if reward > 0 then
        RT.addCredits(reward, "The Whistleblower: " .. outcome)
    end

    local suffix = reward > 0 and (" +" .. reward .. " cr.") or ""
    RT.shipLog("[The Whistleblower] " .. msg .. suffix, "#80FF80")
    RT.flag("whistleblower_complete", outcome)
    RT.setObjective("The Whistleblower: complete", true)
    DIR.emit("whistleblower_complete", {outcome = outcome, choice = choice}, "medium")

    local t = RT.find(st.terminal_cs or "")
    if RT.valid(t) then t:setCanBeDestroyed(true) end

    globalMessage("The Whistleblower -- arc complete.", 10)
end

-- ── on_cancel ──────────────────────────────────────────────────────────────

function M.on_cancel(st)
    for _, cs in ipairs({st.marta_cs, st.relay_cs}) do
        local e = RT.find(cs or "")
        if RT.valid(e) then e:destroy() end
    end
    local t = RT.find(st.terminal_cs or "")
    if RT.valid(t) then
        t:setCanBeDestroyed(true)
        t:destroy()
    end
end

-- ── Phases ─────────────────────────────────────────────────────────────────

M.phases = {}

-- OFFER: Marta Yuen's freighter idles near Port Vesper and hails the crew.
M.phases.offer = {
    enter = function(st)
        st.phase_entered = getScenarioTime()

        local vx, vy = VERSE.at("Port Vesper", 3, 2)
        local marta = CpuShip():setTemplate("Flavia"):setFaction("Independent")
        marta:setPosition(vx, vy)
        marta:orderIdle()
        marta:setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
        marta:setWeaponTubeCount(0):setCanBeDestroyed(false)
        marta:setCallSign("Yuen's Freight")
        RT.register(marta)
        st.marta_cs = marta:getCallSign()

        marta:setCommsFunction(function(src, tgt)
            setCommsMessage('"Marta Yuen, out of Tamsin Hollow. Concord customs at Arbiter has been seizing Independent cargo -- off the books, no receipts, no appeal. Three of my shipments. I want the transaction logs pulled from their docking terminal. 400 credits if you get them to me."')
            addCommsReply("Tell us more.", function(s2, t2)
                setCommsMessage('"Commander Rask runs customs at Arbiter Station. He flags cargo as contraband, confiscates it, and sells it on to his own contacts. The paper trail is in their data terminal -- externally mounted on the dock ring. You\'d need to hack it. Bring the logs to Tamsin Hollow when you have them."')
                addCommsReply("We'll take the job.", function(s3, t3)
                    setCommsMessage('"Good. Arbiter sits in the Arbiter Line -- Concord territory. They run patrols. Watch yourself."')
                    addCommsReply("Understood. We're on it.", function(s4, t4)
                        RT.stationComms(s4, t4)
                        local m2 = RT.find(st.marta_cs or "")
                        if RT.valid(m2) then m2:destroy() end
                        MISSIONS.phase("whistleblower", "transit")
                    end)
                end)
                addCommsReply("Not our kind of work.", function(s3, t3)
                    setCommsMessage('"Alright. If you change your mind, I\'ll be at Port Vesper for another hour."')
                    addCommsReply("Back", function(s4, t4) RT.stationComms(s4, t4) end)
                end)
            end)
            addCommsReply("Not our business.", function(s2, t2)
                setCommsMessage('"Everyone says that."')
                addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
            end)
        end)

        st.offer_hail_at = getScenarioTime() + 3
        globalMessage("Whistleblower arc starting -- incoming hail in 3 seconds.", 3)
    end,

    update = function(st, delta, now)
        if st.offer_hail_at and now >= st.offer_hail_at then
            st.offer_hail_at = nil
            local marta = RT.find(st.marta_cs or "")
            if RT.valid(marta) then
                RT.hail(marta, "Looking for a discreet crew. Open comms when you're clear.", "Marta Yuen")
            end
        end
    end,
}

-- TRANSIT: Crew heads toward Arbiter; terminal spawns when within 30U.
M.phases.transit = {
    enter = function(st)
        st.phase_entered = getScenarioTime()
        local arbiter = RT.find("Concord Station Arbiter")
        if RT.valid(arbiter) then
            local ax, ay = arbiter:getPosition()
            RT.shipLog("[Whistleblower] Concord Station Arbiter at grid " ..
                JOBS.gridRef(ax, ay) ..
                ". Their docking records terminal is on the outer hull. Concord patrols the Arbiter Line -- expect shake-downs.", "#A0C0FF")
        end
        RT.setObjective("Reach Concord Station Arbiter", true)
    end,

    update = function(st, delta, now)
        if st.terminal_cs then return end
        local arbiter = RT.find("Concord Station Arbiter")
        if not RT.valid(arbiter) then return end
        local ax, ay = arbiter:getPosition()
        local ref = RT.nearestPlayer(ax, ay)
        if not ref or not RT.valid(ref) then return end
        local px, py = ref:getPosition()
        local dx, dy = px - ax, py - ay
        if dx * dx + dy * dy < 30000 * 30000 then
            _spawnTerminal(st)
            local tx, ty = VERSE.at("Concord Station Arbiter", 8, -4)
            RT.shipLog("[Whistleblower] Data terminal located: " .. (st.terminal_cs or "unknown") ..
                " at grid " .. JOBS.gridRef(tx, ty) ..
                ". Hack any system to 75% to extract the logs.", "#A0C0FF")
            RT.setObjective("Hack " .. (st.terminal_cs or "the data terminal"), true)
            MISSIONS.phase("whistleblower", "hacking")
        end
    end,
}

-- HACKING: Wait for crew to breach the terminal; jam probes as in hacking jobs.
M.phases.hacking = {
    enter = function(st)
        st.phase_entered = getScenarioTime()
        st._last_jam     = getScenarioTime()
    end,

    update = function(st, delta, now)
        if st.hacked then return end

        local t = RT.find(st.terminal_cs or "")
        if not RT.valid(t) then
            RT.shipLog("[Whistleblower] Data terminal destroyed -- logs lost.", "#FF8080")
            MISSIONS.phase("whistleblower", "done")
            return
        end

        -- Jam scan probes within 5U every 2 s.
        if now - st._last_jam > 2 then
            st._last_jam = now
            local tx, ty = t:getPosition()
            for _, obj in ipairs(getObjectsInRadius(tx, ty, 5000)) do
                if RT.valid(obj) and obj ~= t and isObjectType(obj, "ScanProbe") then
                    obj:destroy()
                    RT.shipLog("[Terminal] Jamming field neutralised a scan probe.", "#FF8080")
                end
            end
        end

        if _checkHacked(st) then
            st.hacked = true
            t:setCanBeDestroyed(true)
            RT.shipLog("[Whistleblower] Transaction logs extracted. Get clear of the area -- Marta Yuen wants to know what you plan to do with these.", "#80FF80")
            RT.after(5, function()
                if MISSIONS._status["whistleblower"] == "active" then
                    MISSIONS.phase("whistleblower", "extracted")
                end
            end, "wb_extracted_delay")
        end
    end,
}

-- EXTRACTED: A relay burst near the player carries Marta's message.
-- Three choices: merchant (fly to Tamsin Hollow), Concord IA (immediate),
-- burn (immediate, no payout).
M.phases.extracted = {
    enter = function(st)
        st.phase_entered = getScenarioTime()

        -- Spawn an encrypted relay burst near the player for the choice comms.
        local ref = RT.nearestPlayer(0, 0)
        local cx, cy = 0, 0
        if ref and RT.valid(ref) then
            cx, cy = ref:getPosition()
        end
        local relay = CpuShip():setTemplate("Flavia"):setFaction("Independent")
        relay:setPosition(cx + 2000, cy - 1500)
        relay:orderIdle():setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
        relay:setWeaponTubeCount(0):setCanBeDestroyed(false)
        relay:setCallSign("Encrypted Relay YM-7")
        RT.register(relay)
        st.relay_cs = relay:getCallSign()

        relay:setCommsFunction(function(src, tgt)
            setCommsMessage('"You got them. The logs name Rask and twelve shipments -- enough to end him.\n\nI can take these to the Border traders and make sure the whole Drift knows what Concord did. Or... I know someone at Concord Internal Affairs. They pay more, and Rask gets audited anyway. Your call."')

            addCommsReply("Deliver to you at Tamsin Hollow. This stays in the Border. (400 cr)", function(s2, t2)
                setCommsMessage('"Thank you. Every hauler Rask ever robbed -- this is for them. Bring the logs to Tamsin Hollow. I\'ll have your 400 waiting."')
                addCommsReply("On our way.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    st.choice = "merchant"
                    local r = RT.find(st.relay_cs or "")
                    if RT.valid(r) then r:destroy() end
                    MISSIONS.phase("whistleblower", "deliver")
                end)
            end)

            addCommsReply("Sell to Concord Internal Affairs. More money, Rask still answers. (600 cr)", function(s2, t2)
                setCommsMessage('"...I understand. The money is the money. Transmitting the IA channel now.\n\n[Concord Internal Affairs] Evidence received. Transfer authorised. -- 600 cr."')
                addCommsReply("Transmitted.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    st.choice = "concord"
                    local r = RT.find(st.relay_cs or "")
                    if RT.valid(r) then r:destroy() end
                    MISSIONS.phase("whistleblower", "done")
                end)
            end)

            addCommsReply("Burn it. This ends here.", function(s2, t2)
                setCommsMessage('"After everything I told you...\n\nFine. I never really expected help from people like you anyway."')
                addCommsReply("Sorry.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    st.choice = "burned"
                    local r = RT.find(st.relay_cs or "")
                    if RT.valid(r) then r:destroy() end
                    MISSIONS.phase("whistleblower", "done")
                end)
            end)
        end)

        RT.hail(relay, "Encrypted relay from Marta Yuen. Open comms when you're clear of the area.", "Marta Yuen [relay]")
        RT.setObjective("Respond to Marta Yuen", true)
    end,
}

-- DELIVER: Crew flies to Tamsin Hollow to hand off the logs to Marta.
M.phases.deliver = {
    enter = function(st)
        st.phase_entered = getScenarioTime()
        local tamsin = RT.find("Tamsin Hollow")
        if RT.valid(tamsin) then
            local tx, ty = tamsin:getPosition()
            RT.shipLog("[Whistleblower] Tamsin Hollow at grid " ..
                JOBS.gridRef(tx, ty) .. ". Marta's payment is waiting there.", "#A0C0FF")
        end
        RT.setObjective("Dock at Tamsin Hollow", true)

        RT.addStationHook("Tamsin Hollow", function(source, target)
            if not RT.isPlayer(source) then return end
            if not source:isDocked(target) then return end
            if MISSIONS._cur_phase["whistleblower"] ~= "deliver" then return end
            addCommsReply("Deliver the Arbiter transaction logs to Marta. (+400 cr)", function(s2, t2)
                setCommsMessage('"These will end him. Every Independent trader who lost cargo to Rask -- this is for all of them. You did the right thing."\n\n[400 cr transferred]')
                addCommsReply("Good luck with it.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    MISSIONS.phase("whistleblower", "done")
                end)
            end)
        end)
    end,
}

-- ── Register ────────────────────────────────────────────────────────────────

MISSIONS.register(M)
