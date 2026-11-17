-- ee/ragtag/director.lua
-- Scenario side of the AI director bridge.
--
-- EmptyEpsilon scenario Lua cannot open network connections, and the HTTP
-- API's /exec.lua runs in a *separate* Lua environment from the scenario. Both
-- environments do share the process-wide ScriptStorage, so we use two keys as
-- a mailbox. Each key has exactly one writer:
--
--   "rt.from_scenario"  written here, read by the director over HTTP
--       {proto, run, seq, events=[...], cmd_ack, results=[...], state={...}}
--   "rt.from_director"  written by the director over HTTP, read here
--       {proto, run, hb, event_ack, paused, cmds=[{id, action, args, source}]}
--
-- This file is ONLY that mailbox. The game does not call into it: core, jobs, world
-- plugins and arcs report what happens with RT.emit (core/events.lua) and this file
-- listens (RT.on), queues the events and ships them out with a state snapshot. Take
-- the require away and the campaign plays exactly the same.
--
-- The director is observation-only. It only ever asks for *named, whitelisted
-- actions* and never sends raw Lua; every action validates and clamps its arguments
-- here. What the model itself may ask for cannot touch the game (a private note to
-- the GM, or nothing); anything the crew can see or that changes the campaign is
-- GM-only and refused unless the GM sent it from the console (see director/actions/).

