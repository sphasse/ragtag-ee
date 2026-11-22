-- ee/ragtag/missions/boneyard.lua
-- Boneyard Arc: breach the Ashgrave Annex, download its archive while a Concord battle fleet
-- tries to stop it, and bring the news back to the lifeboat survivors.
--
-- Trigger: Rezkov arc finished (or declined) AND upgrade investment >= 800cr AND not completed
-- Structure: hook (the survivors brought home) → annex_hack (Relay hacks it) → annex_control (dock: the operations,
-- the Concord fleet jumps in) → report (talk with the survivors where they were dropped off) → done.
-- A crew that found the Annex without rescuing the survivors is done when the fight is.
--
-- Saved flags: M.flags, below.

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
    requires       = function() return RT.flag("rezkov_arc_done") or RT.flag("rezkov_declined") end,
    requires_label = "Rezkov arc finished or declined",
}

M.phase_order = {
    "hook", "annex_hack", "annex_control", "report",
}

-- ── Coordinates ──────────────────────────────────────────────────────────────

local U = 1000  -- world units per verse unit

local _ASHGRAVE_X   =  39000   -- Ashgrave dead world (hook scan target)
local _ASHGRAVE_Y   = -96000
local _ANNEX_X      =  43000   -- Ashgrave Annex deep in the debris field
local _ANNEX_Y      = -104000
local _BONEYARD_CX  =  36000   -- Boneyard center (the drones the hack idles; the exit check)
local _BONEYARD_CY  = -96000
local _LEAVE_R      =  49000   -- the Boneyard's radius (29U) + 20U: past this the crew has left

-- ── State ─────────────────────────────────────────────────────────────────────

function M.init_state()
    return {
        annex            = nil,    -- SpaceStation "Ashgrave Annex"
        idle_drones      = {},     -- Relic drones and gun platforms set Derelict when the hack completes
        annex_battle     = nil,    -- BATTLE.annex: the Concord group, the drones, the Annex's lasers
        concord_beaten   = false,  -- the last Concord ship is gone (the Annex said so)
        fleet_arrived    = false,  -- the crew docked at the Annex and the Concord fleet jumped in
        archive_compressed = false,  -- the fleet is gone: the download takes _DOWNLOAD_FAST
        download_time    = nil,    -- a download running at compression: its shortened total (s)
        idle_next        = 0,      -- next check for Relic drones to idle (new arrivals too)
        concord_group    = {},     -- Concord Hostile battle group ships
        concord_cmd      = nil,    -- command ship reference
        rein_drones      = {},     -- Relic Active drones (every one spawned, replacements too)

        hack_mid_logged  = false,  -- mid-hack revelation fired

        -- Annex operations (_OPS): <key>_start is when it began (nil: not started), <key>_done.
        download_start   = nil,
        download_done    = false,
        reprogram_start  = nil,
        reprogram_done   = false,
        lasers_start     = nil,
        lasers_done      = false,

    }
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

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
        ARC.log(
            "[Science] Anomalous signal from deep in the Boneyard. " ..
            "Source: Ashgrave Annex. Bearing inside the debris field.", "#FFCC00")
    end
    ARC.log("[Nav] Waypoint set: Ashgrave Annex.", "#AAAAFF")
end

