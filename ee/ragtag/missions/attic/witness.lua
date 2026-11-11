-- ee/ragtag/missions/witness.lua
-- The Witness: a GM-triggered story arc.
-- Phases: offer -> transit -> checkpoint -> revealed ->
--         shroud_run -> halcyon -> broadcast -> done

local M = {}
M.id          = "witness"
M.name        = "The Witness"
M.repeatable  = false
M.locks_jobs  = true
M.auto_start  = false
M.start_phase = "offer"

-- Trigger conditions. All must be true for status to flip "triggered".
-- auto_start is false, so "triggered" only lights up the GM button label.
M.triggers = {
    not_flagged = {"witness_complete"},
    -- Uncomment to enable threshold-based auto-trigger in future:
    -- upgrades_min = 500,
    -- rep_min = { Independent = 100 },
}

M.phase_order = {
    "offer", "transit", "checkpoint", "revealed",
    "shroud_run", "halcyon", "broadcast",
}

function M.init_state()
    return {
        phase_entered     = 0,
        panel_next        = 0,
        offer_hail_at     = nil,
        pod_stability     = 100.0,
        pod_drain_on      = false,
        ep_next           = 0,
        kael_alive        = true,
        complied          = false,
        checkpoint_fired  = false,
        checkpoint_choice = nil,
        checkpoint_timer  = 0,
        transit_warned    = false,
        sable_warned      = false,
        broadcast_done    = false,
        concord_names     = {},
        corsair_names     = {},
        buoy_cs           = nil,
        last_warning      = -999,
    }
end

-- Custom GM actions shown when the mission is active.
M.gm_actions = {
    {label = "Pod > Critical", fn = function(st)
        if st.pod_drain_on then
            st.pod_stability = 15
            RT.shipLog("[GM] Stasis pod forced to critical stability.", "#FF4040")
        end
    end},
}

-- ── Pod helpers ────────────────────────────────────────────────────────────

local function _podTick(st, delta)
    if not st.pod_drain_on or not st.kael_alive then return end

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

    local prev = st.pod_stability
    st.pod_stability = math.max(0, math.min(100, st.pod_stability + change))

    local now = getScenarioTime()
    for _, thr in ipairs({60, 30, 10}) do
        if prev > thr and st.pod_stability <= thr and now - st.last_warning > 20 then
            st.last_warning = now
            if thr == 60 then
                RT.shipLog("[Stasis] Pod stability dropping. Engineering: watch your energy draw.", "#FFAA00")
            elseif thr == 30 then
                RT.shipLog("[Stasis] CRITICAL -- pod failing. Engineering: emergency power now.", "#FF4040")
            elseif thr == 10 then
                RT.shipLog("[Science] Cardiac arrest imminent. We need everything Engineering can give.", "#FF4040")
            end
        end
    end

    if st.pod_stability <= 0 and st.kael_alive then
        st.kael_alive    = false
        st.pod_drain_on  = false
        RT.shipLog("[Stasis] Kael Voss -- flatlined.", "#FF4040")
        RT.forEachPlayer(function(p)
            if RT.valid(p) then
                p:addCustomInfo("engineering", "w_pod_status", "Stasis pod: OFFLINE -- patient lost", 1)
                p:addCustomInfo("science",     "w_pod_vitals", "Patient vitals: flatline",            1)
            end
        end)
    end
end

local function _updatePanels(st)
    if not st.kael_alive then return end
    local stab   = st.pod_stability
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

local function _addPodButtons(st)
    RT.forEachPlayer(function(p)
        if not RT.valid(p) then return end
        p:addCustomButton("engineering", "w_ep_button", "Emergency Power (pod)", function()
            local now = getScenarioTime()
            if now < st.ep_next then
                RT.shipLog(string.format("[Engineering] Emergency power on cooldown -- %.0fs remaining.",
                    st.ep_next - now), "#FFAA00")
                return
            end
            st.ep_next       = now + 90
            st.pod_stability = math.min(100, st.pod_stability + 25)
            RT.shipLog(string.format("[Engineering] Emergency power rerouted -- pod stability +25 (now %.0f%%).",
                st.pod_stability), "#80FF80")
        end, 10)
    end)
end

local function _removePodUI()
    RT.forEachPlayer(function(p)
        if RT.valid(p) then
            p:removeCustom("w_ep_button")
            p:removeCustom("w_pod_status")
            p:removeCustom("w_pod_vitals")
        end
    end)
