-- ee/ragtag/world/sciencedb.lua
-- Science station encyclopedia for the Drift universe.
-- Runs in init(): clears auto-populated ship-template entries (best-effort),
-- then builds the Drift lore database.
--
-- API:
--   SCIDB.unlock(key)              -- reveal a locked entry
--   SCIDB.get(key)                 -- return entry handle for further edits
--   SCIDB.addEntry(parent_key, name, desc, kv, lock_key, locked_desc)
--                                  -- add a child entry at runtime (missions use this)
--   SCIDB.meet(arc_id, profile_key) -- the crew met someone: flag "<arc>_met_<who>", add profile
--   SCIDB.rule(key, spec)          -- tie a locked entry or a runtime entry to campaign flags
--   SCIDB.sync()                   -- make the database match the flags (session start, GM jumps)
--
-- State rule: every arc-dependent entry is derived from campaign flags. Profiles exist while any
-- "<arc>_met_<who>" flag is set; rules say when a locked entry is unlocked or a runtime entry
-- exists. Arcs add entries as the story happens (with their log lines); SCIDB.sync() then
-- removes, re-adds, locks or unlocks whatever no longer matches, e.g. after a GM jump back.

SCIDB = SCIDB or {}

SCIDB._entries = {}   -- key → ScienceDatabase handle
SCIDB._locked  = {}   -- key → {entry, description, kv, locked_desc, on_unlock, unlocked}
SCIDB._rules   = SCIDB._rules or {}   -- key → spec (see SCIDB.rule); survives _build

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Reveal a locked entry by key.  No-op if already unlocked or key unknown.
function SCIDB.unlock(key)
    local L = SCIDB._locked[key]
    if not L or L.unlocked then return end
    L.unlocked = true
    if L.description then L.entry:setLongDescription(L.description) end
    if L.kv then
        for k, v in pairs(L.kv) do L.entry:setKeyValue(k, v) end
    end
    if L.on_unlock then pcall(L.on_unlock, L.entry) end
    log("[SCIDB] unlocked: " .. key)
end

-- Return an entry handle so missions can setKeyValue / setLongDescription.
function SCIDB.get(key)
    return SCIDB._entries[key]
end

-- Add a child entry under an existing parent at runtime.
-- parent_key : SCIDB key of the parent (e.g. "lore")
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
    local entry = parent:addEntry(name)
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
            for k, v in pairs(kv) do entry:setKeyValue(k, v) end
        end
    end
    entry:setLongDescription(display_desc)
    return entry
end

-- Character profiles under Lore, added when the crew first meets someone. Deliberately
-- character sketches: what a person is like, not what they will do later.
-- Arcs call SCIDB.meet(arc_id, key): it sets the flag "<arc_id>_met_<who>" (cleared by that
-- arc's GM resets like any of its flags) and adds the entry, returning true only the first time
-- (so callers can log "records added"). A profile exists while any arc's met-flag is set.
SCIDB.PROFILES = {
    thresh_profile = {
        who  = "thresh",
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
              ["Method"] = "In person, never through go-betweens", ["Memory"] = "Total"},
    },
    kael_profile = {
        who  = "kael",
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
        kv = {["Service"] = "Concord Intelligence", ["War record"] = "Fighter pilot, Settlement War",
              ["Current post"] = "Special Operations Investigations", ["Vessel"] = "CWS Meridian",
              ["Reputation"] = "Asks the questions nobody wants asked"},
    },
}

-- Add a profile entry (no flag). Returns true if it was newly added.
function SCIDB.addProfile(key)
    local p = SCIDB.PROFILES[key]
    if not p or SCIDB._entries[key] or not SCIDB._entries["lore"] then return false end
    SCIDB._entries[key] = SCIDB.addEntry("lore", p.name, p.desc, p.kv)
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

-- Make the database match the campaign flags. Quiet (server log only).
function SCIDB.sync()
    if not (RT and RT.campaign and SCIDB._entries["lore"]) then return end
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
    local e = parent:addEntry(name)
    if desc then e:setLongDescription(desc) end
    if kv then for k, v in pairs(kv) do e:setKeyValue(k, v) end end
    return e
