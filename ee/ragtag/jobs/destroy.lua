-- ee/ragtag/jobs/destroy.lua
-- Destroy job type: hunt and eliminate a hostile target ship.

local _ARCHETYPES = {
    -- Any faction
    {cargo="a bounty claim", short_offer="Collect a dead-or-alive bounty",
     faction_label="wanted Corsair", target_template="MT52 Hornet",
     reward_mult=1.0, tier_min=0,
     lore="A wanted Corsair with a dead-or-alive bounty. Last seen operating a fast raider.",
     accept_msg='"Destroy the target completely. No boarding, no survivors. We want proof."',
     recv_msg='"Target eliminated. Bounty posted to your account."'},
    {cargo="proof of destruction", short_offer="Destroy a rogue AI ship",
     faction_label="rogue AI drone", target_template="Adder MK5",
     reward_mult=1.1, tier_min=0,
     lore="An automated patrol ship malfunctioned and is broadcasting corrupted IFF codes. It's firing on friendlies.",
     accept_msg='"Eliminate the target. Do not attempt boarding — the AI is hostile to all organics."',
     recv_msg='"Threat neutralized. Wreckage retrieved for analysis."'},
    {cargo="a quarantine certificate", short_offer="Burn a plague ship",
     faction_label="quarantined freighter", target_template="Flavia P.Falcon",
     reward_mult=1.2, tier_min=1,
     lore="A freighter carrying an unstable bioweapon sample lost containment. The crew is dead or worse.",
     accept_msg='"Burn it out of space. Do not approach within 1U. Do not board. Complete destruction only."',
     recv_msg='"Contaminated hulk destroyed. Medical authority confirms clean burn."'},
    {cargo="combat telemetry", short_offer="Eliminate a raider captain",
     faction_label="Corsair raider captain", target_template="Phobos T3",
     reward_mult=1.3, tier_min=1,
     lore="A Corsair captain with fifteen raids to their name. Known for heavy armor and refusing surrender.",
     accept_msg='"No quarter. This one doesn\'t run and doesn\'t dock quietly."',
     recv_msg='"Captain confirmed KIA. The lanes just got safer."'},
    {cargo="a neutralization receipt", short_offer="Stop a false-IFF ship",
     faction_label="ship running false IFF codes", target_template="MT52 Hornet",
     reward_mult=1.0, tier_min=0,
     lore="A ship broadcasting false IFF codes has been luring vessels into ambushes.",
     accept_msg='"Destroy it before it takes another ship. Complete hull destruction."',
     recv_msg='"False-IFF threat eliminated. Two ships can navigate that corridor safely again."'},
    {cargo="salvage rights", short_offer="Clear a Corsair-held derelict",
     faction_label="Corsair crew holding a derelict", target_template="Adder MK5",
     reward_mult=1.1, tier_min=1,
     lore="A derelict that was a navigational hazard is now a pirate nest. The crew won't negotiate.",
     accept_msg='"Clear them out. The derelict reverts to salvage rights when they\'re gone."',
     recv_msg='"Derelict cleared. Salvage rights filed."'},
    {cargo="a data kill certificate", short_offer="Destroy a spy drone",
     faction_label="shipping data harvester drone", target_template="MT52 Hornet",
     reward_mult=1.1, tier_min=1,
     lore="A drone has been harvesting cargo and route data from shipping in the sector. Someone built it.",
     accept_msg='"Destroy it completely. The data dies with the hardware."',
     recv_msg='"Drone destroyed. Data collection confirmed terminated."'},
    {cargo="a supply disruption receipt", short_offer="Hit a Corsair supply ship",
     faction_label="Corsair supply freighter", target_template="Flavia P.Falcon",
     reward_mult=1.2, tier_min=1,
     lore="A Corsair supply ship keeps their raiding fleet operational in the sector. Cut the supply line.",
     accept_msg='"Destroy the freighter. Their fighters can\'t operate without resupply."',
     recv_msg='"Supply ship destroyed. Corsair activity in the sector should drop sharply."'},
    {cargo="a combat receipt", short_offer="Eliminate a warlord's escort",
     faction_label="warlord's escort vessel", target_template="Phobos T3",
     reward_mult=1.3, tier_min=2,
     lore="A warlord running a protection racket across three stations has a heavily armed escort.",
     accept_msg='"Destroy the escort. The warlord loses half their credibility with it."',
     recv_msg='"Escort destroyed. The warlord\'s next extortion attempt will be considerably less convincing."'},
    {cargo="a claims rights certificate", short_offer="Stop an armed claims jumper",
     faction_label="armed claims jumper", target_template="MT52 Hornet",
     reward_mult=1.0, tier_min=0,
     lore="An armed salvager has been jumping claims and shooting anyone who resists. They need to stop.",
     accept_msg='"They don\'t negotiate. Neither do we."',
     recv_msg='"Claims jumper eliminated. The salvage operators in this sector are safer."'},
    {cargo="a biohazard containment cert", short_offer="Destroy a containment-breach ship",
     faction_label="containment-breach freighter", target_template="Flavia P.Falcon",
     reward_mult=1.2, tier_min=1,
     lore="A freighter's cargo containment has failed. The ship is a biological hazard and cannot be boarded.",
     accept_msg='"Complete destruction only. Do not approach within 0.5U."',
     recv_msg='"Freighter destroyed. Containment zone cleared."'},
    {cargo="a signal kill certificate", short_offer="Destroy a Corsair relay ship",
     faction_label="Corsair comms relay ship", target_template="Adder MK5",
     reward_mult=1.2, tier_min=1,
     lore="A Corsair relay ship is coordinating raids across the sector. Destroy it and their comms go dark.",
     accept_msg='"Take out the relay ship. Their network goes with it."',
     recv_msg='"Relay ship destroyed. Corsair coordination in this sector is blind."'},
    {cargo="a mine clearance certificate", short_offer="Destroy a rogue mining drone",
     faction_label="rogue mining drone", target_template="MT52 Hornet",
     reward_mult=0.9, tier_min=0,
     lore="A mining drone lost its owner transponder and has been attacking any ship that enters its claim zone.",
     accept_msg='"It\'s an automated system. It won\'t respond to hails. Just destroy it."',
     recv_msg='"Drone destroyed. The navigation hazard is cleared."'},
    {cargo="a trafficking interdiction receipt", short_offer="Destroy a trafficking vessel",
     faction_label="trafficking vessel", target_template="Flavia P.Falcon",
     reward_mult=1.3, tier_min=2,
     lore="A ship running human trafficking has been identified. It's armed and will fight.",
     accept_msg='"Destroy the ship. There are no innocents aboard on this run."',
     recv_msg='"Vessel destroyed. That crew won\'t take another run."'},
    {cargo="a claims murder receipt", short_offer="Avenge a murdered crew",
     faction_label="murderous claims jumper", target_template="Adder MK5",
     reward_mult=1.2, tier_min=1,
     lore="A salvage crew was murdered for their claim. The killer is still in the area.",
     accept_msg='"They killed five people for a salvage claim. Make sure that was their last one."',
     recv_msg='"Target destroyed. Those five people have been accounted for."'},
    {cargo="a ram-ship neutralization cert", short_offer="Stop a ship rigged for ramming",
     faction_label="ship rigged for ramming", target_template="MT52 Hornet",
     reward_mult=1.4, tier_min=2,
     lore="A modified ship is heading toward a station, engines at maximum. It's not responding to hails.",
     accept_msg='"Stop it before it reaches the station. Complete destruction."',
     recv_msg='"Ram-ship destroyed. Station traffic is still unaware of how close that was."'},
    {cargo="a terrorism interdiction cert", short_offer="Destroy a terrorist vessel",
     faction_label="deep-space terrorist ship", target_template="Phobos T3",
     reward_mult=1.4, tier_min=2,
     lore="A faction operating in the Shroud has moved an armed ship into the shipping lanes.",
     accept_msg='"Eliminate the ship before it reaches a populated system. Complete destruction."',
     recv_msg='"Terrorist vessel destroyed. The threat is neutralized."'},
    {cargo="an execution receipt", short_offer="Execute a war criminal",
     faction_label="war criminal's vessel", target_template="Phobos T3",
     reward_mult=1.5, tier_min=2,
     lore="A war criminal thought dead for seven years has been spotted operating under a new name.",
     accept_msg='"They\'ve had seven years. End it."',
     recv_msg='"Target destroyed. Seven years of running is over."'},
    {cargo="a cult purge certificate", short_offer="Destroy a Hollow cult ship",
     faction_label="Hollow cult ship", target_template="Phobos M3P",
     reward_mult=1.5, tier_min=2,
     lore="A Hollow cult ship has been seizing civilian vessels and forcibly converting the crews.",
     accept_msg='"Destroy the ship. This isn\'t a negotiation — they don\'t speak to anyone who won\'t join."',
     recv_msg='"Cult ship destroyed. Three civilian ships can navigate this corridor safely again."'},
    {cargo="a black-ops confirmation", short_offer="Stop a defector reaching Hollow space",
     faction_label="Concord defector", target_template="Phobos M3P",
     reward_mult=1.5, tier_min=2,
     lore="A former officer stole classified files and is running for Hollow space. Eliminate before they cross the line.",
     accept_msg='"Target is armed, experienced, and knows you\'re coming. Total destruction. No witnesses."',
     recv_msg='"Target eliminated. Files unrecoverable. This conversation never happened."'},
    -- Concord stations only
    {cargo="a justice receipt", short_offer="Eliminate a fleeing fugitive",
     faction_label="fugitive under active warrant", target_template="Adder MK5",
     reward_mult=1.0, tier_min=0, fac="Concord",
     lore="An armed fugitive with a standing warrant is running and has fired on a pursuit vessel.",
     accept_msg='"Warrant is dead-or-alive. Destroy the ship."',
     recv_msg='"Target destroyed. Warrant closed."'},
    {cargo="a warhead recovery cert", short_offer="Destroy a ship with a stolen warhead",
     faction_label="ship carrying a stolen Concord warhead", target_template="Phobos T3",
     reward_mult=1.6, tier_min=2, fac="Concord",
     lore="A Concord warhead was stolen from a depot. The ship carrying it cannot be allowed to deliver its payload.",
     accept_msg='"Complete destruction. The warhead detonates on hull breach — maintain 2U distance."',
     recv_msg='"Ship destroyed. Warhead rendered inert by the detonation. Crisis averted."'},
    {cargo="a classification purge receipt", short_offer="Destroy a Corsair with Concord intel",
     faction_label="Corsair carrying classified intel", target_template="Phobos T3",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A Corsair acquired classified Concord intelligence. The data cannot be allowed to propagate.",
     accept_msg='"Destroy the ship. The data dies with it."',
     recv_msg='"Target destroyed. Classification breach contained."'},
    {cargo="a vessel recovery cert", short_offer="Destroy a stolen fleet vessel",
     faction_label="stolen Concord vessel", target_template="Adder MK5",
     reward_mult=1.2, tier_min=1, fac="Concord",
     lore="A Concord patrol vessel was stolen and is now being operated by hostiles.",
     accept_msg='"We can\'t recover it. Destroy it before it\'s used against us."',
     recv_msg='"Stolen vessel destroyed. Hull confirmed as registry match."'},
    {cargo="a bio-interdiction cert", short_offer="Destroy a bioweapons carrier",
     faction_label="bioweapon carrier", target_template="Flavia P.Falcon",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A ship carrying biological weapons is heading toward a populated station. It cannot be boarded.",
     accept_msg='"Complete destruction. Do not approach. The payload is not survivable."',
     recv_msg='"Carrier destroyed. Bio-threat neutralized."'},
    {cargo="a termination receipt", short_offer="Eliminate a rogue Concord contractor",
     faction_label="rogue Concord contractor", target_template="Adder MK5",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A Concord contractor has gone off-contract and is selling information to opposition parties.",
     accept_msg='"They know too much to be left active. Destroy the ship."',
     recv_msg='"Contractor eliminated. The information leak is closed."'},
    {cargo="a decommission certificate", short_offer="Destroy an illegally reactivated vessel",
     faction_label="illegally reactivated vessel", target_template="Phobos T3",
     reward_mult=1.2, tier_min=1, fac="Concord",
     lore="A decommissioned Concord vessel was illegally reactivated and is operating in restricted space.",
     accept_msg='"It should have been scrapped. Finish the job."',
     recv_msg='"Vessel destroyed. Decommission completed."'},
    {cargo="a command neutralization cert", short_offer="Destroy a pirate command ship",
     faction_label="pirate command vessel", target_template="Phobos M3P",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="The command vessel coordinating Corsair raids throughout the region has been identified.",
     accept_msg='"Destroy the command ship. Their operational structure collapses without it."',
     recv_msg='"Command vessel destroyed. Corsair activity in the sector will be disorganized for months."'},
    {cargo="a contact seal certificate", short_offer="Stop unauthorized Hollow contact",
     faction_label="Hollow-contacting vessel", target_template="Adder MK5",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A ship has been making contact with Hollow-affiliated entities in restricted space.",
     accept_msg='"Destroy the ship. The contact protocol must not be allowed to propagate."',
     recv_msg='"Ship destroyed. Contact sealed."'},
    {cargo="a preemption receipt", short_offer="Stop an assassination contractor",
     faction_label="active assassination contractor", target_template="MT52 Hornet",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="An assassination contract on a Concord official has been accepted. The contractor is en route.",
     accept_msg='"Intercept and destroy before they reach the target. No second chances."',
     recv_msg='"Contractor destroyed. The official lives."'},
    {cargo="a credential purge cert", short_offer="Destroy a false-credentials ship",
     faction_label="ship with false Concord credentials", target_template="MT52 Hornet",
     reward_mult=1.1, tier_min=1, fac="Concord",
     lore="A ship operating on false Concord credentials has been using them to bypass checkpoints.",
     accept_msg='"Destroy the ship. The credentials die with it."',
     recv_msg='"Ship destroyed. Credential breach contained."'},
    {cargo="a key-kill receipt", short_offer="Destroy a Concord encryption thief",
     faction_label="operative who stole Concord encryption keys", target_template="Phobos T3",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="An operative sold Concord encryption keys to opposition intelligence. They cannot be allowed to deliver them.",
     accept_msg='"Destroy the ship. The keys must not leave this sector."',
     recv_msg='"Operative destroyed. Key compromise contained."'},
    {cargo="an asset recovery cert", short_offer="Destroy a stolen research vessel",
     faction_label="stolen medical research vessel", target_template="Flavia P.Falcon",
     reward_mult=1.3, tier_min=2, fac="Concord",
     lore="A Concord medical research vessel was stolen and its research repurposed.",
     accept_msg='"Destroy the vessel. The research cannot be allowed to continue under their direction."',
     recv_msg='"Research vessel destroyed."'},
    {cargo="a signal suppression cert", short_offer="Destroy a false-distress ship",
     faction_label="ship broadcasting false Concord distress", target_template="Adder MK5",
     reward_mult=1.2, tier_min=1, fac="Concord",
     lore="A ship is broadcasting false Concord distress signals to lure patrol vessels into ambushes.",
     accept_msg='"Destroy it before another patrol responds to the false call."',
     recv_msg='"Lure ship destroyed. The false distress signal has been silenced."'},
    {cargo="a justice execution cert", short_offer="Execute a war profiteer",
     faction_label="war profiteer with compromising evidence", target_template="Phobos T3",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A war profiteer has evidence against senior Concord officers. They're using it as leverage.",
     accept_msg='"Destroy the ship. The evidence is on board. Complete destruction."',
     recv_msg='"Profiteer destroyed. The evidence goes with them."'},
    -- Independent stations only
    {cargo="a protection rights receipt", short_offer="Destroy a protection racket ship",
     faction_label="protection racket ship", target_template="Adder MK5",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A protection racket ship has been threatening stations along this corridor. Stop paying, see what happens.",
     accept_msg='"End the protection racket. Destroy the ship."',
     recv_msg='"Racket ship destroyed. The stations in this corridor owe you."'},
    {cargo="a forfeiture claim", short_offer="Recover from a thieving courier",
     faction_label="courier who stole the cargo", target_template="MT52 Hornet",
     reward_mult=1.0, tier_min=0, fac="Independent",
     lore="A courier took the cargo and disappeared. They're still in the sector.",
     accept_msg='"We\'re past negotiation. Destroy the ship. We\'ll salvage what\'s recoverable."',
     recv_msg='"Ship destroyed. Salvage rights are yours. Recover what you can."'},
    {cargo="a claims clearance cert", short_offer="Stop a claim-destroying rival",
     faction_label="rival destroying salvage claims", target_template="Adder MK5",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A competitor is destroying salvage sites before anyone else can work them — just to cut out the competition.",
     accept_msg='"They\'re not salvaging — they\'re eliminating competition. End it."',
     recv_msg='"Rival destroyed. The salvage sites are open again."'},
    {cargo="an interdiction receipt", short_offer="Stop a corporate enforcement ship",
     faction_label="corporate enforcement vessel", target_template="Phobos T3",
     reward_mult=1.4, tier_min=2, fac="Independent",
     lore="A corporate enforcement ship has been seizing independent vessels over disputed contracts.",
     accept_msg='"Destroy the enforcement ship. The corporation has no jurisdiction out here."',
     recv_msg='"Enforcement ship destroyed. The corporation\'s reach just got shorter."'},
    {cargo="a survival receipt", short_offer="Destroy your own assassination contract",
     faction_label="hired assassin", target_template="MT52 Hornet",
     reward_mult=1.4, tier_min=2, fac="Independent",
     lore="An assassination contractor has your name as their current target. End the contract by ending them.",
     accept_msg='"You or them. Destroy the ship."',
     recv_msg='"Assassin destroyed. Whoever paid for that contract just lost their investment."'},
    {cargo="a water monopoly break cert", short_offer="Break a water monopoly by force",
     faction_label="water monopoly enforcement ship", target_template="Adder MK5",
     reward_mult=1.3, tier_min=2, fac="Independent",
     lore="A ship enforcing a water monopoly in a dry sector has been attacking alternative supply vessels.",
     accept_msg='"Destroy the enforcement ship. Water is a right, not a commodity."',
     recv_msg='"Monopoly enforcement ship destroyed. Alternative supply routes are open."'},
    {cargo="a collection kill receipt", short_offer="Stop a crime lord's collector",
     faction_label="crime lord's collection vessel", target_template="MT52 Hornet",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A crime lord's collection vessel has been working this sector, and several operations have been bled dry.",
     accept_msg='"Destroy the collection ship. Cut the bleeding."',
     recv_msg='"Collection ship destroyed. The bleeding stops here."'},
    {cargo="a free lanes receipt", short_offer="Destroy a pirate targeting traders",
     faction_label="pirate targeting independent traders", target_template="Phobos T3",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A pirate specifically targeting independent traders has been working this sector for three months.",
     accept_msg='"They know which ships are easy targets. Destroy them."',
     recv_msg='"Pirate destroyed. Independent traffic in this sector just got safer."'},
    {cargo="a contamination cert", short_offer="Destroy a bio-agent ship",
     faction_label="ship spreading a bio-agent", target_template="Flavia P.Falcon",
     reward_mult=1.4, tier_min=2, fac="Independent",
     lore="A ship has been deliberately spreading a slow-acting biological agent through a trade route.",
     accept_msg='"Destroy it. Complete hull destruction. Do not approach within 1U."',
     recv_msg='"Ship destroyed. Trade route decontamination can begin."'},
    {cargo="a blood debt receipt", short_offer="Avenge a killed trader",
     faction_label="Corsair captain with a blood debt", target_template="Phobos T3",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A Corsair captain killed a well-known and popular independent trader. The community wants an answer.",
     accept_msg='"The captain knows there\'s a debt. They\'re armed and ready. Destroy them."',
     recv_msg='"Captain destroyed. The debt is paid."'},
    {cargo="a corporate hit elimination cert", short_offer="Destroy a corporate hit squad",
     faction_label="corporate hit squad", target_template="Phobos T3",
     reward_mult=1.4, tier_min=2, fac="Independent",
     lore="A corporation sent a hit team into independent space. Someone doesn't want to be found.",
     accept_msg='"Destroy the hit squad before they reach their target."',
     recv_msg='"Hit squad destroyed. The target lives."'},
    {cargo="a false claim receipt", short_offer="Stop a murderous bounty hunter",
     faction_label="bounty hunter targeting the wrong people", target_template="Adder MK5",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A bounty hunter has been collecting on the wrong people — similar names, wrong faces.",
     accept_msg='"They won\'t be reasoned with. Destroy the ship."',
     recv_msg='"Bounty hunter destroyed. The wrong targets are safe."'},
    {cargo="a bomb disposal cert", short_offer="Stop a ship heading toward a station",
     faction_label="ship loaded with explosives", target_template="MT52 Hornet",
     reward_mult=1.5, tier_min=2, fac="Independent",
     lore="A ship loaded with explosives is heading toward a station. It's not responding to hails.",
     accept_msg='"Destroy it before it reaches the station. Do not miss."',
     recv_msg='"Ship destroyed. The station is safe."'},
    {cargo="a scout kill receipt", short_offer="Destroy a Hollow scout in independent space",
     faction_label="Hollow-backed scout", target_template="Adder MK5",
     reward_mult=1.3, tier_min=2, fac="Independent",
     lore="A Hollow-backed scout ship has been operating in independent space, marking targets.",
     accept_msg='"Destroy the scout before it transmits what it\'s found."',
     recv_msg='"Scout destroyed. Its report dies with it."'},
    {cargo="a predator kill cert", short_offer="Destroy a distress call predator",
     faction_label="ship preying on distress calls", target_template="MT52 Hornet",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A ship has been responding to distress calls — and attacking the distressed vessels when they're vulnerable.",
     accept_msg='"Destroy it. It\'s been using the most vulnerable moment of any crew against them."',
     recv_msg='"Predator destroyed. Distress calls in this sector are real again."'},
}

