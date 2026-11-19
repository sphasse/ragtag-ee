-- ee/ragtag/battle.lua
-- BATTLE: set-piece battles between two lines of NPC ships, fought over a few invisible combat
-- points so they stay spread out instead of collapsing into one mass. Worked out in the Battle Lab
-- (scenarios/battlelab) and used by it, by the Corsair arc's battle at Blackwater and, through
-- BATTLE.annex (below), by the Boneyard arc's fight at the Ashgrave Annex.
--
--   local b = BATTLE.new{x = cx, y = cy, points = 5, spacing_u = 1.5, hulls = {...}, topup = {"b"},
--                        line_heading = 180, norm_hulls = BATTLE.REF_HULLS}
--   b:spawn("a", "Atlantis X23", "Concord Hostile", "CNS Writ", x, y, 90)   -- side "a" or "b"
--   b:spawn("b", "MT52 Hornet", "Relic Active", "Drone 7", x, y, 0, {impulse = 156, beam_damage = 12})
--   b:start()            -- ships spawned before start() wait frozen (no impulse, no turning)
--   b:tick(now)          -- every frame: retargeting and missile top-ups, every RETARGET_EVERY s
--   b:alive("a")         -- live ships on a side
--
-- The rules:
-- * No warp or jump drive for any ship of the battle.
-- * Speeds are normalized: each hull's impulse, turn rate and acceleration are mapped linearly
--   from the range the battle's hulls have stock (`hulls`, measured once; or `norm_hulls`, so one
--   battle keeps another's speeds) onto BATTLE.NORM; then BATTLE.HULL_TWEAKS adjusts single hulls;
--   then the side's impulse multiplier. spawn's `over` replaces single stats for one ship
--   (impulse, turn, accel) and sets its beam damage (beam_damage).
-- * The combat points sit on a line through (x, y), spacing_u apart, running towards line_heading
--   (degrees, 0 = north; default 180: a north-south line, point 1 northernmost). Each side's ships,
--   ordered along that line, are mapped proportionally onto them, so ships head straight across
--   rather than through each other's lanes. A ship spawned after start() joins the nearest point
--   that has live enemies (fewest of its own side on a tie); assign(side) re-deals a whole side.
-- * A ship whose point has no living enemy targeting it moves to the nearest point that has some.
-- * Ships of the sides listed in `topup` refill their missiles when down to TOPUP_AT (beamless
--   missile boats otherwise leave the fight to look for a restock once they run dry).

BATTLE = BATTLE or {}

BATTLE.NORM = {
    impulse = {80, 120},   -- forward impulse
    turn    = {15, 28},    -- degrees per second
    accel   = {15, 25},    -- forward (and reverse) acceleration
}
BATTLE.HULL_TWEAKS = {
    ["Piranha F12"] = {turn = 1.3, accel = 1.3},   -- broadside boats need to swing round
}
-- The Battle Lab's hulls: the speed range every Concord battle group is normalized over, so the
-- Concord flies the same in every battle (Atlantis X23 80, Phobos T3 104, Adder MK5 120 impulse).
BATTLE.REF_HULLS = {"Atlantis X23", "Phobos T3", "Adder MK5", "Piranha F12"}
BATTLE.TOPUP_AT       = 0.25
BATTLE.RETARGET_EVERY = 2

local U = 1000
local MISSILES = {"Homing", "HVLI", "EMP", "Nuke", "Mine"}

local Battle = {}
Battle.__index = Battle

-- Stock stats of each hull into `st` (from throwaway ships, far away). Unless `stats_only`, the
-- hulls also set the range each stat is normalized over.
local function measure(st, hulls, stats_only)
    st = st or {hulls = {}, impulse = {math.huge, -math.huge}, turn = {math.huge, -math.huge}, accel = {math.huge, -math.huge}}
    for _, hull in ipairs(hulls) do
        if not st.hulls[hull] then
            local s = CpuShip():setTemplate(hull):setPosition(0, -900000)
            local v = {impulse = (s:getImpulseMaxSpeed()), turn = s:getRotationMaxSpeed(), accel = s:getAcceleration()}
            s:destroy()
            st.hulls[hull] = v
            if not stats_only then
                for stat, x in pairs(v) do
                    st[stat][1] = math.min(st[stat][1], x)
                    st[stat][2] = math.max(st[stat][2], x)
                end
            end
        end
    end
    return st
end

