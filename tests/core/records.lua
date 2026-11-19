-- Per-ship records: everything a player ship owns (credits, standing, upgrades) is in its own
-- record, and nothing a second ship does lands on the primary ship. A = the primary ship,
-- B = a second freighter. Credits themselves: tests/jobs/credits.lua. Jobs: tests/jobs/multiship.lua.
--
-- Not covered: a kill by actual weapons fire (the test applies damage with the killer as
-- instigator, applyDamageToEntity), and a real restart of the game (a JSON round trip of
-- the save stands in).

T.suite("core")

local HOME = "Port Vesper"
local A, B
local a_c0, b_c0

local function has(list, id)
    for _, u in ipairs(list) do if u == id then return true end end
    return false
end

T.step("two ships", function()
    A = T.P()
    B = T.secondShip()
    T.eq("record: the primary ship's record is the campaign", RT.shipRecord(A), RT.campaign)
    local rb = RT.shipRecord(B)
    T.check("record: B has its own", rb ~= nil and rb ~= RT.campaign)
    T.eq("record: B's is saved under its callsign", rb.name, B:getCallSign())
    T.eq("record: asked twice, the same record", RT.shipRecord(B), rb)
    T.eq("record: no ship given means the primary ship", RT.shipRecord(nil), RT.campaign)
    T.eq("record: B starts with no upgrades", #RT.upgrades(B), 0)
    RT.setCredits(1000, A)
    RT.setCredits(1000, B)
end)

-- ── Upgrades: bought by a ship, for that ship ────────────────────────────────
T.actAs(function() return B end)
T.dock(HOME)
T.talk(HOME, {"Shipwright: browse upgrades"})
T.step("B looks at the yard", function()
    T.check("shop: hull plating on offer to B", T.hasReply("Buy Salvaged hull plating"), table.concat(T.replies(), " | "))
    a_c0, b_c0 = T.credits(A), T.credits(B)
end)
local hull_a0, hull_b0
T.step("note hulls", function() hull_a0, hull_b0 = A:getHullMax(), B:getHullMax() end)
T.talk(HOME, {"Shipwright: browse upgrades", "Buy Salvaged hull plating"})
T.step("B bought it", function()
    T.eq("buy: B paid", b_c0 - T.credits(B), 200)
    T.eq("buy: A did not", T.credits(A), a_c0)
    T.check("buy: in B's record", RT.hasUpgrade("hull_plating", B))
    T.check("buy: not in A's record", not RT.hasUpgrade("hull_plating", A))
    T.check("buy: not in the campaign's (primary) list", not has(RT.campaign.upgrades, "hull_plating"))
    T.eq("buy: B's hull +50", B:getHullMax() - hull_b0, 50)
    T.eq("buy: A's hull unchanged", A:getHullMax(), hull_a0)
    T.eq("spend: B's upgrade spend", RT.upgradeSpend(B), 200)
    T.eq("spend: A's upgrade spend", RT.upgradeSpend(A), 0)
end)
T.talk(HOME, {"Shipwright: browse upgrades"})
T.step("B is not offered it twice", function()
    T.check("shop: gone from B's list", not T.hasReply("Buy Salvaged hull plating"), table.concat(T.replies(), " | "))
end)
T.actAs(nil)
T.dock(HOME)
T.talk(HOME, {"Shipwright: browse upgrades"})
T.step("A still is", function()
    T.check("shop: still on offer to A", T.hasReply("Buy Salvaged hull plating"), table.concat(T.replies(), " | "))
end)
T.closeComms()

-- ── Job tier follows the ship's own investment ───────────────────────────────
T.step("tier", function()
    T.eq("tier: A at 0", JOBS.maxTier(A), 0)
    RT.grantUpgrade("shield_mk2", "test", B)
    RT.grantUpgrade("forward_beams", "test", B)
    T.eq("tier: B at 1 after 750cr of upgrades", JOBS.maxTier(B), 1)
    T.eq("tier: A still 0", JOBS.maxTier(A), 0)
    T.check("grant: only on the ship named", RT.hasUpgrade("shield_mk2", B) and not RT.hasUpgrade("shield_mk2", A))
    T.check("grant: refused twice", not RT.grantUpgrade("shield_mk2", "test", B))
    T.check("grant: unknown upgrade refused", not RT.grantUpgrade("no_such_upgrade", "test", B))
end)
T.step("revoke", function()
    T.check("revoke: done", RT.revokeUpgrade("hull_plating", B))
    T.check("revoke: out of B's record", not RT.hasUpgrade("hull_plating", B))
    T.eq("revoke: B's hull back", B:getHullMax(), hull_b0)
    T.check("revoke: B keeps its other upgrades", RT.hasUpgrade("shield_mk2", B) and RT.hasUpgrade("forward_beams", B))
    T.eq("revoke: B keeps its name", B:getCallSign(), "Kestrel")
    T.check("revoke: B is still B", RT.playerShip(B) == B and RT.players[2] == B)
    T.check("revoke: nothing to revoke on A", not RT.revokeUpgrade("hull_plating", A))
end)

-- ── A kill costs the ship that made it ───────────────────────────────────────
local victim
T.step("B destroys a Concord ship", function()
    local x, y = B:getPosition()
    victim = CpuShip():setTemplate("MT52 Hornet"):setFaction("Concord"):setCallSign("Test Victim"):setPosition(x + 30000, y)
    victim:orderIdle()
    RT.trackShipForReputation(victim)     -- the reputation penalty for a player kill
    local a0, b0 = T.rep("Concord", A), T.rep("Concord", B)
    local cbs = RT._kill_cbs[victim]
    T.check("kill: the ship is tracked", cbs ~= nil and #cbs >= 1)
    for _, cb in ipairs(cbs or {}) do cb(victim, B) end
    T.eq("kill: B's Concord standing -200", T.rep("Concord", B) - b0, -200)
    T.eq("kill: A's Concord standing unchanged", T.rep("Concord", A) - a0, 0)
    for _, cb in ipairs(cbs or {}) do cb(victim, A) end
    T.eq("kill: A pays for its own", T.rep("Concord", A) - a0, -200)
    local a1, b1 = T.rep("Concord", A), T.rep("Concord", B)
    for _, cb in ipairs(cbs or {}) do cb(victim, victim) end
    T.check("kill: an NPC's kill costs nobody", T.rep("Concord", A) == a1 and T.rep("Concord", B) == b1)
    victim:destroy()
end)

-- ── The kill penalty, from a registered ship's death by damage ───────────────
-- RT.register tracks every AI ship; a death the player ship caused costs that ship 200 standing
-- with the dead ship's faction at the time it died. Arc ships (ARC.register) are spared.
local kills = {}
local function spawnAt(dx, faction, name, register)
    local x, y = B:getPosition()
    local s = CpuShip():setTemplate("MT52 Hornet"):setFaction(faction):setPosition(x + 30000 + dx, y + 20000)
    s:orderIdle()
    register(s, name)
    return s
end
local function kill(s, by)
    for _ = 1, 3 do
        if RT.valid(s) then
            local x, y = s:getPosition()
            applyDamageToEntity(s, 1000, {instigator = by, type = "kinetic", x = x + 100, y = y})
        end
    end
end
local before
T.step("ships to destroy", function()
    kills.concord  = spawnAt(0,     "Concord",          "Kill Concord",  RT.register)
    kills.indep    = spawnAt(3000,  "Independent",      "Kill Indep",    RT.register)
    kills.flipped  = spawnAt(6000,  "Independent",      "Kill Flipped",  RT.register)
    kills.friendly = spawnAt(9000,  "Corsair Friendly", "Kill Friendly", RT.register)
    kills.relic    = spawnAt(12000, "Relic",            "Kill Relic",    RT.register)
    kills.arc      = spawnAt(15000, "Concord",          "Kill Arc",      ARC.register)
    kills.npc      = spawnAt(18000, "Concord",          "Kill NPC",      RT.register)
    kills.flipped:setFaction("Corsairs")   -- a job target that turned on the crew
    before = {}
    for _, f in ipairs({"Concord", "Independent", "Corsairs"}) do before[f] = {A = T.rep(f, A), B = T.rep(f, B)} end
    kill(kills.concord, B)
end)
T.wait(1)
T.step("a Concord ship", function()
    T.check("penalty: destroyed", not RT.valid(kills.concord))
    T.eq("penalty: B -200 Concord", T.rep("Concord", B) - before.Concord.B, -200)
    T.eq("penalty: A untouched", T.rep("Concord", A) - before.Concord.A, 0)
    kill(kills.indep, B)
    kill(kills.flipped, B)
end)
T.wait(1)
T.step("an Independent ship, and one that had turned Corsair", function()
    T.eq("penalty: B -200 Independent (the flipped one is not counted here)", T.rep("Independent", B) - before.Independent.B, -200)
    T.eq("penalty: B -200 Corsairs for the flipped one", T.rep("Corsairs", B) - before.Corsairs.B, -200)
    kill(kills.friendly, A)
end)
T.wait(1)
T.step("a friendly Corsair counts as Corsairs", function()
    T.eq("penalty: A -200 Corsairs", T.rep("Corsairs", A) - before.Corsairs.A, -200)
    before.now = {}
    for _, f in ipairs({"Concord", "Independent", "Corsairs"}) do before.now[f] = {A = T.rep(f, A), B = T.rep(f, B)} end
    kill(kills.relic, B)
    kill(kills.arc, B)
    kill(kills.npc, nil)
end)
T.wait(1)
T.step("no penalty for a Relic ship, an arc ship or an NPC's kill", function()
    T.check("none: all three destroyed", not RT.valid(kills.relic) and not RT.valid(kills.arc) and not RT.valid(kills.npc))
    for _, f in ipairs({"Concord", "Independent", "Corsairs"}) do
        T.eq("none: A's " .. f .. " unchanged", T.rep(f, A), before.now[f].A)
        T.eq("none: B's " .. f .. " unchanged", T.rep(f, B), before.now[f].B)
    end
end)

-- ── A donation is credited to the ship that gave ─────────────────────────────
local ind_a0, ind_b0
T.actAs(function() return B end)
T.dock("Saint Brennan's Mission")
T.step("note", function()
    a_c0, b_c0 = T.credits(A), T.credits(B)
    ind_a0, ind_b0 = T.rep("Independent", A), T.rep("Independent", B)
end)
T.talk("Saint Brennan's Mission", {"Donate $100"})
T.step("B donated", function()
    T.eq("donate: B paid 100", b_c0 - T.credits(B), 100)
    T.eq("donate: A paid nothing", T.credits(A), a_c0)
    T.eq("donate: B's standing +100", T.rep("Independent", B) - ind_b0, 100)
    T.eq("donate: A's standing unchanged", T.rep("Independent", A) - ind_a0, 0)
end)
T.actAs(nil)
T.closeComms()

-- ── Identity: the record follows the ship, not the name ──────────────────────
T.step("B is renamed in mid-session", function()
    local rec = RT.shipRecord(B)
    local credits = T.credits(B)
    B:setCallSign("Harrier")
    T.eq("rename: same record", RT.shipRecord(B), rec)
    T.eq("rename: balance kept", T.credits(B), credits)
    T.check("rename: upgrades kept", RT.hasUpgrade("shield_mk2", B))
    RT.saveCampaign()
    T.eq("rename: saved under the new name", rec.name, "Harrier")
    T.eq("rename: still one record for B", #RT.campaign.extra_ships, 1)
end)

-- ── Saved and found again ────────────────────────────────────────────────────
T.step("reload", function()
    local credits, rep = T.credits(B), T.rep("Independent", B)
    RT.campaign = fromJSON(toJSON(RT.campaign))
    T.eq("reload: B's credits", T.credits(B), credits)
    T.eq("reload: B's standing", T.rep("Independent", B), rep)
    T.check("reload: B's upgrades", RT.hasUpgrade("shield_mk2", B) and RT.hasUpgrade("forward_beams", B))
    T.check("reload: A's are still A's own", not RT.hasUpgrade("shield_mk2", A))
    T.eq("reload: A's record is the new campaign table", RT.shipRecord(A), RT.campaign)
end)

-- ── A ship that joins later is outfitted from its own record ─────────────────
local C
T.step("a third ship joins under a saved name", function()
    table.insert(RT.campaign.extra_ships, {name = "Osprey", credits = 321, reputation = {Concord = 77}, upgrades = {"hull_plating"}})
    local x, y = A:getPosition()
    local stock = A:getHullMax()   -- same template, and A has no hull upgrade
    C = RT.spawnPlayer(x + 8000, y, 0, {callsign = "Osprey"})
    C:setCanBeDestroyed(false)
    T.eq("join: its saved credits", T.credits(C), 321)
    T.eq("join: its saved standing", T.rep("Concord", C), 77)
    T.check("join: its saved upgrade", RT.hasUpgrade("hull_plating", C))
    T.eq("join: the upgrade is applied to its hull", C:getHullMax(), stock + 50)
    T.check("join: it did not get B's upgrades", not RT.hasUpgrade("shield_mk2", C))
end)
