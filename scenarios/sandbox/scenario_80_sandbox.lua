-- Name: Sandbox: Open Play
-- Description: Explore the Drift, earn credits, upgrade your ship. No fixed story--make your own. Perfect for learning the universe and trying out ship systems. The AI director creates dynamic encounters based on your choices.
---
--- Sandbox campaign. Credits and upgrades persist across sessions. No fixed objectives.
--- Optional: run the AI director (director/main.py) for dynamic encounters and opportunities.
-- Type: The Drift Universe
-- Setting[Campaign]: Use saved campaign progress or start over.
-- Campaign[Continue|Default]: Keep credits and upgrades from earlier sessions.
-- Campaign[Fresh start]: Wipe campaign progress and start with a stock ship.
-- Setting[Starting Credits]: How much money to start with (Fresh start only).
-- Starting Credits[Modest (200)|Default]: Enough for a few repairs or one small upgrade.
-- Starting Credits[Comfortable (500)]: Enough to buy a decent upgrade right away.
-- Starting Credits[Well-off (1000)]: Can afford multiple upgrades immediately.
-- Setting[Danger Level]: How aggressive the universe is.
-- Danger Level[Relaxed]: Fewer hostiles, more time to explore.
-- Danger Level[Normal|Default]: Balanced encounters.
-- Danger Level[Dangerous]: More hostiles, tighter director budget for spawns.
-- Setting[Director]: Whether the scenario talks to the external AI director.
-- Director[On|Default]: Dynamic encounters and opportunities from the AI director.
-- Director[Off]: Static universe with scripted random encounters only.

require("utils.lua")
require("ragtag/core.lua")
require("ragtag/verse.lua")
require("ragtag/director.lua")
require("ragtag/proximity.lua")
require("ragtag/mission.lua")
require("ragtag/jobs.lua")
require("ragtag/rumors.lua")
require("ragtag/ship_templates.lua")  -- custom playership templates; must load before init

local SESSION_ID = "sandbox"

-- Named ships available to the campaign — slot 1 is always the primary.
-- All are Flavia P.Falcon class; names are birds (sister ships to the Magpie).
local _SHIP_ROSTER = {
    "Magpie", "Raven", "Jackdaw", "Starling", "Wren",
    "Kestrel", "Harrier", "Merlin", "Osprey", "Swift",
}

-- Session state
local S = {
    phase = "start",           -- start, exploring, docked, ending
    session_num = 1,           -- which sandbox session this is
    time_exploring = 0,        -- time spent not docked
    encounters_spawned = 0,
    last_opportunity_time = 0,
    visited_regions = {},      -- track where crew has been
    docked_at = nil,
    ending = false,
    vesper_first_hail = false, -- track first hail to Port Vesper for welcome message
    -- JOBS.config.work_cooldown_enabled and .mission_distance_mode replaced work_cooldown_enabled / mission_distance_mode
    -- JOBS.config.jobboard_locked replaced witness_active for the job board
}

--------------------------------------------------------------------------------
-- Rumors and wreck logs
--------------------------------------------------------------------------------

local RUMORS = {}

-- Wreck story fragments, keyed by callsign.
local _WRECK_LOGS = {
    -- Boneyard -- Settlement War hulks
    ["CWS Bulwark"]        = '"Day 47 of the siege. Captain Orin to any Concord command: we are holding Ashgrave approach. We are still holding. Please respond."',
    ["Free Ship Defiance"] = '"They told us the vote would be bloodless. Somebody forgot to tell the gunships."  -- last entry, Free Ship Defiance.',
    ["CWS Morningside"]    = 'Distress beacon, CWS Morningside, crew of eleven. Hull breach compartments three through seven. "If anyone receives this -- we were here."',
    ["Free Ship Hollis"]   = 'Hollis crew manifest recovered from emergency memory. Forty-one names. The war ended six weeks after they launched.',
    ["CWS Anvil"]          = '"We\'re not retreating. We\'re advancing in a new direction." -- Commander Vayne, CWS Anvil. Last words before the bridge lost pressure.',
    ["Free Ship Tallow"]   = '"If you\'re reading this, the settlement worked. Tell my kids I held the line."  -- Tallow final transmission.',
    ["CWS Equity"]         = '"We surrendered at 0400. The Concord officer was kind about it. I don\'t know what to make of that."  -- Captain\'s log, CWS Equity.',
    ["Free Ship Long Odds"] = 'Encrypted fragment, twenty-year-old code. "Rally at Ashgrave. One last push."  Free Ship Long Odds never arrived.',
    ["CWS Clarion"]        = 'Automated beacon, CWS Clarion, looping since the war ended. Hull integrity: 12%. Crew status: unknown. Unknown. Unknown.',
    ["Free Ship Harrow"]   = '"You\'re fighting for a rock." "We\'re fighting so the rock is ours."  End of argument. End of recording.',
    ["CWS Mercy"]          = '"We have more injured than bay capacity. I am going to run out of things to write."  -- Medical log, CWS Mercy.',
    ["Free Ship Whistler"] = 'Navigation log, Free Ship Whistler. Last entry automated. Destination: Tamsin. Arrival: never.',
    -- Dustmote -- recent hulks
    ["Hulk 7"]  = 'Salvage tag attached: "Strip to frame, sell the rest." Someone didn\'t finish the job.',
    ["Hulk 12"] = 'Registry plate still readable: Persistent Hope. Someone scraped off the name but left the plate.',
    ["Hulk 19"] = 'A coffee mug magnetically clamped to the helm. Still has coffee in it. Relatively recent.',
    ["Hulk 23"] = 'Personal log found wedged in a console. First entry: "New ship, new start." Last entry: "Engine won\'t start." Three months between.',
    -- Shroud -- missing freighters
    ["Penny Dreadful"]   = '"The Shroud doesn\'t mess with sensors. The Shroud messes with you. We\'re turning back."  -- Penny Dreadful voice log. They didn\'t turn back.',
    ["Calloway's Luck"]  = '"We found something. I don\'t know what it is. I don\'t think it\'s-- [static] --beautiful."  -- Final comms, Calloway\'s Luck.',
    ["Seventh Son"]      = 'Automated log, Seventh Son. Navigation: position unknown. Course: unknown. Drift duration: 47 days. Hull: intact. Crew: [null].',
}

