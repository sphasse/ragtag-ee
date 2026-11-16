-- tests/_harness.lua
-- Test harness for story-arc regression tests. Run by tools/game_tests.py, which copies this
-- folder into EmptyEpsilon's scripts/ and starts the real sandbox scenario headless with one
-- test file loaded on top of it. Nothing here is installed into a played game.
--
-- A test file is a plain Lua chunk that queues steps:
--
--     T.arc("ledger")                                   -- the arc under test (others are disabled)
--     T.step("jump to the hook", function()
--         T.jump("hook")
--         T.eq("phase", T.phase(), "hook")
--     end)
--     T.dock("Dustmote Salvage")
--     T.talk("Dustmote Salvage", {"Heard someone here was asking about us."})
--     T.waitFor("Rezkov's station is out", function() return T.find("Rezkov's station") end, 5)
--
-- EmptyEpsilon's Lua has no coroutines, so a test is a queue: T.step / T.wait / T.waitFor / T.dock
-- / T.talk only add to it, and the queue runs one item per frame once the scenario is up. Code
-- that looks at the game must therefore be inside a step function (or a waitFor predicate).
--
-- What is real and what is forced:
--   * Comms are real: T.talk opens a channel from the player ship and picks replies by label, so
--     the arc's own comms functions and station hooks run exactly as in play.
--   * Docking is forced (docking_port.state = "docked"): a real dock needs a collision, which a
--     headless ship with no Helm never gets. isDocked() / getDockedWith() then behave normally.
--   * Movement is teleporting. The player ship is made indestructible and ambient patrols are
--     switched off, so a test never fails because something shot the ship.
--
-- Results go to the log as "[ARCTEST] PASS|FAIL <name>"; "[ARCTEST] DONE" ends the run. Errors the
-- mission engine catches and logs ("[MISSIONS] ... error", non-linear transition warnings) count
-- as failures.

T = {}

local _queue, _qi = {}, 1
local _started, _finished = false, false
local _pass, _fail = 0, 0
local _arc = nil
local _suite = nil
local _replies = {}          -- labels of the comms replies currently on offer
local _wait_until = nil      -- scenario time a wait/waitFor item ends

local function _out(msg) print("[ARCTEST] " .. msg) end

-- ── Assertions ───────────────────────────────────────────────────────────────

function T.check(name, cond, detail)
    if cond then
        _pass = _pass + 1
        _out("PASS " .. name)
    else
        _fail = _fail + 1
        _out("FAIL " .. name .. (detail and (" :: " .. tostring(detail)) or ""))
    end
    return cond and true or false
end

function T.eq(name, got, want)
    return T.check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

-- ── Queue ────────────────────────────────────────────────────────────────────

