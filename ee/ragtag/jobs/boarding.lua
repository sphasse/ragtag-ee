-- ee/ragtag/jobs/boarding.lua
-- Boarding job type: disable a target ship and send a boarding party.

local _ARCHETYPES = {
    -- Any faction
    {cargo="a stolen data core", short_offer="Board a Corsair data thief",
     faction_label="Corsair data thief", reward_mult=1.2, tier_min=0,
     lore="A Corsair runner lifted survey data from a prospecting team. The owner wants it back quietly.",
     accept_msg='"Disable the ship and take back the core. Don\'t destroy it — the data might not survive the hull breach."',
     recv_msg='"Data core intact. You\'ve got a friend in this business."'},
    {cargo="a hijacked courier", short_offer="Rescue a captured courier crew",
     faction_label="captured Independent courier", reward_mult=1.4, tier_min=0,
     lore="An independent courier was pulled off their route — ship taken, crew still aboard.",
     accept_msg='"They\'re still alive. Disable the ship and get them out before the Corsairs move them."',
     recv_msg='"I thought that was it for me. Thank you."'},
    {cargo="a locked evidence container", short_offer="Intercept a smuggling run",
     faction_label="Corsair smuggler", reward_mult=1.1, tier_min=1,
     lore="A smuggler running contraband for a connected outfit. We want the evidence container — not the ship.",
     accept_msg='"Disable them cleanly. Destroy the ship and the evidence chain breaks."',
     recv_msg='"Chain of custody intact. Well done."'},
    {cargo="a Corsair lieutenant", short_offer="Capture a Corsair officer",
     faction_label="Corsair officer", reward_mult=1.5, tier_min=1,
     lore="Mid-level Corsair officer moving between cells. Intelligence wants them alive for questioning.",
     accept_msg='"Disable the escort — light ship, fast. Board carefully."',
     recv_msg='"We\'ll take custody from here. What they know is worth more than you\'d guess."'},
    {cargo="a corporate defector", short_offer="Stop a fleeing operative",
     faction_label="corporate operative", reward_mult=1.6, tier_min=2,
     lore="A corporate operative who knows too much tried to disappear. The parent company wants them back with the financial records.",
     accept_msg='"Disable the ship before they can vent the data. Board fast."',
     recv_msg='"Asset secured and records intact. Discretion noted."'},
    {cargo="a crew in distress", short_offer="Rescue a boarded crew",
     faction_label="Corsair-boarded vessel", reward_mult=1.3, tier_min=0,
     lore="A civilian ship was boarded and the Corsairs are still aboard. The original crew is hostage.",
     accept_msg='"Disable the ship. The original crew is locked in the hold — board fast and get them out."',
     recv_msg='"All crew accounted for. You got there in time."'},
    {cargo="a Corsair accountant", short_offer="Capture a Corsair financier",
     faction_label="Corsair financial operative", reward_mult=1.5, tier_min=1,
     lore="A Corsair accountant who moves money between cells is transiting through this sector.",
     accept_msg='"Disable the ship and board before they can destroy their records. They\'re worth more talking."',
     recv_msg='"Accountant in custody. The financial records are intact."'},
    {cargo="a diplomatic hostage", short_offer="Rescue a diplomat",
     faction_label="hostage-taking vessel", reward_mult=1.6, tier_min=2,
     lore="A low-level diplomat was taken as leverage in a negotiation that's about to go badly wrong.",
     accept_msg='"Disable the ship. The hostage is alive — keep them that way."',
     recv_msg='"Hostage secured and unharmed. The negotiation can resume from a better position."'},
    {cargo="a grey-market weapons shipment", short_offer="Intercept a grey weapons run",
     faction_label="grey-market weapons carrier", reward_mult=1.3, tier_min=1,
     lore="A weapons shipment moving through grey channels is heading for a buyer we'd rather not be armed.",
     accept_msg='"Disable the ship before delivery. Board and secure the cargo."',
     recv_msg='"Weapons secured. The buyer doesn\'t get their order."'},
    {cargo="an engineer we need to debrief", short_offer="Intercept a specific engineer",
     faction_label="ship carrying a needed engineer", reward_mult=1.4, tier_min=1,
     lore="An engineer who designed a sensitive system is aboard this ship. We need to debrief them.",
     accept_msg='"Disable the ship. The engineer is aboard — they\'re not a combatant."',
     recv_msg='"Engineer retrieved. The debrief can begin."'},
    {cargo="a Corsair-taken merchant captain", short_offer="Rescue a captured captain",
     faction_label="Corsair prize ship", reward_mult=1.3, tier_min=0,
     lore="A merchant captain was taken when their ship was seized. The owners want them back.",
     accept_msg='"Disable the prize ship. The captain is still aboard."',
     recv_msg='"Captain retrieved. They\'re rough around the edges but alive."'},
    {cargo="stolen identity documents", short_offer="Recover stolen identity papers",
     faction_label="identity document thief", reward_mult=1.2, tier_min=1,
     lore="A ship carrying stolen identity documents is heading for a buyer who will use them.",
     accept_msg='"Disable the ship and board before delivery. The documents are in the cargo hold."',
     recv_msg='"Documents recovered. The intended buyers go without."'},
    {cargo="a trafficker and their manifest", short_offer="Board a trafficking vessel",
     faction_label="trafficking vessel", reward_mult=1.6, tier_min=2,
     lore="A trafficking vessel is in transit. We need the manifest and the trafficker alive.",
     accept_msg='"Disable it cleanly. The people aboard have been through enough."',
     recv_msg='"Trafficker in custody. Manifest recovered. Victims are safe."'},
    {cargo="an informant who bolted", short_offer="Recover a fleeing informant",
     faction_label="informant who took the files", reward_mult=1.4, tier_min=1,
     lore="An informant got cold feet and left — with the files they were supposed to deliver.",
     accept_msg='"Disable their ship before they destroy the files. Board and retrieve both."',
     recv_msg='"Informant and files recovered. The crisis is contained."'},
    {cargo="a kidnapped technical specialist", short_offer="Rescue a kidnapped engineer",
     faction_label="kidnap vessel", reward_mult=1.5, tier_min=1,
     lore="A technical specialist was kidnapped from their station. The kidnappers are still in the sector.",
     accept_msg='"Disable the ship. The specialist is aboard — retrieve them unharmed."',
     recv_msg='"Specialist retrieved. They\'re shaken but unhurt."'},
    {cargo="stolen navigation archives", short_offer="Recover a stolen nav archive",
     faction_label="ship carrying stolen nav data", reward_mult=1.3, tier_min=1,
     lore="Proprietary navigation archives were stolen from a survey company. They're aboard this ship.",
     accept_msg='"Disable the ship and board before they can transmit the data."',
     recv_msg='"Archives recovered before transmission. The survey company is grateful."'},
    {cargo="a Corsair collection runner", short_offer="Stop a Corsair debt collector",
     faction_label="Corsair collection ship", reward_mult=1.2, tier_min=1,
     lore="A Corsair collection runner is bleeding a route of protection payments. Board the ship and end the arrangement.",
     accept_msg='"Disable the ship. We want the manifest of who they\'ve collected from."',
     recv_msg='"Manifest recovered. Several of those operators are going to be relieved."'},
    {cargo="a person who escaped custody", short_offer="Recapture an escaped prisoner",
     faction_label="vessel carrying an escaped prisoner", reward_mult=1.3, tier_min=1,
     lore="An escaped prisoner with a standing warrant is aboard this ship. Disable and board.",
     accept_msg='"Disable the ship. The prisoner must not reach a foreign station."',
     recv_msg='"Prisoner recaptured. Warrant closed."'},
    {cargo="a message courier who went silent", short_offer="Recover a missing courier",
     faction_label="courier who went dark", reward_mult=1.3, tier_min=1,
     lore="A message courier went dark mid-route. The ship is still moving — but something happened.",
     accept_msg='"Disable the ship gently. We don\'t know what\'s aboard or who\'s running it now."',
     recv_msg='"Courier recovered. The situation aboard was complicated. You did right."'},
    {cargo="a medical research subject", short_offer="Rescue an illegally transported person",
     faction_label="illegal transport ship", reward_mult=1.5, tier_min=2,
     lore="A medical research subject is being transported against their will. Disable the ship and recover them.",
     accept_msg='"The subject is in poor condition. Board carefully and get them out."',
     recv_msg='"Subject recovered and in medical care. The operators are answering questions."'},
    -- Concord stations only
    {cargo="a fugitive under warrant", short_offer="Take a fugitive alive",
     faction_label="fugitive under active warrant", reward_mult=1.2, tier_min=0, fac="Concord",
     lore="An armed fugitive with a warrant is fleeing. Concord needs them alive for questioning.",
     accept_msg='"Disable the ship. The fugitive must survive. Do not destroy it."',
     recv_msg='"Fugitive in custody. Warrant holds. You\'ll get the capture bonus."'},
    {cargo="a Corsair with classified intel", short_offer="Capture a Corsair intel carrier",
     faction_label="Corsair carrying Concord intel", reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A Corsair operative acquired classified Concord intelligence and is carrying it physically.",
     accept_msg='"Disable and board before they can destroy the documents. The intel must survive."',
     recv_msg='"Operative in custody. Intelligence recovered intact."'},
    {cargo="a corporate spy with stolen credentials", short_offer="Capture a credential thief",
     faction_label="corporate spy with stolen Concord credentials", reward_mult=1.4, tier_min=1, fac="Concord",
     lore="A corporate spy is operating on stolen Concord credentials and must be taken alive with the credentials.",
     accept_msg='"Disable the ship. Board and recover the credentials — and the spy."',
     recv_msg='"Spy in custody. Credentials recovered. Access revoked."'},
    {cargo="an illegally modified weapons ship", short_offer="Seize illegal weapons",
     faction_label="ship with illegal weapons modifications", reward_mult=1.3, tier_min=1, fac="Concord",
     lore="A ship with illegally modified weapons systems has been identified. We need to seize the ship and the evidence.",
     accept_msg='"Disable without destroying the weapons systems — we need them as evidence."',
     recv_msg='"Ship boarded. Illegal modifications documented. Evidence chain intact."'},
    {cargo="an unauthorized research operative", short_offer="Capture a rogue researcher",
     faction_label="unauthorized research vessel", reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A medical researcher running unauthorized trials is aboard this ship with their data.",
     accept_msg='"Disable and board. We need the researcher and their data. The subjects, if any, are Concord\'s responsibility."',
     recv_msg='"Researcher in custody. Data secured. Subject status confirmed."'},
    {cargo="a Concord deserter who took something", short_offer="Recover a deserter and what they took",
     faction_label="fleet deserter", reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A fleet deserter left with sensitive hardware. We need both the deserter and what they took.",
     accept_msg='"Disable the ship. Board and recover the hardware. The deserter comes along."',
     recv_msg='"Deserter in custody. Hardware recovered. Fleet security is intact."'},
    {cargo="a witness in a classified case", short_offer="Secure a key witness",
     faction_label="ship carrying a key witness", reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A witness to a classified incident is being moved without authorization. We need to intercept.",
     accept_msg='"Disable the ship. The witness is aboard — recover them before they reach their destination."',
     recv_msg='"Witness secured. The case can proceed."'},
    {cargo="a signals officer who sold Concord encryption", short_offer="Capture a traitor",
     faction_label="signals officer who sold encryption keys", reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A signals officer who sold Concord encryption keys is fleeing. They must be taken alive — and questioned.",
     accept_msg='"Disable and board. The officer must survive. We need the debrief."',
     recv_msg='"Officer in custody. Debrief scheduled. The encryption has been rotated."'},
    {cargo="a corporate executive fleeing charges", short_offer="Capture a fleeing executive",
     faction_label="executive fleeing war crimes charges", reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A corporate executive with a warrant for war crimes is fleeing Concord jurisdiction.",
     accept_msg='"Disable the ship. The executive must be taken alive and delivered to Concord custody."',
     recv_msg='"Executive in custody. The tribunal can proceed."'},
    {cargo="Concord cargo that went dark", short_offer="Recover a ship that vanished",
     faction_label="ship carrying Concord registered cargo that went dark", reward_mult=1.3, tier_min=1, fac="Concord",
     lore="A ship carrying Concord-registered cargo disappeared. It's been found — but isn't responding.",
     accept_msg='"Disable the ship. Board and secure the cargo. Find out what happened to the crew."',
     recv_msg='"Cargo secured. Crew situation reported. The investigation continues."'},
    {cargo="a tech specialist who stole Concord sensors", short_offer="Recover stolen sensor tech",
     faction_label="operative who stole Concord sensors", reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A tech specialist who stole Concord sensor arrays is carrying them aboard this ship.",
     accept_msg='"Disable and board. Recover the sensor arrays intact. The specialist comes along."',
     recv_msg='"Sensor arrays recovered. Specialist in custody."'},
    {cargo="an intelligence officer who switched sides", short_offer="Capture a turned operative",
     faction_label="intelligence officer who switched sides", reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A Concord intelligence officer has switched allegiance and is carrying operational knowledge.",
     accept_msg='"Disable the ship. The officer must be taken alive. What they know cannot be lost."',
     recv_msg='"Officer in custody. Damage assessment underway."'},
    {cargo="unauthorized access codes", short_offer="Secure unauthorized access codes",
     faction_label="ship with unauthorized access codes", reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A ship is carrying unauthorized access codes that can breach Concord secure facilities.",
     accept_msg='"Disable and board. The codes must be recovered before they can be used."',
     recv_msg='"Access codes recovered and deactivated. Breach averted."'},
    {cargo="a Corsair-turned informant in danger", short_offer="Extract an informant under threat",
     faction_label="Corsair-turned informant being burned", reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A Corsair informant has been made and is fleeing on a ship with Corsair pursuers close behind.",
     accept_msg='"Disable the informant\'s ship gently. Get them out before the Corsairs catch up."',
     recv_msg='"Informant extracted. They\'re safe. Good timing."'},
    {cargo="a war profiteer's sealed testimony", short_offer="Recover sealed testimony",
     faction_label="war profiteer with sealed testimony", reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A war profiteer is carrying sealed testimony that could implicate several Concord officials.",
     accept_msg='"Disable and board. The testimony is on board — recover it intact."',
     recv_msg='"Testimony recovered. The profiteer is in custody. The case builds."'},
    -- Independent stations only
    {cargo="a fence's client list", short_offer="Capture a fence",
     faction_label="fence with a valuable client list", reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A fence with connections to every grey-market operation in the sector is aboard this ship.",
     accept_msg='"Disable and board. The fence comes back with us. So does their client list."',
     recv_msg='"Fence in custody. Client list recovered. This opens a lot of doors."'},
    {cargo="a trapped passenger", short_offer="Rescue a passenger being held",
     faction_label="ship that won't let a passenger off", reward_mult=1.3, tier_min=0, fac="Independent",
     lore="A passenger boarded a ship and the crew won't let them disembark. Family filed a report.",
     accept_msg='"Disable the ship. The passenger is being held — get them out."',
     recv_msg='"Passenger recovered. They\'re not going to forget this."'},
    {cargo="a pirate first mate", short_offer="Capture a pirate officer",
     faction_label="pirate first mate with negotiating authority", reward_mult=1.4, tier_min=1, fac="Independent",
     lore="A pirate first mate with authority to negotiate on behalf of their captain is aboard this ship.",
     accept_msg='"Disable and board. The first mate comes back with us — alive and talking."',
     recv_msg='"First mate in custody. They\'re already negotiating."'},
    {cargo="a data broker who knows too much", short_offer="Take a data broker alive",
     faction_label="data broker who knows too much", reward_mult=1.4, tier_min=2, fac="Independent",
     lore="A data broker has been operating in this sector for years. They know things too many people want kept quiet.",
     accept_msg='"Disable and board. The broker comes back — and whatever they\'re carrying."',
     recv_msg='"Broker in custody. What they know is already proving useful."'},
    {cargo="cargo being moved without permission", short_offer="Recover stolen cargo",
     faction_label="ship carrying unauthorized cargo", reward_mult=1.2, tier_min=0, fac="Independent",
     lore="A ship is carrying someone else's cargo without authorization. The owner wants it back.",
     accept_msg='"Disable the ship and board. Recover the cargo and whatever documentation is aboard."',
     recv_msg='"Cargo recovered and documented. The owner is satisfied."'},
    {cargo="a loan shark's collection agent", short_offer="Stop a loan shark's collector",
     faction_label="loan shark's collection ship", reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A loan shark's collection agent is working this route, taking more than is owed.",
     accept_msg='"Disable the collection ship. Board and recover whatever they\'ve already collected."',
     recv_msg='"Collection agent in custody. Funds recovered. The debtors will be relieved."'},
    {cargo="someone running from the wrong people", short_offer="Extract someone from danger",
     faction_label="ship carrying a person being hunted", reward_mult=1.3, tier_min=1, fac="Independent",
     lore="Someone is being transported on a ship without realizing the people after them have already found them.",
     accept_msg='"Disable the ship gently. The person we want is aboard — so are the people hunting them."',
     recv_msg='"Person recovered. The hunters are dealt with. They\'re safe now."'},
    {cargo="laundered stolen goods", short_offer="Seize laundered merchandise",
     faction_label="ship laundering stolen goods", reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A ship is being used to launder stolen goods through a front-company manifest.",
     accept_msg='"Disable and board. Recover the goods and the manifest — we need the paper trail."',
     recv_msg='"Goods and manifest recovered. The paper trail leads somewhere interesting."'},
    {cargo="a Corsair defector heading our way", short_offer="Intercept a Corsair defector",
     faction_label="Corsair defector heading to independent space", reward_mult=1.4, tier_min=1, fac="Independent",
     lore="A Corsair defector is heading for independent space but has Corsair pursuers behind them.",
     accept_msg='"Disable the defector\'s ship before Corsairs do. Board and bring them in."',
     recv_msg='"Defector recovered. They\'re talking. The information is significant."'},
    {cargo="corporate debt enforcement records", short_offer="Stop a corporate collection team",
     faction_label="corporate debt enforcement ship", reward_mult=1.3, tier_min=2, fac="Independent",
     lore="A corporation sent a debt enforcement team into independent space to collect on contested debts.",
     accept_msg='"Disable the enforcement ship. Board and recover their mandate documentation."',
     recv_msg='"Enforcement team detained. Mandate documentation recovered. The debts are contested."'},
    {cargo="a hostage and a ransom record", short_offer="Rescue a hostage",
     faction_label="ship making ransom demands", reward_mult=1.5, tier_min=2, fac="Independent",
     lore="A ship is holding someone ransom and has been sending demands. We're not paying.",
     accept_msg='"Disable the ship. The hostage is aboard — board before they hurt them."',
     recv_msg='"Hostage rescued. Crew in custody. Ransom demand answered."'},
    {cargo="a smuggler carrying someone's life savings", short_offer="Capture a smuggler",
     faction_label="smuggler who took a passenger's savings", reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A smuggler took on a passenger under false pretenses and took their life savings for passage.",
     accept_msg='"Disable and board. The passenger is aboard — so are their savings, presumably."',
     recv_msg='"Passenger recovered. Savings mostly intact. The smuggler is answering for it."'},
    {cargo="a Hollow sympathizer recruiter", short_offer="Stop a Hollow recruiter",
     faction_label="Hollow sympathizer ship recruiting converts", reward_mult=1.5, tier_min=2, fac="Independent",
     lore="A Hollow sympathizer vessel has been boarding ships in the Rim and taking converts by force.",
     accept_msg='"Disable the ship. Board and recover anyone aboard against their will."',
     recv_msg='"Recruiter in custody. Six people recovered who did not choose to be there."'},
    {cargo="stolen medical supplies in a shortage", short_offer="Recover stolen medical supplies",
     faction_label="ship carrying stolen medical supplies during a shortage", reward_mult=1.3, tier_min=1, fac="Independent",
     lore="Medical supplies were stolen from a station in shortage. The thieves are still in the sector.",
     accept_msg='"Disable and board. Recover the supplies intact."',
     recv_msg='"Supplies recovered. The station will have what it needs."'},
    {cargo="a person who knows where a ship went", short_offer="Take a person of interest alive",
     faction_label="person of interest who knows a missing ship's fate", reward_mult=1.4, tier_min=2, fac="Independent",
     lore="A person who knows what happened to a missing ship is aboard this vessel. We need them talking.",
     accept_msg='"Disable and board. The person of interest must survive and come back with us."',
     recv_msg='"Person of interest in custody. They\'re talking. We\'ll know where the ship went."'},
}

