-- create_delivery: Push a rich delivery mission to a station's job board.
-- args: origin, dest, tier (0/1/2), reason_hint (optional cargo keyword)
--
-- Generates a full mission record via MISSION.newDelivery() — narrative lore,
-- appropriate reward, and a probabilistic route interception — and queues it
-- in MISSION._dynamic_queue.  The scenario's job board should check that queue
-- (see scenarios/sandbox/scenario_80_sandbox.lua JOBS.getOffers).
DIR.ACTIONS.create_delivery = function(a)
    local h = DIR._h
    local origin = h.str(a.origin, 40, nil)
    local dest   = h.str(a.dest,   40, nil)
    if not origin or origin == "" then return false, "origin required" end
    if not dest   or dest   == ""   then return false, "dest required" end

    local origin_e = RT.find(origin)
    local dest_e   = RT.find(dest)
    if not RT.valid(origin_e) then return false, "origin not found: " .. origin end
    if not RT.valid(dest_e)   then return false, "dest not found: "   .. dest   end

    local tier = math.floor(math.max(0, math.min(2, h.num(a.tier, 0, 2, 0))))
    local reason = h.str(a.reason_hint, 40, nil)
    if reason == "" then reason = nil end

    if MISSION == nil then return false, "MISSION module not loaded in this scenario" end

    local m = MISSION.newDelivery({
        origin      = origin,
        dest        = dest,
        tier        = tier,
        reason_hint = reason,
    })

    table.insert(MISSION._dynamic_queue, m)

    -- Notify all player ships via ship log
    RT.shipLog("[Board] New job posted at " .. origin .. ": " .. m.short
        .. " (" .. m.reward .. " cr).", "#A0C0FF")

    DIR.emit("delivery_posted", {
        origin  = origin,
        dest    = dest,
        cargo   = m.cargo,
        reward  = m.reward,
        tier    = tier,
        has_intercept = m.intercept ~= nil and 1 or 0,
    }, "normal")

    return true, string.format("delivery posted at %s → %s (%s, %d cr, tier %d)",
        origin, dest, m.cargo, m.reward, tier)
end
