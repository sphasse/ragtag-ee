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
-- The director only ever asks for *named, whitelisted actions*. It never sends
-- raw Lua. Every action validates and clamps its arguments here, so a confused
-- language model can't crash the game or flatten the crew.
--
-- The scenario must stay fully playable with the director offline: every beat
-- the AI may trigger should also have a deterministic fallback in the scenario.

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
DIR.paused = false            -- GM can hush the AI from the GM screen
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
DIR.beats = {}                -- id -> {desc, ai, fn, fired, order}
DIR.beat_order = 0
DIR.state_providers = {}      -- functions returning a table merged into state.extra
DIR.pending_hails = {}        -- hails waiting for the player's comms to be free
DIR.spawned = {}              -- entities created by the director
DIR.controllable = {}         -- callsign -> true, NPCs the director may give orders to
DIR.last_tick = 0
DIR.missions = {}            -- active director-created missions, keyed by id

-- Tunables a scenario may override after require().
DIR.config = {
    max_ai_hostiles = 6,          -- director-spawned hostiles alive at once
    spawn_cooldown = 90,          -- seconds between director spawn_group actions
    glitch_cooldown = 120,
    credit_cap_per_action = 300,
    credit_cap_per_session = 900,
    tick_minutes = 4,             -- periodic "anything to add?" event
    -- Factions come from ragtag_verse.lua. Hollow and Relic are deliberately not
    -- spawnable by the director: they belong to their zones.
    allowed_factions = {"Corsairs", "Independent", "Concord", "Unknown"},
    hostile_factions = {Corsairs = true, Hollow = true, Relic = true},
}
DIR.cooldowns = {}
DIR.credits_given = 0

-- Ship groups by strength. Faction only changes allegiance, not hulls.
DIR.GROUPS = {
    scout  = {"MT52 Hornet"},
    light  = {"Adder MK5", "MT52 Hornet"},
    medium = {"Phobos T3", "Adder MK5", "MT52 Hornet"},
    heavy  = {"Nirvana R5", "Phobos T3", "Adder MK5", "Adder MK5"},
}

DIR.SYSTEMS = {
    reactor = "reactor", beams = "beamweapons", beamweapons = "beamweapons",
    missiles = "missilesystem", missilesystem = "missilesystem", maneuver = "maneuver",
    impulse = "impulse", warp = "warp", jumpdrive = "jumpdrive",
    frontshield = "frontshield", rearshield = "rearshield",
}

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

-- session: {id="s1", title=..., premise=..., cast={{name=..., role=..., voice=...}}, tone=...}
function DIR.init(session)
    DIR.session = session or {}
    DIR.run = string.format("%s-%d-%d", DIR.session.id or "run", math.floor(random(0, 999999)), math.floor(random(0, 999999)))
    DIR.addGMFunctions()
    -- Build fresh copies of campaign sub-tables so toJSON never sees the same
    -- table object twice (shared refs across events+state trigger a Lua next() error).
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
    DIR.emit("session_start", {session = sess_id, campaign = camp_snap}, "high")
end

-- Define a story beat. ai=true lets the director choose when to fire it.
-- fn(source) is called once; source is "ai", "fallback", "gm" or "script".
function DIR.defineBeat(id, opts)
    DIR.beat_order = DIR.beat_order + 1
    DIR.beats[id] = {desc = opts.desc or id, ai = opts.ai or false, fn = opts.fn, fired = false, order = DIR.beat_order}
end

function DIR.fireBeat(id, source)
    local b = DIR.beats[id]
    if b == nil then return false, "no such beat" end
    if b.fired then return false, "already fired" end
    b.fired = true
    local ok, err = pcall(b.fn, source or "script")
    if not ok then
        print("[DIR] beat " .. id .. " failed: " .. tostring(err))
        return false, tostring(err)
    end
    DIR.emit("beat", {id = id, desc = b.desc, by = source or "script"}, "normal")
    return true, "fired"
end

function DIR.beatFired(id)
    return DIR.beats[id] ~= nil and DIR.beats[id].fired
end

function DIR.addStateProvider(fn)
    table.insert(DIR.state_providers, fn)
end

-- Mark an entity as one the director may hail as / give orders to.
function DIR.allowControl(entity)
    DIR.controllable[entity:getCallSign()] = true
    RT.named[entity:getCallSign()] = entity
end

