-- ee/ragtag/voice.lua
-- RT.voice: invisible NPC voices that can hail the crew and hold a branching conversation.
--
-- A voice is a position-less Artifact: it has no transform, so it never appears on radar, yet it
-- can hail a player ship (verified headless; the stock Omicron scenario does the same). Use it
-- for a voice with no ship: survivors, Concord command, a beacon broadcast, a ghost signal,
-- Rezkov or Kael reaching the crew anywhere in the verse.
--
--   RT.voice.create(id, {
--       name = "Lifeboat Survivors",       -- callsign shown on the hail
--       ttl  = 300,                        -- optional: auto-destroy after N seconds
--       tree = <node>,                     -- what the crew sees when they answer the hail
--   })
--   RT.voice.hail(id, "incoming text")     -- hail the crew (ship-log fallback if comms are busy)
--   RT.voice.log(id, "text")               -- just write "[name] text" to the ship log
--   RT.voice.destroy(id) / RT.voice.get(id) / RT.voice.exists(id)
--
-- A conversation node:
--   {
--     text     = "string" | function() return "string" end,
--     on_enter = function() end,                        -- optional, runs each time the node shows
--     replies  = {
--        { label = "Tell me more.",                     -- button text
--          next  = <node> | function() return <node> end,   -- go to another node, or...
--          say   = "closing text",                      -- ...end here showing this text
--          on    = function() end,                      -- side effect (flags, jobs, rep)
--          when  = function() return true end,          -- optional: only show when true
--          once  = true },                              -- optional: only offer one time
--     },
--   }
-- Nodes may refer to each other (including back to the root) to build loops.
-- Every reply ends in a node or a `say`; EE needs every reply callback to set a message.

RT = RT or {}
RT.voice = RT.voice or {}
RT._voices = RT._voices or {}   -- id -> {entity, name}

local function _render(node)
    if node.on_enter then pcall(node.on_enter, node) end
    local text = node.text
    if type(text) == "function" then
        local ok, res = pcall(text)
        text = ok and res or "..."
    end
    setCommsMessage(tostring(text or "..."))
    for _, r in ipairs(node.replies or {}) do
        local show = true
        if r.when then
            local ok, res = pcall(r.when)
            show = ok and res and true or false
        end
        if r.once and r._used then show = false end
        if show then
            local reply = r
            addCommsReply(reply.label, function()
                if reply.once then reply._used = true end
                if reply.on then
                    local ok, err = pcall(reply.on)
                    if not ok then log("[VOICE] reply handler error: " .. tostring(err)) end
                end
                local nxt = reply.next
                if type(nxt) == "function" then
                    local ok, res = pcall(nxt)
                    nxt = ok and res or nil
                end
                if nxt then
                    _render(nxt)
                else
                    setCommsMessage(reply.say or "The channel closes.")
                end
            end)
        end
    end
end

function RT.voice.exists(id)
    local v = RT._voices[id]
    return v ~= nil and RT.valid(v.entity)
end

function RT.voice.get(id)
    local v = RT._voices[id]
    return v and v.entity or nil
end

function RT.voice.destroy(id)
    local v = RT._voices[id]
    if not v then return end
    RT._voices[id] = nil
    RT.cancelTimer("voice_ttl_" .. id)
    RT.cancelTimer("voice_retry_" .. id)
    if RT.valid(v.entity) then pcall(function() v.entity:destroy() end) end
end

function RT.voice.create(id, def)
    assert(id and def and def.tree, "RT.voice.create needs an id and a tree")
    RT.voice.destroy(id)   -- idempotent re-create
    local name = def.name or id
    local tree = def.tree
    local e = Artifact():setCallSign(name):setCommsScript(""):setCommsFunction(function()
        _render(tree)
    end)
    RT._voices[id] = {entity = e, name = name}
    if def.ttl then
        RT.after(def.ttl, function() RT.voice.destroy(id) end, "voice_ttl_" .. id)
    end
    return e
end

-- Hail the crew from the voice. If comms are busy, retry once, then fall back to the ship log.
function RT.voice.hail(id, text, opts)
    local v = RT._voices[id]
    if not v or not RT.valid(v.entity) then return false end
    opts = opts or {}
    if RT.hail(v.entity, text, v.name) then return true end
    RT.after(opts.retry_after or 15, function()
        local v2 = RT._voices[id]
        if v2 and RT.valid(v2.entity) and RT.hail(v2.entity, text, v2.name) then return end
        RT.shipLog("[" .. v.name .. "] " .. text, "#C0E0FF")
    end, "voice_retry_" .. id)
    return false
end

function RT.voice.log(id, text)
    local v = RT._voices[id]
    RT.shipLog("[" .. (v and v.name or id) .. "] " .. text, "#C0E0FF")
end
