-- ee/ragtag/missions/corsair.lua
-- The Corsair Arc: help Blackwater stand against the Concord's second battle group.
--
-- Trigger: upgrades >= 1000, corsair_arc_done unset; the hook fires when the crew enters the
-- Gauntlet. Design notes: corsair.md. Linear: defend, or don't do it.
--
--   hook      a Corsair raider (Long Memory) hails without attacking: follow us to Blackwater
--   escort    follow the guide; Corsair territory is friendly for now; dock at Blackwater
--   briefing  Reva Okonkwo explains, and asks the crew to raid a Concord forward depot
--   raid      two commandable Corsair ships: form up -> attack defenders -> board and loot
--             (an escort lost is replaced at once from Blackwater; Reva hails with both names)
--   return    dock at Blackwater: the haul's mines thicken Blackwater's mine ring (a few lanes
--             left open); the attack fleet is detected; join the defense or decline (= failed)
--   battle    a set piece like the Battle Lab (ragtag/battle.lua): 7 Concord ships and 12
--             Corsairs in two lines west of Blackwater, frozen until the crew comes within 5U
--             of the Corsair line, then fought over five combat points. All 7 Concord destroyed
--             -> defended; the crew's ship destroyed -> failed (the Corsairs may all be lost).
--             The tender Magazine reloads the crew's missiles behind the Corsair line.
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
-- Blackwater has its own mine ring (drift.lua minefields: r 9U, gaps north and west; the raid
-- escorts leave through the west one). Ships
-- heading "to Blackwater" go to this point instead: north of the ring, in front of its opening.
-- (Playtest: Corsairs flying to a point inside the ring hit its mines.)
local _BW_APPROACH_X, _BW_APPROACH_Y = _BW_X, _BW_Y - 12 * U
local _DEPOT_X, _DEPOT_Y = -60 * U, 62 * U          -- Concord forward depot, between Cinder and Tamsin

-- The battle (ragtag/battle.lua, played like the Battle Lab): west of Blackwater, just outside its
-- mine ring. Five combat points on a north-south line through (_BATTLE_X, _BATTLE_Y), 1.5U apart;
-- the Corsair line _LINE_U east of them (x 40U, ~6U outside the ring), the Concord line _LINE_U west.
local _BATTLE_X, _BATTLE_Y = 30 * U, _BW_Y
local _LINE_U   = 10 * U       -- each line's distance from the combat points
local _START_U  = 5 * U        -- the frozen battle starts when the crew is this close to any battle ship
local _CONCORD_HULLS = {"Atlantis X23", "Phobos T3", "Phobos T3", "Atlantis X23", "Phobos T3", "Atlantis X23", "Phobos T3"}
local _CONCORD_NAMES = {"CNS Retribution", "CNS Writ", "CNS Summons", "CNS Remand", "CNS Levy", "CNS Injunction", "CNS Distraint"}
local _CORSAIR_HULLS = {"Adder MK5", "Adder MK5", "Piranha F12"}
local _CORSAIR_NAMES = {"Hearthstone", "Second Chance", "Long Odds", "Short Fuse", "Dead Weight", "Hollis",
                        "Fair Warning", "Low Tide", "Tin Can", "Hard Luck", "Iron Will", "Stray Dog"}

-- Blackwater's mine ring (drift.lua: 26 mines at 9U, none within 25 degrees of north), thickened
-- with the haul's mines: one band laid in a hurry (wobbling radius, uneven steps), leaving a few
-- lanes open: the old north opening and two narrow lanes placed between two of the old ring's mines.
-- Angles are headings (0 = north, 90 = east).
local _RING_R     = 9 * U
local _RING_LANES = {{0, 25}, {103.85, 6.9}, {256.15, 6.9}}   -- {centre, half-width} in degrees

-- ── Tuning ───────────────────────────────────────────────────────────────────
local _LOAD_TIME      = 15          -- seconds the raid escorts dwell, docked at the depot, loading the haul
local _DOCK_GRACE     = 30          -- alongside this long without docking: load anyway
-- What the escort says when the haul is aboard, before they start back to Blackwater.
local _HAUL_ABOARD = '"Gao yang jong duh goo yang... we hit the jackpot. Mines, missiles, the lot, all aboard. '
    .. 'Heading back to Blackwater. Meet you there."'