local function _push(item) _queue[#_queue + 1] = item end

-- Run fn once. An error in fn is a failure; the queue carries on.
function T.step(name, fn) _push({kind = "step", name = name, fn = fn}) end

function T.wait(seconds) _push({kind = "wait", t = seconds}) end

-- Poll pred() every frame until it returns a truthy value; fail after `timeout` seconds.
function T.waitFor(name, pred, timeout) _push({kind = "waitFor", name = name, pred = pred, t = timeout or 10}) end

-- ── Game state ───────────────────────────────────────────────────────────────

function T.P() return RT.players[1] end

function T.arc(id) _arc = id end
-- A test that is not about an arc (the job board): every arc is switched off.
function T.suite(name) _suite = name end
function T.st() return MISSIONS._state[_arc] end
function T.phase() return MISSIONS._cur_phase[_arc] end
function T.status() return MISSIONS._status[_arc] end
function T.flag(name) return RT.flag(name) end
function T.credits() return RT.credits() end
function T.rep(faction) return RT.getReputation(faction) end
function T.now() return getScenarioTime() end

-- Anything with this callsign, anywhere on the map (RT.find only looks 100U around the ship).
function T.find(callsign)
    for _, o in ipairs(getObjectsInRadius(0, 0, 2000000)) do
        local ok, cs = pcall(function() return o:getCallSign() end)
        if ok and cs == callsign and o:isValid() then return o end
    end
    return nil
end

-- Number of valid entities in a list (arc state tables keep lists of spawned ships).
function T.alive(list)
    local n = 0
    for _, e in pairs(list or {}) do if RT.valid(e) then n = n + 1 end end
    return n
end

function T.countType(type_name, x, y, r)
    local n = 0
    for _, o in ipairs(getObjectsInRadius(x, y, r)) do
        if isObjectType(o, type_name) then n = n + 1 end
    end
    return n
end

function T.rumors(category)
    local n = 0
    for _, r in ipairs(RUMORS._injected or {}) do if r.category == category then n = n + 1 end end
    return n
end

function T.jobs(category)
    local n = 0
    for _, e in ipairs(JOBS._injected or {}) do if e.category == category then n = n + 1 end end
    return n
end

-- Arc flags still set (those with one of the arc's GM flag prefixes), as a sorted list.
function T.arcFlags()
    local M = MISSIONS._registry[_arc]
    local prefixes = (M and M.gm_flag_prefixes) or {_arc .. "_"}
    local out = {}
    for name, v in pairs((RT.campaign and RT.campaign.flags) or {}) do
        for _, pre in ipairs(prefixes) do
            if v ~= nil and name:sub(1, #pre) == pre then out[#out + 1] = name; break end
        end
    end
    table.sort(out)
    return out
end

-- ── Acting on the game (call from inside a step) ─────────────────────────────

-- The ship the test drives (moves, docks, talks from): the arc ship unless T.actAs chose another.
-- T.P() is always the arc ship, for assertions.
local _actor = nil
local function A() return _actor or T.P() end
local _resolve

-- A second player ship (another crew working the job board). Returns it; also RT.players[2].
function T.secondShip()
    if RT.valid(RT.players[2]) then return RT.players[2] end
    local x, y = T.P():getPosition()
    local s = RT.spawnPlayer(x - 4000, y, 0, {callsign = "Kestrel"})
    s:setCanBeDestroyed(false)
    return RT.players[2]
end

-- Queue: from here on T.moveTo / T.dock / T.talk drive `ship` (an entity or a function returning
-- one). T.actAs(nil) goes back to the arc ship. Use it to check that an arc ignores other ships.
function T.actAs(ship)
    T.step(ship and "act as another ship" or "act as the arc ship", function()
        if _actor then pcall(function() _actor:commandCloseTextComm() end) end
        _actor = ship and _resolve(ship) or nil
        if ship and not RT.valid(_actor) then error("actAs: no such ship") end
    end)
end

_resolve = function(target)
    if type(target) == "function" then return target() end
    if type(target) == "string" then return T.find(target) end
    return target
end

local function _undockNow()
    local p = A()
    local dp = p.components.docking_port
    if dp and dp.state ~= "not_docking" then p:commandUndock() end
end

function T.moveTo(x, y)
    _undockNow()
    A():setPosition(x, y)
    pcall(function() A():commandImpulse(0) end)
end

function T.moveNear(target, dist)
    local e = _resolve(target)
    if not RT.valid(e) then error("moveNear: no such object: " .. tostring(target)) end
    local x, y = e:getPosition()
    T.moveTo(x + (dist or 2000), y)
end

-- Press one of the arc's GM "->" state buttons by key. "inactive" falls back to the engine's
-- default when the arc does not define its own.
function T.jump(key)
    local M = MISSIONS._registry[_arc]
    for _, g in ipairs(M.gm_states or {}) do
        if g.key == key then g.fn(T.st()); return end
    end
    if key == "inactive" then MISSIONS.gmDeactivate(_arc); return end
    error("no GM state '" .. tostring(key) .. "' on arc " .. tostring(_arc))
end

-- What the next session does: stop the arc (its world is removed, saved flags stay) and start it
-- again, so its start phase routes by the flags. Check T.phase() afterwards.
function T.restart()
    MISSIONS.cancel(_arc)
    MISSIONS.start(_arc)
end

-- Press one of the arc's GM helper buttons by label (only offered in its phases, as in the menu).
function T.action(label)
    local M = MISSIONS._registry[_arc]
    for _, a in ipairs(M.gm_actions or {}) do
        local l = type(a.label) == "function" and a.label(T.st()) or a.label
        if l == label then
            local shown = not a.phases
            for _, ph in ipairs(a.phases or {}) do if ph == T.phase() then shown = true end end
            if not shown then error("GM action '" .. label .. "' is not offered in phase " .. tostring(T.phase())) end
            a.fn(T.st())
            return
        end
    end
    error("no GM action '" .. tostring(label) .. "' on arc " .. tostring(_arc))
end

-- ── Jobs (call from inside a step) ───────────────────────────────────────────

-- Generate a job of one type at a station exactly as the board would (the module's own
-- prepareOpts + generate), without waiting for the random draw to produce that type.
function T.makeJob(jtype, station_cs, tier)
    local mod = JOBS._registry[jtype]
    if not mod then error("no job type " .. tostring(jtype)) end
    for _ = 1, 20 do
        local ctx = JOBS.offerContext(station_cs)
        ctx.tier = tier or 0
        local opts = mod.prepareOpts(ctx)
        if opts then
            local m = mod.generate(opts)
            if m then return m end
        end
    end
    error("could not generate a " .. jtype .. " job at " .. station_cs)
end

-- Put a job on its origin station's board as ordinary work (guaranteed to be listed).
function T.postJob(m)
    JOBS.inject({category = "TEST_JOBS", priority = 3, ensure = true, origin = m.origin, record = m})
    return m
end

-- The active-job entry for a job record (nil once it is completed, failed or expired).
function T.activeEntry(m)
    for _, e in ipairs(JOBS._active) do
        if e.mission == m then return e end
    end
end

-- ── Queued helpers ───────────────────────────────────────────────────────────

-- Take a posted job at its origin station through the real board. `job` is a function returning
-- the record (it does not exist yet when the test file is read). Docks first.
function T.takeJob(job)
    T.dock(function() return T.find(job().origin) end)
    T.talk(function() return T.find(job().origin) end,
           {"Any work available?", function() return "Take: " .. job().short end}, {name = "the origin station"})
end

-- Dock the player ship at a station or ship (callsign, entity, or function returning one).
function T.dock(target)
    T.step("dock at " .. (type(target) == "string" and target or "target"), function()
        local e = _resolve(target)
        if not RT.valid(e) then error("no such object to dock at: " .. tostring(target)) end
        _undockNow()
        local x, y = e:getPosition()
        A():setPosition(x + (_actor and -1500 or 1500), y)
        local dp = A().components.docking_port
        dp.target = e
        dp.state = "docked"
    end)
    T.waitFor("docked", function()
        local e = _resolve(target)
        return RT.valid(e) and A():isDocked(e)
    end, 3)
end

function T.undock()
    T.step("undock", _undockNow)
    T.wait(0.2)
end

local function _commsState()
    local ct = A().components.comms_transmitter
    return ct and tostring(ct.state) or "?"
end

-- The text currently shown in the player's comms window.
function T.msg()
    local ct = A().components.comms_transmitter
    return ct and tostring(ct.incomming_message or "") or ""
end

-- Labels of the replies currently on offer.
function T.replies()
    local out = {}
    for i, l in ipairs(_replies) do out[i] = l end
    return out
end

function T.hasReply(label)
    for _, l in ipairs(_replies) do
        if l:find(label, 1, true) then return true end
    end
    return false
end

-- Hold a conversation: open comms from the player ship to `target`, then pick each reply in
-- `labels` in turn (matched as a plain substring of the button text). The channel stays open so
-- the test can look at T.msg() / T.replies() in a following step; the next T.talk closes it.
--   opts.answer = true: do not open a channel; wait for the target's incoming hail and accept it
--                       (for ships that call openCommsTo on the player).
function T.talk(target, labels, opts)
    opts = opts or {}
    local who = type(target) == "string" and target or (opts.name or "target")
    if opts.answer then
        T.waitFor("hailed by " .. who, function() return A():isCommsBeingHailed() end, opts.timeout or 15)
        T.step("answer the hail", function()
            _replies = {}
            A():commandAnswerCommHail(true)
        end)
    else
        T.step("clear comms", function()
            local p = A()
            if p:isCommsBeingHailed() then p:commandAnswerCommHail(false) end
            p:commandCloseTextComm()
        end)
        T.wait(0.3)
        T.step("hail " .. who, function()
            local e = _resolve(target)
            if not RT.valid(e) then error("no such object to hail: " .. tostring(target)) end
            _replies = {}
            A():commandOpenTextComm(e)
        end)
    end
    T.waitFor("channel open to " .. who, function() return _commsState() == "open" end, 10)
    for _, lbl in ipairs(labels or {}) do
        -- A label may be a function, for text only known when the step runs (a job's name).
        T.step("reply: " .. (type(lbl) == "string" and lbl or "(computed)"), function()
            local label = type(lbl) == "function" and lbl() or lbl
            for i, l in ipairs(_replies) do
                if l:find(label, 1, true) then
                    _replies = {}
                    A():commandSendComm(i - 1)
                    return
                end
            end
            error("no reply '" .. tostring(label) .. "'; on offer: [" .. table.concat(_replies, " | ") .. "]")
        end)
    end
end

function T.closeComms()
    T.step("close comms", function()
        local p = A()
        if p:isCommsBeingHailed() then p:commandAnswerCommHail(false) end
        p:commandCloseTextComm()
    end)
    T.wait(0.3)
end

-- Press every GM state button in turn and check where the arc lands.
--   expect = { {key = "hook", phase = "hook"}, {key = "done_full", done = true, check = function() ... end}, ... }
-- `phase` is the phase the arc must be in right after the jump; `done = true` means status "done".
-- `check` runs a second later (after the phase's update has ticked). Every key in M.gm_states
-- must be listed, so a new GM state cannot be added without a test.
function T.gmWalk(expect)
    T.step("GM walk covers every GM state", function()
        local listed = {}
        for _, e in ipairs(expect) do listed[e.key] = true end
        local missing = {}
        for _, g in ipairs(MISSIONS._registry[_arc].gm_states or {}) do
            if not listed[g.key] then missing[#missing + 1] = g.key end
        end
        T.check("GM walk lists every GM state", #missing == 0, "not walked: " .. table.concat(missing, ", "))
    end)
    for _, e in ipairs(expect) do
        T.step("GM -> " .. e.key, function()
            T.jump(e.key)
            if e.done then
                T.eq("GM -> " .. e.key .. ": status", T.status(), "done")
            elseif e.phase then
                T.eq("GM -> " .. e.key .. ": status", T.status(), "active")
                T.eq("GM -> " .. e.key .. ": phase", T.phase(), e.phase)
            end
        end)
        T.wait(1)
        if e.check then T.step("GM -> " .. e.key .. ": state", e.check) end
    end
end

-- "-> Inactive", then check nothing of the arc is left: no flags (except `opts.keep_flags`), none
-- of the named objects (`opts.gone`), no objective line (`opts.objective` key, default the arc id).
function T.deactivate(opts)
    opts = opts or {}
    T.step("GM -> inactive", function() T.jump("inactive") end)
    T.wait(1)
    T.step("nothing left after -> Inactive", function()
        local keep = {}
        for _, n in ipairs(opts.keep_flags or {}) do keep[n] = true end
        local left = {}
        for _, n in ipairs(T.arcFlags()) do if not keep[n] then left[#left + 1] = n end end
        T.check("inactive: no arc flags left", #left == 0, table.concat(left, ", "))
        for _, cs in ipairs(opts.gone or {}) do
            T.check("inactive: " .. cs .. " removed", T.find(cs) == nil)
        end
        local key = opts.objective or _arc
        T.check("inactive: objective cleared", RT.objectives[key] == nil, tostring(RT.objectives[key]))
        if opts.check then opts.check() end
    end)
end

-- ── Runner ───────────────────────────────────────────────────────────────────

local function _setup()
    if _arc and not MISSIONS._registry[_arc] then
        error("T.arc: no such arc '" .. tostring(_arc) .. "'")
    end
    if not _arc and not _suite then
        error("test did not call T.arc(<arc id>) or T.suite(<name>)")
    end
    for _, id in ipairs(MISSIONS._order) do      -- only the arc under test (none for a job test)
        if id ~= _arc then MISSIONS.setEnabled(id, false) end
    end
    WORLD.disable("proximity")                 -- no ambient patrols or shakedowns
    T.P():setCanBeDestroyed(false)
    _out("START " .. (_arc or _suite))
end

local function _finish()
    _finished = true
    _out(string.format("DONE pass=%d fail=%d", _pass, _fail))
end

local function _tick()
    local now = getScenarioTime()
    if not _started then
        if now < 4 or not RT.valid(T.P()) then return end   -- let the scenario settle
        _started = true
        _setup()
    end
    local item = _queue[_qi]
    if not item then _finish(); return end

    if item.kind == "step" then
        _qi = _qi + 1
        local ok, err = pcall(item.fn)
        if not ok then T.check("step '" .. item.name .. "'", false, err) end
    elseif item.kind == "wait" then
        _wait_until = _wait_until or (now + item.t)
        if now >= _wait_until then _wait_until = nil; _qi = _qi + 1 end
    elseif item.kind == "waitFor" then
        _wait_until = _wait_until or (now + item.t)
        local ok, res = pcall(item.pred)
        if not ok then
            T.check(item.name, false, res)
            _wait_until = nil; _qi = _qi + 1
        elseif res then
            T.check(item.name, true)
            _wait_until = nil; _qi = _qi + 1
        elseif now >= _wait_until then
            T.check(item.name, false, "not within " .. item.t .. "s (phase " .. tostring(T.phase()) .. ")")
            _wait_until = nil; _qi = _qi + 1
        end
    end
end

-- Record the replies on offer (the engine does not expose them to scripts).
local _addCommsReply = addCommsReply
addCommsReply = function(label, cb)
    _replies[#_replies + 1] = tostring(label)
    return _addCommsReply(label, cb)
end

-- Errors the mission engine swallows are failures here.
local _log = log
log = function(msg, ...)
    local s = tostring(msg)
    if s:find("[MISSIONS]", 1, true) and (s:find("error", 1, true) or s:find("WARNING", 1, true)) then
        T.check("no mission engine errors", false, s)
    end
    return _log(msg, ...)
end

-- Every flag set or cleared in an arc's namespace must be declared by that arc (M.flags).
local function _guardFlag(name)
    if type(name) ~= "string" then return end
    if MISSIONS.flagNamespace(name) and not MISSIONS.flagOwner(name) then
        T.check("flag '" .. name .. "' is declared", false,
            "written at run time but in no arc's M.flags (typo, or add it to " .. MISSIONS.flagNamespace(name) .. ")")
    end
end
local _flag, _clearFlag = RT.flag, RT.clearFlag
RT.flag = function(name, value)
    if value ~= nil then _guardFlag(name) end
    return _flag(name, value)
end
RT.clearFlag = function(name)
    _guardFlag(name)
    return _clearFlag(name)
end

local _update = update
function update(delta)
    _update(delta)
    if _finished then return end
    local ok, err = pcall(_tick)
    if not ok then
        T.check("harness", false, err)
        _finish()
    end
end