-- Every Relic drone in the Boneyard goes Derelict and idle (the hack took their IFF offline). Kept
-- in st.idle_drones, so a reset gives them back to the Relic. Called again every 2 s after the
-- hack (_keepDronesIdle), so drones that arrive later are docile too.
local function _idleDrones(st)
    st.idle_drones = st.idle_drones or {}
    local n = 0
    for _, obj in ipairs(getObjectsInRadius(_BONEYARD_CX, _BONEYARD_CY, 32000)) do
        if isObjectType(obj, "CpuShip") then
            local ok, fac = pcall(function() return obj:getFaction() end)
            if ok and fac == "Relic" then
                pcall(function() obj:setFaction("Derelict"); obj:orderIdle() end)
                st.idle_drones[#st.idle_drones + 1] = obj
                n = n + 1
            end
        end
    end
    -- The Boneyard's gun platforms (PLATFORMS) are on the same net: Derelict, they stop firing
    -- (they only fire on ships of a hostile faction). Kept in the same list, so a reset gives them
    -- back to the Relic too. The Annex is not a platform.
    for _, t in ipairs((PLATFORMS and PLATFORMS.list) or {}) do
        local s = t.obj
        if RT.valid(s) and s ~= st.annex then
            local ok, fac = pcall(function() return s:getFaction() end)
            local x, y = s:getPosition()
            if ok and fac == "Relic" and ARC.dist(x, y, _BONEYARD_CX, _BONEYARD_CY) < 32000 then
                pcall(function() s:setFaction("Derelict") end)
                st.idle_drones[#st.idle_drones + 1] = s
                n = n + 1
            end
        end
    end
    if n > 0 then log("[BONEYARD] idled " .. n .. " Relic drones and platforms") end
end

local function _keepDronesIdle(st, now)
    if now < (st.idle_next or 0) then return end
    st.idle_next = now + 2
    _idleDrones(st)
end

-- A message on every console of the arc ship (a pop-up each station dismisses).
local _CONSOLES = {"Helms", "Weapons", "Engineering", "Engineering+", "Science", "Relay", "Tactical",
                   "Operations", "SinglePilot", "AltRelay"}
local function _alertCrew(id, text)
    ARC.withPlayer(function(p)
        for _, pos in ipairs(_CONSOLES) do
            pcall(function() p:addCustomMessage(pos, id .. "_" .. pos, text) end)
        end
    end)
end

-- The Annex fight is BATTLE.annex (ragtag/battle.lua; the Battle Lab's Annex mode runs the same
-- code): when the crew first docks, a seven-ship Concord battle group jumps in on a line 15U
-- north-west of the Annex (no warp, the Battle Lab's speeds) and heads for five combat points 3U
-- north-west of it, engaging the crew there. The drone flip launches 24 small, fast Relic drones
-- (lasers 3x a stock drone's) from the nebulae north-east and south-west of the Annex, each
-- replaced from its own nebula when it dies while any Concord ship is left. A separate operation
-- turns the Annex's own lasers on the Concord. With all three done, a rout; with the Concord gone,
-- the drones guard the Annex.
local function _spawnConcordGroup(st)
    if not RT.valid(st.annex) then return end
    st.annex_battle = st.annex_battle or BATTLE.annex(st.annex)
    st.concord_group = st.annex_battle:spawnConcord()
    st.concord_cmd = st.annex_battle.cmd
    if RT.valid(st.concord_cmd) then ARC.register(st.concord_cmd) end
    ARC.log(
        "[Comms] [CNS Vanguard] All vessels in Boneyard sector: restricted military zone. " ..
        "Stand down and prepare for boarding. Non-compliance will be treated as hostility.", "#FF6666")
end

-- The crew docks for the first time: the Concord fleet jumps in, and every console hears it.
local _FLEET_ALERT = "Incoming jump detected. A Concord battle fleet has arrived."
local function _fleetArrives(st)
    st.fleet_arrived = true
    _alertCrew("boneyard_fleet", _FLEET_ALERT)
    ARC.log("[Science] " .. _FLEET_ALERT, "#FF6666")
    _spawnConcordGroup(st)
end

local function _tickBattle(st, now)
    local A = st.annex_battle
    if not A then return end
    A:tick(now)
    -- Tell the crew the fight is won (once): the last Concord ship is gone. The Annex hails; if
    -- comms are busy (Relay is often in its menu), the line goes to the ship's log instead.
    if not st.concord_beaten and #A.concord > 0 and A:concordAlive() == 0 then
        st.concord_beaten = true
        local msg = "All Concord forces in proximity have been eliminated."
        if not ARC.hail(st.annex, msg, "Ashgrave Annex") then
            ARC.log("[Ashgrave Annex] " .. msg, "#00FF88")
        end
    end
end

local function _reprogramDrones(st)
    if not st.annex_battle then return end
    st.annex_battle:spawnDrones()
    st.rein_drones = st.annex_battle.drones   -- the battle appends replacements to this list
    ARC.log("[Relay] Drone reprogram complete. The drones are hostile to the Concord.", "#FF8800")
    ARC.log("[Science] Relic drone swarms launching from the nebulae north-east and south-west of us. " ..
        "Fast movers, and they are on our side.", "#00FF88")
end

-- Unlock the Ashgrave Science DB entries once the archive has been downloaded (idempotent: the
-- log line fires only the first time, so resolve() can call it again for GM jumps to a done state).
local function _indexAshgraveResearch()
    local L = SCIDB._locked and SCIDB._locked["hollow_true_nature"]
    if L and L.unlocked then return end
    ARC.log("[Science] Ashgrave research files indexed.", "#00CCAA")   -- SCIDB announces each entry
    SCIDB.unlock("hollow_true_nature")
    SCIDB.unlock("ashgrave_research")
    SCIDB.unlock("synthesis_details")
end

-- The Annex's admin operations, one at a time, offered only to a ship docked at the Annex. The
-- Concord fleet jumps in on the first docking, the drones and the lasers only help once their
-- operation finishes, and the download needs the docking clamp the whole time (undocking stops
-- it; it starts again from the beginning). `needs_dock`: the operation stops when the crew undocks.
-- The download is long (_DOWNLOAD_SLOW) while the Concord fleet is out: the Annex's link is busy
-- with its own defence. Once the fleet is gone the archive is compressed and it takes
-- _DOWNLOAD_FAST, a running one included (_opTime). So the sensible order is the drones first,
-- then the fight, then a short docked download.
local _DOWNLOAD_SLOW = 300
local _DOWNLOAD_FAST = 60
local _OPS = {
    {key = "download",  label = "Download research archive",      time = _DOWNLOAD_SLOW, needs_dock = true,
     running = "Downloading archive", done = "Archive download", color = "#00AAFF",
     started = "[Relay] Archive download initiated. Stay docked until it finishes.",
     busy_msg = "Transfer in progress. Stay docked: the link runs through the docking clamp.",
     done_msg = "Transfer complete. Research files indexed in Science database."},
    {key = "reprogram", label = "Reprogram the drones to be hostile to the Concord", time = 60,
     running = "Reprogramming drones", done = "Drones reprogrammed", color = "#FF8800",
     started = "[Relay] Drone reprogram initiated. 60 seconds.",
     busy_msg = "Reprogram running. Stand by.",
     done_msg = "The drones are hostile to the Concord."},
    {key = "lasers",    label = "Enable station defense lasers",   time = 60,
     running = "Defense grid boot", done = "Station defense lasers", color = "#FF4444",
     started = "[Relay] Annex defense grid boot sequence initiated. 60 seconds.",
     busy_msg = "Defense grid booting. Stand by.",
     done_msg = "Defense lasers online. Targeting Concord transponders."},
}

-- The operation running now, if any.
local function _runningOp(st)
    for _, op in ipairs(_OPS) do
        if st[op.key .. "_start"] and not st[op.key .. "_done"] then return op end
    end
end

-- How long an operation takes now: the download is short once the archive has been compressed
-- (st.download_time: the total for a download that was already running then).
local function _opTime(st, op)
    if op.key == "download" and st.archive_compressed then return st.download_time or _DOWNLOAD_FAST end
    return op.time
end

local function _fmtSecs(t)
    return t >= 120 and (t // 60 .. " min") or (t .. "s")
end

-- The Concord fleet is gone: the Annex compresses the archive. Not started yet: it takes
-- _DOWNLOAD_FAST. Running: it finishes within _DOWNLOAD_FAST of now (sooner if it was nearly done).
local function _compressArchive(st)
    if st.archive_compressed or st.download_done then return end
    st.archive_compressed = true
    local s = st.download_start
    if s then
        local elapsed = getScenarioTime() - s
        st.download_time = elapsed + math.min(_DOWNLOAD_SLOW - elapsed, _DOWNLOAD_FAST)
    end
    local msg = "Concord forces gone. Archive compressed: the download now takes one minute."
    if s then msg = "Concord forces gone. Archive compressed: the download finishes within a minute." end
    ARC.log("[Ashgrave Annex] " .. msg, "#00AAFF")
end

local _ONE_AT_A_TIME = "The Annex runs one operation at a time. Wait for the current one to finish."
local _DOCK_FIRST    = "[Ashgrave Annex]\n\nStation security has been reset. Dock for more options."

local function _setAnnexControlComms(st)
    if not RT.valid(st.annex) then return end
    -- The operations menu. "Refresh" redraws it, so the crew can watch a countdown without
    -- disconnecting (playtest); the screens it leads to come back to it the same way.
    local menu
    local function back(label)
        addCommsReply(label or "Back to the operations", function(s2, t2) menu(s2, t2) end)
    end
    menu = function(src, tgt)
        if not ARC.docked(src, tgt, _DOCK_FIRST) then return end
        local now = getScenarioTime()
        local fleet = (st.fleet_arrived and not st.concord_beaten) and "Concord battle fleet in proximity.\n\n" or ""
        setCommsMessage(
            "[Ashgrave Annex — Admin Access Granted]\n\n" .. fleet ..
            "The archive link runs through the docking clamp: undocking stops a download.\n\n" ..
            "The Annex runs one operation at a time. Select operation:"
        )
        for i, op in ipairs(_OPS) do
            local running = _runningOp(st)
            if st[op.key .. "_done"] then
                addCommsReply("[COMPLETE] " .. op.done, function() setCommsMessage(op.done_msg); back() end)
            elseif running == op then
                local remaining = math.max(0, math.ceil(_opTime(st, op) - (now - st[op.key .. "_start"])))
                addCommsReply("[IN PROGRESS] " .. op.running .. ": " .. remaining .. "s", function()
                    setCommsMessage(op.busy_msg)
                    back()
                end)
            elseif running then
                addCommsReply("[LOCKED] " .. op.label, function() setCommsMessage(_ONE_AT_A_TIME); back() end)
            else
                local secs = _fmtSecs(_opTime(st, op))
                addCommsReply(i .. ") " .. op.label .. " (" .. secs .. ")", function(s2, t2)
                    if not ARC.docked(s2, t2, _DOCK_FIRST) then return end
                    if _runningOp(st) then setCommsMessage(_ONE_AT_A_TIME); back(); return end
                    st[op.key .. "_start"] = getScenarioTime()
                    ARC.log(op.started, op.color)
                    setCommsMessage("Operation started. Stand by for " .. secs .. ".")
                    back()
                end)
            end
        end
        back("Refresh")
        addCommsReply("Disconnect", function()
            setCommsMessage("Channel closed.")
        end)
    end
    st.annex:setCommsFunction(ARC.comms(menu, "[Ashgrave Annex]\n\nAdmin session in use by another vessel."))
end

-- The hack landed: the Annex stops being an enemy (Relic Active: hostile to the Concord only), so
-- the crew can dock, and its comms say so.
local function _secureAnnex(st)
    if not RT.valid(st.annex) then return end
    st.annex:setFaction("Relic Active")
    _setAnnexControlComms(st)
end

local function _cleanupCombat(st)
    if st.annex_battle then st.annex_battle:clear() end
    ARC.kill(st.concord_group)
    ARC.kill(st.rein_drones)
end

local function _clearState(st)
    ARC.kill(st.annex)
    st.annex = nil

    for _, s in ipairs(st.idle_drones or {}) do
        if RT.valid(s) then
            pcall(function() s:setFaction("Relic"); s:orderRoaming() end)
        end
    end
    st.idle_drones = {}

    if st.annex_battle then st.annex_battle:clear() end
    st.annex_battle = nil
    ARC.kill(st.concord_group)
    st.concord_group = {}
    st.concord_cmd   = nil

    ARC.kill(st.rein_drones)
    st.rein_drones = {}

    RT.cancelTimer("boneyard_cleanup")

    RUMORS.removeCategory("BONEYARD_HOOK")
    RUMORS.removeCategory("BONEYARD_DONE")
    JOBS.removeCategory("BONEYARD_SPECIAL")
    RT.clearObjective("boneyard")

    PROX.resumeZone("the Boneyard")
end

local function _trackCmdShip(st)
    if not st.concord_cmd then return end
    if not RT.valid(st.concord_cmd) then
        st.concord_cmd = nil
        RT.flag("boneyard_battlegroup_destroyed", true)
        ARC.log("[Science] CNS Vanguard destroyed. Battle group leaderless.", "#FF4444")
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
        "Testimony and instrument logs from four Ashgrave Annex staff recovered from a lifeboat on the Boneyard's south rim, "
          .. "uploaded by senior researcher Mara Quill. Unverified.",
        "",
        "WHO THEY ARE\nDr. Mara Quill, a senior researcher, and three catalogue technicians of the Ashgrave Annex, a Concord Level-5 "
          .. "research archive buried in the debris field beyond Ashgrave. They launched a lifeboat disguised as debris to try and make "
          .. "it out. They drifted among the wrecks until the air ran short.",
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
        "THE ARCHIVE\nThe vault index lists a program called 'Ashgrave Synthesis' and a folder marked 'reversal protocol'. "
          .. "The technicians were never cleared to open either. Quill was: she worked on the reversal program until it was shut "
          .. "down, and its data stayed locked in the Annex.",
    }, "\n")
end

local function _addSurvivorRecords()
    if not SCIDB or not SCIDB.addEntry or SCIDB._entries["boneyard_survivors"] then return end
    local e = SCIDB.addEntry("lore", "Boneyard Survivor Records", _survivorRecordsText(),
        {["Source"] = "Dr. Mara Quill and staff", ["Reliability"] = "Unverified testimony",
         ["Hazards"] = "Relic drones; Concord fleet"})
    SCIDB._entries["boneyard_survivors"] = e
end

-- The survivors hail the ship through an RT.voice (an Artifact with no position: never on radar,
-- see ee/ragtag/voice.lua). Falls back to the ship log if comms are busy. A statement, not a
-- conversation: they ask the crew to come back for the Annex, and nothing needs an answer.
local _SURVIVOR_MSG = '"Thank you. This is Mara Quill, senior researcher at the Ashgrave Annex. We saw a lot of strange activity in '
    .. 'the Boneyard while we were stranded, and we don\'t want those records to be lost, so we\'re uploading them to your database '
    .. 'now. Ashgrave is where it starts."\n\n'
    .. '"Please get us out of here, but somebody needs to take a look at our records and come back and investigate. '
    .. 'Those drones are whacko, but if the Annex could be hacked and all the research extracted, someone might actually be held accountable."'

local function _survivorHail()
    RT.voice.create("boneyard_survivors", {
        name = "Mara Quill", ttl = 300,
        tree = {text = _SURVIVOR_MSG},
    })
    if not ARC.hail(RT.voice.get("boneyard_survivors"), _SURVIVOR_MSG, "Mara Quill") then
        ARC.log("[Mara Quill] " .. _SURVIVOR_MSG, "#C0E0FF")   -- comms busy: never lose it
    end
    RT.after(5, function()
        ARC.log("[Science] Survivor records received.", "#00CCAA")   -- SCIDB announces the entry
        _addSurvivorRecords()
    end, "boneyard_survivor_records")
end

-- The report: back where the survivors were dropped off (the rescue job's station), docked, the
-- crew can talk with them. That ends the arc.
local _SURVIVOR_STATIONS = {"Port Vesper", "Halcyon Rest", "Saint Brennan's Mission"}
local function _survivorsAt()
    local at = RT.flag("boneyard_survivors_at")
    return type(at) == "string" and at or "Port Vesper"
end

local function _survivorsThanks(ship)
    local st = MISSIONS._state["boneyard"] or {}
    local opener = st.concord_beaten
        and '"You got the archive out, and a whole Concord battle group destroyed? That\'ll set them back. '
            .. 'Thank you. All of us, thank you."\n\n'
        or '"You got the archive out, right under the Concord fleet? Thank you. All of us, thank you."\n\n'
    -- Quill, with the archive the crew brought back: the cure existed, and where the work goes next
    -- (the hook for the Hob Works mission; plan.md).
    return opener
        .. '"I\'ve been through the reversal folder. The Concord was very close to a cure, but the political fallout from '
        .. 'building and deploying it would have been too great. So they buried it, and the Pale Sun with it."\n\n'
        .. '"We\'re headed to Hob\'s Landing to keep our work moving forward. We heard they have some exceptional engineers there. '
        .. 'If the ' .. ship .. ' is ever out that way, come and find us."'
end

local function _survivorsHook(src, tgt)
    if MISSIONS._status["boneyard"] ~= "active" or MISSIONS._cur_phase["boneyard"] ~= "report" then return end
    if tgt:getCallSign() ~= _survivorsAt() or not ARC.docked(src, tgt) then return end
    addCommsReply("Talk with the lifeboat survivors", function(s2)
        setCommsMessage(_survivorsThanks(s2:getCallSign()))
        MISSIONS.phase("boneyard", "done")
    end)
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
                -- Picked up: they ask for the Annex to be hacked (the only prompt the crew gets).
                -- Aboard and breathing, so the air clock stops: the job cannot fail on the way home.
                on_found = function(m)
                    m._expires_at = nil
                    RT.flag("boneyard_buoy_found", true)
                    RT.flag("boneyard_survivors_at", m.origin)   -- where the crew reports back
                    ARC.log("[Medical] Four survivors, dehydrated, stable.", "#FFAA44")
                    ARC.log(string.format("[Science] Survivor lifeboat telemetry: launched from the Annex, grid %s. Concord Level-5 archive hold.", JOBS.gridRef(_ANNEX_X, _ANNEX_Y)), "#00CCAA")
                    _survivorHail()
                end,
                -- Home at the rescue job's station: now the Annex can be found and hacked.
                on_complete = function(m)
                    RT.flag("boneyard_survivors_home", true)
                    local bst = MISSIONS._state["boneyard"]
                    if bst and MISSIONS._status["boneyard"] == "active"
                       and MISSIONS._cur_phase["boneyard"] == "hook" then
                        RT.setObjective("Hack the Annex", true, "boneyard")
                        _annexSignal(bst, true)   -- the telemetry already named its grid
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
            -- Survivors recovered in an earlier session: they were taken home between sessions
            -- (the job does not outlive the session), and the objective line and the Annex come
            -- back (the objective display is rebuilt each run; their telemetry named its grid).
            if RT.flag("boneyard_buoy_found") then
                if not RT.flag("boneyard_survivors_home") then RT.flag("boneyard_survivors_home", true) end
                RT.setObjective("Hack the Annex", true, "boneyard")
                _annexSignal(st, true)
            end
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
            -- Survivors aboard but not home yet: nothing starts until they are back at the
            -- rescue job's station (not even by flying past Ashgrave).
            if RT.flag("boneyard_buoy_found") and not RT.flag("boneyard_survivors_home") then return end
            -- The Annex is out (the survivors are home, or the crew came by Ashgrave): the hack
            -- phase starts. How to hack it is for the crew to work out.
            if RT.valid(st.annex) then
                MISSIONS.phase("boneyard", "annex_hack")
            elseif ARC.playerNear(_ASHGRAVE_X, _ASHGRAVE_Y, 8 * U) then
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
                        "Encrypted — military-grade lockdown on all channels."
                    )
                end)
            end
            -- Just the objective line: the survivors asked for the hack, and how to do it is for
            -- the crew to work out. No pop-up, no instructions.
            RT.setObjective("Hack the Annex", true, "boneyard")
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
                ARC.log(
                    "[Science] Partial decryption. These files are marked Concord Level 5. " ..
                    "This is not a standard military installation.", "#FFCC00")
            end

            -- EE decays hacked_level by 1/180 per second before scripts run, so a hack that lands
            -- at 100% already reads just under 1.0 here; 0.99 leaves a ~2 s window.
            if hack_lvl >= 0.99 then
                -- Silence the drones, lock the zone, open the Annex to docking
                _idleDrones(st)
                PROX.suspendZone("the Boneyard")
                _secureAnnex(st)
                MISSIONS.phase("boneyard", "annex_control")
            end
        end,
    },

    annex_control = {
        enter = function(st)
            RT.setObjective("Download Annex data", true, "boneyard")   -- replaces "Hack the Annex"
            ARC.log("[Relay] Ashgrave Annex: station security has been reset. Dock for more options.", "#00FF88")
            ARC.log("[Science] All Relic drones idle.", "#FFCC00")
            _secureAnnex(st)
        end,
        update = function(st, delta, now)
            _keepDronesIdle(st, now)
            local p = ARC.player()
            local docked = p ~= nil and RT.valid(st.annex) and p:isDocked(st.annex)
            if docked and not st.fleet_arrived then _fleetArrives(st) end

            -- Operation timers (one runs at a time; see _OPS). The download needs the clamp.
            local op = _runningOp(st)
            if op and op.needs_dock and not docked then
                st[op.key .. "_start"] = nil
                if op.key == "download" then st.download_time = nil end   -- a restart takes the full time
                ARC.log("[Relay] Archive download interrupted: the link dropped when we undocked. Dock again to restart it.", "#FFAA44")
            elseif op and now - st[op.key .. "_start"] >= _opTime(st, op) then
                st[op.key .. "_done"] = true
                if op.key == "download" then
                    RT.flag("boneyard_hack_done", true)
                    ARC.log("[Relay] Research archive download complete. Data secured.", "#00AAFF")
                    _indexAshgraveResearch()
                    -- A crew that never met the survivors still learns where the work goes next
                    -- (with them, Quill says it at the report).
                    if not RT.flag("boneyard_buoy_found") then
                        ARC.log("[Science] The reversal folder: the Concord was very close to a cure, but shelved it for the "
                            .. "political fallout of building and deploying it. Lead researcher: Dr. Mara Quill. The last note in "
                            .. "her file is a forwarding address: Hob's Landing.", "#00CCAA")
                    end
                    if not st.concord_beaten then RT.setObjective("Defeat Concord fleet", true, "boneyard") end
                elseif op.key == "reprogram" then
                    RT.flag("boneyard_drone_flip", true)
                    _reprogramDrones(st)
                else
                    if st.annex_battle then st.annex_battle:armAnnex() end
                    ARC.log("[Relay] Annex defense lasers online. They are firing on the Concord.", "#FF4444")
                end
            end

            _trackCmdShip(st)
            _tickBattle(st, now)
            if st.concord_beaten then _compressArchive(st) end

            -- Both done (the archive and the fleet), or the crew has left (_LEAVE_R from the
            -- Boneyard's centre: 20U outside it) with whatever it has. With the archive and the
            -- survivors aboard earlier, it reports to them; otherwise that is the end.
            local left = false
            if p then
                local px, py = p:getPosition()
                left = ARC.dist(px, py, _BONEYARD_CX, _BONEYARD_CY) > _LEAVE_R
            end
            if (st.download_done and st.concord_beaten) or left then
                if left then
                    ARC.log("[Mission] We've left the Boneyard. " .. (st.download_done
                        and "The archive is aboard." or "The Annex archive stays behind."), "#80FF80")
                end
                local report = st.download_done and RT.flag("boneyard_buoy_found")
                MISSIONS.phase("boneyard", report and "report" or "done")
            end
        end,
    },

    report = {
        enter = function(st)
            RT.setObjective("Report the success", true, "boneyard")
            ARC.log("[Mission] Report the mission's success to the lifeboat survivors at " .. _survivorsAt() .. ".", "#80FF80")
            for _, cs in ipairs(_SURVIVOR_STATIONS) do ARC.stationHook(cs, _survivorsHook) end
        end,
        update = function(st, delta, now)
            _keepDronesIdle(st, now)
            _tickBattle(st, now)   -- the drones keep guarding the Annex
        end,
    },

}

-- ── Resolve ───────────────────────────────────────────────────────────────────

function M.resolve(st)
    RT.flag("boneyard_arc_done", true)
    RT.clearObjective("boneyard")   -- the Annex fight is over

    -- Reputation and credits are paid once. A GM jump to another end state (or back to done)
    -- does not pay again: "boneyard_rewarded" survives a jump to "done" and is cleared by any
    -- jump to an earlier state, so a replay pays once more.
    ARC.once("boneyard_rewarded", function()
        local concord_delta = -300
        if RT.flag("boneyard_drone_flip") then
            concord_delta = concord_delta - 200
            RT.addReputation("Corsairs", 150, "Enemy of Concord battle group")
        end
        RT.addReputation("Concord", concord_delta, "Ashgrave Annex breach")

        if RT.flag("boneyard_hack_done")  then RT.addCredits(600, "Ashgrave research data") end
        if RT.flag("boneyard_drone_flip") then RT.addCredits(200, "Drone tactical bonus")   end
    end)

    if RT.flag("boneyard_hack_done") then
        _indexAshgraveResearch()   -- normally already done when the download finished
    end

    -- (The crew can leave with the fleet still there: then the Concord "swept" the Boneyard.)
    if st.concord_beaten and RT.flag("boneyard_drone_flip") then
        RUMORS.add({
            text     = "Word's out — a Concord battle group got torn apart in the Boneyard. Something woke those drones up. Official Concord statement: none.",
            priority = 4, category = "BONEYARD_DONE",
        })
    elseif st.concord_beaten then
        RUMORS.add({
            text     = "A Concord battle group went into the Boneyard and didn't come out. Official Concord statement: none.",
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
    ARC.log("[Mission] Boneyard arc resolved. Outcome: " .. outcome .. ".", "#80FF80")
end

-- ── Cancel ────────────────────────────────────────────────────────────────────

function M.on_cancel(st)
    _clearState(st)
end

-- ── GM actions ────────────────────────────────────────────────────────────────

M.gm_flag_prefixes = {"boneyard_"}

-- Saved flags this arc owns: every RT.flag name it sets, with what it means (a "*" suffix covers
-- a family of names). M.reads lists other arcs' flags it looks at. check.py and the arc tests
-- reject any flag that is not declared here. See missions_api.md, "Flags".
M.flags = {
    boneyard_buoy_found            = "the lifeboat survivors were recovered (their records are in the Science DB)",
    boneyard_survivors_at          = "the station the survivors were taken to (a callsign): the crew reports there",
    boneyard_survivors_home        = "the survivors were brought back to the rescue job's station (the Annex and its hack wait for this)",
    boneyard_hack_done             = "the Ashgrave research archive was downloaded",
    boneyard_drone_flip            = "the Relic drones were reprogrammed against the Concord",
    boneyard_battlegroup_destroyed = "the battle group's command ship (CNS Vanguard) was destroyed",
    boneyard_arc_done              = "true once the crew has reported to the survivors (or, without them, won the Annex fight)",
    boneyard_rewarded              = "reputation and credits were paid (an end state pays once)",
}
M.reads = {"rezkov_arc_done", "rezkov_declined"}

-- Science DB follows the flags (SCIDB.sync at session start and after every GM jump): the
-- survivor records exist while the lifeboat has been recovered; the Ashgrave research entries
-- are readable while the archive has been downloaded.
if SCIDB and SCIDB.rule then
    SCIDB.rule("boneyard_survivors", {want = function() return RT.flag("boneyard_buoy_found") end,
                                      add  = function() _addSurvivorRecords() end})
    for _, k in ipairs({"hollow_true_nature", "ashgrave_research", "synthesis_details"}) do
        SCIDB.rule(k, {lock = true, want = function() return RT.flag("boneyard_hack_done") end})
    end
end

-- Short state label for the "Mission state" popup.
-- The GM criteria page's "Mission outcome" (boneyard_arc_done is only true/false).
M.outcome_fn = function()
    if not RT.flag("boneyard_arc_done") then return nil end
    local data, drones = RT.flag("boneyard_hack_done"), RT.flag("boneyard_drone_flip")
    if data and drones then return "full (archive downloaded, drones reprogrammed)" end
    if data then return "data (archive downloaded)" end
    if drones then return "left without the archive (drones reprogrammed)" end
    return "left without the archive"
end

M.gm_state_fn = function()
    local st = MISSIONS._status["boneyard"]
    local ph = MISSIONS._cur_phase["boneyard"]
    if st == "done" then
        return "Complete (hack=" .. tostring(RT.flag("boneyard_hack_done") and true or false)
            .. ", flip=" .. tostring(RT.flag("boneyard_drone_flip") and true or false) .. ")"
    end
    return ph or st
end

-- GM jumps (see MISSIONS.gmJump): reset to a blank slate, replay the lasting effects of every
-- earlier phase, then enter the target. Reset removes the Annex, the Concord group, every drone
-- spawned or re-flagged, pending timers, rumors/jobs, the zone suspension, and restores the
-- state table. It clears boneyard_* flags (the lifeboat's "buoy_found" only when jumping to the
-- start, so its job is offered again; the same for where they were taken) and cannot undo reputation, credits or Science DB unlocks.
M.gm_reset = function(st, target)
    _clearState(st)
    ARC.resetState(M, st)
    MISSIONS.gmClearFlags("boneyard", function(name)
        if name == "boneyard_buoy_found" or name == "boneyard_survivors_at" or name == "boneyard_survivors_home" then
            return target ~= nil and target ~= "hook"
        end
        if name == "boneyard_rewarded"   then return target == "done" end
        return false
    end)
end

-- Lasting effects of having FINISHED each phase.
M.completed = {
    hook       = function(st) _spawnAnnex(st) end,
    annex_hack = function(st)
        st.hack_mid_logged = true
        _idleDrones(st)
        PROX.suspendZone("the Boneyard")
        _secureAnnex(st)
    end,
    -- The archive is downloaded and the fleet is gone (it never jumps in on a GM jump past it).
    annex_control = function(st)
        st.download_done, st.fleet_arrived, st.concord_beaten = true, true, true
        RT.flag("boneyard_hack_done", true)
    end,
}

local _jump = ARC.jumper("boneyard")

-- An end state: which objectives were achieved. The world is left clean (no Annex, no fleet).
local function _done(hack, flip)
    return _jump("done", function()
        if hack then RT.flag("boneyard_hack_done", true) end
        if flip then RT.flag("boneyard_drone_flip", true) end
    end, {skip_completed = true})
end

-- GM "→" buttons (labels max 18 chars). "→ Inactive" is the engine default (stop and disable).
M.gm_states = {
    {key = "hook",     label = "→ Hook",          fn = _jump("hook")},
    {key = "hack",     label = "→ Annex hack",    fn = _jump("annex_hack")},
    {key = "control",  label = "→ Annex control", fn = _jump("annex_control")},
    {key = "report",   label = "→ Report",        fn = _jump("report", function()
        if not RT.flag("boneyard_buoy_found") then RT.flag("boneyard_buoy_found", true) end
    end)},
    -- End states: the archive is always downloaded; were the drones reprogrammed too?
    {key = "done_full",    label = "→ Done: Full",    fn = _done(true,  true)},
    {key = "done_data",    label = "→ Done: Data",    fn = _done(true,  false)},
}

-- State-specific helpers: only shown in the phase they apply to.
M.gm_actions = {
    -- Finish the Relay hack: sets the Annex frontshield to fully hacked, so the annex_hack
    -- update runs its normal completion next frame (idle drones, suspend the zone, the Annex opens
    -- to docking) and moves to annex_control.
    {label = "Complete hack", phases = {"annex_hack"}, fn = function(st)
        if not RT.valid(st.annex) then return end
        pcall(function() st.annex:setSystemHackedLevel("frontshield", 1.0) end)
    end},
    -- Destroy every Concord ship left (a crew that cannot win the fight; a playtest shortcut).
    -- The Annex's "eliminated" hail and the rest follow as in a won fight.
    {label = "Destroy Concord", phases = {"annex_control"}, fn = function(st)
        if not st.fleet_arrived then
            globalMessage("The Concord fleet has not jumped in yet: it arrives when the crew docks at the Annex.")
            return
        end
        for _, s in ipairs(st.concord_group or {}) do
            if RT.valid(s) then s:destroy() end
        end
    end},
}

-- ── Achievements (the arc defines its own; stats.lua knows nothing about arcs) ─
if ACH and ACH.define then
    ACH.define{id = "first_on_the_scene", name = "First on the Scene", category = "story", hidden = true,
        desc = "Rescue the lifeboat survivors in the Boneyard.",
        check = function(s) return RT.flag and RT.flag("boneyard_buoy_found") and true or false end}
    ACH.define{id = "boneyard_breach", name = "Breaching the Annex", category = "story", hidden = true,
        desc = "Finish the Boneyard arc.",
        check = function(s) return s.arcs.boneyard ~= nil and (s.arcs.boneyard.completed or 0) > 0 end}
end

-- ── Register ──────────────────────────────────────────────────────────────────

MISSIONS.register(M)
