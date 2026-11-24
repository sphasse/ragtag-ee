-- ee/ragtag/missions/_helpers.lua
-- ARC: helpers shared by the story arcs in this folder. Part of the missions layer: loaded by
-- ee/ragtag/missions.lua after the engine, used only by arc modules. Core (RT), the job board and
-- world plugins do not know about it, and nothing here belongs in core.lua.
--
-- Before writing a local helper in an arc, look here. If two arcs need the same thing, it goes
-- here, not in both. Reference: missions_api.md, "Arc helpers (ARC)".

ARC = ARC or {}

-- ── Players and distance ─────────────────────────────────────────────────────

-- Story arcs belong to ONE ship: the campaign's primary ship (the Magpie, RT.players[1]). Other
-- player ships in the game can work the job board, but arcs do not react to them: they are not
-- offered arc dialogs, do not trip arc triggers, and do not get arc logs, hails or effects.
-- Arc code therefore never loops over RT.players (check.py rejects RT.players, RT.forEachPlayer,
-- RT.shipLog and RT.hail in an arc); it uses the helpers below.

-- The arc ship, or nil while it is destroyed (arcs then wait; no other ship takes over).
function ARC.player()
    local p = RT.players and RT.players[1]
    if RT.valid(p) then return p end
end

-- Register an arc's ship by name (RT.register) without the kill penalty: a fight the story sets
-- up settles its own consequences (Rezkov's Meridian, the Boneyard battle, ...).
function ARC.register(ship, callsign)
    RT.register(ship, callsign)
    RT.cancelKillTracking(ship)
    return ship
end

-- Run fn(ship) on the arc ship when it is alive (instead of RT.forEachPlayer).
function ARC.withPlayer(fn)
    local p = ARC.player()
    if p then return fn(p) end
end

function ARC.isArcShip(ship)
    return ship ~= nil and ship == ARC.player()
end

-- Ship log line on the arc ship only (RT.shipLog writes to every player ship).
function ARC.log(msg, color)
    local p = ARC.player()
    if p then p:addToShipLog(msg, color or "#FFFFFF") end
end

-- Hail the arc ship only. Returns true when the crew got the text, false when it did not (comms
-- busy, or no arc ship): the caller then retries or falls back to ARC.log. With no valid sender
-- the line goes straight to the arc ship's log under `speaker`.
function ARC.hail(from, text, speaker)
    local p = ARC.player()
    if not p then return false end
    if RT.valid(from) then
        return from:sendCommsMessage(p, text) and true or false
    end
    p:addToShipLog("[" .. (speaker or "Unknown") .. "] " .. text, "#C0E0FF")
    return true
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

-- ANY player ship within r of the point (the arc ship or a sister ship), else nil. Only for
-- physical events in the world that any ship can set off (a frozen battle starting), never for
-- story progress, which belongs to the arc ship.
function ARC.anyPlayerNear(x, y, r)
    for _, p in ipairs(RT.players or {}) do
        if ARC.near(p, x, y, r) then return p end
    end
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

-- Wrap a comms function so only the arc ship gets the dialog; any other ship gets `other`
-- (default: no answer). Use it for every arc comms function that offers a choice or changes
-- arc state:
--     ship:setCommsFunction(ARC.comms(function(src, tgt) ... end))
function ARC.comms(fn, other)
    return function(src, tgt)
        if not ARC.isArcShip(src) then
            setCommsMessage(other or "No response on this channel.")
            return
        end
        return fn(src, tgt)
    end
end

-- For dialogs that only happen docked. Returns true when src is the arc ship and is docked at
-- tgt; otherwise sets `message` (when given) as the comms text and returns false:
--     if not ARC.docked(src, tgt, '"Dock. We do not do business at a distance."') then return end
function ARC.docked(src, tgt, message)
    if ARC.isArcShip(src) and RT.valid(tgt) and src:isDocked(tgt) then return true end
    if message then setCommsMessage(message) end
    return false
end

-- Register a station hook once per session, however often the arc's init phase runs (a GM
-- restart re-enters it). Keyed by callsign and function. The hook only runs for the arc ship:
-- other ships get the station's ordinary menu.
local _hooked = {}
function ARC.stationHook(callsign, fn)
    _hooked[callsign] = _hooked[callsign] or {}
    if _hooked[callsign][fn] then return end
    _hooked[callsign][fn] = true
    RT.addStationHook(callsign, function(src, ...)
        if ARC.isArcShip(src) then return fn(src, ...) end
    end)