end

-- ── Resolve (called when phase "done" is entered) ─────────────────────────

function M.resolve(st)
    if st.broadcast_done then return end
    st.broadcast_done = true
    _removePodUI()
    RUMORS.removeCategory("WITNESS_BACKGROUND")
    RUMORS.removeCategory("WITNESS_HOOK")

    local reward, msg
    if st.kael_alive and not st.complied then
        reward = 600
        msg    = "Broadcast sent. Kael Voss survived. His evidence is on every channel in the Drift -- they can't unring this bell."
    elseif not st.kael_alive then
        reward = 400
        msg    = "Broadcast sent. Kael Voss didn't survive the transit, but his evidence did. The truth got out, carried by a dead man's data."
    else
        reward = 300
        msg    = "Broadcast sent. Kael is in Concord custody, but the evidence is now public. It may free him. It may not be enough."
    end

    local outcome = st.kael_alive and (st.complied and "broadcast_after_comply" or "kael_survived") or "broadcast_only"
    RT.addCredits(reward, "The Witness: " .. outcome)
    RT.shipLog("[The Witness] " .. msg .. " +" .. reward .. " cr.", "#80FF80")
    RT.flag("witness_complete", outcome)
    DIR.emit("witness_complete", {outcome=outcome, kael_alive=st.kael_alive, complied=st.complied}, "high")
    RT.setObjective("The Witness: complete", true)

    local buoy = RT.find(st.buoy_cs or "")
    if RT.valid(buoy) then buoy:setCanBeDestroyed(true) end

    globalMessage("The Witness -- arc complete. " .. msg, 15)
end

-- ── on_cancel: clean up spawned entities, UI, and injected rumors ────────

function M.on_cancel(st)
    local mira = RT.find("Mira's Luck")
    if RT.valid(mira) then mira:destroy() end
    st.pod_drain_on      = false
    st.checkpoint_fired  = false
    st.corsair_names     = {}
    st.concord_names     = {}
    _removePodUI()
    RUMORS.removeCategory("WITNESS_HOOK")
end

-- ── Phases ─────────────────────────────────────────────────────────────────

M.phases = {}

-- OFFER: Mira's Luck spawns near Port Vesper and hails the crew.
M.phases.offer = {
    enter = function(st)
        st.phase_entered = getScenarioTime()

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
                MISSIONS.phase("witness", "transit")
            end)
            addCommsReply("Not our problem.", function(s2, t2)
                setCommsMessage('"Your call. He won\'t last long without power."')
                addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
            end)
        end)

        -- Seed one-shot hook rumors so any NPC the crew hailes can point them to Port Vesper.
        -- These burn off on delivery (once=true) and are cleared when the crew accepts.
        RUMORS.add({ text = "Heard someone near Port Vesper is looking for an independent crew. Urgent cargo, won't go through Concord channels. Could be worth your time.", priority = 5, category = "WITNESS_HOOK", once = true })
        RUMORS.add({ text = "A contact docked at Port Vesper has been asking around for a fast ship with no affiliation. Something sensitive. Not the kind of job you post on a board.", priority = 5, category = "WITNESS_HOOK", once = true })
        RUMORS.add({ text = "Freighter crew said a woman near Port Vesper is sitting on a job she can't advertise. Independent crews only. She's been waiting a while.", priority = 5, category = "WITNESS_HOOK", once = true })

        -- Delayed hail: 3 s to avoid comms collision if player is already in a dialog.
        st.offer_hail_at = getScenarioTime() + 3
        globalMessage("Witness arc starting -- incoming hail in 3 seconds...", 3)
    end,

    update = function(st, delta, now)
        if st.offer_hail_at and now >= st.offer_hail_at then
            st.offer_hail_at = nil
            local mira = RT.find("Mira's Luck")
            if RT.valid(mira) then
                RT.hail(mira, "Independent vessel -- Mira Doss, Mira's Luck. I've got a private offer. Open comms when you're clear.", "Mira Doss")
            end
        end
    end,
}

