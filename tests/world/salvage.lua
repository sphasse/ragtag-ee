-- Salvage clusters: debris fields of pods across the Drift. The starting set, what a pod pays
-- (to the ship that picks it up), the density and reward settings, top-up after collection, and
-- the salvage a scanned wreck gives up (to any ship near it, not only the primary ship).
--
-- Not covered: the ambient "lost crate" a passing freighter drops (it needs minutes of traffic).

T.suite("world")

local A, B, st
local pod

local function clusters() return st.clusters end
local function base() return #VERSE.SALVAGE end
local function want(density) return math.max(1, math.floor(base() * ({0.5, 1.0, 2.0})[density] + 0.5)) end
local function pods_of(cl)
    local n = 0
    for _, a in ipairs(cl.pods) do if RT.valid(a) then n = n + 1 end end
    return n
end
local function alive()
    local n = 0
    for _, cl in ipairs(clusters()) do if pods_of(cl) > 0 then n = n + 1 end end
    return n
end
local function check_now() st.next_check = 0 end
local _POD_NAMES = {["Cargo pod"] = true, ["Munitions crate"] = true, ["Hull patch kit"] = true, ["Encrypted data chip"] = true}
local function pods_near(x, y, r)
    local n = 0
    for _, o in ipairs(getObjectsInRadius(x, y, r)) do
        local ok, cs = pcall(function() return o:getCallSign() end)
        if ok and _POD_NAMES[cs] then n = n + 1 end
    end
    return n
end
-- A pod that pays credits ("Cargo pod"), from the cluster with the most pods.
local function cargo_pod()
    for _, cl in ipairs(clusters()) do
        for _, a in ipairs(cl.pods) do
            if RT.valid(a) and a:getCallSign() == "Cargo pod" then return a, cl end
        end
    end
    error("no cargo pod anywhere")
end

T.step("setup", function()
    A = T.P()
    st = T.world("salvage")
    T.check("setup: the plugin is running", WORLD.isEnabled("salvage") and st and st._initialized)
    T.eq("setup: Medium density", SALV.getDensity(), 2)
    T.eq("setup: Medium reward", SALV.getReward(), 2)
end)