end

-- First meeting with a Science DB profile: sets "<arc>_met_<who>" (SCIDB.meet) and adds the
-- profile; SCIDB announces it in the ship log ("Database entry added: Lore > Thresh"). Returns true
-- the first time. `who` (the person's name) is kept for callers and readability. GM resets clear
-- the flag with the arc's other flags and SCIDB.sync removes the profile.
function ARC.meet(arc_id, profile_key, who)
    if not (SCIDB and SCIDB.meet) then return false end
    local ok, added = pcall(SCIDB.meet, arc_id, profile_key)
    return ok and added == true
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

-- GM travel shortcut for playtesting: put the arc ship `dist` (default 5U) from a place, on the side
-- it is coming from, undocked and stopped. `target` is a callsign, an entity, {x = , y = } in world
-- units, or a function returning one of those (evaluated when the button is pressed). Returns true
-- when the ship moved; tells the GM why not otherwise. ARC.lastShipTo keeps where it went (tests).
function ARC.shipTo(target, dist)
    dist = dist or 5000
    if type(target) == "function" then target = target() end
    local p = ARC.player()
    if not p then
        addGMMessage("No arc ship to move.")
        return false
    end
    local tx, ty
    if type(target) == "string" then
        local e = RT.find(target)
        if RT.valid(e) then tx, ty = e:getPosition() end
    elseif type(target) == "table" and target.x then
        tx, ty = target.x, target.y
    elseif target ~= nil and RT.valid(target) then
        tx, ty = target:getPosition()
    end
    if not tx then
        addGMMessage("Nothing to fly to right now (" .. tostring(target) .. ").")
        return false
    end
    local dp = p.components.docking_port
    if dp and dp.state ~= "not_docking" then pcall(function() p:commandUndock() end) end
    local px, py = p:getPosition()
    local dx, dy = px - tx, py - ty
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1 then dx, dy, d = 1, 0, 1 end
    p:setPosition(tx + dx / d * dist, ty + dy / d * dist)
    pcall(function() p:commandImpulse(0) end)
    pcall(function() p:commandWarp(0) end)
    ARC.lastShipTo = {x = tx, y = ty, dist = dist}
    return true
end

-- A GM helper button for M.gm_actions: "Ship → <label>" in the listed phases, moving the arc ship
-- 5U from `target` (see ARC.shipTo). Labels stay within the 18-character GM limit.
function ARC.travel(label, phases, target)
    return {label = "Ship → " .. label, phases = phases, travel = true,
            fn = function(st) ARC.shipTo(type(target) == "function" and function() return target(st) end or target) end}
end

-- Is the arc ship inside any of the named universe regions (VERSE.REGIONS)? For a chase that ends
-- when the ship is out of Concord space (Hob Works, Cold Chain).
function ARC.inRegions(names)
    local p = ARC.player()
    if not p then return false end
    local x, y = p:getPosition()
    local want = {}
    for _, n in ipairs(names) do want[n] = true end
    for _, r in ipairs(VERSE.REGIONS or {}) do
        if want[r.name] and ((x / 1000 - r.x) ^ 2 + (y / 1000 - r.y) ^ 2) <= r.r * r.r then return true end
    end
    return false
end

-- For M.gm_reset: empty the arc's state table and refill it from M.init_state(), in place (the
-- engine and closures keep their reference to the same table).
function ARC.resetState(M, st)
    for k in pairs(st) do st[k] = nil end
    for k, v in pairs(M.init_state and M.init_state() or {}) do st[k] = v end
    return st
end
