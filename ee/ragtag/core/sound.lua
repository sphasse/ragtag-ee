-- ee/ragtag/core/sound.lua
-- Sound cues (RT.sound, loops, the GM "Sounds..." menu).
-- Part of core (RT). Loaded by ee/ragtag/core.lua; do not require directly.

--------------------------------------------------------------------------------
-- Sound cues.
--
-- Server-side by default: EE's playSoundFile() plays ONLY on the server machine
-- (engine src/script.cpp:1408). That is the room-wide channel for a bridge whose
-- server has the speakers. It has no volume/pitch/stop, so cues are short files
-- and a queue keeps them from stacking.
--
-- Optional client-side positional cue (RT.sound_client_enabled): an entity with
-- an `sfx` component replicates to every client and plays once there. With a
-- position it is only heard on screens that render a 3D view (main screen),
-- relative to that screen's ship. Off by default: clients would need the file.
--
-- Cue files live in ee/ragtag/sfx/ (installed to scripts/ragtag/sfx/, which EE
-- resolves as "ragtag/sfx/<name>.wav"). Entries below point at files
-- as synthesized by tools/gen_sfx.py — see ee/ragtag/sfx/SOURCES.md.
--------------------------------------------------------------------------------

RT.sound_enabled        = true    -- GM toggle; silences every cue
RT.sound_client_enabled = false   -- also emit positional client cues (needs files on clients)

-- id -> {file, seconds}. `seconds` is the clip length, used for queue pacing.
RT.SOUNDS = {
    -- Concord patrol stop
    concord_hail      = {file = "ragtag/sfx/concord_hail.wav",    seconds = 3.4},
    concord_warning   = {file = "ragtag/sfx/concord_warning.wav", seconds = 0.5},
    concord_hostile   = {file = "ragtag/sfx/concord_hostile.wav", seconds = 1.8},
    -- Warp jammer (Concord stop and Boneyard)
    jammer_engage     = {file = "ragtag/sfx/jammer_engage.wav",   seconds = 3.1},
    jammer_bed        = {file = "ragtag/sfx/jammer_bed.wav",      seconds = 8.0},
    jammer_release    = {file = "ragtag/sfx/jammer_release.wav",  seconds = 1.5},
}

RT._sound_queue      = {}   -- pending {id, opts}
RT._sound_busy_until = 0    -- scenario time the current cue ends
RT._sound_loops      = {}   -- name -> {id, interval, next_at, alive}

local function _soundPlayNow(entry, opts)
    local ok, err = pcall(playSoundFile, entry.file)
    if not ok then log("[RT] sound '" .. entry.file .. "' failed: " .. tostring(err)) end
    RT._sound_busy_until = getScenarioTime() + (entry.seconds or 2)
    if RT.sound_client_enabled and opts.x and opts.y then
        pcall(function()
            local e = createEntity()
            e.components = {
                transform = {},
                sfx = {sound = entry.file, volume = opts.volume or 100, pitch = opts.pitch or 1.0},
            }
            e:setPosition(opts.x, opts.y)
            -- Late-joining clients receive every live sfx entity; drop it once played.
            RT.after(5, function() if e:isValid() then e:destroy() end end, "sfx_cleanup")
        end)
    end
end

-- Play a cue by id. opts: {now=true (skip the queue), skip_if_busy=true (drop
-- instead of queueing), x, y (positional client cue), volume, pitch}.
function RT.sound(id, opts)
    if not RT.sound_enabled then return false end
    opts = opts or {}
    local entry = RT.SOUNDS[id]
    if entry == nil then log("[RT] unknown sound cue: " .. tostring(id)); return false end
    local now = getScenarioTime()
    if opts.now or now >= RT._sound_busy_until then
        _soundPlayNow(entry, opts)
        return true
    end
    if opts.skip_if_busy then return false end
    for _, q in ipairs(RT._sound_queue) do
        if q.id == id then return false end   -- already queued; don't stack repeats
    end
    table.insert(RT._sound_queue, {id = id, opts = opts})
    return true
end

-- Re-fire a cue every `interval` seconds while alive() (optional) returns true.
-- Loop cues never queue: if something else is playing, that beat is skipped.
function RT.soundLoop(name, id, interval, alive)
    RT._sound_loops[name] = {id = id, interval = interval, next_at = 0, alive = alive}
end

function RT.stopSoundLoop(name)
    RT._sound_loops[name] = nil
end

function RT.updateSounds()
    local now = getScenarioTime()
    for name, loop in pairs(RT._sound_loops) do
        if loop.alive and not loop.alive() then
            RT._sound_loops[name] = nil
        elseif now >= loop.next_at then
            loop.next_at = now + loop.interval
            RT.sound(loop.id, {skip_if_busy = true})
        end
    end
    if #RT._sound_queue > 0 and now >= RT._sound_busy_until then
        local q = table.remove(RT._sound_queue, 1)
        local entry = RT.SOUNDS[q.id]
        if entry then _soundPlayNow(entry, q.opts) end
    end
end

-- GM submenu: enable/disable toggle, then one test button per cue in RT.SOUNDS
-- (played immediately on the server). Tests work even while cues are disabled.
function RT.showSoundMenu()
    clearGMFunctions()
    addGMFunction("← Back to Main", function()
        clearGMFunctions()
        -- A scenario's addSessionGMFunctions builds the whole main menu (campaign buttons included).
        if addSessionGMFunctions then addSessionGMFunctions() else RT.addCampaignGMFunctions() end
    end)
    addGMFunction("Sound cues: " .. (RT.sound_enabled and "ON" or "OFF"), function()
        RT.sound_enabled = not RT.sound_enabled
        if not RT.sound_enabled then
            RT._sound_queue = {}
            RT._sound_loops = {}
        end
        RT.showSoundMenu()  -- redraw so the label shows the new state
    end)
    local ids = {}
    for id in pairs(RT.SOUNDS) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local entry = RT.SOUNDS[id]
        addGMFunction(string.format("%s (%.1fs)", id, entry.seconds or 0), function()
            local ok, err = pcall(playSoundFile, entry.file)
            if not ok then
                addGMMessage("Could not play " .. entry.file .. ": " .. tostring(err))
            end
            RT._sound_busy_until = getScenarioTime() + (entry.seconds or 2)
        end)
    end
end
