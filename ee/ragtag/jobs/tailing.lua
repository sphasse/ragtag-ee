-- ee/ragtag/jobs/tailing.lua
-- Tailing job type: shadow a ship to a covert meeting; scan both vessels.

local _ARCHETYPES = {
    -- Any faction
    {cargo="traffic analysis", short_offer="Surveil a suspected courier",
     reward_mult=1.0, tier_min=0,
     lore="Someone is moving information through this sector on an irregular route. We need to know who they're meeting.",
     accept_msg='"Find it and follow — not too close. Their sensors pick up ships or probes within 10U. When it meets its contact, we want full scan data on both ships."',
     recv_msg='"Contact identified. This is more than we hoped for."'},
    {cargo="a contact identification", short_offer="Identify a mystery ship's contact",
     reward_mult=1.0, tier_min=0,
     lore="A ship operating without a registered route has been spotted twice. Someone is meeting it out here.",
     accept_msg='"Follow it but stay back. Sensors pick up ships or probes within 10U. Scan both vessels when they meet."',
     recv_msg='"Got the ID. You\'ve answered a question we\'ve been asking for months."'},
    {cargo="rendezvous confirmation", short_offer="Confirm a covert rendezvous",
     reward_mult=1.1, tier_min=1,
     lore="Intelligence points to a handoff happening in deep space. We need confirmation — no intercept, just eyes on.",
     accept_msg='"Eyes only. Stay back beyond 10U. Scan both ships at the meeting and keep your probes stowed."',
     recv_msg='"Confirmed. This closes the loop on a three-month investigation."'},
    {cargo="a defector sighting", short_offer="Locate a missing operative",
     reward_mult=1.3, tier_min=1,
     lore="A former analyst went dark six weeks ago. Last known heading puts them somewhere in this sector.",
     accept_msg='"Find it and follow at distance — they\'ll bolt if they spot us. Scan both ships when the meeting happens."',
     recv_msg='"Both names confirmed. This is sensitive — we\'ll handle it from here."'},
    {cargo="supply chain evidence", short_offer="Trace a contraband supply run",
     reward_mult=1.4, tier_min=2,
     lore="Someone is running contraband through unregistered drops. We've traced the route to this sector.",
     accept_msg='"Follow it to the handoff. Stay outside 10U at all times. Full scan data on both ships."',
     recv_msg='"Supply chain mapped. This reaches further up than we thought."'},
    {cargo="a broker identification", short_offer="Identify an anonymous broker",
     reward_mult=1.1, tier_min=0,
     lore="A broker running grey-market cargo has been operating anonymously for two years. We need a face and a ship.",
     accept_msg='"Follow it without spooking it. When it meets the buyer, scan both. Stay outside 10U."',
     recv_msg='"Broker identified. Two years of anonymity, gone."'},
    {cargo="a meeting location record", short_offer="Establish a covert meeting point",
     reward_mult=1.0, tier_min=0,
     lore="We know two ships meet regularly but we don't know where. Follow one to find out.",
     accept_msg='"Track it to the meeting. Stay back. Scan both ships when you find the spot."',
     recv_msg='"Location logged. We know where they meet now."'},
    {cargo="crew verification data", short_offer="Confirm a crew member's real identity",
     reward_mult=1.1, tier_min=0,
     lore="A crew member on this ship has a registered name that doesn't match any face in the system.",
     accept_msg='"Follow the ship to its next meeting. Scan both vessels — we need biometric confirmation."',
     recv_msg='"Identity confirmed. The name was false, as we suspected."'},
    {cargo="a cargo inspection report", short_offer="Document what a ship is carrying",
     reward_mult=1.0, tier_min=0,
     lore="A ship with a suspicious manifest is heading somewhere. Follow it and see what it actually delivers.",
     accept_msg='"Don\'t intercept — just watch. Scan both ships at the handoff."',
     recv_msg='"Cargo documented. The manifest was completely fabricated."'},
    {cargo="a debt collection lead", short_offer="Skip-trace a debtor",
     reward_mult=1.0, tier_min=0,
     lore="Someone owes money and has been moving to avoid collection. We need to know who they're meeting.",
     accept_msg='"Follow them without making contact. We want the full picture before we move."',
     recv_msg='"Contact found. Now we know who to talk to."'},
    {cargo="a transfer confirmation", short_offer="Confirm a meeting took place",
     reward_mult=1.1, tier_min=0,
     lore="A deal was supposed to happen this week. We need confirmation that both parties showed up.",
     accept_msg='"Just eyes on. If the meeting happens, scan both ships. Stay out of sensor range."',
     recv_msg='"Confirmed. Both parties were there. The deal went through."'},
    {cargo="a shipping pattern analysis", short_offer="Map a recurring route",
     reward_mult=1.0, tier_min=0,
     lore="A ship on an irregular route has been spotted three times. We think we've predicted the next meeting.",
     accept_msg='"Follow it to the rendezvous. Scan both vessels. Stay outside 10U."',
     recv_msg='"Route confirmed. We can predict the next meeting too."'},
    {cargo="a second-tier network map", short_offer="Map a contact's contacts",
     reward_mult=1.2, tier_min=1,
     lore="We know the broker. We don't know who the broker works for. Follow and find out.",
     accept_msg='"We\'re going up the chain. Follow without being seen. Scan at the meeting."',
     recv_msg='"Second tier identified. The chain goes higher than we expected."'},
    {cargo="identity verification data", short_offer="Confirm a false name is in use",
     reward_mult=1.1, tier_min=0,
     lore="A ship registered under one name is being operated by someone using another. We need proof.",
     accept_msg='"Follow to the meeting. Scan both ships. We need biometric data."',
     recv_msg='"False registration confirmed. We have the real name."'},
    {cargo="a meeting attendance record", short_offer="Document who showed up",
     reward_mult=1.0, tier_min=0,
     lore="A meeting was arranged through a cutout. We want to know which principals actually attended.",
     accept_msg='"Follow the ship. Stay at distance. Scan everyone at the meeting."',
     recv_msg='"Attendees documented. Two expected, three actual."'},
    {cargo="a handoff record", short_offer="Document a covert handoff",
     reward_mult=1.1, tier_min=1,
     lore="Something is changing hands. We don't need to know what — just who.",
     accept_msg='"Stay back outside 10U. When the meeting happens, scan both ships."',
     recv_msg='"Handoff confirmed. We have both identities."'},
    {cargo="a route verification report", short_offer="Verify a ship's true destination",
     reward_mult=1.0, tier_min=0,
     lore="A ship filed a route to one place. We think it's going somewhere else. Follow and find out.",
     accept_msg='"Don\'t interfere. Just watch where it goes and who it meets."',
     recv_msg='"Destination confirmed. The filed route was a cover."'},
    {cargo="a deal confirmation report", short_offer="Confirm a deal was completed",
     reward_mult=1.1, tier_min=0,
     lore="A deal was arranged. The client wants to know if both sides followed through.",
     accept_msg='"Shadow the ship to the meeting. Scan both parties. Don\'t get within 10U."',
     recv_msg='"Deal confirmed complete. Both parties delivered."'},
    {cargo="a surveillance gap map", short_offer="Identify a sensor blind spot",
     reward_mult=1.2, tier_min=1,
     lore="A ship consistently meets its contact in a specific corridor. We think it knows where sensor coverage drops.",
     accept_msg='"Follow it to the meeting spot. Note the coordinates. Scan both ships."',
     recv_msg='"Meeting location noted. That corridor has a six-minute coverage gap."'},
    {cargo="a post-dock movement record", short_offer="Track a ship after docking",
     reward_mult=1.1, tier_min=0,
     lore="A ship docked here briefly and left without filing a route. We want to know where it went.",
     accept_msg='"It\'s already moving. Find it and follow it to the meeting. Scan both ships."',
     recv_msg='"Destination and contact confirmed. Now we know."'},
    -- Concord stations only
    {cargo="an operative's handler identification", short_offer="Identify a field handler",
     reward_mult=1.4, tier_min=1, fac="Concord",
     lore="A Concord field operative has been meeting an unregistered contact. We need to know who the handler is.",
     accept_msg='"Follow the operative. Don\'t get within 10U. Scan both ships at the meeting."',
     recv_msg='"Handler identified. This is a significant find."'},
    {cargo="a Corsair logistics link", short_offer="Trace Corsair supply lines",
     reward_mult=1.4, tier_min=1, fac="Concord",
     lore="A supply ship is believed to be resupplying Corsair operations. We need to see the handoff.",
     accept_msg='"Follow it to the contact. Stay back. Scan both ships when they meet."',
     recv_msg='"Supply link confirmed. We can intercept the next delivery."'},
    {cargo="a judicial contact record", short_offer="Surveil an off-books meeting",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A Concord judge has been meeting an unregistered ship. The meetings don't appear in any official log.",
     accept_msg='"This is extremely sensitive. Stay well outside 10U. Scan both vessels."',
     recv_msg='"Both ships identified. This goes to the tribunal."'},
    {cargo="an arms transfer midpoint", short_offer="Locate an arms handoff site",
     reward_mult=1.4, tier_min=1, fac="Concord",
     lore="Weapons are moving through this sector via an intermediary we haven't identified. Follow the middleman.",
     accept_msg='"Follow the ship to the handoff. Scan both parties. Stay back."',
     recv_msg='"Handoff location and both identities confirmed. The transfer chain is broken."'},
    {cargo="an informant status check", short_offer="Verify an informant is intact",
     reward_mult=1.3, tier_min=1, fac="Concord",
     lore="An informant inside a Corsair cell hasn't reported in. We need to confirm they're still in place.",
     accept_msg='"Follow the ship that should be their handler. If the meeting happens, scan both."',
     recv_msg='"Informant confirmed at the meeting. They\'re still in place."'},
    {cargo="a deserter's new identity data", short_offer="Track a fleet deserter",
     reward_mult=1.3, tier_min=1, fac="Concord",
     lore="A fleet deserter is operating under a new identity. Follow their ship to confirm who they're meeting.",
     accept_msg='"They know how to avoid detection. Stay outside 10U and keep your probes stowed."',
     recv_msg='"New identity confirmed. We have the name."'},
    {cargo="a contractor's secondary contract", short_offer="Identify a contractor's second client",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A Concord contractor is believed to be working for a second client. We need to identify them.",
     accept_msg='"Follow the contractor to their next meeting. Scan both ships. No approach."',
     recv_msg='"Second client identified. This is a significant conflict of interest."'},
    {cargo="an official's private meeting record", short_offer="Document an unofficial meeting",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A senior Concord official has been meeting ships that don't appear in their schedule.",
     accept_msg='"This is sensitive. Stay beyond 10U. Full scan data on both vessels."',
     recv_msg='"Meeting documented. The official will have some explaining to do."'},
    {cargo="a leak investigation report", short_offer="Identify an information leak",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="Classified information has been reaching outside parties. We need to identify the source.",
     accept_msg='"Follow the suspected leaker to their next drop. Scan both ships."',
     recv_msg='"Source confirmed. The leak is closed."'},
    {cargo="a protected witness's new contacts", short_offer="Map a witness's new network",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A protected witness has been making unauthorized contacts. We need to know who.",
     accept_msg='"Follow them to the meeting. Scan both ships. This could compromise the case."',
     recv_msg='"Contact identified. The witness has been compromised."'},
    {cargo="a Corsair captain's legitimate business contact", short_offer="ID a Corsair's front operation",
     reward_mult=1.3, tier_min=1, fac="Concord",
     lore="A known Corsair captain has been meeting a ship registered to a legitimate business. We need to identify the front.",
     accept_msg='"Follow the Corsair vessel to the meeting. Scan both ships."',
     recv_msg='"Front company identified. The legitimate business is a fiction."'},
    {cargo="an officer's off-record relationship", short_offer="Document a compromising contact",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="An officer has been meeting a ship with no registered connection to Concord. The meetings are personal.",
     accept_msg='"This is sensitive. We need confirmation of the contact. Scan both ships at the meeting."',
     recv_msg='"Contact confirmed. The officer has some explaining to do."'},
    {cargo="neutral-space contract evidence", short_offer="Observe a secret negotiation",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A negotiation between two parties is taking place in neutral space. We need confirmation of who is involved.",
     accept_msg='"Stay well outside 10U. Scan both ships when they meet."',
     recv_msg='"Both parties identified. The negotiation is real."'},
    {cargo="a defector debrief location", short_offer="Find where a debrief will happen",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A defector is meeting their handlers. We need the location and confirmation of who is running them.",
     accept_msg='"Follow the defector\'s ship. Scan both parties at the meeting."',
     recv_msg='"Debrief location and handler confirmed."'},
    {cargo="a border inspector's external contacts", short_offer="Surveil a corrupt inspector",
     reward_mult=1.3, tier_min=1, fac="Concord",
     lore="A border checkpoint inspector has been meeting ships outside of official duty. We need to see who.",
     accept_msg='"Follow the inspector\'s personal ship to their next off-duty meeting. Scan both."',
     recv_msg='"Contact confirmed. The inspector is on someone\'s payroll."'},
    -- Independent stations only
    {cargo="a cargo origin trace", short_offer="Find where the cargo actually came from",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A ship is delivering cargo with a manifested origin that doesn't exist. Follow it back to find the real source.",
     accept_msg='"We\'re going backwards. Follow the ship to its next pickup. Scan both parties."',
     recv_msg='"Real origin confirmed. The manifest has been false for years."'},
    {cargo="a new distribution contact", short_offer="ID a smuggler's new partner",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A known smuggler has a new distribution partner. We need to know who they're working with.",
     accept_msg='"Follow the ship to the handoff. Stay back. Scan both vessels."',
     recv_msg='"New partner identified. We can work with this information."'},
    {cargo="an off-manifest pickup record", short_offer="Document an unauthorized pickup",
     reward_mult=1.1, tier_min=0, fac="Independent",
     lore="A ship picked up a container that wasn't on its manifest. We want to see where it came from.",
     accept_msg='"Follow it to its source. Scan both vessels at the meeting."',
     recv_msg='"Source confirmed. Now we know where the off-manifest cargo originates."'},
    {cargo="a competitor's route data", short_offer="Map a rival's shipping route",
     reward_mult=1.1, tier_min=0, fac="Independent",
     lore="A competing hauler has found a profitable route they're not sharing. Follow them and find out what it is.",
     accept_msg='"Follow without being spotted. When they meet their contact, scan both ships."',
     recv_msg='"Route confirmed. We can use this."'},
    {cargo="incident evidence", short_offer="Identify who ended a deal",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A deal went badly for someone we work with. A ship was involved. We want to know who it was meeting.",
     accept_msg='"Find the ship and follow it to its next contact. Scan both."',
     recv_msg='"Identity confirmed. Now we know who to hold responsible."'},
    {cargo="a station official's external relationship", short_offer="Catch a corrupt administrator",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A station official is believed to be on the payroll of a Corsair-connected operation. Follow their meetings.",
     accept_msg='"Follow the official\'s personal ship to any off-station meetings. Scan both parties."',
     recv_msg='"Contact confirmed. The official is compromised."'},
    {cargo="a fence's supply chain", short_offer="Map a fence's supplier network",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A fence with good connections has a supplier we want to identify. Follow the chain up.",
     accept_msg='"Follow to the next pickup. Stay back. Scan both ships at the meeting."',
     recv_msg='"Supplier identified. We can approach them directly now."'},
    {cargo="a missing pilot's last meeting", short_offer="Find a missing pilot's last contact",
     reward_mult=1.1, tier_min=0, fac="Independent",
     lore="A pilot went missing after a meeting that wasn't in their schedule. A second ship was involved.",
     accept_msg='"The other ship is still in the area. Follow it to its next contact. Scan both."',
     recv_msg='"Contact identified. We know who the pilot met before they disappeared."'},
    {cargo="a hidden asset location", short_offer="Locate a debtor's hidden assets",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A debtor claims to have nothing. They're lying. Follow their ship to find where they're hiding assets.",
     accept_msg='"Follow the ship to its next contact. We\'ll know where the cache is when we see who they meet."',
     recv_msg='"Contact and location confirmed. The debtor has been found out."'},
    {cargo="a transit inspector's identity", short_offer="ID the bent inspector",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="Someone is clearing unusual shipments through an official checkpoint. We need to know who.",
     accept_msg='"Follow the ship that always gets waved through. It\'ll lead us to the contact."',
     recv_msg='"Inspector identified. We know who to approach — or avoid."'},
    {cargo="a courier's dead drop location", short_offer="Find a courier's dead drop",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A message courier has been making stops that don't appear in their route log. We want to find the drop site.",
     accept_msg='"Follow them to the next unscheduled stop. Scan both ships at the meeting."',
     recv_msg='"Drop location confirmed. The courier has been using it for months."'},
    {cargo="a Corsair defector's new loyalty", short_offer="Confirm a defector's new side",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A Corsair defector claims to be working for us. We want independent confirmation of their contacts.",
     accept_msg='"Follow the defector\'s ship to its next meeting. Scan both parties."',
     recv_msg='"Contact confirmed. The defector is being truthful — or their contact is."'},
    {cargo="a Hollow artefact buyer's identity", short_offer="ID buyers of Hollow artefacts",
     reward_mult=1.4, tier_min=2, fac="Independent",
     lore="Someone is buying Hollow artefacts through intermediaries. We want to know who the final buyer is.",
     accept_msg='"Follow the ship carrying the artefacts. Don\'t approach. Scan both at the handoff."',
     recv_msg='"Final buyer identified. This is a significant find."'},
    {cargo="a black-market staging point", short_offer="Locate an auction staging site",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A black-market auction is being staged at an unknown location. A known middleman will lead us there.",
     accept_msg='"Follow the middleman to the staging point. Scan both ships when they meet."',
     recv_msg='"Staging location confirmed. The auction is already underway."'},
    {cargo="evidence of a missing ship's location", short_offer="Find where a missing ship went",
     reward_mult=1.4, tier_min=2, fac="Independent",
     lore="A ship disappeared with valuable cargo. Someone knows where it went. Follow them to find the connection.",
     accept_msg='"Follow the ship that was in the area when it disappeared. Scan at any meeting."',
     recv_msg='"Connection confirmed. We know what happened to the missing ship."'},
}

