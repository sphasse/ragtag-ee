-- Credits: one balance per ship, kept in the ship's record (not EmptyEpsilon's per-faction
-- reputation points, which are held at 0), shown as a "Credits: N" line on Relay and Operations,
-- and saved with the campaign (other ships by callsign, with their standing). A = primary ship,
-- B = second ship. "Rejoining" is simulated by replacing the campaign table with a JSON round
-- trip of itself; a real restart of the game is not covered. Upgrades, kills and renames: see
-- tests/core/records.lua.

T.suite("jobs")

local A, B
local a0

-- The "Credits: N" line a ship shows on a station screen, or nil.
local function line(ship, key)
    local fns = ship.components.custom_ship_functions   -- the component is the array
    if not fns then return nil end
    for i = 1, #fns do
        if fns[i].name == key then return fns[i].caption end
    end
end
local function engine(ship) return ship:getReputationPoints() end

T.step("two ships", function()
    A = T.P()
    a0 = T.credits(A)
    T.check("start: the primary ship has its starting credits", a0 > 0, a0)
    T.eq("start: the engine's reputation number is not used", engine(A), 0)
    B = T.secondShip()
    T.eq("start: a new ship has 0 credits", T.credits(B), 0)
    T.eq("start: a ship joining leaves A's credits alone", T.credits(A), a0)
end)

-- ── Earning and spending ─────────────────────────────────────────────────────
T.step("earn and spend", function()
    RT.addCredits(120, "test", B)
    T.eq("earn: B +120", T.credits(B), 120)
    T.eq("earn: A unchanged", T.credits(A), a0)
    RT.addCredits(-50, "test", A)
    T.eq("spend: A -50", T.credits(A), a0 - 50)
    T.eq("spend: B unchanged", T.credits(B), 120)
    RT.addCredits(-1000, "test", B)
    T.eq("spend: a balance never goes below zero", T.credits(B), 0)
    RT.addCredits(75, "test", B)
    RT.addCredits(30, "test")
    T.eq("default ship: no ship given means the primary ship", T.credits(A), a0 - 20)
    T.eq("engine number still 0 after earning", engine(A), 0)
end)
T.step("each ship shows its own balance", function()
    T.eq("display: A on Relay", line(A, "rt_credits_relay"), "Credits: " .. (a0 - 20))
    T.eq("display: A on Operations", line(A, "rt_credits_ops"), "Credits: " .. (a0 - 20))
    T.eq("display: B on Relay", line(B, "rt_credits_relay"), "Credits: 75")
    T.eq("display: B on Operations", line(B, "rt_credits_ops"), "Credits: 75")
end)

-- ── The engine's shared number is held at zero ───────────────────────────────
T.step("something adds reputation points behind our back", function() A:addReputationPoints(500) end)
T.wait(0.5)
T.step("it is wiped and changes nobody's credits", function()
    T.eq("phantom: engine number back to 0", engine(A), 0)
    T.eq("phantom: A's credits unchanged", T.credits(A), a0 - 20)
    T.eq("phantom: B's credits unchanged", T.credits(B), 75)
end)

-- ── Buying at a station uses the ship's own balance ──────────────────────────
T.actAs(function() return B end)
T.dock("Port Vesper")
T.talk("Port Vesper", {})
T.step("the station quotes B's balance", function()
    T.check("station: greets B with B's balance", T.msg():find("Balance: 75 credits", 1, true) ~= nil, T.msg())
end)
T.actAs(nil)
T.closeComms()

-- ── Saved with the campaign ──────────────────────────────────────────────────
T.step("save", function()
    RT.addReputation("Independent", 40, "test", B)
    RT.saveCampaign()
    local rec = RT.shipRecord(B)
    T.eq("save: the primary ship's record is the campaign itself", RT.shipRecord(A), RT.campaign)
    T.eq("save: the primary ship's balance", RT.campaign.credits, a0 - 20)
    T.check("save: a record for B under its callsign", rec ~= nil and rec ~= RT.campaign and rec.name == B:getCallSign())
    T.eq("save: B's balance", rec and rec.credits, 75)
    T.eq("save: B's standing", rec and rec.reputation and rec.reputation.Independent, 40)
    -- What a reload does: the save survives a JSON round trip, and every ship finds its record
    -- again (the primary ship: the campaign; any other ship: by callsign).
    RT.campaign = fromJSON(toJSON(RT.campaign))
end)
T.wait(0.5)
T.step("both ships get theirs back", function()
    T.eq("reload: A's credits", T.credits(A), a0 - 20)
    T.eq("reload: B's credits, by callsign", T.credits(B), 75)
    T.eq("reload: B's standing, by callsign", T.rep("Independent", B), 40)
    T.eq("reload: display follows", line(B, "rt_credits_relay"), "Credits: 75")
    T.eq("reload: one record per ship, not a second copy", #RT.campaign.extra_ships, 1)
end)