-- TRANSIT: Crew carries the stasis pod toward Dustmote; pod drains reactor power.
M.phases.transit = {
    enter = function(st)
        st.phase_entered = getScenarioTime()
        st.pod_drain_on  = true
        _addPodButtons(st)
        _updatePanels(st)
        RUMORS.removeCategory("WITNESS_HOOK")  -- player has the job; clear the hook rumors
        RT.shipLog("[Stasis] Pod aboard -- Kael Voss in stasis. Destination: Dustmote Salvage.", "#A0C0FF")
        RT.shipLog("[Engineering] Pod drawing 5 energy/sec. Keep energy above 50% to maintain stability.", "#FFAA00")
        RT.setObjective("Reach Dustmote", true)
    end,

    update = function(st, delta, now)
        _podTick(st, delta)
        if now >= st.panel_next then
            st.panel_next = now + 5
            _updatePanels(st)
        end

        local ref = RT.nearestPlayer(0, 0)
        if not ref or not RT.valid(ref) then return end
        local px, py = ref:getPosition()
        -- Dustmote Salvage is at roughly (104, -36) in U.
        local dx, dy = px - 104000, py + 36000
        local dist_sq = dx * dx + dy * dy

        if not st.transit_warned and dist_sq < 70000 * 70000 then
            st.transit_warned = true
            RT.shipLog("[Comms] Heavy Concord traffic on the approach to Dustmote. Something has their attention out here.", "#FFAA00")
        end
        if not st.checkpoint_fired and dist_sq < 40000 * 40000 then
            st.checkpoint_fired = true
            MISSIONS.phase("witness", "checkpoint")
        end
    end,
}

-- CHECKPOINT: Concord blockade across the crew's path.
M.phases.checkpoint = {
    enter = function(st)
        st.phase_entered = getScenarioTime()
        st.concord_names = {}

        local ref = RT.nearestPlayer(0, 0)
        if not ref or not RT.valid(ref) then return end
        local px, py     = ref:getPosition()
        local heading    = ref:getHeading()
        local angle_rad  = math.rad(heading - 90)
        local cx         = px + math.cos(angle_rad) * 10000
        local cy         = py + math.sin(angle_rad) * 10000
        local perp_rad   = angle_rad + math.pi / 2

        local templates = {"MT52 Hornet", "MT52 Hornet", "MU52 Hornet", "MT52 Hornet", "MT52 Hornet"}
        for i = 1, 5 do
            local offset = (i - 3) * 2500
            local ship = CpuShip():setTemplate(templates[i]):setFaction("Concord")
            ship:setPosition(cx + math.cos(perp_rad) * offset,
                             cy + math.sin(perp_rad) * offset)
            ship:orderIdle():setCanBeDestroyed(true)
            RT.register(ship); DIR.registerKill(ship); DIR.allowControl(ship)
            st.concord_names[i] = ship:getCallSign()
        end

        local s1 = RT.find(st.concord_names[1])
        if not RT.valid(s1) then return end

        s1:setCommsFunction(function(src, tgt)
            setCommsMessage('"Independent vessel. Cut engines. You are carrying an unregistered stasis pod. Surrender it -- you will be free to go."')

            addCommsReply("We're on a licensed delivery. Nothing unusual aboard.", function(s_r, t_r)
                setCommsMessage('"Scan confirms the pod. You have 45 seconds to comply or we board by force."')
                st.checkpoint_choice = "stall"
                st.checkpoint_timer  = getScenarioTime() + 45
                addCommsReply("Fine. Take it.", function(s_r2, t_r2)
                    st.complied          = true
                    st.checkpoint_choice = "comply"
                    setCommsMessage('"Smart choice. On your way."')
                    addCommsReply("...", function(s_r3, t_r3) RT.stationComms(s_r3, t_r3) end)
                    RT.shipLog("[Checkpoint] Pod surrendered to Concord.", "#FF8080")
                    for _, n in ipairs(st.concord_names) do
                        local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
                    end
                    MISSIONS.phase("witness", "revealed")
                end)
                addCommsReply("Full burn -- break contact!", function(s_r2, t_r2)
                    st.checkpoint_choice = "run"
                    setCommsMessage('"All units -- pursue!"')
                    for _, n in ipairs(st.concord_names) do
                        local sc = RT.find(n)
                        if RT.valid(sc) and RT.valid(s_r) then sc:orderAttack(s_r) end
                    end
                end)
            end)

            addCommsReply("We're not stopping for anyone.", function(s_r, t_r)
                st.checkpoint_choice = "run"
                setCommsMessage('"All units -- pursue."')
                for _, n in ipairs(st.concord_names) do
                    local sc = RT.find(n)
                    if RT.valid(sc) and RT.valid(src) then sc:orderAttack(src) end
                end
            end)

            addCommsReply("Take the pod. We want no trouble.", function(s_r, t_r)
                st.complied          = true
                st.checkpoint_choice = "comply"
                setCommsMessage('"Transfer complete. On your way."')
                addCommsReply("...", function(s_r2, t_r2) RT.stationComms(s_r2, t_r2) end)
                RT.shipLog("[Checkpoint] Pod surrendered to Concord.", "#FF8080")
                for _, n in ipairs(st.concord_names) do
                    local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
                end
                MISSIONS.phase("witness", "revealed")
            end)
        end)

        RT.hail(s1, "Independent vessel. Cut engines. You are carrying an unregistered stasis pod. Concord inspection -- comply immediately.", "Concord Patrol")
        RT.shipLog("[Warning] Concord blockade on intercept -- five ships blocking our path.", "#FFAA00")
    end,

    update = function(st, delta, now)
        _podTick(st, delta)
        if now >= st.panel_next then
            st.panel_next = now + 5
            _updatePanels(st)
        end

        if st.checkpoint_choice == "stall" and st.checkpoint_timer > 0
                and now > st.checkpoint_timer then
            RT.shipLog("[Checkpoint] Time expired -- Concord boarded and took the pod.", "#FF8080")
            st.complied          = true
            st.checkpoint_choice = "comply"
            for _, n in ipairs(st.concord_names) do
                local sc = RT.find(n); if RT.valid(sc) then sc:orderIdle() end
            end
            MISSIONS.phase("witness", "revealed")

        elseif st.checkpoint_choice == "run" then
            local alive = false
            for _, n in ipairs(st.concord_names) do
                if RT.valid(RT.find(n)) then alive = true; break end
            end
            if not alive then
                RT.shipLog("[Checkpoint] Concord pursuit broken.", "#80FF80")
                MISSIONS.phase("witness", "revealed")
            end
        end
    end,
}

