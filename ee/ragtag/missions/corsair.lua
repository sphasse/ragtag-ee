-- ee/ragtag/missions/corsair.lua
-- The Corsair Arc: help Blackwater hold the wall against the Concord's second battle group.
--
-- Trigger: upgrades >= 1000, corsair_arc_done unset; the hook fires when the crew enters the
-- Gauntlet. Design notes: corsair.md. Linear: defend, or don't do it.
--
--   hook      a Corsair raider (Long Memory) hails without attacking: follow us to Blackwater
--   escort    follow the guide; Corsair territory is friendly for now; dock at Blackwater
--   briefing  Reva Okonkwo explains, and asks the crew to raid a Concord forward depot
--   raid      two commandable Corsair ships: form up -> attack defenders -> board and loot
--             (both lost: the raid restarts with fresh ships and defenders)
--   return    dock at Blackwater: the mine-wall trap is laid; the attack fleet is detected;
--             join the defense or decline (= failed)
--   battle    the fleet follows scripted waypoints along the wall, through the 3U gap, to
--             Blackwater. All destroyed -> defended; Blackwater falls -> failed. The tender
--             CSR Magazine holds the rest of the depot haul behind the wall: when the crew's
--             racks run low it calls them in, and coming alongside reloads them (limited loads)
--
-- RT.flag keys (prefix "corsair_"):
--   hook, arrived, briefed, raid_done, joined   progress (session routing in init)
--   arc_done        "defended" | "failed" | "declined"
--   battlegroup_destroyed, ally                 exports (Maw finale, Arc 6)
--   rewarded        pay-once guard;  met_reva   Science DB profile (SCIDB.meet)

local M = {}
M.id             = "corsair"
M.name           = "Corsair Arc"
M.repeatable     = false
M.locks_jobs     = false
M.auto_start     = true
M.start_phase    = "init"
M.no_auto_cancel = true

M.triggers = {
    upgrades_min = 1000,
    not_flagged  = {"corsair_arc_done"},
    -- Phase II, like Ledger and Boneyard: after the Rezkov arc (finished or declined).
    requires       = function() return RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined") end,
    requires_label = "Rezkov arc finished or declined",
}

M.phase_order = {"init", "hook", "escort", "briefing", "raid", "return", "battle"}

local U = 1000

-- ── Places (world units) ─────────────────────────────────────────────────────
local _GAUNTLET_X, _GAUNTLET_Y, _GAUNTLET_R = 23 * U, 69 * U, 29 * U
local _BW_X, _BW_Y = 55 * U, 99 * U                 -- Blackwater station
local _BW_R        = 22 * U                         -- Blackwater Reach (region r21)
local _DEPOT_X, _DEPOT_Y = -60 * U, 62 * U          -- Concord forward depot, between Cinder and Tamsin

-- The wall: west of Blackwater on the edge of the Veil, from the Gauntlet belt (north) south.
-- One 3U gap. Mines are laid "pirate style": wobbling, never more than _MINE_MAX_GAP apart.
local _WALL_X        = 36 * U
local _WALL_N, _WALL_S = 75 * U, 120 * U
local _GAP_Y, _GAP_W = 91 * U, 3 * U
local _MINE_MAX_GAP  = 0.7 * U   -- trigger radius is 0.6U: no way through
local _MINE_AVOID    = 0.8 * U   -- AI keep-out bubble (stock 1.2U would close a 3U gap for the AI)

-- Corsair warp jammers: the last stretch of the approach and the gap, so the fleet arrives at
-- impulse and one or two at a time.
local _TRAP_JAMMERS = {
    {x = 30 * U, y = 97 * U, r = 3 * U},
    {x = 37.5 * U, y = 91 * U, r = 2.5 * U},
}

-- Attack fleet: spawns west of the wall, then flies waypoints along its west face, through the
-- gap, and on to Blackwater (FlyTowards: engages enemies that come close, then carries on).
local _FLEET_X, _FLEET_Y = 14 * U, 112 * U
local _FLEET_WAYPOINTS = {
    {31 * U, 110 * U},     -- the south end of the wall's west face
    {31 * U, 95 * U},      -- along the face (into the jammer field)
    {33.5 * U, 91 * U},    -- line up on the gap
    {39 * U, 91 * U},      -- through
    {_BW_X, _BW_Y},        -- Blackwater
}
local _FLEET = {
    {cs = "CNS Retribution", tmpl = "Atlantis X23"},
    {cs = "CNS Remand",      tmpl = "Atlantis X23"},
    {cs = "CNS Writ",        tmpl = "Phobos T3"},
    {cs = "CNS Summons",     tmpl = "Phobos T3"},
    {cs = "CNS Levy",        tmpl = "Phobos T3"},
    {cs = "CNS Distraint",   tmpl = "Phobos T3"},
}

-- ── Tuning ───────────────────────────────────────────────────────────────────
local _LOAD_TIME      = 30          -- seconds the raid escorts spend loading the haul
local _PLAYER_MINES   = 4           -- mines from the haul for the crew's rear tube
local _BW_FALLS_AT    = 0.2         -- Blackwater hull fraction that counts as fallen
local _GUIDE_WAIT_D   = 8 * U       -- the guide waits when the crew falls this far behind

-- The munitions tender: the rest of the Anvil haul, behind the wall north of the fleet's road
-- from the gap to Blackwater, so the crew can pull back and rearm mid-battle.
local _TENDER_X, _TENDER_Y = _WALL_X + 7 * U, _GAP_Y - 9 * U   -- (43, 82)
local _RELOADS       = 3            -- full loads aboard
local _RELOAD_R      = 1.2 * U      -- "alongside"
local _RELOAD_TIME   = 8            -- seconds alongside to transfer a load
local _LOW_AT        = 0.25         -- racks at or below this share count as running low
local _MISSILES      = {"Homing", "HVLI", "Mine", "EMP"}

function M.init_state()
    return {
        guide = nil, hook_hailed = false, guide_waiting = false,
        depot = nil, defenders = {}, escorts = {}, attacking = false, boarding = false,
        defenders_down = false, load_t0 = nil,
        mines = {}, trap_jammers = {}, trap_built = false, mines_given = false,
        fleet = {}, wp = {}, allies = {}, cjam = {}, fleet_spawned = false,
        tender = nil, reloads = _RELOADS, reload_t0 = nil, low_called = false, tender_lost = false,
    }
