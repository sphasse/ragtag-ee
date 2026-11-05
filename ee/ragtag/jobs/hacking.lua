-- ee/ragtag/jobs/hacking.lua
-- Hacking job type: breach a stationary Concord comms relay beacon.

local _ARCHETYPES = {
    -- Any faction
    {cargo="an encrypted nav log", short_offer="Hack a relay for nav logs",
     reward_mult=1.0, tier_min=0,
     lore="Someone has been running routes they don't want on record. The log lives in a relay buoy.",
     accept_msg='"Get Relay in position and crack it before anyone notices the uplink."',
     recv_msg='"Routes confirmed. This is exactly what we needed."'},
    {cargo="a comms archive", short_offer="Extract comms from a dark relay",
     reward_mult=1.0, tier_min=0,
     lore="Months of unencrypted traffic between two stations — someone paid to keep this relay dark.",
     accept_msg='"Pull the archive intact. Partial data is worthless to us."',
     recv_msg='"Everything\'s here. Good clean extraction."'},
    {cargo="a contraband manifest", short_offer="Crack a smuggler's relay cache",
     reward_mult=1.1, tier_min=0,
     lore="A smuggling outfit uses relay buoys to cache their cargo schedules.",
     accept_msg='"Crack it quietly. If they notice the uplink they\'ll wipe the buffer."',
     recv_msg='"Manifest intact. Half a dozen ships just had a very bad week."'},
    {cargo="traffic routing data", short_offer="Pull routing data from a relay",
     reward_mult=1.0, tier_min=0,
     lore="Someone is using this relay to distribute routing updates to ships off the official grid.",
     accept_msg='"We want the full routing table. Get in and get out clean."',
     recv_msg='"Routing table complete. We know every back-channel in the sector now."'},
    {cargo="the manifest of an unregistered ship", short_offer="ID a ghost ship via relay",
     reward_mult=1.1, tier_min=0,
     lore="A ship with no transponder has been using relay infrastructure meant for registered vessels.",
     accept_msg='"Pull whatever it left in the buffer. Enough to identify it."',
     recv_msg='"We have a name. That\'s more than we had yesterday."'},
    {cargo="docking logs from an off-books port", short_offer="Pull logs from a hidden port relay",
     reward_mult=1.2, tier_min=1,
     lore="An unregistered docking facility is running its own relay network. We want the visitor log.",
     accept_msg='"Don\'t trip any of the relay\'s alert flags. Someone monitors this one."',
     recv_msg='"Every ship that visited in the last six months. This is valuable."'},
    {cargo="cargo movement records", short_offer="Map cargo movements via relay",
     reward_mult=1.0, tier_min=0,
     lore="A relay node in the shipping lane is logging every cargo declaration that passes through it.",
     accept_msg='"Pull the last ninety days. We\'re looking for a pattern."',
     recv_msg='"Three ships, same route, same cargo class, different names. There\'s the pattern."'},
    {cargo="a stolen route database", short_offer="Recover a stolen route archive",
     reward_mult=1.2, tier_min=1,
     lore="Proprietary navigation routes were stolen and stashed in a relay cache. The owner wants them back.",
     accept_msg='"The relay has a timer wipe. You have a narrow window."',
     recv_msg='"Full database intact. The original owner will be very pleased."'},
    {cargo="a station's visitor log from a specific week", short_offer="Pull visitor records from a relay",
     reward_mult=1.0, tier_min=0,
     lore="A station visitor log for one specific week is sitting in a relay buffer. Someone needs to know who was there.",
     accept_msg='"In and out. We only need those seven days."',
     recv_msg='"Log complete. Three names we expected, two we didn\'t."'},
    {cargo="financial records from a front company", short_offer="Crack a financial relay cache",
     reward_mult=1.3, tier_min=1,
     lore="A shell company is using a relay node to pass financial data between entities that officially have no connection.",
     accept_msg='"Pull the transaction logs. Don\'t trigger the automated audit alert."',
     recv_msg='"The money trail just got a lot clearer."'},
    {cargo="maintenance logs from a Concord-registered ship", short_offer="Pull maintenance records via relay",
     reward_mult=1.1, tier_min=0,
     lore="A ship's maintenance history tells you what's been modified. This one has been modified.",
     accept_msg='"We want the full service record. Everything since commissioning."',
     recv_msg='"Three undocumented modifications in the last year. Now we know what we\'re dealing with."'},
    {cargo="biometric data from an unauthorized checkpoint", short_offer="Extract biometric records",
     reward_mult=1.2, tier_min=1,
     lore="An unofficial checkpoint is scanning everyone who passes through and storing the data in a relay.",
     accept_msg='"Extract the biometric index. Someone is building a database they shouldn\'t have."',
     recv_msg='"Thousands of entries. This is bigger than we thought."'},
    {cargo="comms logs from a missing vessel", short_offer="Recover a missing ship's comms",
     reward_mult=1.1, tier_min=0,
     lore="A ship went missing three weeks ago. Its last transmissions were routed through a relay buoy.",
     accept_msg='"Pull everything from the last week of transmissions. We need to know where it went."',
     recv_msg='"Final coordinates and a distress call that never finished. We know where to look."'},
    {cargo="encrypted message traffic between two callsigns", short_offer="Intercept a message thread",
     reward_mult=1.2, tier_min=1,
     lore="Two callsigns have been passing encrypted messages through a relay for three months.",
     accept_msg='"We can\'t crack the encryption, but we can grab the packets. Do it."',
     recv_msg='"Message archive pulled. Our people will handle the decryption."'},
    {cargo="a fuel dump's supply records", short_offer="Pull fuel supply records",
     reward_mult=1.0, tier_min=0,
     lore="An unregistered fuel depot is keeping its client list in a relay cache.",
     accept_msg='"Pull the client log. Who fueled up and when."',
     recv_msg='"Client list complete. Two of those ships weren\'t supposed to be in this sector."'},
    {cargo="the chart of a hidden route", short_offer="Recover a secret nav chart",
     reward_mult=1.3, tier_min=1,
     lore="A navigation chart for a passage through the Shroud has been cached in a relay buoy.",
     accept_msg='"That route is worth a lot to the right people. Get the chart."',
     recv_msg='"Route verified. We can use this."'},
    {cargo="ghost ship registry data", short_offer="ID ghost ships via relay",
     reward_mult=1.2, tier_min=1,
     lore="A relay has been serving navigation updates to ships with no registered transponders.",
     accept_msg='"Pull the request log. We want every unregistered vessel that touched this node."',
     recv_msg='"Seven ghost ships. Names, hull signatures, last-known positions."'},
    {cargo="sensor array raw feed from six months ago", short_offer="Recover archived sensor data",
     reward_mult=1.1, tier_min=1,
     lore="A sensor array dumped its raw feed to a relay before going offline. Something happened in that window.",
     accept_msg='"Pull the archive. It\'s big, but we need all of it."',
     recv_msg='"Archive intact. We\'ll analyze it. Something happened out there."'},
    {cargo="the payload of an intercepted courier buoy", short_offer="Crack a courier buoy",
     reward_mult=1.2, tier_min=1,
     lore="A courier buoy drifted into a sector it wasn't supposed to pass through. Someone wants to know what it's carrying.",
     accept_msg='"Crack the buoy\'s data store before it resumes its route."',
     recv_msg='"Contents extracted. Interesting reading."'},
    {cargo="an old distress call recording", short_offer="Recover a lost distress signal",
     reward_mult=1.0, tier_min=0,
     lore="A distress call from three years ago was received by this relay and never forwarded. A family wants to know what it said.",
     accept_msg='"The recording should still be in the buffer. Pull it intact."',
     recv_msg='"Recording recovered. At least the family will know."'},
    -- Concord stations only
    {cargo="docking access codes for a restricted berth", short_offer="Pull restricted access codes",
     reward_mult=1.3, tier_min=1, fac="Concord",
     lore="A Concord restricted berth rotates its access codes weekly. We need the current set.",
     accept_msg='"The relay holds the live key. You have hours before the next rotation."',
     recv_msg='"Codes verified and live. We\'re in."'},
    {cargo="the active fugitive warrant database", short_offer="Access Concord warrant records",
     reward_mult=1.4, tier_min=1, fac="Concord",
     lore="The active warrant index is distributed through Concord relays. We need to know who's on it.",
     accept_msg='"Don\'t trigger the audit ping. The access is detectable if you\'re clumsy."',
     recv_msg='"Full warrant list. Several names on here will be very useful."'},
    {cargo="a classified intelligence assessment", short_offer="Extract a Concord intel brief",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A periodic intelligence brief is cached in a relay before distribution to field commanders.",
     accept_msg='"Pull the current brief before it propagates. We want to know what Concord knows."',
     recv_msg='"Assessment extracted. They know less than we feared."'},
    {cargo="Concord fleet positioning data", short_offer="Pull fleet disposition data",
     reward_mult=1.6, tier_min=2, fac="Concord",
     lore="Fleet movement orders pass through relay infrastructure before reaching ships. Someone wants to know where they're going.",
     accept_msg='"This is sensitive. In and out with no trace."',
     recv_msg='"Fleet positions for the next seventy-two hours. This is valuable."'},
    {cargo="an officer's encrypted message thread", short_offer="Access an officer's comms",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="A Concord officer has been passing personal messages through official relay infrastructure.",
     accept_msg='"Extract the full thread. What they discuss on duty hardware belongs to us."',
     recv_msg='"Thread extracted. This officer has been having a very interesting private conversation."'},
    {cargo="transfer records for high-value detainees", short_offer="Pull detainee transfer logs",
     reward_mult=1.3, tier_min=1, fac="Concord",
     lore="Detainee movement orders route through a relay. We need to know where they're holding someone.",
     accept_msg='"Pull the last thirty days. We\'re looking for one specific name."',
     recv_msg='"Transfer log complete. Found them. You just saved a life."'},
    {cargo="a surveillance network's coverage map", short_offer="Map a surveillance network",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="Concord sensor placement data is distributed through relay nodes. We want to know where the gaps are.",
     accept_msg='"Pull the coverage schema. We need to know which corridors they\'re not watching."',
     recv_msg='"Coverage map complete. There are more gaps than they\'d like to admit."'},
    {cargo="a classified debrief transcript", short_offer="Extract a classified debrief",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A debrief transcript from a sensitive operation is sitting in a relay buffer awaiting archival.",
     accept_msg='"Pull it before it moves to the secure archive. After that we can\'t touch it."',
     recv_msg='"Transcript extracted. The operation went further than the official version says."'},
    {cargo="credentials for a sealed investigation", short_offer="Access a sealed investigation",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A sealed investigation's access credentials are cached in a relay. With these, the file opens.",
     accept_msg='"Don\'t access the file itself — just grab the credentials. We\'ll use them later."',
     recv_msg='"Credentials extracted. We can read the sealed file whenever we\'re ready."'},
    {cargo="a Concord medical registry with blacklisted conditions", short_offer="Pull medical blacklist data",
     reward_mult=1.3, tier_min=1, fac="Concord",
     lore="Concord maintains a registry of medical conditions that disqualify someone from service. We want the full list.",
     accept_msg='"Medical registry is in the relay\'s secondary buffer. Pull the whole thing."',
     recv_msg='"Registry complete. The list of disqualifying conditions is longer than the public version."'},
    {cargo="identification protocols for undercover operatives", short_offer="ID undercover operatives",
     reward_mult=1.6, tier_min=2, fac="Concord",
     lore="A relay holds the challenge-response protocols used to verify undercover operatives in the field.",
     accept_msg='"This is extremely sensitive. If Concord detects the breach, those operatives are burned."',
     recv_msg='"Protocols extracted. This is powerful — and dangerous — information."'},
    {cargo="fleet resupply schedule from an encrypted relay", short_offer="Pull fleet supply schedules",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="Fleet resupply orders reveal patrol schedules. The schedule is cached in an encrypted relay.",
     accept_msg='"The encryption is military grade. You\'ll need to hack the relay systems to get through it."',
     recv_msg='"Schedule extracted. We know when every patrol refuels and where."'},
    {cargo="a sealed audit report fragment", short_offer="Extract an audit report fragment",
     reward_mult=1.4, tier_min=2, fac="Concord",
     lore="An audit of Concord contracting was fragmented and distributed across relay nodes before suppression.",
     accept_msg='"This fragment is one piece of a larger picture. Bring it back intact."',
     recv_msg='"Fragment verified. One piece closer to the full picture."'},
    {cargo="encrypted tribunal vote records", short_offer="Crack tribunal vote records",
     reward_mult=1.5, tier_min=2, fac="Concord",
     lore="A closed tribunal's vote records were encrypted and cached in a relay. We want to know how it went.",
     accept_msg='"Crack the encryption. We need to know who voted for what."',
     recv_msg='"Vote records decrypted. The split is not what the official verdict suggests."'},
    {cargo="a ledger fragment on Concord payoffs", short_offer="Extract a corruption ledger",
     reward_mult=1.6, tier_min=2, fac="Concord",
     lore="Corporate financial records split across relay nodes. One fragment is enough to bring down a board.",
     accept_msg='"This relay is hardened. It will resist. Don\'t stop until you\'re through."',
     recv_msg='"Fragment verified. You just changed some very powerful people\'s plans."'},
    -- Independent stations only
    {cargo="records that could break a trade coalition", short_offer="Pull market manipulation data",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A trade coalition is using relay infrastructure to coordinate price-fixing across the sector.",
     accept_msg='"Pull the coordination logs. The smaller operators have been waiting for this."',
     recv_msg='"Full coordination record. This ends the coalition."'},
    {cargo="a smuggling ring's routing algorithm", short_offer="Crack a smuggling network relay",
     reward_mult=1.4, tier_min=1, fac="Independent",
     lore="A sophisticated smuggling operation uses a relay node to distribute route updates to its network.",
     accept_msg='"We want the algorithm, not just the routes. Pull the whole thing."',
     recv_msg='"Algorithm extracted. We can predict their movements for months."'},
    {cargo="blackmail material on a station administrator", short_offer="Pull compromising records",
     reward_mult=1.4, tier_min=1, fac="Independent",
     lore="A station administrator has been using a private relay to communicate with people they shouldn't know.",
     accept_msg='"Don\'t filter it. We want everything that\'s in the buffer."',
     recv_msg='"That administrator is going to be very cooperative from now on."'},
    {cargo="a broker's contact list", short_offer="Extract a broker's contact list",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A grey-market broker maintains their contact list in a relay cache. With it, we know the whole network.",
     accept_msg='"Names and comms codes. That\'s all we need."',
     recv_msg='"Full contact list. We know everyone in this broker\'s network."'},
    {cargo="location data of a hidden cache", short_offer="Find a hidden cache via relay",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A dead smuggler's cache coordinates were the last thing transmitted through this relay.",
     accept_msg='"Pull the last outgoing transmission before the operator went dark."',
     recv_msg='"Coordinates extracted. The cache has been sitting there for two years."'},
    {cargo="a corporate contract that should not exist", short_offer="Pull a destroyed contract",
     reward_mult=1.4, tier_min=2, fac="Independent",
     lore="A corporate contract for something illegal was 'destroyed' — but a copy passed through a relay.",
     accept_msg='"They deleted the original. This is the only copy. Don\'t miss."',
     recv_msg='"Contract extracted. This is legally actionable."'},
    {cargo="whisper-net traffic from the past month", short_offer="Tap the whisper-net relay",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="The frontier whisper-net routes informal traffic through relay nodes. We want last month's raw feed.",
     accept_msg='"Don\'t filter — we want all of it. Our people will sort the useful bits."',
     recv_msg='"Full feed for the month. Three items of immediate interest."'},
    {cargo="coordinates hidden in a garbage relay", short_offer="Extract hidden coordinates",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A location was encoded in the garbage traffic of an innocuous relay. Someone is hiding something at those coordinates.",
     accept_msg='"Pull the raw traffic stream. The coordinates are buried in it."',
     recv_msg='"Coordinates decoded. Whatever is out there has been hidden very carefully."'},
    {cargo="an encrypted grey-market auction", short_offer="Crack a black market auction relay",
     reward_mult=1.4, tier_min=2, fac="Independent",
     lore="A black market auction is being coordinated through an encrypted relay. We want the lot list.",
     accept_msg='"Crack the encryption. We want to know what\'s on offer."',
     recv_msg='"Lot list extracted. Several items on here shouldn\'t exist."'},
    {cargo="the identity of an informant in the Corsair hierarchy", short_offer="Identify a Corsair informant",
     reward_mult=1.6, tier_min=2, fac="Independent",
     lore="Someone inside the Corsair hierarchy is passing information out. We want to know who before Corsairs do.",
     accept_msg='"This relay is the conduit. Pull the outgoing traffic from the right timeframe."',
     recv_msg='"Name confirmed. We can use this — or protect them. Either way."'},
    {cargo="a corporate espionage package", short_offer="Extract a corporate espionage file",
     reward_mult=1.5, tier_min=2, fac="Independent",
     lore="A corporate espionage package was staged in a relay cache. Half the payment was already sent.",
     accept_msg='"It\'s already in the relay. Just pull it out."',
     recv_msg='"Package extracted. The rest of the payment follows."'},
    {cargo="a criminal debt register", short_offer="Pull a loan shark's debt records",
     reward_mult=1.2, tier_min=1, fac="Independent",
     lore="A criminal lending operation keeps its accounts in a relay cache. We want the full debtor list.",
     accept_msg='"Names, amounts, and collection status. Pull the register."',
     recv_msg='"Register extracted. Some of those debtors are going to be very grateful."'},
    {cargo="private docking ring access codes", short_offer="Pull private dock access codes",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="A station's private docking ring uses a relay to distribute access codes to approved users.",
     accept_msg='"Pull the current cycle codes. We only need one visit."',
     recv_msg='"Codes live. The docking ring is open to us."'},
    {cargo="a price-fixing agreement between freight brokers", short_offer="Expose a price-fixing ring",
     reward_mult=1.3, tier_min=1, fac="Independent",
     lore="Several freight brokers coordinate rates through a private relay. The independent haulers are being squeezed.",
     accept_msg='"Pull the coordination logs. We\'ll make sure the right people see them."',
     recv_msg='"Agreement documented. The brokers are about to have a very public problem."'},
    {cargo="evidence of corporate funding for Corsair raids", short_offer="Extract corporate-Corsair links",
     reward_mult=1.6, tier_min=2, fac="Independent",
     lore="A corporation has been funding Corsair raids on competitor shipping. The payment records passed through this relay.",
     accept_msg='"Pull every financial transaction this relay has ever seen. The proof is in there."',
     recv_msg='"Payment records extracted. This ends a corporation."'},
}

