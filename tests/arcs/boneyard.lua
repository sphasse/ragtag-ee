-- Boneyard arc: hook (survivors home) -> annex_hack (no hints) -> annex_control (dock: the fleet jumps in; download,
-- drone reprogram, Annex lasers; the download stops on undocking) -> report (the survivors, docked at
-- their station) -> done (full); then the other ending (no survivors: Ashgrave reveals the Annex, the fight ends it,
-- and the fleet's end compresses a running download to a minute), leaving the Boneyard (20U outside it) ends the
-- arc, the GM states and "-> Inactive". Not covered: the lifeboat rescue flight (the test calls the pickup's on_found),
-- a real Relay hack (the GM helper sets the level), how the fight plays out (the Battle Lab's
-- Annex mode is for that), the pop-ups on the consoles as the crew sees them; covered: who spawns
-- where, how fast, with what lasers, drone replacement from the same nebula, and the Annex's lasers
-- picking a Concord ship. The 5 min download (1 min once compressed) and the 60 s reprogram and laser timers are shortened
-- by moving their start times back.

T.arc("boneyard")

local ANNEX_X, ANNEX_Y = 43000, -104000
local function annex() return T.st().annex end
local function dist(s, x, y) local sx, sy = s:getPosition(); return math.sqrt((sx - x) ^ 2 + (sy - y) ^ 2) end
local c0, concord0, corsairs0

-- Ships in and around the Boneyard by faction, e.g. "Derelict=3 Relic=14".
local function census()
    local n = {}
    for _, o in ipairs(getObjectsInRadius(36000, -96000, 60000)) do
        if isObjectType(o, "CpuShip") then
            local f = o:getFaction()
            if f == "Concord Hostile" or f == "Relic Active" or f == "Derelict" or f == "Relic" then n[f] = (n[f] or 0) + 1 end
        end
    end
    local keys = {}
    for k in pairs(n) do keys[#keys + 1] = k end
    table.sort(keys)
    for i, k in ipairs(keys) do keys[i] = k .. "=" .. n[k] end
    return table.concat(keys, " ")
end
local census0

-- Pop-ups on the arc ship's consoles whose text has `text`.
local function popups(text)
    local n = 0
    pcall(function()
        local f = T.P().components.custom_ship_functions   -- the component is the array
        for i = 1, #f do
            if tostring(f[i].caption):find(text, 1, true) then n = n + 1 end
        end
    end)
    return n
end

-- ── Hook: rumors and the rescue job; bringing the survivors home reveals the Annex ──
local m
T.step("hook", function()
    census0 = census()
    T.jump("hook")
    T.eq("hook: phase", T.phase(), "hook")
    T.eq("hook: three hook rumors", T.rumors("BONEYARD_HOOK"), 3)
    T.eq("hook: the rescue job is on offer", T.jobs("BONEYARD_SPECIAL"), 1)
    T.check("hook: no Annex yet", not RT.valid(annex()))
    -- The rescue job taken at Halcyon Rest; the flight out is not played: the pod is picked up
    -- through the job's own on_found, the return through its on_complete.
    for _, e in ipairs(JOBS._injected) do
        if e.category == "BONEYARD_SPECIAL" then m = e.record("Halcyon Rest") end
    end
    m._expires_at = T.now() + 1200   -- as if taken: the 20 minute air clock
    m.on_found(m)
end)
T.talk(nil, {}, {answer = true, name = "the lifeboat survivors"})
T.step("the survivors ask for the Annex", function()
    T.check("survivors: get us out", T.msg():find("Please get us out of here", 1, true) ~= nil, T.msg())
    T.check("survivors: Mara Quill introduces herself", T.msg():find("This is Mara Quill, senior researcher", 1, true) ~= nil, T.msg())
    T.check("survivors: hack the Annex and extract the research", T.msg():find("Those drones are whacko, but if the Annex could be hacked and all the research extracted", 1, true) ~= nil, T.msg())
    T.eq("survivors: nothing to answer", #T.replies(), 0)
    T.eq("survivors: where they are taken", T.flag("boneyard_survivors_at"), "Halcyon Rest")
    T.check("survivors: no Annex while they are aboard", not RT.valid(annex()))
    T.check("survivors: the air clock stops once they are aboard", m._expires_at == nil)
    -- The voice that hailed is nowhere: no position, no radar blip (it once sat over Port Vesper).
    local v = RT.voice.get("boneyard_survivors")
    T.check("survivors: the voice has no position", RT.valid(v) and v.components.transform == nil)
    T.check("survivors: and no radar blip", RT.valid(v) and v.components.radar_trace == nil)
    local near = 0
    for _, o in ipairs(getObjectsInRadius(0, 0, 3000)) do
        if o == v then near = near + 1 end
    end
    T.eq("survivors: nothing of theirs at Port Vesper", near, 0)
end)
T.closeComms()
T.waitFor("survivors: their records are announced with where they are", function()
    local l = SCIDB.announced[#SCIDB.announced]
    return l == "[Science] Database entry added: Records > Boneyard Survivor Records."
end, 7)
T.step("their records fit the Science screen", function()
    local n = 0
    for _, e in ipairs(SCIDB.kv_set) do
        if e.path:find("Boneyard Survivor Records", 1, true) then
            n = n + 1
            T.check("records: " .. e.key .. " = " .. e.value .. " fits", #e.value <= SCIDB.KV_VALUE_MAX and #e.key <= SCIDB.KV_KEY_MAX)
        end
    end
    T.eq("records: three key/values", n, 3)
    local d = SCIDB._entries["boneyard_survivors"] and SCIDB._entries["boneyard_survivors"]:getLongDescription() or ""
    T.check("records: from Dr. Mara Quill, senior researcher", d:find("Dr. Mara Quill, a senior researcher", 1, true) ~= nil, d:sub(1, 200))
    T.check("records: she worked on the reversal program", d:find("she worked on the reversal program", 1, true) ~= nil)
end)
T.step("survivors aboard: fly past Ashgrave", function()
    T.moveTo(39000, -102500)   -- 6.5U from Ashgrave: would reveal the Annex without survivors aboard
end)
T.wait(2)
T.step("nothing starts until they are home", function()
    T.eq("survivors: still the hook", T.phase(), "hook")
    T.check("survivors: still no Annex", not RT.valid(annex()))
    T.check("survivors: no hack objective yet", RT.objectives.boneyard ~= "Hack the Annex")
    m.on_complete(m)   -- docked back at Halcyon Rest, job handed in
end)
T.waitFor("annex_hack: the hack starts once the survivors are home", function() return T.phase() == "annex_hack" end, 3)
T.step("lead paid off", function()
    T.eq("survivors: home", T.flag("boneyard_survivors_home"), true)
    T.eq("hook: rumors removed once found", T.rumors("BONEYARD_HOOK"), 0)
    T.eq("hook: rescue job withdrawn", T.jobs("BONEYARD_SPECIAL"), 0)
    T.check("annex_hack: the Annex is an enemy (no docking)", T.P():isEnemy(annex()))
    T.eq("annex_hack: no pop-up telling the crew how", popups("Hack the Ashgrave Annex"), 0)
    T.eq("annex_hack: just the objective", RT.objectives.boneyard, "Hack the Annex")
end)

-- ── Hailing a drone: base64, a threat while hostile, a welcome once idled ───
local drone
local function decodedIn(list)
    for _, line in ipairs(list) do if T.msg() == VERSE.base64(line) then return true end end
    return false
end
T.step("base64 and a hostile drone", function()
    T.eq("base64: 'Man'", VERSE.base64("Man"), "TWFu")
    T.eq("base64: 'Ma' (padding)", VERSE.base64("Ma"), "TWE=")
    T.eq("base64: 'M' (padding)", VERSE.base64("M"), "TQ==")
    local best
    for _, o in ipairs(getObjectsInRadius(ANNEX_X, ANNEX_Y, 15000)) do
        if isObjectType(o, "CpuShip") and o:getFaction() == "Relic" then
            if not best or dist(o, ANNEX_X, ANNEX_Y) < dist(best, ANNEX_X, ANNEX_Y) then best = o end
        end
    end
    drone = best
    T.check("drone: a Relic drone near the Annex", RT.valid(drone))
end)
T.talk(function() return drone end, {}, {name = "a Relic drone"})
T.step("it threatens, in base64", function()
    T.check("drone: a hostile line, base64", decodedIn(VERSE.DRONE_HOSTILE), T.msg())
end)
T.closeComms()

-- ── Hack ─────────────────────────────────────────────────────────────────────
T.talk(annex, {})
T.step("locked down", function()
    T.check("annex_hack: comms say it is locked down", T.msg():find("lockdown", 1, true) ~= nil, T.msg())
    T.check("annex_hack: and do not say how to get in", T.msg():find("hack", 1, true) == nil, T.msg())
    T.eq("annex_hack: objective", RT.objectives.boneyard, "Hack the Annex")
    T.action("Complete hack")
end)
T.waitFor("annex_control: a finished hack opens the Annex", function() return T.phase() == "annex_control" end, 3)
T.closeComms()
T.talk(function() return drone end, {}, {name = "the idled drone"})
T.step("idled, it welcomes the crew, in base64", function()
    T.eq("drone: idled by the hack", drone:getFaction(), "Derelict")
    T.check("drone: a welcome line, base64", decodedIn(VERSE.DRONE_NEUTRAL), T.msg())
end)
T.closeComms()
local function relicDrones()
    local relic = 0
    for _, o in ipairs(getObjectsInRadius(36000, -96000, 32000)) do
        if isObjectType(o, "CpuShip") and o:getFaction() == "Relic" then relic = relic + 1 end
    end
    return relic
end
local late
-- The Boneyard's gun platforms (PLATFORMS), by faction.
local function platformFactions()
    local n = {}
    for _, t in ipairs(PLATFORMS.list) do
        if RT.valid(t.obj) then
            if dist(t.obj, 36000, -96000) < 32000 then n[t.obj:getFaction()] = (n[t.obj:getFaction()] or 0) + 1 end
        end
    end
    return n
end
T.step("security reset", function()
    local pf = platformFactions()
    T.eq("annex_control: the Boneyard's gun platforms go quiet too (Derelict)", pf.Derelict, 3)
    T.check("annex_control: no Relic platform left", pf.Relic == nil)
    for _, t in ipairs(PLATFORMS.list) do
        if RT.valid(t.obj) and t.obj:getFaction() == "Derelict" then
            T.check("annex_control: a quiet platform is no enemy of the crew", not t.obj:isEnemy(T.P()))
        end
    end
    T.eq("annex_control: objective", RT.objectives.boneyard, "Download Annex data")
    T.eq("annex_control: the Annex is Relic Active", annex():getFaction(), "Relic Active")
    T.check("annex_control: no longer an enemy (the crew can dock)", not T.P():isEnemy(annex()))
    T.check("annex_control: the Annex has a docking bay", annex().components.docking_bay ~= nil)
    T.eq("annex_control: no Concord until the crew docks", T.alive(T.st().concord_group), 0)
    T.check("annex_control: Boneyard patrols suspended", PROX._suspended_zones["the Boneyard"])
    T.eq("annex_control: no active Relic drones left in the Boneyard", relicDrones(), 0)
    -- A drone that turns up after the hack goes docile too.
    late = CpuShip():setTemplate("MT52 Hornet"):setFaction("Relic"):setPosition(30000, -90000)
end)
T.waitFor("annex_control: a drone arriving later goes idle too", function()
    return RT.valid(late) and late:getFaction() == "Derelict"
end, 4)
T.talk(annex, {})
T.step("not docked: dock for more options", function()
    late:destroy()
    T.check("annex_control: dock first", T.msg():find("Station security has been reset. Dock for more options.", 1, true) ~= nil, T.msg())
    T.check("annex_control: no operations at a distance", not T.hasReply("Download"), table.concat(T.replies(), " | "))
    T.eq("annex_control: still no fleet", T.alive(T.st().concord_group), 0)
end)

-- ── Docking: the fleet jumps in ──────────────────────────────────────────────
T.dock(annex)
T.waitFor("annex_control: docking brings the Concord fleet", function() return T.st().fleet_arrived end, 3)
T.step("battle group arrives", function()
    T.eq("fleet: every console is told", popups("Incoming jump detected. A Concord battle fleet has arrived."), 10)
    local g = T.st().concord_group
    T.eq("fleet: seven Concord ships", T.alive(g), 7)
    T.eq("fleet: battle group is hostile", g[1]:getFaction(), "Concord Hostile")
    T.eq("fleet: the middle ship is the command ship", g[4], T.st().concord_cmd)
    T.eq("fleet: CNS Vanguard", g[4]:getCallSign(), "CNS Vanguard")
    -- A line 15U north-west of the Annex, running north-east / south-west (ends 12U apart).
    local mx, my = g[4]:getPosition()
    T.check("fleet: line centre 15U north-west", math.abs(dist(g[4], ANNEX_X, ANNEX_Y) - 15000) < 300
        and mx < ANNEX_X and my < ANNEX_Y, string.format("%.0f, %.0f", mx, my))
    local x1, y1 = g[1]:getPosition()
    local x7, y7 = g[7]:getPosition()
    T.check("fleet: the line runs at 45 degrees", math.abs(math.abs(x7 - x1) - math.abs(y7 - y1)) < 300
        and math.abs(dist(g[1], x7, y7) - 12000) < 300, string.format("(%.0f,%.0f) (%.0f,%.0f)", x1, y1, x7, y7))
    T.check("fleet: no warp", not g[1]:hasWarpDrive() and not g[4]:hasWarpDrive())
    T.eq("fleet: Phobos T3 at the lab's 104 impulse", math.floor(g[4]:getImpulseMaxSpeed() + 0.5), 104)
    T.eq("fleet: Atlantis X23 at the lab's 80 impulse", math.floor(g[1]:getImpulseMaxSpeed() + 0.5), 80)
    local p = T.st().annex_battle.b.points
    T.check("fleet: combat points 3U north-west of the Annex",
        math.abs(math.sqrt((p[3][1] - ANNEX_X) ^ 2 + (p[3][2] - ANNEX_Y) ^ 2) - 3000) < 50 and p[3][1] < ANNEX_X and p[3][2] < ANNEX_Y)
    T.check("fleet: the Annex is not armed yet", annex():getBeamWeaponRange(0) == 0)
end)

-- ── Control: one operation at a time, docked ─────────────────────────────────
T.talk(annex, {})
T.step("three operations on offer", function()
    T.check("control: download, 5 min while the fleet is out", T.hasReply("1) Download research archive (5 min)"), table.concat(T.replies(), " | "))
    T.check("control: reprogram, 60 s", T.hasReply("2) Reprogram the drones to be hostile to the Concord (60s)"), table.concat(T.replies(), " | "))
    T.check("control: lasers, 60 s", T.hasReply("3) Enable station defense lasers (60s)"), table.concat(T.replies(), " | "))
end)
T.talk(annex, {"1) Download research archive"})
T.step("download running", function() T.check("control: downloading", T.st().download_start ~= nil) end)
T.talk(annex, {})
T.step("the others are locked meanwhile", function()
    T.check("control: download shown in progress", T.hasReply("[IN PROGRESS] Downloading archive"), table.concat(T.replies(), " | "))
    T.check("control: reprogram locked during download", T.hasReply("[LOCKED] Reprogram the drones"), table.concat(T.replies(), " | "))
    T.check("control: lasers locked during download", T.hasReply("[LOCKED] Enable station defense lasers"), table.concat(T.replies(), " | "))
    T.check("control: not done early", not T.flag("boneyard_hack_done"))
    T.check("control: a Refresh option", T.hasReply("Refresh"), table.concat(T.replies(), " | "))
end)
-- Refresh redraws the menu with the countdown as it is now, without disconnecting (playtest).
local before_s
local function inProgressSecs()
    for _, r in ipairs(T.replies()) do
        local n = r:match("^%[IN PROGRESS%] Downloading archive: (%d+)s")
        if n then return tonumber(n) end
    end
end
T.step("note the countdown", function() before_s = inProgressSecs() end)
T.wait(3)
T.reply({"Refresh"})
T.step("refreshed", function()
    local now_s = inProgressSecs()
    T.check("refresh: the operations menu again", T.msg():find("Select operation:", 1, true) ~= nil, T.msg())
    T.check("refresh: the countdown has moved on", before_s and now_s and now_s <= before_s - 2,
        tostring(before_s) .. " -> " .. tostring(now_s))
    T.check("refresh: and can refresh again", T.hasReply("Refresh"))
end)
T.closeComms()
T.undock()
T.waitFor("control: undocking stops the download", function() return T.st().download_start == nil end, 3)
T.step("interrupted", function()
    T.check("control: no archive", not T.flag("boneyard_hack_done") and not T.st().download_done)
end)
T.dock(annex)
T.talk(annex, {"1) Download research archive"})
T.step("download restarted", function()
    T.check("control: downloading again", T.st().download_start ~= nil)
    T.st().download_start = T.st().download_start - 298
end)
T.waitFor("control: download completes", function() return T.flag("boneyard_hack_done") end, 5)
T.step("research indexed", function()
    T.check("control: Ashgrave research readable", SCIDB._locked.ashgrave_research and SCIDB._locked.ashgrave_research.unlocked)
    local n, upd = #SCIDB.announced, 0
    for i = math.max(1, n - 2), n do
        if SCIDB.announced[i]:find("Database entry updated: ", 1, true) then upd = upd + 1 end
    end
    T.eq("control: each of the three research entries is announced", upd, 3)
    T.eq("control: the fleet is the objective now", RT.objectives.boneyard, "Defeat Concord fleet")
    T.eq("control: still at the Annex (the fleet is not beaten)", T.phase(), "annex_control")
end)
T.talk(annex, {"2) Reprogram the drones"})
T.step("reprogram running", function()
    T.check("control: reprogramming", T.st().reprogram_start ~= nil)
    T.check("control: no drones before the reprogram finishes", #T.st().rein_drones == 0)
end)
T.closeComms()
T.undock()
T.step("the reprogram does not need the clamp", function()
    T.check("control: still reprogramming after undocking", T.st().reprogram_start ~= nil)
    T.st().reprogram_start = T.st().reprogram_start - 58
end)
T.waitFor("control: reprogram completes", function() return T.flag("boneyard_drone_flip") end, 5)
local G = BATTLE.ANNEX.gates
local function gateOf(s)
    for k, g in ipairs(G) do
        if dist(s, ANNEX_X + g[1] * 1000, ANNEX_Y + g[2] * 1000) < 4000 then return k end
    end
end
local victim, victim_gate
T.step("drones on our side", function()
    local d = T.st().rein_drones
    T.eq("control: 24 drones", T.alive(d), 24)
    T.eq("control: drones are Relic Active", d[1]:getFaction(), "Relic Active")
    T.eq("control: small ships (MT52 Hornet)", d[1]:getTypeName(), "MT52 Hornet")
    T.eq("control: drone lasers hit for 18 (1.5x the first 12)", d[1]:getBeamWeaponDamage(0), 18)
    T.eq("control: 1.5x the fastest Concord impulse (156)", math.floor(d[1]:getImpulseMaxSpeed() + 0.5), 156)
    T.check("control: drones have no warp", not d[1]:hasWarpDrive())
    local at = {0, 0}
    for _, s in ipairs(d) do local k = gateOf(s); if k then at[k] = at[k] + 1 end end
    T.eq("control: 12 out of the north-east nebula, 12 out of the south-west one", at[1] .. "/" .. at[2], "12/12")
    local ax, ay = ANNEX_X + G[2][1] * 1000, ANNEX_Y + G[2][2] * 1000
    T.check("control: the south-west gate is clear of Ashgrave", math.sqrt((ax - 39000) ^ 2 + (ay + 96000) ^ 2) > 5000)
    T.check("control: the reprogram does not arm the Annex", annex():getBeamWeaponRange(0) == 0)
    -- A drone dies: a new one comes out of the same nebula.
    victim = d[2]
    victim_gate = gateOf(victim)
    victim:destroy()
end)
T.waitFor("control: a dead drone is replaced", function() return T.alive(T.st().rein_drones) == 24 end, 3)
T.step("from the same nebula", function()
    local d = T.st().rein_drones
    T.eq("control: the replacement came from the dead drone's nebula", gateOf(d[#d]), victim_gate)
    T.eq("control: the dead drone is forgotten (the list does not grow)", #d, 24)
    T.eq("control: and so is its battle record", #T.st().annex_battle.b.sides.b, 24)
end)
T.talk(annex, {})
T.step("undocked: no operations", function()
    T.check("control: undocked, dock first", T.msg():find("Dock for more options", 1, true) ~= nil, T.msg())
end)
local annex_hit = false
T.dock(annex)
T.talk(annex, {"3) Enable station defense lasers"})
T.step("lasers booting", function()
    T.check("control: laser boot running", T.st().lasers_start ~= nil)
    T.st().lasers_start = T.st().lasers_start - 58
end)
T.waitFor("control: the lasers come online", function() return T.st().lasers_done end, 5)
T.step("the Annex is armed", function()
    T.eq("control: the Annex takes the drones' side", annex():getFaction(), "Relic Active")
    T.eq("control: the Annex has lasers", annex():getBeamWeaponRange(0), BATTLE.ANNEX.lasers.range)
    -- A Concord ship in laser range of the Annex draws its fire.
    local s = T.st().concord_group[2]
    s:setPosition(ANNEX_X - 2000, ANNEX_Y - 2000)
    local function hit(_, instigator) if instigator == annex() then annex_hit = true end end
    s:onTakingDamage(hit)
    s:onTakingShieldDamage(hit)
end)
T.waitFor("control: the Annex's lasers pick the Concord ship in range", function()
    return T.st().annex_battle.laser_target == T.st().concord_group[2]
end, 3)
T.step("the engine has the target", function()
    local ok, wt = pcall(function() return annex().components.weapons_target end)
    T.check("control: the Annex's weapons target is that ship", ok and wt and wt.entity == T.st().concord_group[2])
end)
T.waitFor("control: the Annex's lasers hit it", function() return annex_hit end, 10)
T.step("annex lasers hit hard; the Concord group dies", function()
    T.eq("control: Annex lasers hit for 16", annex():getBeamWeaponDamage(0), 16)
    for _, s in ipairs(T.st().concord_group) do if s:isValid() then s:destroy() end end
end)
T.waitFor("control: with the Concord gone, the drones guard the Annex", function()
    local d = T.st().annex_battle.b:ships("b")
    if #d == 0 then return false end
    for _, s in ipairs(d) do if s:getOrderTarget() ~= annex() then return false end end
    return true
end, 4)
T.step("fleet eliminated", function()
    T.check("report: the Annex reports the fleet eliminated", T.st().concord_beaten)
    T.eq("report: still 24 drones (no more replacements)", T.alive(T.st().rein_drones), 24)
    T.eq("report: archive and fleet done: report to the survivors", T.phase(), "report")
    T.eq("report: objective", RT.objectives.boneyard, "Report the success")
    T.check("report: patrols still suspended", PROX._suspended_zones["the Boneyard"])
end)

-- ── Report to the survivors ──────────────────────────────────────────────────
T.dock("Port Vesper")
T.talk("Port Vesper", {})
T.step("not where the survivors are", function()
    T.check("report: no survivors at Port Vesper", not T.hasReply("Talk with the lifeboat survivors"), table.concat(T.replies(), " | "))
end)
T.step("fly off", function() T.moveTo(0, 0) end)
T.talk("Halcyon Rest", {})
T.step("not docked", function()
    T.check("report: only docked", not T.hasReply("Talk with the lifeboat survivors"), table.concat(T.replies(), " | "))
end)
T.dock("Halcyon Rest")
T.wait(2.5)   -- flying into a new region pays survey credits (checked every 2 s): let that land first
T.step("before the talk", function()
    T.eq("report: not done before the talk", T.status(), "active")
    c0, concord0, corsairs0 = T.credits(), T.rep("Concord"), T.rep("Corsairs")
end)
T.talk("Halcyon Rest", {"Talk with the lifeboat survivors"})
T.step("their thanks", function()
    T.check("report: the battle group destroyed sets them back",
        T.msg():find("a whole Concord battle group destroyed? That'll set them back.", 1, true) ~= nil, T.msg())
    T.check("report: the Concord was very close to a cure", T.msg():find("The Concord was very close to a cure, but the political fallout", 1, true) ~= nil, T.msg())
    T.check("report: they head for Hob's Landing", T.msg():find("We're headed to Hob's Landing to keep our work moving forward.", 1, true) ~= nil, T.msg())
    T.check("report: exceptional engineers", T.msg():find("exceptional engineers", 1, true) ~= nil, T.msg())
end)
T.waitFor("done: the talk ends the arc", function() return T.status() == "done" end, 3)
T.step("resolved", function()
    T.eq("done: boneyard_arc_done", T.flag("boneyard_arc_done"), true)
    T.eq("done: objective cleared", RT.objectives.boneyard, nil)
    T.eq("done: 800 cr (data 600 + drones 200)", T.credits() - c0, 800)
    T.eq("done: Concord -500", T.rep("Concord") - concord0, -500)
    T.eq("done: Corsairs +150", T.rep("Corsairs") - corsairs0, 150)
    T.check("done: Boneyard patrols resumed", not PROX._suspended_zones["the Boneyard"])
    T.eq("done: three aftermath rumors (torn apart, Pale Sun, the Senate)", T.rumors("BONEYARD_DONE"), 3)
    T.eq("done: the fleet beaten is saved", T.flag("boneyard_fleet_beaten"), true)
    T.check("done: the arc's achievement is defined and earned", ACH.defs.boneyard_breach and ACH.defs.boneyard_breach.check(STATS.ensure()))
end)
T.closeComms()

-- ── The other ending: no survivors picked up, so the fight is the end ────────
T.step("no survivors: back to the hook", function()
    T.moveTo(ANNEX_X + 7000, ANNEX_Y - 3000)   -- over 8U from Ashgrave
    T.jump("hook")
    T.check("no survivors: no Annex", not RT.valid(annex()) and not T.flag("boneyard_buoy_found"))
    T.moveTo(39000, -102500)   -- 6.5U from Ashgrave (clear of the planet)
end)
T.waitFor("no survivors: flying to Ashgrave reveals the Annex", function() return RT.valid(annex()) end, 3)
T.waitFor("no survivors: and the hack starts", function() return T.phase() == "annex_hack" end, 3)
T.step("park the ship near the Annex", function() T.moveTo(ANNEX_X + 7000, ANNEX_Y - 3000) end)
T.step("back to the Annex, no survivors", function()
    T.jump("control")
    RT.clearFlag("boneyard_buoy_found")
    RT.clearFlag("boneyard_survivors_at")
end)
T.dock(annex)
T.waitFor("no survivors: the fleet jumps in", function() return T.st().fleet_arrived end, 3)
T.talk(annex, {"1) Download research archive"})
T.step("download under way, then the fleet goes", function()
    T.check("compress: downloading", T.st().download_start ~= nil)
    T.check("compress: not compressed while the fleet is out", not T.st().archive_compressed)
    T.st().download_start = T.now() - 30   -- 30 s into the 5 minutes
    T.action("Destroy Concord")
end)
T.waitFor("compress: the fleet gone compresses the archive", function() return T.st().archive_compressed end, 4)
T.step("a running download finishes within a minute", function()
    local t = T.st().download_time or 0
    T.check("compress: its total is the time so far + 60 s", t >= 90 and t < 95, t)
    T.check("compress: not done yet", not T.st().download_done)
end)
T.talk(annex, {})
T.step("the menu shows the shorter time", function()
    local left
    for _, r in ipairs(T.replies()) do
        local n = r:match("^%[IN PROGRESS%] Downloading archive: (%d+)s")
        if n then left = tonumber(n) end
    end
    T.check("compress: about a minute left", left and left > 50 and left <= 61, table.concat(T.replies(), " | "))
    T.st().download_start = T.st().download_start - 58
end)
T.closeComms()
T.waitFor("no survivors: the fight ends the arc", function() return T.status() == "done" end, 4)
T.step("no report", function()
    T.check("no survivors: the arc is done", T.flag("boneyard_arc_done"))
    T.check("no survivors: the archive is in", T.flag("boneyard_hack_done"))
end)

-- ── Leaving the Boneyard ends the arc, with whatever the crew has ───────────
T.step("leave: back at the Annex", function()
    T.moveTo(ANNEX_X + 7000, ANNEX_Y - 3000)
    T.jump("control")
    RT.clearFlag("boneyard_hack_done")
end)
T.dock(annex)
T.waitFor("leave: the fleet jumps in", function() return T.st().fleet_arrived end, 3)
T.undock()
T.step("leave: 45U out is not leaving yet", function()
    T.moveTo(36000 + 45000, -96000)   -- 45U from the Boneyard's centre: 16U outside it
end)
T.wait(1)
T.step("not yet", function()
    T.eq("leave: 16U outside the Boneyard is not enough", T.phase(), "annex_control")
    T.moveTo(36000 + 50000, -96000)   -- 50U: over 20U outside it
end)
T.waitFor("leave: 20U outside the Boneyard ends the arc", function() return T.status() == "done" end, 3)
T.step("left without the archive", function()
    T.check("leave: no archive", not T.flag("boneyard_hack_done"))
    T.check("leave: the arc is done", T.flag("boneyard_arc_done"))
end)

-- ── GM states ────────────────────────────────────────────────────────────────
local paid
-- Parked 7.6U from the Annex: inside the Boneyard (so annex_control does not end by itself), but
-- over 8U from Ashgrave (so the hook stays put).
T.step("park the ship near the Annex", function() T.moveTo(ANNEX_X + 7000, ANNEX_Y - 3000) end)
T.gmWalk({
    {key = "hook",    phase = "hook", check = function()
        T.check("GM hook: no Annex", not RT.valid(annex()))
        T.check("GM hook: no Concord group", T.alive(T.st().concord_group) == 0)
        T.eq("GM hook: rumors back", T.rumors("BONEYARD_HOOK"), 3)
    end},
    {key = "hack",    phase = "annex_hack", check = function()
        T.check("GM hack: Annex out", RT.valid(annex()))
        T.eq("GM hack: still hacking a second later", T.phase(), "annex_hack")
    end},
    {key = "control", phase = "annex_control", check = function()
        T.eq("GM control: no fleet until the crew docks", T.alive(T.st().concord_group), 0)
        T.eq("GM control: the Annex can be docked", annex():getFaction(), "Relic Active")
        T.check("GM control: zone suspended", PROX._suspended_zones["the Boneyard"])
    end},
    {key = "report",  phase = "report", check = function()
        T.eq("GM report: objective", RT.objectives.boneyard, "Report the success")
        T.check("GM report: the archive is in", T.flag("boneyard_hack_done"))
        T.eq("GM report: no fleet", T.alive(T.st().concord_group), 0)
    end},
    {key = "done_full", done = true, check = function()
        T.check("GM done_full: both objectives", T.flag("boneyard_hack_done") and T.flag("boneyard_drone_flip"))
        T.check("GM done_full: survivors rescued (the Hob Works needs them)", T.flag("boneyard_buoy_found"))
        T.check("GM done_full: the battle group destroyed", T.flag("boneyard_battlegroup_destroyed") and T.flag("boneyard_fleet_beaten"))
        T.check("GM done_full: world left clean", not RT.valid(annex()) and T.alive(T.st().concord_group) == 0)
        paid = T.credits()
    end},
    {key = "done_data", done = true, check = function()
        T.check("GM done_data: data only", T.flag("boneyard_hack_done") and not T.flag("boneyard_drone_flip"))
        T.check("GM done_data: survivors rescued", T.flag("boneyard_buoy_found"))
        T.eq("GM done_data: an end state does not pay twice", T.credits(), paid)
    end},
})

T.deactivate({
    gone = {"Ashgrave Annex"},
    check = function()
        T.check("inactive: Boneyard patrols resumed", not PROX._suspended_zones["the Boneyard"])
        T.eq("inactive: no rumors", T.rumors("BONEYARD_HOOK") + T.rumors("BONEYARD_DONE"), 0)
        T.eq("inactive: drones back as they were, no battle group left", census(), census0)
        T.eq("inactive: the gun platforms are Relic again", platformFactions().Relic, 3)
    end,
})
