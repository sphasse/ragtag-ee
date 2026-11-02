-- ee/ragtag/jobs/delivery.lua
-- Delivery job type: ferry cargo between stations.

local _ARCHETYPES = {
    -- Any faction
    {cargo="medical supplies", urgent=true, reward_mult=1.1, tier_min=0,
     lore="The destination is short-staffed and someone isn't doing well.",
     accept_msg='"Move fast. People are waiting on the other end."',
     recv_msg='"You got here in time. Thank you."'},
    {cargo="water reclamation filters", urgent=true, reward_mult=1.1, tier_min=0,
     lore="A remote outpost's recycler is running raw. They're on reserve tanks.",
     accept_msg='"They\'ll run dry before the next supply run. You\'re the supply run."',
     recv_msg='"We were rationing. Not anymore. Good flying."'},
    {cargo="emergency shelter modules", urgent=true, reward_mult=1.0, tier_min=0,
     lore="A pressure seal failed at a frontier settlement. Thirty families are crowded into the ops center.",
     accept_msg='"They\'re fine, just cramped. Don\'t let that change."',
     recv_msg='"We can spread out again. That\'s worth something."'},
    {cargo="a vaccine batch", urgent=true, reward_mult=1.15, tier_min=0,
     lore="Something jumped to the upper respiratory tract in a mining camp. Cold-chain delivery.",
     accept_msg='"Keep it cold. Arrive fast. In that order."',
     recv_msg='"Chain intact. We\'ll start inoculations tonight."'},
    {cargo="replacement reactor rods", urgent=true, reward_mult=1.2, tier_min=0,
     lore="Station is on emergency power. Life support is off the backup cells.",
     accept_msg='"Everything non-essential is dark over there. Not a slow job."',
     recv_msg='"Lights are coming back on. We owe you."'},
    {cargo="survey data cores", urgent=false, reward_mult=1.0, tier_min=0,
     lore="Fresh scan data from a prospecting run. A rival outfit would pay well for it.",
     accept_msg='"Bonded delivery. No stops, no detours."',
     recv_msg='"Ahead of schedule. Appreciated."'},
    {cargo="a locked strongbox", urgent=false, reward_mult=0.9, tier_min=0,
     lore="Someone is moving their savings to a safer port. Don't ask how much is inside.",
     accept_msg='"Don\'t lose it. Don\'t open it. Please."',
     recv_msg='"I thought I\'d never see this again."'},
    {cargo="agricultural seed stock", urgent=false, reward_mult=0.95, tier_min=0,
     lore="A colony had a bad harvest. Certified viable, temperature-managed.",
     accept_msg='"They plant in six weeks. Be there in five."',
     recv_msg='"Germination rate looks good. You may have saved us a year."'},
    {cargo="mining drill components", urgent=false, reward_mult=0.95, tier_min=0,
     lore="A claim is sitting idle, costing a crew wages. Parts are ready; problem is distance.",
     accept_msg='"Every day late is a day they\'re eating through their margin."',
     recv_msg='"Back online tomorrow. You just paid a lot of salaries."'},
    {cargo="frozen livestock embryos", urgent=false, reward_mult=1.05, tier_min=0,
     lore="A new colony starting an animal program. The cryo-unit has twenty hours of backup power.",
     accept_msg='"Don\'t let the cold chain break. These are irreplaceable."',
     recv_msg='"All viable. The herd program starts today."'},
    {cargo="communication relay parts", urgent=false, reward_mult=0.9, tier_min=0,
     lore="A mining outpost has been dark for three days. Not distressed — just silent.",
     accept_msg='"Routine maintenance. Just get it there."',
     recv_msg='"We\'re back on the net. It was getting quiet out here."'},
    {cargo="personal effects of the deceased", urgent=false, reward_mult=0.85, tier_min=0,
     lore="Someone died on a long haul. Family is waiting at the other end.",
     accept_msg='"Take care with it. This is someone\'s everything."',
     recv_msg='"Thank you. We can close the chapter now."'},
    {cargo="fuel cell assemblies", urgent=false, reward_mult=0.9, tier_min=0,
     lore="A remote beacon array is on its last cycle. When it goes dark, ships navigate blind.",
     accept_msg='"Standard maintenance contract. Move it along."',
     recv_msg='"Array is back to full cycle. Another six months on these."'},
    {cargo="a replacement navigation computer", urgent=false, reward_mult=1.0, tier_min=0,
     lore="A ship is stuck at dock — nav system failed certification. Replacement is already cleared.",
     accept_msg='"They\'re paying docking fees every hour it sits."',
     recv_msg='"Certified and installed. We\'re back in the black."'},
    {cargo="protein processor units", urgent=false, reward_mult=0.9, tier_min=0,
     lore="A station's food production is down to two working units. People are eating, just not happily.",
     accept_msg='"Nobody\'s going hungry, but morale is suffering."',
     recv_msg='"Hot food again. You\'d be surprised how much that matters."'},
    {cargo="entertainment archives", urgent=false, reward_mult=0.8, tier_min=0,
     lore="Six months of shows, games, and music for a crew rotating shifts in the dark for three.",
     accept_msg='"Morale counts. Get it there."',
     recv_msg='"This is going to be a good week. Thank you."'},
    {cargo="spare hull plating", urgent=false, reward_mult=0.9, tier_min=0,
     lore="A station took a micro-impact. The patch job won't last.",
     accept_msg='"Temporary fix is holding. This makes it permanent."',
     recv_msg='"Good fit. That module is solid now."'},
    {cargo="a sealed medical stasis case", urgent=false, reward_mult=1.2, tier_min=0,
     lore="Someone is being transferred in controlled suspension. Your job is the flight time.",
     accept_msg='"Status light stays green the whole trip. Don\'t let it go amber."',
     recv_msg='"Transfer stable. Your part is done."'},
    {cargo="surgical instruments", urgent=false, reward_mult=1.05, tier_min=0,
     lore="A frontier hospital is down to improvised tools. This is the replacement shipment.",
     accept_msg='"They\'re doing what they can. Give them proper tools."',
     recv_msg='"Finally. These are exactly what we needed."'},
    {cargo="a genetic sample container", urgent=false, reward_mult=1.1, tier_min=0,
     lore="Medical research material from a field study. Cold-chain, tamper-evident.",
     accept_msg='"Treat it like medicine. It practically is."',
     recv_msg='"Intact and on time. The trial proceeds."'},
    {cargo="ration crates", urgent=true, reward_mult=0.95, tier_min=0,
     lore="Another crew quoted this run first. Get there before they do.",
     accept_msg='"Beat them to it and the contract bonus is yours."',
     recv_msg='"Beat the other crew. Payment\'s yours."'},
    {cargo="emergency beacon parts", urgent=true, reward_mult=1.0, tier_min=0,
     lore="Beacon relay for an outpost that went dark. No backup comms until you deliver.",
     accept_msg='"Someone out there can\'t call for help right now. Move."',
     recv_msg='"We\'re back online. You have no idea what that means to us."'},
    {cargo="a bonded prisoner", urgent=false, reward_mult=1.4, tier_min=1,
     lore="Alive and secured. Licensed transfer. Don't let them talk to you.",
     accept_msg='"They\'ll try to negotiate. Standard contract: you don\'t open the bay."',
     recv_msg='"Secure, no incidents. The bond transfers to you now."'},
    {cargo="ore processing reagents", urgent=false, reward_mult=0.9, tier_min=0,
     lore="A refinery is at sixty percent yield without this. One missing reagent.",
     accept_msg='"Get it there. They\'re losing margin every hour."',
     recv_msg='"Full process restored. You just improved our quarterly."'},
    {cargo="printed navigational charts", urgent=false, reward_mult=0.85, tier_min=0,
     lore="Old-format paper charts for a crew that doesn't trust digital-only navigation in the Shroud.",
     accept_msg='"Archaic and practical. Just deliver them."',
     recv_msg='"Good to have something that doesn\'t need a power source."'},
    -- Concord stations only
    {cargo="an evidence manifest", urgent=false, reward_mult=1.0, tier_min=0, fac="Concord",
     lore="Sealed court documents — chain of custody must remain unbroken from pickup to delivery.",
     accept_msg='"Handle as if a conviction depends on it. It does."',
     recv_msg='"Seal intact. Chain clear. You\'re done here."'},
    {cargo="fleet requisition orders", urgent=false, reward_mult=0.9, tier_min=0, fac="Concord",
     lore="A supply depot needs physical authorization to release components. Bureaucracy requires the packet.",
     accept_msg='"Standard run. Keep it moving."',
     recv_msg='"Received and processed. Depot is cleared."'},
    {cargo="census data cores", urgent=false, reward_mult=0.9, tier_min=0, fac="Concord",
     lore="Population registry update from a frontier survey. Dull work, but Concord needs accurate numbers.",
     accept_msg='"Standard courier contract. Nothing sensitive."',
     recv_msg='"Registry updated. Thank you."'},
    {cargo="arrest warrant documents", urgent=true, reward_mult=1.1, tier_min=0, fac="Concord",
     lore="Priority warrant packet. Physical authorization required — digital issuance for this jurisdiction was suspended.",
     accept_msg='"The clock on this starts when you leave. Move."',
     recv_msg='"Warrant on file. You moved fast. Good."'},
    {cargo="crew transfer orders", urgent=false, reward_mult=0.9, tier_min=0, fac="Concord",
     lore="Personnel rotation paperwork for a Concord posting. The bureaucracy requires the physical packet.",
     accept_msg='"Routine transfer. Don\'t lose the packet."',
     recv_msg='"Orders received. Rotation proceeds."'},
    {cargo="biometric scanner units", urgent=false, reward_mult=1.0, tier_min=1, fac="Concord",
     lore="Checkpoint installation at a border station. This is the last component for commissioning.",
     accept_msg='"Installation crew is standing by. Get it there."',
     recv_msg='"Installed and calibrated. Checkpoint is live."'},
    {cargo="decommissioned weapon parts", urgent=false, reward_mult=1.0, tier_min=1, fac="Concord",
     lore="Cleared for civilian disposition, but the transfer must be physically registered at the depot.",
     accept_msg='"The manifest is clean. Deliver to the registry officer."',
     recv_msg='"Registered and logged. Everything is compliant."'},
    {cargo="classified survey results", urgent=false, reward_mult=1.2, tier_min=1, fac="Concord",
     lore="Sealed results from a restricted zone survey. Above your clearance, but the contract is legitimate.",
     accept_msg='"Deliver to the named recipient only. Don\'t break the seal."',
     recv_msg='"Seal intact. You never saw this."'},
    {cargo="a seized asset manifest", urgent=false, reward_mult=1.0, tier_min=1, fac="Concord",
     lore="Paperwork for assets seized in a recent operation. Customs needs the physical manifest.",
     accept_msg='"Formality. Just get it there."',
     recv_msg='"Processing complete. Assets cleared for disposal."'},
    {cargo="detention transfer orders", urgent=false, reward_mult=1.1, tier_min=1, fac="Concord",
     lore="Physical transfer authorization for a detainee being moved to a higher-security facility.",
     accept_msg='"Deliver to the facility administrator. Sealed and unread."',
     recv_msg='"Transfer authorized. Detainee in custody."'},
    {cargo="an intelligence courier packet", urgent=true, reward_mult=1.5, tier_min=2, fac="Concord",
     lore="Origin, contents, and recipient are all above your clearance. The pay makes up for the ambiguity.",
     accept_msg='"Fast. No stops. No detours. No questions."',
     recv_msg='"Received. This conversation is already over."'},
    {cargo="witness protection relocation papers", urgent=true, reward_mult=1.4, tier_min=2, fac="Concord",
     lore="The relocating party doesn't know the destination yet — it's in the packet. Fewer people knowing, better.",
     accept_msg='"Keep this quiet and keep moving. Lives depend on it, literally."',
     recv_msg='"Package received. Relocation proceeds. Thank you."'},
    {cargo="a military requisition for experimental systems", urgent=false, reward_mult=1.5, tier_min=2, fac="Concord",
     lore="Authorization for components that don't appear in any public catalog. Manifest says 'laboratory supplies.'",
     accept_msg='"Deliver to the named contact. Don\'t read the manifest."',
     recv_msg='"Received. Your discretion is noted."'},
    {cargo="classified medical research data", urgent=false, reward_mult=1.4, tier_min=2, fac="Concord",
     lore="Trial data from a program that officially doesn't exist. The results are significant.",
     accept_msg='"Sealed transport, named recipient. Do not lose this."',
     recv_msg='"Data received and secured. You have done something important today."'},
    {cargo="treaty negotiation documents", urgent=false, reward_mult=1.6, tier_min=2, fac="Concord",
     lore="Preliminary terms for an unannounced negotiation. Wrong hands means the deal falls apart.",
     accept_msg='"Faster than any courier drone, and quieter. Get it done."',
     recv_msg='"Documents received. You\'ve done your part."'},
    -- Independent stations only
    {cargo="unmarked crates", urgent=false, reward_mult=1.5, tier_min=0, fac="Independent",
     lore="They said don't ask. The pay says don't argue.",
     accept_msg='"You didn\'t see this. We never spoke."',
     recv_msg='"Quiet and fast. Just how we like it."'},
    {cargo="off-manifest medical supplies", urgent=false, reward_mult=1.3, tier_min=0, fac="Independent",
     lore="Sourced through channels that skip the tariff. Nothing dangerous, but Concord would still want to talk.",
     accept_msg='"Legitimate need. Inconvenient paperwork. Keep it moving."',
     recv_msg='"No questions asked. No answers given. Good work."'},
    {cargo="a contact's personal effects", urgent=false, reward_mult=1.0, tier_min=0, fac="Independent",
     lore="Someone left in a hurry. A friend held it; now it needs to catch up.",
     accept_msg='"They\'ll be waiting. Don\'t ask where they went."',
     recv_msg='"Thank you. I didn\'t think I\'d see this again."'},
    {cargo="bottled goods from an unlicensed still", urgent=false, reward_mult=1.1, tier_min=0, fac="Independent",
     lore="The best stuff in this sector, and not a tax stamp on any of it.",
     accept_msg='"Smooth operation. Just don\'t shake it."',
     recv_msg='"Beautiful. How\'d it survive the run?"'},
    {cargo="a crated artwork with uncertain provenance", urgent=false, reward_mult=1.2, tier_min=0, fac="Independent",
     lore="Original work, possibly. From where, nobody is currently asking.",
     accept_msg='"The buyer doesn\'t need to know where it came from. Neither do you."',
     recv_msg='"Better than described. I\'ll have more work for you."'},
    {cargo="parts for an unregistered ship", urgent=false, reward_mult=1.3, tier_min=1, fac="Independent",
     lore="The ship doesn't appear in any registry. Parts are for maintenance — probably.",
     accept_msg='"The recipient will know what they are. You don\'t need to."',
     recv_msg='"Exactly right. She\'ll fly now."'},
    {cargo="a data core from an anonymous source", urgent=false, reward_mult=1.4, tier_min=1, fac="Independent",
     lore="The sender used three cutouts and a throwaway comms code.",
     accept_msg='"The recipient knows to expect it. No name on delivery — just the code."',
     recv_msg='"Got it. Don\'t remember this run."'},
    {cargo="unreported salvage cargo", urgent=false, reward_mult=1.3, tier_min=1, fac="Independent",
     lore="Finder's rights are murky. Easiest to move it before anyone asks about the paperwork.",
     accept_msg='"Fast is better than careful on this one."',
     recv_msg='"No manifest, no questions. Exactly what I needed."'},
    {cargo="components that hum at an odd frequency", urgent=false, reward_mult=1.5, tier_min=1, fac="Independent",
     lore="The crate makes a sound. Nobody explained what it is. The pay is good enough not to ask.",
     accept_msg='"Keep it away from the reactor. That\'s all."',
     recv_msg='"There it is. You didn\'t peek, did you."'},
    {cargo="personal cargo for someone leaving fast", urgent=true, reward_mult=1.2, tier_min=1, fac="Independent",
     lore="They left three hours ago with a carry-bag. This is everything else. They'll need it.",
     accept_msg='"Catch up to them before they stop moving."',
     recv_msg='"You found me. Thank you."'},
    {cargo="grey-market encryption hardware", urgent=false, reward_mult=1.6, tier_min=2, fac="Independent",
     lore="Classified source, functional hardware, none of it on any export list.",
     accept_msg='"Don\'t broadcast and don\'t let Concord board you."',
     recv_msg='"The good stuff. It\'s been a while."'},
    {cargo="corporate black budget components", urgent=false, reward_mult=1.7, tier_min=2, fac="Independent",
     lore="Shell company manifest, genuine merchandise. A corporation moving parts it doesn't officially own.",
     accept_msg='"Don\'t ask what it\'s for. You don\'t want to know."',
     recv_msg='"On time and in good order. The project continues."'},
    {cargo="\"decommissioned\" military-grade sensors", urgent=false, reward_mult=1.6, tier_min=2, fac="Independent",
     lore="Officially struck from inventory. Unofficially functional and worth five times the manifest value.",
     accept_msg='"If anyone asks, these are scrap."',
     recv_msg='"These still have their calibration data. Beautiful."'},
    {cargo="a corporate defector's documents", urgent=true, reward_mult=1.8, tier_min=2, fac="Independent",
     lore="Someone left a very large company with evidence. They need it delivered before the company notices.",
     accept_msg='"Fast. Before anyone finds out what they took."',
     recv_msg='"This changes things. Move away from this quickly."'},
    {cargo="a complete new identity", urgent=true, reward_mult=2.0, tier_min=2, fac="Independent",
     lore="Documents, biometric registration, credit history — a full person on paper, for someone who needs to stop being who they are.",
     accept_msg='"The recipient\'s new name is inside the cover. Deliver only to that person."',
     recv_msg='"That\'s me now. I won\'t forget this."'},
}

