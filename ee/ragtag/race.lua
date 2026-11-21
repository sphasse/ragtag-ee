-- ee/ragtag/race.lua
-- RACE: a timed money-making competition between player ships (The Short Haul).
--
-- Loaded by the scenario that runs it (like gm_console.lua), not by core. It keeps the clock, scores
-- every player ship and shows a live leaderboard as status lines on the consoles a short-handed
-- crew uses (Relay, Operations, Tactical, Engineering+, Single Pilot, the alt Relay): no pop-ups
-- until the end. When the clock runs out every ship gets the final standings as a pop-up, the
-- lines go away and the scenario carries on: the ships are on their own.
--
-- Score: net worth = credits + what the ship's upgrades cost (list price), so buying an upgrade
-- never costs a ship its place.
--
--   RACE.setup{minutes = 30}      before the start (the board stays shut: RACE.start opens it)
--   RACE.start()                  the clock runs
--   RACE.tick(now)                every frame (redraws once a second, ends the race at zero)
--   RACE.finish()                 the final standings now (GM "End the competition now")
--   RACE.standings()              {{ship, name, score}, ...}, best first
--   RACE.score(ship)              net worth

RACE = RACE or {}

-- Consoles that show the leaderboard: every one that combines roles for a small crew.
RACE.POSITIONS = {"relay", "operations", "tactical", "engineering+", "singlepilot", "altrelay"}
-- Every console of a ship, for the final pop-up.
RACE.ALL_POSITIONS = {"helms", "weapons", "engineering", "science", "relay", "tactical", "engineering+",
                      "operations", "singlepilot", "altrelay"}
RACE.TOP_N = 5
RACE.NAME = "The Short Haul"
RACE.state = nil

local _ORDER0 = 10   -- custom info order of the first line (the Credits line is 0)

-- 1234567 -> "1,234,567"
function RACE.fmt(n)
    local s = tostring(math.floor(n or 0))
    local neg = s:sub(1, 1) == "-"
    if neg then s = s:sub(2) end
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return (neg and "-" or "") .. out
end

local function _clock(t)
    t = math.max(0, math.ceil(t))
    return string.format("%d:%02d", t // 60, t % 60)
end

function RACE.setup(opts)
    opts = opts or {}
    RACE.state = {
        minutes  = opts.minutes or 30,
        started  = false,
        over     = false,
        ends     = nil,
        next_draw = 0,
        drawn    = {},     -- ship -> number of lines it shows now
    }
    if JOBS and JOBS.config then JOBS.config.jobboard_locked = true end   -- shut until the start
end

function RACE.score(ship)
    return (RT.credits(ship) or 0) + (RT.upgradeSpend(ship) or 0)
end

function RACE.standings()
    local out = {}
    for _, p in ipairs(RT.players or {}) do
        if RT.valid(p) then out[#out + 1] = {ship = p, name = p:getCallSign(), score = RACE.score(p)} end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    return out
end

function RACE.timeLeft(now)
    local s = RACE.state
    if not s then return 0 end
    if not s.started then return s.minutes * 60 end
    return math.max(0, s.ends - (now or getScenarioTime()))
end

local function _lineId(pos, i) return "race_" .. pos .. "_" .. i end

local function _clearLines(p)
    local s = RACE.state
    local n = (s and s.drawn[p]) or 0
    if not RT.valid(p) then return end
    for i = 1, math.max(n, RACE.TOP_N + 2) do
        for _, pos in ipairs(RACE.POSITIONS) do pcall(function() p:removeCustom(_lineId(pos, i)) end) end
    end
    if s then s.drawn[p] = 0 end
end

-- The lines one ship shows: the clock, the top RACE.TOP_N, and its own place if lower.
function RACE.linesFor(p, standings, now)
    local s = RACE.state
    local head
    if not s.started then
        head = string.format("%s: waiting for the start (%g min)", RACE.NAME, s.minutes)
    else
        head = string.format("%s: %s left", RACE.NAME, _clock(RACE.timeLeft(now)))
    end
    local lines = {head}
    local mine
    for i, e in ipairs(standings) do
        if e.ship == p then mine = i end
        if i <= RACE.TOP_N then
            lines[#lines + 1] = string.format("%d. %s  %s%s", i, e.name, RACE.fmt(e.score), e.ship == p and "  (you)" or "")
        end
    end
    if mine and mine > RACE.TOP_N then
        local e = standings[mine]
        lines[#lines + 1] = string.format("%d. %s  %s  (you)", mine, e.name, RACE.fmt(e.score))
    end
    return lines
end

function RACE.draw(now)
    local s = RACE.state
    if not s or s.over then return end
    local st = RACE.standings()
    for _, e in ipairs(st) do
        local p = e.ship
        local lines = RACE.linesFor(p, st, now)
        local before = s.drawn[p] or 0
        for i, text in ipairs(lines) do
            for _, pos in ipairs(RACE.POSITIONS) do
                pcall(function() p:addCustomInfo(pos, _lineId(pos, i), text, _ORDER0 + i) end)
            end
        end
        for i = #lines + 1, before do
            for _, pos in ipairs(RACE.POSITIONS) do pcall(function() p:removeCustom(_lineId(pos, i)) end) end
        end
        s.drawn[p] = #lines
    end
end

function RACE.start(now)
    local s = RACE.state
    if not s or s.started then return false end
    now = now or getScenarioTime()
    s.started, s.ends, s.next_draw = true, now + s.minutes * 60, 0
    if JOBS and JOBS.config then JOBS.config.jobboard_locked = false end
    for _, p in ipairs(RT.players or {}) do
        if RT.valid(p) then
            pcall(function() p:addToShipLog(string.format("%s: the clock is running. %g minutes. Make money.", RACE.NAME, s.minutes), "#E0C060") end)
        end
    end
    RT.emit("race_started", {minutes = s.minutes}, "high")
    RACE.draw(now)
    return true
end

-- The final standings, as text.
function RACE.resultText(standings)
    local lines = {RACE.NAME .. ": final standings (net worth: credits + upgrades)", ""}
    for i, e in ipairs(standings) do
        lines[#lines + 1] = string.format("%d. %s  %s", i, e.name, RACE.fmt(e.score))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "The competition is over. The Drift is still open: you're on your own."
    return table.concat(lines, "\n")
end

function RACE.finish()
    local s = RACE.state
    if not s or s.over then return nil end
    s.over = true
    local st = RACE.standings()
    local text = RACE.resultText(st)
    for _, p in ipairs(RT.players or {}) do
        if RT.valid(p) then
            _clearLines(p)
            for _, pos in ipairs(RACE.ALL_POSITIONS) do
                pcall(function() p:addCustomMessage(pos, "race_result_" .. pos, text) end)
            end
            pcall(function() p:addToShipLog(text, "#E0C060") end)
        end
    end
    pcall(addGMMessage, text)
    local results = {}
    for i, e in ipairs(st) do results[i] = {ship = e.name, score = e.score} end
    RT.emit("race_finished", {standings = results}, "high")
    return st
end

function RACE.tick(now)
    local s = RACE.state
    if not s or s.over then return end
    now = now or getScenarioTime()
    if s.started and now >= s.ends then RACE.finish(); return end
    if now >= s.next_draw then
        s.next_draw = now + 1
        RACE.draw(now)
    end
end