function BATTLE.new(opts)
    local b = setmetatable({
        x = opts.x or 0, y = opts.y or 0,
        n_points = opts.points or 5, spacing_u = opts.spacing_u or 1.5,
        line_heading = opts.line_heading or 180,
        sides = {a = {}, b = {}}, mult = {a = 1, b = 1},
        topup = {}, started = false, next_tick = 0, retargets = 0, topups = 0,
    }, Battle)
    for _, side in ipairs(opts.topup or {}) do b.topup[side] = true end
    b.stock = measure(nil, opts.norm_hulls or opts.hulls or {})
    measure(b.stock, opts.hulls or {}, opts.norm_hulls ~= nil)   -- with norm_hulls: stats only, the range stays
    b:layout()
    return b
end

-- A hull's final stat: normalized, then its tweak.
function Battle:stat(hull, stat)
    local v = self.stock.hulls[hull]
    if not v then return nil end
    local lo, hi = self.stock[stat][1], self.stock[stat][2]
    local a, z = BATTLE.NORM[stat][1], BATTLE.NORM[stat][2]
    local x = hi > lo and a + (v[stat] - lo) / (hi - lo) * (z - a) or z
    local t = BATTLE.HULL_TWEAKS[hull]
    return x * (t and t[stat] or 1)
end

-- The unit vector along the points' line (heading 0 = north, 90 = east; y grows southward).
function Battle:axis()
    local h = math.rad(self.line_heading)
    return math.sin(h), -math.cos(h)
end

function Battle:layout()
    local ux, uy = self:axis()
    self.points = {}
    for k = 1, self.n_points do
        local d = (k - (self.n_points + 1) / 2) * self.spacing_u * U
        self.points[k] = {self.x + ux * d, self.y + uy * d}
    end
end

local function speeds(self, r)
    r.ship:setImpulseMaxSpeed(r.fwd * self.mult[r.side], r.rev)
    r.ship:setRotationMaxSpeed(r.turn)
    r.ship:setAcceleration(r.accel, r.accel)
end