-- EE's built-in toJSON fails with "invalid key to 'next'" whenever a table
-- has two or more values that are themselves non-empty tables.  Root cause:
-- a relative Lua C stack index in EE's toJSON becomes stale after recursing
-- into the first nested table, so the outer next() call gets the wrong table.
-- We use this minimal encoder for the mailbox write only; RT.saveCampaign()
-- and other callers that only nest empty tables are fine with EE's toJSON.
local function _json(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        return (math.floor(v) == v) and string.format("%d", v) or string.format("%.10g", v)
    elseif t == "string" then
        return '"' .. v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')
                       :gsub('\r','\\r'):gsub('\t','\\t')
                       :gsub('[\x00-\x1f]', function(c)
                           return string.format('\\u%04x', c:byte()) end) .. '"'
    elseif t == "table" then
        if depth > 30 then return '"<overflow>"' end
        local n = #v
        -- Array: consecutive integer keys starting at 1 with no gaps.
        if n > 0 then
            local parts = {}
            for i = 1, n do parts[i] = _json(v[i], depth+1) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        -- Object: string keys.
        local parts = {}
        for k, val in pairs(v) do
            if type(k) == "string" then
                table.insert(parts, '"'..k:gsub('\\','\\\\'):gsub('"','\\"')..'":'
                                    .._json(val, depth+1))
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else return "null" end  -- userdata, function, thread
end

DIR = DIR or {}
DIR.PROTO = 1
DIR.KEY_OUT = "rt.from_scenario"
DIR.KEY_IN = "rt.from_director"

DIR.enabled = true
DIR.run = nil
DIR.seq = 0
DIR.events = {}               -- unacknowledged outgoing events
DIR.next_event_id = 1
DIR.last_cmd_id = 0
DIR.results = {}              -- last few action results, reported back
DIR.dirty = true
DIR.last_write = -100
DIR.last_pump = -100
DIR.pump_interval = 1.0
DIR.state_interval = 3.0
DIR.last_hb = nil
DIR.last_hb_time = -1000
DIR.online = false
DIR.session = {}              -- id, title, premise, cast, tone: sent with session_start
DIR.pending_hails = {}        -- GM "say" hails waiting for the player's comms to be free
DIR.last_tick = 0

-- Tunables a scenario may override after require().
DIR.config = {
    tick_minutes = 4,             -- periodic "tick" event, so a quiet stretch still gets a summary
}

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

-- session: {id="s1", title=..., premise=..., cast={{name=..., role=..., voice=...}}, tone=...}
function DIR.init(session)
    DIR.session = session or {}
    DIR.run = string.format("%s-%d-%d", DIR.session.id or "run", math.floor(random(0, 999999)), math.floor(random(0, 999999)))
    -- Build fresh copies of campaign sub-tables so the encoder never sees the same
    -- table object twice (shared refs across events+state).
    local camp_snap = nil
    if RT and RT.campaign then
        local c = RT.campaign
        local upg, flg, nts = {}, {}, {}
        for i, v in ipairs(c.upgrades or {}) do upg[i] = v end
        for k, v in pairs(c.flags or {}) do flg[k] = v end
        for i, v in ipairs(c.notes or {}) do nts[i] = v end
        camp_snap = {credits = c.credits, upgrades = upg, flags = flg, notes = nts, ship = c.ship_name}
    end
    -- Only include scalar session fields in the event — complex nested tables
    -- (cast, locations, director_guidance) are included in every state snapshot.
    local sess = DIR.session
    local sess_id = sess and {
        id = sess.id or "?", campaign = sess.campaign or "?", title = sess.title or "?"
    } or {}
    RT.emit("session_start", {session = sess_id, campaign = camp_snap}, "high")
end

--------------------------------------------------------------------------------
-- Events: everything the game reports with RT.emit is queued for the director.
--------------------------------------------------------------------------------

function DIR.queue(ev)
    if not DIR.enabled then return end
    table.insert(DIR.events, {id = DIR.next_event_id, t = ev.t, type = ev.type, data = ev.data, pri = ev.pri})
    DIR.next_event_id = DIR.next_event_id + 1
    -- Keep the queue bounded if the director is offline: drop oldest low/normal.
    while #DIR.events > 60 do
        local dropped = false
        for i, e in ipairs(DIR.events) do
            if e.pri ~= "high" then table.remove(DIR.events, i); dropped = true; break end
        end
        if not dropped then table.remove(DIR.events, 1) end
    end
    DIR.dirty = true
end

if not DIR._listening then
    DIR._listening = true
    RT.on(function(ev) DIR.queue(ev) end)
end

--------------------------------------------------------------------------------
-- State snapshot sent to the director
--------------------------------------------------------------------------------

local function round(v) return math.floor(v + 0.5) end

function DIR.buildState()
    -- Build a full session snapshot using only fresh tables so the encoder never
    -- encounters the same table object twice across events + state.
    local sess = DIR.session or {}
    local cast_copy = {}
    for i, m in ipairs(sess.cast or {}) do
        cast_copy[i] = {name = m.name or "", where = m.where or "", role = m.role or "", voice = m.voice or ""}
    end
    local loc_copy = {}
    for i, l in ipairs(sess.locations or {}) do
        loc_copy[i] = {name = l.name or "", note = l.note or ""}
    end
    local sess_snap = {
        id = sess.id or "?", campaign = sess.campaign or "?",
        title = sess.title or "?", run = DIR.run,
        premise = sess.premise or "", tone = sess.tone or "",
        cast = cast_copy, locations = loc_copy,
        director_guidance = sess.director_guidance or "",
    }
    local function b01(v) return v and 1 or 0 end
    local st = {
        session = sess_snap,
        time = round(getScenarioTime()),
        objective = RT.objective or "",
        beats = {},
    }
    local list = {}
    for id, b in pairs(RT.beats) do table.insert(list, {id = id, b = b}) end
    table.sort(list, function(a, c) return a.b.order < c.b.order end)
    for _, item in ipairs(list) do
        table.insert(st.beats, {id = item.id, desc = item.b.desc, fired = b01(item.b.fired)})
    end

    -- Per-ship snapshots. st.player = the primary ship (what the director's prompt reads).
    st.players = {}
    for _, p in ipairs(RT.players or {}) do
        if RT.valid(p) then
            local x, y = p:getPosition()
            local docked = p:getDockedWith()
            local damaged = {}
            for name, sys in pairs({reactor = "reactor", beams = "beamweapons", missiles = "missilesystem",
                                    maneuver = "maneuver", impulse = "impulse", warp = "warp",
                                    frontshield = "frontshield", rearshield = "rearshield"}) do
                if p:hasSystem(sys) then
                    local h = p:getSystemHealth(sys)
                    if h < 0.8 then damaged[name] = round(h * 100) end
                end
            end
            local snap = {
                callsign = p:getCallSign(), sector = p:getSectorName(),
                x = round(x), y = round(y), heading = round(p:getHeading()),
                hull = round(p:getHull()), hull_max = round(p:getHullMax()),
                shields_up = b01(p:getShieldsActive()), credits = RT.credits(p),   -- this ship's own balance
                docked_with = (docked and RT.valid(docked)) and docked:getCallSign() or nil,
                damaged_systems = damaged,
                homing = p:getWeaponStorage("Homing"), hvli = p:getWeaponStorage("HVLI"),
            }
            -- Nearby contacts — only for the first (primary) player to keep state small.
            if #st.players == 0 then
                local nearby = {}
                for _, obj in ipairs(getObjectsInRadius(x, y, 30000)) do
                    if obj ~= p and obj.components ~= nil and obj.components.typename ~= nil then
                        local ok, info = pcall(function()
                            return {
                                callsign = obj:getCallSign(), type = obj:getTypeName(), faction = obj:getFaction(),
                                dist_u = round(RT.dist(p, obj) / 100) / 10,
                                hostile = b01(obj:isEnemy(p)),
                            }
                        end)
                        if ok then table.insert(nearby, info) end
                    end
                    if #nearby >= 16 then break end
                end
                table.sort(nearby, function(a, b) return a.dist_u < b.dist_u end)
                snap.nearby = nearby
            end
            table.insert(st.players, snap)
        end
    end
    st.player = st.players[1] or {destroyed = true}

    st.extra = RT.extraState()
    if RT.campaign then
        local c = RT.campaign
        local upg, flg = {}, {}
        for i, v in ipairs(c.upgrades or {}) do upg[i] = v end
        for k, v in pairs(c.flags or {}) do flg[k] = v end
        local sess_count = 0
        if type(c.sessions) == "table" then
            for _ in pairs(c.sessions) do sess_count = sess_count + 1 end
        end
        st.campaign = {
            credits = c.credits, ship = c.ship_name,
            upgrades = upg, flags = flg, sessions_count = sess_count,
        }
    end
    return st
end

--------------------------------------------------------------------------------
-- Mailbox pump. Call DIR.update(delta) from the scenario's update().
--------------------------------------------------------------------------------

function DIR.update(delta)
    if not DIR.enabled or DIR.run == nil then return end
    local now = getScenarioTime()

    DIR.processPendingHails(now)

    -- Periodic tick, so a quiet stretch still prompts a summary.
    if now - DIR.last_tick >= DIR.config.tick_minutes * 60 then
        DIR.last_tick = now
        RT.emit("tick", {minutes = math.floor(now / 60)}, "low")
    end

    if now - DIR.last_pump < DIR.pump_interval then return end
    DIR.last_pump = now

    local storage = getScriptStorage()

    -- 1. Read what the director sent.
    local raw = storage:get(DIR.KEY_IN)
    if type(raw) == "string" and raw ~= "" then
        local ok, msg = pcall(fromJSON, raw)
        if ok and type(msg) == "table" and msg.run == DIR.run then
            if msg.hb ~= DIR.last_hb then
                DIR.last_hb = msg.hb
                DIR.last_hb_time = now
            end
            local ack = tonumber(msg.event_ack) or 0
            for i = #DIR.events, 1, -1 do
                if DIR.events[i].id <= ack then table.remove(DIR.events, i); DIR.dirty = true end
            end
            if type(msg.cmds) == "table" then
                for _, cmd in ipairs(msg.cmds) do
                    local cid = tonumber(cmd.id) or 0
                    if cid > DIR.last_cmd_id then
                        DIR.last_cmd_id = cid
                        DIR.execute(cmd)
                        DIR.dirty = true
                    end
                end
            end
        end
    end

    local was_online = DIR.online
    DIR.online = (now - DIR.last_hb_time) < 20
    if was_online ~= DIR.online then
        addGMMessage(DIR.online and "AI director connected." or "AI director offline - scenario continues on its own.")
        DIR.dirty = true
    end

    -- 2. Write our side when something changed, or periodically for fresh state.
    if DIR.dirty or now - DIR.last_write >= DIR.state_interval then
        DIR.seq = DIR.seq + 1
        local state_ok, state_val = pcall(DIR.buildState)
        if not state_ok then
            log("[DIR] buildState failed: " .. tostring(state_val))
            state_val = {}
        end
        local out = {
            proto = DIR.PROTO, run = DIR.run, seq = DIR.seq,
            events = DIR.events, cmd_ack = DIR.last_cmd_id, results = DIR.results,
            state = state_val,
        }
        -- Our own serialiser: see _json above.
        storage:set(DIR.KEY_OUT, _json(out))
        DIR.dirty = false
        DIR.last_write = now
    end
end

--------------------------------------------------------------------------------
-- Command execution
--------------------------------------------------------------------------------

function DIR.execute(cmd)
    local action = tostring(cmd.action or "")
    local args = type(cmd.args) == "table" and cmd.args or {}
    local handler = DIR.ACTIONS[action]
    local ok, msg
    if handler == nil then
        ok, msg = false, "unknown action"
    else
        local success, r1, r2 = pcall(handler, args, cmd)
        if not success then
            ok, msg = false, "error: " .. tostring(r1)
            log("[DIR] action " .. action .. " crashed: " .. tostring(r1))
        else
            ok, msg = r1, r2
        end
    end
    table.insert(DIR.results, {id = cmd.id, action = action, ok = ok and true or false, msg = tostring(msg or "")})
    while #DIR.results > 12 do table.remove(DIR.results, 1) end
end

local function str(v, max_len, default)
    if v == nil then return default end
    return RT.cleanText(v, max_len or 200)
end

local function num(v, lo, hi, default)
    local n = tonumber(v)
    if n == nil then return default end
    if n < lo then n = lo end
    if n > hi then n = hi end
    return n
end

-- Shared helpers for action files loaded from director/actions/*.lua.
DIR._h = {
    str = str,
    num = num,
    -- True when the GM sent the command from the console. Every action with an effect in the
    -- game starts with:  if not DIR._h.fromGM(cmd) then return false, "GM only" end
    fromGM = function(cmd) return type(cmd) == "table" and cmd.source == "gm" end,
}

--------------------------------------------------------------------------------
-- Action whitelist. Each returns ok(bool), message(string).
-- Actions are loaded from ee/ragtag/director/actions/index.lua (generated).
-- To add a new action: create a .lua file in that directory and run check.py --fix.
-- Keep any new action in sync with director/actions.py (Python validation layer).
--------------------------------------------------------------------------------

DIR.ACTIONS = {}

-- Hails queued by the GM's "say" while the crew's comms were busy.
function DIR.processPendingHails(now)
    for i = #DIR.pending_hails, 1, -1 do
        local h = DIR.pending_hails[i]
        local ent = RT.find(h.speaker)
        -- Remove expired or orphaned hails.
        if not RT.valid(ent) or not RT.anyPlayerAlive() or now > h.until_t then
            table.remove(DIR.pending_hails, i)
            -- Deliver as ship-log fallback to all alive ships.
            RT.shipLog("[" .. h.speaker .. "] " .. h.text, "#C0E0FF")
        else
            -- Try to open comms to the primary ship; fall back to log on the rest.
            local delivered = false
            if RT.valid(RT.player) and ent:sendCommsMessage(RT.player, h.text) then
                delivered = true
            end
            if delivered then
                -- Secondary ships get a log copy so no one misses the hail.
                for i2 = 2, #RT.players do
                    if RT.valid(RT.players[i2]) then
                        RT.players[i2]:addToShipLog("[" .. h.speaker .. "] " .. h.text, "#C0E0FF")
                    end
                end
                table.remove(DIR.pending_hails, i)
            end
        end
    end
end

require("ragtag/director/actions/index.lua")
