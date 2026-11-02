-- ee/ragtag/jobs/salvage.lua
-- Salvage job type: recover cargo pods from open space.

local _ARCHETYPES = {
    -- Any faction
    {cargo="a drifting cargo pod", urgent=false, reward_mult=1.0, tier_min=0,
     lore="Sealed container off a freighter. Transponder's still pinging.",
     accept_msg='"Finder\'s fee. Bring it back intact."',
     recv_msg='"Container secured. That\'s what we were hoping for."'},
    {cargo="an emergency beacon kit", urgent=false, reward_mult=0.9, tier_min=0,
     lore="Evac pod came down in the field. No crew — just the kit. Still useful to someone.",
     accept_msg='"Salvage rights are clear. Just go get it."',
     recv_msg='"That kit will save someone\'s life eventually."'},
    {cargo="a lost survey drone", urgent=false, reward_mult=1.1, tier_min=0,
     lore="Mapping probe went dark after passing through a debris cloud. Data core may still be intact.",
     accept_msg='"If the core is readable, there\'s a bonus."',
     recv_msg='"Data core intact. The bonus is yours."'},
    {cargo="ore pods from a disabled freighter", urgent=false, reward_mult=0.9, tier_min=0,
     lore="Standard loss. The freighter broke drive mid-haul and couldn't recover the pods.",
     accept_msg='"They\'ve got salvage rights. We\'re the salvage."',
     recv_msg='"Pods accounted for. Loss is recoverable."'},
    {cargo="a ship's flight recorder", urgent=false, reward_mult=1.0, tier_min=0,
     lore="A wreck nobody is officially looking for. The recorder is required for the insurance claim.",
     accept_msg='"Don\'t look at what\'s on it. Just bring it back."',
     recv_msg='"Recorder received. Claim proceeds."'},
    {cargo="a dead ship's water reserves", urgent=false, reward_mult=0.9, tier_min=0,
     lore="Ship went silent six months ago. Water bladders were sealed before life support failed.",
     accept_msg='"Worth checking. Nothing else is going to get them."',
     recv_msg='"Reserves intact. That\'s a month of buffer stock."'},
    {cargo="salvage from a crashed shuttle", urgent=false, reward_mult=0.95, tier_min=0,
     lore="Shuttle made it down but didn't make it back up. Nobody was hurt; cargo is still there.",
     accept_msg='"Surface recovery. Bring what\'s intact."',
     recv_msg='"Most of it survived. Better than we expected."'},
    {cargo="an ejected reactor assembly", urgent=false, reward_mult=1.3, tier_min=1,
     lore="Crew jettisoned it before the hull breach. Cold and drifting but intact.",
     accept_msg='"Handle it carefully — salvageable, barely."',
     recv_msg='"Still viable. Well done."'},
    {cargo="personal effects of the deceased", urgent=false, reward_mult=0.85, tier_min=0,
     lore="Family is waiting at the destination. One sealed container.",
     accept_msg='"It\'s all they have left of them. Be careful."',
     recv_msg='"Thank you. We can close the chapter now."'},
    {cargo="a medical supply cache", urgent=false, reward_mult=1.0, tier_min=0,
     lore="A derelict station module still has sealed medical stores. Someone got out in a hurry.",
     accept_msg='"Medical supplies stay sterile in vacuum. Bring what\'s there."',
     recv_msg='"Sealed and clean. These will be useful."'},
    {cargo="a navigation computer from a wreck", urgent=false, reward_mult=1.1, tier_min=1,
     lore="An old ship, a relatively recent nav system. The data it carries may be worth more than the hardware.",
     accept_msg='"Pull the core. Don\'t care about the rest."',
     recv_msg='"Route data intact. There\'s more here than we expected."'},
    {cargo="a crate of printed books", urgent=false, reward_mult=0.9, tier_min=0,
     lore="Paper books in the black — almost extinct out here. A collector paid the finder's fee up front.",
     accept_msg='"Peculiar cargo. Bring it back anyway."',
     recv_msg='"Every volume intact. The collector is very pleased."'},
    {cargo="life support modules from a stripped hulk", urgent=false, reward_mult=0.9, tier_min=0,
     lore="The hull is gone but the support modules are still in their housings.",
     accept_msg='"Standard salvage. Pull what\'s still attached."',
     recv_msg='"Systems check out. These will find a home."'},
    {cargo="a repairable power cell array", urgent=false, reward_mult=1.0, tier_min=0,
     lore="Fire-damaged but probably salvageable. Worth the trip to find out.",
     accept_msg='"If it can be repaired, it\'s worth three times what we\'re paying."',
     recv_msg='"Three of the six cells are good. Better than nothing."'},
    {cargo="a distress buoy with a recorded message", urgent=false, reward_mult=1.0, tier_min=0,
     lore="Buoy is still transmitting. Someone wants to know what the message says.",
     accept_msg='"Bring the buoy back intact. The message matters more than the hardware."',
     recv_msg='"Message received. This tells us something important."'},
    {cargo="mining claim markers from an abandoned site", urgent=false, reward_mult=0.85, tier_min=0,
     lore="Claim abandoned three years ago. Markers are legally eligible for recovery and re-filing.",
     accept_msg='"Routine claim recovery. Standard rates."',
     recv_msg='"Markers logged. The claim is re-filed."'},
    {cargo="a prototype component from an unregistered ship", urgent=false, reward_mult=1.5, tier_min=2,
     lore="The wreck doesn't appear in any registry. What it's carrying is something new.",
     accept_msg='"Don\'t damage it. We don\'t know what it does."',
     recv_msg='"Extraordinary. Where did this come from."'},
    {cargo="a prospector's survey kit", urgent=false, reward_mult=1.0, tier_min=0,
     lore="A solo prospector didn't come back. Their kit holds claim data — and next of kin might want to know.",
     accept_msg='"Bring the kit and any personal effects."',
     recv_msg='"Claims logged. Family notified. You did right."'},
    {cargo="a biometric scanner with footage intact", urgent=false, reward_mult=1.2, tier_min=1,
     lore="An abandoned station checkpoint. Scanner stopped transmitting but may hold local recordings.",
     accept_msg='"Pull the storage core. Don\'t review the footage."',
     recv_msg='"Footage recovered. You didn\'t look, did you."'},
    {cargo="a sealed personal lockbox", urgent=false, reward_mult=0.9, tier_min=0,
     lore="Washed out of a wreck on the edge of a debris field. Someone's name is etched on the lid.",
     accept_msg='"Find the family. Keep whatever\'s inside as a bonus."',
     recv_msg='"Thank you. We\'d given up on this."'},
    {cargo="a corporate flight recorder", urgent=false, reward_mult=1.3, tier_min=1,
     lore="A wreck that nobody is officially looking for. The recorder is worth more than the hull.",
     accept_msg='"Don\'t look at what\'s on it. Just bring it back."',
     recv_msg='"We\'ll take it from here. You didn\'t find this."'},
    {cargo="a sealed courier pouch from a lost ship", urgent=true, reward_mult=1.2, tier_min=1,
     lore="A courier ran into trouble. The ship is gone, but the pouch is hardened and should have survived.",
     accept_msg='"Delivery contract is intact if the pouch is. Same rate."',
     recv_msg='"Seal\'s unbroken. Contract honoured."'},
    -- Concord stations only
    {cargo="wreckage items from a Concord patrol", urgent=true, reward_mult=1.1, tier_min=0, fac="Concord",
     lore="A patrol didn't report in. Concord wants its weapons back before anyone else finds the site.",
     accept_msg='"Recover the armaments before the site attracts wrong attention."',
     recv_msg='"Armaments secured. We\'ll handle the report from here."'},
    {cargo="a missing officer's personal data drive", urgent=false, reward_mult=1.2, tier_min=0, fac="Concord",
     lore="Personal drive from a vessel lost in the line of duty. May contain sensitive information.",
     accept_msg='"Sealed retrieval. Don\'t read it."',
     recv_msg='"Drive secured. Thank you."'},
    {cargo="a classified survey buoy", urgent=false, reward_mult=1.3, tier_min=1, fac="Concord",
     lore="A survey buoy drifted off its registered position. Its data is classified.",
     accept_msg='"Retrieve it before a civilian craft finds it."',
     recv_msg='"Buoy recovered. Data intact. Well done."'},
    {cargo="an evidence container from a closed investigation", urgent=false, reward_mult=1.2, tier_min=1, fac="Concord",
     lore="Evidence from a case that got complicated. Concord needs it but can't send an official crew.",
     accept_msg='"Chain of custody is critical. Bring it back sealed."',
     recv_msg='"Seal intact. The case can proceed."'},
    {cargo="a crew manifest from a ship that never existed", urgent=false, reward_mult=1.4, tier_min=1, fac="Concord",
     lore="Classified vessel, deniable crew. The manifest is the only record.",
     accept_msg='"This doesn\'t leave your hands until it\'s in mine."',
     recv_msg='"Received. This never happened."'},
    {cargo="a medical experiment container", urgent=true, reward_mult=1.3, tier_min=1, fac="Concord",
     lore="A Concord research vessel was lost with experiment specimens aboard. Some must still be viable.",
     accept_msg='"Cold-chain recovery. Some of these need to stay frozen."',
     recv_msg='"Specimens viable. The research continues."'},
    {cargo="an encrypted comms relay from a downed patrol", urgent=false, reward_mult=1.2, tier_min=1, fac="Concord",
     lore="A border patrol relay went down and drifted. Encryption keys can be extracted if recovered intact.",
     accept_msg='"Don\'t damage it. The keys are in the firmware."',
     recv_msg='"Keys extracted. The network is whole again."'},
    {cargo="military ID tags from a classified engagement", urgent=false, reward_mult=1.0, tier_min=0, fac="Concord",
     lore="Personnel tags from an action that isn't in the public record. Families deserve to know.",
     accept_msg='"Recover them all. Every tag matters."',
     recv_msg='"Tags logged. Families will be notified through proper channels."'},
    {cargo="a sealed audit report on Concord contracting", urgent=false, reward_mult=1.6, tier_min=2, fac="Concord",
     lore="A report that certain parties within Concord would rather remained lost.",
     accept_msg='"Recover it before someone gets to it first."',
     recv_msg='"Report secured. The wrong people do not know we have this."'},
    {cargo="sensor data from a downed surveillance array", urgent=false, reward_mult=1.3, tier_min=1, fac="Concord",
     lore="An array went dark six months ago. The data it captured before going down is still on board.",
     accept_msg='"Recover the storage module. Don\'t review what\'s on it."',
     recv_msg='"Module recovered. Six months of data. Significant."'},
    {cargo="requisition crates from an ambushed supply run", urgent=true, reward_mult=1.2, tier_min=1, fac="Concord",
     lore="Supply convoy was hit. Crates are scattered across the debris field but intact.",
     accept_msg='"Corsair activity in the area. Move fast."',
     recv_msg='"Supplies recovered. Logistics chain restored."'},
    {cargo="Concord armory key cards", urgent=false, reward_mult=1.1, tier_min=1, fac="Concord",
     lore="Authorization cards from a vessel lost in the Boneyard. They can still open Concord armories.",
     accept_msg='"Find them before someone else does. Those cards are live."',
     recv_msg='"Cards recovered and deactivated. Thank you."'},
    {cargo="a critical sample kit from a crash", urgent=true, reward_mult=1.3, tier_min=1, fac="Concord",
     lore="An evac shuttle went down. The evacuee survived, but their medical sample kit didn't reach the pickup.",
     accept_msg='"Find the kit. The patient\'s treatment depends on those samples."',
     recv_msg='"Kit recovered. Patient will be alright."'},
    {cargo="a forensic data core from a destroyed patrol", urgent=false, reward_mult=1.5, tier_min=2, fac="Concord",
     lore="The ship was destroyed, but the core is hardened. It holds evidence from a major investigation.",
     accept_msg='"Find it. The case depends on it."',
     recv_msg='"Core recovered. Encryption intact. The investigation continues."'},
    {cargo="a classified navigation chart in a standard pod", urgent=false, reward_mult=1.5, tier_min=2, fac="Concord",
     lore="Someone embedded a classified chart inside an ordinary cargo pod, then the ship carrying it was lost.",
     accept_msg='"Scan every pod at those coordinates until you find the right one."',
     recv_msg='"Chart recovered. This changes a few patrol routes."'},
    -- Independent stations only
    {cargo="a cargo pod that fell off a manifest", urgent=false, reward_mult=1.3, tier_min=0, fac="Independent",
     lore="Standard freighter, standard route — except this pod isn't on the manifest.",
     accept_msg='"Finder\'s rights are clear. Bring it in."',
     recv_msg='"No questions asked. Good haul."'},
    {cargo="a personal stash cache", urgent=false, reward_mult=1.1, tier_min=0, fac="Independent",
     lore="The owner's gone. It's been floating long enough that salvage rights are yours.",
     accept_msg='"Finders keep. Standard field rules."',
     recv_msg='"Useful stuff. Good eye."'},
    {cargo="emergency supplies from a failed settlement", urgent=false, reward_mult=0.9, tier_min=0, fac="Independent",
     lore="The colony didn't make it but the supply caches are still intact.",
     accept_msg='"A lot of it is still good. Worth the trip."',
     recv_msg='"Most of it usable. Sad way to source supplies, but here we are."'},
    {cargo="the payload from a dud torpedo", urgent=false, reward_mult=1.8, tier_min=2, fac="Independent",
     lore="It didn't detonate. The warhead is probably stable. The payload inside is worth considerably more.",
     accept_msg='"Don\'t jostle it. We mean that literally."',
     recv_msg='"Intact. Careful work. You don\'t want to know what\'s inside."'},
    {cargo="a corporate research pod", urgent=false, reward_mult=1.5, tier_min=2, fac="Independent",
     lore="The company will pay to get it back. Their competitors will pay more. We're not the company.",
     accept_msg='"Come to us first. We\'ll make it worth your while."',
     recv_msg='"This is valuable. Very valuable. We\'ll handle distribution."'},
    {cargo="a data vault from a corporate accident", urgent=false, reward_mult=1.6, tier_min=2, fac="Independent",
     lore="The ship suffered an 'accident' that looked convenient. The vault survived.",
     accept_msg='"We\'re paying more. Bring it to us."',
     recv_msg='"The contents of this are going to make some people very nervous."'},
    {cargo="an unlabeled equipment case with no manifest", urgent=false, reward_mult=1.3, tier_min=1, fac="Independent",
     lore="No markings. No manifest. Still floating in the debris field three months after the wreck.",
     accept_msg='"We\'ll pay for delivery. No need to know what\'s inside."',
     recv_msg='"Perfect. Exactly what we were looking for."'},
    {cargo="a smuggler's cache inside an ore pod", urgent=false, reward_mult=1.4, tier_min=1, fac="Independent",
     lore="Standard ore pod on the outside. Not on the inside.",
     accept_msg='"The inventory is liquid. We\'ll clear it."',
     recv_msg='"Clean salvage. Good find."'},
    {cargo="personal cargo from a crew that didn't make it", urgent=false, reward_mult=1.0, tier_min=0, fac="Independent",
     lore="The ship was lost, the crew was lost, but their private cargo is still drifting.",
     accept_msg='"Field salvage. Finder\'s rights. No one is coming for it."',
     recv_msg='"Recovered. We\'ll see if any of it finds its way home."'},
    {cargo="a diplomatic pouch lost for three years", urgent=false, reward_mult=1.5, tier_min=2, fac="Independent",
     lore="Lost before it could be delivered. Three years later, the negotiation it was part of is unresolved.",
     accept_msg='"Bring it intact. We may finally be able to close the deal."',
     recv_msg='"Seal intact after three years. Remarkable. This changes things."'},
    {cargo="a collector's piece in a standard ore pod", urgent=false, reward_mult=1.2, tier_min=1, fac="Independent",
     lore="Someone hid a very expensive piece of art inside an ore pod before their ship was seized.",
     accept_msg='"We know which pod. Go get it."',
     recv_msg='"The piece is undamaged. Remarkable."'},
    {cargo="very expensive medical equipment", urgent=false, reward_mult=1.2, tier_min=1, fac="Independent",
     lore="Surgical robot, still in its protective housing. Worth more than some ships.",
     accept_msg='"Bring it back in one piece. That\'s all."',
     recv_msg='"Functional. We can find a buyer for this."'},
    {cargo="a prototype weapon from a staged accident", urgent=false, reward_mult=1.7, tier_min=2, fac="Independent",
     lore="The 'accident' was arranged to get this off a manifest before it could be cataloged.",
     accept_msg='"Don\'t fire it. We\'re serious."',
     recv_msg='"Intact. You earned the full rate."'},
    {cargo="a nav database from a grey-market ship", urgent=false, reward_mult=1.5, tier_min=2, fac="Independent",
     lore="Every hidden route, dead drop, and unregistered port this ship ever used — all on one drive.",
     accept_msg='"The drive is more valuable than anything else on that ship."',
     recv_msg='"Routes verified. This is years of work. Good find."'},
    {cargo="a weapons locker", urgent=true, reward_mult=1.4, tier_min=2, fac="Independent",
     lore="Patrol ship went down hard. The armory container ejected clean. Concord will want it, but finders keep it.",
     accept_msg='"Manifest says it\'s unsecured. Move fast."',
     recv_msg='"Secured. We\'ll keep this one quiet."'},
}

