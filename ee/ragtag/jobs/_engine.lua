-- ee/ragtag/jobs/_engine.lua
-- Job board engine: registration, weighted selection, accept/update/complete.
-- Type-specific logic lives in individual modules under ee/ragtag/jobs/.
-- Load via ee/ragtag/jobs.lua, not directly.

JOBS = JOBS or {}

-- ── Shared economy config (option B: one place to tune all reward math) ──────
-- type_mult is populated by each module via JOBS.register().
JOBS.ECONOMY = {
    base_reward = {[0] = 50, [1] = 65, [2] = 80},
    type_mult   = {},
}

-- Speed constants for duration formulas (world-units/s).
JOBS.SPEED = { warp1 = 500, impulse = 100 }

-- Runtime session config — scenario may write these before or during play.
JOBS.config = {
    work_cooldown_enabled = true,
    work_cooldown_secs    = 10 * 60,
    -- How long a TAKEN slot stays empty before a new job fills it (nil: work_cooldown_secs).
    -- Untaken offers still stand for work_cooldown_secs. The Short Haul sets 0: a taken job is
    -- replaced at once, but the board is not re-rolled on every hail.
    refill_secs           = nil,
    mission_distance_mode = "medium",   -- "short"|"medium"|"long"
    jobboard_locked       = false,       -- set true during Witness arc
    max_active            = 2,           -- per ship
    station_slots         = 2,
}

-- Internal state.
JOBS._registry     = {}   -- type_string → module table
JOBS._active       = {}   -- list of {mission, phase, ship}: every ship's jobs; see JOBS.activeFor
JOBS._done         = {}   -- mission id → true (taken or completed this session)
JOBS._station_work = {}   -- callsign → {slots = [...]}
JOBS._panel_next   = 0
JOBS._tick_hooks   = {}   -- functions(now) called each update cycle for post-mission work

-- ── Injected jobs (story arcs seed the board) ────────────────────────────────
-- Arcs add jobs with JOBS.inject() from M.on_load / phase enter and remove them
-- with JOBS.removeCategory() from M.on_unload / exit (same pattern as RUMORS).
--   priority 5 (hook): always on the board at every matching station, outside the normal
--                      slot count, as soon as when() holds. Use for story contracts.
--   priority 3 (seed): ordinary-looking board work. Each time a station fills a slot,
--                      there is a JOBS.SEED_CHANCE chance an eligible seed is used
--                      instead of a random job. Cached with the slot like any job.
JOBS.SEED_CHANCE = 0.4
JOBS._injected   = {}
local _inject_seq = 0

