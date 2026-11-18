-- Losing the primary ship while another flies on. The story arcs and the campaign record belong
-- to the primary ship (RT.players[1]); when it is destroyed the session goes on and the arcs
-- wait. A rebuilt freighter is given the campaign's ship name first and becomes the primary
-- again, with the campaign's credits, standing and upgrades; so does a ship renamed to it. A
-- ship that joins while there are dead ships in the list still gets a roster name. Losing a ship
-- costs that ship's record half its credits (RT.DEATH_PENALTY), once, and the rebuilt ship is
-- told what it cost. A = the primary ship, B = a second ship, N = the rebuilt ship.
--
-- Not covered: the "Create player ship" screen itself (the test makes a PlayerSpaceship from
-- script, which fires the same onNewPlayerShip callback) and an arc actually resuming (the test
-- checks ARC.player(), which is all the arcs read).

T.suite("core")

local A, B, N, C
local NAME
local hull0
local lost = {}
RT.on(function(ev) if ev.type == "ship_lost" then lost[#lost + 1] = ev.data end end)

-- A ship made the way the "Create player ship" screen makes one: the scenario's
-- onNewPlayerShip names it, places it and adopts it.
local function newFreighter()
    return PlayerSpaceship():setTemplate("Light Freighter")
end
local function index(ship)
    for i, p in ipairs(RT.players) do if p == ship then return i end end
end

T.step("the primary ship's record", function()
    A = T.P()
    local list = getSpawnablePlayerShips()
    T.eq("list: the Light Freighter is first in the ship-creation list", list[1] and list[1][2], "Light Freighter")
    NAME = RT.campaign.ship_name
    T.eq("setup: the primary ship carries the campaign's name", A:getCallSign(), NAME)
    RT.setCredits(1234, A)
    RT.addReputation("Concord", 250 - T.rep("Concord", A), "test", A)
    RT.grantUpgrade("hull_plating", "test", A)
    hull0 = A:getHullMax()
    B = T.secondShip()
    RT.setCredits(40, B)
end)

T.step("the primary ship is destroyed", function() A:destroy() end)
T.wait(1)
T.step("the arcs wait, the session goes on", function()
    T.check("lost: no arc ship", ARC.player() == nil)
    T.check("lost: the second ship flies on", RT.valid(B) and RT.anyPlayerAlive())
    T.eq("lost: the second ship is not promoted", index(B), 2)
    T.eq("lost: the second ship keeps its own balance", T.credits(B), 40)
    T.eq("lost: half the campaign's credits gone", RT.campaign.credits, 617)
    T.eq("lost: reported once", #lost, 1)
    T.eq("lost: reported for the primary ship", lost[1] and lost[1].ship, NAME)
    T.check("lost: marked as the primary ship's", lost[1] and lost[1].primary == true)
    T.eq("lost: with what it cost", lost[1] and lost[1].credits_lost, 617)
    T.eq("lost: waiting to be told", RT.campaign.loss_note, 617)
end)
T.wait(1)
T.step("charged only once", function() T.eq("lost: still once", #lost, 1); T.eq("lost: balance unchanged", RT.campaign.credits, 617) end)

T.step("a new freighter joins", function() N = newFreighter() end)
T.wait(1)
T.step("it is the primary ship again", function()
    T.eq("rebuilt: given the campaign's ship name", N:getCallSign(), NAME)
    T.check("rebuilt: first in the list", RT.players[1] == N)
    T.check("rebuilt: RT.player follows", RT.player == N)
    T.check("rebuilt: the arcs have their ship", ARC.player() == N)
    T.check("rebuilt: its record is the campaign", RT.shipRecord(N) == RT.campaign)
    T.eq("rebuilt: the campaign's credits, after the loss", T.credits(N), 617)
    T.check("rebuilt: the crew has been told what the loss cost", RT.campaign.loss_note == nil)
    T.eq("rebuilt: the campaign's standing", T.rep("Concord", N), 250)
    T.check("rebuilt: the campaign's upgrades", RT.hasUpgrade("hull_plating", N))
    T.eq("rebuilt: and they are fitted", N:getHullMax(), hull0)
    local stray = 0
    for _, e in ipairs(RT.campaign.extra_ships or {}) do
        if e.name == NAME then stray = stray + 1 end
    end
    T.eq("rebuilt: no second record under the campaign's name", stray, 0)
    T.eq("rebuilt: the second ship is still second", index(B), 2)
    T.eq("rebuilt: the second ship keeps its balance", T.credits(B), 40)
end)

-- ── A ship joins while a dead ship is still in the list ──────────────────────
T.step("the second ship is destroyed, then another freighter joins", function()
    B:destroy()
end)
T.wait(1)
T.step("join", function() C = newFreighter() end)
T.wait(1)
T.step("it gets a roster name", function()
    T.eq("second lost: reported", #lost, 2)
    T.eq("second lost: half of its own 40", lost[2] and lost[2].credits_lost, 20)
    T.check("second lost: not the primary ship's", lost[2] and lost[2].primary == false)
    T.eq("second lost: the campaign untouched", RT.campaign.credits, 617)
    T.check("join: registered", index(C) ~= nil)
    T.check("join: not the primary's name", C:getCallSign() ~= NAME, C:getCallSign())
    T.check("join: the primary is unchanged", RT.players[1] == N)
end)

-- ── A ship renamed to the lost primary's name takes its place ────────────────
T.step("the primary ship is lost again", function() N:destroy() end)
T.wait(1)
T.step("no arc ship", function() T.check("again: no arc ship", ARC.player() == nil) end)
T.step("the GM renames the remaining ship", function() C:setCallSign(NAME) end)
T.wait(1)
T.step("it is the primary ship", function()
    T.check("rename: first in the list", RT.players[1] == C)
    T.check("rename: the arcs have their ship", ARC.player() == C)
    T.eq("rename: the campaign's credits, halved again", T.credits(C), 309)
    T.check("rename: the campaign's upgrades", RT.hasUpgrade("hull_plating", C))
end)