-- Spawn one ship of a side; frozen until start() if the battle has not started (frozen, not idle:
-- an idle ship can turn away from the enemy and then take a long time to swing back; playtest),
-- else it joins a point at once (enlist). `over` (optional): {impulse =, turn =, accel =} replace
-- those stats, beam_damage sets every beam's damage. Returns the ship and its record.
function Battle:spawn(side, hull, faction, name, x, y, heading, over)
    if not self.stock.hulls[hull] then measure(self.stock, {hull}, true) end   -- not listed up front: stats only
    over = over or {}
    local s = CpuShip():setTemplate(hull):setFaction(faction):setCallSign(name)
    s:setPosition(x, y):setHeading(heading)
    s:setWarpDrive(false)
    pcall(function() s:setJumpDrive(false) end)
    if over.beam_damage then
        for i = 0, 15 do
            local range = s:getBeamWeaponRange(i)
            if range and range > 0 then
                s:setBeamWeapon(i, s:getBeamWeaponArc(i), s:getBeamWeaponDirection(i), range,
                    s:getBeamWeaponCycleTime(i), over.beam_damage)
            end
        end
    end
    local _, rev = s:getImpulseMaxSpeed()
    local r = {ship = s, side = side, hull = hull, rev = rev,
               fwd = over.impulse or self:stat(hull, "impulse"), turn = over.turn or self:stat(hull, "turn"),
               accel = over.accel or self:stat(hull, "accel")}
    self.sides[side][#self.sides[side] + 1] = r
    if self.started then
        speeds(self, r)
        self:enlist(r)
    else
        s:setImpulseMaxSpeed(0, 0):setRotationMaxSpeed(0)
        s:orderIdle()
    end
    return s, r
end

function Battle:defend(r)
    local p = self.points[r.pos]
    r.ship:orderDefendLocation(p[1], p[2])
end

-- Map a side's ships, ordered along the points' line by where they are, proportionally onto them.
function Battle:assign(side)
    local ships = {}
    for _, r in ipairs(self.sides[side]) do if r.ship:isValid() then ships[#ships + 1] = r end end
    local ux, uy = self:axis()
    local along = {}
    for _, r in ipairs(ships) do
        local x, y = r.ship:getPosition()
        along[r] = x * ux + y * uy
    end
    table.sort(ships, function(p, q) return along[p] < along[q] end)
    local n = #ships
    for i, r in ipairs(ships) do
        r.pos = n > 1 and math.floor((i - 1) * (self.n_points - 1) / (n - 1) + 0.5) + 1 or (self.n_points + 1) // 2
        self:defend(r)
    end
end

function Battle:start()
    if self.started then return end
    self.started = true
    for _, side in ipairs({"a", "b"}) do
        for _, r in ipairs(self.sides[side]) do if r.ship:isValid() then speeds(self, r) end end
        self:assign(side)
    end
end

function Battle:alive(side)
    local n = 0
    for _, r in ipairs(self.sides[side]) do if r.ship:isValid() then n = n + 1 end end
    return n
end

function Battle:ships(side)
    local out = {}
    for _, r in ipairs(self.sides[side]) do if r.ship:isValid() then out[#out + 1] = r.ship end end
    return out
end

local function hasEnemies(k, enemies)
    for _, e in ipairs(enemies) do
        if e.pos == k and e.ship:isValid() then return true end
    end
    return false
end

-- A ship joining after start(): the nearest point that has live enemies (any point if none do),
-- the one with fewest of its own side on a tie.
function Battle:enlist(r)
    local enemies = self.sides[r.side == "a" and "b" or "a"]
    local any_live = false
    for k = 1, self.n_points do if hasEnemies(k, enemies) then any_live = true; break end end
    local x, y = r.ship:getPosition()
    local best, best_d, best_n
    for k = 1, self.n_points do
        if not any_live or hasEnemies(k, enemies) then
            local p = self.points[k]
            local d = math.floor(math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2) / 500)   -- 0.5U buckets: near-ties
            local n = 0
            for _, f in ipairs(self.sides[r.side]) do if f ~= r and f.pos == k and f.ship:isValid() then n = n + 1 end end
            if not best or d < best_d or (d == best_d and n < best_n) then best, best_d, best_n = k, d, n end
        end
    end
    r.pos = best
    self:defend(r)
end

-- Ships whose point has no living enemy targeting it move to the nearest point that has some.
function Battle:retarget(side, other)
    local enemies = self.sides[other]
    local live = {}
    for k = 1, self.n_points do if hasEnemies(k, enemies) then live[#live + 1] = k end end
    if #live == 0 then return end
    for _, r in ipairs(self.sides[side]) do
        if r.ship:isValid() and r.pos and not hasEnemies(r.pos, enemies) then
            local best, best_d = {}, math.huge
            for _, k in ipairs(live) do
                local d = math.abs(k - r.pos)
                if d < best_d then best, best_d = {k}, d elseif d == best_d then best[#best + 1] = k end
            end
            r.pos = best[math.random(#best)]
            self:defend(r)
            self.retargets = self.retargets + 1
        end
    end
end

function Battle:topUp(side)
    for _, r in ipairs(self.sides[side]) do
        local s = r.ship
        if s:isValid() then
            local have, max = 0, 0
            for _, w in ipairs(MISSILES) do
                local m = s:getWeaponStorageMax(w) or 0
                if m > 0 then max = max + m; have = have + (s:getWeaponStorage(w) or 0) end
            end
            if max > 0 and have <= max * BATTLE.TOPUP_AT then
                for _, w in ipairs(MISSILES) do
                    local m = s:getWeaponStorageMax(w) or 0
                    if m > 0 then s:setWeaponStorage(w, m) end
                end
                self.topups = self.topups + 1
            end
        end
    end
end

function Battle:tick(now)
    if not self.started or now < self.next_tick then return end
    self.next_tick = now + BATTLE.RETARGET_EVERY
    self:retarget("a", "b")
    self:retarget("b", "a")
    for side in pairs(self.topup) do self:topUp(side) end
end

-- Live changes (the Battle Lab's GM buttons).
function Battle:setImpulse(side, mult)
    self.mult[side] = mult
    if not self.started then return end
    for _, r in ipairs(self.sides[side]) do if r.ship:isValid() then speeds(self, r) end end
end

function Battle:setSpacing(u)
    self.spacing_u = u
    self:layout()
    for _, side in ipairs({"a", "b"}) do
        for _, r in ipairs(self.sides[side]) do if r.ship:isValid() and r.pos then self:defend(r) end end
    end
end

-- Remove every ship of the battle.
function Battle:clear()
    for _, side in ipairs({"a", "b"}) do
        for _, r in ipairs(self.sides[side]) do
            if r.ship:isValid() then
                pcall(function() r.ship:setCanBeDestroyed(true) end)
                r.ship:destroy()
            end
        end
        self.sides[side] = {}
    end
end

-- ── The Annex battle (the Boneyard arc's climax; the Battle Lab's "Annex" mode) ─────────────────
-- Side a: a Concord battle group (Concord Hostile) spawns active on a line 15U north-west of the
-- Annex, running north-east to south-west, and heads for five combat points on a line 3U
-- north-west of it. Side b: small, fast Relic drones (Relic Active: enemies of the Concord only)
-- come out of the two Boneyard nebulae north-east and south-west of the Annex; every drone that
-- dies is replaced from the nebula it came from while any Concord ship is left. Once armed, the
-- Annex's own lasers fire on the nearest Concord ship in range. All positions are relative to the
-- Annex, in U; bearings in degrees (0 = north).

BATTLE.ANNEX = {
    -- The command ship is the middle one (CNS Vanguard, as before); hulls repeat for bigger groups.
    concord_hulls = {"Atlantis X23", "Phobos T3", "Atlantis X23", "Phobos T3", "Atlantis X23", "Phobos T3", "Atlantis X23"},
    concord_names = {"Edict", "Statute", "Decree", "Mandate", "Writ", "Summons", "Levy", "Remand", "Injunction",
                     "Distraint", "Tariff", "Retribution"},
    command_name  = "CNS Vanguard",
    command_hull  = "Phobos T3",
    concord       = 7,
    drones        = 24,
    bearing       = 315,   -- both lines are north-west of the Annex ...
    concord_u     = 15,    -- ... the Concord's starting line this far out,
    points_u      = 3,     -- ... the combat points this far,
    line_heading  = 45,    -- ... and both run north-east / south-west (45 degrees, not north-south).
    ship_gap_u    = 2,     -- between Concord ships on the starting line
    spacing_u     = 1.5,   -- between combat points
    points        = 5,
    -- Drone gates: just inside the Boneyard nebulae north-east (12.5U) and south-west (11.5U) of
    -- the Annex, the far side of each cloud. The south-west gate keeps 6.6U from Ashgrave's centre
    -- (radius 3.4U); drones appear within gate_scatter_u of a gate.
    gates         = {{7.2, -10.2}, {-10.1, 5.6}},
    gate_scatter_u = 1.2,
    drone_hull    = "MT52 Hornet",   -- a small fighter, yellow like the Relic's other drones
    drone_beam    = 12,              -- twice the 6 of a stock drone's laser (Ktlitan Drone, Stalker)
    drone_speed   = 1.5,             -- x the fastest Concord ship's impulse (no warp)
    drone_turn    = 30,
    drone_accel   = 35,
    lasers        = {count = 3, range = 4500, cycle = 3, damage = 8},   -- the Annex's, once armed
}

local Annex = {}
Annex.__index = Annex

local function bearingXY(x, y, bearing, d)
    local h = math.rad(bearing)
    return x + math.sin(h) * d, y - math.cos(h) * d
end

-- annex: the station entity; opts override BATTLE.ANNEX fields.
function BATTLE.annex(annex, opts)
    local cfg = setmetatable(opts or {}, {__index = BATTLE.ANNEX})
    local ax, ay = annex:getPosition()
    local px, py = bearingXY(ax, ay, cfg.bearing, cfg.points_u * U)
    local hulls = {cfg.drone_hull, cfg.command_hull}
    for _, h in ipairs(cfg.concord_hulls) do hulls[#hulls + 1] = h end
    local b = BATTLE.new{x = px, y = py, points = cfg.points, spacing_u = cfg.spacing_u,
                         line_heading = cfg.line_heading, hulls = hulls, norm_hulls = BATTLE.REF_HULLS}
    b:start()   -- every ship spawns active
    local fastest = 0
    for _, h in ipairs(hulls) do
        if h ~= cfg.drone_hull then fastest = math.max(fastest, b:stat(h, "impulse")) end
    end
    return setmetatable({cfg = cfg, annex = annex, ax = ax, ay = ay, b = b,
        concord = {}, drones = {}, quota = {0, 0}, serial = 0, replaced = 0,
        drone_impulse = fastest * cfg.drone_speed, armed = false, next_at = 0}, Annex)
end

-- Spawn n Concord ships on the starting line, facing the Annex. Returns them; the command ship
-- (the middle one) is also self.cmd.
function Annex:spawnConcord(n)
    local cfg = self.cfg
    n = n or cfg.concord
    local cx, cy = bearingXY(self.ax, self.ay, cfg.bearing, cfg.concord_u * U)
    local mid = (n + 1) // 2
    local out = {}
    for i = 1, n do
        local x, y = bearingXY(cx, cy, cfg.line_heading, (i - (n + 1) / 2) * cfg.ship_gap_u * U)
        local cmd = i == mid and not (self.cmd and self.cmd:isValid())
        local hull = cmd and cfg.command_hull or cfg.concord_hulls[(i - 1) % #cfg.concord_hulls + 1]
        local name = cmd and cfg.command_name or ("CNS " .. cfg.concord_names[(#self.concord) % #cfg.concord_names + 1])
        local s = self.b:spawn("a", hull, "Concord Hostile", name, x, y, (cfg.bearing + 180) % 360)
        s:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
        if cmd then self.cmd = s end
        self.concord[#self.concord + 1] = s
        out[#out + 1] = s
    end
    self.b:assign("a")
    return out
end

function Annex:spawnDrone(k)
    local cfg = self.cfg
    local g = cfg.gates[k]
    local sc = cfg.gate_scatter_u * U
    local x = self.ax + g[1] * U + random(-sc, sc)
    local y = self.ay + g[2] * U + random(-sc, sc)
    self.serial = self.serial + 1
    local heading = (math.deg(math.atan(self.ay - y, self.ax - x)) + 90) % 360
    local s, r = self.b:spawn("b", cfg.drone_hull, "Relic Active", "Relic drone " .. self.serial, x, y, heading,
        {impulse = self.drone_impulse, turn = cfg.drone_turn, accel = cfg.drone_accel, beam_damage = cfg.drone_beam})
    r.gate = k
    self.drones[#self.drones + 1] = s
    return s
end

-- Spawn n drones, alternating between the two gates; each gate keeps its share topped up.
function Annex:spawnDrones(n)
    n = n or self.cfg.drones
    for i = 1, n do
        local k = (i - 1) % 2 + 1
        self.quota[k] = self.quota[k] + 1
        self:spawnDrone(k)
    end
    self.b:assign("b")
end

-- The Annex's lasers: the station takes the drones' side (Relic Active: enemies of the Concord
-- only, so they never fire on the crew) and its beams fire on the nearest Concord ship in range.
function Annex:armAnnex()
    if self.armed or not self.annex:isValid() then return end
    self.armed = true
    local L = self.cfg.lasers
    self.annex:setFaction("Relic Active")
    for i = 0, L.count - 1 do
        self.annex:setBeamWeapon(i, 360, i * 360 / L.count, L.range, L.cycle, L.damage)
        pcall(function() self.annex:setBeamWeaponHeatPerFire(i, 0); self.annex:setBeamWeaponEnergyPerFire(i, 0) end)
    end
end

function Annex:aimLasers()
    if not self.armed or not self.annex:isValid() then return end
    local best, best_d = nil, self.cfg.lasers.range
    for _, s in ipairs(self.b:ships("a")) do
        local x, y = s:getPosition()
        local d = math.sqrt((x - self.ax) ^ 2 + (y - self.ay) ^ 2)
        if d <= best_d then best, best_d = s, d end
    end
    self.laser_target = best
    pcall(function() self.annex.components.weapons_target = best and {entity = best} or nil end)
end

function Annex:concordAlive() return self.b:alive("a") end
function Annex:dronesAlive() return self.b:alive("b") end

-- Every frame: the battle's own tick, then once a second: replace dead drones from their gate
-- (while any Concord ship is left) and aim the Annex's lasers.
function Annex:tick(now)
    self.b:tick(now)
    if now < self.next_at then return end
    self.next_at = now + 1
    if self.b:alive("a") > 0 then
        local alive = {0, 0}
        for _, r in ipairs(self.b.sides.b) do
            if r.gate and r.ship:isValid() then alive[r.gate] = alive[r.gate] + 1 end
        end
        for k = 1, 2 do
            for _ = alive[k] + 1, self.quota[k] do
                self:spawnDrone(k)
                self.replaced = self.replaced + 1
            end
        end
    end
    self:aimLasers()
end

-- Remove every ship of the battle and disarm the Annex (back to Relic).
function Annex:clear()
    self.b:clear()
    self.concord, self.drones, self.quota, self.cmd = {}, {}, {0, 0}, nil
    if self.armed and self.annex:isValid() then
        pcall(function()
            self.annex.components.weapons_target = nil
            self.annex.components.beam_weapons = nil
            self.annex:setFaction("Relic")
        end)
    end
    self.armed = false
end