-- The guide paces the crew: it holds (defending itself) once the crew is more than _GUIDE_HOLD_D
-- behind and flies on once they are back within _GUIDE_GO_D. It has no warp drive (the AI warps in
-- hops) but cruises on impulse at warp-1 speed, _GUIDE_IMPULSE: 500 world units/s = 30 U/min on the
-- helm, the Light Freighter's warp 1 (warp speed 500 per level), so the crew follows at warp 1.
-- Past _GUIDE_WAIT_D it tells them to keep up (once a minute at most). It leads to the Blackwater
-- approach (north of the mine ring), then slows to _GUIDE_DOCK_IMPULSE (6 U/min) to go in through
-- the north gap and dock at Blackwater.
local _GUIDE_IMPULSE      = 500
local _GUIDE_DOCK_IMPULSE = 100
local _GUIDE_HOLD_D   = 5.5 * U
local _GUIDE_GO_D     = 4.5 * U
local _GUIDE_WAIT_D   = 8 * U

-- The munitions tender: the rest of the Anvil haul, behind the north end of the Corsair line and
-- clear of Blackwater's ring, so the crew can pull back and rearm mid-battle.
local _TENDER_X, _TENDER_Y = 43 * U, 82 * U
local _RELOADS       = 3            -- full loads aboard
local _RELOAD_R      = 1.2 * U      -- "alongside"
local _RELOAD_TIME   = 8            -- seconds alongside to transfer a load
local _LOW_AT        = 0.25         -- racks at or below this share count as running low
local _MISSILES      = {"Homing", "HVLI", "Mine", "EMP"}

