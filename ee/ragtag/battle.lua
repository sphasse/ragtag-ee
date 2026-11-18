-- ee/ragtag/battle.lua
-- BATTLE: set-piece battles between two lines of NPC ships, fought over a few invisible combat
-- points so they stay spread out instead of collapsing into one mass. Worked out in the Battle Lab
-- (scenarios/battlelab) and used by it and by the Corsair arc's battle at Blackwater.
--
--   local b = BATTLE.new{x = cx, y = cy, points = 5, spacing_u = 1.5, hulls = {...}, topup = {"b"}}
--   b:spawn("a", "Atlantis X23", "Concord Hostile", "CNS Writ", x, y, 90)   -- side "a" or "b"
--   b:start()            -- ships spawned before start() wait frozen (no impulse, no turning)
--   b:tick(now)          -- every frame: retargeting and missile top-ups, every RETARGET_EVERY s
--   b:alive("a")         -- live ships on a side
--
-- The rules:
-- * No warp or jump drive for any ship of the battle.
-- * Speeds are normalized: each hull's impulse, turn rate and acceleration are mapped linearly
--   from the range the battle's hulls have stock (`hulls`, measured once) onto BATTLE.NORM; then
--   BATTLE.HULL_TWEAKS adjusts single hulls; then the side's impulse multiplier.
-- * The combat points sit on a north-south line through (x, y), spacing_u apart. Each side's ships,
--   ordered north to south, are mapped proportionally onto them (north to south), so ships head
--   straight across rather than through each other's lanes.
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
BATTLE.TOPUP_AT       = 0.25
BATTLE.RETARGET_EVERY = 2

local U = 1000
local MISSILES = {"Homing", "HVLI", "EMP", "Nuke", "Mine"}

local Battle = {}
Battle.__index = Battle

-- Stock stats of each hull into `st`, and the min / max of each stat (from throwaway ships, far away).
local function measure(st, hulls)
    st = st or {hulls = {}, impulse = {math.huge, -math.huge}, turn = {math.huge, -math.huge}, accel = {math.huge, -math.huge}}
    for _, hull in ipairs(hulls) do
        if not st.hulls[hull] then
            local s = CpuShip():setTemplate(hull):setPosition(0, -900000)
            local v = {impulse = (s:getImpulseMaxSpeed()), turn = s:getRotationMaxSpeed(), accel = s:getAcceleration()}
            s:destroy()
            st.hulls[hull] = v
            for stat, x in pairs(v) do
                st[stat][1] = math.min(st[stat][1], x)
                st[stat][2] = math.max(st[stat][2], x)
            end
        end
    end
    return st
end

function BATTLE.new(opts)
    local b = setmetatable({
        x = opts.x or 0, y = opts.y or 0,
        n_points = opts.points or 5, spacing_u = opts.spacing_u or 1.5,
        sides = {a = {}, b = {}}, mult = {a = 1, b = 1},
        topup = {}, started = false, next_tick = 0, retargets = 0, topups = 0,
    }, Battle)
    for _, side in ipairs(opts.topup or {}) do b.topup[side] = true end
    b.stock = measure(nil, opts.hulls or {})
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

function Battle:layout()
    self.points = {}
    for k = 1, self.n_points do
        self.points[k] = {self.x, self.y + (k - (self.n_points + 1) / 2) * self.spacing_u * U}
    end
end

local function speeds(self, r)
    r.ship:setImpulseMaxSpeed(r.fwd * self.mult[r.side], r.rev)
    r.ship:setRotationMaxSpeed(r.turn)
    r.ship:setAcceleration(r.accel, r.accel)
end

-- Spawn one ship of a side; frozen until start() if the battle has not started.
function Battle:spawn(side, hull, faction, name, x, y, heading)
    if not self.stock.hulls[hull] then measure(self.stock, {hull}) end   -- not listed up front: add it
    local s = CpuShip():setTemplate(hull):setFaction(faction):setCallSign(name)
    s:setPosition(x, y):setHeading(heading)
    s:setWarpDrive(false)
    pcall(function() s:setJumpDrive(false) end)
    local _, rev = s:getImpulseMaxSpeed()
    local r = {ship = s, side = side, hull = hull, rev = rev,
               fwd = self:stat(hull, "impulse"), turn = self:stat(hull, "turn"), accel = self:stat(hull, "accel")}
    self.sides[side][#self.sides[side] + 1] = r
    if self.started then
        speeds(self, r)
    else
        s:setImpulseMaxSpeed(0, 0):setRotationMaxSpeed(0)
        s:orderIdle()
    end
    return s
end

function Battle:defend(r)
    local p = self.points[r.pos]
    r.ship:orderDefendLocation(p[1], p[2])
end

-- Map a side's ships, north to south by where they are, proportionally onto the points.
function Battle:assign(side)
    local ships = {}
    for _, r in ipairs(self.sides[side]) do if r.ship:isValid() then ships[#ships + 1] = r end end
    table.sort(ships, function(p, q)
        local _, yp = p.ship:getPosition()
        local _, yq = q.ship:getPosition()
        return yp < yq
    end)
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