local _wrecks_logged = {}  -- callsign -> true

function RUMORS.checkWrecks()
    if not RT.valid(RT.player) then return end
    for _, entry in ipairs(VERSE.wrecks) do
        local s = entry.ship
        if RT.valid(s) then
            local cs = s:getCallSign()
            if not _wrecks_logged[cs] then
                local ok, scanned = pcall(function() return s:isFullyScannedBy(RT.player) end)
                if ok and scanned then
                    _wrecks_logged[cs] = true
                    local log = _WRECK_LOGS[cs] or
                        ('Automated beacon, ' .. cs .. '. Crew status: no response.')
                    RT.shipLog("[Scan] " .. cs .. ": " .. log, "#C0A0A0")
                    DIR.emit("wreck_scanned", {name=cs, tier=entry.tier}, "low")
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- THE WITNESS -- optional story arc (GM-triggered)
-- Phases: inactive → offer → transit → checkpoint → revealed →
--         shroud_run → halcyon → broadcast → done
-- JOBS.config.jobboard_locked blocks the job board for the duration.
--------------------------------------------------------------------------------

local W = {
    phase            = "inactive",
    phase_entered    = 0,
    panel_next       = 0,
    offer_hail_at    = nil,      -- delayed hail timer for offer phase
    -- pod
    pod_stability    = 100.0,
    pod_drain_on     = false,
    ep_next          = 0,        -- emergency power cooldown (scenario time)
    -- flags
    kael_alive       = true,
    complied         = false,    -- surrendered pod at checkpoint
    checkpoint_fired = false,
    checkpoint_choice = nil,     -- "comply" | "stall" | "run"
    checkpoint_timer  = 0,
    transit_warned   = false,    -- one-time Concord traffic warning en route
    sable_warned     = false,
    broadcast_done   = false,
    -- entity callsigns
    concord_names    = {},
    corsair_names    = {},
    buoy_cs          = nil,
    -- cooldowns
    last_warning     = -999,
}

-- ── Utilities ──────────────────────────────────────────────────────────────

local function W_enterPhase(name)
    W.phase        = name
    W.phase_entered = getScenarioTime()
end

-- Drain ship energy and degrade pod stability based on power level.
local function W_podTick(delta)
    if not W.pod_drain_on or not W.kael_alive then return end

    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            p:setEnergyLevel(math.max(0, p:getEnergy() - 5 * delta))
        end
    end)

    local total_frac, count = 0, 0
    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            local mx = p:getMaxEnergy()
            if mx > 0 then
                total_frac = total_frac + p:getEnergy() / mx
                count = count + 1
            end
        end
    end)
    local frac = count > 0 and (total_frac / count) or 1.0

    local change = 0
    if     frac < 0.10 then change = -5.0 * delta
    elseif frac < 0.25 then change = -2.5 * delta
    elseif frac < 0.45 then change = -0.8 * delta
    elseif frac > 0.70 then change =  0.3 * delta
    end

    local prev = W.pod_stability
    W.pod_stability = math.max(0, math.min(100, W.pod_stability + change))

    local now = getScenarioTime()
    for _, thr in ipairs({60, 30, 10}) do
        if prev > thr and W.pod_stability <= thr and now - W.last_warning > 20 then
            W.last_warning = now
            if thr == 60 then
                RT.shipLog("[Stasis] Pod stability dropping. Engineering: watch your energy draw.", "#FFAA00")
            elseif thr == 30 then
                RT.shipLog("[Stasis] CRITICAL -- pod failing. Engineering: emergency power now.", "#FF4040")
            elseif thr == 10 then
                RT.shipLog("[Science] Cardiac arrest imminent. We need everything Engineering can give.", "#FF4040")
            end
        end
    end

    if W.pod_stability <= 0 and W.kael_alive then
        W.kael_alive   = false
        W.pod_drain_on = false
        RT.shipLog("[Stasis] Kael Voss -- flatlined.", "#FF4040")
        RT.forEachPlayer(function(p)
            if RT.valid(p) then
                p:addCustomInfo("engineering", "w_pod_status", "Stasis pod: OFFLINE -- patient lost", 1)
                p:addCustomInfo("science",     "w_pod_vitals", "Patient vitals: flatline",            1)
            end
        end)
    end
end

local function W_updatePanels()
    if not W.kael_alive then return end  -- flatline messages set on death; don't overwrite
    local stab   = W.pod_stability
    local status = stab > 60 and "Stable" or (stab > 30 and "Unstable" or "CRITICAL")
    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            p:addCustomInfo("engineering", "w_pod_status",
                string.format("Stasis pod: %.0f%% -- %s", stab, status), 1)
            p:addCustomInfo("science", "w_pod_vitals",
                string.format("Patient vitals: %s (pod %.0f%%)",
                    stab > 60 and "stable" or (stab > 30 and "irregular" or "critical"),
                    stab), 1)
        end
    end)
end

local function W_addPodButtons()
    RT.forEachPlayer(function(p)
        if not RT.valid(p) then return end
        p:addCustomButton("engineering", "w_ep_button", "Emergency Power (pod)", function()
            local now = getScenarioTime()
            if now < W.ep_next then
                RT.shipLog(string.format("[Engineering] Emergency power on cooldown -- %.0fs remaining.", W.ep_next - now), "#FFAA00")
                return
            end
            W.ep_next       = now + 90
            W.pod_stability = math.min(100, W.pod_stability + 25)
            RT.shipLog(string.format("[Engineering] Emergency power rerouted -- pod stability +25 (now %.0f%%).", W.pod_stability), "#80FF80")
        end, 10)
    end)
end

local function W_removePodUI()
    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            p:removeCustom("w_ep_button")
            p:removeCustom("w_pod_status")
            p:removeCustom("w_pod_vitals")
        end
    end)
end

-- ── Phase functions (defined bottom-up so each can reference earlier ones) ─

