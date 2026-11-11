-- ee/ragtag/missions/boneyard.lua
-- Boneyard Arc: breach the Ashgrave Annex before a Concord battle group arrives.
--
-- Trigger: upgrade investment >= 800cr AND not yet completed
-- Structure: hook → approach → annex_hack → annex_control → extract → done
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
}

M.phase_order = {
    "hook", "approach", "annex_hack", "annex_control", "extract",
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

-- ── Phases ────────────────────────────────────────────────────────────────────

M.phases = {

    hook = {
        enter = function(st)
            -- Re-inject each session (RUMORS resets per run); clear first so a
            -- GM re-entry of this phase doesn't duplicate them.
            RUMORS.removeCategory("BONEYARD_HOOK")
            RUMORS.add({
                text     = "Concord assembled a heavy response group at Sentinel Fleet Yard. Destination undisclosed.",
                priority = 3, category = "BONEYARD_HOOK",
            })
            RUMORS.add({
                text     = "Two Concord battle groups left Lumen system inside a week. That doesn't happen unless something serious is planned.",
                priority = 3, category = "BONEYARD_HOOK",
            })
        end,
        update = function(st, delta, now)
            local players = RT.players
            if not players or not players[1] then return end
            local player = players[1]
            if not RT.valid(player) then return end
            local px, py = player:getPosition()
            -- 8U: Ashgrave's planet radius is 3.4U, so the trigger band clears
            -- the surface comfortably.
            if _dist(px, py, _ASHGRAVE_X, _ASHGRAVE_Y) < 8 * U then
                MISSIONS.phase("boneyard", "approach")
            end
        end,
        exit = function(st)
            RUMORS.removeCategory("BONEYARD_HOOK")
        end,
    },

    approach = {
        enter = function(st)
            _spawnAnnex(st)
            RT.shipLog(
                "[Science] Anomalous signal from deep in the Boneyard. " ..
                "Source: Ashgrave Annex. Bearing inside the debris field.", "#FFCC00")
            RT.shipLog("[Nav] Waypoint set: Ashgrave Annex.", "#AAAAFF")
        end,
        update = function(st, delta, now)
            if not RT.valid(st.annex) then return end
            local players = RT.players
            if not players or not players[1] then return end
            local player = players[1]
            if not RT.valid(player) then return end
            local px, py = player:getPosition()
            local ax, ay = st.annex:getPosition()
            if _dist(px, py, ax, ay) < 2.5 * U then
                MISSIONS.phase("boneyard", "annex_hack")
            end
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

M.gm_actions = {
    {label = function(st)
        return "Ph: " .. (MISSIONS._cur_phase["boneyard"] or "inactive")
    end, done_ok = true, fn = function(st) end},

    {label = "→ Hook", fn = function(st)
        _clearState(st)
        MISSIONS.phase("boneyard", "hook")
        globalMessage("[GM] Boneyard: → Hook.", 4)
    end},

    {label = "→ Approach", fn = function(st)
        _clearState(st)
        MISSIONS.phase("boneyard", "approach")
        globalMessage("[GM] Boneyard: → Approach.", 4)
    end},

    {label = "→ Annex hack", fn = function(st)
        _clearState(st)
        MISSIONS.phase("boneyard", "annex_hack")
        globalMessage("[GM] Boneyard: → Annex hack.", 4)
    end},

    {label = "→ Annex control", fn = function(st)
        _clearState(st)
        _spawnAnnex(st)
        _idleDrones(st)
        PROX.suspendZone("the Boneyard")
        _spawnConcordGroup(st)
        RT.after(90, function()
            if MISSIONS._status["boneyard"] ~= "active" then return end
            local cst = MISSIONS._state["boneyard"]
            if cst then _spawnJammer(cst) end
        end, "boneyard_jammer")
        MISSIONS.phase("boneyard", "annex_control")
        globalMessage("[GM] Boneyard: → Annex control.", 4)
    end},

    {label = "→ Extract", fn = function(st)
        _clearState(st)
        PROX.suspendZone("the Boneyard")
        MISSIONS.phase("boneyard", "extract")
        globalMessage("[GM] Boneyard: → Extract.", 4)
    end},

    {label = "→ Complete arc", fn = function(st)
        _clearState(st)
        RT.flag("boneyard_hack_done",  true)
        RT.flag("boneyard_drone_flip", true)
        MISSIONS.phase("boneyard", "done")
        globalMessage("[GM] Boneyard: → Complete.", 4)
    end},
}

-- ── Register ──────────────────────────────────────────────────────────────────

MISSIONS.register(M)
