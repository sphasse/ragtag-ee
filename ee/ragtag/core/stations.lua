-- ee/ragtag/core/stations.lua
-- Campaign stations and their comms menu: hooks, shipwright, restock (RT.station, RT.stationComms, ...).
-- Part of core (RT). Loaded by ee/ragtag/core.lua; do not require directly.

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

-- Returns a one-line reputation-flavored aside appended to the station greeting,
-- or nil when standing is neutral. Only Concord and Independent have voiced drift.
local function _repDrift(source, faction)
    local rep = RT.getReputation(faction)
    local cs  = source:getCallSign()
    if faction == "Concord" then
        if     rep >  1000 then return '"Your record here is noted, ' .. cs .. '. We appreciate crews that keep their word."'
        elseif rep >   250 then return '"Welcome, ' .. cs .. '. You\'re known here."'
        elseif rep < -1000 then return '"This channel is monitored, ' .. cs .. '. State your business and go."'
        elseif rep <  -250 then return '"We\'re watching your transponder, ' .. cs .. '. Keep this brief."'
        end
    elseif faction == "Independent" then
        if     rep >  1000 then return '"You\'ve made some friends out here, ' .. cs .. '. That matters."'
        elseif rep >   250 then return '"Word\'s gotten around. Good word, in your case."'
        elseif rep < -1000 then return '"You\'re not exactly popular right now. What do you need?"'
        elseif rep <  -250 then return '"Heard a few things about your crew lately. Not all of them good."'
        end
    end
    return nil
end

function RT.stationComms(source, target)
    local info = RT.stations[target:getCallSign()] or {flavor = "", hooks = {}}
    if source:isEnemy(target) then
        setCommsMessage("Static. Then a click. They've cut the channel.")
        return
    end
    local msg = info.flavor ~= "" and info.flavor or ("This is " .. target:getCallSign() .. ". State your business.")
    local drift = _repDrift(source, target:getFaction())
    if drift then msg = msg .. "\n\n" .. drift end
    if source:isDocked(target) then
        msg = msg .. "\n\nYou're docked. Balance: " .. RT.credits(source) .. " credits."
    end
    setCommsMessage(msg)

    for _, hook in ipairs(info.hooks) do
        local ok, err = pcall(hook, source, target, info)
        if not ok then log("[RT] station hook failed: " .. tostring(err)) end
    end

    if source:isDocked(target) then
        if info.shop then
            addCommsReply("Shipwright: browse upgrades", function(s, t) RT.shipwrightMenu(s, t) end)
        end
        addCommsReply("Restock missiles (15 cr each)", function(s, t) RT.restockMenu(s, t) end)
    end

    addCommsReply("Any news worth hearing?", function(s, t)
        -- Deliver a rumor with cooldown, plus ping the director for dynamic content
        -- RUMORS.get returns nil when the rumors plugin is disabled.
        local rumor = RUMORS and RUMORS.get and RUMORS.get(s:getCallSign(), t:getFaction())
        local rumor_text = "\"" .. (rumor or "Nothing worth repeating right now.") .. "\""
        setCommsMessage(rumor_text)
        if DIR then
            DIR.emit("comms_ask", {station = t:getCallSign(), faction = t:getFaction(), topic = "rumours"}, "normal")
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
    local lines = {"Shipwright. Balance: " .. RT.credits(source) .. " credits.\n"}
    local any = false
    for _, u in ipairs(RT.UPGRADES) do
        if RT.stocks(info, u.id) and not RT.hasUpgrade(u.id) and (u.requires == nil or RT.hasUpgrade(u.requires))
           and (u.available == nil or u.available(source)) then
            any = true
            table.insert(lines, string.format("%s (%d cr): %s", u.name, u.cost, u.desc))
            addCommsReply(string.format("Buy %s (%d)", u.name, u.cost), function(s, t)
                if RT.credits(s) < u.cost then
                    setCommsMessage("\"Come back when you can pay for it.\"")
                else
                    RT.addCredits(-u.cost, "bought " .. u.name, s)
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
    setCommsMessage("Missiles are 15 credits apiece. Balance: " .. RT.credits(source))
    for _, w in ipairs({"Homing", "HVLI"}) do
        local missing = source:getWeaponStorageMax(w) - source:getWeaponStorage(w)
        if missing > 0 then
            addCommsReply(string.format("Fill %s (%d for %d cr)", w, missing, missing * 15), function(s, t)
                local m = s:getWeaponStorageMax(w) - s:getWeaponStorage(w)
                local cost = m * 15
                if RT.credits(s) < cost then
                    setCommsMessage("\"You're short.\"")
                else
                    RT.addCredits(-cost, "restocked " .. w, s)
                    s:setWeaponStorage(w, s:getWeaponStorageMax(w))
                    setCommsMessage("Loaded.")
                end
                addCommsReply("Back", function(s2, t2) RT.stationComms(s2, t2) end)
            end)
        end
    end
    addCommsReply("Back", function(s, t) RT.stationComms(s, t) end)
end