local _TEMPLATES = {
    [0] = {"Adder MK5", "MT52 Hornet"},
    [1] = {"Phobos T3", "Adder MK5"},
    [2] = {"Phobos M3P", "Phobos T3"},
}

local M = {}
M.type      = "boarding"
M.weight    = 3
M.tier_min  = 2
M.type_mult = 1.8

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    local wx, wy, dist, region = ctx.spawnInVerse(rx, ry)
    if not wx then return nil end
    local nearby = ctx.nearbyStations(wx, wy, 150000)
    local filtered = {}
    for _, cs in ipairs(nearby) do
        if cs ~= ctx.station_cs then
            local e = ctx.findStation(cs)
            if ctx.valid(e) then
                local ok, fac = pcall(function() return e:getFaction() end)
                if ok and fac ~= "Hollow" and fac ~= "Corsairs" then
                    filtered[#filtered + 1] = cs
                end
            end
        end
    end
    return {
        origin         = ctx.station_cs,
        origin_faction = JOBS.stationFaction(ctx.station_cs),
        wx = wx, wy = wy,
        tier           = ctx.tier,
        distance_u     = dist,
        danger_level   = region and region.danger or 0,
        region_name    = region and region.name or nil,
        distance_min_u = ctx.distanceRange.min,
        distance_max_u = ctx.distanceRange.max,
        nearby_stations = filtered,
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
    local arch      = pool[math.random(#pool)]
    local templates = _TEMPLATES[tier] or _TEMPLATES[0]
    local reward = JOBS.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["boarding"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)

    local target_dest = nil
    if opts.nearby_stations and #opts.nearby_stations > 0 then
        target_dest = opts.nearby_stations[math.random(#opts.nearby_stations)]
    end

    return {
        id              = JOBS.nextId(),
        type            = "boarding",
        tier            = tier,
        origin          = opts.origin,
        wx              = opts.wx,
        wy              = opts.wy,
        cargo           = arch.cargo,
        reward          = reward,
        short           = arch.short_offer,
        obj             = "Locate and disable target",
        brief           = arch.lore .. "\n\n" .. arch.accept_msg
                          .. "\n\nTarget propulsion with beam weapons (Weapons station → system target: impulse) to disable without destroying. Once disabled, dock with the ship to board.",
        complete_msg    = arch.recv_msg,
        target_template = templates[math.random(#templates)],
        target_dest     = target_dest,
        distance_u      = opts.distance_u or 0,
        region_name     = opts.region_name,
        faction_label   = arch.faction_label,
        _spawned        = false,
        _attacking      = false,
        _disabled       = false,
        _boarded        = false,
        target_cs       = nil,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.warp1 + 900)
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    return string.format("* Disable and board a %s in %s.\n  %s", m.faction_label or "target", region, stats)
end

function M.spawn(m)
    if m._spawned then return end
    local dest_station = nil
    if m.target_dest then dest_station = RT.find(m.target_dest) end

    local s = CpuShip():setTemplate(m.target_template):setFaction("Unknown")
    local name = JOBS.corsairName()
    s:setCallSign(name)
    s:setPosition(m.wx + math.random(-2000, 2000), m.wy + math.random(-2000, 2000))
    s:setHull(s:getHullMax())
    for _, sys in ipairs({"impulse","reactor","beamweapons","missilesystem","maneuver","warp","jumpdrive","frontshield","rearshield"}) do
        s:setSystemHealth(sys, 1.0)
    end
    local mf = s:getShieldMax(0)
    local mr = s:getShieldMax(1)
    if mf > 0 then s:setShields(mf, mr) end
    s:setScanningParameters(1, 1)
    s.components.docking_bay = {external_dock_classes = {"Frigate"}}
    if dest_station and RT.valid(dest_station) then
        local dx, dy = dest_station:getPosition()
        s:orderFlyTowards(dx, dy)
    else
        s:orderRoaming()
    end
    RT.register(s)
    DIR.registerKill(s)
    DIR.allowControl(s)
    s:setCommsFunction(function(src, tgt)
        setCommsMessage('"Get away from us."')
    end)
    m.target_cs  = name
    m.short      = "Disable " .. name
    m.obj        = "Intercept " .. name
    m._spawned   = true
    m._attacking = false
end

function M.acceptLog(m)
    local heading_text = m.target_dest and (" heading toward " .. m.target_dest) or ""
    return string.format("Contract: %s. %dm to complete. %s last seen around %s%s.",
        m.short, math.floor(m._time_limit / 60),
        m.target_cs or "unknown", JOBS.gridRef(m.wx, m.wy), heading_text)
end

-- Surrender hail: the disabled target hails the crew with a line that fits the contract
-- (hostage-takers, cargo runners, data thieves, a person on the run). Chosen by keyword from the
-- archetype's cargo / label so every archetype gets flair without a per-archetype table.
local function _has(text, words)
    for _, w in ipairs(words) do
        if text:find(w, 1, true) then return true end
    end
    return false
end

local function _surrenderLine(m)
    local t = (tostring(m.cargo) .. " " .. tostring(m.faction_label)):lower()
    if _has(t, {"hostage", "crew in distress", "captain", "kidnap", "traffick", "passenger",
                "prisoner", "diplomat", "hijacked", "prize", "boarded", "research subject"}) then
        return '"Hold your fire! We give up. Nobody aboard has been hurt, and nobody will be. Come aboard and take them."'
    elseif _has(t, {"weapons", "shipment", "contraband", "smuggl", "transport", "cargo"}) then
        return '"That\'s enough. We give up. The cargo\'s sealed and untouched. Take it and let us go."'
    elseif _has(t, {"data", "nav", "record", "files", "client list", "testimony", "keys",
                    "credentials", "access codes", "sensors", "intel", "encryption", "evidence", "documents"}) then
        return '"You win. We give up. We haven\'t wiped anything, and we won\'t. It\'s all there. Just don\'t shoot."'
    elseif _has(t, {"officer", "operative", "defector", "informant", "spy", "fugitive", "deserter",
                    "executive", "engineer", "accountant", "lieutenant", "mate", "broker", "fence",
                    "thief", "courier", "agent", "runner"}) then
        return '"All right. I\'m done running. I give up, and I\'ll come quietly. Just keep your people off the triggers."'
    end
    return '"We give up. Engines are gone and so is our nerve. Come aboard, and don\'t shoot."'
end

local function _surrenderHail(m)
    local cs = m.target_cs
    local line = _surrenderLine(m)
    local function send()
        local tgt = RT.find(cs)
        if not RT.valid(tgt) or m._boarded then return true end
        return RT.hail(tgt, line, cs)
    end
    if send() then return end
    RT.after(15, function()
        if not send() then RT.shipLog("[" .. cs .. "] " .. line, "#FFCC80") end
    end, "boarding_surrender_retry_" .. tostring(cs))
end

function M.update(m, entry, ctx)
    if m._boarded then return nil end

    local target = RT.find(m.target_cs)

    if not m._disabled then
        if not RT.valid(target) then
            RT.shipLog("[Boarding] Target destroyed before boarding -- contract lost.", "#FF8080")
            return "remove"
        end

        if not m._attacking then
            for _, p in ipairs(RT.players) do
                if RT.valid(p) and RT.dist(target, p) < 8000 then
                    target:setFaction("Corsairs")
                    target:orderAttack(p)
                    m._attacking = true
                    RT.shipLog("[Target] " .. m.target_cs .. " detected our approach and is engaging!", "#FF8080")
                    break
                end
            end
        end

        local impulse_h = target:getSystemHealth("impulse") or 1
        local hull_pct  = target:getHull() / target:getHullMax()
        if impulse_h < 0.3 or hull_pct < 0.25 then
            m._disabled = true
            RT.addReputation("Corsairs", -100, "boarded " .. m.target_cs)
            target:setCanBeDestroyed(false)
            target:orderIdle()
            -- Switch faction away from Corsairs so the player's dock button is not blocked by enemy-faction check.
            target:setFaction("Independent")
            local cs = m.target_cs
            target:setCommsFunction(function(src, tgt)
                setCommsMessage(string.format('[%s] Engines are gone. We surrender. Close to within 1U and request docking to board.', cs))
                addCommsReply("Understood. Stand by.", function() setCommsMessage("Channel open.") end)
            end)
            m.obj = "Dock with " .. m.target_cs
            RT.shipLog("[Target] " .. m.target_cs .. " disabled. Close to within 1U and request docking to board.", "#FFCC80")
            JOBS.updateObj()
            RT.after(3, function() _surrenderHail(m) end, "boarding_surrender_" .. tostring(cs))
        end
    end

    -- Phase 2: watch for the player to dock with the disabled target.
    if m._disabled and not m._boarded then
        for _, p in ipairs(RT.players) do
            if RT.valid(p) and p:isDocked(target) then
                m._boarded = true
                m.obj = "Return " .. m.cargo .. " to " .. m.origin
                RT.shipLog("[Boarding] " .. m.cargo .. " secured. Return to " .. m.origin .. ".", "#80FF80")
                JOBS.updateObj()
                break
            end
        end
    end
    return nil
end

function M.completable(m, cs)
    return m.origin == cs and m._boarded == true
end

function M.cleanup(m)
    if m.target_cs then
        local s = RT.find(m.target_cs)
        if RT.valid(s) then
            RT.cancelKillTracking(s)
            s:setCanBeDestroyed(true)
            s:destroy()
        end
    end
end

function M.completeReply(m, entry)
    return {
        label = string.format("Deliver %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Good boarding."',
    }
end

JOBS.register(M)