local _TEMPLATES = {
    [0] = {"Flavia P.Falcon"},
    [1] = {"Flavia P.Falcon", "Phobos T3"},
    [2] = {"Phobos T3", "Phobos M3P"},
}

local function _disperse(m)
    local available = {}
    for _, st in ipairs(VERSE.STATIONS) do
        if st.fac ~= "Corsairs" and st.fac ~= "Hollow" then
            available[#available + 1] = st.cs
        end
    end
    for i = #available, 2, -1 do
        local j = math.random(i); available[i], available[j] = available[j], available[i]
    end
    local tgt = RT.find(m.target_cs or "")
    if RT.valid(tgt) and #available >= 1 then
        local st = RT.find(available[1])
        if RT.valid(st) then
            local sx, sy = st:getPosition()
            tgt:setWarpDrive(true):setWarpSpeed(300)
            tgt:orderFlyTowardsBlind(sx, sy)
        end
    end
    local rdv = RT.find(m.rendezvous_cs or "")
    if RT.valid(rdv) and #available >= 2 then
        local st = RT.find(available[2])
        if RT.valid(st) then
            local sx, sy = st:getPosition()
            rdv:setWarpDrive(true):setWarpSpeed(300)
            rdv:orderFlyTowardsBlind(sx, sy)
        end
    end
end

local M = {}
M.type      = "tailing"
M.weight    = 3
M.tier_min  = 1
M.type_mult = 1.4

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    -- The meeting point is the full spawn distance; ships spawn at D/4 and D/2 from that point.
    local mx, my, dist, region = ctx.spawnInVerse(rx, ry)
    if not mx then return nil end
    return {
        origin         = ctx.station_cs,
        origin_faction = JOBS.stationFaction(ctx.station_cs),
        wx = mx, wy = my,   -- placeholder; spawn overwrites with target position
        mx = mx, my = my,
        tier           = ctx.tier,
        distance_u     = dist,
        danger_level   = region and region.danger or 0,
        region_name    = region and region.name or nil,
        distance_min_u = ctx.distanceRange.min,
        distance_max_u = ctx.distanceRange.max,
    }
end

function M.generate(opts)
    local tier = opts.tier or 0
    local sfac = opts.origin_faction
    local pool = {}
    for _, a in ipairs(_ARCHETYPES) do
        if (a.tier_min or 0) <= tier and (not a.fac or not sfac or a.fac == sfac) then
            pool[#pool + 1] = a
        end
    end
    if #pool == 0 then
        for _, a in ipairs(_ARCHETYPES) do
            if (a.tier_min or 0) <= tier and not a.fac then pool[#pool + 1] = a end
        end
    end
    if #pool == 0 then pool = _ARCHETYPES end
    local arch    = pool[math.random(#pool)]
    local templates = _TEMPLATES[tier] or _TEMPLATES[0]
    local target_template = templates[math.random(#templates)]
    local reward = JOBS.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["tailing"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)

    return {
        id               = JOBS.nextId(),
        type             = "tailing",
        tier             = tier,
        origin           = opts.origin,
        wx               = opts.wx,
        wy               = opts.wy,
        mx               = opts.mx,
        my               = opts.my,
        cargo            = arch.cargo,
        reward           = reward,
        short            = arch.short_offer,
        obj              = "Locate target",
        brief            = arch.lore .. "\n\n" .. arch.accept_msg
                           .. "\n\nThey'll detect a probe signature or any ship within weapons range — spook them before the meeting and the contract is lost.",
        complete_msg     = arch.recv_msg,
        target_template  = target_template,
        distance_u       = opts.distance_u or 0,
        region_name      = opts.region_name,
        _spawned         = false,
        _meeting         = false,
        _meeting_at      = nil,
        _scanned         = false,
        target_cs        = nil,
        rendezvous_cs    = nil,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.warp1 + 600)
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    return string.format("* Shadow a ship to a covert meeting in %s.\n  %s", region, stats)
end

function M.spawn(m)
    if m._spawned then return end
    local WARP1     = 500
    local SHIP_WARP = 125
    local RDV_WARP  = 250
    local D  = math.max(m.distance_u, 15000)
    local T  = D / WARP1
    local spawn_dist     = T * SHIP_WARP   -- D/4
    local rdv_spawn_dist = T * RDV_WARP    -- D/2

    local t_ang   = math.random() * 2 * math.pi
    local rdv_ang = t_ang + math.pi * 0.5 + math.random() * math.pi

    local tname = JOBS.corsairName()
    local twx = math.floor(m.mx + math.cos(t_ang) * spawn_dist)
    local twy = math.floor(m.my + math.sin(t_ang) * spawn_dist)
    local target = CpuShip():setTemplate(m.target_template):setFaction("Unknown")
    target:setCallSign(tname)
    target:setPosition(twx + math.random(-1000, 1000), twy + math.random(-1000, 1000))
    target:setRotation((270 - math.deg(t_ang)) % 360)
    target:setHull(target:getHullMax())
    target:setScanningParameters(1, 1)
    target:setWarpDrive(false):setImpulseMaxSpeed(SHIP_WARP)
    target:orderFlyTowardsBlind(m.mx, m.my)
    RT.register(target)
    target:setCommsFunction(function(src, tgt) setCommsMessage('"No response."') end)

    local rname = JOBS.freighterName()
    local rwx = math.floor(m.mx + math.cos(rdv_ang) * rdv_spawn_dist)
    local rwy = math.floor(m.my + math.sin(rdv_ang) * rdv_spawn_dist)
    local rendezvous = CpuShip():setTemplate("Flavia P.Falcon"):setFaction("Unknown")
    rendezvous:setCallSign(rname)
    rendezvous:setPosition(rwx, rwy)
    rendezvous:setRotation((270 - math.deg(rdv_ang)) % 360)
    rendezvous:setWarpDrive(false):setImpulseMaxSpeed(RDV_WARP)
    rendezvous:orderFlyTowardsBlind(m.mx, m.my)
    RT.register(rendezvous)
    rendezvous:setCommsFunction(function(src, tgt) setCommsMessage('"Move along."') end)

    -- Overwrite wx/wy with target's actual spawn position for the log hint.
    m.wx = twx
    m.wy = twy

    m.target_cs     = tname
    m.rendezvous_cs = rname
    m._meet_at      = getScenarioTime() + T
    m.short = "Surveil " .. tname
    m.obj   = "Locate " .. tname
    m._spawned = true
end

function M.acceptLog(m)
    local hdx = m.mx - m.wx
    local hdy = m.my - m.wy
    local heading_deg = math.floor((math.deg(math.atan(hdx, -hdy)) + 360) % 360 + 0.5)
    local t_min = math.max(1, math.floor((m._meet_at - getScenarioTime()) / 60 + 0.5))
    return string.format(
        "Contract: %s. %dm to complete. Target last spotted at %s heading %03d. We expect a rendezvous in ~%dm. Approach with care.",
        m.short, math.floor(m._time_limit / 60),
        JOBS.gridRef(m.wx, m.wy), heading_deg, t_min)
end

function M.update(m, entry, ctx)
    if m._scanned then return nil end  -- waiting for return

    local tgt = RT.find(m.target_cs or "")
    local rdv = RT.find(m.rendezvous_cs or "")

    if not m._meeting then
        if not RT.valid(tgt) then
            RT.shipLog("[Tailing] Target lost -- contract failed.", "#FF8080")
            return "remove"
        end

        -- Detection en route: player or probe within 10U spooks the target.
        local spook = nil
        for _, p in ipairs(RT.players) do
            if RT.valid(p) and RT.dist(p, tgt) < 10000 then
                spook = "target spotted the ship"; break
            end
        end
        if not spook then
            local tx, ty = tgt:getPosition()
            for _, obj in ipairs(getObjectsInRadius(tx, ty, 10000)) do
                if RT.valid(obj) and isObjectType(obj, "ScanProbe") then
                    spook = "target detected a probe"; break
                end
            end
        end
        if spook then
            RT.shipLog("[Tailing] Contract failed — looks like they got spooked. (" .. spook .. ")", "#FF8080")
            _disperse(m)
            return "remove"
        end

        -- Stall watchdog: re-issue fly orders every 20s.
        m._fly_refresh = m._fly_refresh or 0
        if ctx.now > m._fly_refresh then
            tgt:orderFlyTowardsBlind(m.mx, m.my)
            if RT.valid(rdv) then rdv:orderFlyTowardsBlind(m.mx, m.my) end
            m._fly_refresh = ctx.now + 20
        end

        -- Meeting: target and rendezvous within 1.5U.
        if RT.valid(rdv) and RT.dist(tgt, rdv) < 1500 then
            m._meeting    = true
            m._meeting_at = ctx.now
            tgt:orderIdle()
            rdv:orderIdle()
            local mx, my = tgt:getPosition()
            RT.shipLog("[Tailing] Meeting in progress at " .. JOBS.gridRef(mx, my)
                .. ". Science: scan both ships. 90 seconds.", "#FFCC80")
            m.obj = "Scan both ships at meeting"
            JOBS.updateObj()
        end

        -- Rendezvous deadline: 120s grace past T.
        if ctx.now > m._meet_at + 120 and not m._meeting then
            RT.shipLog("[Tailing] Ships completed their rendezvous unobserved. Contract failed.", "#FF8080")
            _disperse(m)
            return "remove"
        end

    else
        -- Meeting in progress: watch for detection.
        local spook = nil
        for _, p in ipairs(RT.players) do
            if RT.valid(p) and RT.valid(tgt) and RT.dist(p, tgt) < 10000 then
                spook = "ship got too close during the meeting"; break
            end
        end
        if not spook and RT.valid(tgt) then
            local tx, ty = tgt:getPosition()
            for _, obj in ipairs(getObjectsInRadius(tx, ty, 10000)) do
                if RT.valid(obj) and isObjectType(obj, "ScanProbe") then
                    spook = "probe detected during the meeting"; break
                end
            end
        end
        if spook then
            RT.shipLog("[Tailing] Contract failed — looks like they got spooked. (" .. spook .. ")", "#FF8080")
            _disperse(m)
            return "remove"
        end

        -- 90-second scan window.
        if ctx.now - m._meeting_at > 90 then
            RT.shipLog("[Tailing] Meeting ended — not scanned in time. Contract lost.", "#FF8080")
            _disperse(m)
            return "remove"
        end

        if RT.valid(tgt) and RT.valid(rdv) then
            for _, p in ipairs(RT.players) do
                if RT.valid(p) then
                    if not m._tgt_scanned then
                        local ok, s = pcall(function() return tgt:isScannedBy(p) end)
                        if ok and s then
                            m._tgt_scanned = true
                            RT.shipLog("[Tailing] " .. m.target_cs .. " identified. Scan the contact.", "#FFCC80")
                        end
                    end
                    if not m._rdv_scanned then
                        local ok, s = pcall(function() return rdv:isScannedBy(p) end)
                        if ok and s then
                            m._rdv_scanned = true
                            RT.shipLog("[Tailing] Contact ship " .. m.rendezvous_cs .. " identified.", "#FFCC80")
                        end
                    end
                    if m._tgt_scanned and m._rdv_scanned then
                        m._scanned = true
                        m.obj = "Return intel to " .. m.origin
                        local cx, cy = tgt:getPosition()
                        RT.shipLog("[Tailing] Both ships identified at " .. JOBS.gridRef(cx, cy)
                            .. ". Return to " .. m.origin .. ".", "#80FF80")
                        JOBS.updateObj()
                        _disperse(m)
                        return nil
                    end
                end
            end
        end
    end
    return nil
end

function M.expire(m)
    local tgt = RT.find(m.target_cs or "")
    local rdv = RT.find(m.rendezvous_cs or "")
    if RT.valid(tgt) then tgt:destroy() end
    if RT.valid(rdv) then rdv:destroy() end
    RT.shipLog("[Contract] " .. m.short .. " -- time expired. Contract lost.", "#FF8080")
    if m.origin_faction then
        RT.addReputation(m.origin_faction, -2 * m.reward, "failed: " .. m.short)
    end
    return true  -- suppress engine default
end

function M.completable(m, cs)
    return m.origin == cs and m._scanned == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Deliver %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Intel received."',
    }
end

JOBS.register(M)
