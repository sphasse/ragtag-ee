-- ee/ragtag/missions/boneyard.lua
-- Boneyard Arc: breach the Ashgrave Annex before a Concord battle group arrives.
--
-- Trigger: Rezkov arc finished (or declined) AND upgrade investment >= 800cr AND not completed
-- Structure: hook → annex_hack → annex_control → extract → done
--
-- RT.flag keys used (prefix "boneyard_"):
--   arc_done                  arc complete (blocks re-trigger)
--   hack_done                 research archive downloaded
--   drone_flip                drone IFF override completed
--   battlegroup_destroyed     CNS Vanguard destroyed

local M = {}
M.id          = "boneyard"
M.name        = "Boneyard Arc"
M.repeatable  = false
M.locks_jobs  = false
M.auto_start  = true
M.start_phase = "hook"

M.triggers = {
    upgrades_min = 800,
    not_flagged  = {"boneyard_arc_done"},
    -- Phase II follows the Rezkov arc. A crew that declined Rezkov (or had it
    -- GM-inactivated) is not locked out of the rest of the campaign.
    custom       = function() return RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined") end,
    custom_label = "Rezkov arc finished or declined",
}

M.phase_order = {
    "hook", "annex_hack", "annex_control", "extract",
}

-- ── Coordinates ──────────────────────────────────────────────────────────────

local U = 1000  -- world units per verse unit

local _ASHGRAVE_X   =  39000   -- Ashgrave dead world (hook scan target)
local _ASHGRAVE_Y   = -96000
local _ANNEX_X      =  43000   -- Ashgrave Annex deep in the debris field
local _ANNEX_Y      = -104000
local _BATTLE_X     =   8000   -- Concord battle group initial position (~42U NW of Annex)
local _BATTLE_Y     = -80000
local _REIN_X       =  43000   -- Reinforcement drone spawn (~35U S of Annex, outside scan range)
local _REIN_Y       = -139000
local _BONEYARD_CX  =  36000   -- Boneyard center (for jammer placement and exit check)
local _BONEYARD_CY  = -96000
local _BONEYARD_R   =  29500   -- Boneyard radius in world units (29U + small buffer)

-- ── State ─────────────────────────────────────────────────────────────────────

function M.init_state()
    return {
        annex            = nil,    -- SpaceStation "Ashgrave Annex"
        idle_drones      = {},     -- Relic ships set Derelict when hack completes
        concord_group    = {},     -- Concord Hostile battle group ships
        concord_cmd      = nil,    -- command ship reference
        rein_drones      = {},     -- Relic Active reinforcement wave
        jammer           = nil,    -- WarpJammer over Boneyard
        jammer_spawned   = false,

        hack_mid_logged  = false,  -- mid-hack revelation fired

        downloading      = false,
        download_start   = 0,
        download_done    = false,
        reprogramming    = false,
        reprogram_start  = 0,
        reprogram_done   = false,

        cmd_vulnerable   = false,
    }
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function _dist(x1, y1, x2, y2)
    return math.sqrt((x1 - x2)^2 + (y1 - y2)^2)
end

local function _nearestConcord(st, x, y)
    local best, best_d = nil, math.huge
    for _, s in ipairs(st.concord_group) do
        if RT.valid(s) then
            local cx, cy = s:getPosition()
            local d = _dist(x, y, cx, cy)
            if d < best_d then best_d = d; best = s end
        end
    end
    return best
end

local function _spawnAnnex(st)
    if RT.valid(st.annex) then return end
    local a = SpaceStation():setTemplate("Small Station"):setFaction("Relic")
    a:setPosition(_ANNEX_X, _ANNEX_Y)
    a:setCallSign("Ashgrave Annex")
    a:setCanBeDestroyed(false)
    a:setCommsFunction(function(src, tgt)
        setCommsMessage(
            "[Ashgrave Annex]\n\nEncrypted — military-grade lockdown.\n\n" ..
            "Relay: breach the access codes via system hack."
        )
    end)
    st.annex = a
    log("[BONEYARD] Annex spawned at (" .. _ANNEX_X .. "," .. _ANNEX_Y .. ")")
end

-- Make the Annex appear (idempotent). Called when the survivors are recovered (their telemetry
-- names its grid) or, for a crew following the rumors instead, when they reach Ashgrave.
-- `quiet`: the caller already told the crew about the signal.
local function _annexSignal(st, quiet)
    local fresh = not RT.valid(st.annex)
    _spawnAnnex(st)
    if not fresh then return end
    RUMORS.removeCategory("BONEYARD_HOOK")      -- the lead has paid off
    JOBS.removeCategory("BONEYARD_SPECIAL")
    if not quiet then
        RT.shipLog(
            "[Science] Anomalous signal from deep in the Boneyard. " ..
            "Source: Ashgrave Annex. Bearing inside the debris field.", "#FFCC00")
    end
    RT.shipLog("[Nav] Waypoint set: Ashgrave Annex.", "#AAAAFF")