local function W_finish()
    if W.broadcast_done then return end
    W.broadcast_done = true
    W_enterPhase("done")
    W.pod_drain_on = false
    W_removePodUI()

    local reward, msg
    if W.kael_alive and not W.complied then
        reward = 600
        msg    = "Broadcast sent. Kael Voss survived. His evidence is on every channel in the Drift -- they can't unring this bell."
    elseif not W.kael_alive then
        reward = 400
        msg    = "Broadcast sent. Kael Voss didn't survive the transit, but his evidence did. The truth got out, carried by a dead man's data."
    else
        reward = 300
        msg    = "Broadcast sent. Kael is in Concord custody, but the evidence is now public. It may free him. It may not be enough."
    end

    local outcome = W.kael_alive and (W.complied and "broadcast_after_comply" or "kael_survived") or "broadcast_only"
    RT.addCredits(reward, "The Witness: " .. outcome)
    RT.shipLog("[The Witness] " .. msg .. " +" .. reward .. " cr.", "#80FF80")
    RT.flag("witness_complete", outcome)
    DIR.emit("witness_complete", {outcome = outcome, kael_alive = W.kael_alive, complied = W.complied}, "high")
    RT.setObjective("The Witness: complete", true)

    local buoy = RT.find(W.buoy_cs or "")
    if RT.valid(buoy) then buoy:setCanBeDestroyed(true) end

    globalMessage("The Witness -- arc complete. " .. msg, 15)
end

local function W_startBroadcast()
    W_enterPhase("broadcast")

    local buoy = RT.find(W.buoy_cs or "")
    if RT.valid(buoy) then
        local bx, by = buoy:getPosition()
        RT.shipLog("[Relay] " .. W.buoy_cs .. " at grid " .. MISSION.gridRef(bx, by) ..
            ". Science: open the hacking panel and breach the reactor to 50% to trigger the broadcast.", "#A0C0FF")
        buoy:setCommsFunction(function(src, tgt)
            setCommsMessage('"Public Relay Node. Unauthorized access detected. This channel is Concord-licensed."')
        end)
    end

    -- Concord response wave
    local ref = RT.nearestPlayer(0, 0)
    if ref and RT.valid(ref) then
        local px, py = ref:getPosition()
        for i = 1, 3 do
            local s = CpuShip():setTemplate("MT52 Hornet"):setFaction("Concord")
            local ang = ((i - 1) / 3) * 2 * math.pi + math.random() * 0.5
            s:setPosition(px + math.cos(ang) * 22000, py + math.sin(ang) * 22000)
            s:orderAttack(ref)
            RT.register(s); DIR.registerKill(s); DIR.allowControl(s)
        end
    end
    RT.shipLog("[Warning] Concord response inbound -- three ships. Hold them off while Relay completes the broadcast.", "#FF8080")
end

local function W_startHalcyon()
    W_enterPhase("halcyon")
    RT.setObjective("Dock at Halcyon Rest", true)

    -- Spawn the relay buoy near Halcyon Rest
    local hx, hy = VERSE.at("Halcyon Rest", 8, 6)
    local buoy = CpuShip():setTemplate("Flavia"):setFaction("Independent")
    buoy:setPosition(hx + random(-1500, 1500), hy + random(-1500, 1500))
    buoy:orderIdle()
    buoy:setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    buoy:setWeaponTubeCount(0):setCanBeDestroyed(false)
    buoy:setCallSign("Public Relay " .. math.random(10, 99))
    RT.register(buoy)
    W.buoy_cs = buoy:getCallSign()

    local bx, by = buoy:getPosition()
    RT.shipLog("[Intel] Relay buoy: " .. W.buoy_cs .. " at grid " .. MISSION.gridRef(bx, by) .. ".", "#A0C0FF")

    RT.addStationHook("Halcyon Rest", function(source, target)
        if not RT.isPlayer(source) then return end
        if not source:isDocked(target) then return end
        if W.phase ~= "halcyon" then return end
        addCommsReply("Ask for Sable.", function(s2, t2)
            if W.sable_warned then
                setCommsMessage('"Sable checked out an hour ago. Left in a hurry -- Concord shuttle was asking after her."')
                addCommsReply("We know where to go.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    W_startBroadcast()
                end)
            else
                setCommsMessage('"She\'s here. Keeps looking at the docks."\n\nA message arrives from Sable: "Don\'t trust me. They have leverage. The broadcast still matters -- go to the relay buoy. Don\'t wait."')
                W.sable_warned = true
                addCommsReply("Head to the relay buoy.", function(s3, t3)
                    RT.stationComms(s3, t3)
                    W_startBroadcast()
                end)
            end
        end)
    end)
end

local function W_spawnCorsairAmbush()
    local ref = RT.nearestPlayer(0, 0)
    if not ref then return end
    local px, py = ref:getPosition()
    local ang = math.random() * 2 * math.pi
    W.corsair_names = {}
    local templates = {"MT52 Hornet", "MT52 Hornet", "Adder MK5"}
    for i, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction("Corsairs")
        s:setPosition(px + math.cos(ang + (i-1) * 0.7) * (8000 + random(-1000, 1000)),
                      py + math.sin(ang + (i-1) * 0.7) * (8000 + random(-1000, 1000)))
        s:orderAttack(ref)
        RT.register(s); DIR.registerKill(s); DIR.allowControl(s)
        W.corsair_names[i] = s:getCallSign()
    end
    RT.shipLog("[Ambush] Corsairs -- " .. table.concat(W.corsair_names, ", ") .. ". Someone talked.", "#FF8080")
end

local function W_startShroudRun()
    W_enterPhase("shroud_run")
    local hp = VERSE.places["Halcyon Rest"]
    local hloc = hp and (" Grid " .. MISSION.gridRef(hp.x, hp.y)) or ""
    RT.shipLog("[Navigation] Entering the Shroud. Long-range sensors degrading — watch for contacts. Halcyon Rest" .. hloc .. " is a neutral station inside the nebula.", "#C0C0C0")
    RT.setObjective("Reach Halcyon Rest", true)
end