-- Expose for combat drops (other systems reference MISSION.SALVAGE_ARCHETYPES).
MISSION.SALVAGE_ARCHETYPES = _ARCHETYPES

local _DECOY_LORE = {
    "Pressurised coolant drum — salvage value, no mission relevance.",
    "Fuel cell casing, empty. Useful for the alloy.",
    "Structural debris, stripped clean.",
    "Machine components, fire-damaged.",
}
local _DECOY_CARGO = {"Scrap Metal", "Coolant Residue", "Spent Fuel Cells", "Salvage Debris"}

local function _cleanCluster(m)
    if not m._cluster then return end
    for _, e in ipairs(m._cluster) do
        if not e._materialized and RT.valid(e.marker) then
            e.marker:setCanBeDestroyed(true)
            e.marker:destroy()
        end
    end
end

local M = {}
M.type      = "salvage"
M.weight    = 7
M.tier_min  = 0
M.type_mult = 1.2

function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    local wx, wy, dist, region = ctx.spawnInVerse(rx, ry)
    if not wx then return nil end
    return {
        origin         = ctx.station_cs,
        origin_faction = MISSION.stationFaction(ctx.station_cs),
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
    local urgent = arch.urgent or false
    local reward = MISSION.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["salvage"],
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u,
        urgent and 1.5 or 1.0)
    local prefix = urgent and "URGENT: " or ""

    return {
        id           = MISSION.nextId(),
        type         = "salvage",
        tier         = tier,
        origin       = opts.origin,
        wx           = opts.wx,
        wy           = opts.wy,
        cargo        = arch.cargo,
        reward       = reward,
        short        = prefix .. arch.cargo,
        obj          = "Recover " .. arch.cargo,
        brief        = arch.lore .. "\n\n" .. arch.accept_msg,
        complete_msg = arch.recv_msg,
        urgent       = urgent,
        distance_u   = opts.distance_u or 0,
        region_name  = opts.region_name,
        _found       = false,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    if m.urgent then
        return math.floor(2 * d / JOBS.SPEED.warp1 + 180)
    else
        return math.floor(2 * d / JOBS.SPEED.impulse + 180)
    end
end

function M.offerText(m, stats)
    local region = m.region_name or "open space"
    local prefix = m.urgent and "URGENT: " or ""
    return string.format("● %sRecover %s from %s.\n  %s", prefix, m.cargo, region, stats)
end

function M.spawn(m)
    if m._spawned then return end
    local n = math.random(3, 5)
    local target_idx = math.random(1, n)
    m._cluster = {}
    for i = 1, n do
        local angle  = (i - 1) * (360 / n) + math.random(-20, 20)
        local spread = math.random(1500, 4000)
        local cx = m.wx + math.cos(math.rad(angle)) * spread
        local cy = m.wy + math.sin(math.rad(angle)) * spread
        local pod = CpuShip():setTemplate("MT52 Hornet"):setFaction("Unknown")
        pod:setPosition(cx, cy):setCallSign("Unknown Salvage"):orderIdle()
        pod:setCanBeDestroyed(false):setScanningParameters(1, 1)
        if i == target_idx then
            pod:setDescriptions(
                "Unidentified salvage container — have Science scan to identify",
                "Mission Cargo: " .. m.cargo .. ". Retrieve and return to " .. m.origin .. ".")
            m._cluster[i] = {marker=pod, is_target=true,  _materialized=false}
        else
            local di = math.random(#_DECOY_CARGO)
            pod:setDescriptions(
                "Unidentified salvage container — have Science scan to identify",
                _DECOY_LORE[di])
            m._cluster[i] = {marker=pod, is_target=false, cargo=_DECOY_CARGO[di], _materialized=false}
        end
        RT.register(pod)
    end
    m._spawned = true
end

function M.acceptLog(m)
    return string.format("Contract: %s. %dm to complete. Head to grid %s.",
        m.short, math.floor(m._time_limit / 60), MISSION.gridRef(m.wx, m.wy))
end

function M.update(m, entry, ctx)
    -- Cargo pod destroyed before pickup → mission lost.
    if m.cargo_obj and not RT.valid(m.cargo_obj) then
        RT.shipLog("[Salvage] Cargo destroyed — contract lost.", "#FF8080")
        _cleanCluster(m)
        return "remove"
    end

    if m._found then return nil end  -- waiting for return to station

    -- Scan the cluster: materialise a SupplyDrop when each pod is identified.
    if not m._cluster then return nil end
    for _, ce in ipairs(m._cluster) do
        if not ce._materialized and RT.valid(ce.marker) then
            local scanned = false
            for _, p in ipairs(RT.players) do
                if ce.marker:isFullyScannedBy(p) then scanned = true; break end
            end
            if scanned then
                local mx, my = ce.marker:getPosition()
                ce.marker:setCanBeDestroyed(true); ce.marker:destroy()
                ce._materialized = true
                local drop = SupplyDrop():setFaction("Independent"):setPosition(mx, my)
                RT.register(drop)
                if ce.is_target then
                    local cargo_name = m.cargo:gsub("^%l", string.upper)
                    drop:setDescriptions("Salvage Container", m.cargo):setCallSign(cargo_name)
                    drop:onPickUp(function(self, player)
                        for _, ae in ipairs(JOBS._active) do
                            local mis = ae.mission
                            if mis.type == "salvage" and mis.cargo_obj == self then
                                mis._found = true
                                mis.obj    = "Return " .. mis.cargo .. " to " .. mis.origin
                                RT.shipLog("[Salvage] Cargo collected: " .. mis.cargo
                                    .. ". Return to " .. mis.origin .. " for payment.", "#80FF80")
                                JOBS.updateObj()
                                break
                            end
                        end
                    end)
                    m.cargo_obj = drop
                else
                    local label = ce.cargo or "Salvage Debris"
                    drop:setDescriptions("Standard Salvage", label):setCallSign(label)
                    drop:onPickUp(function(self, player)
                        player:setReputationPoints(player:getReputationPoints() + math.random(25, 50))
                        RT.shipLog("[Salvage] Standard debris recovered — small bonus.", "#FFFF80")
                    end)
                end
            end
        end
    end
    return nil
end

function M.expire(m)
    _cleanCluster(m)
    RT.shipLog("[Contract] " .. m.short .. " -- time expired. Contract lost.", "#FF8080")
    if m.origin_faction then
        RT.addReputation(m.origin_faction, -2 * m.reward, "failed: " .. m.short)
    end
    return true  -- suppress default engine expiry handling
end

function M.cleanup(m)
    _cleanCluster(m)
end

function M.completable(m, cs)
    return m.origin == cs and m._found == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Deliver %s (+%d cr)", m.cargo, m.reward),
        msg   = entry.mission.complete_msg or '"Received. Good work."',
    }
end

JOBS.register(M)
