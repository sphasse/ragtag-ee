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
-- The last ship-log announcement SCIDB made, and how many it has made.
local function last() return SCIDB.announced[#SCIDB.announced] end
local function count() return #SCIDB.announced end
local function top_names()
    local out = {}
    for _, t in ipairs(getScienceDatabases()) do out[t:getName()] = (out[t:getName()] or 0) + 1 end
    return out
end

T.step("setup", function()
    T.check("setup: the plugin is running", WORLD.isEnabled("sciencedb") and T.world("sciencedb")._initialized)
    T.eq("announce: building the database (session start) is quiet", count(), 0)
end)

-- ── The sections ─────────────────────────────────────────────────────────────
T.step("the Drift's sections are there", function()
    for _, key in ipairs({"root", "regions", "factions", "ports", "people", "records", "briefings"}) do
        T.check("sections: " .. key, SCIDB.get(key) ~= nil)
    end
    local tops = top_names()
    T.eq("sections: one Factions section (the Drift's; the stock one is removed)", tops["Factions"], 1)
    T.check("sections: stock Ships help is kept", tops["Ships"] ~= nil)
    T.check("sections: the stock Stations section is removed (the Drift's are in Ports)", tops["Stations"] == nil)
    local facs = child_names("factions")
    for _, f in ipairs({"Concord", "Corsairs", "Independent", "Relic", "Hollow"}) do
        T.check("factions: " .. f, facs[f])
    end
    T.check("factions: no stock factions", not facs["Human Navy"] and not facs["Exuari"])
end)
T.step("People, Records and Mission Briefings replace Lore", function()
    local tops = top_names()
    T.check("sections: no Lore any more", tops["Lore"] == nil)
    for _, n in ipairs({"People", "Records", "Mission Briefings"}) do T.eq("sections: one " .. n, tops[n], 1) end
    T.check("records: the Settlement War is a record", child_names("records")["The Settlement War"])
    T.check("records: Ashgrave Research is a record", child_names("records")["Ashgrave Research"])
end)
T.step("Ships keeps only the ships the game uses", function()
    local ships, classes = {}, 0
    for _, top in ipairs(getScienceDatabases()) do
        if top:getName() == "Ships" then
            for _, class in ipairs(top:getEntries()) do
                classes = classes + 1
                T.check("ships: no empty hull class (" .. class:getName() .. ")", #class:getEntries() > 0)
                for _, s in ipairs(class:getEntries()) do ships[s:getName()] = true end
            end
        end
    end
    local used = {}
    for _, shown in pairs(SCIDB.SHIPS_USED) do used[shown] = true end
    used["Light Freighter"] = true               -- the crew's ship: its own entry (SCIDB.addFreighterEntry)
    local n = 0
    for name in pairs(ships) do
        n = n + 1
        T.check("ships: " .. name .. " is used by the game", used[name])
    end
    for _, name in ipairs({"Adder MK5", "MT52 Hornet", "Atlantis X23", "Phobos T3", "Tug"}) do
        T.check("ships: kept " .. name, ships[name])
    end
    for _, name in ipairs({"Ktlitan Drone", "Odin", "Transport1x1", "Transport 1x1"}) do
        T.check("ships: dropped " .. name, not ships[name])
    end
    T.check("ships: a few dozen, not EE's 150", n > 10 and n <= 40, tostring(n))
    T.check("ships: the Light Freighter has an entry", ships["Light Freighter"])
end)
T.step("the Light Freighter's entry", function()
    local e = SCIDB.addFreighterEntry()          -- already there: returns it, adds no second one
    T.check("freighter: found", e ~= nil)
    if not e then return end
    T.check("freighter: the crew's ship", e:getLongDescription():find("The crew's own ship", 1, true) == 1)
    T.check("freighter: names coolant among the upgrades", e:getLongDescription():find("reactor and coolant", 1, true) ~= nil)
    for _, k in ipairs({"Class", "Hull", "Shield", "Move speed", "Turn speed", "Warp speed"}) do
        local v = e:getKeyValue(k)
        T.check("freighter: " .. k, v ~= nil and v ~= "", tostring(v))
    end
    local flavia
    for _, top in ipairs(getScienceDatabases()) do
        if top:getName() == "Ships" then
            for _, class in ipairs(top:getEntries()) do
                local n = 0
                for _, s in ipairs(class:getEntries()) do
                    if s:getName() == "Light Freighter" then n = n + 1 end
                    if s:getName() == "Flavia P.Falcon" then flavia = s end
                end
                if n > 0 then T.eq("freighter: one entry, beside the Flavia P.Falcon", n, flavia and 1 or -1) end
            end
        end
    end
    T.eq("freighter: same hull as the Flavia P.Falcon", e:getKeyValue("Hull"), flavia and flavia:getKeyValue("Hull"))
end)
T.step("the Regions section and each region entry have a map", function()
    T.eq("maps: the Drift on the Regions section", SCIDB.get("regions"):getImage(), "ragtag/img/maps/drift.png")
    local n = 0
    for key, img in pairs(SCIDB.REGION_MAPS) do
        n = n + 1
        T.eq("maps: " .. key, SCIDB.get(key) and SCIDB.get(key):getImage(), img)
    end
    T.eq("maps: ten (the Drift and nine regions)", n, 10)
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

-- ── Ship Upgrades: the catalogue rolled up ───────────────────────────────────
T.step("the Ship Upgrades section", function()
    T.eq("upgrades: a top-level section", top_names()["Ship Upgrades"], 1)
    local intro = desc("upgrades") or ""
    T.check("upgrades: says how to buy", intro:find("open Shipwright", 1, true) ~= nil, intro)
    local listed = {}
    for _, line in ipairs(RT.UPGRADE_LINES) do
        local text = desc("upgrades_" .. line.id)
        T.check("upgrades: an entry for " .. line.id, text ~= nil)
        text = text or ""
        for _, u in ipairs(RT.UPGRADES) do
            if u.line == line.id then
                local cost = u.cost >= 1000 and string.format("%d,%03d cr", u.cost // 1000, u.cost % 1000) or (u.cost .. " cr")
                local has = text:find(u.name .. ", " .. cost, 1, true) ~= nil and text:find(u.desc, 1, true) ~= nil
                T.check("upgrades: " .. u.id .. " with its price and effect", has, text)
                if has then listed[u.id] = true end
                if u.requires then
                    T.check("upgrades: " .. u.id .. " says what it needs",
                        text:find("(needs " .. RT.upgradeNeedsText(u) .. ")", 1, true) ~= nil)
                end
                for _, d in ipairs(VERSE.STATIONS) do
                    if RT.stocks(d, u.id) and not SCIDB.PORT_EXCLUDE_FACTIONS[d.fac] then
                        T.check("upgrades: " .. u.id .. " fitted at " .. d.cs, text:find(d.cs, 1, true) ~= nil)
                    end
                end
            end
        end
    end
    for _, u in ipairs(RT.UPGRADES) do T.check("upgrades: every upgrade is listed: " .. u.id, listed[u.id]) end
    local hull = desc("upgrades_hull") or ""
    T.check("upgrades: Port Vesper fits hull, with its grid", hull:find("Port Vesper (", 1, true) ~= nil, hull)
    T.check("upgrades: Lumen Exchange does not", hull:find("Lumen Exchange", 1, true) == nil, hull)
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
    T.check("announce: an unlock tells Relay where", last() ~= nil
        and last():find("^%[Science%] Database entry updated: Regions > ") ~= nil
        and last():find("Maw", 1, true) ~= nil, tostring(last()))
    local n = count()
    SCIDB.unlock("maw_full")
    T.check("lock: unlocking twice is harmless", L.unlocked)
    T.eq("announce: not twice", count(), n)
    SCIDB.relock("maw_full")
    T.eq("lock: relocking hides it again", desc("region_maw"), locked_text)
    SCIDB.unlock("no_such_key")
    SCIDB.relock("no_such_key")
    T.check("lock: unknown keys are ignored", true)
end)

-- ── Entries added at run time ────────────────────────────────────────────────
T.step("a mission adds an entry", function()
    local e = SCIDB.addEntry("records", "Test Finding", "What the crew found.", {["Source"] = "a test"})
    T.check("add: created under Records", e ~= nil and child_names("records")["Test Finding"])
    T.eq("add: its text", e:getLongDescription(), "What the crew found.")
    T.eq("add: its key/value", e:getKeyValue("Source"), "a test")
    T.eq("announce: a new entry and where it is", last(), "[Science] Database entry added: Records > Test Finding.")
    SCIDB._entries["test_finding"] = e
    T.check("remove: done", SCIDB.removeEntry("test_finding"))
    T.check("remove: gone from Records", not child_names("records")["Test Finding"])
    T.check("remove: twice is a no-op", SCIDB.removeEntry("test_finding") == false)
    local logged = T.expectLogged(function() return SCIDB.addEntry("no_such_parent", "X", "x") end)
    T.check("add: an unknown parent is refused", SCIDB.get("no_such_parent") == nil)
end)
T.step("a locked entry added at run time", function()
    local e = SCIDB.addEntry("records", "Test Secret", "The real story.", {["Rating"] = "high"}, "test_secret", "[ sealed ]")
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
    T.check("profile: under People", child_names("people")["Thresh"])
    T.eq("announce: a profile", last(), "[Science] Database entry added: People > Thresh.")
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
    T.check("sync: the entry is gone from People", not child_names("people")["Thresh"])
    RT.flag("rezkov_met_thresh", true)
    local n = count()
    SCIDB.sync()
    T.check("sync: a flag set elsewhere (a loaded save) brings the profile back", SCIDB.get("thresh_profile") ~= nil)
    T.eq("announce: sync restores quietly", count(), n)
    RT.clearFlag("rezkov_met_thresh")
    SCIDB.sync()
end)

-- ── Rules ────────────────────────────────────────────────────────────────────
local on = false
T.step("a rule ties an entry to a condition", function()
    SCIDB.rule("test_rule_entry", {
        want = function() return on end,
        add  = function() SCIDB._entries["test_rule_entry"] = SCIDB.addEntry("records", "Test Rule Entry", "Exists while wanted.") end,
    })
    SCIDB.sync()
    T.check("rule: absent while not wanted", SCIDB.get("test_rule_entry") == nil)
    on = true; SCIDB.sync()
    T.check("rule: added when wanted", SCIDB.get("test_rule_entry") ~= nil and child_names("records")["Test Rule Entry"])
    SCIDB.sync()
    local n = 0
    for _, c in ipairs(SCIDB.get("records"):getEntries()) do if c:getName() == "Test Rule Entry" then n = n + 1 end end
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

-- Every key/value fits the Science screen's narrow column (playtest: Rezkov's "Method" ran into
-- the description): built entries (SCIDB.kv_set), locked ones' hidden values, every profile.
T.step("key/values fit the Science screen", function()
    local all = {}
    for _, e in ipairs(SCIDB.kv_set) do all[#all + 1] = {e.path, e.key, e.value} end
    for lk, L in pairs(SCIDB._locked) do
        for k, v in pairs(L.kv or {}) do all[#all + 1] = {"locked " .. lk, k, tostring(v)} end
    end
    for pk, p in pairs(SCIDB.PROFILES) do
        for k, v in pairs(p.kv or {}) do all[#all + 1] = {"profile " .. pk, k, tostring(v)} end
    end
    T.check("kv: there are key/values to check", #all > 20, #all)
    for _, e in ipairs(all) do
        if #e[3] > SCIDB.KV_VALUE_MAX or #e[2] > SCIDB.KV_KEY_MAX then
            T.check(string.format("kv fits: %s: %s = %s (%d)", e[1], e[2], e[3], #e[3]), false)
        end
    end
end)

-- ── The Science pop-up ───────────────────────────────────────────────────────
-- Everything announced also pops up on Science, Operations and Single Pilot; entries that change
-- within a second share one pop-up; quiet restores pop nothing up.
local popups0
T.wait(1.5)   -- let the pop-ups from the steps above go out
T.step("two entries at once", function()
    popups0 = #SCIDB.popups
    T.eq("pop-up: nothing waiting", #SCIDB._pending, 0)
    SCIDB.addEntry("records", "Test Popup One", "First.")
    SCIDB.addEntry("records", "Test Popup Two", "Second.", nil, "test_popup_two", "[ sealed ]")
    SCIDB.unlock("test_popup_two")
    T.eq("pop-up: not shown at once (gathering)", #SCIDB.popups, popups0)
end)
T.wait(1.5)
T.step("one pop-up for both", function()
    T.eq("pop-up: one pop-up", #SCIDB.popups, popups0 + 1)
    local text = SCIDB.popups[#SCIDB.popups] or ""
    T.check("pop-up: a heading", text:find("Science database updated:", 1, true) == 1, text)
    T.check("pop-up: the new entry, with its place", text:find("New: Records > Test Popup One", 1, true) ~= nil, text)
    T.check("pop-up: the revealed entry", text:find("Updated: Records > Test Popup Two", 1, true) ~= nil, text)
    T.eq("pop-up: the consoles", table.concat(SCIDB.POPUP_CONSOLES, ","), "Science,Operations,SinglePilot")
    SCIDB.quietly(function() SCIDB.addEntry("records", "Test Popup Quiet", "Restored.") end)
end)
T.wait(1.5)
T.step("a quiet restore pops nothing up", function()
    T.eq("pop-up: quiet adds no pop-up", #SCIDB.popups, popups0 + 1)
    T.eq("pop-up: and nothing waiting", #SCIDB._pending, 0)
end)
