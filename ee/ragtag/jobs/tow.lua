-- ee/ragtag/jobs/tow.lua
-- Tow job type: a ship has broken down out in quiet space and called the port. The crew flies out,
-- puts a tow line on it (TOW, ee/ragtag/tow.lua: Engineering's "Attach tow line" within 2U; up to
-- half of warp 1; hauling costs energy) and brings it within DELIVER_R of the port, then docks to be paid.
-- Basic work like deliveries: common at tier 0 and tapering off as the crew moves up (the engine's
-- _TIER_WEIGHTS). The breakdown is always somewhere no patrol flies. Once the ship asking has upgraded
-- (tier 1+), a tow may draw Shroud Raiders (RAIDER_ODDS: none at tier 0, up to one at tier 1, up to two
-- at tier 2), rolled when the job is posted: the board says "Raiders about." and pays +15% a raider.
-- They show up as the crew arrives, heading for the stranded ship (their leader hails: stand off,
-- she's ours), open fire when the crew comes close or puts the line on, and break off when the tow is
-- home. The board text borrows the voice of a roadside recovery crew: "We got a
-- call...", and the acknowledge button reads "We'll get 'em home".

local DELIVER_R = 4000      -- the towed ship this close to the port: home
local MAX_DIST  = 60000     -- breakdowns are at most this far out (world units)

-- Raiders: once the crew has upgraded (job tier 1+, JOBS.maxTier of the ship asking), some tows draw
-- Shroud Raiders who come for the easy mark once the line is on. Odds of 0, 1, 2 raiders by tier;
-- rolled when the job is posted, so the board can say so and pay for it (+15% a raider).
local RAIDER_ODDS = {
    [0] = {1.0},
    [1] = {0.5, 0.5},
    [2] = {0.25, 0.35, 0.40},
}
local RAIDER_SHIPS = {"Adder MK5", "MT52 Hornet"}   -- the first raider, the second
local RAIDER_TRIGGER = 10000  -- the job's ship this close to the stranded ship: the raiders show up
local RAIDER_START   = 8000   -- this far out on the far side of her, heading for her
local RAIDER_ENGAGE  = 5000   -- they open fire when the crew is this close, or once the line is on
local RAIDER_SPEED   = 1.2    -- their impulse, as a multiple of the tow line's limit (TOW.MAX_SPEED): a tow can't outrun them
local RAIDER_ACCEL   = 150    -- impulse acceleration (world units/s^2): up to speed in about 4 s
local RAIDER_TURN    = 25     -- degrees a second, so they can come round at that speed
-- Claim jumpers dressed up as rival recovery outfits.
local _RAIDER_NAMES = {
    "Jake's Towing & Salvage", "Interspace AAA", "Finders Keepers Recovery", "No Questions Towing",
    "Honest Abe's Salvage", "Repo Rick's", "Grab & Go Recovery", "Second Owner Salvage",
    "24-Hour Hook & Haul", "Bargain Bin Recovery", "Totally Legit Towing", "Lien Machine",
    "Midnight Recovery Co.", "Dibs Salvage", "Cut Rate Towing", "Big Earl's Roadside",
}

local _ARCHETYPES = {
    {what = "a grain hauler", tmpl = "Goods Freighter 2", reward_mult = 1.0,
     call = "Grain hauler out of the Cinder Fields lost her main bus. Lights are on, engines aren't, and the skipper's been drifting long enough to start counting the stars.",
     recv_msg = '"Look at that, she\'s home. The skipper says the first round\'s on him, and he means it this time."'},
    {what = "a family transport", tmpl = "Personnel Freighter 1", reward_mult = 1.05,
     call = "Family transport blew a coupling halfway through a run. Two kids aboard who think it's the best day ever. Their parents disagree.",
     recv_msg = '"Kids are asking if they can ride on your ship next time. Parents are just glad to be docked."'},
    {what = "a fuel tender", tmpl = "Fuel Freighter 1", reward_mult = 1.1,
     call = "Fuel tender cooked her impulse coils. Ironic, sitting on a hold full of fuel she can't burn. Go easy on her, she sloshes.",
     recv_msg = '"Tender\'s on the clamps and nobody blew up. That\'s a good day in this business."'},
    {what = "a prospector's tug", tmpl = "Tug", reward_mult = 0.9,
     call = "Old prospector's tug threw a drive shaft. Fella's been flying her forty years and swears this has never happened before. It's happened before.",
     recv_msg = '"He says she\'ll be good as new by Tuesday. He said that last time too. Thanks for getting him home."'},
    {what = "a parts runner", tmpl = "Equipment Freighter 1", reward_mult = 1.0,
     call = "Parts runner hauling spares for everybody else, and now she's the one that needs fixing. Reactor scrammed and won't restart.",
     recv_msg = '"Our own mechanic gets to fix the parts runner. He\'s pretending he\'s not enjoying it."'},
    {what = "a garbage scow", tmpl = "Garbage Freighter 1", reward_mult = 0.85,
     call = "Garbage scow lost steering and she's turning slow circles out there. Nobody's in a hurry to go get her. That's why we're calling you.",
     recv_msg = '"You towed a garbage scow home and didn\'t complain once. That\'s professionalism."'},
    {what = "a courier", tmpl = "Personnel Freighter 2", reward_mult = 1.15,
     call = "Courier skipper pushed her warp past the redline to make a deadline. Made the deadline, killed the drive. Now she needs a ride home.",
     recv_msg = '"Courier\'s home. The skipper promises she\'s learned her lesson. She hasn\'t."'},
    {what = "a water hauler", tmpl = "Goods Freighter 3", reward_mult = 1.0,
     call = "Water hauler's on battery power, and she's floating in the dark with a full hold that people are waiting on.",
     recv_msg = '"Water and crew both home. Couldn\'t ask for better."'},
    {what = "a survey boat", tmpl = "Flavia", reward_mult = 1.05,
     call = "Survey boat ran her reactor dry doing one more pass. Crew's fine, a little cold. They'll be colder soon.",
     recv_msg = '"Survey crew\'s thawing out in the galley. They say they\'ll owe you forever."'},
    {what = "a mining barge", tmpl = "Equipment Freighter 3", reward_mult = 1.1, fac = "Independent",
     call = "Mining barge snapped her drive mounts trying to shift a rock she had no business shifting. She's heavy. Bring your patience.",
     recv_msg = '"Heaviest thing you\'ll tow all month, and you brought her in straight. Nice work."'},
    {what = "a Concord supply tender", tmpl = "Goods Freighter 4", reward_mult = 1.1, fac = "Concord",
     call = "Concord supply tender reports a total drive failure. They'd send their own tug, but their own tug is the one they're waiting on parts for.",
     recv_msg = '"Tender recovered. The quartermaster will pretend this never happened, but the pay\'s real."'},
}

local _NAMES = {
    "Old Reliable", "Second Chance", "Hard Luck", "Last Legs", "Patchwork", "Dust Devil", "Lemon Twist",
    "Busted Flush", "Low Gear", "Stuck Throttle", "Good Enough", "Almost There", "Sputter", "Loose Bolt",
    "Blown Gasket", "Spare Change", "Long Shot", "Tin Can", "Rattletrap", "Never Again",
}

local M = {}
M.type      = "tow"
M.weight    = 6         -- tier weights: jobs/_engine.lua _TIER_WEIGHTS
M.tier_min  = 0
M.type_mult = 1.2
M.DELIVER_R = DELIVER_R
M.ack_label    = "We'll get 'em home"   -- the button under the job details (jobs/_engine.lua _showBoard)
M.accept_outro = ""                      -- the brief ends on its own line

local function _safe(region)
    if not region then return true end   -- open space: nobody patrols it
    if (region.danger or 0) > 0 then return false end
    return not (PROX and PROX.zones and PROX.zones[region.name])
end

-- How many raiders come for a tow offered to a ship of `max_tier` (0, 1 or 2).
function M.rollRaiders(max_tier)
    local odds = RAIDER_ODDS[math.max(0, math.min(2, max_tier or 0))]
    local r = math.random()
    for n, p in ipairs(odds) do
        r = r - p
        if r <= 0 then return n - 1 end
    end
    return #odds - 1
end

-- A spot out in quiet space (no danger, no patrol zone) within MAX_DIST of the port.
function M.prepareOpts(ctx)
    if not ctx.valid(ctx.station_e) then return nil end
    local rx, ry = ctx.station_e:getPosition()
    for _ = 1, 16 do
        local wx, wy, dist, region = ctx.spawnInVerse(rx, ry)
        if wx and dist <= MAX_DIST and _safe(region) then
            return {
                origin         = ctx.station_cs,
                origin_faction = JOBS.stationFaction(ctx.station_cs),
                wx = wx, wy = wy,
                tier           = ctx.tier,
                distance_u     = dist,
                danger_level   = 0,
                raiders        = M.rollRaiders(ctx.max_tier),
                region_name    = region and region.name or nil,
                distance_min_u = ctx.distanceRange.min,
                distance_max_u = ctx.distanceRange.max,
            }
        end
    end
    return nil
end

function M.generate(opts)
    local tier = opts.tier or 0
    local sfac = opts.origin_faction
    local pool = {}
    for _, a in ipairs(_ARCHETYPES) do
        if not a.fac or not sfac or a.fac == sfac then pool[#pool + 1] = a end
    end
    if #pool == 0 then pool = _ARCHETYPES end
    local arch = pool[math.random(#pool)]
    local name = JOBS.uniqueName(_NAMES)
    local raiders = opts.raiders or 0
    local reward = JOBS.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["tow"] * (arch.reward_mult or 1),
        opts.distance_u, raiders,
        opts.distance_min_u, opts.distance_max_u, 1.0)
    local where = opts.region_name or "open space"
    local grid = getSectorName and getSectorName(opts.wx, opts.wy) or "?"
    local warning = ""
    if raiders > 0 then
        warning = '\n\n"One more thing. Raiders have been working that patch, and a ship that can\'t move is '
            .. 'an easy mark. Expect company out there. We\'ve added hazard pay."'
    end
    return {
        id           = JOBS.nextId(),
        type         = "tow",
        tier         = tier,
        origin       = opts.origin,
        wx           = opts.wx,
        wy           = opts.wy,
        what         = arch.what,
        tmpl         = arch.tmpl,
        target_cs    = name,
        reward       = reward,
        reward_mult  = arch.reward_mult or 1,
        short        = "Tow " .. name .. " home",
        obj          = "Tow " .. name,
        brief        = '"We got a call. ' .. arch.call .. '"\n\n"She\'s ' .. name .. ', dead in space in ' .. where
            .. ', grid ' .. grid .. '. Get a line on her and bring her back here, within '
            .. math.floor(DELIVER_R / 1000) .. 'U of the port. A tow line takes ' .. TOW.LIMIT_TEXT .. ', no faster: '
            .. 'warp 1 with the drive at half power, and have Science watch the speed."' .. warning,
        complete_msg = arch.recv_msg,
        distance_u   = opts.distance_u or 0,
        region_name  = opts.region_name,
        raiders      = raiders,
        _found       = false,
    }
end

-- The raiders: when the job's ship comes within RAIDER_TRIGGER of the stranded ship (or puts the
-- line on first), they appear RAIDER_START out on the far side of her and head for her: they want
-- the salvage. Their leader hails the crew to stand off. They open fire once the crew is within
-- RAIDER_ENGAGE of them or the line goes on (M.update).
function M.spawnRaiders(m)
    if m._raided or (m.raiders or 0) <= 0 or not RT.valid(m.target) then return end
    local p = JOBS.owner(m)
    if not p then return end
    m._raided = true
    local tx, ty = m.target:getPosition()
    local px, py = p:getPosition()
    local dx, dy = tx - px, ty - py
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1 then dx, dy, d = 1, 0, 1 end
    dx, dy = dx / d, dy / d
    local sx, sy = tx + dx * RAIDER_START, ty + dy * RAIDER_START
    m.raider_ships = {}
    for i = 1, m.raiders do
        local s = CpuShip():setTemplate(RAIDER_SHIPS[i] or RAIDER_SHIPS[#RAIDER_SHIPS]):setFaction("Shroud Raiders")
        s:setCallSign(JOBS.uniqueName(_RAIDER_NAMES))
        s:setImpulseMaxSpeed(TOW.MAX_SPEED * RAIDER_SPEED, 100)
        s:setAcceleration(RAIDER_ACCEL, RAIDER_ACCEL)
        s:setRotationMaxSpeed(RAIDER_TURN)
        s:setPosition(sx - dy * (i - 1) * 800, sy + dx * (i - 1) * 800)
        s:setDescriptions("Salvage outfit.", "Calls itself a recovery service. Its licence is a Shroud Raider's guns: they hunt the quiet lanes for ships that can't run and claim them as salvage.")
        s:setCommsScript(""):setCommsFunction(function()
            setCommsMessage('"Still here? Last chance, tow truck. Cut her loose and run, and you keep your ship."')
        end)
        RT.register(s)
        RT.reportKills(s)
        s:orderFlyTowards(tx, ty)
        m.raider_ships[#m.raider_ships + 1] = s
    end
    local lead = m.raider_ships[1]
    local who = lead:getCallSign()
    if m.raiders > 1 then who = who .. " and friends" end
    JOBS.log(m, "[Tow] Raiders: " .. who .. ", closing on " .. m.target_cs .. " from the far side.", "#FF8040")
    m._raid_hail = '"Well, well. Somebody sent a tow truck. Listen close, friend: that hulk\'s been ours since '
        .. 'her lights went out. Finders keepers, and we found her first. Turn your nose around and go '
        .. 'tell ' .. m.origin .. ' she sank. Nobody needs to get scratched over a busted ' .. m.what:gsub("^an? ", "") .. '."'
    if not JOBS.hail(m, lead, m._raid_hail) then
        JOBS.log(m, "[" .. lead:getCallSign() .. "] " .. m._raid_hail, "#FF8040")
    end
end

-- The raiders open fire: the crew came too close or put the line on.
local function _raidersAttack(m)
    if m._raid_attack then return end
    local p = JOBS.owner(m)
    if not p then return end
    m._raid_attack = true
    for _, s in ipairs(m.raider_ships or {}) do
        if RT.valid(s) then s:orderAttack(p) end
    end
end

-- Home: whoever is left breaks off and runs.
local function _raidersBreakOff(m)
    for _, s in ipairs(m.raider_ships or {}) do
        if RT.valid(s) then
            local x, y = s:getPosition()
            s:orderFlyTowards(x + math.random(-40000, 40000), y + math.random(-40000, 40000))
        end
    end
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.impulse + 180)
end

function M.offerText(m, stats)
    local raiders = ""
    if (m.raiders or 0) > 0 then raiders = " Raiders about." end
    return string.format("* Tow %s, %s broken down in %s, back here.%s\n  %s",
        m.target_cs, m.what, m.region_name or "open space", raiders, stats)
end

-- The broken-down ship: no engines, can't be destroyed, on TOW's list for the job's ship only.
function M.spawn(m)
    if RT.valid(m.target) then return end
    local s = CpuShip():setTemplate(m.tmpl):setFaction("Independent"):setCallSign(m.target_cs)
    s:setPosition(m.wx, m.wy):setRotation(math.random(0, 359))
    s:orderIdle():setImpulseMaxSpeed(0, 0):setRotationMaxSpeed(0):setWarpDrive(false)
    pcall(function() s:setJumpDrive(false) end)
    s:setCanBeDestroyed(false)
    s:setDescriptions("Disabled ship.", m.what:gsub("^%l", string.upper) .. ", broken down and waiting for a tow to " .. m.origin .. ".")
    s:setCommsScript(""):setCommsFunction(function()
        setCommsMessage('"Is that you? Oh, thank goodness. Get a line on us whenever you\'re ready. We\'re not going anywhere."')
    end)
    m.target = s
    TOW.offer(s, {ship = JOBS.owner(m), name = m.target_cs,
        on_attach = function()
            m.obj = "Tow " .. m.target_cs
            JOBS.updateObj()
            M.spawnRaiders(m)
        end})
end

function M.acceptLog(m)
    if m.accept_log then return m.accept_log end
    return string.format("Contract: %s. %dm to complete. %s is at grid %s.",
        m.short, math.floor(m._time_limit / 60), m.target_cs, JOBS.gridRef(m.wx, m.wy))
end

-- Home once the towed ship is within DELIVER_R of the port: off the line, and the crew docks to be paid.
function M.update(m, entry, ctx)
    if m._found or not RT.valid(m.target) then return nil end
    local p = JOBS.owner(m)
    if p and (m.raiders or 0) > 0 then
        if not m._raided and RT.dist(p, m.target) <= RAIDER_TRIGGER then M.spawnRaiders(m) end
        if m._raided and not m._raid_attack then
            local close = TOW.towedBy(m.target) == p
            for _, s in ipairs(m.raider_ships or {}) do
                if RT.valid(s) and RT.dist(p, s) <= RAIDER_ENGAGE then close = true end
            end
            if close then _raidersAttack(m) end
        end
    end
    local port = RT.find(m.origin)
    if not RT.valid(port) then return nil end
    if RT.dist(port, m.target) <= DELIVER_R then
        TOW.withdraw(m.target)
        m._found = true
        _raidersBreakOff(m)
        m.obj = "Return to " .. m.origin
        JOBS.log(m, "[Tow] " .. m.target_cs .. " is home. The port's crew takes her from here. Dock at "
            .. m.origin .. " to get paid.", "#80FF80")
        JOBS.updateObj()
    end
    return nil
end

function M.cleanup(m)
    for _, s in ipairs(m.raider_ships or {}) do
        if RT.valid(s) then s:destroy() end
    end
    m.raider_ships = nil
    if m.target then
        TOW.withdraw(m.target)
        if RT.valid(m.target) then m.target:setCanBeDestroyed(true); m.target:destroy() end
        m.target = nil
    end
end

function M.completable(m, cs)
    return m.origin == cs and m._found == true
end

function M.completeReply(m, entry)
    return {
        label = string.format("Got 'em home (+%d cr)", m.reward),
        msg   = entry.mission.complete_msg or '"Home safe. Good work."',
    }
end

JOBS.register(M)