end

local function _locked(parent, name, locked_desc, real_desc, real_kv, lock_key)
    local e = parent:addEntry(name)
    e:setLongDescription(locked_desc)
    SCIDB._locked[lock_key] = {
        entry       = e,
        description = real_desc,
        kv          = real_kv,
        locked_desc = locked_desc,
    }
    return e
end

-- ─── Database construction ────────────────────────────────────────────────────

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

    local regions = _entry(root, "Regions",
        "The Drift is divided into named regions with distinct hazard profiles and " ..
        "political climates. Knowing where you are matters."
    )
    SCIDB._entries["regions"] = regions

    SCIDB._entries["region_core"] = _entry(regions, "The Core",
        "The innermost systems, orbiting the white star Lumen. Rich Concord worlds, " ..
        "heavy patrols, and expensive docking fees. Safe for ships with clean transponders.",
        { ["Star"] = "Lumen (white)", ["Law"] = "Heavy Concord presence", ["Danger"] = "Low — unless you're wanted" }
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
        "that sometimes go offline without explanation.",
        { ["Hazard"] = "Sensor interference", ["Danger"] = "Moderate to high" }
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

    -- ── Factions ─────────────────────────────────────────────────────────────

    local factions = _entry(root, "Factions",
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
        { ["Attitude at rep ≥ 0"] = "Routine inspection, courteous", ["Attitude at rep < -200"] = "Shoot on sight", ["Warp jammer"] = "Comply within 60s or hostile" }
    )

    SCIDB._entries["faction_corsairs"] = _entry(factions, "Corsairs",
        "Organised raiders operating primarily from Blackwater Reach and the Gauntlet. " ..
        "Attack traders on sight unless you have an arrangement with them. " ..
        "More organised than they appear — attacks in Concord-patrolled space " ..
        "suggest coordination and insider knowledge.",
        { ["Territory"] = "Blackwater Reach, Gauntlet", ["Attitude"] = "Hostile to unknown ships", ["Note"] = "Rep affects spawn rate" }
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
        { ["Origin"] = "Human (Concord test subjects)", ["Status"] = "Ongoing — self-sustaining", ["Reversal"] = "Phase II protocol (theoretical)" },
        "hollow_true_nature"
    )

    -- ── Lore ─────────────────────────────────────────────────────────────────

    local lore = _entry(root, "Lore",
        "Historical records, research summaries, and recovered documents. " ..
        "Updated as new information is retrieved."
    )
    SCIDB._entries["lore"] = lore

    SCIDB._entries["lore_settlement_war"] = _entry(lore, "The Settlement War",
        "Twenty years ago, Border and Rim colonial worlds attempted to break from " ..
        "Concord governance over tariff disputes and trade route control. " ..
        "The war lasted four years. Concord won by attrition — not decisive battle, " ..
        "but economic blockade and systematic destruction of Rim infrastructure. " ..
        "The peace treaty restored Concord authority with new 'transitional' tariffs " ..
        "that have not transitioned. Ashgrave was destroyed during the final campaign. " ..
        "The Relic drones were left running. Nobody has explained why.",
        { ["Duration"] = "~4 years, ended 20 years ago", ["Outcome"] = "Concord victory", ["Unresolved"] = "Drones still active; Maw sealed" }
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
        { ["Classification"] = "Destroy on intercept", ["Status"] = "Research discontinued", ["Reversal protocol"] = "Archived — not destroyed" },
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
        { ["Type"] = "Engineered biological compound", ["Reversible"] = "Phase II broadcast protocol", ["Broadcast frequency"] = "In Ashgrave archive, Phase II" },
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

function _P.init(state)
    -- Best-effort: clear auto-populated ship-template entries.
    -- getAllObjects() only returns entities with positions, so ScienceDatabase
    -- entries may not appear. This is harmless if they're not returned.
    for _, obj in ipairs(getAllObjects()) do
        if isObjectType(obj, "ScienceDatabase") then
            obj:destroy()
        end
    end
    _build()
end

function _P.update(state, delta, now) end

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
