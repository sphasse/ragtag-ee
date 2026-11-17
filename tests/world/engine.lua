-- The world plugin engine itself (WORLD): registration, lazy init, per-plugin config with
-- defaults, enable / disable with a fresh state, and isolation (one plugin's error does not
-- stop the others). Uses throw-away plugins; the real ones have their own files in this folder.

T.suite("world")

local calls = {init = 0, update = 0, cleanup = 0}
local P = {
    id = "test_plugin", name = "Test Plugin",
    defaults = {speed = 3, label = "default"},
    init    = function(state) calls.init = calls.init + 1; state.ready = true end,
    update  = function(state, delta, now) calls.update = calls.update + 1; state.ticks = (state.ticks or 0) + 1 end,
    cleanup = function(state) calls.cleanup = calls.cleanup + 1 end,
}
local broken_ticks, after_ticks = 0, 0

T.step("the real plugins are registered and running", function()
    for _, id in ipairs({"sciencedb", "rumors", "defenders", "proximity", "salvage", "traffic"}) do
        T.check("registered: " .. id, WORLD._registry[id] ~= nil)
    end
    for _, id in ipairs({"sciencedb", "rumors", "defenders", "salvage", "traffic"}) do
        T.check("running: " .. id, WORLD.isEnabled(id) and T.world(id)._initialized)
    end
    T.check("tests switch the patrols off unless they ask for them", not WORLD.isEnabled("proximity"))
end)

T.step("register", function()
    WORLD.register(P)
    T.check("register: enabled by default", WORLD.isEnabled("test_plugin"))
    T.eq("register: init has not run yet", calls.init, 0)
    T.check("register: an id is required", not pcall(WORLD.register, {name = "No Id"}))
    T.check("register: a name is required", not pcall(WORLD.register, {id = "no_name"}))
end)
T.wait(0.5)
T.step("lazy init, then an update every frame", function()
    T.eq("init: ran once", calls.init, 1)
    T.check("update: runs every frame", calls.update > 5, calls.update)
    T.check("state: the plugin's own table", T.world("test_plugin").ready and T.world("test_plugin").ticks == calls.update)
end)

T.step("config", function()
    T.eq("config: the plugin's default", WORLD.get("test_plugin", "speed", 99), 3)
    T.eq("config: the caller's fallback for an unknown key", WORLD.get("test_plugin", "missing", 99), 99)
    WORLD.set("test_plugin", "speed", 8)
    T.eq("config: a runtime override wins", WORLD.get("test_plugin", "speed", 99), 8)
    WORLD.set("test_plugin", "speed", false)
    T.eq("config: false is a value, not 'unset'", WORLD.get("test_plugin", "speed", 99), false)
    WORLD.set("no_such_plugin", "speed", 1)
    T.eq("config: an unknown plugin has no settings", WORLD.get("no_such_plugin", "speed", 99), 99)
end)

local ticks_at_disable
T.step("disable", function()
    WORLD.disable("test_plugin")
    T.check("disable: off", not WORLD.isEnabled("test_plugin"))
    T.eq("disable: cleanup ran", calls.cleanup, 1)
    ticks_at_disable = calls.update
end)
T.wait(0.5)
T.step("no updates while off; enable starts fresh", function()
    T.eq("disable: no more updates", calls.update, ticks_at_disable)
    WORLD.enable("test_plugin")
    T.check("enable: on", WORLD.isEnabled("test_plugin"))
    T.check("enable: a fresh state table", T.world("test_plugin").ready == nil)
    T.eq("enable: the override survives", WORLD.get("test_plugin", "speed", 99), false)
end)
T.wait(0.5)
T.step("init ran again", function()
    T.eq("enable: init a second time", calls.init, 2)
    T.check("enable: updating again", calls.update > ticks_at_disable)
    WORLD.enable("test_plugin")
    T.eq("enable: enabling a running plugin does not reset it", calls.init, 2)
    WORLD.disable("test_plugin")
end)

-- ── Isolation ────────────────────────────────────────────────────────────────
T.step("a plugin that throws, registered before one that works", function()
    local logged = T.expectLogged(function()
        WORLD.register({id = "test_broken", name = "Broken",
            update = function() broken_ticks = broken_ticks + 1; error("plugin blew up") end})
        WORLD.register({id = "test_after", name = "After",
            update = function() after_ticks = after_ticks + 1 end})
        WORLD.update(0.016)
        WORLD.update(0.016)
    end)
    T.eq("isolation: the broken plugin was called", broken_ticks, 2)
    T.eq("isolation: the next plugin still ran", after_ticks, 2)
    T.check("isolation: the error is logged, each time", #logged == 2, table.concat(logged, " / "))
    WORLD.disable("test_broken")
    WORLD.disable("test_after")
end)
T.step("a plugin with a default of off", function()
    local ran = false
    WORLD.register({id = "test_off", name = "Off", default_enabled = false, update = function() ran = true end})
    WORLD.update(0.016)
    T.check("default off: not enabled", not WORLD.isEnabled("test_off"))
    T.check("default off: not run", not ran)
end)
