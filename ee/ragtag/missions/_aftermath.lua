-- ee/ragtag/missions/_aftermath.lua
-- AFTERMATH: the rumors that follow the crew's exploits, in one list.
--
-- Each entry is a rumor with a fixed id, the category of the arc it belongs to (so an arc's reset
-- still removes it with RUMORS.removeCategory) and a condition on the saved arc flags. AFTERMATH.sync
-- puts on the rumor pool every entry whose condition holds and takes off every entry whose condition
-- no longer holds (a GM rewind). It runs every second from MISSIONS.update, at session start and
-- whenever an arc resolves, so the rumors come back every session.
--
-- News is told once: when a ship hears an aftermath rumor it is marked in the campaign save
-- (`campaign.rumors_heard`). It stays in rotation for the rest of that session and is not put back
-- in a later one. A rumor whose condition stops holding loses its mark, so a GM replay of an arc
-- brings its news back.
--
-- Rumors that need two arcs go here too: give the entry a condition on both arcs' flags.
-- All entries are priority 3 (seed tier): they share the rumor cooldown and rotate with the
-- background pool; never use a hook priority (>= 4) for news, it drowns out everything else.

AFTERMATH = AFTERMATH or {}

local F = function(name) return RT.flag(name) end

-- The Boneyard fight: won (with or without the drones) or the fleet left alive.
local function _bnyBeaten()
    -- boneyard_fleet_beaten is set at resolve; saves from before it have only the command ship flag.
    return F("boneyard_fleet_beaten") or F("boneyard_battlegroup_destroyed")
end
local function _bnyDone() return F("boneyard_arc_done") end

AFTERMATH.ENTRIES = {
    -- ── Boneyard ────────────────────────────────────────────────────────────
    {id = "aftermath_boneyard_torn_apart", category = "BONEYARD_DONE",
     when = function() return _bnyDone() and _bnyBeaten() and F("boneyard_drone_flip") end,
     text = "Word's out — a Concord battle group got torn apart in the Boneyard. Something woke those drones up. Official Concord statement: none."},
    {id = "aftermath_boneyard_lost_group", category = "BONEYARD_DONE",
     when = function() return _bnyDone() and _bnyBeaten() and not F("boneyard_drone_flip") end,
     text = "A Concord battle group went into the Boneyard and didn't come out. Official Concord statement: none."},
    {id = "aftermath_boneyard_swept", category = "BONEYARD_DONE",
     when = function() return _bnyDone() and not _bnyBeaten() end,
     text = "Concord swept the Boneyard. Called it a routine security operation. Nobody's buying it."},
    {id = "aftermath_boneyard_pale_sun", category = "BONEYARD_DONE",
     when = _bnyDone,
     text = "Whatever Concord had locked in the Boneyard, someone got to it. The rumors about the Pale Sun are getting louder."},
    {id = "aftermath_boneyard_senate", category = "BONEYARD_DONE",
     when = function() return _bnyDone() and _bnyBeaten() end,
     text = "The Senate's defence committee wants to know how a full battle group was lost on a 'routine security operation'. Fleet Command has asked for the hearing to be held in closed session."},
    {id = "aftermath_boneyard_recalled", category = "BONEYARD_DONE",
     when = function() return _bnyDone() and not _bnyBeaten() end,
     text = "The battle group that swept the Boneyard went straight back to Ostia. No shore leave, no comms, and a Senate aide says nobody will tell them what it was guarding."},

    -- ── Ledger ──────────────────────────────────────────────────────────────
    {id = "aftermath_ledger_audit_stopped", category = "LEDGER_DONE",
     when = function() return F("ledger_arc_done") == "full" end,
     text = "Concord's audit at Lumen just stopped. Nobody closed it. Nobody explains it. The auditors look scared."},
    {id = "aftermath_ledger_resignations", category = "LEDGER_DONE",
     when = function() return F("ledger_arc_done") == "full" end,
     text = "Two senior Treasury clerks at Lumen resigned the same morning. Word is Deputy Secretary Voss has stopped taking meetings."},
    {id = "aftermath_ledger_audit_closed", category = "LEDGER_DONE",
     when = function() return F("ledger_arc_done") == "lost" end,
     text = "Concord closed its audit at Lumen. Official word: an accounting error, corrected."},
    {id = "aftermath_ledger_commendation", category = "LEDGER_DONE",
     when = function() return F("ledger_arc_done") == "lost" end,
     text = "The Audit Service got a commendation and a bigger budget after Lumen. Whatever they caught, the Treasury's very pleased about it."},

    -- ── Corsair ─────────────────────────────────────────────────────────────
    {id = "aftermath_corsair_second_settlement", category = "CORSAIR_DONE",
     when = function() return F("corsair_arc_done") == "defended" end,
     text = "A whole Concord battle group died off Blackwater. The Corsairs are calling it the Second Settlement."},
    {id = "aftermath_corsair_squadrons", category = "CORSAIR_DONE",
     when = function() return F("corsair_arc_done") == "defended" end,
     text = "Fleet Command pulled two squadrons off the Arbiter Line to cover the hole Blackwater left. Border captains say they're stretched thin, and the tariff collectors are nervous."},
    {id = "aftermath_corsair_burning", category = "CORSAIR_DONE",
     when = function() return F("corsair_arc_done") == "failed" end,
     text = "Blackwater's burning, they say. The Concord calls it a clean-up. The Corsair families scattered into the Gauntlet."},
    {id = "aftermath_corsair_medals", category = "CORSAIR_DONE",
     when = function() return F("corsair_arc_done") == "failed" end,
     text = "The Concord's handing out medals for Blackwater. Half the Border stations wouldn't fly the flag for the ceremony."},
}

