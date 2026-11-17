-- ee/ragtag/core/events.lua
-- The campaign event bus, scripted beats and state providers (RT.emit, RT.on, RT.defineBeat, ...).
-- Part of core (RT). Loaded by ee/ragtag/core.lua; do not require directly.
--
-- Game code says WHAT happened with RT.emit and does not know who is listening. Anything that
-- wants to observe the campaign subscribes with RT.on. The AI director's mailbox
-- (ee/ragtag/director.lua) is one such listener; with no listener an event simply goes nowhere,
-- so every layer below the director works the same with or without it.
--
-- Nothing in core, the job board, the world plugins or the story arcs may name DIR
-- (tools/check.py enforces it): they emit, the director listens.

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

RT._listeners = {}

-- Subscribe to every event. fn(ev) with ev = {t = scenario seconds, type, data, pri}.
-- A listener must not change ev or ev.data (other listeners get the same tables).
function RT.on(fn)
    table.insert(RT._listeners, fn)
end

-- Report that something happened. data: a flat table of numbers / strings (it may be sent out
-- of the game as JSON). priority: "high" (worth reacting to at once), "normal" (default), "low".
function RT.emit(etype, data, priority)
    local ev = {t = math.floor(getScenarioTime()), type = etype, data = data or {}, pri = priority or "normal"}
    for _, fn in ipairs(RT._listeners) do
        local ok, err = pcall(fn, ev)
        if not ok then log("[RT] event listener failed on '" .. tostring(etype) .. "': " .. tostring(err)) end
    end
end

-- Report the death of a ship the crew might fight: "destroyed" for every damage kill, plus
-- "combat_kill" (with strength data) when a player made it. Shares the ship's single
-- onDestruction slot through RT.onKill, so it does not clobber reputation tracking or loot.
function RT.reportKills(ship)
    if not RT.valid(ship) then return end
    local str = RT.shipStrength(ship)
    RT.onKill(ship, function(s, instigator)
        local killer = RT.playerShip(instigator)
        RT.emit("destroyed", {callsign = s:getCallSign(), faction = s:getFaction(),
            by_player = killer and 1 or 0}, "normal")
        if killer then
            local player_str = RT.shipStrength(killer)
            local ratio = str.total > 0 and math.floor(player_str.total * 100 / str.total) / 100 or 0
            RT.emit("combat_kill", {
                callsign   = s:getCallSign(),
                faction    = s:getFaction(),
                enemy_str  = str,
                player_str = player_str,
                ratio      = ratio,
                killer     = RT.valid(killer) and killer:getCallSign() or "unknown",
            }, "normal")
        end
    end)
end

--------------------------------------------------------------------------------
-- Scripted beats: named story moments a scenario fires once.
--------------------------------------------------------------------------------

RT.beats = {}            -- id -> {desc, fn, fired, order}
RT._beat_order = 0

-- fn(source) is called once; source is "script", "fallback" or "gm".
function RT.defineBeat(id, opts)
    RT._beat_order = RT._beat_order + 1
    RT.beats[id] = {desc = opts.desc or id, fn = opts.fn, fired = false, order = RT._beat_order}
end

function RT.fireBeat(id, source)
    local b = RT.beats[id]
    if b == nil then return false, "no such beat" end
    if b.fired then return false, "already fired" end
    b.fired = true
    local ok, err = pcall(b.fn, source or "script")
    if not ok then
        log("[RT] beat " .. id .. " failed: " .. tostring(err))
        return false, tostring(err)
    end
    RT.emit("beat", {id = id, desc = b.desc, by = source or "script"}, "normal")
    return true, "fired"
end

function RT.beatFired(id)
    return RT.beats[id] ~= nil and RT.beats[id].fired
end

--------------------------------------------------------------------------------
-- State providers: what a layer wants an observer to know about right now.
--------------------------------------------------------------------------------

RT.state_providers = {}

-- fn() returns a flat table; observers merge the tables of every provider into one snapshot.
function RT.addStateProvider(fn)
    table.insert(RT.state_providers, fn)
end

function RT.extraState()
    local out = {}
    for _, fn in ipairs(RT.state_providers) do
        local ok, t = pcall(fn)
        if ok and type(t) == "table" then
            for k, v in pairs(t) do out[k] = v end
        end
    end
    return out
end
