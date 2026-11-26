-- The fake transponder code (core/transponder.lua): not for sale until the campaign unlocks it, then
-- sold at the Hob Works shipwright only, one code per purchase in the buying ship's record; the
-- Engineering button spends one; while it runs the Concord reads a wanted ship as clean (port guards
-- stand down); it runs out; the "Nothing to See Here" achievement; the Science DB's Ship Upgrades
-- entry (added when unlocked, removed when locked again) and the Achievements entry.
--
-- Not covered: pressing the button on a real Engineering screen (RT.useTransponder is called), a
-- real Concord patrol stop with the code running (RT.concordSees is checked; proximity.lua uses it).

T.suite("core")

local A, c0, guard_slot

local function stateOf(p) return RT.shipState(p) end

T.step("setup: not for sale yet", function()
    A = T.P()
    RT.lockTransponder()
    T.check("locked: not unlocked", not RT.transponderUnlocked())
    T.eq("locked: no codes", RT.transponderCodes(A), 0)
    T.check("locked: no Science DB entry", SCIDB._entries["upgrades_transponder"] == nil)
    RT.addCredits(2000 - RT.credits(A), "test", A)
end)
T.dock("Hob's Landing")
T.talk("Hob's Landing", {"Shipwright: browse upgrades"})
T.step("locked: the Hob Works does not sell it", function()
    T.check("locked: no buy button", not T.hasReply("Buy a fake transponder code"), table.concat(T.replies(), " | "))
    RT.unlockTransponder()
end)
T.wait(1.5)
T.step("unlocked", function()
    T.check("unlocked: flag", RT.transponderUnlocked())
    T.check("unlocked: Ship Upgrades > Fake transponder", SCIDB._entries["upgrades_transponder"] ~= nil)
    local e = SCIDB._entries["upgrades_transponder"]
    T.check("unlocked: says what it does", e and e:getLongDescription():find("the Concord reads the ship as clean", 1, true) ~= nil)
    T.eq("unlocked: price", e and e:getKeyValue("Price"), "500 cr")
    local said = false
    for _, l in ipairs(SCIDB.announced) do if l:find("Ship Upgrades > Fake transponder", 1, true) then said = true end end
    T.check("unlocked: announced", said, table.concat(SCIDB.announced, " | "))
end)
T.talk("Hob's Landing", {"Shipwright: browse upgrades"})
T.step("for sale at the Hob Works", function()
    T.check("shop: the line", T.msg():find("Fake transponder code (500 cr)", 1, true) ~= nil, T.msg())
    T.check("shop: the buy button", T.hasReply("Buy a fake transponder code (500)"), table.concat(T.replies(), " | "))
    c0 = RT.credits(A)
end)
T.reply({"Buy a fake transponder code (500)"})
T.step("bought one", function()
    T.eq("buy: -500", RT.credits(A) - c0, -500)
    T.eq("buy: one code", RT.transponderCodes(A), 1)
    T.check("buy: the reply", T.msg():find("Wired in.", 1, true) ~= nil, T.msg())
end)
T.reply({"Back to shipwright", "Buy a fake transponder code (500)"})
T.wait(1.5)
T.step("bought two; the button shows the count", function()
    T.eq("buy: two codes", RT.transponderCodes(A), 2)
    T.eq("button: on Engineering", stateOf(A).tp_button, "Change transponder (2)")
    T.check("button: no countdown yet", stateOf(A).tp_info == nil)
end)
T.closeComms()
T.dock("Port Vesper")
T.talk("Port Vesper", {})
T.step("other ports do not sell it", function()
    T.check("Vesper: no shipwright offer", not T.hasReply("Buy a fake transponder code"), table.concat(T.replies(), " | "))
end)
T.closeComms()