local function W_startRevealed()
    W_enterPhase("revealed")
    if W.complied then
        local hp = VERSE.places["Halcyon Rest"]
        local hloc = hp and (" Grid " .. MISSION.gridRef(hp.x, hp.y) .. ", deep in the Shroud") or " (deep in the Shroud)"
        RT.shipLog('[Message] Dead-drop — Mira\'s contact: "Concord got the pod, not the data. It\'s sewn into the outer casing — check your cargo hold, they left it behind. Get to Halcyon Rest' .. hloc .. '. Find Sable. There\'s a public relay buoy. This isn\'t over."', "#A0C0FF")
    else
        local hp = VERSE.places["Halcyon Rest"]
        local hloc = hp and (" Grid " .. MISSION.gridRef(hp.x, hp.y) .. ", deep in the Shroud") or " (deep in the Shroud)"
        RT.shipLog('[Stasis] Transmission from the pod: "My name is Kael Voss. I was a Concord logistics officer. What I know will end careers. Get me to Halcyon Rest' .. hloc .. ' -- there\'s a relay buoy there. One broadcast and it\'s over. Whatever she paid you, I\'ll double it."', "#A0C0FF")
    end
    RT.setObjective("Reach Halcyon Rest", true)
end

local function W_startCheckpoint()
    W_enterPhase("checkpoint")

    local ref = RT.nearestPlayer(0, 0)
    if not ref or not RT.valid(ref) then return end

    local px, py = ref:getPosition()
    local heading = ref:getHeading()

    -- Spawn 10U ahead of player along their heading
    local angle_rad = math.rad(heading - 90)  -- EE heading conversion
    local lead_dist = 10000  -- 10U ahead
    local cx = px + math.cos(angle_rad) * lead_dist
    local cy = py + math.sin(angle_rad) * lead_dist

    -- Create perpendicular line formation (5 ships across their path)
    local perp_rad = angle_rad + math.pi/2  -- 90 degrees to heading
    local spacing = 2500  -- 2.5U between ships

    local templates = {"MT52 Hornet", "MT52 Hornet", "MU52 Hornet", "MT52 Hornet", "MT52 Hornet"}
    for i = 1, 5 do
        local offset = (i - 3) * spacing  -- -2, -1, 0, 1, 2 positions
        local sx = cx + math.cos(perp_rad) * offset
        local sy = cy + math.sin(perp_rad) * offset

        local ship = CpuShip():setTemplate(templates[i]):setFaction("Concord")
        ship:setPosition(sx, sy):orderIdle():setCanBeDestroyed(true)
        RT.register(ship); DIR.registerKill(ship); DIR.allowControl(ship)
        W.concord_names[i] = ship:getCallSign()
    end

    -- Lead ship gets comms function
    local s1 = RT.find(W.concord_names[1])
    if not RT.valid(s1) then return end

    s1:setCommsFunction(function(src, tgt)
        setCommsMessage('"Independent vessel. Cut engines. You are carrying an unregistered stasis pod. Surrender it -- you will be free to go."')
        addCommsReply("We're on a licensed delivery. Nothing unusual aboard.", function(s_r, t_r)
            setCommsMessage('"Scan confirms the pod. You have 45 seconds to comply or we board by force."')
            W.checkpoint_choice = "stall"
            W.checkpoint_timer  = getScenarioTime() + 45
            addCommsReply("Fine. Take it.", function(s_r2, t_r2)
                W.complied        = true
                W.checkpoint_choice = "comply"
                setCommsMessage('"Smart choice. On your way."')
                addCommsReply("...", function(s_r3, t_r3) RT.stationComms(s_r3, t_r3) end)
                RT.shipLog("[Checkpoint] Pod surrendered to Concord.", "#FF8080")
                for _, n in ipairs(W.concord_names) do
                    local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
                end
                W_startRevealed()
            end)
            addCommsReply("Full burn -- break contact!", function(s_r2, t_r2)
                W.checkpoint_choice = "run"
                for _, n in ipairs(W.concord_names) do
                    local sc = RT.find(n)
                    if RT.valid(sc) and RT.valid(s_r) then sc:orderAttack(s_r) end
                end
            end)
        end)
        addCommsReply("We're not stopping for anyone.", function(s_r, t_r)
            W.checkpoint_choice = "run"
            setCommsMessage('"All units -- pursue."')
            for _, n in ipairs(W.concord_names) do
                local sc = RT.find(n)
                if RT.valid(sc) and RT.valid(src) then sc:orderAttack(src) end
            end
        end)
        addCommsReply("Take the pod. We want no trouble.", function(s_r, t_r)
            W.complied        = true
            W.checkpoint_choice = "comply"
            setCommsMessage('"Transfer complete. On your way."')
            addCommsReply("...", function(s_r2, t_r2) RT.stationComms(s_r2, t_r2) end)
            RT.shipLog("[Checkpoint] Pod surrendered to Concord.", "#FF8080")
            for _, n in ipairs(W.concord_names) do
                local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
            end
            W_startRevealed()
        end)
    end)

    RT.hail(s1, "Independent vessel. Cut engines. You are carrying an unregistered stasis pod. Concord inspection -- comply immediately.", "Concord Patrol")
    RT.shipLog("[Warning] Concord blockade on intercept -- five ships blocking our path.", "#FFAA00")
end

local function W_startOffer()
    JOBS.config.jobboard_locked = true
    W_enterPhase("offer")

    local vx, vy = VERSE.at("Port Vesper", -2, -1)
    local mira = CpuShip():setTemplate("Flavia"):setFaction("Independent")
    mira:setPosition(vx, vy)
    mira:orderIdle()
    mira:setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    mira:setWeaponTubeCount(0):setCanBeDestroyed(false)
    mira:setCallSign("Mira's Luck")
    RT.register(mira)

    mira:setCommsFunction(function(src, tgt)
        setCommsMessage('"I need a discreet crew -- no questions asked. Passenger in stasis who needs to reach Dustmote Salvage quietly. Concord would prefer he never arrive. 300 credits. Yes or no?"')
        addCommsReply("We'll take the job.", function(s2, t2)
            setCommsMessage('"Good. Transferring the pod now. He draws five energy a second from your reactor -- keep him stable. Get to Dustmote Salvage before Concord gets word. If things go wrong, ask for Sable at Halcyon Rest -- she knows what to do with him."\n\nMira\'s Luck goes dark.')
            addCommsReply("Understood.", function(s3, t3) RT.stationComms(s3, t3) end)
            local m = RT.find("Mira's Luck")
            if RT.valid(m) then m:destroy() end
            W_enterPhase("transit")
            W.pod_drain_on = true
            W_addPodButtons()
            W_updatePanels()
            RT.shipLog("[Stasis] Pod aboard -- Kael Voss in stasis. Destination: Dustmote Salvage.", "#A0C0FF")
            RT.shipLog("[Engineering] Pod drawing 5 energy/sec. Keep energy above 50% to maintain stability.", "#FFAA00")
            RT.setObjective("Reach Dustmote Salvage", true)
        end)
        addCommsReply("Not our problem.", function(s2, t2)
            setCommsMessage('"Your call. He won\'t last long without power."')
            addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
        end)
    end)

    -- Delay hail by 3 seconds to avoid comms collision if player is in station dialog
    W.offer_hail_at = getScenarioTime() + 3
    globalMessage("Witness arc starting -- incoming hail in 3 seconds...", 3)