-- REVEALED: The pod transmits its secret or Mira's contact delivers it.
M.phases.revealed = {
    enter = function(st)
        st.phase_entered = getScenarioTime()
        local hp    = VERSE.places["Halcyon Rest"]
        local hloc  = hp and (" Grid " .. JOBS.gridRef(hp.x, hp.y) .. ", deep in the Shroud") or " (deep in the Shroud)"
        if st.complied then
            RT.shipLog('[Message] Dead-drop -- Mira\'s contact: "Concord got the pod, not the data. It\'s sewn into the outer casing -- check your cargo hold, they left it behind. Get to Halcyon Rest' .. hloc .. '. Find Sable. There\'s a public relay buoy. This isn\'t over."', "#A0C0FF")
        else
            RT.shipLog('[Stasis] Transmission from the pod: "My name is Kael Voss. I was a Concord logistics officer. What I know will end careers. Get me to Halcyon Rest' .. hloc .. ' -- there\'s a relay buoy there. One broadcast and it\'s over. Whatever she paid you, I\'ll double it."', "#A0C0FF")
        end
        RT.setObjective("Reach Halcyon Rest", true)
    end,

    update = function(st, delta, now)
        _podTick(st, delta)
        if now >= st.panel_next then
            st.panel_next = now + 5
            _updatePanels(st)
        end
        if now - st.phase_entered > 60 then
            MISSIONS.phase("witness", "shroud_run")
        end
    end,
}