AFTERMATH.PRIORITY      = 3
AFTERMATH.SYNC_INTERVAL = 1     -- seconds between syncs from MISSIONS.update
AFTERMATH._session_heard = AFTERMATH._session_heard or {}   -- id -> true: heard this session
AFTERMATH._next_sync    = 0

-- The saved "heard" marks (id -> true). nil when there is no campaign (nothing is saved then).
local function _saved()
    local c = RT.campaign
    if type(c) ~= "table" then return nil end
    if type(c.rumors_heard) ~= "table" then c.rumors_heard = {} end
    return c.rumors_heard
end

local function _onPool(id)
    for _, r in ipairs(RUMORS._injected) do if r.id == id then return true end end
    return false
end

local function _heard(e)
    AFTERMATH._session_heard[e.id] = true
    local saved = _saved()
    if saved and not saved[e.id] then
        saved[e.id] = true
        RT.saveCampaign()
    end
end

-- Bring the rumor pool in line with the arc flags.
function AFTERMATH.sync()
    if not RUMORS or not RUMORS.add then return end
    local saved = _saved() or {}
    for _, e in ipairs(AFTERMATH.ENTRIES) do
        local ok, holds = pcall(e.when)
        holds = ok and holds and true or false
        if holds then
            -- Told in an earlier session: retired. Heard this session: keep it in rotation.
            local retired = saved[e.id] and not AFTERMATH._session_heard[e.id]
            if not retired and not _onPool(e.id) then
                RUMORS.add({id = e.id, text = e.text, priority = AFTERMATH.PRIORITY, category = e.category,
                            on_heard = function() _heard(e) end})
            elseif retired and _onPool(e.id) then
                RUMORS.remove(e.id)
            end
        else
            if _onPool(e.id) then RUMORS.remove(e.id) end
            if saved[e.id] then saved[e.id] = nil end   -- a rewind: the news can be told again
            AFTERMATH._session_heard[e.id] = nil
        end
    end
end

function AFTERMATH.update()
    local now = getScenarioTime and getScenarioTime() or 0
    if now < AFTERMATH._next_sync then return end
    AFTERMATH._next_sync = now + AFTERMATH.SYNC_INTERVAL
    AFTERMATH.sync()
end