end

-- ── Main update dispatcher ───────────────────────────────────────────────────

local function W_update(delta)
    local now = getScenarioTime()

    -- Handle delayed hail in offer phase
    if W.phase == "offer" and W.offer_hail_at and now >= W.offer_hail_at then
        W.offer_hail_at = nil
        local mira = RT.find("Mira's Luck")
        if RT.valid(mira) then
            RT.hail(mira, "Independent vessel -- Mira Doss, Mira's Luck. I've got a private offer. Open comms when you're clear.", "Mira Doss")
        end
    end

    if W.phase == "inactive" or W.phase == "offer" or W.phase == "done" then return end

    -- Pod drain + panel refresh every 5 s in all active phases
    W_podTick(delta)
    if now >= W.panel_next then
        W.panel_next = now + 5
        W_updatePanels()
    end

    if W.phase == "transit" then
        local ref = RT.nearestPlayer(0, 0)
        if ref and RT.valid(ref) then
            local px, py = ref:getPosition()
            -- Trigger checkpoint when 40U from Dustmote Salvage (104, -36)
            local dx, dy = px - 104000, py + 36000
            local dist_sq = dx * dx + dy * dy
            if not W.transit_warned and dist_sq < 70000 * 70000 then
                W.transit_warned = true
                RT.shipLog("[Comms] Heavy Concord traffic on the approach to Dustmote. Something has their attention out here.", "#FFAA00")
            end
            if not W.checkpoint_fired and dist_sq < 40000 * 40000 then
                W.checkpoint_fired = true
                W_startCheckpoint()
            end
        end

    elseif W.phase == "checkpoint" then
        if W.checkpoint_choice == "stall" and W.checkpoint_timer > 0 and now > W.checkpoint_timer then
            RT.shipLog("[Checkpoint] Time expired -- Concord boarded and took the pod.", "#FF8080")
            W.complied        = true
            W.checkpoint_choice = "comply"
            for _, n in ipairs(W.concord_names) do
                local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
            end
            W_startRevealed()
        elseif W.checkpoint_choice == "run" then
            local alive = false
            for _, n in ipairs(W.concord_names) do
                if RT.valid(RT.find(n)) then alive = true; break end
            end
            if not alive then
                RT.shipLog("[Checkpoint] Concord pursuit broken.", "#80FF80")
                W_startRevealed()
            end
        end

    elseif W.phase == "revealed" then
        if now - W.phase_entered > 60 then
            W_startShroudRun()
        end

    elseif W.phase == "shroud_run" then
        if #W.corsair_names == 0 and now - W.phase_entered > 60 then
            W_spawnCorsairAmbush()
        end
        -- Advance when corsairs cleared, near Halcyon Rest, or 5-min timeout
        local halcyon_e = RT.find("Halcyon Rest")
        local near_halcyon = false
        if RT.valid(halcyon_e) then
            local hx, hy = halcyon_e:getPosition()
            local ref = RT.nearestPlayer(hx, hy)
            if ref and RT.valid(ref) then
                local px, py = ref:getPosition()
                local dx, dy = px - hx, py - hy
                near_halcyon = dx * dx + dy * dy < 15000 * 15000
            end
        end
        local corsairs_alive = false
        for _, n in ipairs(W.corsair_names) do
            if RT.valid(RT.find(n)) then corsairs_alive = true; break end
        end
        if near_halcyon or (#W.corsair_names > 0 and not corsairs_alive) or now - W.phase_entered > 300 then
            W_startHalcyon()
        end

    elseif W.phase == "halcyon" then
        -- Also advance when player reaches the buoy directly (saw grid ref in log)
        local buoy = RT.find(W.buoy_cs or "")
        if RT.valid(buoy) then
            local bx, by = buoy:getPosition()
            local ref = RT.nearestPlayer(bx, by)
            if ref and RT.valid(ref) then
                local px, py = ref:getPosition()
                local dx, dy = px - bx, py - by
                if dx * dx + dy * dy < 8000 * 8000 then
                    W_startBroadcast()
                end
            end
        end
        -- 5-minute fallback in case players skip Halcyon Rest comms
        if now - W.phase_entered > 300 then
            W_startBroadcast()
        end

    elseif W.phase == "broadcast" then
        local buoy = RT.find(W.buoy_cs or "")
        if not RT.valid(buoy) then
            RT.shipLog("[Error] Relay buoy destroyed before broadcast -- arc failed.", "#FF8080")
            W_enterPhase("done")
            W.pod_drain_on = false
            W_removePodUI()
        elseif buoy:getSystemHackedLevel("reactor") >= 0.5 then
            W_finish()
        end
    end
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function init()
    VERSE.setupFactions()

    RT.useCampaign("sandbox")
    local fresh = getScenarioSetting("Campaign") == "Fresh start"
    RT.loadCampaign(fresh)

    if fresh then
        -- Set starting credits based on setting
        local start_credits = getScenarioSetting("Starting Credits")
        if start_credits == "Comfortable (500)" then
            RT.campaign.credits = 500
        elseif start_credits == "Well-off (1000)" then
            RT.campaign.credits = 1000
        else
            RT.campaign.credits = 200
        end
        RT.saveCampaign()
    end

    -- Track which sandbox session this is
    S.session_num = (RT.campaign.sandbox_sessions or 0) + 1
    RT.campaign.sandbox_sessions = S.session_num

    local danger = getScenarioSetting("Danger Level")
    if danger == "Relaxed" then
        DIR.config.max_ai_hostiles = 2
        DIR.config.spawn_cooldown = 240  -- 4 minutes between spawns
    elseif danger == "Dangerous" then
        DIR.config.max_ai_hostiles = 8
        DIR.config.spawn_cooldown = 90   -- 1.5 minutes between spawns
    else
        DIR.config.max_ai_hostiles = 5
        DIR.config.spawn_cooldown = 150  -- 2.5 minutes between spawns
    end
    DIR.enabled = getScenarioSetting("Director") ~= "Off"

    VERSE.build({session = S.session_num})
    -- Sandbox uses the whole universe; only explicitly require the starting location
    VERSE.requirePlaces({"Port Vesper", "Dustmote Salvage", "Halcyon Rest"})
    PROX.init()
    PROX.addGMButtons()

    -- Spawn the primary ship at Port Vesper. Additional ships join via the
    -- in-game "Create player ship" selection screen; onNewPlayerShip handles them.
    RT.PLAYER_TEMPLATE = "Light Freighter"
    local px, py = VERSE.at("Port Vesper", 1.5, 1.5)
    RT.spawnPlayer(px, py, 0)

    -- Ships created via the "Create player ship" selection screen spawn at 0,0 with no
    -- faction or name.  Move them to Port Vesper, set faction, and assign the next
    -- available roster name so every Drift freighter gets its bird name.
    onNewPlayerShip(function(ship)
        local vx, vy = VERSE.at("Port Vesper", 1.5, 1.5)
        local offset = #RT.players * 4000
        ship:setPosition(vx + offset, vy)
        local tmpl = ship:getTypeName()
        local faction =
            tmpl == "Concord Enforcer" and "Concord"  or
            tmpl == "Corsair Raider"   and "Corsairs" or
            RT.PLAYER_FACTION
        ship:setFaction(faction)
        -- Auto-assign the next available roster name for freighters.
        -- RT.spawnPlayer overrides this with its explicit callsign, so no conflict.
        if tmpl == "Light Freighter" then
            local used = {}
            for _, p in ipairs(RT.players) do used[p:getCallSign()] = true end
            for _, name in ipairs(_SHIP_ROSTER) do
                if not used[name] then ship:setCallSign(name); break end
            end
        end
        if RT.campaign then
            ship:setReputationPoints(RT.campaign.credits or 150)
        end
        -- Pre-register so RT.update's sync loop doesn't override the faction next frame.
        -- (RT.spawnPlayer may also insert; the duplicate guard there prevents double-entry.)
        local found = false
        for _, p in ipairs(RT.players) do
            if p == ship then found = true; break end
        end
        if not found then
            table.insert(RT.players, ship)
            RT.player = RT.players[1]
        end
    end)

    -- Custom Port Vesper comms: welcome message on first hail, standard message after
    local vesper = RT.find("Port Vesper")
    if RT.valid(vesper) then
        vesper:setCommsFunction(function(source, target)
            if source:isEnemy(target) then
                setCommsMessage("Static. Then a click. They've cut the channel.")
                return
            end

            local msg
            if not S.vesper_first_hail then
                -- First hail: welcome message
                S.vesper_first_hail = true
                local session_text = S.session_num == 1 and "Welcome to the Drift, independents." or "Back again, I see."
                msg = session_text .. " Port Vesper is neutral ground--you're safe here. But out there? That's on you. The Gauntlet has good salvage if you can keep it, Core stations pay top credits but ask questions, and nobody goes to the Maw and comes back. Fly safe."
            else
                -- Subsequent hails: standard docking message
                msg = "Port Vesper traffic control. Mind the dock clamps, they bite."
            end

            if source:isDocked(target) then
                msg = msg .. "\n\nYou're docked. Balance: " .. RT.credits(source) .. " credits."
            end
            setCommsMessage(msg)

            -- Run standard station hooks (mission board, upgrades, etc.)
            local info = RT.stations["Port Vesper"]
            if info then
                for _, hook in ipairs(info.hooks) do
                    local ok, err = pcall(hook, source, target, info)
                    if not ok then print("[RT] station hook failed: " .. tostring(err)) end
                end

                if source:isDocked(target) then
                    if info.shop then
                        addCommsReply("Shipwright: browse upgrades", function(s, t)
                            RT.shipwrightMenu(s, t)
                        end)
                    end
                end
            end

            addCommsReply("Back", function() end)
        end)
    end

    -- Wire mission board into every friendly station
    JOBS.init()
    for _, d in ipairs(VERSE.STATIONS) do
        if d.fac ~= "Corsairs" and d.fac ~= "Hollow" then
            RT.addStationHook(d.cs, JOBS.stationHook)
        end
    end

    RT.addCampaignGMFunctions()
    addSessionGMFunctions()
    defineBeats()

    DIR.addStateProvider(function()
        local job_descs = {}
        for _, entry in ipairs(_active) do
            job_descs[#job_descs+1] = entry.mission.short .. " (" .. entry.mission.type .. ")"
        end
        return {
            phase = S.phase,
            session_num = S.session_num,
            time_exploring = math.floor(S.time_exploring),
            encounters = S.encounters_spawned,
            region = getCurrentRegion(),
            visited = table.concat(getVisitedRegionsList(), ", "),
            active_jobs = table.concat(job_descs, "; "),
        }
    end)

    DIR.init({
        id = SESSION_ID,
        campaign = "sandbox",
        title = "Open Play (Session " .. S.session_num .. ")",
        premise = "The crew of an independent freighter explores the Drift, a frontier cluster of five suns. No fixed mission--just opportunities, dangers, and whatever the crew decides to pursue. This is session " .. S.session_num .. " of their ongoing story.",
        tone = "Space-western sandbox. Wry humour, real stakes, never grimdark. The crew are independents making their way. Every choice matters, but nothing is scripted. React to what the crew does and where they go.",
        cast = {
            {name = "Port Vesper Dockmaster", where = "Port Vesper", role = "neutral port authority", voice = "professional, knows everyone's business"},
            {name = "Freighter Captains", where = "various stations", role = "sources of rumours", voice = "varied; some friendly, some suspicious"},
            {name = "Corsair Raiders", where = "ambush sites", role = "opportunistic pirates", voice = "greedy, avoid fair fights"},
            {name = "Concord Patrols", where = "patrol routes", role = "the law", voice = "by-the-book, can be reasoned with"},
        },
        locations = {
            {name = "The Drift", note = "The whole universe is accessible. Danger increases toward the edges: Gauntlet (risky), Blackwater (dangerous), Boneyard (dangerous), Maw (deadly)."},
        },
        director_guidance = [[
You are observing a sandbox campaign set in the Drift. The crew flies an independent freighter through a frontier cluster of five suns.

Your role:
- Watch events and track what's happening
- Periodically summarize the situation (every 5-10 minutes of play)
- Note significant moments: first combat, reputation changes, close calls, discoveries
- Track crew's choices and their consequences

DO NOT:
- Fire story beats or spawn encounters (proximity spawns handle this automatically)
- Push narrative or complications
- Voice NPCs unless explicitly asked by GM
- Suggest opportunities or actions

Your summaries should be factual and concise:
- Current location and activity
- Recent events (last 5-10 minutes)
- Notable changes (credits, reputation, damage)
- Active missions (shown in state as "active_jobs")

Example summary:
"Crew completed salvage mission in the Gauntlet (+120cr, Corsairs -10 rep). Currently docked at Halcyon Rest with 45% hull. One boarding mission active (target heading to Dustmote)."
]],
    })
end

function getCurrentRegion()
    if not RT.valid(RT.player) then return "unknown" end
    local px, py = RT.player:getPosition()
    local region = VERSE.regionAt(px, py)
    return region and region.name or "deep space"
end

function getVisitedRegionsList()
    local list = {}
    for region, _ in pairs(S.visited_regions) do
        table.insert(list, region)
    end
    return list
end

--------------------------------------------------------------------------------
-- Story beats
--------------------------------------------------------------------------------

function defineBeats()
    -- No automatic welcome beat - player gets welcome message on first hail to Port Vesper

    DIR.defineBeat("first_undock", {desc = "Crew undocks for the first time this session", fn = function()
        RT.shipLog("Session " .. S.session_num .. " begins. Current funds: " .. RT.credits() .. " credits.", "#A0E0A0")
        if S.session_num == 1 then
            RT.shipLog("Helm: Stations are marked on the sector map. Science: Scan objects to reveal details. Relay: Hail stations for rumours. Engineering: Watch your power and repair damage. Weapons: Keep missiles loaded.", "#E0E0A0")
        end
    end})

    -- AI beats removed 2026-10-29: Director now observes and summarizes rather than driving narrative beats
end

function addSessionGMFunctions()
    addGMFunction("Campaign Status", function()
        local lines = {"=== CAMPAIGN STATUS ===\n"}
        if RT.campaign then
            table.insert(lines, string.format("Session: %d", S.session_num))
            table.insert(lines, string.format("Credits: %d", RT.campaign.credits))

            -- Upgrades and investment
            local cost_map = {}
            for _, u in ipairs(RT.UPGRADES) do cost_map[u.id] = u.cost end
            local total_invested = 0
            local upgrade_lines = {}
            for _, id in ipairs(RT.campaign.upgrades or {}) do
                local cost = cost_map[id] or 0
                total_invested = total_invested + cost
                for _, u in ipairs(RT.UPGRADES) do
                    if u.id == id then
                        upgrade_lines[#upgrade_lines+1] = string.format("  %s (%dcr)", u.name, cost)
                        break
                    end
                end
            end
            local tier = JOBS.maxTier()
            local next_threshold = tier == 0 and 500 or (tier == 1 and 1000 or nil)
            local tier_note = next_threshold
                and string.format(" — tier %d (next tier at %dcr)", tier, next_threshold)
                or  string.format(" — tier %d (max)", tier)
            table.insert(lines, string.format("\nUPGRADES: %dcr invested%s", total_invested, tier_note))
            if #upgrade_lines == 0 then
                table.insert(lines, "  (none)")
            else
                for _, l in ipairs(upgrade_lines) do table.insert(lines, l) end
            end

            table.insert(lines, "\nREPUTATION:")
            local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic", "Unknown"}
            for _, faction in ipairs(factions) do
                local rep = RT.getReputation(faction)
                local standing = ""
                if rep >= 50 then standing = " (Friendly)"
                elseif rep >= 20 then standing = " (Liked)"
                elseif rep >= -20 then standing = " (Neutral)"
                elseif rep >= -50 then standing = " (Disliked)"
                else standing = " (Hostile)" end
                table.insert(lines, string.format("  %s: %+d%s", faction, rep, standing))
            end
        end
        addGMMessage(table.concat(lines, "\n"))
    end)

    -- Reputation adjustment submenu
    local function showReputationFactionList()
        clearGMFunctions()
        addGMFunction("< Back to Main", function()
            clearGMFunctions()
            addSessionGMFunctions()
        end)

        local factions = {"Concord", "Corsairs", "Independent", "Hollow", "Relic"}
        for _, faction in ipairs(factions) do
            addGMFunction(faction .. "...", function()
                clearGMFunctions()
                addGMFunction("< Back to Factions", showReputationFactionList)

                local current = RT.getReputation(faction) or 0
                addGMFunction(string.format("Current: %+d", current), function()
                    addGMMessage(string.format("%s reputation: %+d", faction, RT.getReputation(faction) or 0))
                end)

                addGMFunction(faction .. " +50", function()
                    RT.adjustReputation(faction, 50)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s +50 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " +10", function()
                    RT.adjustReputation(faction, 10)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s +10 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " +1", function()
                    RT.adjustReputation(faction, 1)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s +1 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " -1", function()
                    RT.adjustReputation(faction, -1)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s -1 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " -10", function()
                    RT.adjustReputation(faction, -10)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s -10 (now %+d)", faction, RT.getReputation(faction)))
                end)

                addGMFunction(faction .. " -50", function()
                    RT.adjustReputation(faction, -50)
                    RT.saveCampaign()
                    addGMMessage(string.format("%s -50 (now %+d)", faction, RT.getReputation(faction)))
                end)
            end)
        end
    end

    addGMFunction("Adjust Reputation...", showReputationFactionList)

    addGMFunction("End session", function()
        if RT.valid(RT.player) then
            local docked = RT.player:getDockedWith()
            if docked and RT.valid(docked) then
                finishSession("completed", "Session ended at " .. docked:getCallSign() .. ".")
            else
                globalMessage("Dock at a friendly station first.", 5)
            end
        end
    end)

    addGMFunction("Credits +10", function()
        if RT.valid(RT.player) then
            RT.addCredits(10, "GM reward")
        end
    end)

    addGMFunction("Credits -10", function()
        if RT.valid(RT.player) then
            RT.addCredits(-10, "GM penalty")
        end
    end)

    addGMFunction("Work Cooldown: " .. (JOBS.config.work_cooldown_enabled and "ON" or "OFF"), function()
        JOBS.config.work_cooldown_enabled = not JOBS.config.work_cooldown_enabled
        clearGMFunctions()
        addSessionGMFunctions()
    end)

    local distance_labels = {short = "SHORT", medium = "MEDIUM", long = "LONG"}
    addGMFunction("Job Distance: " .. (distance_labels[JOBS.config.mission_distance_mode] or "MEDIUM"), function()
        if JOBS.config.mission_distance_mode == "short" then
            JOBS.config.mission_distance_mode = "medium"
        elseif JOBS.config.mission_distance_mode == "medium" then
            JOBS.config.mission_distance_mode = "long"
        else
            JOBS.config.mission_distance_mode = "short"
        end
        clearGMFunctions()
        addSessionGMFunctions()
    end)

    addGMFunction("Witness: Start", function()
        if W.phase ~= "inactive" then
            local msg = "Witness arc already at phase: " .. W.phase
            globalMessage(msg, 5)
            addGMMessage(msg)
            return
        end
        W_startOffer()
    end)

    addGMFunction("Witness: >Chkpt", function()
        JOBS.config.jobboard_locked = true
        W.pod_drain_on     = true
        W.checkpoint_fired = true
        W_addPodButtons()
        W_updatePanels()
        RT.shipLog("[Stasis] Pod aboard -- Kael Voss in stasis. (GM skip)", "#A0C0FF")
        W_startCheckpoint()
    end)

    addGMFunction("Witness: >Bcast", function()
        JOBS.config.jobboard_locked = true
        W.pod_drain_on     = true
        W.checkpoint_fired = true
        W_addPodButtons()
        W_updatePanels()
        RT.shipLog("[Stasis] Pod aboard -- Kael Voss in stasis. (GM skip)", "#A0C0FF")
        W_startHalcyon()
        W_startBroadcast()
    end)

    addGMFunction("Witness: Pod>Crit", function()
        if W.pod_drain_on then
            W.pod_stability = 15
            RT.shipLog("[GM] Stasis pod forced to critical stability.", "#FF4040")
        end
    end)

    addGMFunction("Witness: Cancel", function()
        if W.phase == "inactive" then return end
        local m = RT.find("Mira's Luck")
        if RT.valid(m) then m:destroy() end
        W.phase            = "inactive"
        W.offer_hail_at    = nil
        W.pod_drain_on     = false
        W.checkpoint_fired = false
        W.corsair_names    = {}
        W.concord_names    = {}
        JOBS.config.jobboard_locked = false
        W_removePodUI()
        globalMessage("Witness arc cancelled and reset.", 5)
        addGMMessage("Witness arc cancelled. Phase reset to inactive.")
    end)
end

--------------------------------------------------------------------------------
-- Ending
--------------------------------------------------------------------------------

function finishSession(outcome, note)
    if S.ending then return end
    S.ending = true
    S.phase = "ending"

    RT.completeSession(SESSION_ID .. "_" .. S.session_num, outcome, note)
    DIR.emit("session_end", {
        session = SESSION_ID,
        session_num = S.session_num,
        outcome = outcome,
        note = note,
        credits = RT.credits(),
        time_exploring = S.time_exploring,
        encounters = S.encounters_spawned,
        visited = getVisitedRegionsList(),
        flags = RT.campaign.flags
    }, "high")

    globalMessage("Session " .. S.session_num .. " complete: " .. note .. " | Credits: " .. RT.credits(), 12)

    -- Give the director time to generate a session summary
    RT.after(12, function() victory(RT.PLAYER_FACTION) end, "victory")
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

function update(delta)
    RT.update(delta)
    RT.updateKillTracking()  -- Track ship kills for reputation
    VERSE.update(delta)
    DIR.update(delta)
    if not JOBS.config.jobboard_locked then PROX.update(delta) end

    if S.phase == "ending" then return end

    if not RT.anyPlayerAlive() then
        if not S.ending then
            finishSession("destroyed", "The ship was lost after " .. math.floor(S.time_exploring / 60) .. " minutes.")
        end
        return
    end

    local now = getScenarioTime()
    local docked = RT.valid(RT.player) and RT.player:getDockedWith() or nil

    -- Track region visits (primary ship drives phase/region logic)
    local region = getCurrentRegion()
    if region and region ~= "unknown" and not S.visited_regions[region] then
        S.visited_regions[region] = true
        RT.shipLog("Entered " .. region .. ".", "#C0C0C0")
        DIR.emit("region_visited", {region = region}, "low")
    end

    -- Phase management
    if S.phase == "start" then
        if now > 5 then
            -- Set initial objective
            RT.setObjective("Explore the Drift")
            S.phase = "docked"
            S.docked_at = "Port Vesper"
        end
    elseif S.phase == "docked" then
        if not docked or not RT.valid(docked) then
            -- Just undocked
            DIR.fireBeat("first_undock", "script")
            S.phase = "exploring"
            S.undocked_at = now
            S.docked_at = nil
        end
    elseif S.phase == "exploring" then
        S.time_exploring = S.time_exploring + delta

        if docked and RT.valid(docked) then
            -- Just docked
            S.phase = "docked"
            S.docked_at = docked:getCallSign()
            DIR.emit("docked", {station = S.docked_at}, "medium")
        end
    end

    JOBS.update()
    RUMORS.checkWrecks()
    W_update(delta)

end