end

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function _blackwater() return RT.find("Blackwater") end

local function _grid(x, y) return JOBS.gridRef(x, y) end

-- ── Corsair territory: friendly while the arc runs, and for good once allied ─────────────────

local function _corsairShipsIn(fac)
    local out = {}
    for _, area in ipairs({{_GAUNTLET_X, _GAUNTLET_Y, _GAUNTLET_R}, {_BW_X, _BW_Y, _BW_R}}) do
        for _, o in ipairs(getObjectsInRadius(area[1], area[2], area[3])) do
            if isObjectType(o, "CpuShip") then
                local ok, f = pcall(function() return o:getFaction() end)
                if ok and f == fac then out[#out + 1] = o end
            end
        end
    end
    return out
end

local function _blackwaterComms(src, tgt) end   -- forward (defined with the dialogs)

local function _befriend()
    for _, s in ipairs(_corsairShipsIn("Corsairs")) do
        s:setFaction("Corsair Friendly")
        s:setCommsFunction(function() setCommsMessage('"Friend of Blackwater. Fly safe."') end)
    end
    local bw = _blackwater()
    if RT.valid(bw) then
        bw:setFaction("Corsair Friendly")
        bw:setCommsFunction(ARC.comms(function(src, tgt) _blackwaterComms(src, tgt) end, '"Blackwater."'))
    end
    PROX.suspendZone("the Gauntlet")
    PROX.suspendZone("Blackwater Reach")
end

local function _unfriend(st)
    local own = {}
    for _, list in ipairs({{st.guide}, st.escorts or {}, st.allies or {}}) do
        for _, s in ipairs(list) do if s then own[s] = true end end
    end
    for _, s in ipairs(_corsairShipsIn("Corsair Friendly")) do
        if not own[s] then
            s:setFaction("Corsairs")
            s:setCommsFunction(function()
                setCommsMessage("\"Corsair space, little freighter. Your cargo or your hull - we're easy either way.\"")
            end)
        end
    end
    local bw = _blackwater()
    if RT.valid(bw) then
        bw:setFaction("Corsairs")
        bw:setCommsFunction(function()
            setCommsMessage("\"Wrong neighbourhood, freighter. Turn around or we'll take your hull for scrap.\"")
        end)
    end
    PROX.resumeZone("the Gauntlet")
    PROX.resumeZone("Blackwater Reach")
end

-- ── The guide (Long Memory) ──────────────────────────────────────────────────

-- The crew said "not right now": the raider leaves, the hook stays open. Another contact (the
-- Greywater message, or entering the Gauntlet again) can try after _REASK_DELAY.
local _REASK_DELAY = 10 * 60
local function _deferHook(st)
    st.deferred_until = getScenarioTime() + _REASK_DELAY
    st.hook_hailed, st.hail_when_near, st.hook_at = false, false, nil
    RT.clearObjective("corsair")
    -- The raider flies off and is removed a minute later. It stays in st.guide_leaving so a
    -- reset inside that minute (GM jump, cancel) still removes it.
    local g = st.guide
    st.guide = nil
    ARC.kill(st.guide_leaving)
    st.guide_leaving = g
    if RT.valid(g) then
        g:orderFlyTowards(_BW_X, _BW_Y)
        RT.after(60, function()
            if RT.valid(g) then g:destroy() end
            local cur = MISSIONS._state["corsair"]
            if cur and cur.guide_leaving == g then cur.guide_leaving = nil end
        end, "corsair_guide_leave")
    end
end

local _HOOK_TEXT = '"Easy. If we wanted you dead you\'d have noticed.\n\nWe watch things in the Drift, and we know you are someone who is not intimidated by the Concord. '
    .. 'Somebody at Blackwater wants to talk to you. Follow us in, and nobody out here will touch you."'

local function _guideComms(src, tgt)
    local phase = MISSIONS._cur_phase["corsair"]
    if phase == "hook" then
        setCommsMessage(_HOOK_TEXT)
        addCommsReply("Lead the way.", function()
            RT.flag("corsair_hook", true)
            MISSIONS.phase("corsair", "escort")
            setCommsMessage('"Stay on my tail. Blackwater\'s through the Veil."')
        end)
        addCommsReply("Not right now.", function()
            local st = MISSIONS._state["corsair"]
            if st then _deferHook(st) end
            setCommsMessage('"Fair enough. We\'ll be around. Ask at Greywater when you\'re ready."')
        end)
        addCommsReply("Tell your people to forget us.", function()
            RT.flag("corsair_arc_done", "declined")
            MISSIONS.phase("corsair", "done")
            setCommsMessage('"Your call. The Drift\'s going to get very loud, very soon. Remember we asked."')
        end)
    elseif phase == "escort" then
        setCommsMessage('"Stay close. Blackwater\'s through the Veil. Dock when we get there; she\'s expecting you."')
    else
        setCommsMessage('"Long Memory. Fly safe, friend."')
    end
end

local function _spawnGuide(st, x, y)
    if RT.valid(st.guide) then return st.guide end
    local g = CpuShip():setTemplate("Adder MK5"):setFaction("Corsair Friendly")
    g:setCallSign("Long Memory"):setPosition(x, y)
    g:setWarpDrive(true)
    g:setDescriptions("Corsair raider.", "Corsair raider Long Memory, running friendly colours. Weapons cold.")
    g:setScanningParameters(1, 1)
    g:setCommsScript(""):setCommsFunction(ARC.comms(_guideComms, '"Long Memory. Not looking for you."'))
    st.guide = g
    return g
end

-- ── Raid: the forward depot ──────────────────────────────────────────────────

local function _spawnDepot(st)
    if RT.valid(st.depot) then return end
    local d = SpaceStation():setTemplate("Small Station"):setFaction("Concord Hostile")
    d:setCallSign("Forward Depot Anvil"):setPosition(_DEPOT_X, _DEPOT_Y)
    d:setCanBeDestroyed(false)
    d:setDescriptions("Concord supply depot.", "Concord forward depot, provisioned for a fleet operation: mines, missiles and warp jammers in the cargo manifests.")
    d:setCommsFunction(function() setCommsMessage('"Restricted Concord facility. Turn away."') end)
    st.depot = d
end

local function _spawnDefenders(st)
    ARC.kill(st.defenders)
    st.defenders = {}
    for i, cs in ipairs({"CNS Warden", "CNS Bailiff"}) do
        local s = CpuShip():setTemplate("Phobos T3"):setFaction("Concord Hostile")
        s:setCallSign(cs):setPosition(_DEPOT_X + (i == 1 and -1500 or 1500), _DEPOT_Y + 1200)
        s:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
        s:orderDefendLocation(_DEPOT_X, _DEPOT_Y)
        s:setCommsScript(""):setCommsFunction(function() setCommsMessage('"Concord depot security. Leave the area."') end)
        st.defenders[#st.defenders + 1] = s
    end
end

local _escortComms   -- forward

local function _spawnEscorts(st)
    ARC.kill(st.escorts)
    st.escorts = {}
    local p = ARC.player()
    for i, cs in ipairs({"CSR Hardtack", "CSR Ninth Life"}) do
        local s = CpuShip():setTemplate("Phobos T3"):setFaction("Corsair Friendly")
        s:setCallSign(cs):setPosition(_BW_X - 3000, _BW_Y + (i == 1 and -1500 or 1500))
        s:setWarpDrive(true)
        s:setDescriptions("Corsair warship.", "Corsair warship " .. cs .. ", lent by Blackwater for the depot raid.")
        s:setScanningParameters(1, 1)
        s:setCommsScript(""):setCommsFunction(ARC.comms(function(src, tgt) _escortComms(src, tgt) end, '"We take our orders from someone else."'))
        if RT.valid(p) then s:orderDefendTarget(p) end
        st.escorts[#st.escorts + 1] = s
    end
end

local function _orderAttack(st)
    local targets = ARC.alive(st.defenders)
    for i, s in ipairs(ARC.alive(st.escorts)) do
        if #targets > 0 then s:orderAttack(targets[((i - 1) % #targets) + 1]) end
    end
end

_escortComms = function(src, tgt)
    local st = MISSIONS._state["corsair"]
    if MISSIONS._cur_phase["corsair"] ~= "raid" or not st then
        setCommsMessage('"Heading home to Blackwater."')
        return
    end
    setCommsMessage('"' .. tgt:getCallSign() .. ' here. Your call, captain."')
    addCommsReply("Form up on me.", function()
        st.attacking, st.boarding = false, false
        for _, s in ipairs(ARC.alive(st.escorts)) do s:orderDefendTarget(src) end
        setCommsMessage('"Forming up on you."')
    end)
    local near_depot = ARC.near(src, _DEPOT_X, _DEPOT_Y, 7 * U)
    if near_depot and #ARC.alive(st.defenders) > 0 then
        addCommsReply("Attack the Concord defenders.", function()
            st.attacking, st.boarding = true, false
            _orderAttack(st)
            setCommsMessage('"With pleasure. Engaging."')
        end)
    end
    if st.defenders_down and not st.load_t0 then
        addCommsReply("Board the depot and take the weapons.", function()
            st.attacking, st.boarding = false, true
            for _, s in ipairs(ARC.alive(st.escorts)) do s:orderFlyTowards(_DEPOT_X, _DEPOT_Y) end
            setCommsMessage('"Moving in. Keep an eye out for company while we work."')
        end)
    end
end

-- ── The trap ─────────────────────────────────────────────────────────────────

local function _layMine(st, x, y)
    local m = Mine():setPosition(x, y)
    pcall(function() m.components.avoid_object = {range = _MINE_AVOID} end)
    st.mines[#st.mines + 1] = m
end

-- One wobbly wall section along y from y0 to y1 (y0 < y1). Steps of 0.45-0.55U along the wall
-- with a sideways drift of at most 0.3U per step keeps neighbours within 0.7U; a slow bend
-- makes the wall look laid by hand, not by a surveyor.
local function _laySection(st, y0, y1, seed)
    local lateral = 0
    local y = y0
    local i = 0
    while y <= y1 do
        local bend = math.sin((y - _WALL_N) / (9 * U) + seed) * 1.2 * U
        _layMine(st, _WALL_X + bend + lateral, y)
        lateral = math.max(-0.5 * U, math.min(0.5 * U, lateral + (math.random() * 2 - 1) * 0.3 * U))
        y = y + (0.45 + math.random() * 0.10) * U
        i = i + 1
    end
    return i
end

local function _spawnTrap(st)
    if st.trap_built then return end
    st.trap_built = true
    local n = _laySection(st, _WALL_N, _GAP_Y - _GAP_W / 2, 0.3)
    n = n + _laySection(st, _GAP_Y + _GAP_W / 2, _WALL_S, 0.3)
    for _, j in ipairs(_TRAP_JAMMERS) do
        local w = WarpJammer():setPosition(j.x, j.y)
        w:setRange(j.r)
        w:setFaction("Corsair Friendly")
        w:setDescriptions("Warp jammer.", "Concord-issue warp jammer, now flying Corsair colours.")
        st.trap_jammers[#st.trap_jammers + 1] = w
    end
    log(string.format("[CORSAIR] trap: %d mines, %d jammers, gap at %s", n, #_TRAP_JAMMERS, _grid(_WALL_X, _GAP_Y)))
end

local function _clearTrap(st)
    ARC.kill(st.mines); ARC.kill(st.trap_jammers)
    st.mines, st.trap_jammers, st.trap_built = {}, {}, false
end

local function _giveMines(st)
    if st.mines_given then return end
    st.mines_given = true
    ARC.withPlayer(function(p)
        if RT.valid(p) then
            p:setWeaponStorageMax("Mine", _PLAYER_MINES):setWeaponStorage("Mine", _PLAYER_MINES)
        end
    end)
    ARC.log(string.format("[Weapons] %d mines from the depot haul loaded in the rear tube racks.", _PLAYER_MINES), "#FFCC80")
end

-- ── The battle ───────────────────────────────────────────────────────────────

local function _spawnAllies(st)
    ARC.kill(st.allies)
    st.allies = {}
    local function add(tmpl, cs, x, y, desc)
        local s = CpuShip():setTemplate(tmpl):setFaction("Corsair Friendly")
        s:setCallSign(cs):setPosition(x, y)
        s:orderDefendLocation(x, y)
        s:setDescriptions("Corsair ship.", desc)
        s:setScanningParameters(1, 1)
        s:setCommsFunction(function() setCommsMessage('"Holding the line."') end)
        st.allies[#st.allies + 1] = s
    end
    -- Missile boats beside the gap on the Blackwater side, to cut the fleet down as it threads it.
    add("Piranha F12", "CSR Long Odds", _WALL_X + 4 * U, _GAP_Y - 3 * U, "Corsair missile boat covering the gap.")
    add("Piranha F12", "CSR Hollis",    _WALL_X + 4 * U, _GAP_Y + 3 * U, "Corsair missile boat covering the gap.")
    -- Family freighters retrofitted as gunboats, holding at Blackwater.
    add("Adder MK5", "Hearthstone",   _BW_X - 3 * U, _BW_Y - 2 * U, "A family freighter with guns bolted on. The paint is still wet.")
    add("Adder MK5", "Second Chance", _BW_X - 3 * U, _BW_Y + 2 * U, "A family freighter with guns bolted on. The paint is still wet.")
    -- Raid survivors hold at Blackwater too.
    for _, s in ipairs(ARC.alive(st.escorts)) do s:orderDefendLocation(_BW_X - 2 * U, _BW_Y) end
end

local function _spawnFleet(st)
    if st.fleet_spawned then return end
    st.fleet_spawned = true
    st.fleet, st.wp = {}, {}
    for i, f in ipairs(_FLEET) do
        local s = CpuShip():setTemplate(f.tmpl):setFaction("Concord Hostile")
        s:setCallSign(f.cs):setPosition(_FLEET_X + ((i - 1) % 3) * 1500, _FLEET_Y + math.floor((i - 1) / 3) * 1500)
        s:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
        s:setWarpDrive(true)
        s:setDescriptions("Concord warship.", "Concord Battle Group Two. Assigned: Blackwater Reach.")
        s:setScanningParameters(2, 2)
        s:setCommsScript(""):setCommsFunction(function()
            setCommsMessage('"Battle Group Two. You are standing between the Concord and a pirate nest. Move."')
        end)
        st.fleet[#st.fleet + 1] = s
        st.wp[s] = 1
        s:orderFlyTowards(_FLEET_WAYPOINTS[1][1], _FLEET_WAYPOINTS[1][2])
    end
    ARC.log("[CNS Retribution] Blackwater Reach, this is Concord Battle Group Two. Your haven is declared a pirate installation under the Settlement Accords. Stand down and prepare to be boarded.", "#FF6666")
end

-- ── The munitions tender ─────────────────────────────────────────────────────

-- Share of the ship's missile racks that is still full (nil: it carries no missiles).
local function _missileShare(p)
    local have, max = 0, 0
    for _, w in ipairs(_MISSILES) do
        local m = p:getWeaponStorageMax(w) or 0
        if m > 0 then max = max + m; have = have + (p:getWeaponStorage(w) or 0) end
    end
    if max == 0 then return nil end
    return have / max
end

local function _tenderComms(src, tgt)
    local st = MISSIONS._state["corsair"]
    if not st then return end
    if st.reloads <= 0 then
        setCommsMessage('"The haul is gone. Every round we took from Anvil is in a tube somewhere. Make them count."')
        return
    end
    setCommsMessage(string.format('"CSR Magazine. We carry what\'s left of the Anvil haul: %d full load%s. '
        .. 'Come alongside, inside a klick, and give us %d seconds. We\'ll do the rest."',
        st.reloads, st.reloads == 1 and "" or "s", _RELOAD_TIME))
end

local function _spawnTender(st)
    if RT.valid(st.tender) then return end
    local s = CpuShip():setTemplate("Flavia"):setFaction("Corsair Friendly")
    s:setCallSign("CSR Magazine"):setPosition(_TENDER_X, _TENDER_Y)
    s:orderStandGround()
    s:setDescriptions("Corsair tender.", "A munitions tender carrying the rest of the haul from Forward Depot Anvil. Come alongside to rearm.")
    s:setScanningParameters(1, 1)
    s:setCommsScript(""):setCommsFunction(ARC.comms(_tenderComms, '"Corsair business. Keep clear."'))
    st.tender, st.tender_lost = s, false
end

-- Per tick in the battle: call the crew in when their racks run low, and reload them while
-- they are alongside.
local function _tickTender(st, now)
    if not RT.valid(st.tender) then
        if st.tender and not st.tender_lost then
            st.tender_lost = true
            RT.clearObjective("corsair_rearm")
            ARC.log("[Reva Okonkwo] We've lost the Magazine! What's in your racks is all there is.", "#FF8040")
        end
        return
    end
    local p = ARC.player()
    if not p then return end
    local share = _missileShare(p)
    if share == nil then return end
    local tx, ty = st.tender:getPosition()

    if share <= _LOW_AT and st.reloads > 0 and not st.low_called then
        st.low_called = true
        local where = _grid(tx, ty)
        local text = "Your racks are nearly empty. We carry what's left of the Anvil haul. Come alongside at " .. where .. " and we'll load you up."
        if not ARC.hail(st.tender, '"' .. text .. '"') then ARC.log("[CSR Magazine] " .. text, "#FFCC80") end
        RT.setObjective("Rearm alongside CSR Magazine (" .. where .. ")", true, "corsair_rearm")
    end

    if st.reloads > 0 and share < 1 and ARC.near(p, tx, ty, _RELOAD_R) then
        if not st.reload_t0 then
            st.reload_t0 = now
            ARC.log("[CSR Magazine] Hold her steady, we're passing crates across.", "#FFCC80")
        elseif now - st.reload_t0 >= _RELOAD_TIME then
            for _, w in ipairs(_MISSILES) do
                local m = p:getWeaponStorageMax(w) or 0
                if m > 0 then p:setWeaponStorage(w, m) end
            end
            st.reloads, st.reload_t0, st.low_called = st.reloads - 1, nil, false
            RT.clearObjective("corsair_rearm")
            ARC.log(string.format("[CSR Magazine] Racks full. %s", st.reloads > 0
                and string.format("%d load%s left aboard.", st.reloads, st.reloads == 1 and "" or "s")
                or "That was the last of it."), "#FFCC80")
        end
    else
        st.reload_t0 = nil
    end
end

-- Advance each ship to its next waypoint once within 1.5U of the current one.
local function _tickWaypoints(st)
    for _, s in ipairs(st.fleet) do
        if RT.valid(s) then
            local i = st.wp[s] or 1
            local w = _FLEET_WAYPOINTS[i]
            if w and ARC.near(s, w[1], w[2], 1.5 * U) and i < #_FLEET_WAYPOINTS then
                st.wp[s] = i + 1
                local n = _FLEET_WAYPOINTS[i + 1]
                s:orderFlyTowards(n[1], n[2])
            end
        end
    end
end

-- ── Blackwater dialogs ───────────────────────────────────────────────────────

local function _briefing(src)
    ARC.meet("corsair", "reva_profile", "Reva Okonkwo")
    setCommsMessage('"So you\'re the one Long Memory has been shadowing. Reva Okonkwo. I keep the books here, and the guns.\n\n'
        .. 'We have some fierce fighters, out in the Drift and guarding these approaches. But look around you: most of the ships at Blackwater are families. '
        .. 'Free Ship crews\' kids, and their kids.\n\nThe Concord calls what we do piracy. We call it the Corsair tax. We only take back what the "transitional" tariffs took, '
        .. 'and only from Concord hulls or to defend our territory. Now the Concord means to settle the account for good."')
    addCommsReply("What do you need from us?", function()
        setCommsMessage('"They\'ve provisioned a forward depot for the invasion, between Cinder and Tamsin, grid ' .. _grid(_DEPOT_X, _DEPOT_Y) .. '. '
            .. 'Mines, missiles, and a handful of warp jammers. Two Concord ships guarding it.\n\n'
            .. 'I\'ll give you two of my best ships. You lead them in, deal with the guards, and my crews will board the depot and take everything that isn\'t bolted down. '
            .. 'Then we turn their own weapons on them."')
        addCommsReply("We'll take the depot.", function()
            RT.flag("corsair_briefed", true)
            MISSIONS.phase("corsair", "raid")
            setCommsMessage('"Hardtack and Ninth Life are yours. Hail them to give orders. Bring them home."')
        end)
        addCommsReply("Give us a moment.", function()
            setCommsMessage('"Don\'t take too long. Neither will the Concord."')
        end)
    end)
end

local function _returnDialog(src)
    local st = MISSIONS._state["corsair"]
    if st then _spawnTrap(st); _giveMines(st) end
    setCommsMessage('"You did it. My crews came home singing, and the holds are full.\n\n'
        .. 'We\'ve already put the haul to work. The mines are laid in a wall west of here, on the edge of the Veil, with one gap at grid ' .. _grid(_WALL_X, _GAP_Y) .. ', '
        .. 'and the Concord\'s own warp jammers are sitting in the approach. We\'re refitting a couple of the family freighters as gunboats, too. '
        .. 'And we saved you a few mines for your own rack."')
    addCommsReply("Good work.", function()
        setCommsMessage('"And just in time, too. News is the Concord attack fleet was just detected at grid ' .. _grid(_FLEET_X, _FLEET_Y) .. ', and it is closing fast.\n\n'
            .. 'I know you haven\'t always seen eye to eye with us Corsairs. But will you fly out and join our defense?"')
        addCommsReply("We'll hold the wall with you.", function()
            RT.flag("corsair_joined", true)
            MISSIONS.phase("corsair", "battle")
            setCommsMessage('"Then let\'s show them what a pirate nest can do. Get to the gap."')
        end)
        addCommsReply("This isn't our fight.", function()
            RT.flag("corsair_arc_done", "failed")
            MISSIONS.phase("corsair", "done")
            setCommsMessage('"...I see. Then fly, and don\'t look back. We\'ll do this without you."\n\nThe channel closes.')
        end)
    end)
end

_blackwaterComms = function(src, tgt)
    local phase = MISSIONS._cur_phase["corsair"]
    local docked = ARC.docked(src, tgt)
    if phase == "briefing" then
        if not docked then setCommsMessage('"Dock and we\'ll talk. Reva\'s waiting."') return end
        _briefing(src)
    elseif phase == "escort" then
        setCommsMessage('"Long Memory says you\'re coming in. Dock when you\'re here."')
    elseif phase == "raid" then
        setCommsMessage('"The depot is at grid ' .. _grid(_DEPOT_X, _DEPOT_Y) .. '. Bring my ships home."')
    elseif phase == "return" then
        if not docked then setCommsMessage('"Dock. We have news."') return end
        _returnDialog(src)
    elseif phase == "battle" then
        setCommsMessage('"Hold the wall! Everything we have is at the gap."')
    elseif RT.flag("corsair_ally") then
        setCommsMessage('"Blackwater remembers who stood at the wall. Dock any time, friend."')
    else
        setCommsMessage('"Blackwater."')
    end
end

-- ── Greywater: the barkeep holds a message ───────────────────────────────────

local _GREYWATER_MEET_X, _GREYWATER_MEET_Y = 24 * U, 45 * U   -- the Gauntlet's north edge, ~9U south of Greywater

local function _greywaterHook(src, tgt)
    if not ARC.docked(src, tgt) then return end
    if MISSIONS._status["corsair"] ~= "active" or MISSIONS._cur_phase["corsair"] ~= "hook" then return end
    local st = MISSIONS._state["corsair"]
    if not st or RT.valid(st.guide) then return end
    addCommsReply("Heard you're holding a message for us.", function()
        if getScenarioTime() < (st.deferred_until or 0) then
            setCommsMessage('"They said you weren\'t ready. Come back in a bit and I\'ll pass word along again."')
            return
        end
        local g = _spawnGuide(st, _GREYWATER_MEET_X, _GREYWATER_MEET_Y)
        g:orderIdle()
        st.hail_when_near, st.hook_hailed = true, false
        RT.setObjective("Meet Long Memory at the Gauntlet's edge", true, "corsair")
        ARC.log("[Greywater] Message for you: Long Memory is waiting at grid " .. _grid(_GREYWATER_MEET_X, _GREYWATER_MEET_Y) .. ", the edge of the Gauntlet.", "#A0C0FF")
        setCommsMessage('The barkeep wipes the same glass for a while, then slides a data chip across the bar.\n\n'
            .. '"Friend of yours at Blackwater wants a word. There\'s a ship called Long Memory waiting at the edge of the Gauntlet, grid '
            .. _grid(_GREYWATER_MEET_X, _GREYWATER_MEET_Y) .. '. Fly out, they\'ll find you.\n\nI never saw the chip. You never saw me."')
    end)
end

-- ── Rumors ───────────────────────────────────────────────────────────────────

local _SEED_RUMORS = {
    "Concord's moving a lot of ordnance south of the Arbiter Line. Nobody says where it's headed.",
    "The Corsairs have gone quiet in the Gauntlet. Quiet Corsairs are watching for something.",
    "A Concord battle group left Lumen with sealed orders. The second one, I mean. Everyone forgets the second one.",
    "There's a Corsair raider out of Blackwater that shadows freighters and never fires. Gives people the creeps.",
}

function M.on_load(st)
    RUMORS.removeCategory("CORSAIR_SEED")
    if RT.flag("corsair_ally") then _befriend() end   -- allied for good (re-applied each session)
    if RT.flag("corsair_arc_done") then return end
    for _, t in ipairs(_SEED_RUMORS) do RUMORS.add({text = t, priority = 3, category = "CORSAIR_SEED"}) end
end

function M.on_unload(st)
    RUMORS.removeCategory("CORSAIR_SEED")
end

-- ── Cleanup, resolve ─────────────────────────────────────────────────────────

local function _clearWorld(st)
    RT.cancelTimer("corsair_cleanup")
    RT.cancelTimer("corsair_guide_leave")
    ARC.kill(st.guide); ARC.kill(st.guide_leaving); st.guide, st.guide_leaving = nil, nil
    ARC.kill(st.escorts); st.escorts = {}
    ARC.kill(st.defenders); st.defenders = {}
    ARC.kill(st.depot)
    st.depot = nil
    ARC.kill(st.fleet); st.fleet = {}
    ARC.kill(st.allies); st.allies = {}
    ARC.kill(st.tender); st.tender = nil
    PROX.clearCombatJammers(st.cjam)
    _clearTrap(st)
    RUMORS.removeCategory("CORSAIR_HOOK")
    RT.clearObjective("corsair")
    RT.clearObjective("corsair_rearm")
    local bw = _blackwater()
    if RT.valid(bw) then pcall(function() bw:setCanBeDestroyed(true) end) end
end

function M.resolve(st)
    local outcome = RT.flag("corsair_arc_done") or "failed"
    RT.clearObjective("corsair")
    RT.clearObjective("corsair_rearm")
    if outcome == "defended" then
        RT.flag("corsair_battlegroup_destroyed", true)
        RT.flag("corsair_ally", true)
        _befriend()
    else
        _unfriend(st)
    end
    ARC.once("corsair_rewarded", function()
        if outcome == "defended" then
            RT.addReputation("Corsairs", 400, "Corsair Arc: held the wall at Blackwater")
            RT.addReputation("Concord", -300, "Corsair Arc: destroyed Concord Battle Group Two")
        end
        ARC.log("[Corsair Arc] Arc complete. Outcome: " .. outcome .. ".", outcome == "defended" and "#80FF80" or "#FF8080")
    end)
    RUMORS.removeCategory("CORSAIR_DONE")
    if outcome == "defended" then
        RUMORS.add({text = "A whole Concord battle group died at Blackwater's mine wall. The Corsairs are calling it the Second Settlement.", priority = 3, category = "CORSAIR_DONE"})
    elseif outcome == "failed" then
        RUMORS.add({text = "Blackwater's burning, they say. The Concord calls it a clean-up. The Corsair families scattered into the Gauntlet.", priority = 3, category = "CORSAIR_DONE"})
    end
    -- Jammers go now (so the crew can warp out); the fleet's remains, allies and mines later.
    ARC.kill(st.trap_jammers); st.trap_jammers = {}
    PROX.clearCombatJammers(st.cjam)
    ARC.kill(st.guide); st.guide = nil
    RT.after(180, function()
        local cur = MISSIONS._state["corsair"]
        if cur then ARC.kill(cur.fleet); ARC.kill(cur.allies); ARC.kill(cur.escorts); ARC.kill(cur.tender); _clearTrap(cur) end
    end, "corsair_cleanup")
end

function M.on_cancel(st)
    _clearWorld(st)
    _unfriend(st)
end

-- ── Phases ───────────────────────────────────────────────────────────────────

M.phases = {}

M.phases.init = {
    no_skip = true,
    enter = function(st)
        ARC.stationHook("Greywater Depot", _greywaterHook)
        ARC.route("corsair", {
            {"corsair_arc_done", "done"},
            {"corsair_joined", "battle"},
            {"corsair_raid_done", "return"},
            {"corsair_briefed", "raid"},
            {"corsair_arrived", "briefing"},
            {"corsair_hook", "escort"},
        }, "hook")
    end,
}

local _HOOK_RUMORS = {
    "The barkeep at Greywater is holding a message for a freighter crew. Sounds a lot like yours.",
    "Corsairs have been asking around Greywater about you. Asking, not shooting. That's new.",
    "Somebody at Blackwater wants to meet you. Word is, you start at Greywater.",
}

M.phases.hook = {
    enter = function(st)
        st.hook_hailed = false
        RUMORS.removeCategory("CORSAIR_HOOK")
        for _, t in ipairs(_HOOK_RUMORS) do RUMORS.add({text = t, priority = 5, category = "CORSAIR_HOOK"}) end
    end,
    exit = function(st)
        RUMORS.removeCategory("CORSAIR_HOOK")
    end,
    update = function(st, delta, now)
        local p = ARC.player()
        if not p then return end
        local px, py = p:getPosition()
        local in_gauntlet = ARC.dist(px, py, _GAUNTLET_X, _GAUNTLET_Y) < _GAUNTLET_R
        if RT.valid(st.guide) and st.hail_when_near then
            -- Staged by the Greywater message: waiting at the Gauntlet's edge, hails once close.
            if RT.dist(p, st.guide) < 6 * U then
                st.hail_when_near = false
                st.guide:orderDefendTarget(p)
                st.hook_at = now + 2
            end
            return
        end
        if not RT.valid(st.guide) then
            if not in_gauntlet or now < (st.deferred_until or 0) then return end
            local a = math.rad(p:getRotation() or 0)
            local g = _spawnGuide(st, px + math.cos(a) * 4500, py + math.sin(a) * 4500)
            g:orderDefendTarget(p)
            st.hook_at = now + 4
            ARC.log("[Science] Corsair raider closing. Weapons cold, shields down. They're not attacking.", "#00CCAA")
        elseif not st.hook_hailed and now >= (st.hook_at or 0) then
            st.hook_hailed = true
            local ok, opened = pcall(function() return st.guide:openCommsTo(p) end)
            if not (ok and opened) then
                ARC.hail(st.guide, _HOOK_TEXT, "Long Memory")
                ARC.log("[Relay] Long Memory is waiting for an answer. Hail them back.", "#A0C0FF")
            end
        elseif ARC.dist(px, py, _GAUNTLET_X, _GAUNTLET_Y) > _GAUNTLET_R + 20 * U then
            -- The crew left without answering: the raider goes back to watching.
            ARC.kill(st.guide); st.guide = nil
        end
    end,
}

M.phases.escort = {
    enter = function(st)
        _befriend()
        local p = ARC.player()
        if not RT.valid(st.guide) then
            local x, y = _BW_X - 15 * U, _BW_Y - 15 * U
            if p then
                local px, py = p:getPosition()
                x, y = px + 2500, py
            end
            _spawnGuide(st, x, y)
        end
        st.guide:orderFlyTowards(_BW_X - 2 * U, _BW_Y)
        st.guide_waiting = false
        RT.setObjective("Follow Long Memory to Blackwater", true, "corsair")
    end,
    update = function(st, delta, now)
        local p = ARC.player()
        if not p then return end
        local bw = _blackwater()
        if RT.valid(bw) and p:isDocked(bw) then
            RT.flag("corsair_arrived", true)
            MISSIONS.phase("corsair", "briefing")
            return
        end
        local g = st.guide
        if not RT.valid(g) then return end
        local d = RT.dist(p, g)
        if not st.guide_waiting and d > _GUIDE_WAIT_D and not ARC.near(g, _BW_X, _BW_Y, 5 * U) then
            st.guide_waiting = true
            g:orderIdle()
            if now >= (st.keep_up_at or 0) then
                st.keep_up_at = now + 60
                ARC.hail(g, '"Keep up. These rocks eat the careless."', "Long Memory")
            end
        elseif st.guide_waiting and d < 4 * U then
            st.guide_waiting = false
            g:orderFlyTowards(_BW_X - 2 * U, _BW_Y)
        end
    end,
}

M.phases.briefing = {
    enter = function(st)
        _befriend()
        if RT.valid(st.guide) then st.guide:orderDefendLocation(_BW_X - 2 * U, _BW_Y - 1 * U) end
        RT.setObjective("Dock at Blackwater, talk to Reva", true, "corsair")
    end,
}

M.phases.raid = {
    enter = function(st)
        _befriend()
        st.attacking, st.boarding, st.defenders_down, st.load_t0 = false, false, false, nil
        _spawnDepot(st)
        _spawnDefenders(st)
        _spawnEscorts(st)
        RT.setObjective("Raid the Concord forward depot", true, "corsair")
        ARC.log("[Corsair Arc] Concord forward depot at grid " .. _grid(_DEPOT_X, _DEPOT_Y)
            .. ", between Cinder and Tamsin. Two Concord guards. Hardtack and Ninth Life are under your command: hail them for orders.", "#A0C0FF")
    end,
    update = function(st, delta, now)
        local escorts = ARC.alive(st.escorts)
        if #escorts == 0 then
            ARC.log("[Reva Okonkwo] Both ships lost? Damn it. I'm sending two more. The Concord will have re-crewed that depot. Try again.", "#FFCC80")
            MISSIONS.phase("corsair", "raid")   -- failure restart: fresh escorts, fresh defenders
            return
        end
        if not st.defenders_down and #ARC.alive(st.defenders) == 0 then
            st.defenders_down = true
            ARC.hail(escorts[1], '"Guards are down. Give the word and we\'ll board the depot."', escorts[1]:getCallSign())
        elseif st.attacking and #ARC.alive(st.defenders) > 0 then
            for _, s in ipairs(escorts) do
                local ok, ord = pcall(function() return s:getOrder() end)
                if ok and ord ~= "Attack" then _orderAttack(st); break end
            end
        end
        if st.boarding then
            if not st.load_t0 then
                for _, s in ipairs(escorts) do
                    if ARC.near(s, _DEPOT_X, _DEPOT_Y, 1.8 * U) then
                        st.load_t0 = now
                        for _, e in ipairs(escorts) do e:orderIdle() end
                        ARC.log("[" .. s:getCallSign() .. "] Alongside the depot. Cutting into the cargo bays.", "#FFCC80")
                        break
                    end
                end
            elseif now - st.load_t0 >= _LOAD_TIME then
                ARC.hail(escorts[1], '"We\'re loading up the haul now: mines, missiles, jammers, the lot. Meet you back at Blackwater."', escorts[1]:getCallSign())
                RT.flag("corsair_raid_done", true)
                MISSIONS.phase("corsair", "return")
            end
        end
    end,
}

M.phases["return"] = {
    enter = function(st)
        _befriend()
        for _, s in ipairs(ARC.alive(st.escorts)) do s:orderFlyTowards(_BW_X - 2 * U, _BW_Y) end
        RT.setObjective("Return to Blackwater", true, "corsair")
    end,
}

M.phases.battle = {
    enter = function(st)
        _befriend()
        _spawnTrap(st)
        _giveMines(st)
        _spawnAllies(st)
        _spawnTender(st)
        _spawnFleet(st)
        local bw = _blackwater()
        if RT.valid(bw) then pcall(function() bw:setCanBeDestroyed(false) end) end
        RT.setObjective("Hold the wall at Blackwater", true, "corsair")
    end,
    update = function(st, delta, now)
        _tickWaypoints(st)
        _tickTender(st, now)
        if PROX and PROX.tickCombatJammers then PROX.tickCombatJammers(st.cjam, st.fleet, ARC.player(), now) end
        if st.fleet_spawned and #ARC.alive(st.fleet) == 0 then
            RT.flag("corsair_arc_done", "defended")
            ARC.log("[Reva Okonkwo] That's the last of them. Battle Group Two is gone. Blackwater stands!", "#80FF80")
            MISSIONS.phase("corsair", "done")
            return
        end
        local bw = _blackwater()
        if RT.valid(bw) then
            local ok, frac = pcall(function() return bw:getHull() / bw:getHullMax() end)
            if ok and frac < _BW_FALLS_AT then
                RT.flag("corsair_arc_done", "failed")
                ARC.log("[Reva Okonkwo] Blackwater's breached. Everyone out! Scatter into the Gauntlet!", "#FF4040")
                MISSIONS.phase("corsair", "done")
            end
        end
    end,
}

-- ── GM console ───────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"corsair_"}

-- Saved flags this arc owns: every RT.flag name it sets, with what it means (a "*" suffix covers
-- a family of names). M.reads lists other arcs' flags it looks at. check.py and the arc tests
-- reject any flag that is not declared here. See missions_api.md, "Flags".
M.flags = {
    corsair_hook      = "told Long Memory to lead the way",
    corsair_arrived   = "docked at Blackwater",
    corsair_briefed   = "took the depot raid from Reva",
    corsair_raid_done = "the escorts loaded the depot haul",
    corsair_joined    = "agreed to hold the wall",
    corsair_arc_done  = 'outcome: "defended" | "failed" | "declined"',
    corsair_ally      = "set on defended: Gauntlet and Blackwater Corsairs stay friendly, Blackwater is dockable",
    corsair_battlegroup_destroyed = "set on defended: Concord Battle Group Two is gone",
    corsair_rewarded  = "reputation was paid (an end state pays once)",
    ["corsair_met_*"] = "Science DB profile met in this arc (reva), set by ARC.meet",
}
M.reads = {"rezkov_arc_done", "rezkov_declined"}   -- the Phase II gate (M.triggers.requires)

M.gm_state_fn = function()
    if MISSIONS._status["corsair"] == "done" then
        return "Complete (" .. tostring(RT.flag("corsair_arc_done")) .. ")"
    end
    local st = MISSIONS._state["corsair"]
    if MISSIONS._cur_phase["corsair"] == "battle" and st then
        return string.format("Battle (%d Concord left)", #ARC.alive(st.fleet))
    end
    return MISSIONS._cur_phase["corsair"] or MISSIONS._status["corsair"]
end

M.gm_reset = function(st, target)
    _clearWorld(st)
    _unfriend(st)
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("corsair", function(name)
        if name == "corsair_rewarded" then return target == "done" end
        return false
    end)
end

M.completed = {
    hook     = function(st) RT.flag("corsair_hook", true) end,
    escort   = function(st) RT.flag("corsair_arrived", true) end,
    briefing = function(st) RT.flag("corsair_briefed", true); ARC.meet("corsair", "reva_profile", "Reva Okonkwo") end,
    raid     = function(st) RT.flag("corsair_raid_done", true) end,
    ["return"] = function(st) RT.flag("corsair_joined", true) end,
}

local _jump = ARC.jumper("corsair")

local function _done(outcome, met)
    return _jump("done", function() RT.flag("corsair_arc_done", outcome) end,
        met and {} or {skip_completed = true})   -- met: replay flags + Reva's profile
end

M.gm_states = {
    {key = "hook",     label = "→ Hook",          fn = _jump("hook")},
    {key = "escort",   label = "→ Escort",        fn = _jump("escort")},
    {key = "briefing", label = "→ Briefing",      fn = _jump("briefing")},
    {key = "raid",     label = "→ Raid",          fn = _jump("raid")},
    {key = "return",   label = "→ Return",        fn = _jump("return")},
    {key = "battle",   label = "→ Battle",        fn = _jump("battle")},
    {key = "done_def", label = "→ Done: Defended", fn = _done("defended", true)},
    {key = "done_fail", label = "→ Done: Failed",  fn = _done("failed", true)},
    {key = "done_decl", label = "→ Done: Declined", fn = _done("declined", false)},
}

M.gm_actions = {
    {label = "Raider now", phases = {"hook"}, fn = function(st)
        local p = ARC.player()
        if not p or RT.valid(st.guide) then return end
        local px, py = p:getPosition()
        _spawnGuide(st, px + 4500, py):orderDefendTarget(p)
        st.hook_at = getScenarioTime() + 2
    end},
    {label = "Kill defenders", phases = {"raid"}, fn = function(st)
        for _, s in ipairs(ARC.alive(st.defenders)) do s:destroy() end
    end},
    {label = "Finish loading", phases = {"raid"}, fn = function(st)
        if not st.defenders_down then for _, s in ipairs(ARC.alive(st.defenders)) do s:destroy() end end
        st.defenders_down, st.boarding, st.load_t0 = true, true, getScenarioTime() - _LOAD_TIME
    end},
    {label = "Fleet to gap", phases = {"battle"}, fn = function(st)
        for i, s in ipairs(ARC.alive(st.fleet)) do
            s:setPosition(_FLEET_WAYPOINTS[3][1] - 2 * U, _FLEET_WAYPOINTS[3][2] + (i - 3) * 1200)
            st.wp[s] = 3
            s:orderFlyTowards(_FLEET_WAYPOINTS[3][1], _FLEET_WAYPOINTS[3][2])
        end
    end},
    {label = "Kill fleet", phases = {"battle"}, fn = function(st)
        for _, s in ipairs(ARC.alive(st.fleet)) do s:destroy() end
    end},
}

MISSIONS.register(M)
