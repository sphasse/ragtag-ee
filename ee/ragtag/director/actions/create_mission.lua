-- create_mission: Director creates a cargo/escort mission with staged events.
-- args: from_cs, to_cs, cargo, reward, intro, speaker,
--       event_1, event_1_speaker, event_2, event_2_speaker
--
-- Events fire when the player is 1/3 and 2/3 of the way to the destination.
-- Mission completes (and pays reward) when the player docks at to_cs.
-- DIR.updateMissions() is called every frame from DIR.update().

DIR.ACTIONS.create_mission = function(a)
    local h = DIR._h
    local from_cs = h.str(a.from_cs, 40, nil)
    local to_cs   = h.str(a.to_cs,   40, nil)
    if not from_cs or from_cs == "" then return false, "from_cs required" end
    if not to_cs   or to_cs   == "" then return false, "to_cs required" end
    local from_e = RT.find(from_cs)
    local to_e   = RT.find(to_cs)
    if not RT.valid(from_e) then return false, "from_cs not found: " .. from_cs end
    if not RT.valid(to_e)   then return false, "to_cs not found: "   .. to_cs   end

    local reward  = math.floor(h.num(a.reward, 50, 500, 120))
    local cargo   = h.str(a.cargo,   80,  "cargo")
    local intro   = h.str(a.intro,   400, nil)
    local speaker = h.str(a.speaker, 40,  from_cs)

    if intro and intro ~= "" then
        DIR.ACTIONS.say({speaker = speaker, text = intro})
    end

    local fx, fy = from_e:getPosition()
    local tx, ty = to_e:getPosition()
    local dx, dy = fx - tx, fy - ty
    local total_dist = math.sqrt(dx * dx + dy * dy)
    if total_dist < 1 then total_dist = 1 end

    local id = "dm_" .. math.floor(getScenarioTime() * 1000) .. "_" .. DIR.seq
    DIR.missions[id] = {
        from_cs       = from_cs,
        to_cs         = to_cs,
        cargo         = cargo,
        reward        = reward,
        total_dist    = total_dist,
        event_1       = h.str(a.event_1,         400, nil),
        event_1_spk   = h.str(a.event_1_speaker, 40,  from_cs),
        event_1_fired = false,
        event_2       = h.str(a.event_2,         400, nil),
        event_2_spk   = h.str(a.event_2_speaker, 40,  from_cs),
        event_2_fired = false,
        completed     = false,
    }

    DIR.emit("mission_created", {id=id, from=from_cs, to=to_cs, cargo=cargo, reward=reward}, "normal")
    return true, "mission " .. id .. ": " .. from_cs .. " -> " .. to_cs .. " (" .. cargo .. ", " .. reward .. " cr)"
end

-- Called every frame from DIR.update() to advance active missions.
function DIR.updateMissions()
    if not RT.anyPlayerAlive() then return end
    -- Use the nearest player for route-progress and dock checks.
    local ref = RT.nearestPlayer(0, 0)
    if not ref then return end
    local px, py = ref:getPosition()
    local to_remove = {}
    for id, m in pairs(DIR.missions) do
        if not m.completed then
            local to_e = RT.find(m.to_cs)
            if RT.valid(to_e) then
                local tx, ty = to_e:getPosition()
                local dx, dy = px - tx, py - ty
                local dist = math.sqrt(dx * dx + dy * dy)
                local frac = dist / m.total_dist

                -- 1/3 through the route: distance to dest <= 2/3 of total
                if not m.event_1_fired and m.event_1 and frac <= 0.67 then
                    m.event_1_fired = true
                    DIR.ACTIONS.say({speaker = m.event_1_spk, text = m.event_1})
                end

                -- 2/3 through the route: distance to dest <= 1/3 of total
                if not m.event_2_fired and m.event_2 and frac <= 0.33 then
                    m.event_2_fired = true
                    DIR.ACTIONS.say({speaker = m.event_2_spk, text = m.event_2})
                end

                -- Complete when any player docks at destination
                local completed_by = nil
                RT.forEachPlayer(function(p)
                    if not completed_by then
                        local docked = p:getDockedWith()
                        if docked and docked == to_e then completed_by = p end
                    end
                end)
                if completed_by then
                    m.completed = true
                    RT.addCredits(m.reward, "Mission: " .. m.to_cs)
                    RT.shipLog("[Mission complete] Delivered " .. m.cargo .. " to " .. m.to_cs ..
                        ". +" .. m.reward .. " cr.", "#80FF80")
                    DIR.emit("mission_complete", {
                        from=m.from_cs, to=m.to_cs, cargo=m.cargo, reward=m.reward
                    }, "normal")
                    table.insert(to_remove, id)
                end
            end
        end
    end
    for _, rid in ipairs(to_remove) do DIR.missions[rid] = nil end
end