-- Register a kill-tracking callback on any ship (player or scenario spawned).
-- Emits "destroyed" for every kill and "combat_kill" (with strength data) for
-- player kills. Call this after creating any CpuShip the crew might fight:
--   VERSE's garrison builder calls it automatically for all garrison ships.
--   spawn_group calls it for director-spawned groups.
--   Scenario scripts should call DIR.registerKill(ship) for their own spawns.
function DIR.registerKill(ship)
    if not RT.valid(ship) then return end
    local str = RT.shipStrength(ship)
    ship:onDestruction(function(s, instigator)
        local by_player = instigator ~= nil and instigator == RT.player
        DIR.emit("destroyed", {callsign = s:getCallSign(), faction = s:getFaction(),
            by_player = by_player and 1 or 0}, "normal")
        if by_player then
            local player_str = RT.shipStrength(RT.player)
            local ratio = str.total > 0 and math.floor(player_str.total * 100 / str.total) / 100 or 0
            DIR.emit("combat_kill", {
                callsign   = s:getCallSign(),
                faction    = s:getFaction(),
                enemy_str  = str,
                player_str = player_str,
                ratio      = ratio,
            }, "normal")
        end
    end)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- priority: "high" asks the director to react right away; "normal"/"low" batch.
function DIR.emit(etype, data, priority)
    local ev = {id = DIR.next_event_id, t = math.floor(getScenarioTime()), type = etype,
                data = data or {}, pri = priority or "normal"}
    DIR.next_event_id = DIR.next_event_id + 1
    table.insert(DIR.events, ev)
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

--------------------------------------------------------------------------------
-- State snapshot sent to the director
--------------------------------------------------------------------------------

local function round(v) return math.floor(v + 0.5) end

function DIR.countAIHostiles()
    local n = 0
    for i = #DIR.spawned, 1, -1 do
        local e = DIR.spawned[i]
        if not RT.valid(e) then
            table.remove(DIR.spawned, i)
        elseif RT.valid(RT.player) and e:isEnemy(RT.player) then
            n = n + 1
        end
    end
    return n
end

