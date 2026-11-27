-- ee/ragtag/match.lua
-- MATCH: how hard a fight should be, as a race. Each side's effective hit points (hull plus shields)
-- and damage a second give the time each needs to destroy the other:
--   T_crews  = enemy EHP / (crew DPS x r)        r: the crews' skill rating (1 = plays as the numbers say)
--   T_enemy  = crew EHP / (enemy DPS x f_type)   f_type: a measured per-type correction (MATCH.TYPE_FACTOR)
--   R        = T_enemy / T_crews                 above 1 favours the crews
-- MATCH.offer builds every group of 1-4 ships from a list of types and picks one near each target R:
-- easy, a good match and hard. The targets and type factors are first guesses, to be fitted from the
-- fight log (BOUT, tools/fight_stats.py). Loaded by the scenarios that use it, not by core.
-- Test: tests/core/bout.lua.

MATCH = MATCH or {}

MATCH.SHIELD_WEIGHT = 1.2     -- shields regenerate: a point of shield is worth a little more than hull
MATCH.FIGHT_SECS    = 90      -- missiles: a ship's whole stock is spread over a fight about this long
MATCH.MAX_GROUP     = 4
MATCH.TARGETS = {             -- target R for each slot, and the order they are offered in
    {slot = "easy",  r = 2.0, label = "Easy"},
    {slot = "match", r = 1.3, label = "Good match"},
    {slot = "hard",  r = 0.9, label = "Hard"},
}
MATCH.NEAR = 5                -- pick at random among this many groups nearest a target (variety)
-- Damage per missile (EmptyEpsilon's missilesystem.cpp); EMP only hits shields, counted at half.
MATCH.MISSILE_DAMAGE = {Homing = 35, HVLI = 10, Nuke = 160, Mine = 160, EMP = 80}
-- Measured per type: how much harder (above 1) or softer a type fights than its numbers. 1 until the
-- fight log says otherwise.
MATCH.TYPE_FACTOR = {}

-- ── One ship's numbers ───────────────────────────────────────────────────────
-- {ehp, dps}: effective hit points and damage a second (beams, plus missiles: as fast as the tubes
-- load, but no more than the stock spread over MATCH.FIGHT_SECS).
function MATCH.power(s)
    local ehp, dps = s:getHullMax() or 0, 0
    pcall(function()
        for i = 0, (s:getShieldCount() or 0) - 1 do ehp = ehp + MATCH.SHIELD_WEIGHT * (s:getShieldMax(i) or 0) end
    end)
    for i = 0, 15 do
        local r = s:getBeamWeaponRange(i)
        if r and r > 0 then
            local cyc = s:getBeamWeaponCycleTime(i)
            if cyc and cyc > 0 then dps = dps + (s:getBeamWeaponDamage(i) or 0) / cyc end
        end
    end
    local tubes = s:getWeaponTubeCount() or 0
    if tubes > 0 then
        local stock, best, count = 0, 0, 0
        for w, dmg in pairs(MATCH.MISSILE_DAMAGE) do
            local ok, n = pcall(function() return s:getWeaponStorage(w) end)
            n = ok and n or 0
            if n > 0 then
                stock = stock + n * dmg
                best = math.max(best, dmg)
                count = count + n
            end
        end
        if count > 0 then
            local load = 0
            for i = 0, tubes - 1 do
                local ok, t = pcall(function() return s:getTubeLoadTime(i) end)
                load = load + ((ok and t and t > 0) and t or 10)
            end
            local per_shot = stock / count
            local rate = tubes * per_shot / (load / tubes)
            dps = dps + math.min(rate, stock / MATCH.FIGHT_SECS)
        end
    end
    return {ehp = ehp, dps = dps}
end

-- A type's numbers, measured once on a ship spawned out of the way (cached).
MATCH._type_cache = {}
function MATCH.typePower(name)
    local c = MATCH._type_cache[name]
    if c then return c end
    local ok, res = pcall(function()
        local s = CpuShip():setTemplate(name):setFaction("Independent"):setPosition(-950000, -950000)
        s:orderIdle()
        local pw = MATCH.power(s)
        s:destroy()
        return pw
    end)
    c = ok and res or {ehp = 1, dps = 0}
    MATCH._type_cache[name] = c
    return c
end

-- The crews' side: every live player ship given (default: all).
function MATCH.crewPower(ships)
    local ehp, dps = 0, 0
    for _, p in ipairs(ships or RT.players) do
        if RT.valid(p) then
            local pw = MATCH.power(p)
            ehp, dps = ehp + pw.ehp, dps + pw.dps
        end
    end
    return {ehp = ehp, dps = dps}
end

-- R for a group (a list of type names) against the crews' power, with skill rating r (default 1).
function MATCH.ratio(crew, group, r)
    local ehp, dps = 0, 0
    for _, name in ipairs(group) do
        local pw = MATCH.typePower(name)
        ehp = ehp + pw.ehp
        dps = dps + pw.dps * (MATCH.TYPE_FACTOR[name] or 1)
    end
    if crew.dps <= 0 or ehp <= 0 then return 0 end
    if dps <= 0 then return math.huge end
    local t_crews = ehp / (crew.dps * (r or 1))
    local t_enemy = crew.ehp / dps
    return t_enemy / t_crews, t_crews, t_enemy
end

-- Every group of 1..MATCH.MAX_GROUP ships from `types` (repeats allowed, order ignored).
function MATCH.groups(types)
    local out, cur = {}, {}
    local function walk(from, left)
        if #cur > 0 then
            local g = {}
            for i, v in ipairs(cur) do g[i] = v end
            out[#out + 1] = g
        end
        if left == 0 then return end
        for i = from, #types do
            cur[#cur + 1] = types[i]
            walk(i, left - 1)
            cur[#cur] = nil
        end
    end
    walk(1, MATCH.MAX_GROUP)
    return out
end

-- "2 x Adder MK5, Phobos T3"
function MATCH.groupText(group)
    local counts, order = {}, {}
    for _, n in ipairs(group) do
        if not counts[n] then order[#order + 1] = n end
        counts[n] = (counts[n] or 0) + 1
    end
    table.sort(order)
    local parts = {}
    for _, n in ipairs(order) do parts[#parts + 1] = (counts[n] > 1 and (counts[n] .. " x ") or "") .. n end
    return table.concat(parts, ", ")
end

-- Three opponents for the crews: for each MATCH.TARGETS slot, one group (at random among the
-- MATCH.NEAR nearest its target R, never the same group twice). Returns
-- {{slot, label, target, group, r_value, t_crews, t_enemy}, ...}, or nil when there is nothing to offer.
function MATCH.offer(types, ships, r)
    local crew = MATCH.crewPower(ships)
    if crew.dps <= 0 or #types == 0 then return nil end
    local scored = {}
    for _, g in ipairs(MATCH.groups(types)) do
        local R, tc, te = MATCH.ratio(crew, g, r)
        if R > 0 and R < math.huge then scored[#scored + 1] = {group = g, r_value = R, t_crews = tc, t_enemy = te} end
    end
    if #scored == 0 then return nil end
    local used, out = {}, {}
    for _, t in ipairs(MATCH.TARGETS) do
        table.sort(scored, function(a, b)
            return math.abs(math.log(a.r_value / t.r)) < math.abs(math.log(b.r_value / t.r))
        end)
        local near = {}
        for _, s in ipairs(scored) do
            local key = MATCH.groupText(s.group)
            if not used[key] then near[#near + 1] = s end
            if #near >= MATCH.NEAR then break end
        end
        local pick = near[math.random(math.max(1, #near))]
        if pick then
            used[MATCH.groupText(pick.group)] = true
            out[#out + 1] = {slot = t.slot, label = t.label, target = t.r, group = pick.group,
                             r_value = pick.r_value, t_crews = pick.t_crews, t_enemy = pick.t_enemy}
        end
    end
    return out
end
