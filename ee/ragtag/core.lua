-- ee/ragtag/core.lua
-- Shared library for the "Long Haul" ragtag campaign.
--
-- Provides:
--   * Campaign persistence across sessions (getScriptStorage, key "ragtag.campaign")
--   * Player ship creation with purchased upgrades re-applied every session
--   * Credits (stored as the player ship's reputation points, visible on Relay)
--   * A generic station comms menu with a shipwright (upgrade shop) and rumours
--   * Objective display on Relay / Operations screens
--   * Small helpers (named object registry, distance, timers)
--
-- Usage in a scenario:
--   require("utils.lua")
--   require("ragtag/core.lua")
--   require("ragtag/verse.lua")
--   require("ragtag/director.lua")
--
-- Written against the ECS-era EmptyEpsilon scripting API (2024+ releases).

RT = RT or {}
RT.VERSION = "1.0"
RT.CAMPAIGN_KEY = "ragtag.campaign"   -- set per campaign by RT.useCampaign()
RT.PLAYER_FACTION = "Independent"
RT.PLAYER_TEMPLATE = "Flavia P.Falcon"

RT.named = {}          -- callsign -> entity, for objects the scenario or director created
RT.stations = {}       -- callsign -> {entity=..., shop=bool, flavor=string, hooks={fn,...}}
RT.objective = ""
RT.player = nil
RT.timers = {}         -- list of {at=time, fn=function, name=string}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

function RT.valid(e)
    return e ~= nil and e:isValid()
end

function RT.now()
    return getScenarioTime()
end

-- Run fn after `seconds` of scenario time. Returns the timer record.
function RT.after(seconds, fn, name)
    local t = {at = getScenarioTime() + seconds, fn = fn, name = name or "timer"}
    table.insert(RT.timers, t)
    return t
end

function RT.cancelTimer(name)
    for i = #RT.timers, 1, -1 do
        if RT.timers[i].name == name then table.remove(RT.timers, i) end
    end
end

function RT.updateTimers()
    local now = getScenarioTime()
    for i = #RT.timers, 1, -1 do
        local t = RT.timers[i]
        if now >= t.at then
            table.remove(RT.timers, i)
            local ok, err = pcall(t.fn)
            if not ok then print("[RT] timer '" .. t.name .. "' failed: " .. tostring(err)) end
        end
    end
end

function RT.register(entity, callsign)
    if callsign then entity:setCallSign(callsign) end
    RT.named[entity:getCallSign()] = entity
    return entity
end

-- Find an entity by callsign: registry first, then a radius scan around the player.
function RT.find(callsign)
    if callsign == nil or callsign == "" then return nil end
    local e = RT.named[callsign]
    if RT.valid(e) then return e end
    local cx, cy = 0, 0
    if RT.valid(RT.player) then cx, cy = RT.player:getPosition() end
    for _, obj in ipairs(getObjectsInRadius(cx, cy, 100000)) do
        if obj.getCallSign and obj:getCallSign() == callsign then
            RT.named[callsign] = obj
            return obj
        end
    end
    return nil
end

function RT.dist(a, b)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Hail the player from an entity; if their comms are busy, fall back to the log.
function RT.hail(from, text, speaker)
    if not RT.valid(RT.player) then return false end
    if RT.valid(from) and from:sendCommsMessage(RT.player, text) then return true end
    RT.player:addToShipLog("[" .. (speaker or (RT.valid(from) and from:getCallSign()) or "Unknown") .. "] " .. text, "#C0E0FF")
    return false
end

-- Remove control characters and clamp length for anything shown to players.
function RT.cleanText(s, max_len)
    s = tostring(s or "")
    s = s:gsub("[%c]", function(c) if c == "\n" then return "\n" end return " " end)
    max_len = max_len or 600
    if #s > max_len then s = s:sub(1, max_len - 3) .. "..." end
    return s
end

--------------------------------------------------------------------------------
-- Campaign persistence
--------------------------------------------------------------------------------

local function defaultCampaign()
    return {
        version = 1,
        ship_name = "Magpie",
        credits = 150,
        upgrades = {},   -- list of upgrade ids, applied in purchase order
        sessions = {},   -- "s1" -> {outcome="success", at=...}
        flags = {},      -- story flags: string -> bool/number/string
        notes = {},      -- short human-readable campaign log lines
        discovered = {}, -- names of charted regions (see ragtag_verse.lua)
    }
end

-- Each campaign keeps its own save, so scenarios from different campaigns
-- (or one-shots) never overwrite each other. Call before RT.loadCampaign().
function RT.useCampaign(id)
    RT.campaign_id = id
    RT.CAMPAIGN_KEY = "ragtag.campaign." .. id
    -- Saves from before the repo layout used a single shared key; adopt it once.
    if id == "longhaul" then
        local s = getScriptStorage()
        local cur = s:get(RT.CAMPAIGN_KEY)
        local legacy = s:get("ragtag.campaign")
        if (cur == nil or cur == "") and type(legacy) == "string" and legacy ~= "" then
            s:set(RT.CAMPAIGN_KEY, legacy)
        end
    end
end

function RT.loadCampaign(fresh)
    local c = nil
    if not fresh then
        local raw = getScriptStorage():get(RT.CAMPAIGN_KEY)
        if type(raw) == "string" and raw ~= "" then
            local ok, v = pcall(fromJSON, raw)
            if ok and type(v) == "table" then c = v end
        end
    end
    local d = defaultCampaign()
    if c == nil then
        c = d
    else
        for k, v in pairs(d) do
            if c[k] == nil then c[k] = v end
        end
        -- toJSON turns empty tables into arrays; normalise the keyed ones.
        if type(c.flags) ~= "table" then c.flags = {} end
        if type(c.sessions) ~= "table" then c.sessions = {} end
        if type(c.discovered) ~= "table" then c.discovered = {} end
    end
    RT.campaign = c
    return c
end

function RT.saveCampaign()
    if RT.campaign == nil then return end
    if RT.valid(RT.player) then
        RT.campaign.credits = math.floor(RT.player:getReputationPoints())
    end
    getScriptStorage():set(RT.CAMPAIGN_KEY, toJSON(RT.campaign))
end

function RT.flag(name, value)
    if value == nil then return RT.campaign.flags[name] end
    RT.campaign.flags[name] = value
    RT.saveCampaign()
    return value
end

function RT.note(text)
    table.insert(RT.campaign.notes, RT.cleanText(text, 200))
    while #RT.campaign.notes > 40 do table.remove(RT.campaign.notes, 1) end
end

function RT.hasUpgrade(id)
    for _, u in ipairs(RT.campaign.upgrades) do
        if u == id then return true end
    end
    return false
end

-- Mark a session finished and persist. outcome: "success", "partial", "failed"
function RT.completeSession(session_id, outcome, note)
    RT.campaign.sessions[session_id] = {outcome = outcome, at = math.floor(getScenarioTime())}
    if note then RT.note(session_id .. ": " .. note) end
    RT.saveCampaign()
end

--------------------------------------------------------------------------------
-- Credits (reputation points on the player ship)
--------------------------------------------------------------------------------

function RT.credits()
    if not RT.valid(RT.player) then return 0 end
    return math.floor(RT.player:getReputationPoints())
end

function RT.addCredits(amount, reason)
    if not RT.valid(RT.player) then return end
    amount = math.floor(amount)
    if amount >= 0 then
        RT.player:addReputationPoints(amount)
    else
        RT.player:setReputationPoints(math.max(0, RT.credits() + amount))
    end
    local sign = amount >= 0 and "+" or ""
    RT.player:addToShipLog(string.format("Credits %s%d (%s). Balance: %d", sign, amount, reason or "misc", RT.credits()), "#E0C060")
    RT.saveCampaign()
end

--------------------------------------------------------------------------------
-- Upgrades. Each apply() must be idempotent-safe when re-run on a fresh ship
-- (they are re-applied in purchase order at the start of every session).
--------------------------------------------------------------------------------

RT.UPGRADES = {
    {id = "hull_plating", name = "Salvaged hull plating", cost = 200,
     desc = "+50 hull.",
     apply = function(p) p:setHullMax(p:getHullMax() + 50); p:setHull(p:getHullMax()) end},
    {id = "shield_mk2", name = "Mk II shield emitters", cost = 250,
     desc = "Shields to 100 / 100.",
     apply = function(p) p:setShieldsMax(100, 100); p:setShields(100, 100) end},
    {id = "forward_beams", name = "Forward beam mount", cost = 300,
     desc = "Adds a forward-firing beam. Finally something pointing where you're going.",
     apply = function(p) p:setBeamWeapon(2, 50, 0, 1000, 6, 6) end},
    {id = "beam_coils", name = "Overclocked beam coils", cost = 250, requires = "forward_beams",
     desc = "+2 damage on every beam.",
     apply = function(p)
        for i = 0, 15 do
            local range = p:getBeamWeaponRange(i)
            if range ~= nil and range > 0 then
                p:setBeamWeapon(i, p:getBeamWeaponArc(i), p:getBeamWeaponDirection(i), range,
                    p:getBeamWeaponCycleTime(i), p:getBeamWeaponDamage(i) + 2)
            end
        end
     end},
    {id = "engine_tune", name = "Black-market engine tune", cost = 200,
     desc = "Impulse 60 -> 75.",
     apply = function(p) p:setImpulseMaxSpeed(75, 15) end},
    {id = "missile_racks", name = "Extra missile racks", cost = 150,
     desc = "+4 homing, +6 HVLI capacity.",
     apply = function(p)
        p:setWeaponStorageMax("Homing", p:getWeaponStorageMax("Homing") + 4)
        p:setWeaponStorageMax("HVLI", p:getWeaponStorageMax("HVLI") + 6)
        p:setWeaponStorage("Homing", p:getWeaponStorageMax("Homing"))
        p:setWeaponStorage("HVLI", p:getWeaponStorageMax("HVLI"))
     end},
    {id = "front_tube", name = "Bow torpedo tube", cost = 350,
     desc = "Adds a forward missile tube.",
     apply = function(p)
        -- setWeaponTubeCount rebuilds all tubes, so re-set both directions.
        p:setWeaponTubeCount(2)
        p:setWeaponTubeDirection(0, 180)
        p:setWeaponTubeDirection(1, 0)
     end},
    {id = "repair_crew", name = "Two more hands", cost = 150,
     desc = "+2 repair crew.",
     apply = function(p) p:setRepairCrewCount(p:getRepairCrewCount() + 2) end},
    {id = "sensor_suite", name = "Long-range sensor suite", cost = 150,
     desc = "Long-range radar 30u -> 45u.",
     apply = function(p) p:setLongRangeRadarRange(45000) end},
    {id = "jump_drive", name = "Second-hand jump drive", cost = 500,
     desc = "Jump drive, 5u - 30u.",
     apply = function(p) p:setJumpDrive(true); p:setJumpDriveRange(5000, 30000) end},

    -- Second tier: what it takes to survive Blackwater, the Boneyard and, eventually, the Maw.
    {id = "reactor_overhaul", name = "Reactor overhaul", cost = 200,
     desc = "+50% energy capacity.",
     apply = function(p) p:setMaxEnergy(p:getMaxEnergy() * 1.5); p:setEnergy(p:getMaxEnergy()) end},
    {id = "warp_overhaul", name = "Warp coil overhaul", cost = 250,
     desc = "Warp speed +50%.",
     apply = function(p) p:setWarpSpeed(p:getWarpSpeed() * 1.5) end},
    {id = "combat_thrusters", name = "Combat thrusters", cost = 300,
     desc = "Much stronger combat boost and strafe. Gets you out of trouble.",
     apply = function(p) p:setCombatManeuver(450, 300) end},
    {id = "hull_plating_2", name = "Armoured hull", cost = 450, requires = "hull_plating",
     desc = "+100 hull.",
     apply = function(p) p:setHullMax(p:getHullMax() + 100); p:setHull(p:getHullMax()) end},
    {id = "heavy_beams", name = "Heavy beam emitters", cost = 400, requires = "beam_coils",
     desc = "+400 range on every beam.",
     apply = function(p)
        for i = 0, 15 do
            local range = p:getBeamWeaponRange(i)
            if range ~= nil and range > 0 then
                p:setBeamWeapon(i, p:getBeamWeaponArc(i), p:getBeamWeaponDirection(i), range + 400,
                    p:getBeamWeaponCycleTime(i), p:getBeamWeaponDamage(i))
            end
        end
     end},
    {id = "shield_mk3", name = "Military shield generators", cost = 600, requires = "shield_mk2",
     desc = "Shields to 160 / 160. Concord military surplus, officially.",
     apply = function(p) p:setShieldsMax(160, 160); p:setShields(160, 160) end},
}

function RT.upgradeById(id)
    for _, u in ipairs(RT.UPGRADES) do
        if u.id == id then return u end
    end
    return nil
end

function RT.applyUpgrade(p, id)
    local u = RT.upgradeById(id)
    if u == nil then return false end
    local ok, err = pcall(u.apply, p)
    if not ok then print("[RT] upgrade " .. id .. " failed: " .. tostring(err)) end
    return ok
end

-- Grant an upgrade for free (story reward). Saves.
function RT.grantUpgrade(id, reason)
    if RT.hasUpgrade(id) or RT.upgradeById(id) == nil then return false end
    table.insert(RT.campaign.upgrades, id)
    if RT.valid(RT.player) then
        RT.applyUpgrade(RT.player, id)
        RT.player:addToShipLog("Upgrade installed: " .. RT.upgradeById(id).name .. (reason and (" (" .. reason .. ")") or ""), "#80FF80")
    end
    RT.saveCampaign()
    if DIR then DIR.emit("upgrade", {id = id, how = "granted", reason = reason}) end
    return true
end

--------------------------------------------------------------------------------
-- Player ship
--------------------------------------------------------------------------------

function RT.spawnPlayer(x, y, heading)
    local c = RT.campaign or RT.loadCampaign()
    local p = PlayerSpaceship():setTemplate(RT.PLAYER_TEMPLATE):setFaction(RT.PLAYER_FACTION)
    p:setCallSign(c.ship_name):setPosition(x, y)
    if heading then p:setHeading(heading) end
    -- A modest, slightly battered start: no nukes or mines on a freight hauler.
    p:setWeaponStorageMax("Nuke", 0):setWeaponStorage("Nuke", 0)
    p:setWeaponStorageMax("Mine", 0):setWeaponStorage("Mine", 0)
    p:setWeaponStorage("Homing", 2)
    for _, id in ipairs(c.upgrades) do RT.applyUpgrade(p, id) end
    p:setReputationPoints(c.credits or 0)
    RT.player = p
    RT.named[p:getCallSign()] = p
    return p
end

--------------------------------------------------------------------------------
-- Objectives (shown on Relay and Operations, logged to ship's log)
--------------------------------------------------------------------------------

function RT.setObjective(text, silent)
    RT.objective = RT.cleanText(text, 160)
    if RT.valid(RT.player) then
        RT.player:addCustomInfo("relay", "rt_objective", "Job: " .. RT.objective, 0)
        RT.player:addCustomInfo("operations", "rt_objective_ops", "Job: " .. RT.objective, 0)
        if not silent then RT.player:addToShipLog("New objective: " .. RT.objective, "#80C0FF") end
    end
    if DIR then DIR.emit("objective", {text = RT.objective}) end
end

--------------------------------------------------------------------------------
-- Stations and comms
--------------------------------------------------------------------------------

-- Create a station that uses the campaign comms menu.
--   opts: template, faction, callsign, x, y, shop (bool), flavor (string), description
function RT.station(opts)
    local s = SpaceStation():setTemplate(opts.template or "Small Station")
    s:setFaction(opts.faction or "Independent"):setPosition(opts.x, opts.y)
    if opts.callsign then s:setCallSign(opts.callsign) end
    if opts.description then s:setDescription(opts.description) end
    local cs = s:getCallSign()
    RT.stations[cs] = {entity = s, shop = opts.shop or false, flavor = opts.flavor or "", hooks = {}}
    RT.named[cs] = s
    s:setCommsFunction(RT.stationComms)
    return s
end

-- Add scenario-specific comms replies to a station.
-- fn(source, target, info) is called while the menu is built; it may call addCommsReply.
function RT.addStationHook(callsign, fn)
    local info = RT.stations[callsign]
    if info then table.insert(info.hooks, fn) end
end

function RT.stationComms(source, target)
    local info = RT.stations[target:getCallSign()] or {flavor = "", hooks = {}}
    if source:isEnemy(target) then
        setCommsMessage("Static. Then a click. They've cut the channel.")
        return
    end
    local msg = info.flavor ~= "" and info.flavor or ("This is " .. target:getCallSign() .. ". State your business.")
    if source:isDocked(target) then
        msg = msg .. "\n\nYou're docked. Balance: " .. RT.credits() .. " credits."
    end
    setCommsMessage(msg)

    for _, hook in ipairs(info.hooks) do
        local ok, err = pcall(hook, source, target, info)
        if not ok then print("[RT] station hook failed: " .. tostring(err)) end
    end

    if source:isDocked(target) then
        if info.concord and RT.campaign.flags.wanted then
            addCommsReply("Request services", function(s, t)
                setCommsMessage("\"Your transponder is flagged, " .. s:getCallSign() .. ". No services for wanted vessels. " ..
                    "Undock and consider yourself lucky we're not detaining you.\"")
            end)
        else
            if info.shop then
                addCommsReply("Shipwright: browse upgrades", function(s, t) RT.shipwrightMenu(s, t) end)
            end
            addCommsReply("Restock missiles (15 cr each)", function(s, t) RT.restockMenu(s, t) end)
        end
    end

    addCommsReply("Any news worth hearing?", function(s, t)
        setCommsMessage("\"Let me ask around. I'll ping you if anything turns up.\"")
        if DIR then
            DIR.emit("comms_ask", {station = t:getCallSign(), faction = t:getFaction(), topic = "rumours"}, "high")
        end
        addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
    end)
end

-- Does this station's shipwright sell the upgrade? shop = true sells everything.
function RT.stocks(info, id)
    if info.shop == true then return true end
    if type(info.shop) ~= "table" then return false end
    for _, s in ipairs(info.shop) do
        if s == id then return true end
    end
    return false
end

function RT.shipwrightMenu(source, target)
    local info = RT.stations[target:getCallSign()] or {shop = true}
    local lines = {"Shipwright. Balance: " .. RT.credits() .. " credits.\n"}
    local any = false
    for _, u in ipairs(RT.UPGRADES) do
        if RT.stocks(info, u.id) and not RT.hasUpgrade(u.id) and (u.requires == nil or RT.hasUpgrade(u.requires)) then
            any = true
            table.insert(lines, string.format("%s (%d cr): %s", u.name, u.cost, u.desc))
            addCommsReply(string.format("Buy %s (%d)", u.name, u.cost), function(s, t)
                if RT.credits() < u.cost then
                    setCommsMessage("\"Come back when you can pay for it.\"")
                else
                    RT.addCredits(-u.cost, "bought " .. u.name)
                    table.insert(RT.campaign.upgrades, u.id)
                    RT.applyUpgrade(s, u.id)
                    RT.saveCampaign()
                    setCommsMessage("Installed: " .. u.name .. ". Try not to scratch it.")
                    if DIR then DIR.emit("upgrade", {id = u.id, how = "bought", station = t:getCallSign()}) end
                end
                addCommsReply("Back to shipwright", function(s2, t2) RT.shipwrightMenu(s2, t2) end)
            end)
        end
    end
    if not any then table.insert(lines, "Nothing here I can bolt onto that hull. Try another yard.") end
    -- Point the crew at where else to look.
    local elsewhere = {}
    for cs, other in pairs(RT.stations) do
        if cs ~= target:getCallSign() and other.shop then
            for _, u in ipairs(RT.UPGRADES) do
                if RT.stocks(other, u.id) and not RT.hasUpgrade(u.id) and not RT.stocks(info, u.id) then
                    elsewhere[u.name] = elsewhere[u.name] or cs
                end
            end
        end
    end
    local tips = {}
    for name, cs in pairs(elsewhere) do table.insert(tips, name .. " (" .. cs .. ")") end
    table.sort(tips)
    if #tips > 0 then
        table.insert(lines, "\nHeard you can get elsewhere: " .. table.concat(tips, ", ", 1, math.min(#tips, 6)) .. ".")
    end
    setCommsMessage(table.concat(lines, "\n"))
    addCommsReply("Back", function(s, t) RT.stationComms(s, t) end)
end

function RT.restockMenu(source, target)
    setCommsMessage("Missiles are 15 credits apiece. Balance: " .. RT.credits())
    for _, w in ipairs({"Homing", "HVLI"}) do
        local missing = source:getWeaponStorageMax(w) - source:getWeaponStorage(w)
        if missing > 0 then
            addCommsReply(string.format("Fill %s (%d for %d cr)", w, missing, missing * 15), function(s, t)
                local m = s:getWeaponStorageMax(w) - s:getWeaponStorage(w)
                local cost = m * 15
                if RT.credits() < cost then
                    setCommsMessage("\"You're short.\"")
                else
                    RT.addCredits(-cost, "restocked " .. w)
                    s:setWeaponStorage(w, s:getWeaponStorageMax(w))
                    setCommsMessage("Loaded.")
                end
                addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
            end)
        end
    end
    addCommsReply("Back", function(s, t) RT.stationComms(s, t) end)
end

--------------------------------------------------------------------------------
-- Common GM tools
--------------------------------------------------------------------------------

function RT.addCampaignGMFunctions()
    addGMFunction("Campaign: show status", function()
        local c = RT.campaign
        local msg = "Campaign: " .. (RT.campaign_id or "unknown") .. "\n"
        msg = msg .. "Ship: " .. c.ship_name .. "\n"
        msg = msg .. "Credits: " .. RT.credits() .. "\n"
        msg = msg .. "Upgrades (" .. #c.upgrades .. "): " .. (c.upgrades[1] and table.concat(c.upgrades, ", ") or "none") .. "\n"
        local session_list = {}
        for sid, _ in pairs(c.sessions) do table.insert(session_list, sid) end
        table.sort(session_list)
        msg = msg .. "Completed sessions: " .. (session_list[1] and table.concat(session_list, ", ") or "none")
        addGMMessage(msg)
    end)

    addGMFunction("Campaign: +200 credits", function() RT.addCredits(200, "GM") end)
    addGMFunction("Campaign: -200 credits", function() RT.addCredits(-200, "GM") end)

    addGMFunction("Campaign: save now", function()
        RT.saveCampaign()
        addGMMessage("Campaign saved. Credits: " .. RT.credits() .. ", Upgrades: " .. #RT.campaign.upgrades)
    end)

    addGMFunction("Ship: reset to fresh (keep credits)", function()
        if not RT.valid(RT.player) then
            addGMMessage("No player ship to reset.")
            return
        end
        -- Store current state
        local px, py = RT.player:getPosition()
        local heading = RT.player:getHeading()
        local old_upgrades = #RT.campaign.upgrades

        -- Clear upgrades but keep credits and story progress
        RT.campaign.upgrades = {}
        RT.saveCampaign()

        -- Respawn with fresh ship
        RT.player:destroy()
        RT.spawnPlayer(px, py, heading)

        addGMMessage("Ship reset to stock template. Removed " .. old_upgrades .. " upgrades. Credits preserved: " .. RT.credits())
    end)

    addGMFunction("Ship: full repair + refuel", function()
        if not RT.valid(RT.player) then
            addGMMessage("No player ship to repair.")
            return
        end
        -- Repair hull
        RT.player:setHull(RT.player:getHullMax())

        -- Restore shields
        local front_max, rear_max = RT.player:getShieldsMax()
        RT.player:setShields(front_max, rear_max)

        -- Refuel energy
        RT.player:setEnergy(RT.player:getMaxEnergy())

        -- Restock missiles
        for _, missile_type in ipairs({"Homing", "Nuke", "Mine", "EMP", "HVLI"}) do
            RT.player:setWeaponStorage(missile_type, RT.player:getWeaponStorageMax(missile_type))
        end

        -- Repair all systems to 100%
        for _, system in ipairs({"reactor", "beamweapons", "missilesystem", "maneuver", "impulse", "warp", "jumpdrive", "frontshield", "rearshield"}) do
            RT.player:setSystemHealth(system, 1.0)
            RT.player:setSystemHeat(system, 0.0)
        end

        addGMMessage("Ship fully repaired and refueled: Hull, shields, energy, missiles, and all systems restored.")
    end)

    addGMFunction("Ship: snapshot current state", function()
        if not RT.valid(RT.player) then
            addGMMessage("No player ship to snapshot.")
            return
        end
        -- Save current hull/shields/energy as percentages
        local hull_pct = RT.player:getHull() / RT.player:getHullMax()
        local front_shield, rear_shield = RT.player:getShieldLevel()
        local front_max, rear_max = RT.player:getShieldsMax()
        local energy_pct = RT.player:getEnergy() / RT.player:getMaxEnergy()

        RT.campaign.ship_snapshot = {
            hull_pct = hull_pct,
            front_shield_pct = front_max > 0 and front_shield / front_max or 0,
            rear_shield_pct = rear_max > 0 and rear_shield / rear_max or 0,
            energy_pct = energy_pct,
            position = {x = RT.player:getPosition()},
            heading = RT.player:getHeading(),
        }
        RT.saveCampaign()

        addGMMessage(string.format("Ship snapshot saved: Hull %.0f%%, Shields %.0f/%.0f%%, Energy %.0f%%, Position recorded.",
            hull_pct * 100,
            (front_max > 0 and front_shield / front_max or 0) * 100,
            (rear_max > 0 and rear_shield / rear_max or 0) * 100,
            energy_pct * 100))
    end)

    addGMFunction("Ship: restore from snapshot", function()
        if not RT.valid(RT.player) then
            addGMMessage("No player ship to restore.")
            return
        end
        local snap = RT.campaign.ship_snapshot
        if not snap then
            addGMMessage("No snapshot saved. Use 'Ship: snapshot current state' first.")
            return
        end

        -- Restore hull/shields/energy
        RT.player:setHull(RT.player:getHullMax() * snap.hull_pct)
        local front_max, rear_max = RT.player:getShieldsMax()
        RT.player:setShields(front_max * snap.front_shield_pct, rear_max * snap.rear_shield_pct)
        RT.player:setEnergy(RT.player:getMaxEnergy() * snap.energy_pct)

        -- Restore position if saved
        if snap.position and snap.position.x then
            RT.player:setPosition(snap.position.x, snap.position[2] or 0)
        end
        if snap.heading then
            RT.player:setHeading(snap.heading)
        end

        addGMMessage(string.format("Ship restored from snapshot: Hull %.0f%%, Shields %.0f/%.0f%%, Energy %.0f%%",
            snap.hull_pct * 100,
            snap.front_shield_pct * 100,
            snap.rear_shield_pct * 100,
            snap.energy_pct * 100))
    end)
end

--------------------------------------------------------------------------------
-- Per-frame housekeeping. Call from update(delta).
--------------------------------------------------------------------------------

RT._last_save = 0
RT._hull_marks = {}

function RT.update(delta)
    RT.updateTimers()
    local now = getScenarioTime()
    if RT.valid(RT.player) then
        -- Autosave credits every 60s so a crash doesn't eat the crew's money.
        if now - RT._last_save > 60 then
            RT._last_save = now
            RT.saveCampaign()
        end
        -- Report hull thresholds once each (75/50/25%).
        local pct = RT.player:getHull() / RT.player:getHullMax() * 100
        for _, mark in ipairs({75, 50, 25}) do
            if pct < mark and not RT._hull_marks[mark] then
                RT._hull_marks[mark] = true
                if DIR then DIR.emit("player_damaged", {hull_pct = math.floor(pct)}, mark <= 50 and "high" or "normal") end
            elseif pct > mark + 10 then
                RT._hull_marks[mark] = nil
            end
        end
    end
end