function DIR.buildState()
    -- Build a full session snapshot using only fresh tables so toJSON never
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
        objective = RT and RT.objective or "",
        paused = b01(DIR.paused),
        beats = {},
        budget = {
            ai_hostiles_alive = 0, max_ai_hostiles = DIR.config.max_ai_hostiles,
            credits_given = DIR.credits_given, credit_cap = DIR.config.credit_cap_per_session,
        },
    }
    local list = {}
    for id, b in pairs(DIR.beats) do table.insert(list, {id = id, b = b}) end
    table.sort(list, function(a, c) return a.b.order < c.b.order end)
    for _, item in ipairs(list) do
        table.insert(st.beats, {id = item.id, desc = item.b.desc, ai = b01(item.b.ai), fired = b01(item.b.fired)})
    end

    st.budget.ai_hostiles_alive = DIR.countAIHostiles()

    local p = RT and RT.player
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
        st.player = {
            callsign = p:getCallSign(), sector = p:getSectorName(),
            x = round(x), y = round(y), heading = round(p:getHeading()),
            hull = round(p:getHull()), hull_max = round(p:getHullMax()),
            shields_up = b01(p:getShieldsActive()), credits = RT.credits(),
            docked_with = (docked and RT.valid(docked)) and docked:getCallSign() or nil,
            damaged_systems = damaged,
            homing = p:getWeaponStorage("Homing"), hvli = p:getWeaponStorage("HVLI"),
        }
        local nearby = {}
        for _, obj in ipairs(getObjectsInRadius(x, y, 30000)) do
            -- Only ships and stations: asteroids, nebulae etc. have no typename
            -- component, and calling getTypeName() on them raises an error.
            if obj ~= p and obj.components ~= nil and obj.components.typename ~= nil then
                local ok, info = pcall(function()
                    return {
                        callsign = obj:getCallSign(), type = obj:getTypeName(), faction = obj:getFaction(),
                        dist_u = round(RT.dist(p, obj) / 100) / 10,
                        hostile = b01(obj:isEnemy(p)), ai_spawned = b01(DIR.controllable[obj:getCallSign()]),
                    }
                end)
                if ok then table.insert(nearby, info) end
            end
            if #nearby >= 16 then break end
        end
        table.sort(nearby, function(a, b) return a.dist_u < b.dist_u end)
        st.player.nearby = nearby
    else
        st.player = {destroyed = true}
    end

    st.extra = {}
    for _, fn in ipairs(DIR.state_providers) do
        local ok, t = pcall(fn)
        if ok and type(t) == "table" then
            for k, v in pairs(t) do st.extra[k] = v end
        end
    end
    if RT and RT.campaign then
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
    if not DIR.enabled then
        if DIR.run ~= nil then print("[DIR] update: disabled, skipping") end
        return
    end
    if DIR.run == nil then return end
    local now = getScenarioTime()

    DIR.processPendingHails(now)
    if DIR.updateMissions then DIR.updateMissions() end

    -- Periodic tick so the director can add colour during quiet stretches.
    if now - DIR.last_tick >= DIR.config.tick_minutes * 60 then
        DIR.last_tick = now
        DIR.emit("tick", {minutes = math.floor(now / 60)}, "low")
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
            print("[DIR] buildState failed: " .. tostring(state_val))
            state_val = {}
        end
        local out = {
            proto = DIR.PROTO, run = DIR.run, seq = DIR.seq,
            events = DIR.events, cmd_ack = DIR.last_cmd_id, results = DIR.results,
            state = state_val,
        }

        -- Use our own serialiser: EE's toJSON has a C stack-index bug that makes
        -- it fail on any table containing two or more non-empty table values.
        local s = _json(out)
        if DIR.seq <= 3 then
            print("[DIR] write seq=" .. DIR.seq .. " len=" .. #s .. " proto=" .. tostring(out.proto) .. " run=" .. tostring(out.run))
        end
        storage:set(DIR.KEY_OUT, s)
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
    elseif DIR.paused and cmd.source ~= "gm" then
        ok, msg = false, "director paused by GM"
    else
        local success, r1, r2 = pcall(handler, args, cmd)
        if not success then
            ok, msg = false, "error: " .. tostring(r1)
            print("[DIR] action " .. action .. " crashed: " .. tostring(r1))
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

local function onCooldown(name, seconds)
    local now = getScenarioTime()
    local last = DIR.cooldowns[name]
    if last and now - last < seconds then
        return true, math.ceil(seconds - (now - last))
    end
    DIR.cooldowns[name] = now
    return false
end

local function factionAllowed(f)
    for _, a in ipairs(DIR.config.allowed_factions) do
        if a == f then return true end
    end
    return false
end

-- Resolve a spawn point. near = "player" | callsign; distance in units (1u = 1000).
local function resolvePoint(args, default_dist, min_d, max_d)
    local anchor = nil
    local near = args.near or "player"
    if near == "player" then anchor = RT.player else anchor = RT.find(near) end
    if not RT.valid(anchor) then anchor = RT.player end
    if not RT.valid(anchor) then return nil end
    local ax, ay = anchor:getPosition()
    local d = num(args.distance, min_d, max_d, default_dist) * 1000
    local bearing = tonumber(args.bearing)
    if args.side == "ahead" and RT.valid(RT.player) then
        bearing = RT.player:getHeading() + random(-30, 30)
    elseif args.side == "behind" and RT.valid(RT.player) then
        bearing = RT.player:getHeading() + 180 + random(-30, 30)
    end
    if bearing == nil then bearing = random(0, 360) end
    local dx, dy = vectorFromAngle(bearing, d, true)
    return ax + dx, ay + dy
end

local function uniqueCallsign(base)
    base = str(base, 24, nil)
    if base == nil or base == "" then return nil end
    if RT.find(base) == nil then return base end
    for i = 2, 99 do
        local c = base .. "-" .. i
        if RT.find(c) == nil then return c end
    end
    return nil
end

-- Shared helpers for action files loaded from director/actions/*.lua.
DIR._h = {
    str            = str,
    num            = num,
    onCooldown     = onCooldown,
    factionAllowed = factionAllowed,
    resolvePoint   = resolvePoint,
    uniqueCallsign = uniqueCallsign,
}

-- Comms function for director-spawned NPCs: asking them anything turns into an
-- event; the director answers with a "say" action a few seconds later.
function DIR.npcComms(source, target)
    local cs = target:getCallSign()
    local info = DIR.npc_info and DIR.npc_info[cs] or {}
    if info.greeting and info.greeting ~= "" then
        setCommsMessage(info.greeting)
    else
        setCommsMessage("\"" .. cs .. " here. Go ahead.\"")
    end

    -- Pre-generated tree from comms_tree action: instant replies, no LLM round-trip.
    if info.tree and #info.tree > 0 then
        for _, opt in ipairs(info.tree) do
            local reply = opt.reply
            addCommsReply(opt.label, function(s, t)
                setCommsMessage(reply)
            end)
        end
        addCommsReply("Nothing, thanks.", function(s, t)
            setCommsMessage("\"Safe travels.\"")
        end)
        return
    end

    -- Generic LLM-driven comms: crew picks a topic, director answers with "say".
    local fallback = {
        identity = "\"Just another crew trying to make a living out here.\"",
        intent = "\"Same as you. Get paid, stay breathing.\"",
        work = "\"Nothing for you. Try the stations.\"",
        negotiate = "\"Ha! No.\"",
    }
    local function ask(label, topic)
        addCommsReply(label, function(s, t)
            if DIR.online and not DIR.paused then
                setCommsMessage("(They consider this. Stand by...)")
                DIR.emit("npc_hailed", {callsign = cs, faction = t:getFaction(), topic = topic, role = info.role}, "high")
            else
                setCommsMessage(fallback[topic] or "\"...\"")
            end
        end)
    end
    ask("Who are you?", "identity")
    ask("What do you want?", "intent")
    ask("Got any work?", "work")
    if source:isEnemy(target) then ask("Let's make a deal.", "negotiate") end
end
DIR.npc_info = {}

--------------------------------------------------------------------------------
-- Action whitelist. Each returns ok(bool), message(string).
-- Actions are loaded from ee/ragtag/director/actions/index.lua (generated).
-- To add a new action: create a .lua file in that directory and run check.py --fix.
-- Keep any new action in sync with director/actions.py (Python validation layer).
--------------------------------------------------------------------------------

DIR.ACTIONS = {}

function DIR.processPendingHails(now)
    for i = #DIR.pending_hails, 1, -1 do
        local h = DIR.pending_hails[i]
        local ent = RT.find(h.speaker)
        if not RT.valid(ent) or not RT.valid(RT.player) or now > h.until_t then
            table.remove(DIR.pending_hails, i)
            if RT.valid(RT.player) then RT.player:addToShipLog("[" .. h.speaker .. "] " .. h.text, "#C0E0FF") end
        elseif ent:sendCommsMessage(RT.player, h.text) then
            table.remove(DIR.pending_hails, i)
        end
    end
end


--------------------------------------------------------------------------------
-- GM screen buttons
--------------------------------------------------------------------------------

function DIR.addGMFunctions()
    addGMFunction("AI: twist!", function()
        DIR.emit("gm_request", {kind = "twist", note = "GM wants a surprise complication now"}, "high")
    end)
    addGMFunction("AI: escalate", function()
        DIR.emit("gm_request", {kind = "escalate", note = "GM wants more pressure"}, "high")
    end)
    addGMFunction("AI: ease off", function()
        DIR.emit("gm_request", {kind = "ease", note = "GM thinks the crew is overwhelmed"}, "high")
    end)
    addGMFunction("AI: chatter", function()
        DIR.emit("gm_request", {kind = "chatter", note = "GM wants some flavour comms"}, "high")
    end)
    addGMFunction("AI: pause", function()
        DIR.paused = not DIR.paused
        DIR.dirty = true
        addGMMessage(DIR.paused and "AI director paused (its actions will be refused)." or "AI director resumed.")
    end)
    addGMFunction("AI: status", function()
        local lines = {
            "Director: " .. (DIR.online and "online" or "OFFLINE") .. (DIR.paused and " (paused)" or ""),
            "Run: " .. tostring(DIR.run),
            "Unsent events: " .. #DIR.events .. ", last command: " .. DIR.last_cmd_id,
        }
        for _, r in ipairs(DIR.results) do
            table.insert(lines, string.format("#%s %s: %s %s", tostring(r.id), r.action, r.ok and "ok" or "FAIL", r.msg))
        end
        addGMMessage(table.concat(lines, "\n"))
    end)
end

-- NPC order helper shared by spawn_group and npc_order actions.
function DIR.orderGroup(callsigns, behavior)
    local leader = nil
    for i, cs in ipairs(callsigns) do
        local s = RT.find(cs)
        if RT.valid(s) then
            if behavior == "attack" and RT.valid(RT.player) then
                s:orderAttack(RT.player)
            elseif behavior == "patrol" then
                s:orderRoaming()
            elseif behavior == "flee" then
                s:orderRetreat()
            elseif behavior == "follow" and RT.valid(RT.player) then
                s:orderDefendTarget(RT.player)
            else
                if leader ~= nil then s:orderFlyFormation(leader, (i - 1) * 300, 300) else s:orderIdle() end
            end
            if leader == nil then leader = s end
        end
    end
end

require("ragtag/director/actions/index.lua")