local function _beaconName()
    local chars = "ABCDEFGHJKLMNPQRSTUVWXYZ123456789"
    local code = ""
    for _ = 1, 5 do
        local idx = math.random(#chars)
        code = code .. chars:sub(idx, idx)
    end
    return "Beacon " .. code
end

local M = {}
M.type      = "hacking"
M.weight    = 3
M.tier_min  = 1   -- requires 500cr investment
M.type_mult = 1.4

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    if JOBS.stationFaction(ctx.station_cs) == "Concord" then return nil end
    local rx, ry = ctx.station_e:getPosition()
    local wx, wy, dist, region = ctx.spawnInVerse(rx, ry)
    if not wx then return nil end
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
        JOBS.ECONOMY.type_mult["hacking"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u)

    return {
        id             = JOBS.nextId(),
        type           = "hacking",
        tier           = tier,
        origin         = opts.origin,
        wx             = opts.wx,
        wy             = opts.wy,
        cargo          = arch.cargo,
        hack_threshold = 0.75,
        reward         = reward,
        short          = arch.short_offer,
        obj            = "Hack relay near " .. opts.origin,
        brief          = arch.lore .. "\n\n" .. arch.accept_msg
                         .. "\n\nHack any of the relay's systems to 75% to breach its datastore.",
        complete_msg   = arch.recv_msg,
        distance_u     = opts.distance_u or 0,
        region_name    = opts.region_name,
        _spawned       = false,
        _hacked        = false,
        target_cs      = nil,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.warp1 + 780)
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    return string.format("* Breach a Concord comms relay in %s.\n  %s", region, stats)
end

function M.spawn(m)
    if m._spawned then return end
    local name = _beaconName()
    local s = CpuShip():setTemplate("ANT 615"):setFaction("Concord")
    s:setCallSign(name):setTypeName("Comms Relay")
    s:setPosition(m.wx, m.wy):orderIdle():setImpulseMaxSpeed(0):setRotationMaxSpeed(0)
    s:setHullMax(50):setHull(50):setShieldsMax(0):setShields(0)
    s:setCanBeDestroyed(false)
    s:setSystemHealth("reactor", 1.0)
    s:setSystemHealth("beamweapons", 1.0)
    -- Four overlapping 120° mounts at 90° intervals → full 360° coverage at 4U.
    s:setBeamWeapon(0, 120,   0, 4000, 6, 4)
    s:setBeamWeapon(1, 120,  90, 4000, 6, 4)
    s:setBeamWeapon(2, 120, 180, 4000, 6, 4)
    s:setBeamWeapon(3, 120, 270, 4000, 6, 4)
    s:setSystemHackedLevel("reactor", 0.0)
    RT.named[name] = s
    s:setCommsFunction(function(src, tgt)
        setCommsMessage("Automated relay. No response.")
    end)
    m.target_cs = name
    m.short     = "Hack " .. name
    m.obj       = "Hack " .. name
    m._spawned  = true
end

function M.acceptLog(m)
    return string.format("Contract: %s. %dm to complete. Target: %s at grid %s.",
        m.short, math.floor(m._time_limit / 60),
        m.target_cs or "unknown", JOBS.gridRef(m.wx, m.wy))
end

local _SYSTEMS = {"reactor","beamweapons","missilesystem","maneuver","impulse","warp","jumpdrive","frontshield","rearshield"}

function M.update(m, entry, ctx)
    if m._hacked then return nil end  -- waiting for return

    local target = RT.find(m.target_cs)
    if not RT.valid(target) then
        RT.shipLog("[Hack] Relay destroyed before extraction -- contract lost.", "#FF8080")
        return "remove"
    end

    -- Every 2s: aim beams at nearest player within 4U; jam probes within 5U.
    m._last_jam_check = m._last_jam_check or 0
    if ctx.now - m._last_jam_check > 2 then
        m._last_jam_check = ctx.now

        local beam_target, beam_dist = nil, math.huge
        for _, p in ipairs(RT.players) do
            if RT.valid(p) then
                local d = RT.dist(target, p)
                if d < 4000 and d < beam_dist then
                    beam_target = p; beam_dist = d
                end
            end
        end
        if beam_target then
            target:orderAttack(beam_target)
        else
            target:orderIdle()
        end

        local rx, ry = target:getPosition()
        for _, obj in ipairs(getObjectsInRadius(rx, ry, 5000)) do
            if RT.valid(obj) and obj ~= target and isObjectType(obj, "ScanProbe") then
                obj:destroy()
                RT.shipLog("[Relay] Jamming field neutralised a probe.", "#FF8080")
            end
        end
    end

    -- Check any system hacked to threshold.
    local max_hack, hacked_sys = 0, nil
    for _, sys in ipairs(_SYSTEMS) do
        local has = false
        local ok1 = pcall(function() has = target:hasSystem(sys) end)
        if ok1 and has then
            local ok2, lvl = pcall(function() return target:getSystemHackedLevel(sys) end)
            if ok2 and lvl and lvl > max_hack then
                max_hack = lvl; hacked_sys = sys
            end
        end
    end

    if max_hack >= m.hack_threshold then
        m._hacked = true
        target:setCanBeDestroyed(true)
        m.obj = "Return " .. m.cargo .. " to " .. m.origin
        RT.shipLog("[Hack] " .. (hacked_sys or "system") .. " breach successful! Data extracted from "
            .. m.target_cs .. ". Return to " .. m.origin .. ".", "#80FF80")
        JOBS.updateObj()
    end
    return nil
end

function M.completable(m, cs)
    return m.origin == cs and m._hacked == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Deliver %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Good extraction."',
    }
end

JOBS.register(M)
