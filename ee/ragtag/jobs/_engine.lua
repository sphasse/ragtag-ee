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
    mission_distance_mode = "medium",   -- "short"|"medium"|"long"
    jobboard_locked       = false,       -- set true during Witness arc
    max_active            = 2,
    station_slots         = 2,
}

-- Internal state.
JOBS._registry     = {}   -- type_string → module table
JOBS._active       = {}   -- list of {mission, phase}
JOBS._done         = {}   -- mission id → true (taken or completed this session)
JOBS._station_work = {}   -- callsign → {slots = [...]}
JOBS._panel_next   = 0

-- Ship name pools used by boarding, destroy, and tailing modules.
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
function JOBS.corsairName()   return _CORSAIR_NAMES[math.random(#_CORSAIR_NAMES)]   end
function JOBS.freighterName() return _FREIGHTER_NAMES[math.random(#_FREIGHTER_NAMES)] end

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
end

-- ── Tier ──────────────────────────────────────────────────────────────────────
function JOBS.maxTier()
    if not RT.campaign then return 0 end
    local cost_map = {}
    for _, u in ipairs(RT.UPGRADES) do cost_map[u.id] = u.cost end
    local total = 0
    for _, id in ipairs(RT.campaign.upgrades or {}) do
        total = total + (cost_map[id] or 0)
    end
    if total >= 1000 then return 2 elseif total >= 500 then return 1 else return 0 end
end

-- ── Type selection ────────────────────────────────────────────────────────────
-- Weighted random draw from registered types whose tier_min <= maxTier().
function JOBS.pickType()
    local mt = JOBS.maxTier()
    local pool, total = {}, 0
    for _, mod in pairs(JOBS._registry) do
        if (mod.tier_min or 0) <= mt then
            pool[#pool + 1] = mod
            total = total + (mod.weight or 1)
        end
    end
    if #pool == 0 then return "delivery" end
    local r = math.random() * total
    for _, mod in ipairs(pool) do
        r = r - (mod.weight or 1)
        if r <= 0 then return mod.type end
    end
    return pool[#pool].type
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

-- ── Panel ─────────────────────────────────────────────────────────────────────
function JOBS.refreshPanel()
    RT.forEachPlayer(function(p)
        for slot = 1, 2 do
            local entry = JOBS._active[slot]
            local txt = (entry and entry.phase == "active")
                        and ("Job: " .. entry.mission.short)
                        or  ("Job " .. slot .. ": (none)")
            p:addCustomInfo("relay", "rt_job_" .. slot, txt, slot)
        end
    end)
end

function JOBS.updateObj()
    RT.setObjective("Explore the Drift", true)
    JOBS.refreshPanel()
end

-- ── Accept ────────────────────────────────────────────────────────────────────
function JOBS.accept(m, skip_log, ship)
    if #JOBS._active >= JOBS.config.max_active then return false end
    JOBS._done[m.id] = true
    for i, dm in ipairs(MISSION._dynamic_queue) do
        if dm.id == m.id then table.remove(MISSION._dynamic_queue, i); break end
    end

    local mod = JOBS._registry[m.type]
    m._time_limit = mod and mod.duration(m) or (20 * 60)
    m._expires_at = getScenarioTime() + m._time_limit

    local os_e = RT.find(m.origin)
    if RT.valid(os_e) then m.origin_faction = os_e:getFaction() end

    JOBS._active[#JOBS._active + 1] = {mission = m, phase = "active"}

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

    if not skip_log then
        local line = mod and mod.acceptLog and mod.acceptLog(m)
        if not line then
            local dest = m.dest or (m.wx and ("grid " .. MISSION.gridRef(m.wx, m.wy)) or "??")
            line = string.format("Contract: %s. %dm to complete. Head to %s.",
                m.short, math.floor(m._time_limit / 60), dest)
        end
        RT.shipLog(line, "#60CCFF")
    end
    return true
end

-- ── Complete ──────────────────────────────────────────────────────────────────
function JOBS.complete(entry, completing_ship)
    entry.phase = "done"
    for i, a in ipairs(JOBS._active) do
        if a == entry then table.remove(JOBS._active, i); break end
    end
    local mod = JOBS._registry[entry.mission.type]
    if mod and mod.cleanup then mod.cleanup(entry.mission) end
    MISSION.untrack(entry.mission.id)
    RT.addCredits(entry.mission.reward, "job: " .. entry.mission.short, completing_ship)

    local fac = entry.mission.origin_faction
    if not fac then
        local os_e = RT.find(entry.mission.origin)
        if RT.valid(os_e) then fac = os_e:getFaction() end
    end
    if fac then
        RT.addReputation(fac, entry.mission.reward, "completed: " .. entry.mission.short)
    end

    JOBS.updateObj()
    DIR.emit("job_complete", {type=entry.mission.type, tier=entry.mission.tier, reward=entry.mission.reward}, "low")
end

-- ── Update ────────────────────────────────────────────────────────────────────
function JOBS.update()
    if not RT.anyPlayerAlive() then return end
    local now = getScenarioTime()

    if now >= JOBS._panel_next then
        JOBS._panel_next = now + 15
        JOBS.refreshPanel()
    end

    local i = #JOBS._active
    while i >= 1 do
        local entry = JOBS._active[i]
        local m = entry.mission
        if entry.phase == "active" then
            if m._expires_at and now > m._expires_at then
                local mod = JOBS._registry[m.type]
                local handled = mod and mod.expire and mod.expire(m)
                if not handled then
                    RT.shipLog("[Contract] " .. m.short .. " -- time expired. Contract lost.", "#FF8080")
                    if m.origin_faction then
                        RT.addReputation(m.origin_faction, -2 * m.reward, "failed: " .. m.short)
                    end
                end
                if mod and mod.cleanup then mod.cleanup(m) end
                MISSION.untrack(m.id)
                table.remove(JOBS._active, i)
                JOBS.updateObj()
            else
                local mod = JOBS._registry[m.type]
                if mod and mod.update then
                    local result = mod.update(m, entry, {now=now, jobs=JOBS})
                    if result == "remove" then
                        MISSION.untrack(m.id)
                        table.remove(JOBS._active, i)
                        JOBS.updateObj()
                    end
                end
            end
        end
        i = i - 1
    end
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

local function _offerMissions(cs)
    local now     = getScenarioTime()
    local mt      = JOBS.maxTier()
    local n_slots = JOBS.stationSlots(cs)

    if not JOBS._station_work[cs] then
        local slots = {}
        for i = 1, n_slots do slots[i] = {mission=nil, offered_at=0, taken_at=nil} end
        JOBS._station_work[cs] = {slots=slots}
    end
    local ss = JOBS._station_work[cs]

    -- Per-slot cooldown: decide which slots need new generation.
    local slots_to_gen = {}
    if JOBS.config.work_cooldown_enabled then
        for sn = 1, n_slots do
            local slot = ss.slots[sn]
            if slot.taken_at then
                if now - slot.taken_at >= JOBS.config.work_cooldown_secs then
                    slot.taken_at = nil
                    slots_to_gen[#slots_to_gen + 1] = sn
                end
            elseif slot.mission then
                if now - slot.offered_at >= JOBS.config.work_cooldown_secs then
                    slots_to_gen[#slots_to_gen + 1] = sn
                end
            else
                slots_to_gen[#slots_to_gen + 1] = sn
            end
        end
    else
        for i = 1, n_slots do slots_to_gen[i] = i end
    end

    local offers = {}

    -- Director-pushed missions take priority.
    for _, m in ipairs(MISSION._dynamic_queue) do
        if m.origin == cs and not JOBS._done[m.id] then
            offers[#offers + 1] = m
        end
    end

    -- Cached valid slot missions.
    for sn = 1, n_slots do
        local slot = ss.slots[sn]
        if slot.mission and not slot.taken_at then
            local seen = false
            for _, o in ipairs(offers) do if o.id == slot.mission.id then seen=true; break end end
            if not seen then offers[#offers + 1] = slot.mission end
        end
    end

    -- Build context passed to prepareOpts.
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

    local slots_failed = 0
    for _, sn in ipairs(slots_to_gen) do
        ctx.tier = math.min(mt, math.random(0, 1))
        local mtype = JOBS.pickType()
        local mod   = JOBS._registry[mtype]
        if not mod then goto next_slot end

        local opts = mod.prepareOpts(ctx)
        if not opts then
            slots_failed = slots_failed + 1
            goto next_slot
        end

        local ok, result = pcall(mod.generate, opts)
        if ok and result then
            if JOBS.config.work_cooldown_enabled then
                ss.slots[sn].mission    = result
                ss.slots[sn].offered_at = now
                ss.slots[sn].taken_at   = nil
            end
            offers[#offers + 1] = result
        else
            print("[JOBS] " .. mtype .. " generate failed: " .. tostring(result))
            slots_failed = slots_failed + 1
        end
        ::next_slot::
    end

    if #offers == 0 then
        if JOBS.config.work_cooldown_enabled then
            local min_r = math.huge
            for _, slot in pairs(ss.slots) do
                if slot.taken_at then
                    local r = JOBS.config.work_cooldown_secs - (now - slot.taken_at)
                    if r > 0 and r < min_r then min_r = r end
                end
            end
            if min_r < math.huge then
                setCommsMessage(string.format('"No new contracts right now. Check back in %dm %ds."',
                    math.floor(min_r/60), math.ceil(min_r%60)))
            else
                setCommsMessage('"Nothing going out from here right now."')
            end
        else
            setCommsMessage('"Nothing going out from here right now."')
        end
        addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
        return
    end

    local lines = {"Work out of " .. cs .. ":"}
    for _, m in ipairs(offers) do
        local mod2 = JOBS._registry[m.type]
        local dist_u  = math.floor((m.distance_u or 0) / 1000 + 0.5)
        local dur_min = math.floor((mod2 and mod2.duration(m) or 1200) / 60)
        local stats   = string.format("%dU · %dcr · %d min", dist_u, m.reward, dur_min)
        lines[#lines + 1] = mod2 and mod2.offerText(m, stats) or ("● " .. m.short .. "\n  " .. stats)
    end
    if slots_failed > 0 then
        local noun = slots_failed == 1 and "contract was" or "contracts were"
        lines[#lines + 1] = string.format("\n(%d %s just picked up by another crew.)", slots_failed, noun)
    end
    setCommsMessage(table.concat(lines, "\n"))

    for _, m in ipairs(offers) do
        local cap = m
        addCommsReply("Take: " .. cap.short, function(s2, t2)
            if #JOBS._active >= JOBS.config.max_active then
                setCommsMessage('"You look pretty busy. I think I\'ll save my work for someone that gets stuff done."')
            else
                JOBS.accept(cap, true, s2)
                local mod3 = JOBS._registry[cap.type]
                local outro = (cap.type == "delivery") and "" or "\n\n\"Come back when it\'s done.\""
                setCommsMessage(cap.brief .. outro .. "\n\nTransmitting details to your log.")
                local log_line = mod3 and mod3.acceptLog and mod3.acceptLog(cap)
                if not log_line then
                    local dest = cap.dest or (cap.wx and ("grid " .. MISSION.gridRef(cap.wx, cap.wy)) or "??")
                    log_line = string.format("Contract: %s. %dm to complete. Head to %s.",
                        cap.short, math.floor(cap._time_limit / 60), dest)
                end
                RT.shipLog(log_line, "#60CCFF")
            end
            addCommsReply("Back", function(s3, t3) RT.stationComms(s3, t3) end)
        end)
    end
    addCommsReply("Nothing for me", function(s2, t2) RT.stationComms(s2, t2) end)
end

function JOBS.stationHook(source, target)
    if not RT.isPlayer(source) then return end
    if not source:isDocked(target) then return end
    local cs = target:getCallSign()

    -- Completion replies for active missions due here.
    for _, entry in ipairs(JOBS._active) do
        if entry.phase == "active" then
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
        local ok, err = pcall(_offerMissions, cs)
        if not ok then
            print("[JOBS] offer error at " .. cs .. ": " .. tostring(err))
            setCommsMessage('"System error. Please report to the dockmaster."')
            addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
        end
    end)
end

function JOBS.init() end
