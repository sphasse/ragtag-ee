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
    DIR.emit("session_start", {
        session = DIR.session,
        campaign = RT and RT.campaign and {
            credits = RT.campaign.credits, upgrades = RT.campaign.upgrades,
            flags = RT.campaign.flags, notes = RT.campaign.notes, ship = RT.campaign.ship_name,
        } or nil,
    }, "high")
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
    local st = {
        -- Repeated in every snapshot so a director that starts (or restarts)
        -- mid-session still gets the briefing and campaign id.
        session = DIR.session,
        time = round(getScenarioTime()),
        objective = RT and RT.objective or "",
        paused = DIR.paused,
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
        table.insert(st.beats, {id = item.id, desc = item.b.desc, ai = item.b.ai, fired = item.b.fired})
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
            shields_up = p:getShieldsActive(), credits = RT.credits(),
            docked_with = (docked and RT.valid(docked)) and docked:getCallSign() or nil,
            damaged_systems = damaged,
            homing = p:getWeaponStorage("Homing"), hvli = p:getWeaponStorage("HVLI"),
        }
        local nearby = {}
        for _, obj in ipairs(getObjectsInRadius(x, y, 30000)) do
            -- Only ships and stations: asteroids, nebulae etc. have no typename
            -- component, and calling getTypeName() on them raises an error.
            if obj ~= p and obj.components.typename ~= nil then
                local ok, info = pcall(function()
                    return {
                        callsign = obj:getCallSign(), type = obj:getTypeName(), faction = obj:getFaction(),
                        dist_u = round(RT.dist(p, obj) / 100) / 10,
                        hostile = obj:isEnemy(p), ai_spawned = DIR.controllable[obj:getCallSign()] or false,
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
        st.campaign = RT.campaign
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
        local out = {
            proto = DIR.PROTO, run = DIR.run, seq = DIR.seq,
            events = DIR.events, cmd_ack = DIR.last_cmd_id, results = DIR.results,
            state = DIR.buildState(),
        }
        local ok, s = pcall(toJSON, out)
        if ok then
            storage:set(DIR.KEY_OUT, s)
        else
            print("[DIR] toJSON failed: " .. tostring(s))
        end
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
-- Keep this list in sync with director/actions.py.
--------------------------------------------------------------------------------

DIR.ACTIONS = {}

-- Speak to the crew as a named character.
-- args: speaker, text, channel = "hail" | "log"
DIR.ACTIONS.say = function(a)
    local text = str(a.text, 500, nil)
    if text == nil or text == "" then return false, "text required" end
    if not RT.valid(RT.player) then return false, "no player ship" end
    local speaker = str(a.speaker, 40, "Unknown")
    local ent = RT.find(speaker)
    if a.channel ~= "log" and RT.valid(ent) and ent ~= RT.player then
        if ent:sendCommsMessage(RT.player, text) then return true, "hailed as " .. speaker end
        table.insert(DIR.pending_hails, {speaker = speaker, text = text, until_t = getScenarioTime() + 30})
        return true, "player comms busy; queued"
    end
    RT.player:addToShipLog("[" .. speaker .. "] " .. text, "#C0E0FF")
    return true, "logged as " .. speaker
end

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

-- Text on every main screen. args: text
DIR.ACTIONS.main_screen = function(a)
    local text = str(a.text, 120, nil)
    if text == nil or text == "" then return false, "text required" end
    globalMessage(text, 8)
    return true, "shown"
end

-- Private note to the human GM. args: text
DIR.ACTIONS.gm_note = function(a)
    addGMMessage("[AI] " .. str(a.text, 400, ""))
    return true, "noted"
end

-- Spawn a group of ships. args: faction, strength, near, distance, side, behavior, callsign
DIR.ACTIONS.spawn_group = function(a)
    local faction = str(a.faction, 30, "Corsairs")
    if not factionAllowed(faction) then return false, "faction not allowed" end
    local strength = str(a.strength, 10, "light")
    local templates = DIR.GROUPS[strength]
    if templates == nil then return false, "strength must be scout/light/medium/heavy" end
    local hostile = DIR.config.hostile_factions[faction] or false
    if hostile then
        local alive = DIR.countAIHostiles()
        if alive + #templates > DIR.config.max_ai_hostiles then
            return false, string.format("hostile budget exceeded (%d alive, max %d)", alive, DIR.config.max_ai_hostiles)
        end
        local cd, left = onCooldown("spawn_group", DIR.config.spawn_cooldown)
        if cd then return false, "spawn cooldown, " .. left .. "s left" end
    end
    local x, y = resolvePoint(a, 12, 6, 30)
    if x == nil then return false, "no anchor" end
    local behavior = str(a.behavior, 20, hostile and "attack" or "idle")
    local base = uniqueCallsign(a.callsign)
    local leader = nil
    local names = {}
    for i, tmpl in ipairs(templates) do
        local s = CpuShip():setTemplate(tmpl):setFaction(faction)
        local cs = base and (i == 1 and base or (base .. "-" .. i)) or nil
        if cs and RT.find(cs) == nil then s:setCallSign(cs) end
        if leader == nil then
            s:setPosition(x, y)
            leader = s
        else
            s:setPosition(x + random(-600, 600), y + random(-600, 600))
        end
        table.insert(DIR.spawned, s)
        DIR.allowControl(s)
        s:setCommsFunction(DIR.npcComms)
        s:onDestruction(function(ship, instigator)
            DIR.emit("destroyed", {callsign = ship:getCallSign(), faction = ship:getFaction(),
                by_player = (instigator ~= nil and instigator == RT.player)}, "normal")
        end)
        table.insert(names, s:getCallSign())
    end
    DIR.orderGroup(names, behavior)
    return true, "spawned " .. table.concat(names, ", ")
end

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

-- Spawn a single non-combat NPC the crew can talk to.
-- args: role = trader|patrol|derelict|stranger, faction, callsign, near, distance, side, greeting, description
DIR.ACTIONS.spawn_npc = function(a)
    local role = str(a.role, 12, "trader")
    local faction = str(a.faction, 30, role == "patrol" and "Concord" or "Independent")
    if not factionAllowed(faction) then return false, "faction not allowed" end
    if DIR.config.hostile_factions[faction] and role ~= "derelict" then
        return false, "use spawn_group for hostile factions"
    end
    local cd, left = onCooldown("spawn_npc", 45)
    if cd then return false, "npc cooldown, " .. left .. "s left" end
    local tmpl = ({trader = "Flavia", patrol = "Phobos M3", derelict = "Tug", stranger = "Piranha F12"})[role]
    if tmpl == nil then return false, "role must be trader/patrol/derelict/stranger" end
    local x, y = resolvePoint(a, 8, 3, 25)
    if x == nil then return false, "no anchor" end
    local s = CpuShip():setTemplate(tmpl):setFaction(faction):setPosition(x, y)
    local cs = uniqueCallsign(a.callsign)
    if cs then s:setCallSign(cs) end
    cs = s:getCallSign()
    if a.description then s:setDescription(str(a.description, 300, "")) end
    if role == "derelict" then
        s:orderIdle()
        s:setHull(math.max(1, s:getHullMax() * 0.15))
        s:setImpulseMaxSpeed(0)
        s:setShieldsMax(0)
    elseif role == "patrol" then
        s:orderRoaming()
    else
        s:orderIdle()
    end
    DIR.npc_info[cs] = {greeting = str(a.greeting, 300, nil), role = role}
    s:setCommsFunction(DIR.npcComms)
    table.insert(DIR.spawned, s)
    DIR.allowControl(s)
    return true, "spawned " .. role .. " " .. cs
end

-- A floating crate/pod the crew can pick up for credits.
-- args: near, distance, side, credits, label, description
DIR.ACTIONS.spawn_salvage = function(a)
    local cd, left = onCooldown("spawn_salvage", 120)
    if cd then return false, "salvage cooldown, " .. left .. "s left" end
    local x, y = resolvePoint(a, 6, 2, 20)
    if x == nil then return false, "no anchor" end
    local credits = math.floor(num(a.credits, 0, 150, 50))
    local label = str(a.label, 40, "Drifting cargo pod")
    local art = Artifact():setPosition(x, y):allowPickup(true)
    art:setDescriptions("Unidentified object", str(a.description, 200, label))
    art:setCallSign(label)
    art:onPickUp(function(obj, player)
        RT.addCredits(credits, label)
        DIR.emit("pickup", {label = label, credits = credits}, "normal")
    end)
    return true, "salvage placed (" .. credits .. " cr)"
end

-- args: amount (-300..300), reason
DIR.ACTIONS.give_credits = function(a)
    local amt = math.floor(num(a.amount, -DIR.config.credit_cap_per_action, DIR.config.credit_cap_per_action, 0))
    if amt == 0 then return false, "amount required" end
    if amt > 0 and DIR.credits_given + amt > DIR.config.credit_cap_per_session then
        return false, "session credit cap reached"
    end
    if amt > 0 then DIR.credits_given = DIR.credits_given + amt end
    RT.addCredits(amt, str(a.reason, 60, "director"))
    return true, "credits " .. amt
end

-- Knock a ship system's health down (engineering gets something to do).
-- args: system, severity (0.1 - 0.5), reason
DIR.ACTIONS.system_glitch = function(a)
    if not RT.valid(RT.player) then return false, "no player" end
    local sys = DIR.SYSTEMS[string.lower(str(a.system, 20, "") or "")]
    if sys == nil then return false, "unknown system" end
    if not RT.player:hasSystem(sys) then return false, "ship lacks that system" end
    local cd, left = onCooldown("system_glitch", DIR.config.glitch_cooldown)
    if cd then return false, "glitch cooldown, " .. left .. "s left" end
    local sev = num(a.severity, 0.1, 0.5, 0.25)
    local h = RT.player:getSystemHealth(sys)
    RT.player:setSystemHealth(sys, math.max(-0.3, h - sev))
    if a.reason then RT.player:addToShipLog("Engineering: " .. str(a.reason, 120, ""), "#FFA060") end
    return true, sys .. " health " .. math.floor((h - sev) * 100) .. "%"
end

-- Fire a scenario-defined story beat that is marked ai=true. args: beat
DIR.ACTIONS.fire_beat = function(a, cmd)
    local id = str(a.beat, 40, "")
    local b = DIR.beats[id]
    if b == nil then return false, "no such beat" end
    if not b.ai and cmd.source ~= "gm" then return false, "beat is not AI-triggerable" end
    return DIR.fireBeat(id, cmd.source == "gm" and "gm" or "ai")
end

-- Order a director-controllable NPC. args: callsign, order = attack|flee|idle|follow|patrol|dock, target
DIR.ACTIONS.npc_order = function(a)
    local cs = str(a.callsign, 40, "")
    if not DIR.controllable[cs] then return false, "not a controllable NPC" end
    local s = RT.find(cs)
    if not RT.valid(s) then return false, "NPC gone" end
    local order = str(a.order, 12, "idle")
    if order == "dock" then
        local t = RT.find(str(a.target, 40, ""))
        if not RT.valid(t) then return false, "dock target not found" end
        s:orderDock(t)
    else
        DIR.orderGroup({cs}, order)
    end
    return true, cs .. " -> " .. order
end

-- GM-only actions (the director refuses to send these from the model).
DIR.ACTIONS.set_objective = function(a)
    RT.setObjective(str(a.text, 160, ""))
    return true, "objective set"
end

DIR.ACTIONS.restore_campaign = function(a, cmd)
    if cmd.source ~= "gm" then return false, "GM only" end
    if type(a.campaign) ~= "table" then return false, "campaign table required" end
    getScriptStorage():set(RT.CAMPAIGN_KEY, toJSON(a.campaign))
    RT.loadCampaign()
    return true, "campaign restored; restart the scenario to apply upgrades"
end

DIR.ACTIONS.rename_ship = function(a, cmd)
    if cmd.source ~= "gm" then return false, "GM only" end
    local name = str(a.name, 24, nil)
    if name == nil or name == "" then return false, "name required" end
    RT.campaign.ship_name = name
    if RT.valid(RT.player) then RT.player:setCallSign(name); RT.named[name] = RT.player end
    RT.saveCampaign()
    return true, "ship renamed " .. name
end

DIR.ACTIONS.noop = function(a) return true, "ok" end

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
    addGMFunction("AI: pause/resume", function()
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
