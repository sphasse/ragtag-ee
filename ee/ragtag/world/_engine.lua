-- ee/ragtag/world/_engine.lua
-- World plugin engine: ambient, persistent features that run every session.
-- Plugins are self-contained modules registered here.
-- Load via ee/ragtag/world.lua, not directly.
--
-- Designed to host proximity spawns, station defenders, and any other
-- always-on world behaviour. Each plugin owns a mutable state table
-- and optional default config values overridable at runtime.

WORLD = WORLD or {}

WORLD._registry = {}   -- id -> module
WORLD._state    = {}   -- id -> mutable state table (reset when re-enabled)
WORLD._enabled  = {}   -- id -> bool
WORLD._config   = {}   -- id -> {key=value} runtime overrides
WORLD._order    = {}   -- insertion order for deterministic iteration

-- Register a world plugin. Called by each plugin file at the bottom.
-- Required fields: P.id (string), P.name (string)
-- Optional fields:
--   P.defaults (table)           -- default config values
--   P.default_enabled (bool)     -- if false, starts disabled (default: true)
--   P.init(state)                -- called once before first update
--   P.update(state, delta, now)  -- called every frame
--   P.cleanup(state)             -- called when disabled mid-session
function WORLD.register(P)
    assert(P.id,   "world plugin missing .id")
    assert(P.name, "world plugin missing .name")
    WORLD._registry[P.id]             = P
    WORLD._state[P.id]                = {}
    WORLD._enabled[P.id]              = (P.default_enabled ~= false)
    WORLD._config[P.id]               = {}
    WORLD._order[#WORLD._order + 1]   = P.id
    log("[WORLD] registered plugin: " .. P.id .. " (" .. P.name .. ")")
end

-- Get a config value for a plugin (runtime override > module default > fallback).
function WORLD.get(id, key, fallback)
    local cfg = WORLD._config[id]
    if cfg and cfg[key] ~= nil then return cfg[key] end
    local P = WORLD._registry[id]
    if P and P.defaults and P.defaults[key] ~= nil then return P.defaults[key] end
    return fallback
end

-- Return whether a plugin is currently enabled.
function WORLD.isEnabled(id)
    return WORLD._enabled[id] == true
end

-- Set a runtime config override for a plugin.
function WORLD.set(id, key, value)
    if WORLD._config[id] then WORLD._config[id][key] = value end
end

-- Enable a plugin (re-initialises its state on the next update).
function WORLD.enable(id)
    if not WORLD._registry[id] then return end
    if WORLD._enabled[id] then return end
    WORLD._state[id] = {}   -- fresh state so init() runs again
    WORLD._enabled[id] = true
end

-- Disable a plugin mid-session (calls cleanup if defined).
function WORLD.disable(id)
    local P  = WORLD._registry[id]
    local st = WORLD._state[id]
    if not P then return end
    if P.cleanup then
        local ok, err = pcall(P.cleanup, st)
        if not ok then
            print("[WORLD] " .. id .. " cleanup error: " .. tostring(err))
        end
    end
    WORLD._enabled[id] = false
end

-- Build the "World Plugins..." GM menu entry and its per-plugin submenus.
-- Call once from the scenario's addSessionGMFunctions, passing a callback
-- that re-enters the main GM menu (used by the Back button in the plugin list).
-- Only plugins that define P.gmMenu(addButton, showSelf) appear in the list.
function WORLD.addGMButton(showParent)
    local function showWorldMenu()
        clearGMFunctions()
        addGMFunction("← Back to Main", showParent)
        for _, id in ipairs(WORLD._order) do
            local P = WORLD._registry[id]
            if P.gmMenu then
                local cap_id = id
                addGMFunction(P.name .. "...", function()
                    WORLD.showPluginMenu(cap_id, showWorldMenu)
                end)
            end
        end
    end
    addGMFunction("World Plugins...", showWorldMenu)
end

-- Render one plugin's submenu page (clear + back button + call P.gmMenu).
-- showWorldMenu is the callback that re-enters the World Plugins list.
function WORLD.showPluginMenu(id, showWorldMenu)
    local P = WORLD._registry[id]
    if not P or not P.gmMenu then return end
    clearGMFunctions()
    addGMFunction("← Back to World", showWorldMenu)
    local function showSelf()
        WORLD.showPluginMenu(id, showWorldMenu)
    end
    P.gmMenu(addGMFunction, showSelf)
end

-- Called every frame from the scenario update().
function WORLD.update(delta)
    if not RT.anyPlayerAlive() then return end
    local now = getScenarioTime()
    for _, id in ipairs(WORLD._order) do
        if WORLD._enabled[id] then
            local P  = WORLD._registry[id]
            local st = WORLD._state[id]
            -- Lazy init: runs once before the first update tick.
            if not st._initialized then
                st._initialized = true
                if P.init then
                    local ok, err = pcall(P.init, st)
                    if not ok then
                        print("[WORLD] " .. id .. " init error: " .. tostring(err))
                    end
                end
            end
            if P.update then
                local ok, err = pcall(P.update, st, delta, now)
                if not ok then
                    print("[WORLD] " .. id .. "." .. "update error: " .. tostring(err))
                end
            end
        end
    end
end