-- SHROUD_RUN: Navigate to Halcyon Rest through the Shroud; Corsair ambush.
M.phases.shroud_run = {
    enter = function(st)
        st.phase_entered = getScenarioTime()
        st.corsair_names = {}
        local hp    = VERSE.places["Halcyon Rest"]
        local hloc  = hp and (" Grid " .. JOBS.gridRef(hp.x, hp.y)) or ""
        RT.shipLog("[Navigation] Entering the Shroud. Long-range sensors degrading -- watch for contacts. Halcyon Rest" .. hloc .. " is a neutral station inside the nebula.", "#C0C0C0")
        RT.setObjective("Reach Halcyon Rest", true)
    end,

    update = function(st, delta, now)
        _podTick(st, delta)
        if now >= st.panel_next then
            st.panel_next = now + 5
            _updatePanels(st)
        end

        -- Corsair ambush spawns 60 s into the phase.
        if #st.corsair_names == 0 and now - st.phase_entered > 60 then
            local ref = RT.nearestPlayer(0, 0)
            if ref and RT.valid(ref) then
                local px, py = ref:getPosition()
                local ang    = math.random() * 2 * math.pi
                local tmpls  = {"MT52 Hornet", "MT52 Hornet", "Adder MK5"}
                for i, tmpl in ipairs(tmpls) do
                    local s = CpuShip():setTemplate(tmpl):setFaction("Corsairs")
                    s:setPosition(px + math.cos(ang + (i-1) * 0.7) * (8000 + random(-1000, 1000)),
                                  py + math.sin(ang + (i-1) * 0.7) * (8000 + random(-1000, 1000)))
                    s:orderAttack(ref)
                    RT.register(s); DIR.registerKill(s); DIR.allowControl(s)
                    st.corsair_names[i] = s:getCallSign()
                end
                RT.shipLog("[Ambush] Corsairs -- " .. table.concat(st.corsair_names, ", ") .. ". Someone talked.", "#FF8080")
            end
        end

        -- Advance when near Halcyon Rest, or corsairs cleared, or 5-min timeout.
        local halcyon_e   = RT.find("Halcyon Rest")
        local near_halcyon = false
        if RT.valid(halcyon_e) then
            local hx, hy = halcyon_e:getPosition()
            local ref    = RT.nearestPlayer(hx, hy)
            if ref and RT.valid(ref) then
                local px, py = ref:getPosition()
                local dx, dy = px - hx, py - hy
                near_halcyon = dx * dx + dy * dy < 15000 * 15000
            end
        end

        local corsairs_alive = false
        for _, n in ipairs(st.corsair_names) do
            if RT.valid(RT.find(n)) then corsairs_alive = true; break end
        end

        if near_halcyon or (#st.corsair_names > 0 and not corsairs_alive)
                or now - st.phase_entered > 300 then
            MISSIONS.phase("witness", "halcyon")
        end
    end,
}

-- HALCYON: Dock at Halcyon Rest, find Sable; she directs crew to the relay buoy.
M.phases.halcyon = {
    enter = function(st)
        st.phase_entered = getScenarioTime()
        RT.setObjective("Dock: Halcyon Rest", true)

        local hx, hy = VERSE.at("Halcyon Rest", 8, 6)
        local buoy   = CpuShip():setTemplate("Flavia"):setFaction("Independent")
        buoy:setPosition(hx + random(-1500, 1500), hy + random(-1500, 1500))
        buoy:orderIdle()
        buoy:setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
        buoy:setWeaponTubeCount(0):setCanBeDestroyed(false)
        buoy:setCallSign("Public Relay " .. math.random(10, 99))
        RT.register(buoy)
        st.buoy_cs = buoy:getCallSign()

        local bx, by = buoy:getPosition()
        RT.shipLog("[Intel] Relay buoy: " .. st.buoy_cs .. " at grid " .. JOBS.gridRef(bx, by) .. ".", "#A0C0FF")

        RT.addStationHook("Halcyon Rest", function(source, target)
            if not RT.isPlayer(source) then return end
            if not source:isDocked(target) then return end
            if MISSIONS._cur_phase["witness"] ~= "halcyon" then return end
            addCommsReply("Ask for Sable.", function(s2, t2)
                if st.sable_warned then
                    setCommsMessage('"Sable checked out an hour ago. Left in a hurry -- Concord shuttle was asking after her."')
                    addCommsReply("We know where to go.", function(s3, t3)
                        RT.stationComms(s3, t3)
                        MISSIONS.phase("witness", "broadcast")
                    end)
                else
                    setCommsMessage('"She\'s here. Keeps looking at the docks."\n\nA message arrives from Sable: "Don\'t trust me. They have leverage. The broadcast still matters -- go to the relay buoy. Don\'t wait."')
                    st.sable_warned = true
                    addCommsReply("Head to the relay buoy.", function(s3, t3)
                        RT.stationComms(s3, t3)
                        MISSIONS.phase("witness", "broadcast")
                    end)
                end
            end)
        end)
    end,

    update = function(st, delta, now)
        _podTick(st, delta)
        if now >= st.panel_next then
            st.panel_next = now + 5
            _updatePanels(st)
        end

        -- Player reaches buoy directly (skipping Halcyon dock).
        local buoy = RT.find(st.buoy_cs or "")
        if RT.valid(buoy) then
            local bx, by = buoy:getPosition()
            local ref    = RT.nearestPlayer(bx, by)
            if ref and RT.valid(ref) then
                local px, py = ref:getPosition()
                local dx, dy = px - bx, py - by
                if dx * dx + dy * dy < 8000 * 8000 then
                    MISSIONS.phase("witness", "broadcast")
                    return
                end
            end
        end

        -- 5-min fallback in case crew skips Halcyon comms.
        if now - st.phase_entered > 300 then
            MISSIONS.phase("witness", "broadcast")
        end
    end,
}

-- BROADCAST: Hack the relay buoy reactor to 50%; Concord response inbound.
M.phases.broadcast = {
    enter = function(st)
        st.phase_entered = getScenarioTime()

        local buoy = RT.find(st.buoy_cs or "")
        if RT.valid(buoy) then
            local bx, by = buoy:getPosition()
            RT.shipLog("[Relay] " .. st.buoy_cs .. " at grid " .. JOBS.gridRef(bx, by) ..
                ". Relay: open the hacking panel and breach the reactor to 50% to trigger the broadcast.", "#A0C0FF")
            buoy:setCommsFunction(function(src, tgt)
                setCommsMessage('"Public Relay Node. Unauthorized access detected. This channel is Concord-licensed."')
            end)
        end

        local ref = RT.nearestPlayer(0, 0)
        if ref and RT.valid(ref) then
            local px, py = ref:getPosition()
            for i = 1, 3 do
                local s   = CpuShip():setTemplate("MT52 Hornet"):setFaction("Concord")
                local ang = ((i - 1) / 3) * 2 * math.pi + math.random() * 0.5
                s:setPosition(px + math.cos(ang) * 22000, py + math.sin(ang) * 22000)
                s:orderAttack(ref)
                RT.register(s); DIR.registerKill(s); DIR.allowControl(s)
            end
        end
        RT.shipLog("[Warning] Concord response inbound -- three ships. Hold them off while Relay completes the broadcast.", "#FF8080")
    end,

    update = function(st, delta, now)
        _podTick(st, delta)
        if now >= st.panel_next then
            st.panel_next = now + 5
            _updatePanels(st)
        end

        local buoy = RT.find(st.buoy_cs or "")
        if not RT.valid(buoy) then
            RT.shipLog("[Error] Relay buoy destroyed before broadcast -- arc failed.", "#FF8080")
            MISSIONS.phase("witness", "done")
        elseif buoy:getSystemHackedLevel("reactor") >= 0.5 then
            MISSIONS.phase("witness", "done")
        end
    end,
}

-- ── Register ────────────────────────────────────────────────────────────────

MISSIONS.register(M)

-- Inject background lore rumors about Concord accounting irregularities.
-- These cycle through the normal rumor pool (priority 1, recycled) as long as
-- the witness arc hasn't been completed. Removed in M.resolve when arc is done.
local _BACKGROUND_RUMORS = {
    "Heard Concord supply shipments to the Border don't match the manifests. Auditors found a discrepancy but nobody's saying how big.",
    "Logistics officer on Lumen got reassigned overnight. No explanation, no forwarding post. Just gone.",
    "Someone's cooking the books on Concord fleet contracts. Millions unaccounted for. Inspector started asking questions and got transferred.",
    "Freighter captain said Concord's requisition numbers don't add up. Ten ships ordered, eight delivered, full payment cleared. Who got paid for the missing two?",
    "Dockmaster said a Concord logistics officer, name of Voss, put in for extended leave last month. Hasn't been seen since.",
    "Concord Waypoint Galen's fuel reserves are 30% under logged capacity. Somebody's been skimming for years.",
    "Administrator on Lumen retired early. Rumor is they found something in his files and offered him a quiet exit.",
    "Heard Concord's internal audit division got disbanded. New policy: contractors handle reviews now. That's not suspicious at all.",
    "Freighter crew said they delivered construction materials to a Concord station that doesn't exist on the charts. Payment cleared, though.",
    "Someone leaked partial Concord budget files to the independent net. Numbers don't match official reports by 40 million credits. Files disappeared an hour later.",
}
for _, text in ipairs(_BACKGROUND_RUMORS) do
    RUMORS.add({ text = text, priority = 1, category = "WITNESS_BACKGROUND" })
end
