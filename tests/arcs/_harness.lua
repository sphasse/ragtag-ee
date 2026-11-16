-- tests/arcs/_harness.lua
-- Test harness for story-arc regression tests. Run by tools/arc_tests.py, which copies this
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

local function _resolve(target)
    if type(target) == "function" then return target() end
    if type(target) == "string" then return T.find(target) end
    return target
end

local function _undockNow()
    local p = T.P()
    local dp = p.components.docking_port
    if dp and dp.state ~= "not_docking" then p:commandUndock() end
end

function T.moveTo(x, y)
    _undockNow()
    T.P():setPosition(x, y)
    pcall(function() T.P():commandImpulse(0) end)
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

-- ── Queued helpers ───────────────────────────────────────────────────────────

-- Dock the player ship at a station or ship (callsign, entity, or function returning one).
function T.dock(target)
    T.step("dock at " .. (type(target) == "string" and target or "target"), function()
        local e = _resolve(target)
        if not RT.valid(e) then error("no such object to dock at: " .. tostring(target)) end
        _undockNow()
        local x, y = e:getPosition()
        T.P():setPosition(x + 1500, y)
        local dp = T.P().components.docking_port
        dp.target = e
        dp.state = "docked"
    end)
    T.waitFor("docked", function()
        local e = _resolve(target)
        return RT.valid(e) and T.P():isDocked(e)
    end, 3)
end

function T.undock()
    T.step("undock", _undockNow)
    T.wait(0.2)
end

local function _commsState()
    local ct = T.P().components.comms_transmitter
    return ct and tostring(ct.state) or "?"
end

-- The text currently shown in the player's comms window.
function T.msg()
    local ct = T.P().components.comms_transmitter
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
        T.waitFor("hailed by " .. who, function() return T.P():isCommsBeingHailed() end, opts.timeout or 15)
        T.step("answer the hail", function()
            _replies = {}
            T.P():commandAnswerCommHail(true)
        end)
    else
        T.step("clear comms", function()
            local p = T.P()
            if p:isCommsBeingHailed() then p:commandAnswerCommHail(false) end
            p:commandCloseTextComm()
        end)
        T.wait(0.3)
        T.step("hail " .. who, function()
            local e = _resolve(target)
            if not RT.valid(e) then error("no such object to hail: " .. tostring(target)) end
            _replies = {}
            T.P():commandOpenTextComm(e)
        end)
    end
    T.waitFor("channel open to " .. who, function() return _commsState() == "open" end, 10)
    for _, label in ipairs(labels or {}) do
        T.step("reply: " .. label, function()
            for i, l in ipairs(_replies) do
                if l:find(label, 1, true) then
                    _replies = {}
                    T.P():commandSendComm(i - 1)
                    return
                end
            end
            error("no reply '" .. label .. "'; on offer: [" .. table.concat(_replies, " | ") .. "]")
        end)
    end
end

function T.closeComms()
    T.step("close comms", function()
        local p = T.P()
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
    if not _arc or not MISSIONS._registry[_arc] then
        error("test did not call T.arc(<registered arc id>)")
    end
    for _, id in ipairs(MISSIONS._order) do
        if id ~= _arc then MISSIONS.setEnabled(id, false) end
    end
    WORLD.disable("proximity")                 -- no ambient patrols or shakedowns
    T.P():setCanBeDestroyed(false)
    _out("START " .. _arc)
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