local M = {}
M.type      = "destroy"
M.weight    = 3
M.tier_min  = 2
M.type_mult = 1.6

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    local wx, wy, dist, region = ctx.spawnInVerse(rx, ry)
    if not wx then return nil end
    local nearby = ctx.nearbyStations(wx, wy, 150000)
    -- Exclude origin, Hollow, and Corsair stations from target destinations.
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
    local arch   = pool[math.random(#pool)]
    local reward = JOBS.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["destroy"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)

    local target_dest = nil
    if opts.nearby_stations and #opts.nearby_stations > 0 then
        target_dest = opts.nearby_stations[math.random(#opts.nearby_stations)]
    end

    return {
        id              = JOBS.nextId(),
        type            = "destroy",
        tier            = tier,
        origin          = opts.origin,
        wx              = opts.wx,
        wy              = opts.wy,
        cargo           = arch.cargo,
        reward          = reward,
        short           = arch.short_offer,
        obj             = "Locate and destroy target",
        brief           = arch.lore .. "\n\n" .. arch.accept_msg
                          .. "\n\nTarget must be completely destroyed. No boarding, no salvage.",
        complete_msg    = arch.recv_msg,
        target_template = arch.target_template,
        target_dest     = target_dest,
        distance_u      = opts.distance_u or 0,
        region_name     = opts.region_name,
        faction_label   = arch.faction_label,
        _spawned        = false,
        _destroyed      = false,
        _attacking      = false,
        target_cs       = nil,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.warp1 + 600)
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    return string.format("* Eliminate a %s in %s.\n  %s", m.faction_label or "target", region, stats)
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
    m.short      = "Destroy " .. name
    m.obj        = "Destroy " .. name
    m._spawned   = true
    m._attacking = false
end

function M.acceptLog(m)
    local heading_text = m.target_dest and (" heading toward " .. m.target_dest) or ""
    return string.format("Contract: %s. %dm to complete. %s last seen around %s%s.",
        m.short, math.floor(m._time_limit / 60),
        m.target_cs or "unknown", JOBS.gridRef(m.wx, m.wy), heading_text)
end

function M.update(m, entry, ctx)
    if m._destroyed then return nil end

    local target = RT.find(m.target_cs)
    if not RT.valid(target) then
        m._destroyed = true
        RT.addReputation("Corsairs", -200, "destroyed " .. (m.target_cs or "unknown"))
        m.obj = "Return to " .. m.origin
        RT.shipLog("[Target] " .. (m.target_cs or "target") .. " destroyed. Return to " .. m.origin .. ".", "#80FF80")
        JOBS.updateObj()
        return nil
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
    return nil
end

function M.completable(m, cs)
    return m.origin == cs and m._destroyed == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Submit %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Target confirmed destroyed."',
    }
end

JOBS.register(M)
