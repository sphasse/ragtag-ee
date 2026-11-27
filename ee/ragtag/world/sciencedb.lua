-- ee/ragtag/world/sciencedb.lua
-- Science station encyclopedia for the Drift universe.
-- Runs in init(): removes the stock sections listed in SCIDB.REMOVE_STOCK (EE builds the stock
-- database before the scenario starts), then builds the Drift's top-level sections: "The Drift"
-- (overview), Factions, Regions, Ports (one entry per friendly/neutral universe station, from
-- VERSE.STATIONS), Ship Upgrades, Achievements, People, Records and Mission Briefings, beside the stock
-- Natural, Technologies, Weapons and Ships (Ships cut to the templates the game uses).
--
-- API:
--   SCIDB.unlock(key)              -- reveal a locked entry
--   SCIDB.get(key)                 -- return entry handle for further edits
--   SCIDB.addEntry(parent_key, name, desc, kv, lock_key, locked_desc)
--                                  -- add a child entry at runtime (missions use this)
--   SCIDB.meet(arc_id, profile_key) -- the crew met someone: flag "<arc>_met_<who>", add profile
--   SCIDB.rule(key, spec)          -- tie a locked entry or a runtime entry to campaign flags
--   SCIDB.sync()                   -- make the database match the flags (session start, GM jumps)
--   SCIDB.quietly(fn)              -- run fn without the ship-log announcements (a restore, not news)
--
-- Every entry added (SCIDB.addEntry, profiles) or revealed (SCIDB.unlock) during play is announced
-- in the ship log, where Relay sees it, with where it is: "[Science] Database entry added: People >
-- Thresh.", and as a pop-up on Science, Operations and Single Pilot ("Science database updated:
-- New: People > Thresh"; entries within a second share one pop-up). Building the database and
-- SCIDB.sync (restoring what a save already earned) are quiet: no log line, no pop-up.
-- Arcs therefore never write their own "database updated" lines; a narrative line ("Survivor
-- records received.") goes before the change, so it reads first.
--
-- State rule: every arc-dependent entry is derived from campaign flags. Profiles exist while any
-- "<arc>_met_<who>" flag is set; rules say when a locked entry is unlocked or a runtime entry
-- exists. Arcs add entries as the story happens (with their log lines); SCIDB.sync() then
-- removes, re-adds, locks or unlocks whatever no longer matches, e.g. after a GM jump back.

SCIDB = SCIDB or {}

SCIDB._entries = {}   -- key → ScienceDatabase handle
SCIDB._locked  = {}   -- key → {entry, description, kv, locked_desc, on_unlock, unlocked}
SCIDB._rules   = SCIDB._rules or {}   -- key → spec (see SCIDB.rule); survives _build
SCIDB._paths   = {}   -- entry handle → where it is, "People > Thresh" (for the announcements)
SCIDB._quiet   = 0    -- > 0: no announcements (building, sync)
SCIDB.announced = {}  -- the last announcements, newest last (tests read it: the ship log can't be)

-- The Science screen's key/value column is narrow (400 px, 37% key / 63% value): a value longer
-- than about 30 characters runs into the description beside it (playtest: Rezkov's "Method").
-- Every key/value goes through SCIDB.setKV, which records what was set (SCIDB.kv_set: tests
-- check the lengths) and logs a value that is too long.
SCIDB.KV_VALUE_MAX = 28
SCIDB.KV_KEY_MAX   = 16
SCIDB.kv_set = {}     -- {path, key, value} for every key/value set this session

function SCIDB.setKV(entry, k, v)
    v = tostring(v)
    entry:setKeyValue(k, v)
    SCIDB.kv_set[#SCIDB.kv_set + 1] = {path = SCIDB._paths and SCIDB._paths[entry] or "?", key = k, value = v}
    if #v > SCIDB.KV_VALUE_MAX or #tostring(k) > SCIDB.KV_KEY_MAX then
        log("[SCIDB] WARNING: key/value too long for the Science screen: " .. tostring(k) .. " = " .. v)
    end
end

-- Remember where an entry sits: its parent's place, then its name.
local function _place(entry, parent, name)
    local up = parent and SCIDB._paths[parent]
    SCIDB._paths[entry] = up and (up .. " > " .. name) or name
    return entry
end

-- The Science pop-up: the consoles that have the database, and how long to gather entries that
-- arrive together (the Boneyard archive unlocks three at once) into one pop-up.
SCIDB.POPUP_CONSOLES = {"Science", "Operations", "SinglePilot"}
SCIDB.POPUP_GATHER   = 1      -- seconds
SCIDB.popups   = {}           -- the last pop-up texts, newest last (tests read it: pop-ups can't be)
SCIDB._pending = {}           -- places waiting for the next pop-up
SCIDB._popup_n = 0

-- Show the gathered entries as one dismissable pop-up on the database consoles of every player ship.
function SCIDB._flushPopup()
    if #SCIDB._pending == 0 then return end
    local text = "Science database updated:\n" .. table.concat(SCIDB._pending, "\n")
    SCIDB._pending = {}
    SCIDB._popup_n = SCIDB._popup_n + 1
    SCIDB.popups[#SCIDB.popups + 1] = text
    while #SCIDB.popups > 20 do table.remove(SCIDB.popups, 1) end
    if not (RT and RT.forEachPlayer) then return end
    RT.forEachPlayer(function(p)
        for _, pos in ipairs(SCIDB.POPUP_CONSOLES) do
            pcall(function() p:addCustomMessage(pos, "scidb_popup_" .. SCIDB._popup_n .. "_" .. pos, text) end)
        end
    end)
end

-- Tell the crew that an entry was added or updated: a line in every player ship's log (Relay reads
-- it) and, gathered with anything else that changes within a second, a pop-up on Science.
local function _announce(entry, verb)
    if SCIDB._quiet > 0 then return end
    local where = SCIDB._paths[entry] or "the database"
    local line = "[Science] Database entry " .. verb .. ": " .. where .. "."
    SCIDB.announced[#SCIDB.announced + 1] = line
    while #SCIDB.announced > 20 do table.remove(SCIDB.announced, 1) end
    if RT and RT.shipLog then RT.shipLog(line, "#00CCAA") end
    SCIDB._pending[#SCIDB._pending + 1] = (verb == "added" and "New: " or "Updated: ") .. where
    if #SCIDB._pending == 1 then
        if RT and RT.after then RT.after(SCIDB.POPUP_GATHER, SCIDB._flushPopup, "scidb_popup")
        else SCIDB._flushPopup() end
    end
end

-- Run fn(...) with the announcements off (a restore of what the crew already had, not news).
function SCIDB.quietly(fn, ...)
    SCIDB._quiet = SCIDB._quiet + 1
    local ok, err = pcall(fn, ...)
    SCIDB._quiet = SCIDB._quiet - 1
    if not ok then error(err, 0) end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Reveal a locked entry by key.  No-op if already unlocked or key unknown.
function SCIDB.unlock(key)
    local L = SCIDB._locked[key]
    if not L or L.unlocked then return end
    L.unlocked = true
    if L.description then L.entry:setLongDescription(L.description) end
    if L.kv then
        for k, v in pairs(L.kv) do SCIDB.setKV(L.entry, k, v) end
    end
    if L.on_unlock then pcall(L.on_unlock, L.entry) end
    log("[SCIDB] unlocked: " .. key)
    _announce(L.entry, "updated")
end

-- Return an entry handle so missions can setKeyValue / setLongDescription.
function SCIDB.get(key)
    return SCIDB._entries[key]
end

-- Add a child entry under an existing parent at runtime.
-- parent_key : SCIDB key of the parent ("people", "records", "briefings", ...)
-- name       : display name
-- desc       : long description (shown immediately)
-- kv         : table of {key=value} pairs, or nil
-- lock_key   : if set, entry starts locked and SCIDB.unlock(lock_key) reveals desc
-- locked_desc: placeholder shown while locked (nil → generic "CLASSIFIED" text)
function SCIDB.addEntry(parent_key, name, desc, kv, lock_key, locked_desc)
    local parent = SCIDB._entries[parent_key]
    if not parent then
        log("[SCIDB] addEntry: unknown parent key '" .. tostring(parent_key) .. "'")
        return nil
    end
    local entry = _place(parent:addEntry(name), parent, name)
    local display_desc = desc
    if lock_key then
        display_desc = locked_desc or "[ CLASSIFIED — access restricted ]"
        SCIDB._locked[lock_key] = {
            entry       = entry,
            description = desc,
            kv          = kv,
            locked_desc = display_desc,
        }
    else
        if kv then
            for k, v in pairs(kv) do SCIDB.setKV(entry, k, v) end
        end
    end
    entry:setLongDescription(display_desc)
    _announce(entry, "added")
    return entry
end

-- Character profiles under People, added when the crew first meets someone. Deliberately
-- character sketches: what a person is like, not what they will do later. Each has a portrait
-- (`image`), made from tools/portraits/portraits.json, whose `look` is how the person appears.
-- Arcs call SCIDB.meet(arc_id, key): it sets the flag "<arc_id>_met_<who>" (cleared by that
-- arc's GM resets like any of its flags) and adds the entry, returning true only the first time
-- (so callers can log "records added"). A profile exists while any arc's met-flag is set.
SCIDB.PROFILES = {
    thresh_profile = {
        who  = "thresh",
        image = "ragtag/img/people/thresh.png",   -- tools/make_portraits.py
        name = "Thresh",
        desc = "Proprietor of Dustmote Salvage, and the usual way to reach people who don't answer " ..
               "hails.\n\n" ..
               "Runs the yard's books, its lines out to the Rim, and a steady trade in work that " ..
               "never reaches the posted boards. Dry, sparing with words, and careful about " ..
               "what he is asked and by whom. He pays on time and expects the same discretion " ..
               "in return.\n\n" ..
               "Known to act for an associate he has never named in public. Nobody in the Drift " ..
               "can say how long he has worked for them, or whether he is the one who chose it.",
        kv = {["Role"] = "Fixer, Dustmote Salvage", ["Works for"] = "An unnamed associate",
              ["Manner"] = "Dry, discreet, punctual", ["Standing"] = "Pays on time"},
    },
    rezkov_profile = {
        who  = "rezkov",
        image = "ragtag/img/people/rezkov.png",   -- tools/make_portraits.py
        name = "Orlan Rezkov",
        desc = "Independent operator, and the head of a small network of couriers, salvagers and " ..
               "informants working the lanes around Dustmote.\n\n" ..
               "Keeps a station in a nebula cloud that is hard to find and harder to find twice: " ..
               "it is not always where it was. Does business in person, and has no patience for " ..
               "go-betweens other than the one he trusts. Said to remember everything anyone " ..
               "has ever said to him, and to hold a grudge exactly as long as the memory lasts.\n\n" ..
               "Concord patrols have never been seen to trouble his people, and he is careful " ..
               "to keep it that way.",
        kv = {["Role"] = "Independent operator", ["Base"] = "Nebula station near Dustmote",
              ["Method"] = "In person, no go-betweens", ["Memory"] = "Total"},
    },
    reva_profile = {
        who  = "reva",
        image = "ragtag/img/people/reva.png",   -- tools/make_portraits.py
        name = "Reva Okonkwo",
        desc = "Quartermaster of Blackwater, which in practice means she runs it.\n\n" ..
               "Served as a gunnery chief on Free Ship cruisers in the Settlement War and was still " ..
               "at her station when the surrender order came through. She did not surrender; she " ..
               "took her crew and two damaged hulls into the Gauntlet instead, and most of " ..
               "Blackwater's first families came with her.\n\n" ..
               "Keeps the books, the guns and the peace among people who do not like being told " ..
               "what to do. Blunt, fair, and slow to trust anyone flying a clean transponder. " ..
               "Her crews follow her because she has never once asked them to do something she " ..
               "would not do first.",
        kv = {["Role"] = "Quartermaster, Blackwater", ["War record"] = "Free Ship gunnery chief",
              ["Manner"] = "Blunt, fair, wary", ["Known for"] = "Never asks what she won't do"},
    },
    kael_profile = {
        who  = "kael",
        image = "ragtag/img/people/kael.png",   -- tools/make_portraits.py
        name = "Commander Kael",
        desc = "Concord Intelligence, Special Operations Investigations.\n\n" ..
               "Flew for the Concord in the Settlement War, and was one of a handful of officers " ..
               "who put their doubts about their orders in writing. She was not punished; she was " ..
               "moved. After the war she transferred to special-operations investigation, where she " ..
               "has spent twenty years following the gaps in the official record.\n\n" ..
               "Colleagues describe her as patient, precise and unwilling to let a file close. " ..
               "She commands CWS Meridian with a small, steady crew who are said to follow her " ..
               "without needing to be told twice, and she is considered one of Concord " ..
               "Intelligence's most capable field officers. She does not bluff.",
        kv = {["Service"] = "Concord Intelligence", ["War record"] = "Settlement War fighter pilot",
              ["Current post"] = "Special Ops Investigations", ["Vessel"] = "CWS Meridian",
              ["Reputation"] = "Asks what nobody else will"},
    },
    quill_profile = {
        who  = "quill",
        image = "ragtag/img/people/quill.png",   -- tools/make_portraits.py
        name = "Dr. Mara Quill",
        desc = "Former senior researcher at the Ashgrave Annex, now working out of the Hob Works at " ..
               "Hob's Landing.\n\n" ..
               "Worked on the Concord's Phase II reversal program until it was shut down, and was one " ..
               "of four Annex staff who escaped the Boneyard in a lifeboat. Precise, tired, and " ..
               "stubborn in the way of someone who has decided a thing will get done whatever it " ..
               "costs her.\n\n" ..
               "Speaks for the survivors, and for the people she believes the Concord abandoned in " ..
               "the Maw.",
        kv = {["Role"] = "Researcher, the Hob Works", ["Formerly"] = "Ashgrave Annex",
              ["Field"] = "Phase II reversal", ["Manner"] = "Precise, relentless"},
    },
    varga_profile = {
        who  = "varga",
        image = "ragtag/img/people/varga.png",   -- tools/make_portraits.py
        name = "Dr. Nell Varga",
        desc = "The doctor at Tamsin Hollow, the farm depot that feeds half the Border.\n\n" ..
               "Keeps the depot's crews alive on a clinic budget and a lot of stubbornness. Applies through " ..
               "the proper channels first, every time, and keeps the paperwork to prove she did. When the " ..
               "channels fail, she stops waiting for them.",
        kv = {["Role"] = "Doctor, Tamsin Hollow", ["Manner"] = "Tired, direct, kind",
              ["Known for"] = "Never giving up a patient"},
    },
    calloway_profile = {
        who  = "calloway",
        image = "ragtag/img/people/calloway.png",   -- tools/make_portraits.py
        name = "Ines Calloway",
        desc = "Foreman of Breaker's Claim, the mining camp on the southern edge of the Shroud.\n\n" ..
               "Worked other people's claims for twenty years before she filed her own. Pays her crews " ..
               "first and herself last, keeps the claim's papers in order, and has run off two raider " ..
               "crews with nothing but cutting lasers and bad language. Doesn't ask for help often. " ..
               "Remembers who gave it.",
        kv = {["Role"] = "Foreman, Breaker's Claim", ["Manner"] = "Gruff, fair, unafraid",
              ["Known for"] = "Never giving up the claim"},
    },
    marchetti_profile = {
        who  = "marchetti",
        image = "ragtag/img/people/marchetti.png",   -- tools/make_portraits.py
        name = "Anton Marchetti",
        desc = "Chief engineer of the Hob Works at Hob's Landing, and young for it.\n\n" ..
               "His father, an engineer on the Free Ships, was killed in the last year of the Settlement " ..
               "War. The Works took the boy in, and he grew up in its test bays. He runs the yard now: " ..
               "builds things other yards say cannot be built, usually on time and rarely on budget. " ..
               "Talks fast, swears in three languages, and treats his crew like family. He has never " ..
               "worked for the Concord, and never will.",
        kv = {["Role"] = "Chief engineer, Hob Works", ["Age"] = "About thirty",
              ["Father"] = "Killed in the war",
              ["Manner"] = "Fast, blunt, warm", ["Known for"] = "Building the impossible"},
    },
}

-- Add a profile entry (no flag). Returns true if it was newly added.
function SCIDB.addProfile(key)
    local p = SCIDB.PROFILES[key]
    if not p or SCIDB._entries[key] or not SCIDB._entries["people"] then return false end
    local e = SCIDB.addEntry("people", p.name, p.desc, p.kv)
    SCIDB._entries[key] = e
    -- The portrait (tools/portraits/: one style for all, 512x512) beside the description.
    if e and p.image then pcall(function() e:setImage(p.image) end) end
    return true
end

-- The crew met someone in an arc. Returns true the first time the profile appears.
function SCIDB.meet(arc_id, key)
    local p = SCIDB.PROFILES[key]
    if not p then return false end
    RT.flag(arc_id .. "_met_" .. p.who, true)
    return SCIDB.addProfile(key)
end

-- True while any arc's "<arc>_met_<who>" flag is set.
function SCIDB.known(key)
    local p = SCIDB.PROFILES[key]
    if not p then return false end
    local suffix = "_met_" .. p.who
    for name, v in pairs((RT.campaign and RT.campaign.flags) or {}) do
        if v and name:sub(-#suffix) == suffix then return true end
    end
    return false
end

-- Remove an entry (and any children) from the database.
function SCIDB.removeEntry(key)
    local e = SCIDB._entries[key]
    SCIDB._entries[key] = nil
    if not e then return false end
    local function _kill(node)
        local ok, kids = pcall(function() return node:getEntries() end)
        for _, c in ipairs(ok and kids or {}) do _kill(c) end
        pcall(function() node:destroy() end)
    end
    _kill(e)
    log("[SCIDB] removed: " .. key)
    return true
end

-- Put an unlocked entry back behind its placeholder (description and revealed keys).
function SCIDB.relock(key)
    local L = SCIDB._locked[key]
    if not L or not L.unlocked then return end
    L.unlocked = false
    L.entry:setLongDescription(L.locked_desc or "[ CLASSIFIED — access restricted ]")
    for k in pairs(L.kv or {}) do pcall(function() L.entry:removeKey(k) end) end
    log("[SCIDB] relocked: " .. key)
end

-- Tie an entry to campaign flags. Registered once by its owner (sciencedb or an arc module):
--   SCIDB.rule("ashgrave_research", {lock = true, want = function() return RT.flag("x") end})
--   SCIDB.rule("boneyard_survivors", {want = fn, add = function() ... end})   -- runtime entry
-- lock = true: unlocked while want() is true, relocked otherwise. Otherwise: add() creates the
-- entry (stored in SCIDB._entries[key]) while want() is true; it is removed otherwise.
function SCIDB.rule(key, spec)
    SCIDB._rules[key] = spec
end

-- Old saves recorded profiles as "<key>_known"; those meetings all happened in the Rezkov arc.
local function _migrateProfileFlags()
    for key, p in pairs(SCIDB.PROFILES) do
        if RT.flag(key .. "_known") then
            RT.flag("rezkov_met_" .. p.who, true)
            RT.clearFlag(key .. "_known")
        end
    end
end

-- Make the database match the campaign flags. Quiet (server log only): it restores what the
-- campaign already earned, or follows a GM jump.
function SCIDB.sync()
    SCIDB.quietly(SCIDB._sync)
end

function SCIDB._sync()
    if not (RT and RT.campaign and SCIDB._entries["people"]) then return end
    pcall(_migrateProfileFlags)
    for key in pairs(SCIDB.PROFILES) do
        if SCIDB.known(key) then SCIDB.addProfile(key)
        elseif SCIDB._entries[key] then SCIDB.removeEntry(key) end
    end
    for key, spec in pairs(SCIDB._rules) do
        local ok, want = pcall(spec.want)
        want = ok and want
        if spec.lock then
            if want then SCIDB.unlock(key) else SCIDB.relock(key) end
        elseif want then
            if not SCIDB._entries[key] and spec.add then pcall(spec.add) end
        elseif SCIDB._entries[key] then
            SCIDB.removeEntry(key)
        end
    end
end

-- ─── Internal builder helpers ─────────────────────────────────────────────────

local function _entry(parent, name, desc, kv)
    -- parent == nil makes a top-level section (the Science screen's first column).
    local e = _place(parent and parent:addEntry(name) or ScienceDatabase():setName(name), parent, name)
    if desc then e:setLongDescription(desc) end
    if kv then for k, v in pairs(kv) do SCIDB.setKV(e, k, v) end end
    return e
end

local function _locked(parent, name, locked_desc, real_desc, real_kv, lock_key)
    local e = _place(parent and parent:addEntry(name) or ScienceDatabase():setName(name), parent, name)
    e:setLongDescription(locked_desc)
    SCIDB._locked[lock_key] = {
        entry       = e,
        description = real_desc,
        kv          = real_kv,
        locked_desc = locked_desc,
    }
    return e
end

-- ─── Ports directory ──────────────────────────────────────────────────────────
-- One entry per universe station (VERSE.STATIONS, so extension stations appear automatically).
-- Hostile havens (Corsairs, Hollow) are left out: the crew has no directory entry for them.
-- Stations spawned by story arcs (Rezkov's station, the Ashgrave Annex) are not universe
-- stations and never appear here.
SCIDB.PORT_EXCLUDE_FACTIONS = {Corsairs = true, Hollow = true}

local _PORT_U = 1000

-- The named area a port sits in: the smallest region containing it that is not just the port's
-- own namesake pocket (e.g. the "Calder's Reach" region around Calder's Reach). Ports outside
-- every other region get "Near <closest region>".
local function _portArea(d)
    local own = d.cs:lower()
    local best, best_r, near, near_gap
    for _, r in ipairs(VERSE.REGIONS or {}) do
        local name = r.name:lower():gsub("^the ", "")
        if not own:find(name, 1, true) and r.r > 1 then
            local dist = math.sqrt((d.x - r.x) ^ 2 + (d.y - r.y) ^ 2)
            if dist <= r.r then
                if not best_r or r.r < best_r then best, best_r = r, r.r end
            elseif not near_gap or dist - r.r < near_gap then
                near, near_gap = r, dist - r.r
            end
        end
    end
    if best then return best.name end
    if near then return "near " .. near.name end
    return "open space"
end

local function _cap(s) return (s:gsub("^%l", string.upper)) end

local function _buildPorts()
    if not (VERSE and VERSE.STATIONS) then return end
    local ports = {}
    for _, d in ipairs(VERSE.STATIONS) do
        if not SCIDB.PORT_EXCLUDE_FACTIONS[d.fac] then ports[#ports + 1] = d end
    end
    if #ports == 0 then return end
    table.sort(ports, function(a, b) return a.cs < b.cs end)

    local root = _entry(nil, "Ports",
        "Stations of the Drift that will take a freighter's docking request, with where to find " ..
        "them and what they offer. Grid references are the same ones the job board uses.")
    SCIDB._entries["ports"] = root

    for _, d in ipairs(ports) do
        local grid = getSectorName(d.x * _PORT_U, d.y * _PORT_U)
        local area = _cap(_portArea(d))
        -- The shipwright is a base for upgrade lines: "Base for hull, reactor and beam upgrades".
        local shop = {}
        for _, id in ipairs(d.shop or {}) do
            local u = RT and RT.upgradeById and RT.upgradeById(id)
            shop[#shop + 1] = u and u.name or (RT and RT.upgradeLineName and RT.upgradeLineName(id)) or id
        end
        local base = #shop > 1 and (table.concat(shop, ", ", 1, #shop - 1) .. " and " .. shop[#shop]) or shop[1]
        local services = {"Job board", "Repairs and resupply"}
        if #shop > 0 then services[#services + 1] = "Shipwright" end
        if d.concord then services[#services + 1] = "Concord customs" end

        local lines = {d.desc or "", ""}
        if d.lore then lines[#lines + 1] = d.lore; lines[#lines + 1] = "" end
        for _, l in ipairs({
            "LOCATION\nGrid " .. grid .. ", " .. area .. ".", "",
            "SERVICES\n" .. table.concat(services, ", ") .. "."}) do lines[#lines + 1] = l end
        if #shop > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "SHIPWRIGHT\nBase for " .. base .. " upgrades. Every level of those is fitted here."
        end
        if d.concord then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "STANDING\nA Concord port. Work here dries up as your Concord standing falls: few jobs below -200, none below -400."
        end
        -- The key/value column fits about 28 characters (SCIDB.KV_VALUE_MAX): the lines themselves
        -- when they fit ("hull, reactor, beam"), else how many (the description lists them).
        local short = table.concat(shop, ", ")
        local kv_shop = (#shop == 0 and "None") or (#short <= SCIDB.KV_VALUE_MAX and short)
            or (#shop .. " upgrade lines")
        local kv = {["Grid"] = grid, ["Area"] = area, ["Authority"] = d.fac, ["Shipwright"] = kv_shop}
        SCIDB._entries["port_" .. d.cs] = _entry(root, d.cs, table.concat(lines, "\n"), kv)
    end
end

-- ─── Ship Upgrades ────────────────────────────────────────────────────────────
-- A top-level section rolling up the upgrade catalogue (RT.UPGRADES): one entry per component line
-- (RT.UPGRADE_LINES), with every level's name, effect, price and prerequisite, and the ports whose
-- shipwright fits that line (VERSE.STATIONS `shop`, read through RT.stocks, the shipwright's own test).
SCIDB.UPGRADE_LINE_TITLES = {
    hull = "Hull", shields = "Shields", beams = "Beam weapons", missiles = "Missile racks",
    tubes = "Torpedo tubes", engines = "Engines", thrusters = "Thrusters", reactor = "Reactor",
    repair = "Engineering crew", sensors = "Sensors", probes = "Probes",
}

local function _fmtCr(n)
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then break end
    end
    return s .. " cr"
end

-- The ports whose shipwright fits an upgrade, sorted by name (hostile havens are left out, as in Ports).
local function _fittedAt(id)
    local out = {}
    for _, d in ipairs((VERSE and VERSE.STATIONS) or {}) do
        if not SCIDB.PORT_EXCLUDE_FACTIONS[d.fac] and RT and RT.stocks and RT.stocks(d, id) then
            out[#out + 1] = d
        end
    end
    table.sort(out, function(a, b) return a.cs < b.cs end)
    return out
end

local function _buildUpgrades()
    if not (RT and RT.UPGRADES and RT.UPGRADE_LINES) then return end
    local root = _entry(nil, "Ship Upgrades",
        "What the Drift's shipwrights can fit to a Light Freighter, by component, with prices and where " ..
        "to buy them.\n\n" ..
        "HOW TO BUY\nDock at a port with a shipwright and open Shipwright in the station's comms. A " ..
        "shipwright fits every level of the components it is a base for; a level is offered once the " ..
        "one it needs is fitted.\n\n" ..
        "WHO OWNS IT\nAn upgrade belongs to the ship that bought it, and stays with it from session to " ..
        "session, even if the ship is lost and rebuilt.\n\n" ..
        "BETTER WORK\nThe more a ship has invested in upgrades, the better the work the job boards " ..
        "offer it: hacking jobs from 500 cr invested, destroy and boarding jobs from 1,000 cr.",
        {["Components"] = tostring(#RT.UPGRADE_LINES), ["Upgrades"] = tostring(#RT.UPGRADES)})
    SCIDB._entries["upgrades"] = root

    for _, line in ipairs(RT.UPGRADE_LINES) do
        local ups = {}
        for _, u in ipairs(RT.UPGRADES) do if u.line == line.id then ups[#ups + 1] = u end end
        if #ups > 0 then
            -- Ports: those that fit any level of the line (a base sells every level).
            local ports = _fittedAt(ups[1].id)
            local where = {}
            for _, d in ipairs(ports) do
                where[#where + 1] = d.cs .. " (" .. getSectorName(d.x * _PORT_U, d.y * _PORT_U) .. ")"
            end
            local lo, hi = ups[1].cost, ups[1].cost
            local levels = {}
            for _, u in ipairs(ups) do
                lo, hi = math.min(lo, u.cost), math.max(hi, u.cost)
                local need = RT.upgradeNeedsText(u)
                levels[#levels + 1] = u.name .. ", " .. _fmtCr(u.cost) ..
                    (need and (" (needs " .. need .. ")") or "") .. "\n" .. u.desc
            end
            local title = SCIDB.UPGRADE_LINE_TITLES[line.id] or _cap(line.name)
            local desc = "FITTED AT\n" .. (#where > 0 and (table.concat(where, ", ") .. ".") or "No shipwright in the Drift fits these.") ..
                "\n\nUPGRADES\n" .. table.concat(levels, "\n\n")
            local kv = {
                ["Upgrades"]    = tostring(#ups),
                ["Price"]       = lo == hi and _fmtCr(lo) or (_fmtCr(lo) .. " - " .. _fmtCr(hi)),
                ["Shipwrights"] = #ports == 1 and ports[1].cs or (#ports .. " ports"),
            }
            SCIDB._entries["upgrades_" .. line.id] = _entry(root, title, desc, kv)
        end
    end
end

-- The fake transponder code (core/transponder.lua): under Ship Upgrades once the campaign has
-- earned it (Marchetti's offer at the end of the Hob Works arc). A consumable, not a component.
local function _addTransponderEntry()
    local root = SCIDB._entries["upgrades"]
    if not (root and RT and RT.TRANSPONDER) or SCIDB._entries["upgrades_transponder"] then return end
    local T = RT.TRANSPONDER
    local where = {}
    for _, d in ipairs((VERSE and VERSE.STATIONS) or {}) do
        if T.sold_at[d.cs] then where[#where + 1] = d.cs .. " (" .. getSectorName(d.x * _PORT_U, d.y * _PORT_U) .. ")" end
    end
    local desc = "SOLD AT\n" .. table.concat(where, ", ") .. ": the Hob Works, which made the first one for the Treasury convoy job.\n\n" ..
        "WHAT IT DOES\n" .. T.name .. ", " .. _fmtCr(T.cost) .. ". It goes on Engineering's board as \"Change transponder\". " ..
        "Press it and for " .. (T.secs // 60) .. " minutes the Concord reads the ship as clean: a wanted ship's patrols find " ..
        "nothing to stop it for, and port guards and lane pickets let it pass. Then the Concord rotates its keys and the code is spent.\n\n" ..
        "ONE USE\nEach code works once. Buy as many as you like; the ones you have not used stay with the ship.\n\n" ..
        "WHAT IT DOES NOT DO\nIt does not change your standing, and it does not hide what you do: fire on the Concord and they know who you are."
    local e = root:addEntry("Fake transponder")
    SCIDB._paths[e] = (SCIDB._paths[root] or "Ship Upgrades") .. " > Fake transponder"
    e:setLongDescription(desc)
    SCIDB.setKV(e, "Price", _fmtCr(T.cost))
    SCIDB.setKV(e, "Uses", "One per code")
    SCIDB.setKV(e, "Lasts", (T.secs // 60) .. " minutes")
    SCIDB._entries["upgrades_transponder"] = e
    _announce(e, "added")
end
SCIDB.rule("upgrades_transponder", {want = function() return RT.transponderUnlocked and RT.transponderUnlocked() end,
    add = _addTransponderEntry})
if RT and RT.on then
    RT.on(function(ev)
        if ev.type == "transponder_unlocked" then _addTransponderEntry() end
    end)
end

-- ─── Achievements ─────────────────────────────────────────────────────────────
-- A top-level entry listing every achievement (ACH, stats.lua) and which the campaign has. A
-- hidden one shows as "???" until it is earned. Kept current by _P.update (no announcement: the
-- ship log already says "[Achievement] ...").
SCIDB.ACH_TITLES = {jobs = "Jobs", money = "Money", exploration = "Exploration", story = "Story"}
-- One column (no key/values beside it), drawn with the Science screen's formatting tags (<h2>, <color=#..>,
-- </> back to normal): a gold diamond for an earned one, a grey hollow one for the rest. The font
-- (Big Shoulders Display) has ◆ and ◇; it has no check marks or stars.
SCIDB.ACH_EARNED  = "<color=#ffd45a>\u{25C6}</> "      -- ◆, gold
SCIDB.ACH_PENDING = "<color=#7d8a99>\u{25C7} "         -- ◇, the whole line grey
SCIDB.ACH_HEADING = "#9fc4ff"

function SCIDB.achievementsText()
    local groups, order, earned, total = {}, {}, 0, 0
    for _, id in ipairs((ACH and ACH.order) or {}) do
        local def = ACH.defs[id]
        if def then
            local cat = def.category or "other"
            if not groups[cat] then groups[cat] = {}; order[#order + 1] = cat end
            local has = ACH.has(id)
            total = total + 1
            if has then earned = earned + 1 end
            local line
            if has then line = SCIDB.ACH_EARNED .. def.name .. ": " .. (def.desc or "")
            elseif def.hidden then line = SCIDB.ACH_PENDING .. "???  (a secret, for now)</>"
            else line = SCIDB.ACH_PENDING .. def.name .. ": " .. (def.desc or "") .. "</>" end
            table.insert(groups[cat], line)
        end
    end
    local out = {"<h2>Earned " .. earned .. " of " .. total .. "</>",
        "Every achievement in the campaign. " .. SCIDB.ACH_EARNED .. "earned, "
        .. SCIDB.ACH_PENDING .. "not yet</>. A new one is announced in the ship log.", ""}
    for _, cat in ipairs(order) do
        out[#out + 1] = "<color=" .. SCIDB.ACH_HEADING .. ">" .. string.upper(SCIDB.ACH_TITLES[cat] or cat) .. "</>"
        for _, l in ipairs(groups[cat]) do out[#out + 1] = l end
        out[#out + 1] = ""
    end
    return table.concat(out, "\n"), earned, total
end

function SCIDB.refreshAchievements()
    local e = SCIDB._entries["achievements"]
    if not e or not ACH then return end
    local text, earned, total = SCIDB.achievementsText()
    local sig = earned .. "/" .. total
    if sig == SCIDB._ach_sig then return end
    SCIDB._ach_sig = sig
    e:setLongDescription(text)
end

local function _buildAchievements()
    SCIDB._entries["achievements"] = _entry(nil, "Achievements", "")
    SCIDB._ach_sig = nil
    SCIDB.refreshAchievements()
end

-- ─── Database construction ────────────────────────────────────────────────────

-- The region maps (entry key -> image), drawn by tools/make_region_maps.py (keep its MAPS in step).
SCIDB.REGION_MAPS = {
    regions           = "ragtag/img/maps/drift.png",
    region_core       = "ragtag/img/maps/region_core.png",
    region_escrow     = "ragtag/img/maps/region_escrow.png",
    region_border     = "ragtag/img/maps/region_border.png",
    region_rim        = "ragtag/img/maps/region_rim.png",
    region_shroud     = "ragtag/img/maps/region_shroud.png",
    region_gauntlet   = "ragtag/img/maps/region_gauntlet.png",
    region_blackwater = "ragtag/img/maps/region_blackwater.png",
    region_boneyard   = "ragtag/img/maps/region_boneyard.png",
    region_maw        = "ragtag/img/maps/region_maw.png",
}

local function _build()

    -- Root
    local root = ScienceDatabase():setName("The Drift")
    root:setLongDescription(
        "Independent space spanning five solar systems from the wealthy Concord Core " ..
        "to the deadly Maw. Law is thin, distances are long, and credits are tight. " ..
        "The Settlement War ended twenty years ago. The Concord won. " ..
        "Border and Rim worlds remember losing."
    )
    SCIDB._entries["root"] = root

    -- ── Regions ──────────────────────────────────────────────────────────────

    -- Regions, Factions, People, Records and Mission Briefings are top-level sections beside the stock Natural / Technologies /
    -- Weapons / Ships / Stations ones; "The Drift" above is the overview entry.
    local regions = _entry(nil, "Regions",
        "The Drift is divided into named regions with distinct hazard profiles and " ..
        "political climates. Knowing where you are matters. Each region's entry has its own map; " ..
        "the letters and numbers on the maps' edges are the sectors, as on Relay."
    )
    SCIDB._entries["regions"] = regions

    SCIDB._entries["region_core"] = _entry(regions, "The Core",
        "The innermost systems, orbiting the white star Lumen. Rich Concord worlds, " ..
        "heavy patrols, and expensive docking fees. Safe for ships with clean transponders.",
        { ["Star"] = "Lumen (white)", ["Law"] = "Heavy Concord presence", ["Danger"] = "Low — unless you're wanted" }
    )

    SCIDB._entries["region_escrow"] = _entry(regions, "The Escrow Marches",
        "Concord space south of the Core and the Arbiter Line, reaching almost to the Cinder Fields. " ..
        "The Concord calls it a buffer held 'in trust' for the Border worlds until they are 'ready' for " ..
        "full membership; the Border calls it the Concord's front yard. Checkpoints and patrols, the same " ..
        "as on the Arbiter Line: a clean transponder passes, a flagged one gets stopped.",
        { ["Control"] = "Concord", ["Law"] = "Checkpoints and patrols", ["Danger"] = "Low — unless you're wanted" }
    )

    SCIDB._entries["region_border"] = _entry(regions, "The Border",
        "Independent trading posts around the red star Cinder. Port Vesper is the " ..
        "largest neutral hub in the Drift. Busy lanes, loose law. Where most deals get made.",
        { ["Star"] = "Cinder (red)", ["Law"] = "Nominal — sparse patrols", ["Danger"] = "Low to moderate" }
    )

    SCIDB._entries["region_rim"] = _entry(regions, "The Rim",
        "Frontier worlds around the gold star Kestrel. Long distances, rough folk, " ..
        "and opportunities that don't appear in official trade registers. " ..
        "Concord presence is thin. Locals prefer it that way.",
        { ["Star"] = "Kestrel (gold)", ["Law"] = "Minimal", ["Danger"] = "Moderate" }
    )

    SCIDB._entries["region_shroud"] = _entry(regions, "The Shroud",
        "A vast nebula cutting through the mid-Drift. Sensors degrade inside it. " ..
        "Ships go missing. Spacers tell stories. Navigation relies on signal buoys " ..
        "that sometimes go offline without explanation. The Shroud Raiders hunt inside it, " ..
        "and in the Deep Shroud beyond.",
        { ["Hazard"] = "Blind sensors, raiders", ["Danger"] = "Moderate to high" }
    )

    SCIDB._entries["region_gauntlet"] = _entry(regions, "The Gauntlet",
        "A dense asteroid belt notorious for Corsair ambushes. The rocks provide " ..
        "cover for attack craft and make pursuit difficult. Avoid unless you're armed " ..
        "or you have business there.",
        { ["Hazard"] = "Corsairs, debris fields", ["Danger"] = "High" }
    )

    SCIDB._entries["region_blackwater"] = _entry(regions, "Blackwater Reach",
        "Corsair-controlled territory. Mined approaches, fortified outposts, " ..
        "and no Concord presence. Ships without Corsair clearance do not return. " ..
        "Corsair faction vessels operate freely here.",
        { ["Control"] = "Corsair-held", ["Law"] = "None — Corsair rules apply", ["Danger"] = "Extreme for neutrals" }
    )

    SCIDB._entries["region_boneyard"] = _entry(regions, "The Boneyard",
        "Settlement War battlefield surrounding the dead world Ashgrave. " ..
        "Relic war drones still patrol the debris fields, still following " ..
        "twenty-year-old targeting orders. Salvage value is high. " ..
        "Life expectancy is not.",
        { ["Hazard"] = "Active Relic war drones", ["Danger"] = "High — no warning given" }
    )

    SCIDB._entries["region_maw"] = _locked(regions, "The Maw",
        "Pale Sun sector. Access restricted by Concord order. No authorised traffic. " ..
        "Ships that enter do not return. Reason for restriction: classified.",
        "The innermost region, orbiting the blue-white Pale Sun. Home to the Hollow. " ..
        "Concord sealed access twenty years ago without public explanation. " ..
        "Expeditions have a near-total loss rate. The ones who come back don't talk about it. " ..
        "Long-range scans show no stations, no debris fields — only Hollow ship signatures " ..
        "and electromagnetic anomalies consistent with large-scale biological activity.",
        { ["Star"] = "Pale Sun (blue-white)", ["Law"] = "Concord-restricted", ["Danger"] = "Extreme" },
        "maw_full"
    )

    -- Maps: the whole Drift on the section, one region on each entry. tools/make_region_maps.py draws them
    -- from the universe data (its MAPS table matches this one); check.py fails when one is stale.
    for key, img in pairs(SCIDB.REGION_MAPS) do
        local e = SCIDB._entries[key]
        if e then pcall(function() e:setImage(img) end) end
    end

    -- ── Factions ─────────────────────────────────────────────────────────────

    local factions = _entry(nil, "Factions",
        "Known groups operating in the Drift. Reputation with each faction affects " ..
        "how they respond to your ship."
    )
    SCIDB._entries["factions"] = factions

    SCIDB._entries["faction_concord"] = _entry(factions, "Concord",
        "The dominant authority in the Core and controlling power in the Drift. " ..
        "Concord patrols enforce trade law, collect tariffs, and conduct inspections. " ..
        "At good standing they wave you through. At bad standing, expect warp jammers " ..
        "and compliance timers. Below -200 reputation they treat your ship as hostile " ..
        "and attack on sight.",
        { ["At rep 0+"] = "Routine, courteous checks", ["At rep < -200"] = "Shoot on sight", ["Warp jammer"] = "Comply in 60s or hostile" }
    )

    SCIDB._entries["faction_corsairs"] = _entry(factions, "Corsairs",
        "Organised raiders operating primarily from Blackwater Reach and the Gauntlet. " ..
        "Attack traders on sight unless you have an arrangement with them. " ..
        "More organised than they appear — attacks in Concord-patrolled space " ..
        "suggest coordination and insider knowledge.",
        { ["Territory"] = "Blackwater Reach, Gauntlet", ["Attitude"] = "Hostile to unknown ships", ["Note"] = "Rep affects spawn rate" }
    )

    SCIDB._entries["faction_shroud_raiders"] = _entry(factions, "Shroud Raiders",
        "Corsair crews who never answered to Blackwater. When the Settlement War ended, " ..
        "Blackwater made its peace with what was left of the Free Ships and set rules for " ..
        "its crews. The ones who wouldn't keep them went into the Shroud. They hide in the " ..
        "nebulae of the Shroud and the Deep Shroud and take whatever comes through. " ..
        "No arrangement with Blackwater protects you from them, and they don't negotiate.",
        { ["Territory"] = "The Shroud, the Deep Shroud", ["Attitude"] = "Hostile to outsiders", ["Note"] = "No standing to win or lose" }
    )

    SCIDB._entries["faction_independent"] = _entry(factions, "Independent",
        "Traders, salvagers, and freelancers with no faction alignment. " ..
        "Includes your own ship. Neutral to other Independents by default. " ..
        "Most stations in the Border and Rim cater to Independent traffic.",
        { ["Attitude"] = "Neutral", ["Common locations"] = "Border, Rim, Port Vesper" }
    )

    SCIDB._entries["faction_relic"] = _entry(factions, "Relic",
        "Settlement War-era automated combat drones. Still operational in the Boneyard " ..
        "twenty years after the war ended. No communications capability — they attack " ..
        "anything that enters their patrol radius without the correct military IFF codes, " ..
        "which Concord never published. Origin: Concord military procurement, " ..
        "deployed during the Ashgrave campaign.",
        { ["Location"] = "Boneyard", ["Attitude"] = "Hostile to all — no comms", ["IFF"] = "Unknown — codes classified" }
    )

    SCIDB._entries["faction_hollow"] = _locked(factions, "Hollow",
        "Unknown faction. Encountered only in Maw sector. No communications established. " ..
        "Ships do not match any known template. Extreme aggression toward intruders. " ..
        "Origin: unknown.",
        "Former human colonists from Pale Sun settlements. Subjects of Concord " ..
        "Project Ashgrave Synthesis — a neural cohesion compound administered without " ..
        "consent in Maw-adjacent colonial water supplies approximately 20 years ago. " ..
        "Compound caused progressive cognitive transformation: initial compliance effects " ..
        "followed by catastrophic cascade. Subjects developed collective behavior, " ..
        "loss of individual cognition, and extreme aggression toward outsiders. " ..
        "Concord withdrew and sealed the sector. The Hollow are what remained. " ..
        "Phase II reversal protocols were developed but abandoned when Phase III " ..
        "subjects proved unresponsive. Protocol data exists in Ashgrave research archives.",
        { ["Origin"] = "Human: Concord test subjects", ["Status"] = "Ongoing — self-sustaining", ["Reversal"] = "Phase II protocol (theory)" },
        "hollow_true_nature"
    )

    -- ── People, Records, Mission Briefings ───────────────────────────────────
    -- What used to be one Lore section (split 2026-11-26): People are the profiles (SCIDB.PROFILES, added as
    -- the crew meets them), Records the history and recovered documents, Mission Briefings what an arc gives
    -- the crew for a job (its arc adds them). Arcs name the section: SCIDB.addEntry("records"|"briefings", ...).

    _buildPorts()
    _buildUpgrades()
    _buildAchievements()

    SCIDB._entries["people"] = _entry(nil, "People",
        "People the crew has met: who they are and what they are like. Added as you meet them."
    )
    SCIDB._entries["records"] = _entry(nil, "Records",
        "Historical records, research summaries, and recovered documents. " ..
        "Updated as new information is retrieved."
    )
    SCIDB._entries["briefings"] = _entry(nil, "Mission Briefings",
        "What the crew has been told about the jobs it has taken on: the task, where, the pay, and what to expect."
    )
    local lore = SCIDB._entries["records"]

    SCIDB._entries["lore_settlement_war"] = _entry(lore, "The Settlement War",
        "Twenty years ago, Border and Rim colonial worlds attempted to break from " ..
        "Concord governance over tariff disputes and trade route control. " ..
        "The war lasted four years. Concord won by attrition — not decisive battle, " ..
        "but economic blockade and systematic destruction of Rim infrastructure. " ..
        "The peace treaty restored Concord authority with new 'transitional' tariffs " ..
        "that have not transitioned. Ashgrave was destroyed during the final campaign. " ..
        "The Relic drones were left running. Nobody has explained why.",
        { ["Duration"] = "~4 years, ended 20 years ago", ["Outcome"] = "Concord victory", ["Unresolved"] = "Drones active; Maw sealed" }
    )

    SCIDB._entries["lore_ashgrave"] = _locked(lore, "Ashgrave Research",
        "[ CLASSIFIED — Concord security clearance required ]",
        "Project Ashgrave Synthesis. Concord applied research division, " ..
        "active during and immediately after the Settlement War.\n\n" ..
        "Objective: develop a neural cohesion compound to increase social compliance " ..
        "and reduce resistance behaviors in difficult colonial environments.\n\n" ..
        "Phase I–II results: compound administered via water supply to Pale Sun " ..
        "colonial settlements without subject consent. Initial results exceeded " ..
        "projections. Populations became cooperative, conflict rates dropped, " ..
        "Concord administrative efficiency improved.\n\n" ..
        "Phase III: catastrophic cascade. Compound continued transforming subjects " ..
        "beyond target threshold. Progressive loss of individual cognition. " ..
        "Emergence of collective behavior and extreme aggression toward outsiders. " ..
        "Electromagnetic hypersensitivity. Self-sustaining and transmissible.\n\n" ..
        "Resolution: research station sealed, population quarantined, sector access " ..
        "restricted by emergency order. Phase II reversal protocols shelved — " ..
        "Phase III subjects unresponsive in initial trials. Data archived at Ashgrave Annex.",
        { ["Classification"] = "Destroy on intercept", ["Status"] = "Research discontinued", ["Reversal"] = "Archived, not destroyed" },
        "ashgrave_research"
    )

    SCIDB._entries["lore_synthesis"] = _locked(lore, "The Synthesis",
        "[ CLASSIFIED — Concord security clearance required ]",
        "The Ashgrave Synthesis compound. Developed by Concord applied research " ..
        "as a population management tool during the Settlement War.\n\n" ..
        "Key properties:\n" ..
        "- Self-sustaining after Phase II threshold: does not require continued dosing\n" ..
        "- Transmissible through close proximity exposure (Phase III subjects)\n" ..
        "- Responds to specific electromagnetic frequencies — basis for Phase II reversal protocol\n" ..
        "- Not alien in origin. Entirely Concord-developed. Peer-reviewed within " ..
        "Concord research division and approved at senior level.\n\n" ..
        "Phase II reversal: a targeted electromagnetic broadcast at the documented " ..
        "frequency induces Synthesis dormancy. Effective on Phase I and II subjects. " ..
        "Phase III efficacy untested due to research termination. " ..
        "Broadcast source must be within range of the subject population. " ..
        "Duration: 90 seconds minimum for dormancy cascade to initiate.",
        { ["Type"] = "Engineered bio-compound", ["Reversible"] = "Phase II broadcast protocol", ["Broadcast freq."] = "Ashgrave archive, Phase II" },
        "synthesis_details"
    )

    -- Ledger arc: the AI's findings, unlocked when the AI reaches Rezkov (lock key ledger_findings).
    SCIDB._entries["lore_ledger"] = _locked(lore, "The Containment Ledger",
        "[ ENCRYPTED — no matching records recovered ]",
        "Twenty years of Concord Treasury transfers through one account that never closed, " ..
        "recovered by a program planted in the Concord accounting system at Waypoint Galen.\n\n" ..
        "The account is coded CX-0, 'Contingent Reserve'. Its line items read 'Maw containment' " ..
        "and 'Ashgrave remediation': maintenance for Relic drones that officially stood down " ..
        "after the Settlement War, upkeep for an archive at Ashgrave that officially does not " ..
        "exist, and patrol costs for a sector that is officially empty.\n\n" ..
        "Every transfer is signed. The recurring signatories:\n" ..
        "- Aurelian Voss, Deputy Secretary of the Treasury (authorising signatory, all twenty years)\n" ..
        "- Rear Admiral Corin Hale, Fleet Logistics (drone maintenance and Boneyard patrols)\n" ..
        "- Director Mireille Tan, Applied Research Division (Ashgrave archive upkeep)\n" ..
        "The original appropriation was approved in closed session by the Concord Council's " ..
        "Standing Committee on Security. The session minutes are sealed.\n\n" ..
        "Orlan Rezkov holds the ledger. He has not released it.",
        { ["Account"] = "CX-0 'Contingent Reserve'", ["Duration"] = "20 years, still open",
          ["Signatories"] = "Voss, Hale, Tan", ["Status"] = "Held by Rezkov, unreleased" },
        "ledger_findings"
    )

    -- Re-add entries earned in a previous session (the database is rebuilt every init).
    SCIDB.sync()

    log("[SCIDB] Drift database built.")
end

-- ─── WORLD plugin ─────────────────────────────────────────────────────────────

local _P = {}
_P.id               = "sciencedb"
_P.name             = "Science Database"
_P.default_enabled  = true
_P.defaults         = {}

-- Stock top-level sections the Drift replaces (EE builds the stock database in science_db.lua
-- before the scenario's init). The stock Factions list the stock universe (Human Navy, Kraylor,
-- Exuari...); the Drift has its own top-level Factions. The stock Stations section is only generic
-- station templates (the Drift's own stations are in Ports), so it goes too; a scanned station's
-- "Database" button on Science then has no template entry to open. Natural, Technologies,
-- Weapons and Ships stay: generic gameplay help, and that button looks a ship's template up in Ships.
SCIDB.REMOVE_STOCK = {"Factions", "Stations"}

local function _destroyTree(node)
    local ok, kids = pcall(function() return node:getEntries() end)
    for _, c in ipairs(ok and kids or {}) do _destroyTree(c) end
    pcall(function() node:destroy() end)
end

local function _removeStockSections()
    local remove = {}
    for _, n in ipairs(SCIDB.REMOVE_STOCK) do remove[n] = true end
    for _, top in ipairs(getScienceDatabases() or {}) do
        local ok, name = pcall(function() return top:getName() end)
        if ok and remove[name] then
            _destroyTree(top)
            log("[SCIDB] removed stock section: " .. name)
        end
    end
end

-- The stock Ships section lists every EmptyEpsilon template; keep the ones the game uses
-- (SCIDB.SHIPS_USED, ships_used.lua: generated by check.py from every template the Lua names) and drop
-- the rest, and any hull class left empty. A scanned ship's "Database" button still finds its entry.
require("ragtag/ships_used.lua")

function SCIDB.pruneShips()
    local keep = {}
    for _, shown in pairs(SCIDB.SHIPS_USED or {}) do keep[shown] = true end
    keep[SCIDB.FREIGHTER or "Light Freighter"] = true      -- the crew's ship (SCIDB.addFreighterEntry)
    local kept, dropped = 0, 0
    for _, top in ipairs(getScienceDatabases() or {}) do
        local ok, name = pcall(function() return top:getName() end)
        if ok and name == "Ships" then
            local _, classes = pcall(function() return top:getEntries() end)
            for _, class in ipairs(classes or {}) do
                local _, ships = pcall(function() return class:getEntries() end)
                local left = 0
                for _, ship in ipairs(ships or {}) do
                    local _, sname = pcall(function() return ship:getName() end)
                    if keep[sname] then left = left + 1; kept = kept + 1
                    else _destroyTree(ship); dropped = dropped + 1 end
                end
                if left == 0 then _destroyTree(class) end
            end
        end
    end
    log("[SCIDB] Ships: kept " .. kept .. " the game uses, removed " .. dropped)
    return kept, dropped
end

-- The crew's own ship. Its template (ragtag/ship_templates.lua) is defined after EmptyEpsilon builds the
-- stock database, so it has no entry: add one beside the Flavia P.Falcon it is copied from, with the same
-- facts the stock entries show (read from the live template), and what the Drift does to it.
SCIDB.FREIGHTER = "Light Freighter"
SCIDB.FREIGHTER_TEXT =
    "The crew's own ship, and every independent hauler's: a Flavia-class transport running independent colors. " ..
    "Solid, unglamorous, and surprisingly hard to kill.\n\n" ..
    "AS SHE LEAVES THE YARD\nTwo homing missiles in the racks, no nukes or mines, and two repair crew. Everything else " ..
    "is bought: hull, shields, beams, tubes, engines, thrusters, reactor and coolant, sensors and probes at the " ..
    "shipwrights (see Ship Upgrades). What a ship has fitted stays with it."

local function _dirLabel(d)
    d = ((d or 0) + 180) % 360 - 180
    if math.abs(d) <= 45 then return "Front" elseif math.abs(d) >= 135 then return "Rear" end
    return d > 0 and "Right" or "Left"
end

function SCIDB.addFreighterEntry()
    local t = __ship_templates and __ship_templates[SCIDB.FREIGHTER]
    if not t then return nil end
    local parent
    for _, top in ipairs(getScienceDatabases() or {}) do
        if top:getName() == "Ships" then
            for _, class in ipairs(top:getEntries() or {}) do
                for _, s in ipairs(class:getEntries() or {}) do
                    if s:getName() == SCIDB.FREIGHTER then return s end      -- already there
                    if s:getName() == "Flavia P.Falcon" then parent = class end
                end
            end
            parent = parent or top:addEntry("Frigate")
        end
    end
    if not parent then return nil end
    local e = parent:addEntry(SCIDB.FREIGHTER)
    SCIDB._paths[e] = "Ships > " .. tostring(parent:getName()) .. " > " .. SCIDB.FREIGHTER
    e:setLongDescription(SCIDB.FREIGHTER_TEXT)
    local function kv(k, v) pcall(function() e:addKeyValue(k, tostring(v)) end) end
    pcall(function()
        local dp = t.docking_port
        kv("Class", dp and dp.dock_class or parent:getName())
        if dp and dp.dock_subclass then kv("Sub-class", dp.dock_subclass) end
    end)
    pcall(function() if t.__model_data_name then e:setModelDataName(t.__model_data_name) end end)
    pcall(function() if t.radar_trace then e:setImage(t.radar_trace.icon) end end)
    pcall(function()
        local sz = t.physics.size
        kv("Size", math.floor(type(sz) == "table" and sz[1] or sz))
    end)
    pcall(function()
        local sh = {}
        for _, d in ipairs(t.shields) do sh[#sh + 1] = tostring(math.floor(d.max)) end
        if #sh > 0 then kv("Shield", table.concat(sh, "/")) end
    end)
    pcall(function() kv("Hull", math.floor(t.hull.max)) end)
    pcall(function()
        kv("Move speed", string.format("%.1f u/min", t.impulse_engine.max_speed_forward * 60 / 1000))
        kv("Reverse move speed", string.format("%.1f u/min", t.impulse_engine.max_speed_reverse * 60 / 1000))
    end)
    pcall(function() kv("Turn speed", string.format("%.1f deg/sec", t.maneuvering_thrusters.speed)) end)
    pcall(function() kv("Warp speed", string.format("%.1f u/min", t.warp_drive.speed_per_level * 60 / 1000)) end)
    pcall(function()
        for _, d in ipairs(t.beam_weapons) do
            if d.range > 0 then kv(_dirLabel(d.direction) .. " beam weapon", string.format("%.1f Dmg / %.1f sec", d.damage, d.cycle_time)) end
        end
    end)
    pcall(function()
        for _, d in ipairs(t.missile_tubes) do kv(_dirLabel(d.direction) .. " tube", string.format("%.1f sec", d.load_time)) end
    end)
    return e
end

function _P.init(state)
    _removeStockSections()
    SCIDB.pruneShips()
    pcall(SCIDB.addFreighterEntry)
    SCIDB.quietly(_build)   -- the database as it stands at session start is not news
end

function _P.update(state, delta, now)
    -- Achievements: arcs define theirs as they load, and awards come any time.
    if now >= (state.next_ach or 0) then
        state.next_ach = now + 2
        SCIDB.refreshAchievements()
    end
end

function _P.gmMenu(addButton, showSelf)
    addButton("Test: unlock hollow", function()
        SCIDB.unlock("hollow_true_nature")
        showSelf()
    end)
    addButton("Test: unlock ashgrave", function()
        SCIDB.unlock("ashgrave_research")
        SCIDB.unlock("synthesis_details")
        showSelf()
    end)
    addButton("Test: unlock maw", function()
        SCIDB.unlock("maw_full")
        showSelf()
    end)
end

WORLD.register(_P)
