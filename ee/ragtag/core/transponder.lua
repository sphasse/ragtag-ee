-- ee/ragtag/core/transponder.lua
-- The fake transponder code: a consumable sold at the Hob Works once the campaign has earned it.
--
-- One purchase is one code. Engineering's "Change transponder" button spends it: for
-- RT.TRANSPONDER.secs seconds the Concord reads the ship as clean. Anything that judges a ship by
-- its Concord standing asks RT.concordSees(ship) instead of RT.getReputation("Concord", ship):
-- while a code is running a wanted ship (standing below 0) reads as 0, so patrols spawn as
-- shake-downs that find nothing, and port guards and lane pickets let it pass. Its real standing
-- is unchanged, and so is anything it does while the code runs (shoot a Concord ship and it is an
-- enemy anyway).
--
-- Who owns what:
--   campaign.transponder_unlocked   for sale (campaign-wide): set by RT.unlockTransponder(), which
--                                   the Hob Works arc calls when the crew pays the Works
--   record.transponder_codes        codes a ship has bought and not used (its own record)
--   RT.shipState(ship).code_until   a running code (this session only)
-- The Hob Works heist has its own one-use code on the same button label (missions/hob.lua).

RT.TRANSPONDER = {
    cost    = 500,
    secs    = 600,                      -- the Concord rotates its keys
    sold_at = {["Hob's Landing"] = true},
    name    = "Fake transponder code",
}
local _POS = {"engineering", "engineering+"}

function RT.transponderUnlocked()
    return RT.campaign ~= nil and RT.campaign.transponder_unlocked == true
end

-- For sale from now on (idempotent). Tells the Science database (an event: core never names SCIDB),
-- unless quiet (restoring what an older save had earned: SCIDB.sync adds the entry quietly).
function RT.unlockTransponder(quiet)
    if not RT.campaign or RT.campaign.transponder_unlocked then return false end
    RT.campaign.transponder_unlocked = true
    RT.saveCampaign()
    if not quiet then RT.emit("transponder_unlocked", {}, "low") end
    return true
end

-- Not for sale (a GM reset of the arc that unlocked it). Codes already bought are kept.
function RT.lockTransponder()
    if not RT.campaign or not RT.campaign.transponder_unlocked then return false end
    RT.campaign.transponder_unlocked = false
    RT.saveCampaign()
    return true
end

function RT.transponderCodes(ship)
    local rec = RT.shipRecord(ship)
    return rec and (rec.transponder_codes or 0) or 0
end

function RT.addTransponderCodes(n, ship)
    local rec = RT.shipRecord(ship)
    if not rec then return end
    rec.transponder_codes = math.max(0, (rec.transponder_codes or 0) + n)
    RT.saveCampaign()
end

-- Seconds left on the ship's running code, or 0.
function RT.transponderLeft(ship)
    local p = RT.playerShip(ship)
    if not p then return 0 end
    local u = RT.shipState(p).code_until
    return u and math.max(0, u - getScenarioTime()) or 0
end

-- The standing the Concord reads for this ship: its real Concord standing, or at least 0 while a
-- fake code is running.
function RT.concordSees(ship)
    local rep = RT.getReputation("Concord", ship) or 0
    if RT.transponderLeft(ship) > 0 then return math.max(rep, 0) end
    return rep
end

-- Engineering's button: spend one code.
function RT.useTransponder(ship)
    local p = RT.playerShip(ship)
    if not p or RT.transponderCodes(p) <= 0 or RT.transponderLeft(p) > 0 then return false end
    RT.addTransponderCodes(-1, p)
    RT.shipState(p).code_until = getScenarioTime() + RT.TRANSPONDER.secs
    if STATS then STATS.inc("transponder_swaps", 1) end
    p:addToShipLog(string.format("[Engineering] Transponder swapped. The fake code will check out for %d minutes, "
        .. "until the Concord rotates its keys.%s", RT.TRANSPONDER.secs // 60,
        RT.transponderCodes(p) > 0 and (" " .. RT.transponderCodes(p) .. " more on hand.") or ""), "#80FF80")
    RT.emit("transponder_used", {ship = p:getCallSign()}, "low")
    RT.tickTransponders(true)
    return true
