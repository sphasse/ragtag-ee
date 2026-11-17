-- The Science database: the Drift's own sections, locked entries that unlock (and relock),
-- entries added at run time, character profiles the crew meets, and SCIDB.sync, which makes the
-- database follow the campaign flags (after a GM jump back, an entry the story no longer
-- supports goes away).
--
-- Not covered: what the Science screen draws (only the entries and their text are checked).

T.suite("world")

local function desc(key)
    local e = SCIDB.get(key)
    return e and e:getLongDescription() or nil
end
local function child_names(key)
    local out = {}
    for _, c in ipairs(SCIDB.get(key):getEntries()) do out[c:getName()] = true end
    return out
end
local function top_names()
    local out = {}
    for _, t in ipairs(getScienceDatabases()) do out[t:getName()] = (out[t:getName()] or 0) + 1 end
    return out
end

T.step("setup", function()
    T.check("setup: the plugin is running", WORLD.isEnabled("sciencedb") and T.world("sciencedb")._initialized)
end)

-- ── The sections ─────────────────────────────────────────────────────────────
T.step("the Drift's sections are there", function()
    for _, key in ipairs({"root", "regions", "factions", "ports", "lore"}) do
        T.check("sections: " .. key, SCIDB.get(key) ~= nil)
    end
    local tops = top_names()
    T.eq("sections: one Factions section (the Drift's; the stock one is removed)", tops["Factions"], 1)
    T.check("sections: stock Ships help is kept", tops["Ships"] ~= nil)
    local facs = child_names("factions")
    for _, f in ipairs({"Concord", "Corsairs", "Independent", "Relic", "Hollow"}) do
        T.check("factions: " .. f, facs[f])
    end
    T.check("factions: no stock factions", not facs["Human Navy"] and not facs["Exuari"])
end)
T.step("one port entry per friendly station", function()
    for _, d in ipairs(VERSE.STATIONS) do
        local hostile = (d.fac == "Corsairs" or d.fac == "Hollow")
        if SCIDB.get("port_" .. d.cs) then
            T.check("ports: " .. d.cs, true)
        elseif not hostile then
            T.check("ports: " .. d.cs, false, "no entry for a " .. d.fac .. " station")
        end
    end
    T.check("ports: Port Vesper is described", #(desc("port_Port Vesper") or "") > 20)
end)

-- ── Locked entries ───────────────────────────────────────────────────────────
local locked_text
T.step("a locked entry", function()
    local L = SCIDB._locked["maw_full"]
    T.check("lock: the Maw entry starts locked", L ~= nil and not L.unlocked)
    locked_text = desc("region_maw")
    T.check("lock: it shows a placeholder, not the real text", locked_text ~= L.description)
    SCIDB.unlock("maw_full")
    T.eq("lock: unlocking reveals the text", desc("region_maw"), L.description)
    SCIDB.unlock("maw_full")
    T.check("lock: unlocking twice is harmless", L.unlocked)
    SCIDB.relock("maw_full")
    T.eq("lock: relocking hides it again", desc("region_maw"), locked_text)
    SCIDB.unlock("no_such_key")
    SCIDB.relock("no_such_key")
    T.check("lock: unknown keys are ignored", true)
end)

-- ── Entries added at run time ────────────────────────────────────────────────
T.step("a mission adds an entry", function()
    local e = SCIDB.addEntry("lore", "Test Finding", "What the crew found.", {["Source"] = "a test"})
    T.check("add: created under Lore", e ~= nil and child_names("lore")["Test Finding"])
    T.eq("add: its text", e:getLongDescription(), "What the crew found.")
    T.eq("add: its key/value", e:getKeyValue("Source"), "a test")
    SCIDB._entries["test_finding"] = e
    T.check("remove: done", SCIDB.removeEntry("test_finding"))
    T.check("remove: gone from Lore", not child_names("lore")["Test Finding"])
    T.check("remove: twice is a no-op", SCIDB.removeEntry("test_finding") == false)
    local logged = T.expectLogged(function() return SCIDB.addEntry("no_such_parent", "X", "x") end)
    T.check("add: an unknown parent is refused", SCIDB.get("no_such_parent") == nil)
end)
T.step("a locked entry added at run time", function()
    local e = SCIDB.addEntry("lore", "Test Secret", "The real story.", {["Rating"] = "high"}, "test_secret", "[ sealed ]")
    T.eq("add locked: placeholder shown", e:getLongDescription(), "[ sealed ]")
    SCIDB.unlock("test_secret")
    T.eq("add locked: unlock reveals", e:getLongDescription(), "The real story.")
    T.eq("add locked: and its data", e:getKeyValue("Rating"), "high")
    SCIDB._entries["test_secret"] = e
    SCIDB.removeEntry("test_secret")
    SCIDB._locked["test_secret"] = nil
end)

-- ── Profiles: people the crew has met ────────────────────────────────────────
T.step("meeting someone", function()
    T.check("profile: unknown before the meeting", SCIDB.get("thresh_profile") == nil and not SCIDB.known("thresh_profile"))
    T.check("profile: first meeting adds the entry", SCIDB.meet("rezkov", "thresh_profile") == true)
    T.check("profile: under Lore", child_names("lore")["Thresh"])
    T.check("profile: remembered in a campaign flag", T.flag("rezkov_met_thresh") == true)
    T.check("profile: meeting again adds nothing", SCIDB.meet("rezkov", "thresh_profile") == false)
    T.check("profile: nobody by that name", SCIDB.meet("rezkov", "no_such_profile") == false)
end)
T.step("the database follows the flags", function()
    SCIDB.meet("ledger", "thresh_profile")              -- met again in another arc
    RT.clearFlag("rezkov_met_thresh")
    SCIDB.sync()
    T.check("sync: still known through the other arc", SCIDB.get("thresh_profile") ~= nil)
    RT.clearFlag("ledger_met_thresh")
    SCIDB.sync()
    T.check("sync: forgotten once no arc remembers the meeting", SCIDB.get("thresh_profile") == nil)
    T.check("sync: the entry is gone from Lore", not child_names("lore")["Thresh"])
    RT.flag("rezkov_met_thresh", true)
    SCIDB.sync()
    T.check("sync: a flag set elsewhere (a loaded save) brings the profile back", SCIDB.get("thresh_profile") ~= nil)
    RT.clearFlag("rezkov_met_thresh")
    SCIDB.sync()
end)

-- ── Rules ────────────────────────────────────────────────────────────────────
local on = false
T.step("a rule ties an entry to a condition", function()
    SCIDB.rule("test_rule_entry", {
        want = function() return on end,
        add  = function() SCIDB._entries["test_rule_entry"] = SCIDB.addEntry("lore", "Test Rule Entry", "Exists while wanted.") end,
    })
    SCIDB.sync()
    T.check("rule: absent while not wanted", SCIDB.get("test_rule_entry") == nil)
    on = true; SCIDB.sync()
    T.check("rule: added when wanted", SCIDB.get("test_rule_entry") ~= nil and child_names("lore")["Test Rule Entry"])
    SCIDB.sync()
    local n = 0
    for _, c in ipairs(SCIDB.get("lore"):getEntries()) do if c:getName() == "Test Rule Entry" then n = n + 1 end end
    T.eq("rule: not added twice", n, 1)
    on = false; SCIDB.sync()
    T.check("rule: removed when no longer wanted", SCIDB.get("test_rule_entry") == nil)
end)
T.step("a rule on a locked entry", function()
    SCIDB.rule("maw_full", {lock = true, want = function() return on end})
    on = true; SCIDB.sync()
    T.check("rule: unlocks while wanted", SCIDB._locked["maw_full"].unlocked)
    on = false; SCIDB.sync()
    T.check("rule: relocks otherwise", not SCIDB._locked["maw_full"].unlocked)
    T.eq("rule: placeholder is back", desc("region_maw"), locked_text)
    SCIDB._rules["maw_full"] = nil
    SCIDB._rules["test_rule_entry"] = nil
end)
