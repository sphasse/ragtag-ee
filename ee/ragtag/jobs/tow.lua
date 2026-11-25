-- ee/ragtag/jobs/tow.lua
-- Tow job type: a ship has broken down out in quiet space and called the port. The crew flies out,
-- puts a tow line on it (TOW, ee/ragtag/tow.lua: Engineering's "Attach tow line" within 2U; up to
-- warp 1; hauling costs energy) and brings it within DELIVER_R of the port, then docks to be paid.
-- Basic work like deliveries: common at tier 0 and tapering off as the crew moves up (the engine's
-- _TIER_WEIGHTS). No resistance: the breakdown is always somewhere no patrol flies (a later variant
-- may add an intercept). The board text borrows the voice of a roadside recovery crew: "We got a
-- call...", and the acknowledge button reads "We'll get 'em home".

local DELIVER_R = 4000      -- the towed ship this close to the port: home
local MAX_DIST  = 60000     -- breakdowns are at most this far out (world units)

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
    local reward = JOBS.calcReward(
        JOBS.ECONOMY.base_reward[tier],
        JOBS.ECONOMY.type_mult["tow"] * (arch.reward_mult or 1),
        opts.distance_u, opts.danger_level,
        opts.distance_min_u, opts.distance_max_u, 1.0)
    local where = opts.region_name or "open space"
    local grid = getSectorName and getSectorName(opts.wx, opts.wy) or "?"
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
            .. math.floor(DELIVER_R / 1000) .. 'U of the port. Warp 1 is as fast as a tow line takes."',
        complete_msg = arch.recv_msg,
        distance_u   = opts.distance_u or 0,
        region_name  = opts.region_name,
        _found       = false,
    }
end

function M.duration(m)
    local d = m.distance_u or 60000
    return math.floor(2 * d / JOBS.SPEED.impulse + 180)
end

function M.offerText(m, stats)
    return string.format("* Tow %s, %s broken down in %s, back here.\n  %s",
        m.target_cs, m.what, m.region_name or "open space", stats)
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
    local port = RT.find(m.origin)
    if not RT.valid(port) then return nil end
    if RT.dist(port, m.target) <= DELIVER_R then
        TOW.withdraw(m.target)
        m._found = true
        m.obj = "Return to " .. m.origin
        JOBS.log(m, "[Tow] " .. m.target_cs .. " is home. The port's crew takes her from here. Dock at "
            .. m.origin .. " to get paid.", "#80FF80")
        JOBS.updateObj()
    end
    return nil
end

function M.cleanup(m)
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