end

-- Engineering pop-up: what the new button does.
function RT.explainTransponder(ship)
    local p = RT.playerShip(ship)
    if not p then return end
    local text = "Fake transponder code installed.\n\nPress \"Change transponder\" when you need it. For "
        .. (RT.TRANSPONDER.secs // 60) .. " minutes the Concord reads this ship as clean: patrols find "
        .. "nothing to stop it for, and port guards and lane pickets let it pass. Then the Concord rotates "
        .. "its keys and the code is spent. Each code works once; the Hob Works sells more."
    for _, pos in ipairs(_POS) do
        pcall(function() p:addCustomMessage(pos, "rt_transponder_help_" .. pos, text) end)
    end
end

-- Keep each ship's Engineering button and countdown in step (every second, from RT.update).
RT._tp_next = 0
function RT.tickTransponders(force)
    local now = getScenarioTime()
    if not force and now < RT._tp_next then return end
    RT._tp_next = now + 1
    for _, p in ipairs(RT.players) do
        if RT.valid(p) then
            local st = RT.shipState(p)
            local left = RT.transponderLeft(p)
            local codes = RT.transponderCodes(p)
            local button = (left <= 0 and codes > 0) and ("Change transponder" .. (codes > 1 and (" (" .. codes .. ")") or "")) or nil
            local info = left > 0 and string.format("Code valid %d:%02d", math.floor(left / 60), math.floor(left % 60)) or nil
            if st.code_until and left <= 0 then
                st.code_until = nil
                p:addToShipLog("[Engineering] The Concord has rotated its keys. The fake code no longer checks out.", "#FFAA40")
            end
            -- A rebuilt ship is a new entity: its widgets are redrawn from scratch.
            if st.tp_ship ~= p then st.tp_button, st.tp_info, st.tp_ship = false, false, p end
            if button ~= st.tp_button then
                for _, pos in ipairs(_POS) do
                    if button then
                        pcall(function() p:addCustomButton(pos, "rt_transponder_" .. pos, button,
                            function() RT.useTransponder(p) end, 6) end)
                    else
                        pcall(function() p:removeCustom("rt_transponder_" .. pos) end)
                    end
                end
                st.tp_button = button
            end
            if info ~= st.tp_info then
                for _, pos in ipairs(_POS) do
                    if info then
                        pcall(function() p:addCustomInfo(pos, "rt_code_" .. pos, info, 7) end)
                    else
                        pcall(function() p:removeCustom("rt_code_" .. pos) end)
                    end
                end
                st.tp_info = info
            end
        end
    end
end

-- The shipwright's offer (core/stations.lua calls this inside its menu).
function RT.transponderShopReply(source, target)
    if not RT.transponderUnlocked() or not RT.TRANSPONDER.sold_at[target:getCallSign()] then return nil end
    local T = RT.TRANSPONDER
    local have = RT.transponderCodes(source)
    addCommsReply(string.format("Buy a %s (%d)", T.name:lower(), T.cost), function(s, t)
        if RT.credits(s) < T.cost then
            setCommsMessage("\"Come back when you can pay for it.\"")
        else
            RT.addCredits(-T.cost, "bought " .. T.name:lower(), s)
            RT.addTransponderCodes(1, s)
            setCommsMessage("\"Wired in. It's on your Engineering board: one swap, ten minutes, then the keys rotate. "
                .. "Don't make me regret it.\"")
            RT.explainTransponder(s)
            RT.emit("upgrade", {id = "transponder_code", how = "bought", station = t:getCallSign(), ship = s:getCallSign()})
            RT.tickTransponders(true)
        end
        addCommsReply("Back to shipwright", function(s2, t2) RT.shipwrightMenu(s2, t2) end)
    end)
    return string.format("%s (%d cr): one swap, %d minutes in which the Concord reads you as clean. "
        .. "You have %d.", T.name, T.cost, T.secs // 60, have)
end