-- ── Using one: a wanted ship near a Concord port guard ──────────────────────
T.step("wanted, beside a Concord guard", function()
    T.undock()
    RT.addReputation("Concord", -300 - T.rep("Concord", A), "test", A)
    guard_slot = T.world("defenders").slots["Concord Station Arbiter"]
    T.moveNear(guard_slot.ship, 3000)
end)
T.waitFor("guard: turns on the wanted ship", function() return guard_slot.hostile_to ~= nil end, 3)
T.step("swap the transponder", function()
    T.eq("sees: wanted", RT.concordSees(A), -300)
    T.check("use: works", RT.useTransponder(A))
    T.eq("use: one code left", RT.transponderCodes(A), 1)
    T.check("use: ten minutes", math.abs(RT.transponderLeft(A) - 600) < 2, RT.transponderLeft(A))
    T.eq("sees: clean while it runs", RT.concordSees(A), 0)
    T.eq("real standing unchanged", T.rep("Concord", A), -300)
    T.check("use: not twice at once", not RT.useTransponder(A))
end)
T.waitFor("guard: stands down for a clean ship", function() return guard_slot.hostile_to == nil end, 3)
T.step("while it runs", function()
    T.eq("guard: Concord again", guard_slot.ship:getFaction(), "Concord")
    T.check("ui: countdown on Engineering", (stateOf(A).tp_info or ""):find("^Code valid ") ~= nil, tostring(stateOf(A).tp_info))
    T.check("ui: button hidden while it runs", stateOf(A).tp_button == nil)
end)
T.waitFor("achievement: Nothing to See Here", function() return ACH.has("nothing_to_see") end, 7)
T.waitFor("Science DB: achievements list it as earned", function()
    local e = SCIDB._entries["achievements"]
    return e ~= nil and e:getLongDescription():find(SCIDB.ACH_EARNED .. "Nothing to See Here", 1, true) ~= nil
end, 4)
T.step("the code runs out", function()
    stateOf(A).code_until = getScenarioTime() - 1
end)
T.wait(1.5)
T.step("expired", function()
    T.eq("expired: wanted again", RT.concordSees(A), -300)
    T.check("expired: countdown gone", stateOf(A).tp_info == nil)
    T.eq("expired: the button is back for the last code", stateOf(A).tp_button, "Change transponder")
end)
T.waitFor("guard: notices again", function() return guard_slot.hostile_to ~= nil end, 3)

-- ── The Achievements entry ───────────────────────────────────────────────────
T.step("the achievements entry", function()
    local e = SCIDB._entries["achievements"]
    local text = e:getLongDescription()
    T.check("achievements: lists one not yet earned", text:find(SCIDB.ACH_PENDING .. "Old Hand: Complete 50 jobs.</>", 1, true) ~= nil, text)
    local hidden_shown = false
    for _, id in ipairs(ACH.order) do
        local d = ACH.defs[id]
        if d.hidden and not ACH.has(id) and text:find(d.name, 1, true) then hidden_shown = true end
    end
    T.check("achievements: hidden ones stay secret until earned", not hidden_shown)
    T.check("achievements: hidden ones show as ???", text:find("???", 1, true) ~= nil)
    local n = 0
    for _ in pairs(RT.campaign.achievements) do n = n + 1 end
    T.check("achievements: earned count at the top", text:find("<h2>Earned " .. n .. " of " .. #ACH.order .. "</>", 1, true) == 1, text)
    local kv = e:getKeyValue("Earned")
    T.check("achievements: one column (no key/values)", kv == nil or kv == "", tostring(kv))
end)

-- ── Locked again (a GM reset of the Hob Works) ───────────────────────────────
T.step("locked again", function()
    RT.addReputation("Concord", 0 - T.rep("Concord", A), "test", A)
    RT.lockTransponder()
    SCIDB.sync()
    T.check("relock: entry removed", SCIDB._entries["upgrades_transponder"] == nil)
    T.eq("relock: codes kept", RT.transponderCodes(A), 1)
    T.moveNear("Port Vesper", 3000)
end)