-- ── The starting set ─────────────────────────────────────────────────────────
T.step("one cluster per universe salvage site", function()
    T.check("start: the universe defines salvage sites", base() > 0)
    T.eq("start: clusters", #clusters(), want(2))
    local empty, out_of_range = 0, 0
    for _, cl in ipairs(clusters()) do
        local n = pods_of(cl)
        if n == 0 then empty = empty + 1 end
        if n < 3 or n > 7 then out_of_range = out_of_range + 1 end
        if cl.tier < 0 or cl.tier > 3 then T.check("start: tier 0..3", false, cl.tier) end
    end
    T.eq("start: no empty cluster", empty, 0)
    T.eq("start: 3 to 7 pods each", out_of_range, 0)
end)

-- ── Picking up a pod pays the ship that flew into it ─────────────────────────
local a0, b0
T.step("a second ship flies into a cargo pod", function()
    B = T.secondShip()
    pod = cargo_pod()
    a0, b0 = T.credits(A), T.credits(B)
end)
T.actAs(function() return B end)
T.step("B on the pod", function() T.moveTo(pod:getPosition()) end)
T.waitFor("pickup: the pod is collected", function() return not RT.valid(pod) end, 8)
T.step("B is paid", function()
    local gain = T.credits(B) - b0
    T.check("pickup: B gains the pod's value", gain >= 5 and gain <= 20, gain)
    T.eq("pickup: A gains nothing", T.credits(A), a0)
end)
T.actAs(nil)

-- ── Top-up after collection ──────────────────────────────────────────────────
local n0
T.step("the count is taken", function() check_now() end)
T.wait(0.5)
T.step("four more pods are collected", function()
    n0 = #clusters()
    local gone = 0
    for _, cl in ipairs(clusters()) do          -- one from each of four clusters: none is emptied
        if gone < 4 and pods_of(cl) >= 2 then
            for _, a in ipairs(cl.pods) do
                if RT.valid(a) then a:destroy(); gone = gone + 1; break end
            end
        end
    end
    T.eq("top-up: four pods taken", gone, 4)
    check_now()
end)
T.waitFor("top-up: a new cluster appears somewhere", function() return #clusters() == n0 + 1 end, 3)
T.step("an emptied cluster is replaced", function()
    local cl = clusters()[1]
    for _, a in ipairs(cl.pods) do if RT.valid(a) then a:destroy() end end
    n0 = alive()
    check_now()
end)
T.waitFor("top-up: back to at least the target", function() return alive() >= want(2) and alive() >= n0 end, 3)

-- ── Settings ─────────────────────────────────────────────────────────────────
T.step("density Low", function() SALV.setDensity(1); check_now() end)
T.waitFor("density: culled to half", function() return alive() == want(1) end, 3)
T.step("density High", function() SALV.setDensity(3); check_now() end)
T.waitFor("density: grown to double", function() return alive() == want(3) end, 3)
local old_pod
T.step("reward High", function()
    old_pod = cargo_pod()
    SALV.setReward(3); check_now()
end)
T.waitFor("reward: every cluster is replaced", function() return not RT.valid(old_pod) end, 3)
T.step("with richer pods", function()
    T.eq("reward: the count is kept", alive(), want(3))
    B:setPosition(0, 0)
    pod = cargo_pod()
    b0 = T.credits(B)
    SALV.setReward(9)
    T.eq("reward: never above High", SALV.getReward(), 3)
end)
T.actAs(function() return B end)
T.step("B on a rich pod", function() T.moveTo(pod:getPosition()) end)
T.waitFor("reward: collected", function() return not RT.valid(pod) end, 8)
T.step("double pay", function()
    local gain = T.credits(B) - b0
    T.check("reward: a High pod pays 10 to 40", gain >= 10 and gain <= 40, gain)
end)
T.actAs(nil)

-- ── A scanned wreck gives up salvage ─────────────────────────────────────────
local wreck, pods_before
T.step("the primary ship scans a wreck", function()
    for _, w in ipairs(VERSE.wrecks) do
        if not w.looted and RT.valid(w.ship) then wreck = w; break end
    end
    T.check("wreck: the universe has wrecks", wreck ~= nil)
    local x, y = wreck.ship:getPosition()
    T.moveTo(x + 6000, y)
    pods_before = pods_near(x, y, 6000)
end)
T.wait(2.5)
T.step("not before it is scanned", function()
    T.check("wreck: nothing for flying past", not wreck.looted)
    wreck.ship:setScannedByFaction(A:getFaction(), true)
end)
T.waitFor("wreck: scanned and looted", function() return wreck.looted end, 4)
T.step("salvage around it", function()
    local x, y = wreck.ship:getPosition()
    T.check("wreck: pods appear around the wreck", pods_near(x, y, 6000) > pods_before)
end)

-- ── A wreck scanned near the second ship, the primary ship far away ──────────
local wreck2
T.step("the second ship scans a wreck", function()
    T.moveTo(VERSE.at("Port Vesper", 2, 2))
    for _, w in ipairs(VERSE.wrecks) do
        if not w.looted and RT.valid(w.ship) and RT.dist(A, w.ship) > 25000 then wreck2 = w; break end
    end
    T.check("wreck2: a wreck far from the primary ship", wreck2 ~= nil)
    local x, y = wreck2.ship:getPosition()
    B:setPosition(x + 6000, y)
    pcall(function() B:commandImpulse(0) end)
    pods_before = pods_near(x, y, 6000)
    wreck2.ship:setScannedByFaction(B:getFaction(), true)
end)
T.waitFor("wreck2: the second ship finds the salvage", function() return wreck2.looted end, 4)
T.step("salvage around the second wreck", function()
    local x, y = wreck2.ship:getPosition()
    T.check("wreck2: the primary ship was never near", RT.dist(A, wreck2.ship) > 15000)
    T.check("wreck2: pods appear around the wreck", pods_near(x, y, 6000) > pods_before)
end)

-- ── Off ──────────────────────────────────────────────────────────────────────
T.step("plugin off", function()
    local left = cargo_pod()
    WORLD.disable("salvage")
    T.eq("off: tracking is dropped", #st.clusters, 0)
    T.check("off: the pods stay in the world", RT.valid(left))
end)