function M.init_state()
    return {
        guide = nil, hook_hailed = false, guide_waiting = false, guide_lost = false,
        guide_leg = nil,   -- "approach" (north of the ring), then "dock" (in to Blackwater)
        depot = nil, defenders = {}, escorts = {}, attacking = false, boarding = false,
        defenders_down = false, load_t0 = nil, near_t0 = nil,
        mines = {}, trap_built = false,
        battle = nil, fleet = {}, allies = {},   -- the BATTLE, its Concord (side a) and Corsair (b) ships
        escort_cs = {},   -- names of st.escorts, by index
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
    -- The arc's own Corsair ships (guide, escorts, the battle line, the munitions tender) keep
    -- their colours; any other Corsair ship in the Gauntlet or Blackwater Reach turns hostile.
    for _, list in ipairs({{st.guide, st.guide_leaving, st.tender}, st.escorts or {}, st.allies or {}}) do
        for _, s in pairs(list) do own[s] = true end   -- pairs: the first list has holes
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

-- Long Memory flies off toward (x, y) and is removed a minute later. It stays in st.guide_leaving
-- so a reset inside that minute (GM jump, cancel) still removes it.
local function _guideLeaves(st, x, y)
    local g = st.guide
    st.guide = nil
    ARC.kill(st.guide_leaving)
    st.guide_leaving = g
    if RT.valid(g) then
        g:orderFlyTowards(x, y)
        RT.after(60, function()
            if RT.valid(g) then g:destroy() end
            local cur = MISSIONS._state["corsair"]
            if cur and cur.guide_leaving == g then cur.guide_leaving = nil end
        end, "corsair_guide_leave")
    end
end

-- The crew said "not right now": the raider leaves, the hook stays open. Another contact (the
-- Greywater message, or entering the Gauntlet again) can try after _REASK_DELAY.
local _REASK_DELAY = 10 * 60
local function _deferHook(st)
    st.deferred_until = getScenarioTime() + _REASK_DELAY
    st.hook_hailed, st.hail_when_near, st.hook_at = false, false, nil
    RT.clearObjective("corsair")
    _guideLeaves(st, _BW_APPROACH_X, _BW_APPROACH_Y)
end

local _HOOK_TEXT = '"Easy there. If we wanted you dead you\'d have noticed.\n\nWe watch things in the Drift, and we know you are someone who is not intimidated by the Concord. '
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
    -- A steady lead the crew can follow at warp 1: no warp drive (the AI warps in hops), a warp-1
    -- cruise on impulse (_GUIDE_IMPULSE), and the acceleration to reach it in about 8 s.
    g:setWarpDrive(false)
    g:setImpulseMaxSpeed(_GUIDE_IMPULSE)
    pcall(function() g:setAcceleration(60, 60) end)
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
    d:setDescriptions("Concord supply depot.", "Concord forward depot, provisioned for a fleet operation: mines and missiles in the cargo manifests.")
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
local _sendHome      -- forward (with the routing below)

-- The guards are down: the depot crew gives up. The depot turns Concord Surrendered (a Concord
-- faction that is nobody's enemy, verse.lua), so nobody
-- keeps shooting at it and the escorts can dock to load the haul.
local function _depotSurrenders(st)
    if st.depot_surrendered then return end
    st.depot_surrendered = true
    local d = st.depot
    if RT.valid(d) then
        d:setFaction("Concord Surrendered")   -- enemy of nobody: the escorts board it, nobody fires on it
        d:setDescriptions("Concord supply depot.", "Concord forward depot. The crew has surrendered and the docking clamps are open.")
        d:setCommsFunction(function() setCommsMessage('"We surrender. Take what you want, just leave us the air."') end)
    end
    local p = ARC.player()
    for _, s in ipairs(ARC.alive(st.escorts)) do
        if RT.valid(p) then s:orderDefendTarget(p) else s:orderIdle() end
    end
end

-- Ships Reva sends to replace an escort lost in the raid (any not already flying).
local _REPLACEMENT_NAMES = {
    "Second Wind", "Last Laugh", "Scrap Iron", "Old Grudge", "Long Shot",
    "Lucky Break", "Sweet Revenge", "Rust Bucket", "Bad Habit", "Spare Change",
}

-- The raid escorts are tougher than a stock Phobos T3 (hull 70, shields 50/40): a mine does up to
-- 160 at its centre, so one stray mine destroyed an escort. With 100/100 shields and 120 hull an
-- escort survives one direct hit (the shield takes 100, the hull 60); two still finish it.
local _ESCORT_HULL    = 120
local _ESCORT_SHIELDS = {100, 100}   -- front, rear

-- One raid escort, near Blackwater, forming up on the crew. st.escort_cs keeps its name (by
-- index, alongside st.escorts) so a lost ship can still be named.
local function _spawnEscort(st, cs, x, y)
    local s = CpuShip():setTemplate("Phobos T3"):setFaction("Corsair Friendly")
    s:setCallSign(cs):setPosition(x, y)
    s:setWarpDrive(true)
    s:setHullMax(_ESCORT_HULL):setHull(_ESCORT_HULL)
    s:setShieldsMax(_ESCORT_SHIELDS[1], _ESCORT_SHIELDS[2]):setShields(_ESCORT_SHIELDS[1], _ESCORT_SHIELDS[2])
    s:setDescriptions("Corsair warship.", "Corsair warship " .. cs .. ", lent by Blackwater for the depot raid.")
    s:setScanningParameters(1, 1)
    s:setCommsScript(""):setCommsFunction(ARC.comms(function(src, tgt) _escortComms(src, tgt) end, '"We take our orders from someone else."'))
    local p = ARC.player()
    if RT.valid(p) then s:orderDefendTarget(p) end
    st.escorts[#st.escorts + 1] = s
    st.escort_cs[#st.escort_cs + 1] = cs
    return s
end

local function _spawnEscorts(st)
    ARC.kill(st.escorts)
    st.escorts, st.escort_cs = {}, {}
    for i, cs in ipairs({"Hardtack", "Ninth Life"}) do
        _spawnEscort(st, cs, _BW_X - 3000, _BW_Y + (i == 1 and -1500 or 1500))
    end
end

-- During the raid an escort lost is replaced at once from Blackwater, and Reva says so.
local function _replaceLostEscorts(st)
    for i = #st.escorts, 1, -1 do
        if not RT.valid(st.escorts[i]) then
            local lost = st.escort_cs[i] or "one of ours"
            table.remove(st.escorts, i)
            table.remove(st.escort_cs, i)
            local taken = {}
            for _, n in ipairs(st.escort_cs) do taken[n] = true end
            local name = "Second Wind"
            for _, n in ipairs(_REPLACEMENT_NAMES) do
                if not taken[n] and not RT.valid(RT.find(n)) then name = n; break end
            end
            _spawnEscort(st, name, _BW_X - 3000, _BW_Y + (#st.escorts % 2 == 0 and -1500 or 1500))
            local line = '"We lost ' .. lost .. '. I\'m sending ' .. name .. ' out to you. Look after her."'
            if not ARC.hail(_blackwater(), line, "Reva Okonkwo") then ARC.log("[Reva Okonkwo] " .. line, "#FFCC80") end
        end
    end
end

-- Ships sent home fly to the Blackwater approach (north of the ring, in front of its opening) and
-- stand ground there, or with `dock` go in and dock at Blackwater.
_sendHome = function(st, s, dest_x, dest_y, dock)
    if not RT.valid(s) then return end
    dest_x, dest_y = dest_x or _BW_APPROACH_X, dest_y or _BW_APPROACH_Y
    st.routes = st.routes or {}
    for i = #st.routes, 1, -1 do if st.routes[i].ship == s then table.remove(st.routes, i) end end
    st.routes[#st.routes + 1] = {ship = s, steps = {{dest_x, dest_y}}, i = 1, dock = dock}
    s:orderFlyTowards(dest_x, dest_y)
end

-- Per tick: move routed ships on to their next point; at the last one they stand ground (or dock).
local function _tickRoutes(st)
    for k = #(st.routes or {}), 1, -1 do
        local r = st.routes[k]
        local s = r.ship
        if not RT.valid(s) then
            table.remove(st.routes, k)
        else
            local pt = r.steps[r.i]
            if ARC.near(s, pt[1], pt[2], 1.2 * U) then
                r.i = r.i + 1
                local nxt = r.steps[r.i]
                if nxt then
                    s:orderFlyTowards(nxt[1], nxt[2])
                else
                    local bw = _blackwater()
                    if r.dock and RT.valid(bw) then s:orderDock(bw) else s:orderStandGround() end
                    table.remove(st.routes, k)
                end
            end
        end
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
    addCommsReply("Hold position.", function()
        st.attacking, st.boarding = false, false
        for _, s in ipairs(ARC.alive(st.escorts)) do s:orderStandGround() end
        setCommsMessage('"Holding here. We\'ll fire on anything that comes close."')
    end)
    addCommsReply("Head to the depot.", function()
        st.attacking, st.boarding = false, false
        for _, s in ipairs(ARC.alive(st.escorts)) do s:orderFlyTowards(_DEPOT_X + 3 * U, _DEPOT_Y) end
        setCommsMessage('"Making for the depot. We\'ll hold off its guns until you say."')
    end)
    addCommsReply("Head back to Blackwater.", function()
        st.attacking, st.boarding = false, false
        for _, s in ipairs(ARC.alive(st.escorts)) do _sendHome(st, s) end
        setCommsMessage('"Turning for home."')
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
            for _, s in ipairs(ARC.alive(st.escorts)) do
                if RT.valid(st.depot) then s:orderDock(st.depot) else s:orderFlyTowards(_DEPOT_X, _DEPOT_Y) end
            end
            setCommsMessage('"Docking with the depot. Keep an eye out for company while we work."')
        end)
    end
end

-- ── The mine ring ────────────────────────────────────────────────────────────

local function _inLane(a)   -- with a degree to spare, so no mine sits on a lane's edge
    for _, l in ipairs(_RING_LANES) do
        if math.abs(((a - l[1]) + 180) % 360 - 180) < l[2] + 1 then return true end
    end
    return false
end

-- The haul's mines go round Blackwater: one band at about _RING_R, laid in a hurry: steps of
-- 3.2-3.8 degrees (0.5-0.6U), the radius drifting up to 0.12U a step within 0.5U of _RING_R plus a
-- slow wobble. None in the lanes.
local function _spawnTrap(st)
    if st.trap_built then return end
    st.trap_built = true
    local a, drift = _RING_LANES[1][2], 0
    while a < 360 - _RING_LANES[1][2] do
        drift = math.max(-0.5 * U, math.min(0.5 * U, drift + (math.random() * 2 - 1) * 0.12 * U))
        if not _inLane(a) then
            local r = _RING_R + drift + math.sin(math.rad(a) * 3) * 0.25 * U
            local dx, dy = vectorFromAngle(a, r, true)
            st.mines[#st.mines + 1] = Mine():setPosition(_BW_X + dx, _BW_Y + dy)
        end
        a = a + 3.2 + math.random() * 0.6
    end
    log(string.format("[CORSAIR] ring: %d mines added round Blackwater, %d lanes", #st.mines, #_RING_LANES))
end

local function _clearTrap(st)
    ARC.kill(st.mines)
    st.mines, st.trap_built = {}, false
end

-- ── The battle ───────────────────────────────────────────────────────────────

-- Both lines, frozen (BATTLE: they wait until start()). Concord is side a, the Corsairs side b
-- (missile top-ups for the Corsairs, as in the lab).
local function _spawnBattle(st)
    if st.battle then return end
    local hulls = {}
    for _, h in ipairs(_CONCORD_HULLS) do hulls[#hulls + 1] = h end
    for _, h in ipairs(_CORSAIR_HULLS) do hulls[#hulls + 1] = h end
    local b = BATTLE.new{x = _BATTLE_X, y = _BATTLE_Y, points = 5, spacing_u = 1.5, hulls = hulls, topup = {"b"}}
    st.battle, st.fleet, st.allies = b, {}, {}
    for i, hull in ipairs(_CONCORD_HULLS) do
        local s = b:spawn("a", hull, "Concord Hostile", _CONCORD_NAMES[i],
            _BATTLE_X - _LINE_U, _BATTLE_Y + (i - (#_CONCORD_HULLS + 1) / 2) * 2 * U, 90)
        s:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
        s:setDescriptions("Concord warship.", "Concord battle fleet. Assigned: Blackwater Reach.")
        s:setScanningParameters(2, 2)
        s:setCommsScript(""):setCommsFunction(function()
            setCommsMessage('"Concord battle fleet. You are standing between the Concord and a pirate nest. Move."')
        end)
        st.fleet[#st.fleet + 1] = s
    end
    for i = 1, 12 do
        local s = b:spawn("b", _CORSAIR_HULLS[(i - 1) % #_CORSAIR_HULLS + 1], "Corsair Friendly", _CORSAIR_NAMES[i],
            _BATTLE_X + _LINE_U, _BATTLE_Y + (i - 6.5) * 2 * U, 270)
        s:setDescriptions("Corsair ship.", "One of Blackwater's ships, holding the line west of the ring.")
        s:setScanningParameters(1, 1)
        s:setCommsFunction(function() setCommsMessage('"Holding the line."') end)
        st.allies[#st.allies + 1] = s
    end
end

-- The crew comes within _START_U of a battle ship (either side): the battle begins.
local function _startBattle(st)
    if not st.battle or st.battle.started then return end
    st.battle:start()
    ARC.log("[CNS Retribution] Blackwater Reach, this is Concord battle fleet command. Your haven is declared a pirate installation under the Settlement Accords. Stand down and prepare to be boarded.", "#FF6666")
    local line = '"Here they come. Hold the line!"'
    if not ARC.hail(_blackwater(), line, "Reva Okonkwo") then ARC.log("[Reva Okonkwo] " .. line, "#FFCC80") end
    RT.setObjective("Destroy the Concord battle fleet", true, "corsair")
end

-- True when ANY player ship is within _START_U of any ship of the battle, on either side: coming
-- in from the west reaches the Concord line first, and frozen ships do not fight back, so the
-- battle has to start before anyone can pick them off. (A sister ship flying with the crew
-- starts it too, though the arc itself belongs to the arc ship.)
local function _crewNear(b)
    for _, side in ipairs({"a", "b"}) do
        for _, s in ipairs(b:ships(side)) do
            local x, y = s:getPosition()
            if ARC.anyPlayerNear(x, y, _START_U) then return true end
        end
    end
    return false
end

local function _tickBattle(st, now)
    local b = st.battle
    if not b then return end
    if not b.started and _crewNear(b) then _startBattle(st) end
    b:tick(now)
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
    setCommsMessage(string.format('"Magazine. We carry what\'s left of the Anvil haul: %d full load%s. '
        .. 'Come alongside, inside a klick, and give us %d seconds. We\'ll do the rest."',
        st.reloads, st.reloads == 1 and "" or "s", _RELOAD_TIME))
end

local function _spawnTender(st)
    if RT.valid(st.tender) then return end
    local s = CpuShip():setTemplate("Flavia"):setFaction("Corsair Friendly")
    s:setCallSign("Magazine"):setPosition(_TENDER_X, _TENDER_Y)
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
        if not ARC.hail(st.tender, '"' .. text .. '"') then ARC.log("[Magazine] " .. text, "#FFCC80") end
        RT.setObjective("Rearm alongside Magazine (" .. where .. ")", true, "corsair_rearm")
    end

    if st.reloads > 0 and share < 1 and ARC.near(p, tx, ty, _RELOAD_R) then
        if not st.reload_t0 then
            st.reload_t0 = now
            ARC.log("[Magazine] Hold her steady, we're passing crates across.", "#FFCC80")
        elseif now - st.reload_t0 >= _RELOAD_TIME then
            for _, w in ipairs(_MISSILES) do
                local m = p:getWeaponStorageMax(w) or 0
                if m > 0 then p:setWeaponStorage(w, m) end
            end
            st.reloads, st.reload_t0, st.low_called = st.reloads - 1, nil, false
            RT.clearObjective("corsair_rearm")
            ARC.log(string.format("[Magazine] Racks full. %s", st.reloads > 0
                and string.format("%d load%s left aboard.", st.reloads, st.reloads == 1 and "" or "s")
                or "That was the last of it."), "#FFCC80")
        end
    else
        st.reload_t0 = nil
    end
end

-- ── Blackwater dialogs ───────────────────────────────────────────────────────

local function _briefing(src)
    ARC.meet("corsair", "reva_profile", "Reva Okonkwo")
    setCommsMessage('"So you\'re the one Long Memory has been shadowing. I\'m Reva Okonkwo. I keep the books here, and the guns.\n\n'
        .. 'We have some fierce fighters, out in the Drift and guarding these approaches. But look around you: most of the ships at Blackwater are families. '
        .. 'Free Ship crews\' kids, and their kids.\n\nThe Concord calls what we do piracy. We call it the Corsair tax. We only take back what the "transitional" tariffs took, '
        .. 'and only from Concord hulls or to defend our territory. Now the Concord means to settle the account for good, and we need help."')
    addCommsReply("What do you need from us?", function()
        setCommsMessage('"The Concord has provisioned a forward depot in preparation for a full-scale invasion and occupation of Blackwater. It sits between Cinder and Tamsin, grid ' .. _grid(_DEPOT_X, _DEPOT_Y) .. '. '
            .. 'Mines and missiles. Two Concord ships guarding it.\n\n'
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
    if st then _spawnTrap(st) end
    setCommsMessage('"You did it. My crews came home singing, and the holds are full.\n\n'
        .. 'We\'ve already put the haul to work. Every mine we took is going into the ring round Blackwater, thick enough now that only a few lanes are open. '
        .. 'We\'re refitting a couple of the family freighters as gunboats, too."')
    addCommsReply("Good work.", function()
        setCommsMessage('"And just in time, too. News is the Concord attack fleet was just detected at grid ' .. _grid(_BATTLE_X - _LINE_U, _BATTLE_Y) .. ', and it is closing fast.\n\n'
            .. 'I know you haven\'t always seen eye to eye with us Corsairs. But will you fly out and join our defense?"')
        addCommsReply("We'll stand with you.", function()
            RT.flag("corsair_joined", true)
            MISSIONS.phase("corsair", "battle")
            setCommsMessage('"I\'ve heard your hackers are second to none. If you can hack their big ships, that gives us a much better shot at winning this thing.\n\n'
                .. 'Also, since we took out their supply depot, they have a limited supply of missiles, so once they run out they\'ll be sitting ducks. '
                .. 'Any distraction your awesome piloting can provide improves our odds."')
            addCommsReply("Understood. We're on our way.", function()
                setCommsMessage('"Then let\'s show them what a pirate nest can do. Our line is forming west of the ring, at grid ' .. _grid(_BATTLE_X + _LINE_U, _BATTLE_Y) .. '. Join them."')
            end)
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
        setCommsMessage('"Hold the line! Everything we have is west of the ring."')
    elseif RT.flag("corsair_ally") then
        setCommsMessage('"Blackwater remembers who stood with us. Dock any time, friend."')
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
    "A Concord battle group left Lumen with sealed orders. Not the one everyone is talking about. The other one.",
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
    if st.battle then st.battle:clear() end
    st.battle = nil
    ARC.kill(st.fleet); st.fleet = {}
    ARC.kill(st.allies); st.allies = {}
    ARC.kill(st.tender); st.tender = nil
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
            -- Corsair standing: up to +500 from zero or below; +500 more if it was already positive.
            local corsairs = RT.getReputation("Corsairs") or 0
            RT.addReputation("Corsairs", corsairs > 0 and 500 or (500 - corsairs), "Corsair Arc: stood with Blackwater")
            RT.addReputation("Concord", -300, "Corsair Arc: destroyed a Concord battle fleet")
        end
        ARC.log("[Corsair Arc] Arc complete. Outcome: " .. outcome .. ".", outcome == "defended" and "#80FF80" or "#FF8080")
    end)
    RUMORS.removeCategory("CORSAIR_DONE")
    if outcome == "defended" then
        RUMORS.add({text = "A whole Concord battle group died off Blackwater. The Corsairs are calling it the Second Settlement.", priority = 3, category = "CORSAIR_DONE"})
    elseif outcome == "failed" then
        RUMORS.add({text = "Blackwater's burning, they say. The Concord calls it a clean-up. The Corsair families scattered into the Gauntlet.", priority = 3, category = "CORSAIR_DONE"})
    end
    -- The fleet's remains, the allies and the haul's mines leave the board a little later.
    ARC.kill(st.guide); st.guide = nil
    -- 5 minutes: time for the surviving Corsairs to fly home out of sight.
    RT.after(300, function()
        local cur = MISSIONS._state["corsair"]
        if cur then
            if cur.battle then cur.battle:clear(); cur.battle = nil end
            ARC.kill(cur.fleet); ARC.kill(cur.allies); ARC.kill(cur.escorts); ARC.kill(cur.tender); _clearTrap(cur)
        end
        -- Blackwater was made indestructible for the battle only.
        local bw = _blackwater()
        if RT.valid(bw) then pcall(function() bw:setCanBeDestroyed(true) end) end
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

-- Long Memory's lead: to the Blackwater approach first, then (st.guide_leg == "dock") in through
-- the north gap of the mine ring to dock at Blackwater, so the crew is taken all the way to the port.
local function _guideLead(st, g)
    local bw = _blackwater()
    if st.guide_leg == "dock" and RT.valid(bw) then
        g:setImpulseMaxSpeed(_GUIDE_DOCK_IMPULSE)   -- slow through the mine gap and into the dock
        g:orderDock(bw)
    else
        g:setImpulseMaxSpeed(_GUIDE_IMPULSE)        -- warp-1 speed
        g:orderFlyTowards(_BW_APPROACH_X, _BW_APPROACH_Y)
    end
end

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
        st.guide_leg = "approach"
        _guideLead(st, st.guide)
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
        if not RT.valid(g) then
            -- Long Memory was lost on the way: the crew finds Blackwater on its own (docking still
            -- moves the arc on).
            if not st.guide_lost then
                st.guide_lost = true
                RT.setObjective("Dock at Blackwater", true, "corsair")
                ARC.log("[Relay] We've lost Long Memory. Blackwater is at grid " .. _grid(_BW_X, _BW_Y)
                    .. "; their approach lane comes in from the north. Dock there and ask for Reva.", "#FFCC80")
            end
            return
        end
        -- In sight of Blackwater: Long Memory hands the crew over to Reva.
        if not st.arrival_hailed and ARC.near(p, _BW_X, _BW_Y, 5 * U) then
            st.arrival_hailed = true
            local line = '"I got you here safe. Dock with Blackwater to meet Reva and she\'ll fill you in."'
            if not ARC.hail(g, line, "Long Memory") then ARC.log("[Long Memory] " .. line, "#FFCC80") end
        end
        -- At the approach point: on in through the ring's north gap, to dock.
        if st.guide_leg ~= "dock" and ARC.near(g, _BW_APPROACH_X, _BW_APPROACH_Y, 1.5 * U) then
            st.guide_leg = "dock"
            if not st.guide_waiting then _guideLead(st, g) end
        end
        local d = RT.dist(p, g)
        local docked = RT.valid(bw) and g:isDocked(bw)
        if not st.guide_waiting and not docked and d > _GUIDE_HOLD_D then
            st.guide_waiting = true
            local gx, gy = g:getPosition()
            g:orderDefendLocation(gx, gy)   -- hold here, and fight back if anything comes at it
        elseif st.guide_waiting and d < _GUIDE_GO_D then
            st.guide_waiting = false
            _guideLead(st, g)
        end
        if st.guide_waiting and d > _GUIDE_WAIT_D and now >= (st.keep_up_at or 0) then
            st.keep_up_at = now + 60
            ARC.hail(g, '"Keep up. These rocks eat the careless."', "Long Memory")
        end
    end,
}

M.phases.briefing = {
    enter = function(st)
        _befriend()
        -- The crew has docked: Long Memory's job is done. Back out into the Drift (east, away
        -- from where the wall will go), gone a minute later.
        _guideLeaves(st, _BW_X + 25 * U, _BW_Y - 10 * U)
        RT.setObjective("Dock at Blackwater, talk to Reva", true, "corsair")
    end,
}

M.phases.raid = {
    enter = function(st)
        _befriend()
        st.attacking, st.boarding, st.defenders_down, st.load_t0, st.near_t0 = false, false, false, nil, nil
        st.depot_surrendered = false
        _spawnDepot(st)
        _spawnDefenders(st)
        _spawnEscorts(st)
        RT.setObjective("Raid the Concord forward depot", true, "corsair")
        ARC.log("[Corsair Arc] Concord forward depot at grid " .. _grid(_DEPOT_X, _DEPOT_Y)
            .. ", between Cinder and Tamsin. Two Concord guards. Hardtack and Ninth Life are under your command: hail them for orders.", "#A0C0FF")
    end,
    update = function(st, delta, now)
        local escorts = ARC.alive(st.escorts)
        _replaceLostEscorts(st)
        escorts = ARC.alive(st.escorts)
        if not st.defenders_down and #ARC.alive(st.defenders) == 0 then
            st.defenders_down = true
            _depotSurrenders(st)
            ARC.hail(escorts[1], '"Guards are down and the depot\'s surrendered. Give the word and we\'ll dock and board it."', escorts[1]:getCallSign())
        elseif st.attacking and #ARC.alive(st.defenders) > 0 then
            for _, s in ipairs(escorts) do
                local ok, ord = pcall(function() return s:getOrder() end)
                if ok and ord ~= "Attack" then _orderAttack(st); break end
            end
        end
        if st.boarding then
            if not st.load_t0 then
                -- The dwell starts when an escort has really docked (EE docks on contact, a few
                -- seconds after it closes in). Fallback: alongside (1.8U) for _DOCK_GRACE without
                -- docking still counts, so a docking that never lands cannot stall the raid.
                for _, s in ipairs(escorts) do
                    local docked = false
                    pcall(function() docked = RT.valid(st.depot) and s:getDockedWith() == st.depot end)
                    if not st.near_t0 and ARC.near(s, _DEPOT_X, _DEPOT_Y, 1.8 * U) then st.near_t0 = now end
                    if docked or (st.near_t0 and now - st.near_t0 >= _DOCK_GRACE) then
                        st.load_t0 = now
                        ARC.log("[" .. s:getCallSign() .. "] " .. (docked and "Docked at" or "Alongside")
                            .. " the depot. Loading the cargo bays.", "#FFCC80")
                        break
                    end
                end
            elseif now - st.load_t0 >= _LOAD_TIME then
                -- One message once they have dwelt there: the jackpot, aboard, heading home.
                local s = escorts[1]
                if not ARC.hail(s, _HAUL_ABOARD, s:getCallSign()) then
                    ARC.log("[" .. s:getCallSign() .. "] " .. _HAUL_ABOARD, "#FFCC80")
                end
                RT.flag("corsair_raid_done", true)
                MISSIONS.phase("corsair", "return")
            end
        end
    end,
}

M.phases["return"] = {
    enter = function(st)
        _befriend()
        for _, s in ipairs(ARC.alive(st.escorts)) do _sendHome(st, s) end
        RT.setObjective("Return to Blackwater", true, "corsair")
    end,
    update = function(st) _tickRoutes(st) end,
}

M.phases.battle = {
    enter = function(st)
        _befriend()
        _spawnTrap(st)
        _spawnBattle(st)
        _spawnTender(st)
        -- The raid escorts sit this one out: home, and docked at Blackwater.
        for _, s in ipairs(ARC.alive(st.escorts)) do _sendHome(st, s, nil, nil, true) end
        local bw = _blackwater()
        if RT.valid(bw) then pcall(function() bw:setCanBeDestroyed(false) end) end
        RT.setObjective("Join the Corsair line west of Blackwater", true, "corsair")
    end,
    update = function(st, delta, now)
        _tickRoutes(st)
        _tickBattle(st, now)
        _tickTender(st, now)
        -- Victory: the whole Concord battle fleet destroyed, however that happens. Blackwater hails, the
        -- arc ends, and the surviving Corsairs head home (removed with the rest in M.resolve).
        if st.battle and #ARC.alive(st.fleet) == 0 then
            RT.flag("corsair_arc_done", "defended")
            local p = ARC.player()
            local name = (p and p:getCallSign()) or (RT.campaign and RT.campaign.ship_name) or "Magpie"
            local line = '"The Concord battle group is destroyed! Victory is ours, but at a great cost. '
                .. 'The pirate families of Blackwater owe you our thanks. Safe flying and see you around, ' .. name .. '!"'
            if not ARC.hail(_blackwater(), line, "Blackwater") then ARC.log("[Blackwater] " .. line, "#80FF80") end
            for _, s in ipairs(ARC.alive(st.allies)) do _sendHome(st, s) end
            MISSIONS.phase("corsair", "done")
        end
    end,
}

-- Defeat: the crew's (primary) ship destroyed during the battle. Heard on the event bus, which
-- also runs when that was the crew's only ship. Losing Corsair ships, even all of them, is not defeat.
RT.on(function(ev)
    if ev.type ~= "ship_lost" or not ev.data.primary then return end
    if MISSIONS._status["corsair"] ~= "active" or MISSIONS._cur_phase["corsair"] ~= "battle" then return end
    RT.flag("corsair_arc_done", "failed")
    ARC.log("[Reva Okonkwo] We've lost them. Everyone, fall back inside the ring!", "#FF4040")
    MISSIONS.phase("corsair", "done")
end)

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
    corsair_joined    = "agreed to stand with Blackwater in the battle",
    corsair_arc_done  = 'outcome: "defended" | "failed" | "declined"',
    corsair_ally      = "set on defended: Gauntlet and Blackwater Corsairs stay friendly, Blackwater is dockable",
    corsair_battlegroup_destroyed = "set on defended: the Concord battle fleet is gone",
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
        _depotSurrenders(st)
        st.defenders_down, st.boarding, st.load_t0 = true, true, getScenarioTime() - _LOAD_TIME
    end},
    {label = "Start battle", phases = {"battle"}, fn = function(st)
        _spawnBattle(st)
        _startBattle(st)
    end},
    {label = "Kill fleet", phases = {"battle"}, fn = function(st)
        _spawnBattle(st)
        for _, s in ipairs(ARC.alive(st.fleet)) do s:destroy() end
    end},
}

MISSIONS.register(M)
