-- ee/ragtag/missions/_helpers.lua
-- ARC: helpers shared by the story arcs in this folder. Part of the missions layer: loaded by
-- ee/ragtag/missions.lua after the engine, used only by arc modules. Core (RT), the job board and
-- world plugins do not know about it, and nothing here belongs in core.lua.
--
-- Before writing a local helper in an arc, look here. If two arcs need the same thing, it goes
-- here, not in both. Reference: missions_api.md, "Arc helpers (ARC)".

ARC = ARC or {}

-- ── Players and distance ─────────────────────────────────────────────────────

-- The ship an arc acts on: the first valid player ship (nil when none is alive).
function ARC.player()
    for _, p in ipairs(RT.players or {}) do
        if RT.valid(p) then return p end
    end
end

function ARC.dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- True when a valid entity is within r (world units) of the point.
function ARC.near(ent, x, y, r)
    if not RT.valid(ent) then return false end
    local ex, ey = ent:getPosition()
    local dx, dy = ex - x, ey - y
    return dx * dx + dy * dy < r * r
end

-- The arc's player ship when it is within r of the point, else nil.
function ARC.playerNear(x, y, r)
    local p = ARC.player()
    if p and ARC.near(p, x, y, r) then return p end
end

-- ── Spawned objects ──────────────────────────────────────────────────────────

-- The valid entities of a list, as a new list (order kept).
function ARC.alive(list)
    local out = {}
    for _, e in ipairs(list or {}) do
        if RT.valid(e) then out[#out + 1] = e end
    end
    return out
end

-- Remove one entity or every entity in a table (list or keyed), including ones made
-- indestructible. Invalid and nil entries are skipped. The table itself is not emptied:
--     ARC.kill(st.fleet); st.fleet = {}
function ARC.kill(what)
    if what == nil then return end
    local function one(e)
        if RT.valid(e) then
            pcall(function() e:setCanBeDestroyed(true) end)   -- not every entity type has it
            pcall(function() e:destroy() end)
        end
    end
    if type(what) == "table" then
        for _, e in pairs(what) do one(e) end
    else
        one(what)
    end
end

-- ── Dialogs ──────────────────────────────────────────────────────────────────

-- For dialogs that only happen docked. Returns true when src is docked at tgt; otherwise sets
-- `message` (when given) as the comms text and returns false:
--     if not ARC.docked(src, tgt, '"Dock. We do not do business at a distance."') then return end
function ARC.docked(src, tgt, message)
    if RT.valid(src) and RT.valid(tgt) and src:isDocked(tgt) then return true end
    if message then setCommsMessage(message) end
    return false
end

-- Register a station hook once per session, however often the arc's init phase runs (a GM
-- restart re-enters it). Keyed by callsign and function.
local _hooked = {}
function ARC.stationHook(callsign, fn)
    _hooked[callsign] = _hooked[callsign] or {}
    if _hooked[callsign][fn] then return end
    _hooked[callsign][fn] = true
    RT.addStationHook(callsign, fn)
end

-- First meeting with a Science DB profile: sets "<arc>_met_<who>" (SCIDB.meet), adds the profile
-- and tells the crew once. `who` is the name for the log line. GM resets clear the flag with the
-- arc's other flags and SCIDB.sync removes the profile.
function ARC.meet(arc_id, profile_key, who)
    if not (SCIDB and SCIDB.meet) then return false end
    local ok, added = pcall(SCIDB.meet, arc_id, profile_key)
    if ok and added then
        local M = MISSIONS._registry[arc_id]
        RT.shipLog("[" .. (M and M.name or arc_id) .. "] " .. who .. " personnel records added to our database.", "#80C0FF")
        return true
    end
    return false
end

-- ── Flags, rewards, routing ──────────────────────────────────────────────────

-- Run fn the first time only, remembered in a saved flag. For rewards in M.resolve, so a GM
-- jump between end states does not pay twice:
--     ARC.once("ledger_rewarded", function() RT.addCredits(600, "...") end)
function ARC.once(flag, fn)
    if RT.flag(flag) then return false end
    RT.flag(flag, true)
    fn()
    return true
end

-- Start-of-session routing for an arc's "init" phase: go to the phase of the first rule that
-- holds, else to `default`. A rule is {when, phase}; `when` is a flag name or a function.
-- List the furthest progress first:
--     ARC.route("ledger", {{"ledger_arc_done", "done"}, {"ledger_accepted", "relay_run"}}, "hook")
function ARC.route(arc_id, rules, default)
    for _, r in ipairs(rules) do
        local when = r[1]
        local hit
        if type(when) == "function" then hit = when() else hit = RT.flag(when) end
        if hit then MISSIONS.phase(arc_id, r[2]); return r[2] end
    end
    MISSIONS.phase(arc_id, default)
    return default
end

-- ── GM console ───────────────────────────────────────────────────────────────

-- Builder for GM "->" buttons:
--     local _jump = ARC.jumper("ledger")
--     M.gm_states = { {key = "hook", label = "→ Hook", fn = _jump("hook")}, ... }
-- _jump(phase, setup, opts) returns a function that calls MISSIONS.gmJump(id, phase, setup, opts).
function ARC.jumper(arc_id)
    return function(phase, setup, opts)
        return function() MISSIONS.gmJump(arc_id, phase, setup, opts) end
    end
end

-- For M.gm_reset: empty the arc's state table and refill it from M.init_state(), in place (the
-- engine and closures keep their reference to the same table).
function ARC.resetState(M, st)
    for k in pairs(st) do st[k] = nil end
    for k, v in pairs(M.init_state and M.init_state() or {}) do st[k] = v end
    return st
end
