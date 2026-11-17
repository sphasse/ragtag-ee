-- The event bus (RT.emit / RT.on), scripted beats, state providers, and the AI director's
-- mailbox on top of them. The director is observation-only: it hears events, and nothing the
-- model can send has an effect in the game.
--
-- Not covered: the HTTP side (tools/smoke_test.py drives the real mailbox over /exec.lua) and the
-- Python director itself.

T.suite("core")

local heard = {}
local function count(etype)
    local n = 0
    for _, ev in ipairs(heard) do if ev.type == etype then n = n + 1 end end
    return n
end
local function last(etype)
    for i = #heard, 1, -1 do if heard[i].type == etype then return heard[i] end end
end
local function run(action, args, source)
    DIR.execute({id = 9000 + #DIR.results, action = action, args = args, source = source})
    return DIR.results[#DIR.results]
end

-- ── The bus ──────────────────────────────────────────────────────────────────
T.step("subscribe and emit", function()
    RT.on(function(ev) heard[#heard + 1] = ev end)
    RT.emit("test_event", {n = 7}, "high")
    local ev = last("test_event")
    T.check("bus: a listener hears an event", ev ~= nil)
    T.eq("bus: its data", ev and ev.data.n, 7)
    T.eq("bus: its priority", ev and ev.pri, "high")
    T.check("bus: it is timestamped", ev and type(ev.t) == "number")
    RT.emit("test_plain")
    T.eq("bus: priority defaults to normal", last("test_plain").pri, "normal")
    T.eq("bus: data defaults to an empty table", next(last("test_plain").data), nil)
end)
T.step("a broken listener does not break the game", function()
    local logged = T.expectLogged(function()
        RT.on(function(ev) if ev.type == "test_boom" then error("listener blew up") end end)
        RT.emit("test_boom")
    end)
    T.check("bus: the error is logged", #logged == 1, table.concat(logged, " / "))
    T.check("bus: the other listeners still heard it", last("test_boom") ~= nil)
end)

-- ── The game reports through the bus ─────────────────────────────────────────
T.step("game code emits", function()
    RT.setObjective("Test objective", true)
    T.eq("emit: objective", last("objective") and last("objective").data.text, "Test objective")
    RT.grantUpgrade("sensor_suite", "test", T.P())
    T.eq("emit: upgrade", last("upgrade") and last("upgrade").data.id, "sensor_suite")
    T.eq("emit: upgrade names the ship", last("upgrade").data.ship, T.P():getCallSign())
end)

-- ── Beats ────────────────────────────────────────────────────────────────────
local fired_by = {}
T.step("a beat fires once", function()
    RT.defineBeat("test_beat", {desc = "A test beat", fn = function(src) fired_by[#fired_by + 1] = src end})
    T.check("beat: not fired yet", not RT.beatFired("test_beat"))
    local ok = RT.fireBeat("test_beat", "script")
    T.check("beat: fired", ok and RT.beatFired("test_beat"))
    T.eq("beat: told who fired it", fired_by[1], "script")
    T.eq("beat: reported", last("beat") and last("beat").data.id, "test_beat")
    T.check("beat: not twice", not RT.fireBeat("test_beat", "gm"))
    T.eq("beat: the function ran once", #fired_by, 1)
    T.check("beat: unknown beat refused", not RT.fireBeat("no_such_beat"))
    T.check("beat: the scenario's own beat is on the list", RT.beats["first_undock"] ~= nil)
end)

-- ── State providers ──────────────────────────────────────────────────────────
T.step("state providers are merged", function()
    RT.addStateProvider(function() return {test_value = 42} end)
    RT.addStateProvider(function() error("provider blew up") end)
    local st = RT.extraState()
    T.eq("state: a provider's value", st.test_value, 42)
    T.check("state: the universe's provider", st.region ~= nil)
    T.check("state: the scenario's provider", st.phase ~= nil)
end)

-- ── The director's mailbox listens ───────────────────────────────────────────
T.step("the mailbox queues what the game reports", function()
    T.check("dir: enabled in this scenario", DIR.enabled)
    local before = #DIR.events
    RT.emit("test_for_director", {x = 1}, "low")
    T.eq("dir: one more queued event", #DIR.events, before + 1)
    local ev = DIR.events[#DIR.events]
    T.eq("dir: it is that event", ev.type, "test_for_director")
    T.check("dir: with an id for the director to acknowledge", type(ev.id) == "number")
    local st = DIR.buildState()
    T.eq("dir: snapshot has the objective", st.objective, "Test objective")
    T.eq("dir: snapshot has the primary ship", st.player.callsign, T.P():getCallSign())
    T.eq("dir: snapshot has provider values", st.extra.test_value, 42)
    local found = false
    for _, b in ipairs(st.beats) do if b.id == "test_beat" and b.fired == 1 then found = true end end
    T.check("dir: snapshot lists beats", found)
end)
T.step("each ship is reported with its own balance", function()
    local B = T.secondShip()
    RT.setCredits(55, B)
    local st = DIR.buildState()
    T.eq("dir: two ships in the snapshot", #st.players, 2)
    T.eq("dir: the primary ship's credits", st.players[1].credits, T.credits(T.P()))
    T.eq("dir: the second ship's credits are its own", st.players[2].credits, 55)
end)
T.step("the queue stays bounded with nobody reading it", function()
    for i = 1, 100 do RT.emit("test_flood", {i = i}, "low") end
    T.check("dir: at most 60 queued", #DIR.events <= 60, #DIR.events)
end)

-- ── Observation only: the model's commands cannot touch the game ─────────────
T.step("what the model may send", function()
    local r = run("gm_note", {text = "a private note"}, "llm")
    T.check("llm: gm_note accepted (the crew never sees it)", r.ok, r.msg)
    r = run("noop", {}, "llm")
    T.check("llm: noop accepted", r.ok, r.msg)
end)
T.step("what it may not", function()
    local objective = RT.objective
    local name = T.P():getCallSign()
    local r = run("say", {speaker = "Port Vesper", text = "The model speaks."}, "llm")
    T.check("llm: say refused", not r.ok, r.msg)
    T.eq("llm: no hail was queued", #DIR.pending_hails, 0)
    r = run("say", {speaker = "Nobody", text = "The model writes to the log.", channel = "log"}, "llm")
    T.check("llm: say to the log refused", not r.ok, r.msg)
    r = run("set_objective", {text = "Obey the model"}, "llm")
    T.check("llm: set_objective refused", not r.ok, r.msg)
    T.eq("llm: the objective is unchanged", RT.objective, objective)
    r = run("rename_ship", {name = "Hacked"}, "llm")
    T.check("llm: rename_ship refused", not r.ok, r.msg)
    T.eq("llm: the ship keeps its name", T.P():getCallSign(), name)
    r = run("restore_campaign", {campaign = {credits = 999999}}, "llm")
    T.check("llm: restore_campaign refused", not r.ok, r.msg)
    r = run("spawn_group", {faction = "Corsairs"}, "llm")
    T.check("llm: an action that does not exist is refused", not r.ok and r.msg == "unknown action", r.msg)
    r = run("say", {speaker = "Port Vesper", text = "No source at all."}, nil)
    T.check("llm: a command with no source is treated as the model's", not r.ok, r.msg)
end)
T.step("every action with an effect is GM-only", function()
    -- Whatever is on the whitelist: sent as the model, only gm_note and noop may succeed.
    local harmless = {gm_note = true, noop = true}
    local leaked = {}
    for name in pairs(DIR.ACTIONS) do
        if not harmless[name] then
            local r = run(name, {text = "x", speaker = "x", name = "x", campaign = {}}, "llm")
            if r.ok then leaked[#leaked + 1] = name end
        end
    end
    T.check("llm: nothing else on the whitelist runs for the model", #leaked == 0, table.concat(leaked, ", "))
end)
T.step("the GM still can", function()
    local r = run("say", {speaker = "Nobody", text = "The GM speaks.", channel = "log"}, "gm")
    T.check("gm: say accepted", r.ok, r.msg)
    r = run("set_objective", {text = "GM objective"}, "gm")
    T.check("gm: set_objective accepted", r.ok, r.msg)
    T.eq("gm: the objective changed", RT.objective, "GM objective")
end)

-- ── With the director switched off the game does not queue for it ────────────
T.step("director off", function()
    DIR.enabled = false
    local before = #DIR.events
    local n = count("test_off")
    RT.emit("test_off")
    T.eq("off: nothing queued for the director", #DIR.events, before)
    T.eq("off: other listeners still hear it", count("test_off"), n + 1)
    DIR.enabled = true
end)