end

local function _idleDrones(st)
    local found = {}
    local objs = getObjectsInRadius(_BONEYARD_CX, _BONEYARD_CY, 32000)
    for _, obj in ipairs(objs) do
        if isObjectType(obj, "CpuShip") then
            local ok, fac = pcall(function() return obj:getFaction() end)
            if ok and fac == "Relic" then
                pcall(function() obj:setFaction("Derelict"); obj:orderIdle() end)
                found[#found + 1] = obj
            end
        end
    end
    st.idle_drones = found
    log("[BONEYARD] idled " .. #found .. " Relic drones")
end

local function _spawnConcordGroup(st)
    local offsets = {
        {    0,     0},   -- command ship
        {-1500,  1200},
        { 1500,  1200},
        {-2500,  -400},
        { 2500,  -400},
        {    0, -2200},
    }
    local templates = {
        "Phobos T3",
        "Atlantis X23", "Atlantis X23",
        "Atlantis X23", "Atlantis X23",
        "Atlantis X23",
    }

    for i, o in ipairs(offsets) do
        local s = CpuShip():setTemplate(templates[i]):setFaction("Concord Hostile")
        s:setPosition(_BATTLE_X + o[1], _BATTLE_Y + o[2])
        s:setWarpDrive(true)
        s:orderFlyTowards(st.annex)
        st.concord_group[#st.concord_group + 1] = s
        if i == 1 then
            s:setCallSign("CNS Vanguard")
            s:setCanBeDestroyed(false)
            RT.register(s)
            st.concord_cmd = s
        end
    end

    RT.shipLog(
        "[Comms] [CNS Vanguard] All vessels in Boneyard sector: restricted military zone. " ..
        "Stand down and prepare for boarding. Non-compliance will be treated as hostility.", "#FF6666")
end

local function _reprogramDrones(st)
    for _, s in ipairs(st.idle_drones) do
        if RT.valid(s) then
            s:setFaction("Relic Active")
            local sx, sy = s:getPosition()
            local target = _nearestConcord(st, sx, sy)
            if target then
                s:orderAttack(target)
            else
                s:orderRoaming()
            end
        end
    end

    -- Eight-ship reinforcement wave from south, outside scan range
    local positions = {
        { 40000, -130000}, { 44000, -132000}, { 46000, -128000}, { 38000, -131000},
        { 50000, -134000}, { 36000, -129000}, { 48000, -138000}, { 42000, -133000},
    }
    local templates = {
        "WX-Lindworm","WX-Lindworm","WX-Lindworm","WX-Lindworm",
        "Stalker Q7",  "Stalker Q7",  "Stalker R7",  "Stalker R7",
    }

    st.rein_drones = {}
    for i, pos in ipairs(positions) do
        local s = CpuShip():setTemplate(templates[i]):setFaction("Relic Active")
        s:setPosition(pos[1], pos[2])
        s:setWarpDrive(true)
        local target = _nearestConcord(st, pos[1], pos[2])
        if target then
            s:orderAttack(target)
        elseif RT.valid(st.annex) then
            s:orderFlyTowards(st.annex)
        end
        st.rein_drones[#st.rein_drones + 1] = s
    end

    RT.shipLog("[Relay] IFF override complete. All drones retargeting Concord transponders.", "#FF8800")
    RT.shipLog("[Science] Eight Relic contacts inbound from south — fast approach. They are on our side.", "#00FF88")
end

local function _spawnJammer(st)
    if st.jammer_spawned then return end
    st.jammer_spawned = true
    local j = WarpJammer()
    j:setPosition(_BONEYARD_CX, _BONEYARD_CY)
    j:setRange(32000)  -- 32U radius covers full Boneyard
    pcall(function() j:setFaction("Concord Hostile") end)
    st.jammer = j
    RT.shipLog("[Science] Warp signatures suppressed. Concord jammer active. Fly out — warp is down.", "#FF4444")
    RT.sound("jammer_engage", {now = true})
    RT.soundLoop("boneyard_jammer", "jammer_bed", 10, function() return RT.valid(st.jammer) end)
end

local function _setAnnexControlComms(st)
    if not RT.valid(st.annex) then return end
    st.annex:setCommsFunction(function(src, tgt)
        local now = getScenarioTime()
        setCommsMessage(
            "[Ashgrave Annex — Admin Access Granted]\n\n" ..
            "Concord battle group inbound. Time is critical.\n\n" ..
            "Select operation:"
        )

        -- Download option
        if st.download_done then
            addCommsReply("[COMPLETE] Archive download", function()
                setCommsMessage("Transfer complete. Research files indexed in Science database.")
            end)
        elseif st.downloading then
            local elapsed   = now - st.download_start
            local remaining = math.max(0, 60 - math.floor(elapsed))
            addCommsReply("[IN PROGRESS] Downloading archive: " .. remaining .. "s", function()
                setCommsMessage("Transfer in progress. Hold position.")
            end)
        else
            addCommsReply("1) Download research archive (60s)", function(s, t)
                st.downloading    = true
                st.download_start = getScenarioTime()
                RT.shipLog("[Relay] Archive download initiated. 60 seconds to complete.", "#00AAFF")
                setCommsMessage("Transfer started. Stand by for 60 seconds.")
            end)
        end

        -- Reprogram option
        if st.reprogram_done then
            addCommsReply("[COMPLETE] Drone IFF override", function()
                setCommsMessage("Targeting override active. Drones are retargeting Concord.")
            end)
        elseif st.reprogramming then
            local elapsed   = now - st.reprogram_start
            local remaining = math.max(0, 30 - math.floor(elapsed))
            addCommsReply("[IN PROGRESS] IFF reprogram: " .. remaining .. "s", function()
                setCommsMessage("Override sequence running. Stand by.")
            end)
        else
            addCommsReply("2) Reprogram drone IFF targets (30s)", function(s, t)
                st.reprogramming    = true
                st.reprogram_start  = getScenarioTime()
                RT.shipLog("[Relay] Drone IFF override sequence initiated. 30 seconds.", "#FF8800")
                setCommsMessage("Override started. Stand by for 30 seconds.")
            end)
        end

        addCommsReply("Disconnect", function()
            setCommsMessage("Channel closed.")
        end)
    end)
end

local function _cleanupCombat(st)
    for _, s in ipairs(st.concord_group or {}) do
        if RT.valid(s) then
            pcall(function() s:setCanBeDestroyed(true); s:destroy() end)
        end
    end
    for _, s in ipairs(st.rein_drones or {}) do
        if RT.valid(s) then pcall(function() s:destroy() end) end
    end
end

local function _clearState(st)
    if RT.valid(st.annex) then
        pcall(function() st.annex:setCanBeDestroyed(true); st.annex:destroy() end)
    end
    st.annex = nil

    for _, s in ipairs(st.idle_drones or {}) do
        if RT.valid(s) then
            pcall(function() s:setFaction("Relic"); s:orderRoaming() end)
        end
    end
    st.idle_drones = {}

    for _, s in ipairs(st.concord_group or {}) do
        if RT.valid(s) then
            pcall(function() s:setCanBeDestroyed(true); s:destroy() end)
        end
    end
    st.concord_group = {}
    st.concord_cmd   = nil

    for _, s in ipairs(st.rein_drones or {}) do
        if RT.valid(s) then pcall(function() s:destroy() end) end
    end
    st.rein_drones = {}

    if RT.valid(st.jammer) then pcall(function() st.jammer:destroy() end) end
    st.jammer         = nil
    st.jammer_spawned = false
    RT.stopSoundLoop("boneyard_jammer")

    RT.cancelTimer("boneyard_jammer")
    RT.cancelTimer("boneyard_cleanup")

    RUMORS.removeCategory("BONEYARD_HOOK")
    RUMORS.removeCategory("BONEYARD_DONE")
    JOBS.removeCategory("BONEYARD_SPECIAL")

    PROX.resumeZone("the Boneyard")
end

local function _trackCmdShip(st)
    if not st.concord_cmd then return end
    if not RT.valid(st.concord_cmd) then
        st.concord_cmd = nil
        RT.flag("boneyard_battlegroup_destroyed", true)
        RT.shipLog("[Science] CNS Vanguard destroyed. Battle group leaderless.", "#FF4444")
        return
    end
    if not st.cmd_vulnerable then
        local ok,  hull    = pcall(function() return st.concord_cmd:getHull()    end)
        local ok2, max_hul = pcall(function() return st.concord_cmd:getHullMax() end)
        if ok and ok2 and max_hul and max_hul > 0 and hull / max_hul < 0.2 then
            st.cmd_vulnerable = true
            st.concord_cmd:setCanBeDestroyed(true)
            RT.shipLog("[Science] CNS Vanguard hull critical — command ship attempting withdrawal.", "#FFCC00")
        end
    end
end

-- ── Lifecycle (waiting-for-trigger) ───────────────────────────────────────────
-- Seed rumors: vague foreshadowing loaded as soon as the arc is enabled, before
-- its trigger is met. Priority 3 = seed tier (mixed into the normal rumor rotation,
-- slightly favoured over the pool; harmless if never heard). The actionable hooks
-- (priority 5) live in the hook phase.

local _SEED_RUMORS = {
    "Whatever's up north past the Boneyard, Concord stopped talking about it years ago.",
    "Ships that run the Boneyard edge say the drones thin out toward the middle. Nobody's gone far enough to ask why.",
    "My cousin flew survey for Concord. Won't say where. Points north whenever the subject comes up.",
    "There's an old Settlement War rumor that Concord buried something up there instead of winning anything.",
    "Long-range picks up a Concord transponder up north that never moves. It's been there for years.",
    "Salvagers who go deep into the Boneyard come back quiet. Or don't come back.",
    "The Free Ship veterans say the war didn't end where the treaty says it did. They look north when they say it.",
    "Concord keeps flying supply runs up north and logging them as 'training'. Training for what, twenty years on?",
    "If you want to know what the Boneyard is really for, ask why nobody ever finished clearing it.",
    "Something up there still sends a signal on a war-era frequency. Concord jams it. Never the other way round.",
}

-- Seed jobs (priority 3): ordinary-looking deliveries among the north-side stations,
-- so crews are already moving around Halcyon / Vesper / Arbiter / Saint Brennan's.
local _SEED_JOBS = {
    {"Halcyon Rest",           "Concord Station Arbiter",  "sealed legal pouches",   85, "Halcyon's clerks need these filed with Arbiter's registry office. Don't read them."},
    {"Port Vesper",            "Saint Brennan's Mission",  "replacement relay cores", 105, "Brennan's comms array has been dropping packets for a month. The Mission can't pay Concord prices, so a private buyer is covering it."},
    {"Concord Station Arbiter","Halcyon Rest",             "inspection stamps",       80, "Arbiter's stamps for Halcyon's yard. Halcyon pays on delivery and tips if you don't make a fuss."},
    {"Saint Brennan's Mission","Halcyon Rest",             "survey data crates",      95, "The Mission's survey volunteers bag data faster than they can ship it. Take a crate to Halcyon's archive."},
    {"Port Vesper",            "Halcyon Rest",             "coolant canisters",       70, "Halcyon burns through coolant. Standard run."},
}

local function _injectSeedJobs()
    JOBS.removeCategory("BONEYARD_JOBS")
    for _, j in ipairs(_SEED_JOBS) do
        local o, d, cargo, reward, brief = j[1], j[2], j[3], j[4], j[5]
        JOBS.inject({
            category = "BONEYARD_JOBS", priority = 3, origin = o,
            record = function(cs)
                return JOBS.build("delivery", {origin = cs, dest = d, cargo = cargo,
                    reward = reward, brief = brief})
            end,
        })
    end
end

-- Survivor records (Science DB). Added when the survivors are recovered, and re-added at
-- the start of every later session (the DB is rebuilt each run; the flag persists).
local function _survivorRecordsText()
    return table.concat({
        "Testimony and instrument logs from four archive technicians recovered from a lifeboat on the Boneyard's south rim. "
          .. "Unverified. Recorded by people who were never cleared to know what they were looking at.",
        "",
        "WHO THEY ARE\nCatalogue and records staff of the Ashgrave Annex, a Concord Level-5 research archive buried in the debris field "
          .. "beyond Ashgrave. They launched a lifeboat disguised as debris to try and make it out. They drifted among the wrecks until the air ran short.",
        "",
        "THE ANNEX\nIt sits deeper in the debris field than the visible battle damage, north-east of Ashgrave at grid "
          .. JOBS.gridRef(_ANNEX_X, _ANNEX_Y) .. ". Its systems are encrypted and locked down. Anyone with a Relay officer who can breach "
          .. "one of its systems opens the access net. We don't know what the data in there is, but it is clear it is very valuable and the Concord will kill to keep it out of the wrong hands.",
        "",
        "THE DRONES\nThe Relic drones are not rogue. Their war-IFF is slaved to the Annex's own access network, which is why they never stopped "
          .. "fighting: nothing ever told them the war was over. The Concord wants it that way. The drones are protecting what is there. "
          .. "The Annex is the command and control center for the drones.",
        "",
        "CONCORD\nConcord traffic over Ashgrave has been heavy for weeks, logged as 'routine rotation'. Staff were told a heavy response group "
          .. "would arrive to seal the archive permanently. That battle group is expected soon and after that the Annex will be closed off forever.",
        "",
        "THE ARCHIVE\nThe technicians only worked the catalogue desk. The vault index lists a program called 'Ashgrave Synthesis' and a "
          .. "folder marked 'reversal protocol'. Nobody on staff was cleared to open either.",
    }, "\n")
end

local function _addSurvivorRecords()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["boneyard_survivors"] then return end
    local e = SCIDB.addEntry("lore", "Boneyard Survivor Records", _survivorRecordsText(),
        {["Source"] = "Ashgrave Annex archive staff", ["Reliability"] = "Unverified testimony",
         ["Hazards"] = "Relic drones; Concord response group"})
    SCIDB._entries["boneyard_survivors"] = e
end

-- The survivors hail the ship through an RT.voice (a position-less Artifact: never on radar,
-- see ee/ragtag/voice.lua). Falls back to the ship log if comms are busy. Answering the hail
-- opens a short conversation.
local _SURVIVOR_MSG = '"Thank you. We saw a lot of strange activity in the Boneyard while we were stranded, '
    .. 'and we don\'t want those records to be lost, so we\'re uploading them to your database now. Please read them. Ashgrave is where it starts."'

local function _survivorHail()
    RT.voice.create("boneyard_survivors", {
        name = "Lifeboat Survivors", ttl = 300,
        tree = {
            text = _SURVIVOR_MSG,
            replies = {
                {label = "What did you see out there?", next = {
                    text = '"We kept the catalogue desk at the Annex. Then the lockdown came and Concord sealed it from the outside, with us locked out. '
                        .. 'The drones never touched our lifeboat. We think the Annex was keeping them off us. It is all in the records."'}},
                {label = "Rest. We'll get you home.", say = '"Thank you. Please, read the records."'},
            },
        },
    })
    RT.voice.hail("boneyard_survivors", _SURVIVOR_MSG)
    RT.after(5, function()
        _addSurvivorRecords()
        RT.shipLog("[Science] Survivor records received. Science database updated: Lore, Boneyard Survivor Records.", "#00CCAA")
    end, "boneyard_survivor_records")
end

-- Hook job (priority 5): an urgent rescue. A lifeboat of survivors is pinging from the
-- Boneyard south rim. Offered only at the three nearest friendly stations, on the board
-- (no rumor, no objective), 350 cr, 20 minute clock. Recovering them reveals the lead.
-- (22, -72) is inside the Boneyard (center (36, -96), r 29), ~15U off the Galen-Saint
-- Brennan's lane. Survivors: archive staff who got out of the Ashgrave Annex before Concord
-- sealed it. A missed clock re-offers the job (the signal is reacquired). Never re-offered
-- once the survivors have been recovered in any session.
local _BUOY_X, _BUOY_Y = 22000, -72000

-- True while the Rezkov arc is mid-run (M1 to M3). The Boneyard's special job waits for the crew
-- to finish or step out of it, so two story contracts never compete (e.g. a GM replaying Rezkov).
local _REZKOV_ACTIVE = {m1_navigate = true, m2_active = true, m2_deliver = true,
                        m3_active = true, m3_deliver = true}
local function _rezkovBusy()
    return _REZKOV_ACTIVE[MISSIONS._cur_phase and MISSIONS._cur_phase["rezkov"] or ""] == true
end

local function _injectHookJob()
    JOBS.removeCategory("BONEYARD_SPECIAL")
    JOBS.inject({
        category = "BONEYARD_SPECIAL", priority = 5,
        origin = {"Port Vesper", "Halcyon Rest", "Saint Brennan's Mission"},
        when = function() return not RT.flag("boneyard_buoy_found") and not _rezkovBusy() end,
        record = function(cs)
            return JOBS.build("salvage", {
                id = "boneyard_buoy",   -- one shared id: taking it at one station hides the others
                origin = cs, wx = _BUOY_X, wy = _BUOY_Y,
                cargo = "a lifeboat of survivors", reward = 350, story = true, urgent = true,
                time_limit = 20 * 60,
                region_name = "the Boneyard",
                brief = "\"My god. We've picked up a signal: people are alive out there. A lifeboat pod on the south rim of the Boneyard, "
                      .. "air failing, drifting among the Settlement War wrecks. The drones will be on them if the pod's beacon draws attention.\"\n\n"
                      .. "\"Somebody has to go and get them. The Boneyard's no place for a freighter, but you're the nearest crew. "
                      .. "Scan the debris to find the pod, and bring them back here. Fast.\"",
                complete_msg = '"They\'re breathing. They\'re talking. Whatever they\'re saying, I think Concord wants it kept quiet. Thank you."',
                accept_log = string.format("URGENT rescue: lifeboat survivors, grid %s on the Boneyard south rim. Air is failing; 20 minutes. Danger: drones.",
                    JOBS.gridRef(_BUOY_X, _BUOY_Y)),
                on_found = function(m)
                    RT.flag("boneyard_buoy_found", true)
                    RT.shipLog("[Medical] Four survivors, dehydrated, stable.", "#FFAA44")
                    RT.shipLog(string.format("[Science] Survivor lifeboat telemetry: launched from the Annex, grid %s. Concord Level-5 archive hold.", JOBS.gridRef(_ANNEX_X, _ANNEX_Y)), "#00CCAA")
                    _survivorHail()
                    local bst = MISSIONS._state["boneyard"]
                    if bst and MISSIONS._status["boneyard"] == "active"
                       and MISSIONS._cur_phase["boneyard"] == "hook" then
                        _annexSignal(bst, true)   -- the telemetry line above already named its grid
                    end
                end,
            })
        end,
    })
end

function M.on_load(st)
    RUMORS.removeCategory("BONEYARD_SEED")   -- idempotent
    for _, text in ipairs(_SEED_RUMORS) do
        RUMORS.add({text = text, priority = 3, category = "BONEYARD_SEED"})
    end
    _injectSeedJobs()
    if RT.flag("boneyard_buoy_found") then _addSurvivorRecords() end   -- DB is rebuilt each session
end

function M.on_unload(st)
    RUMORS.removeCategory("BONEYARD_SEED")
    JOBS.removeCategory("BONEYARD_JOBS")
end

-- ── Phases ────────────────────────────────────────────────────────────────────

M.phases = {

    hook = {
        enter = function(st)
            -- Re-inject each session (RUMORS resets per run); clear first so a
            -- GM re-entry of this phase doesn't duplicate them.
            RUMORS.removeCategory("BONEYARD_HOOK")
            _injectHookJob()
            -- Hooks: few, and nearly actionable. Priority 5 = same tier as other arcs'
            -- hooks, so a crew with several leads hears all of them.
            RUMORS.add({
                text     = "Concord survey tugs have been parking over Ashgrave, deep in the Boneyard. Nobody surveys a dead world for fun.",
                priority = 5, category = "BONEYARD_HOOK",
            })
            RUMORS.add({
                text     = "Concord pulled two battle groups off the Lumen run and pointed them north. Whatever's sitting at Ashgrave, they want it sealed before anyone else sees it.",
                priority = 5, category = "BONEYARD_HOOK",
            })
            RUMORS.add({
                text     = "A salvager swears the Boneyard drones go quiet near Ashgrave. Like they're guarding something, or told to leave it alone.",
                priority = 5, category = "BONEYARD_HOOK",
            })
        end,
        update = function(st, delta, now)
            local players = RT.players
            if not players or not players[1] then return end
            local player = players[1]
            if not RT.valid(player) then return end
            local px, py = player:getPosition()
            if RT.valid(st.annex) then
                -- The Annex is out (survivors recovered, or the crew came by Ashgrave): closing
                -- to 2.5U starts the hack.
                local ax, ay = st.annex:getPosition()
                if _dist(px, py, ax, ay) < 2.5 * U then
                    MISSIONS.phase("boneyard", "annex_hack")
                end
            elseif _dist(px, py, _ASHGRAVE_X, _ASHGRAVE_Y) < 8 * U then
                -- No survivors yet: a crew following the rumors finds it at Ashgrave. 8U clears
                -- the planet (radius 3.4U) comfortably.
                _annexSignal(st)
            end
        end,
        exit = function(st)
            RUMORS.removeCategory("BONEYARD_HOOK")
            JOBS.removeCategory("BONEYARD_SPECIAL")
        end,
    },

    annex_hack = {
        enter = function(st)
            if RT.valid(st.annex) then
                st.annex:setCommsFunction(function(src, tgt)
                    setCommsMessage(
                        "[Ashgrave Annex]\n\n" ..
                        "Encrypted — military-grade lockdown on all channels.\n\n" ..
                        "Relay: hack any system to gain access."
                    )
                end)
            end
            RT.shipLog("[Science] Ashgrave Annex: encrypted lockdown. Relay, that is a hacking job: breach any system.", "#FFAA44")
            -- Diagnostics (EmptyEpsilon.log): is the Annex a valid hack target?
            if RT.valid(st.annex) then
                local okf, fac = pcall(function() return st.annex:getFaction() end)
                local oks, has = pcall(function() return st.annex:hasSystem("frontshield") end)
                log("[BONEYARD] annex_hack: faction=" .. tostring(okf and fac) ..
                    " hasFrontshield=" .. tostring(oks and has))
            end
            st.hack_last_logged = -1
        end,
        update = function(st, delta, now)
            if not RT.valid(st.annex) then return end

            local ok, hack_lvl = pcall(function()
                return st.annex:getSystemHackedLevel("frontshield")
            end)
            if not ok then hack_lvl = 0 end
            if not hack_lvl then hack_lvl = 0 end
            -- Log each 5% step so a playtest shows whether the Relay hack lands.
            local step = math.floor(hack_lvl * 20)
            if step ~= st.hack_last_logged then
                st.hack_last_logged = step
                log("[BONEYARD] Annex frontshield hacked level = " .. string.format("%.2f", hack_lvl))
            end

            if not st.hack_mid_logged and hack_lvl >= 0.5 then
                st.hack_mid_logged = true
                RT.shipLog(
                    "[Science] Partial decryption. These files are marked Concord Level 5. " ..
                    "This is not a standard military installation.", "#FFCC00")
            end

            if hack_lvl >= 1.0 then
                -- Silence the drones and lock the zone
                _idleDrones(st)
                PROX.suspendZone("the Boneyard")

                -- Concord battle group: ~85 seconds travel time at warp
                _spawnConcordGroup(st)

                -- Warp jammer deploys 90 seconds after control phase enters
                RT.after(90, function()
                    if MISSIONS._status["boneyard"] ~= "active" then return end
                    local cst = MISSIONS._state["boneyard"]
                    if cst then _spawnJammer(cst) end
                end, "boneyard_jammer")

                MISSIONS.phase("boneyard", "annex_control")
            end
        end,
    },

    annex_control = {
        enter = function(st)
            RT.shipLog("[Relay] Ashgrave Annex: access granted. Concord battle group inbound.", "#00FF88")
            RT.shipLog("[Science] All Relic drones idle. That won't last.", "#FFCC00")
            _setAnnexControlComms(st)
        end,
        update = function(st, delta, now)
            -- Download timer
            if st.downloading and not st.download_done then
                if now - st.download_start >= 60 then
                    st.download_done = true
                    RT.flag("boneyard_hack_done", true)
                    RT.shipLog("[Relay] Research archive download complete. Data secured.", "#00AAFF")
                end
            end

            -- Reprogram timer
            if st.reprogramming and not st.reprogram_done then
                if now - st.reprogram_start >= 30 then
                    st.reprogram_done = true
                    RT.flag("boneyard_drone_flip", true)
                    _reprogramDrones(st)
                end
            end

            _trackCmdShip(st)

            -- Advance to extract when player moves >10U from Annex
            local players = RT.players
            if not players or not players[1] then return end
            local player = players[1]
            if not RT.valid(player) then return end
            local px, py = player:getPosition()
            local ax, ay
            if RT.valid(st.annex) then
                ax, ay = st.annex:getPosition()
            else
                ax, ay = _ANNEX_X, _ANNEX_Y
            end
            if _dist(px, py, ax, ay) > 10 * U then
                MISSIONS.phase("boneyard", "extract")
            end
        end,
    },

    extract = {
        enter = function(st)
            _spawnJammer(st)  -- ensure jammer is up regardless of timer state
            RT.shipLog("[Nav] Exit the Boneyard. Warp is suppressed inside the jammer radius.", "#FFAA44")
        end,
        update = function(st, delta, now)
            _trackCmdShip(st)

            local players = RT.players
            if not players or not players[1] then return end
            local player = players[1]
            if not RT.valid(player) then return end
            local px, py = player:getPosition()
            if _dist(px, py, _BONEYARD_CX, _BONEYARD_CY) > _BONEYARD_R then
                MISSIONS.phase("boneyard", "done")
            end
        end,
        exit = function(st)
            if RT.valid(st.jammer) then
                pcall(function() st.jammer:destroy() end)
            end
            st.jammer = nil
            RT.stopSoundLoop("boneyard_jammer")
            RT.sound("jammer_release", {now = true})
        end,
    },
}

-- ── Resolve ───────────────────────────────────────────────────────────────────

function M.resolve(st)
    RT.flag("boneyard_arc_done", true)

    local concord_delta = -300
    if RT.flag("boneyard_drone_flip") then
        concord_delta = concord_delta - 200
        RT.addReputation("Corsairs", 150, "Enemy of Concord battle group")
    end
    RT.addReputation("Concord", concord_delta, "Ashgrave Annex breach")

    if RT.flag("boneyard_hack_done")  then RT.addCredits(600, "Ashgrave research data") end
    if RT.flag("boneyard_drone_flip") then RT.addCredits(200, "Drone tactical bonus")   end

    if RT.flag("boneyard_hack_done") then
        SCIDB.unlock("hollow_true_nature")
        SCIDB.unlock("ashgrave_research")
        SCIDB.unlock("synthesis_details")
        RT.shipLog("[Science] Ashgrave research files indexed. Database updated.", "#00CCAA")
    end

    if RT.flag("boneyard_drone_flip") then
        RUMORS.add({
            text     = "Word's out — a Concord battle group got torn apart in the Boneyard. Something woke those drones up. Official Concord statement: none.",
            priority = 4, category = "BONEYARD_DONE",
        })
    else
        RUMORS.add({
            text     = "Concord swept the Boneyard. Called it a routine security operation. Nobody's buying it.",
            priority = 3, category = "BONEYARD_DONE",
        })
    end
    RUMORS.add({
        text     = "Whatever Concord had locked in the Boneyard, someone got to it. The rumors about the Pale Sun are getting louder.",
        priority = 3, category = "BONEYARD_DONE",
    })

    PROX.resumeZone("the Boneyard")

    RT.after(120, function()
        if MISSIONS._state["boneyard"] then
            _cleanupCombat(MISSIONS._state["boneyard"])
        end
    end, "boneyard_cleanup")

    local outcome = RT.flag("boneyard_hack_done") and RT.flag("boneyard_drone_flip") and "full"
                 or RT.flag("boneyard_hack_done")  and "data_only"
                 or RT.flag("boneyard_drone_flip")  and "drones_only"
                 or "minimal"
    RT.shipLog("[Mission] Boneyard arc resolved. Outcome: " .. outcome .. ".", "#80FF80")
end

-- ── Cancel ────────────────────────────────────────────────────────────────────

function M.on_cancel(st)
    _clearState(st)
end

-- ── GM actions ────────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"boneyard_"}

-- Short state label for the "Mission state" popup.
M.gm_state_fn = function()
    local st = MISSIONS._status["boneyard"]
    local ph = MISSIONS._cur_phase["boneyard"]
    if st == "done" then
        return "Complete (hack=" .. tostring(RT.flag("boneyard_hack_done") and true or false)
            .. ", flip=" .. tostring(RT.flag("boneyard_drone_flip") and true or false) .. ")"
    end
    return ph or st
end

-- GM "→" buttons (labels max 18 chars). "→ Inactive" is the engine default (stop and disable).
local function _gmJump(phase, setup)
    return function(st)
        _clearState(st)
        if setup then setup(st) end
        MISSIONS.phase("boneyard", phase)
    end
end

local function _gmDone(hack, flip)
    return function(st)
        _clearState(st)
        if hack then RT.flag("boneyard_hack_done", true)  else RT.clearFlag("boneyard_hack_done") end
        if flip then RT.flag("boneyard_drone_flip", true) else RT.clearFlag("boneyard_drone_flip") end
        MISSIONS.phase("boneyard", "done")
    end
end

M.gm_states = {
    {key = "hook",     label = "→ Hook",          fn = _gmJump("hook")},
    {key = "hack",     label = "→ Annex hack",    fn = _gmJump("annex_hack", function(st) _spawnAnnex(st) end)},
    {key = "control",  label = "→ Annex control", fn = _gmJump("annex_control", function(st)
        _spawnAnnex(st)
        _idleDrones(st)
        PROX.suspendZone("the Boneyard")
        _spawnConcordGroup(st)
        RT.after(90, function()
            if MISSIONS._status["boneyard"] ~= "active" then return end
            local cst = MISSIONS._state["boneyard"]
            if cst then _spawnJammer(cst) end
        end, "boneyard_jammer")
    end)},
    {key = "extract",  label = "→ Extract",       fn = _gmJump("extract", function(st)
        PROX.suspendZone("the Boneyard")
    end)},
    -- End states: which of the two objectives (Annex data, drone flip) were achieved.
    {key = "done_full",    label = "→ Done: Full",    fn = _gmDone(true,  true)},
    {key = "done_data",    label = "→ Done: Data",    fn = _gmDone(true,  false)},
    {key = "done_drones",  label = "→ Done: Drones",  fn = _gmDone(false, true)},
    {key = "done_minimal", label = "→ Done: Minimal", fn = _gmDone(false, false)},
}

-- No phase-specific helpers yet.
M.gm_actions = {}

-- ── Register ──────────────────────────────────────────────────────────────────

MISSIONS.register(M)
