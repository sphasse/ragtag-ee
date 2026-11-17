-- Rumors: what stations and freighters say to "any news?". The background pool and its
-- per-source cooldown, injected seeds (foreshadowing) and hooks (quest leads), the faction
-- filter, tell-once rumors, removal by category, and the plugin switch.

T.suite("world")

local function in_list(list, text)
    for _, t in ipairs(list) do if t == text then return true end end
    return false
end
local function is_pool(text) return in_list(RUMORS.pool, text) end
local function is_no_news(text) return in_list(RUMORS.no_news, text) end
local n = 0
local function fresh_source() n = n + 1; return "Test Source " .. n end

T.step("setup", function()
    T.check("setup: the plugin is running", WORLD.isEnabled("rumors"))
    T.check("setup: a pool of background rumors", #RUMORS.pool >= 100, #RUMORS.pool)
    T.eq("setup: nothing injected (every arc is off)", #RUMORS._injected, 0)
end)

-- ── Background chatter and its cooldown ──────────────────────────────────────
T.step("background", function()
    local first = RUMORS.get("Asker One", "Independent")
    T.check("pool: a first ask gets a background rumor", is_pool(first), first)
    local again = RUMORS.get("Asker One", "Independent")
    T.check("cooldown: the same asker gets 'no news' straight after", is_no_news(again), again)
    local other = RUMORS.get("Asker Two", "Independent")
    T.check("cooldown: it is per asker", is_pool(other), other)
    T.check("pool: no repeat until the pool is used up", other ~= first)
    RUMORS._cooldowns["Asker One"] = T.now() - RUMORS.COOLDOWN_SECONDS - 1
    local later = RUMORS.get("Asker One", "Independent")
    T.check("cooldown: five minutes later there is news again", is_pool(later), later)
end)
T.step("the whole pool is told before any repeat", function()
    local seen, repeats = {}, 0
    for _ = 1, #RUMORS.pool do
        local t = RUMORS.get(fresh_source(), "Independent")
        if seen[t] then repeats = repeats + 1 end
        seen[t] = true
    end
    T.check("pool: at most the few already told above repeat in a full cycle", repeats <= 3, repeats)
end)

-- ── Hooks: quest leads ───────────────────────────────────────────────────────
local hook, concord_hook
T.step("a hook replaces the chatter", function()
    hook = RUMORS.add({text = "HOOK: someone at Dustmote is asking for you.", priority = 5, category = "TEST_HOOK"})
    T.check("hook: add returns an id", hook ~= nil)
    for i = 1, 5 do
        T.eq("hook: told every time, ask " .. i, RUMORS.get("Asker One", "Independent"), "HOOK: someone at Dustmote is asking for you.")
    end
    T.eq("hook: any faction's stations tell it", RUMORS.get(fresh_source(), "Concord"), "HOOK: someone at Dustmote is asking for you.")
end)
T.step("faction filter", function()
    RUMORS.remove(hook)
    concord_hook = RUMORS.add({text = "HOOK: Concord only.", priority = 5, faction = "Concord", category = "TEST_HOOK"})
    T.eq("faction: told at Concord stations", RUMORS.get(fresh_source(), "Concord"), "HOOK: Concord only.")
    local elsewhere = RUMORS.get(fresh_source(), "Independent")
    T.check("faction: not told elsewhere", elsewhere ~= "HOOK: Concord only.", elsewhere)
end)
T.step("the higher priority wins", function()
    RUMORS.add({text = "HOOK: urgent.", priority = 7, category = "TEST_HOOK"})
    for i = 1, 5 do
        T.eq("priority: the urgent hook, ask " .. i, RUMORS.get(fresh_source(), "Concord"), "HOOK: urgent.")
    end
end)
T.step("removal by category", function()
    T.eq("category: three hooks were added, two remain", T.rumors("TEST_HOOK"), 2)
    RUMORS.removeCategory("TEST_HOOK")
    T.eq("category: all removed", T.rumors("TEST_HOOK"), 0)
    T.check("category: chatter is back", is_pool(RUMORS.get(fresh_source(), "Concord")))
    T.check("remove: an unknown id is a no-op", RUMORS.remove("no_such_rumor") == false)
end)
T.step("a tell-once hook", function()
    RUMORS.add({text = "HOOK: said once.", priority = 5, once = true, category = "TEST_ONCE"})
    T.eq("once: told", RUMORS.get(fresh_source(), "Independent"), "HOOK: said once.")
    T.eq("once: then removed", T.rumors("TEST_ONCE"), 0)
    T.check("once: not told again", RUMORS.get(fresh_source(), "Independent") ~= "HOOK: said once.")
end)

-- ── Seeds: foreshadowing mixed into the chatter ──────────────────────────────
T.step("seeds", function()
    local weight = RUMORS.SEED_WEIGHT
    RUMORS.SEED_WEIGHT = 1e9          -- a seed is always drawn when one is unheard
    RUMORS.add({text = "SEED: one.", priority = 3, category = "TEST_SEED"})
    RUMORS.add({text = "SEED: two.", priority = 3, category = "TEST_SEED"})
    local a = RUMORS.get(fresh_source(), "Independent")
    local b = RUMORS.get(fresh_source(), "Independent")
    T.check("seed: both are heard before either repeats",
        (a == "SEED: one." and b == "SEED: two.") or (a == "SEED: two." and b == "SEED: one."), a .. " / " .. b)
    local c = RUMORS.get(fresh_source(), "Independent")
    T.check("seed: then they come round again", c == "SEED: one." or c == "SEED: two.", c)
    local src = fresh_source()
    RUMORS.get(src, "Independent")
    T.check("seed: seeds respect the cooldown (hooks do not)", is_no_news(RUMORS.get(src, "Independent")))
    RUMORS.SEED_WEIGHT = 0
    T.check("seed: with no weight only chatter is told", is_pool(RUMORS.get(fresh_source(), "Independent")))
    RUMORS.SEED_WEIGHT = weight
    RUMORS.removeCategory("TEST_SEED")
end)

-- ── Through real comms ───────────────────────────────────────────────────────
T.step("a hook is waiting at Port Vesper", function()
    RUMORS.add({text = "HOOK: ask at the dock.", priority = 5, category = "TEST_COMMS"})
end)
T.talk("Port Vesper", {"Any news worth hearing?"})
T.step("the station tells it", function()
    T.check("comms: the station passes the hook on", T.msg():find("HOOK: ask at the dock.", 1, true) ~= nil, T.msg())
end)

-- ── Off ──────────────────────────────────────────────────────────────────────
T.step("plugin off", function() WORLD.disable("rumors") end)
T.talk("Port Vesper", {"Any news worth hearing?"})
T.step("stations have nothing to say", function()
    T.check("off: RUMORS.get answers nil", RUMORS.get(fresh_source(), "Independent") == nil)
    T.check("off: the station says so", T.msg():find("Nothing worth repeating", 1, true) ~= nil, T.msg())
    T.eq("off: injected rumors are dropped", #RUMORS._injected, 0)
    WORLD.enable("rumors")
end)
T.wait(0.5)
T.step("on again", function()
    T.check("on: chatter is back", is_pool(RUMORS.get(fresh_source(), "Independent")))
end)
T.closeComms()