local M = {}
M.type      = "delivery"
M.weight    = 15
M.tier_min  = 0
M.type_mult = 1.0

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local dest_cs = ctx.nextCandidate()
    if not dest_cs then return nil end
    local dest_e = ctx.findStation(dest_cs)
    if not ctx.valid(dest_e) then return nil end
    local ox, oy = ctx.station_e:getPosition()
    local dx, dy = dest_e:getPosition()
    local ddx, ddy = dx - ox, dy - oy
    local region = VERSE.regionAt(dx, dy)
    return {
        origin         = ctx.station_cs,
        origin_faction = MISSION.stationFaction(ctx.station_cs),
        dest           = dest_cs,
        dest_faction   = MISSION.stationFaction(dest_cs),
        tier           = ctx.tier,
        distance_u     = math.sqrt(ddx*ddx + ddy*ddy),
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
    local arch   = pool[math.random(#pool)]
    local urgent = arch.urgent or false
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["delivery"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u,
        urgent and 1.5 or 1.0)
    local prefix = urgent and "URGENT: " or ""
    local dest_short = MISSION.shortName(opts.dest)

    return {
        id           = MISSION.nextId(),
        type         = "delivery",
        tier         = tier,
        origin       = opts.origin,
        dest         = opts.dest,
        cargo        = arch.cargo,
        reward       = reward,
        short        = prefix .. arch.cargo .. " → " .. dest_short,
        obj          = "Deliver to " .. dest_short,
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        urgent       = urgent,
        distance_u   = opts.distance_u or 0,
        region_name  = opts.region_name,
        dest_faction = opts.dest_faction or "Independent",
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    if m.urgent then
        return math.floor(d / JOBS.SPEED.warp1 + 180)
    else
        return math.floor(d / JOBS.SPEED.impulse + 180)
    end
end

function M.offerText(m, stats)
    local fac    = m.dest_faction or "Independent"
    local prefix = m.urgent and "URGENT: " or ""
    return string.format("● %sDeliver %s to %s (%s).\n  %s", prefix, m.cargo, m.dest, fac, stats)
end

function M.spawn(m)
    -- No world objects to spawn for delivery.
end

function M.acceptLog(m)
    local dest_e = RT.find(m.dest)
    if RT.valid(dest_e) then
        local dx, dy = dest_e:getPosition()
        return string.format("Contract: %s. %dm to complete. Head to %s (%s).",
            m.short, math.floor(m._time_limit / 60), m.dest, MISSION.gridRef(dx, dy))
    end
    return string.format("Contract: %s. %dm to complete. Head to %s.",
        m.short, math.floor(m._time_limit / 60), m.dest or "??")
end

function M.update(m, entry, ctx)
    -- No per-frame logic; completion is handled by stationHook completable check.
    return nil
end

function M.completable(m, cs)
    return m.dest == cs
end

function M.completeReply(m, entry)
    return {
        label = string.format("Hand off %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Received. Good flying."',
    }
end

JOBS.register(M)