-- def = {
--   category = "BONEYARD_JOBS",      -- for removeCategory
--   priority = 5 | 3,                -- default 3
--   origin   = "Port Vesper" | {"A","B"} | nil (any station),
--   when     = function(cs) ... end, -- optional; evaluated each time the board is opened
--   ensure   = true,                 -- priority 3 only: guarantee this job is on the station's
--                                    -- board (takes a free slot, else replaces a cached ordinary
--                                    -- job). Still looks like a normal job (no [SPECIAL] tag).
--   any_ship = true,                 -- not arc work: offered to every player ship (tests, GM).
--                                    -- Without it an injected job is for the primary ship only.
--   for_ship = <ship>,               -- not arc work: offered to that one player ship only (GM).
--   record   = <mission table> | function(cs) return <mission table> end,
-- }
-- Build records with JOBS.build("delivery"|"salvage", opts) (see those modules).
function JOBS.inject(def)
    _inject_seq = _inject_seq + 1
    local e = {
        id = def.id or ("inj_" .. _inject_seq),
        category = def.category, priority = def.priority or 3,
        origin = def.origin, when = def.when, record = def.record, ensure = def.ensure,
        any_ship = def.any_ship, for_ship = def.for_ship, missions = {},
    }
    JOBS._injected[#JOBS._injected + 1] = e
    return e.id
end

-- Remove one injected job by the id JOBS.inject returned (a job already taken carries on).
function JOBS.removeInjected(id)
    for i = #JOBS._injected, 1, -1 do
        if JOBS._injected[i].id == id then table.remove(JOBS._injected, i) end
    end
end

-- Whether `ship` may see and take job `m`: generated jobs are open to every ship; an injected
-- job is for its for_ship, every ship (any_ship), or else the primary ship only (arc work).
function JOBS._openTo(m, ship)
    if not m._inject then return true end
    if m._for_ship then return m._for_ship == ship end
    return (m._any_ship or ship == RT.player) and true or false
end

function JOBS.removeCategory(category)
    for i = #JOBS._injected, 1, -1 do
        if JOBS._injected[i].category == category then table.remove(JOBS._injected, i) end
    end
end

local function _originMatches(e, cs)
    if e.origin == nil then return true end
    if type(e.origin) == "string" then return e.origin == cs end
    for _, o in ipairs(e.origin) do if o == cs then return true end end
    return false
end

-- Eligible missions at station cs. hook=true -> priority >= 4; false -> seeds.
-- primary=false: only the entries open to every ship (any_ship). An entry with for_ship is
-- listed only when `ship` is that ship.
function JOBS._injectedFor(cs, hook, primary, ship)
    local out = {}
    for _, e in ipairs(JOBS._injected) do
        local open
        if e.for_ship then open = (ship ~= nil and e.for_ship == ship)
        else open = (primary ~= false or e.any_ship) end
        if (e.priority >= 4) == hook and _originMatches(e, cs) and open then
            local ok_when = true
            if e.when then
                local ok, res = pcall(e.when, cs)
                ok_when = ok and res and true or false
            end
            if ok_when then
                local m = e.missions[cs]
                if not m then
                    local rec = e.record
                    if type(rec) == "function" then
                        local ok, res = pcall(rec, cs)
                        rec = ok and res or nil
                        if not ok then log("[JOBS] inject record error: " .. tostring(res)) end
                    end
                    if rec then
                        rec.id      = rec.id or (e.id .. ":" .. cs)
                        rec.origin  = rec.origin or cs
                        rec._inject = e.id
                        rec._ensure = e.ensure and e.priority < 4 or nil
                        rec._any_ship = e.any_ship or nil
                        rec._for_ship = e.for_ship
                        e.missions[cs] = rec
                        m = rec
                    end
                end
                if m and not JOBS._done[m.id] then out[#out + 1] = m end
            end
        end
    end
    return out
end

-- Build a mission record of the given type through its module's build(opts).
-- Common story opts, handled for every type:
--   story=true    bypasses max_active, no expiry timer, no reputation penalty on
--                 failure, re-offered after a failure, listed as [SPECIAL]
--   special=true  listed as [SPECIAL] without the story rules
--   accept_log    text for the accept ship log (replaces the generic "N minutes" line)
--   on_accept(m), on_complete(m), on_fail(m), on_found(m: salvage cargo picked up)
function JOBS.build(mtype, o)
    local mod = JOBS._registry[mtype]
    assert(mod and mod.build, "JOBS.build: no builder for type " .. tostring(mtype))
    local m = mod.build(o)
    m.id = o.id or m.id
    for _, k in ipairs({"story", "special", "time_limit", "accept_log", "on_accept", "on_complete", "on_fail", "on_found", "category"}) do
        if o[k] ~= nil then m[k] = o[k] end
    end
    if m.story then m.special = true end
    return m
end

local function _cb(m, name)
    if m[name] then
        local ok, err = pcall(m[name], m)
        if not ok then log("[JOBS] " .. name .. " error: " .. tostring(err)) end
    end
end

-- A job was lost (expired / cargo destroyed). Story jobs come back on the board.
function JOBS._failed(m)
    if STATS then STATS.jobFailed(m) end
    _cb(m, "on_fail")
    if m.story then
        JOBS._done[m.id] = nil
        for _, e in ipairs(JOBS._injected) do
            if e.id == m._inject and m.origin then e.missions[m.origin] = nil end
        end
    end
end

-- First dock at each station is recorded as flag visited_<callsign> (saved with the
-- campaign) so arcs can gate on "the crew has been to X".
function JOBS.hasVisited(cs) return RT.flag("visited_" .. cs) and true or false end

-- ── Shared utilities (used by all job type modules) ───────────────────────────

local _id_seq = 0
function JOBS.nextId()
    _id_seq = _id_seq + 1
    return "job_" .. _id_seq
end

-- Returns the in-game sector label (e.g. "F5") for world-unit coordinates.
function JOBS.gridRef(wx, wy)
    return getSectorName(wx, wy)
end

local _SHORT_NAMES = {
    ["Concord Station Arbiter"] = "C.S. Arbiter",
    ["Concord Waypoint Galen"]  = "Waypoint Galen",
    ["Saint Brennan's Mission"] = "St. Brennan's",
    ["Lastchance Outpost"]      = "Lastchance",
    ["Dustmote Salvage"]        = "Dustmote",
    ["Greywater Depot"]         = "Greywater",
}
function JOBS.shortName(cs) return _SHORT_NAMES[cs] or cs end

-- The shortest recognisable form of a station's name, for the 20-character side panels:
-- "Halcyon Rest" -> "Halcyon", "Concord Station Arbiter" -> "Arbiter".
local _TINY_NAMES = {
    ["Port Vesper"]             = "Vesper",
    ["Concord Station Arbiter"] = "Arbiter",
    ["Concord Waypoint Galen"]  = "Galen",
    ["Saint Brennan's Mission"] = "Brennan's",
    ["Sentinel Fleet Yard"]     = "Sentinel",
    ["The Maw"]                 = "Maw",
}
function JOBS.tinyName(cs)
    cs = tostring(cs or "?")
    return _TINY_NAMES[cs] or cs:match("^(%S+)") or cs
end

JOBS.PANEL_MAX = 20   -- RT.SIDE_LINE_MAX: a status line on the side panels

-- What an active job shows on Relay: one line of at most JOBS.PANEL_MAX characters, saying what
-- to do next ("Deliver to Halcyon Rest", "Destroy Iron Gull", "Return to Vesper"). A station
-- name is shortened (JOBS.shortName, then JOBS.tinyName) until the line fits, then it is cut.
function JOBS.panelLine(m)
    local max = JOBS.PANEL_MAX
    local function fit(verb, cs)
        for _, name in ipairs({cs, JOBS.shortName(cs), JOBS.tinyName(cs)}) do
            local line = verb .. " " .. name
            if #line <= max then return line end
        end
        return (verb .. " " .. JOBS.tinyName(cs)):sub(1, max)
    end
    local function named(verb, name) return (verb .. " " .. tostring(name or "target")):sub(1, max) end
    local t = m.type
    -- The work is done: back to the station that pays.
    if m._found or m._hacked or m._destroyed or m._scanned or m._boarded then
        return fit("Return to", m.origin)
    end
    if t == "delivery" then return fit("Deliver to", m.dest) end
    if t == "escort" then return fit("Escort to", m.dest) end
    if t == "salvage" then
        local grid = (m.wx and m.wy and getSectorName) and getSectorName(m.wx, m.wy) or nil
        return grid and ("Salvage at " .. grid) or "Salvage"
    end
    if t == "hacking" then return named("Hack", m.target_cs) end
    if t == "destroy" then return named("Destroy", m.target_cs) end
    if t == "boarding" then return named("Board", m.target_cs) end
    if t == "tailing" then return named("Tail", m.target_cs) end
    return tostring(m.short or "Job"):sub(1, max)
end

function JOBS.stationFaction(cs)
    for _, st in ipairs(VERSE.STATIONS) do
        if st.cs == cs then return st.fac end
    end
    return "Independent"
end

function JOBS.weightedPick(list)
    local total = 0
    for _, e in ipairs(list) do total = total + (e.weight or 1) end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - (e.weight or 1)
        if r <= 0 then return e end
    end
    return list[#list]
end

-- Calculate reward with distance, danger, and urgency modifiers.
-- distance_min_u/max_u: range for a 0-30% distance bonus.
-- danger_level: +15% per level.  urgency_mult: 1.5 for urgent, 1.0 otherwise.
function JOBS.calcReward(base, type_mult, distance_u, danger_level, distance_min_u, distance_max_u, urgency_mult)
    local reward = base * type_mult
    if distance_u and distance_min_u and distance_max_u and distance_max_u > distance_min_u then
        local dist_pct = math.max(0, math.min(1,
            (distance_u - distance_min_u) / (distance_max_u - distance_min_u)))
        reward = reward * (1.0 + dist_pct * 0.30)
    end
    if danger_level and danger_level > 0 then
        reward = reward * (1.0 + danger_level * 0.15)
    end
    if urgency_mult and urgency_mult > 1 then
        reward = reward * urgency_mult
    end
    return math.floor(reward / 5 + 0.5) * 5
end

-- ── Ship name pools used by boarding, destroy, and tailing modules. ──────────
local _CORSAIR_NAMES = {
    "Blackjack", "Cutthroat", "Rogue Star", "Night Runner", "Silent Edge",
    "Red Drift", "Ghost Hound", "Dark Current", "Bone Cutter", "Scarlet Wake",
    "Shadow Play", "Viper's Run", "Iron Thorn", "Void Walker", "Cruel Fortune",
    "Wild Card", "Blood Money", "Fast Poison", "Dead Reckoning", "Sharp Practice",
    "Quick Silver", "Bad Penny", "Loose Cannon", "Dirty Business", "Hard Bargain",
    "Last Chance", "Cold Comfort", "Rough Justice", "Dark Horse", "Free Radical",
}
local _FREIGHTER_NAMES = {
    "Quiet Trade", "Long Run", "Far Margin", "Still Water", "Low Profile",
    "Unmarked", "Grey Cargo", "Clean Manifest", "Third Party", "No Questions",
    "Standard Rate", "Passing Through", "Brief Stop", "Short Notice", "Slow Moving",
    "Common Carriage", "Side Channel", "Dark Freight", "Off The Books", "Thin Air",
}
-- A name from the pool that no live object is using, so the crew never sees two ships with one
-- name. (Only for the crew's sake: jobs keep the ENTITIES they spawn, m.target / m.convoy / ...,
-- and never find them again by callsign.)
function JOBS.uniqueName(pool)
    for _ = 1, 40 do
        local name = pool[math.random(#pool)]
        if not RT.valid(RT.find(name)) then return name end
    end
    for n = 2, 99 do   -- every name is taken: number one
        local name = pool[math.random(#pool)] .. " " .. n
        if not RT.valid(RT.find(name)) then return name end
    end
    return pool[1] .. " " .. math.random(100, 999)
end
function JOBS.corsairName()   return JOBS.uniqueName(_CORSAIR_NAMES)   end
function JOBS.freighterName() return JOBS.uniqueName(_FREIGHTER_NAMES) end

-- ── Registration ──────────────────────────────────────────────────────────────
-- Each type module calls JOBS.register(M) with its table at load time.
-- Adding a type: create the file, add one require() line to jobs.lua.
function JOBS.register(mod)
    assert(mod.type,     "job type module missing .type")
    assert(mod.weight,   "job type module missing .weight")
    assert(mod.generate, "job type module missing .generate")
    JOBS._registry[mod.type] = mod
    if mod.type_mult then
        JOBS.ECONOMY.type_mult[mod.type] = mod.type_mult
    end
    log("[JOBS] registered type: " .. mod.type .. " (weight=" .. tostring(mod.weight) .. ")")
end

-- ── Tier ──────────────────────────────────────────────────────────────────────
-- A ship's job tier follows what that ship has put into upgrades (default: the primary ship).
function JOBS.maxTier(ship)
    if not RT.campaign then return 0 end
    local total = RT.upgradeSpend(ship)
    if total >= 1000 then return 2 elseif total >= 500 then return 1 else return 0 end
end

-- ── Type selection ────────────────────────────────────────────────────────────
-- Weights shift with tier so higher-investment ships see more variety and fewer
-- plain delivery/salvage offers. Falls back to mod.weight for unlisted types.
local _TIER_WEIGHTS = {
    [0] = {delivery=15, salvage=7},
    [1] = {delivery=10, salvage=6, hacking=4},
    [2] = {delivery=5,  salvage=4, hacking=5, destroy=5, boarding=5},
}

-- Weighted random draw from registered types whose tier_min <= maxTier().
function JOBS.pickType(ship)
    local mt = JOBS.maxTier(ship)
    local tw = _TIER_WEIGHTS[mt] or {}
    local pool, total = {}, 0
    for _, mod in pairs(JOBS._registry) do
        if (mod.tier_min or 0) <= mt then
            local w = tw[mod.type] or mod.weight or 1
            pool[#pool + 1] = {mod=mod, w=w}
            total = total + w
        end
    end
    if #pool == 0 then return "delivery" end
    local r = math.random() * total
    for _, e in ipairs(pool) do
        r = r - e.w
        if r <= 0 then return e.mod.type end
    end
    return pool[#pool].mod.type
end

-- ── Verse/spawn helpers ───────────────────────────────────────────────────────
local _VERSE_BOUNDS = nil
local function _verseBounds()
    if _VERSE_BOUNDS then return _VERSE_BOUNDS end
    local xn, xx, yn, yx = math.huge, -math.huge, math.huge, -math.huge
    for _, r in ipairs(VERSE.REGIONS) do
        if r.x - r.r < xn then xn = r.x - r.r end
        if r.x + r.r > xx then xx = r.x + r.r end
        if r.y - r.r < yn then yn = r.y - r.r end
        if r.y + r.r > yx then yx = r.y + r.r end
    end
    _VERSE_BOUNDS = {x_min=xn*VERSE.U, x_max=xx*VERSE.U, y_min=yn*VERSE.U, y_max=yx*VERSE.U}
    return _VERSE_BOUNDS
end

function JOBS.getDistanceRange()
    local m = JOBS.config.mission_distance_mode
    if m == "short" then return 15000,  50000
    elseif m == "long" then return 60000, 200000
    else                    return 30000, 100000 end
end

-- Returns wx, wy, dist_u, region or nil×4 when no point fits the verse bounds.
function JOBS.spawnInVerse(rx, ry, max_tries)
    local b = _verseBounds()
    local dmin, dmax = JOBS.getDistanceRange()
    for _ = 1, (max_tries or 8) do
        local ang  = math.random() * 2 * math.pi
        local dist = dmin + math.random() * (dmax - dmin)
        local wx   = math.floor(rx + math.cos(ang) * dist)
        local wy   = math.floor(ry + math.sin(ang) * dist)
        if wx >= b.x_min and wx <= b.x_max and wy >= b.y_min and wy <= b.y_max then
            return wx, wy, dist, VERSE.regionAt(wx, wy)
        end
    end
    return nil, nil, nil, nil
end

-- Returns list of non-hostile station callsigns within radius_u of (wx, wy).
function JOBS.nearbyStations(wx, wy, radius_u)
    local result = {}
    for _, st in ipairs(VERSE.STATIONS) do
        if st.fac ~= "Corsairs" and st.fac ~= "Hollow" then
            local e = RT.find(st.cs)
            if RT.valid(e) then
                local sx, sy = e:getPosition()
                local dx, dy = sx - wx, sy - wy
                if dx*dx + dy*dy < radius_u*radius_u then
                    result[#result + 1] = st.cs
                end
            end
        end
    end
    return result
end

-- ── Ownership ─────────────────────────────────────────────────────────────────
-- A job belongs to the ship that took it (m.ship). Only that ship advances it, completes it,
-- is paid for it, hears about it in its log, and gains or loses standing over it. Other player
-- ships can neither help nor sabotage. Each ship has its own cap (config.max_active), credits
-- and standing; the board itself is shared, so a job one ship takes is gone for the others.
-- Arc jobs (everything JOBS.inject adds: story contracts and seeds) are offered to, and can be
-- taken by, the primary ship only: story arcs belong to that ship.
-- Job modules use the helpers below and never RT.players / RT.shipLog / RT.hail.

-- The job's owner while it is alive, else nil.
function JOBS.owner(m)
    if RT.valid(m.ship) then return m.ship end
end

-- The ships whose position, docking and scans count for this job: {owner}, or {} when it is
-- gone. For loops in job modules:  for _, p in ipairs(JOBS.ships(m)) do ... end
function JOBS.ships(m)
    return {JOBS.owner(m)}
end

-- Ship log line for the job's owner.
function JOBS.log(m, text, color)
    local p = JOBS.owner(m)
    if p then p:addToShipLog(text, color or "#FFFFFF") end
end

-- Hail the job's owner from `from`. Returns true when the hail went out.
function JOBS.hail(m, from, text)
    local p = JOBS.owner(m)
    if not p or not RT.valid(from) then return false end
    return from:sendCommsMessage(p, text) and true or false
end

-- Change the owner's standing with a faction.
function JOBS.rep(m, faction, amount, reason)
    RT.addReputation(faction, amount, reason, m.ship)
end

-- A ship's active jobs (entries of JOBS._active), in the order taken.
function JOBS.activeFor(ship)
    local out = {}
    for _, e in ipairs(JOBS._active) do
        if e.ship == ship then out[#out + 1] = e end
    end
    return out
end

-- ── Panel ─────────────────────────────────────────────────────────────────────
-- Each ship's Relay screen lists its own jobs.
-- A job's countdown on Relay, under its line: "Time left 12:34", or nil for a job with no
-- time limit (a story job without one).
function JOBS.timerLine(m, now)
    if not m._expires_at then return nil end
    local left = math.max(0, math.floor(m._expires_at - (now or getScenarioTime())))
    return string.format("Time left %d:%02d", math.floor(left / 60), left % 60)
end

-- Relay order: credits (0), the region (1), then each job's line and its countdown under it.
-- Lines are re-sent only when they change, except on the 15 s refresh (force), which re-sends
-- everything so a line lost any other way comes back.
local _panel_shown = setmetatable({}, {__mode = "k"})   -- ship -> {key = caption}
local function _panelSet(p, key, txt, order, force)
    local shown = _panel_shown[p] or {}
    _panel_shown[p] = shown
    if shown[key] == txt and not force then return end
    shown[key] = txt
    if txt then p:addCustomInfo("relay", key, txt, order) else p:removeCustom(key) end
end

-- The countdown lines only (every second, from JOBS.update).
function JOBS.refreshTimers(now, force)
    RT.forEachPlayer(function(p)
        local mine = JOBS.activeFor(p)
        for slot = 1, JOBS.config.max_active do
            local entry = mine[slot]
            local txt = (entry and entry.phase == "active") and JOBS.timerLine(entry.mission, now) or nil
            _panelSet(p, "rt_job_" .. slot .. "_time", txt, 11 + 2 * slot, force)
        end
    end)
end

function JOBS.refreshPanel()
    RT.forEachPlayer(function(p)
        local mine = JOBS.activeFor(p)
        for slot = 1, JOBS.config.max_active do
            local entry = mine[slot]
            local txt = (entry and entry.phase == "active")
                        and JOBS.panelLine(entry.mission)
                        or  ("Job " .. slot .. ": (none)")
            _panelSet(p, "rt_job_" .. slot, txt, 10 + 2 * slot, true)
        end
    end)
    JOBS.refreshTimers(nil, true)
end

function JOBS.updateObj()
    RT.setObjective("Explore the Drift", true)
    JOBS.refreshPanel()
end

-- ── Accept ────────────────────────────────────────────────────────────────────
-- `ship` takes the job (default: the primary ship). Returns false when that ship is at its cap.
function JOBS.accept(m, skip_log, ship)
    ship = RT.playerShip(ship) or RT.player
    if not RT.valid(ship) then return false end
    if not JOBS._openTo(m, ship) then return false end   -- arc jobs: primary only; GM jobs: their ship
    if #JOBS.activeFor(ship) >= JOBS.config.max_active and not m.story then return false end
    m.ship = ship
    JOBS._done[m.id] = true

    local mod = JOBS._registry[m.type]
    m._time_limit = JOBS.timeLimit(m)
    -- Story jobs have no timer unless they set time_limit (seconds); either way a
    -- story job never costs reputation when it expires.
    m._expires_at = (m.time_limit or not m.story) and (getScenarioTime() + m._time_limit) or nil

    local os_e = RT.find(m.origin)
    if RT.valid(os_e) then m.origin_faction = os_e:getFaction() end

    JOBS._active[#JOBS._active + 1] = {mission = m, phase = "active", ship = ship}

    if m.origin and JOBS.config.work_cooldown_enabled then
        local ss = JOBS._station_work[m.origin]
        if ss and ss.slots then
            for sn, slot in pairs(ss.slots) do
                if slot.mission and slot.mission.id == m.id then
                    m._slot_num = sn
                    slot.taken_at = getScenarioTime()
                    slot.mission  = nil
                    break
                end
            end
        end
    end

    if mod and mod.spawn then mod.spawn(m) end
    JOBS.updateObj()
    if STATS then STATS.jobAccepted(m) end
    _cb(m, "on_accept")

    if not skip_log then
        local line = mod and mod.acceptLog and mod.acceptLog(m)
        if not line then
            local dest = m.dest or (m.wx and ("grid " .. JOBS.gridRef(m.wx, m.wy)) or "??")
            line = string.format("Contract: %s. %dm to complete. Head to %s.",
                m.short, math.floor(m._time_limit / 60), dest)
        end
        JOBS.log(m, line, "#60CCFF")
    end
    return true
end

-- A job's time limit in seconds: its own time_limit, else its type's duration, else 20 min;
-- always whole minutes (rounded down, at least one), so the clock starts at exactly the
-- minutes the board, the contract log and the Relay countdown show.
function JOBS.timeLimit(m)
    local mod = JOBS._registry[m.type]
    local t = m.time_limit or (mod and mod.duration and mod.duration(m)) or (20 * 60)
    return math.max(60, math.floor(t / 60) * 60)
end

-- ── Complete ──────────────────────────────────────────────────────────────────
-- Pays the job's owner. (The second argument is kept for callers; the owner is who is paid.)
function JOBS.complete(entry, _ship)
    local completing_ship = entry.ship
    entry.phase = "done"
    for i, a in ipairs(JOBS._active) do
        if a == entry then table.remove(JOBS._active, i); break end
    end
    local mod = JOBS._registry[entry.mission.type]
    if mod and mod.cleanup then mod.cleanup(entry.mission) end
    RT.addCredits(entry.mission.reward, "job: " .. entry.mission.short, completing_ship)

    local fac = entry.mission.origin_faction
    if not fac then
        local os_e = RT.find(entry.mission.origin)
        if RT.valid(os_e) then fac = os_e:getFaction() end
    end
    if fac then
        JOBS.rep(entry.mission, fac, entry.mission.reward, "completed: " .. entry.mission.short)
    end

    JOBS.updateObj()
    -- Board jobs this ship has finished (arcs' own story contracts excluded), kept in its record:
    -- an arc can wait for the primary ship to have done some work (the Ledger hook does).
    if not entry.mission.story then
        local rec = RT.shipRecord(completing_ship)
        if rec then rec.jobs_done = (rec.jobs_done or 0) + 1 end
    end
    if STATS then STATS.jobCompleted(entry.mission) end
    _cb(entry.mission, "on_complete")
    RT.emit("job_complete", {type=entry.mission.type, tier=entry.mission.tier, reward=entry.mission.reward,
        ship = RT.valid(completing_ship) and completing_ship:getCallSign() or nil}, "low")
end

-- ── Update ────────────────────────────────────────────────────────────────────
function JOBS.update()
    if not RT.anyPlayerAlive() then return end
    local now = getScenarioTime()

    if now >= JOBS._panel_next then
        JOBS._panel_next = now + 15
        JOBS.refreshPanel()
    elseif now >= (JOBS._timer_next or 0) then
        JOBS._timer_next = now + 1
        JOBS.refreshTimers(now)
    end

    local i = #JOBS._active
    while i >= 1 do
        local entry = JOBS._active[i]
        local m = entry.mission
        if entry.phase == "active" and not RT.valid(entry.ship) then
            -- The ship that held the contract is gone: the job goes with it, at no cost to anyone.
            local mod = JOBS._registry[m.type]
            if mod and mod.cleanup then pcall(mod.cleanup, m) end
            JOBS._failed(m)
            table.remove(JOBS._active, i)
            JOBS.updateObj()
        elseif entry.phase == "active" then
            if m._expires_at and now > m._expires_at then
                local mod = JOBS._registry[m.type]
                local handled = mod and mod.expire and mod.expire(m)
                if not handled then
                    JOBS.log(m, "[Contract] " .. m.short .. " -- time expired. Contract lost.", "#FF8080")
                    if m.origin_faction and not m.story then
                        JOBS.rep(m, m.origin_faction, -m.reward, "failed: " .. m.short)
                    end
                end
                if mod and mod.cleanup then mod.cleanup(m) end
                JOBS._failed(m)
                table.remove(JOBS._active, i)
                JOBS.updateObj()
            else
                local mod = JOBS._registry[m.type]
                if mod and mod.update then
                    local result = mod.update(m, entry, {now=now, jobs=JOBS})
                    if result == "remove" then
                        if m.origin_faction and not m.story then
                            JOBS.rep(m, m.origin_faction, -m.reward, "failed: " .. m.short)
                        end
                        if mod.cleanup then pcall(mod.cleanup, m) end
                        JOBS._failed(m)
                                table.remove(JOBS._active, i)
                        JOBS.updateObj()
                    end
                end
            end
        end
        i = i - 1
    end

    for _, fn in ipairs(JOBS._tick_hooks) do fn(now) end
end

-- ── Station hook ──────────────────────────────────────────────────────────────

local _SLOT_BY_TMPL = {
    ["Small Station"]  = 1,
    ["Medium Station"] = 2,
    ["Large Station"]  = 3,
    ["Huge Station"]   = 3,
}
function JOBS.stationSlots(cs)
    for _, st in ipairs(VERSE.STATIONS) do
        if st.cs == cs then
            return _SLOT_BY_TMPL[st.tmpl] or JOBS.config.station_slots
        end
    end
    return JOBS.config.station_slots
end

-- The context a job type's prepareOpts(ctx) gets for a station: where the station is, the
-- distance band, and a shuffled supply of other friendly stations (nextCandidate). ctx.tier is
-- set by the caller per slot.
function JOBS.offerContext(cs)
    local station_e = RT.find(cs)
    local dmin, dmax = JOBS.getDistanceRange()
    local candidates = {}
    for _, d in ipairs(VERSE.STATIONS) do
        if d.cs ~= cs and d.fac ~= "Corsairs" and d.fac ~= "Hollow" then
            candidates[#candidates + 1] = d.cs
        end
    end
    for i = #candidates, 2, -1 do
        local j = math.random(i); candidates[i], candidates[j] = candidates[j], candidates[i]
    end
    local cand_idx = 1

    local ctx = {
        station_cs     = cs,
        station_e      = station_e,
        tier           = 0,               -- re-set per slot below
        distanceRange  = {min=dmin, max=dmax},
        nextCandidate  = function()
            if cand_idx > #candidates then return nil end
            local c = candidates[cand_idx]; cand_idx = cand_idx + 1; return c
        end,
        spawnInVerse   = function(rx, ry) return JOBS.spawnInVerse(rx, ry) end,
        nearbyStations = function(wx, wy, r) return JOBS.nearbyStations(wx, wy, r) end,
        findStation    = RT.find,
        valid          = RT.valid,
    }
    return ctx
end

-- ── The board ─────────────────────────────────────────────────────────────────
-- Two halves, so the board can be reasoned about (and tested) without a comms window:
--   JOBS.board(cs, ship)   decides what station `cs` offers `ship` right now. No comms calls.
--   _showBoard(cs, ship)   renders that to the comms window and wires the "Take:" replies.
-- JOBS.board is built from the small steps below, in the order they run.

-- Two jobs with the same summary (type + short text) must not both be offered.
local function _key(m) return tostring(m.type) .. "|" .. tostring(m.short) end

local function _hasId(list, m)
    for _, o in ipairs(list) do if o.id == m.id then return true end end
    return false
end

local function _hasKey(list, m)
    local k = _key(m)
    for _, o in ipairs(list) do if _key(o) == k then return true end end
    return false
end

-- The station's slot table (created on first use): {slots = {{mission, offered_at, taken_at}, ...}}.
local function _stationState(cs, n_slots)
    if not JOBS._station_work[cs] then
        local slots = {}
        for i = 1, n_slots do slots[i] = {mission=nil, offered_at=0, taken_at=nil} end
        JOBS._station_work[cs] = {slots=slots}
    end
    return JOBS._station_work[cs]
end

-- Put a job in a slot. With the work cooldown off nothing is cached: the board is rebuilt on
-- every visit.
local function _setSlot(ss, sn, m, now)
    if not JOBS.config.work_cooldown_enabled then return end
    ss.slots[sn].mission    = m
    ss.slots[sn].offered_at = now
    ss.slots[sn].taken_at   = nil
end

-- Step 1, the reputation gate: how many offers the station will show this ship, and what it
-- says about it. Judged by the asking ship's own standing with the station's faction.
local function _repGate(cs, ship, n_slots)
    local se   = RT.find(cs)
    local sfac = RT.valid(se) and se:getFaction() or nil
    local rep  = sfac and RT.getReputation(sfac, ship) or 0
    if rep < -400 then
        return 0, '"We\'ve got nothing for someone with your reputation. Come back when you\'ve earned some trust."'
    elseif rep < -200 then
        return math.max(0, n_slots - 2), '"If you were more trustworthy, I\'d have more work for you."'
    elseif rep < 0 then
        return math.max(0, n_slots - 1), '"If you were more trustworthy, I\'d have more work for you."'
    end
    return n_slots, nil
end

-- How long a taken slot stays empty (JOBS.config.refill_secs, else the work cooldown).
local function _refillSecs()
    return JOBS.config.refill_secs or JOBS.config.work_cooldown_secs
end

-- Step 2, the per-slot cooldown: which slots get a new job now. A taken slot stays empty for
-- the refill time (_refillSecs); an untaken offer is replaced after the work cooldown.
local function _slotsDue(ss, n_slots, now)
    local due = {}
    if not JOBS.config.work_cooldown_enabled then
        for i = 1, n_slots do due[i] = i end
        return due
    end
    for sn = 1, n_slots do
        local slot = ss.slots[sn]
        if slot.taken_at then
            if now - slot.taken_at >= _refillSecs() then
                slot.taken_at = nil
                due[#due + 1] = sn
            end
        elseif slot.mission then
            if now - slot.offered_at >= JOBS.config.work_cooldown_secs then due[#due + 1] = sn end
        else
            due[#due + 1] = sn
        end
    end
    return due
end

-- Step 3: the offers still standing in the slots from an earlier visit.
local function _cachedOffers(ss, n_slots)
    local offers = {}
    for sn = 1, n_slots do
        local slot = ss.slots[sn]
        if slot.mission and not slot.taken_at and not _hasId(offers, slot.mission) then
            offers[#offers + 1] = slot.mission
        end
    end
    return offers
end

-- Step 4, ensured seeds (inject{ensure = true}) must be on the board: each takes a slot that is
-- due, otherwise replaces a cached ordinary job. They carry no special tag, so they read as
-- regular work that happened to be there.
local function _placeEnsured(ss, n_slots, due, offers, seeds, now)
    for _, sm in ipairs(seeds) do
        if sm._ensure and not _hasId(offers, sm) then
            local sn = table.remove(due, 1)
            if not sn then
                for i = 1, n_slots do
                    local sl = ss.slots[i]
                    if sl.mission and not sl.taken_at and not sl.mission._ensure then
                        for k, o in ipairs(offers) do
                            if o.id == sl.mission.id then table.remove(offers, k); break end
                        end
                        sn = i; break
                    end
                end
            end
            if sn then
                _setSlot(ss, sn, sm, now)
                table.insert(offers, 1, sm)
            end
        end
    end
end

-- Step 5, one new job for a slot: an injected seed (JOBS.SEED_CHANCE), else a generated job of
-- a random type, re-rolled a few times when its summary is already on the board (same cargo
-- and destination, same salvage cargo, ...). Returns the job, or nil when nothing came of it
-- (`failed` = the generator could not make one; nil without it = only duplicates came up).
local function _newJob(ctx, ship, seeds, offers, story)
    if #seeds > 0 and math.random() < JOBS.SEED_CHANCE then
        for _, sm in ipairs(seeds) do
            if not _hasId(offers, sm) then return sm end
        end
    end
    local mt = JOBS.maxTier(ship)
    for _ = 1, 4 do
        ctx.tier = math.min(mt, math.random(0, 1))
        local mtype = JOBS.pickType(ship)
        local mod   = JOBS._registry[mtype]
        if not mod then return nil end
        local opts = mod.prepareOpts(ctx)
        if not opts then return nil, true end
        local ok, result = pcall(mod.generate, opts)
        if not (ok and result) then
            log("[JOBS] " .. mtype .. " generate failed: " .. tostring(result))
            return nil, true
        end
        if not _hasKey(offers, result) and not _hasKey(story, result) then return result end
        -- duplicate summary: roll again
    end
    return nil
end

-- What station `cs` offers `ship` right now. Updates the station's slots (so the same jobs are
-- there on the next visit) but touches nothing else and makes no comms calls. Returns:
--   offers        the jobs to list, in display order
--   nag           the station's remark about the ship's standing, or nil
--   closed        true when that standing gets the ship no offers at all
--   slots_failed  slots the generator could not fill this time
--   wait          seconds until the next taken slot refills (nil: nothing is cooling down)
function JOBS.board(cs, ship)
    ship = RT.playerShip(ship) or RT.player
    local now     = getScenarioTime()
    local n_slots = JOBS.stationSlots(cs)
    local ss      = _stationState(cs, n_slots)

    local n_offer, nag = _repGate(cs, ship, n_slots)
    local due    = _slotsDue(ss, n_slots, now)
    local offers = _cachedOffers(ss, n_slots)
    -- Everything an arc injects (story contracts and seeds alike) is for the primary ship only:
    -- story arcs belong to that ship. Story contracts do not use up the station's slots. A seed
    -- already sitting in a slot stays there for the primary ship and is hidden from the others.
    local primary = (ship == RT.player)
    local story  = JOBS._injectedFor(cs, true, primary, ship)
    local seeds  = JOBS._injectedFor(cs, false, primary, ship)

    _placeEnsured(ss, n_slots, due, offers, seeds, now)
    for i = #offers, 1, -1 do
        if not JOBS._openTo(offers[i], ship) then table.remove(offers, i) end
    end

    local ctx, slots_failed = JOBS.offerContext(cs), 0
    for _, sn in ipairs(due) do
        local m, failed = _newJob(ctx, ship, seeds, offers, story)
        if m then
            _setSlot(ss, sn, m, now)
            offers[#offers + 1] = m
        elseif failed then
            slots_failed = slots_failed + 1
        end
    end

    -- The reputation cap on displayed offers; story contracts go on top of what is left.
    while #offers > n_offer do table.remove(offers) end
    if n_offer > 0 then
        for i = #story, 1, -1 do table.insert(offers, 1, story[i]) end
    end
    -- Final de-duplication by summary (cached slots / injected seeds can still collide).
    -- Earlier entries win, so story and ensured jobs are kept over generated ones.
    local seen, uniq = {}, {}
    for _, m in ipairs(offers) do
        local k = _key(m)
        if not seen[k] then seen[k] = true; uniq[#uniq + 1] = m end
    end
    offers = uniq
    -- Present in random order so arc-injected jobs are not always the first ones listed.
    for i = #offers, 2, -1 do
        local j = math.random(i)
        offers[i], offers[j] = offers[j], offers[i]
    end

    local wait
    if JOBS.config.work_cooldown_enabled then
        for _, slot in pairs(ss.slots) do
            if slot.taken_at then
                local r = _refillSecs() - (now - slot.taken_at)
                if r > 0 and (wait == nil or r < wait) then wait = r end
            end
        end
    end
    return {offers = offers, nag = nag, closed = (n_offer == 0), slots_failed = slots_failed, wait = wait}
end

-- One line of the listing for a job.
local function _offerLine(m)
    local mod     = JOBS._registry[m.type]
    local dist_u  = math.floor((m.distance_u or 0) / 1000 + 0.5)
    local stats   = string.format("%dU · %dcr · %d min", dist_u, m.reward, JOBS.timeLimit(m) // 60)
    if m.story and not m.time_limit then
        stats = string.format("%dU · %dcr · no time limit", dist_u, m.reward)
    end
    local txt = mod and mod.offerText(m, stats) or ("* " .. m.short .. "\n  " .. stats)
    if m.special then txt = txt:gsub("^%* ", "* [SPECIAL] ", 1) end
    return txt
end

-- "Check back ..." for a board with nothing on offer yet: a rough time, never minutes and
-- seconds (over 5 min: "in a while"; over 2 min: "in a few"; less: "in a bit").
function JOBS.checkBackText(wait)
    local when = (wait > 300 and "in a while") or (wait > 120 and "in a few") or "in a bit"
    return '"No new contracts right now. Check back ' .. when .. '."'
end

-- Render JOBS.board(cs, ship) in the open comms window.
local function _showBoard(cs, ship)
    local b = JOBS.board(cs, ship)
    local back = function(s2, t2) RT.stationComms(s2, t2) end

    if #b.offers == 0 then
        if b.nag and b.closed then
            setCommsMessage(b.nag)
        elseif b.wait then
            setCommsMessage(JOBS.checkBackText(b.wait))
        else
            setCommsMessage('"Nothing going out from here right now."')
        end
        addCommsReply("Back", back)
        return
    end

    local lines = {"Work out of " .. cs .. ":"}
    for _, m in ipairs(b.offers) do lines[#lines + 1] = _offerLine(m) end
    if b.slots_failed > 0 then
        local noun = b.slots_failed == 1 and "contract was" or "contracts were"
        lines[#lines + 1] = string.format("\n(%d %s just picked up by another crew.)", b.slots_failed, noun)
    end
    if b.nag then lines[#lines + 1] = "\n" .. b.nag end
    setCommsMessage(table.concat(lines, "\n"))

    for _, m in ipairs(b.offers) do
        local cap = m
        addCommsReply("Take: " .. cap.short, function(s2, t2)
            local taker = RT.playerShip(s2) or s2
            if JOBS._done[cap.id] then
                setCommsMessage('"Sorry. Another crew just took that one."')
            elseif #JOBS.activeFor(taker) >= JOBS.config.max_active and not cap.story then
                setCommsMessage('"You look pretty busy. I think I\'ll save my work for someone that gets stuff done."')
            else
                JOBS.accept(cap, false, taker)   -- logs the contract line to the taker
                local outro = (cap.type == "delivery") and "" or "\n\n\"Come back when it\'s done.\""
                setCommsMessage(cap.brief .. outro .. "\n\nTransmitting details to your log.")
            end
            addCommsReply("Back", back)
        end)
    end
    addCommsReply("Nothing for me", back)
end

function JOBS.stationHook(source, target)
    if not RT.isPlayer(source) then return end
    if not source:isDocked(target) then return end
    local cs = target:getCallSign()
    if not RT.flag("visited_" .. cs) then RT.flag("visited_" .. cs, true) end

    -- Completion replies for this ship's own jobs due here.
    for _, entry in ipairs(JOBS._active) do
        if entry.phase == "active" and entry.ship == source then
            local m   = entry.mission
            local mod = JOBS._registry[m.type]
            if mod and mod.completable and mod.completable(m, cs) then
                local ent = entry
                local rep = mod.completeReply(m, ent)
                addCommsReply(rep.label, function(s, t)
                    JOBS.complete(ent, s)
                    setCommsMessage(rep.msg .. string.format("\n\n%d credits transferred.", ent.mission.reward))
                    addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
                end)
            end
        end
    end

    if JOBS.config.jobboard_locked then return end

    addCommsReply("Any work available?", function(s, t)
        local ok, err = pcall(_showBoard, cs, RT.playerShip(s) or s)
        if not ok then
            log("[JOBS] offer error at " .. cs .. ": " .. tostring(err))
            setCommsMessage('"System error. Please report to the dockmaster."')
            addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
        end
    end)
end

-- Kept so scenarios can call it before wiring station hooks; the engine needs no set-up.
function JOBS.init() end
