-- ee/ragtag/world/rumors.lua
-- Unified rumors system: background lore pool + injectable high-priority rumors.
--
-- Background pool (priority 1): 100 strings, cycle through all before repeating.
--   Subject to per-source cooldown (RUMORS.COOLDOWN_SECONDS).
--
-- Injected rumors (priority 2-10): added by missions/plugins via RUMORS.add().
--   Priority >= 2 bypasses the cooldown so quest hooks always cut through.
--   Persist until explicitly removed with RUMORS.remove() or RUMORS.removeCategory().
--
-- API:
--   RUMORS.add({text, priority, faction, category})  -- returns assigned id
--   RUMORS.remove(id)                                -- remove one rumor
--   RUMORS.removeCategory(category)                  -- remove all in a category
--   RUMORS.get(callsign, source_faction)             -- call from comms handlers

RUMORS = RUMORS or {}

-- ─── Background pool ──────────────────────────────────────────────────────────

RUMORS.pool = {
    -- General trade & economy (20)
    "Fuel hauler rates are up 15% this quarter. Someone's squeezing the margins.",
    "Port Vesper's been turning away ore shipments. Storage is full and prices are tanking.",
    "Heard Lumen Exchange is buying hull plating at double rate. Military contract, maybe.",
    "Freighters are running empty from Kestrel to the Core. Nothing worth hauling back.",
    "Word is the Concord put a tariff on Rim grain. Border stations aren't happy.",
    "Salvage prices dropped hard after that Boneyard find last month. Market's flooded.",
    "Equipment haulers can't keep missile stocks. Somebody's buying them all up.",
    "Calder's Reach hit a new vein. Nickel's cheap if you can haul it.",
    "Independent crews are blacklisting Greywater Depot. Something about short pay.",
    "Hob's Landing is offering bounties on old nav data. Charting the Deep Shroud, I think.",
    "Lastchance Outpost is rationing water. Their recyclers are shot and nobody's fixing them.",
    "Concord fleet's buying up all the titanium they can find. Building something big.",
    "Freight rates to Saint Brennan's are through the roof. Somebody needs supplies bad.",
    "Heard a prospector found something valuable in the Gauntlet. Keeping it quiet though.",
    "Border stations are stockpiling food. They know something we don't.",
    "Luxury goods are moving slow. Rich folk on Lumen are tightening their belts.",
    "Fuel prices spiked after that hauler went missing near Blackwater. Insurance costs.",
    "Old-timer said platinum's been cheap for months. Somebody's dumping reserves.",
    "Medical shipments to the Rim are delayed. Concord says it's a paperwork issue.",
    "Freighter captains are refusing Boneyard runs. Too many ships not coming back.",

    -- Corsairs & piracy (15)
    "Corsairs hit three freighters in the Gauntlet this week. They're getting bolder.",
    "Grinning Teeth crew is laying low. Someone hurt them bad.",
    "Blackwater Reach defenses got upgraded. New minefields, tighter patrols.",
    "Heard Corsairs are recruiting. Offering good pay for anyone who can fly and shoot.",
    "Patrol captain said Corsair activity is down in the Gauntlet. Suspicious if you ask me.",
    "Freighter captain swears he paid off a Corsair raider and they let him go. Smart or lucky?",
    "Corsairs are hitting ore haulers, not passenger ships. They know where the money is.",
    "Someone's arming the Corsairs with military-grade weapons. Where's that coming from?",
    "Blackwater station changed callsigns last month. Concord lost track of them for a week.",
    "Heard a Corsair crew got wiped by Relic drones. They're not invincible.",
    "Independent crew took out a Corsair scout near Halcyon. Didn't even get a bounty.",
    "Corsairs are moving shipments through the Deep Shroud. Nobody can track them in there.",
    "Border patrol says Corsair raids are coordinated. Somebody's planning them.",
    "Concord put a 500-credit bounty on a Corsair lieutenant. Must've done something big.",
    "Rumor is the Corsairs lost a capital ship. Nobody knows how or where.",

    -- Settlement War & Boneyard (10)
    "Boneyard drones are active again. Something woke them up.",
    "Salvager found a Concord War frigate intact in the Boneyard. Hull's worth a fortune.",
    "Old vet said the Settlement War peace treaty was a sham. Concord just won by attrition.",
    "Ashgrave is still radioactive. Somebody dropped a nuke during the war and nobody talks about it.",
    "Free Ship captains still hold grudges against Concord. War's been over twenty years but they remember.",
    "Relic drones don't attack Hollow ships. Makes you wonder what the Hollow are.",
    "Boneyard wreck yielded a war-era data chip. Concord confiscated it fast.",
    "Someone's mining the Boneyard for military tech. Concord turned a blind eye.",
    "Settlement War veteran drinks at Hob's Landing every night. Says the real story never got told.",
    "Freighter captain found a memorial beacon in the Boneyard. Still broadcasting names of the dead.",

    -- The Shroud & mysteries (12)
    "Ship went into the Deep Shroud three weeks ago. No distress call, no wreckage. Just gone.",
    "Sensors go haywire near the rift. One captain swears his long-range picked up something big on the other side.",
    "Halcyon Rest gets strange visitors. Ships with no transponder, crews that don't talk.",
    "Heard there's a derelict station in the Shroud. Nobody knows who built it.",
    "Independent crew reported seeing lights in the Deep Shroud. Concord said it was instrument error.",
    "Wren's Folly is still out there. Some say the crew abandoned ship, others say they never left.",
    "Signal buoy near the Shroud rift went silent. Maintenance crew won't go near it.",
    "Old charts show a station in the Deep Shroud that isn't there anymore. Nobody knows what happened.",
    "Spacer legend says the Shroud hides a settlement. No proof, just stories.",
    "Navigation hazard warnings for the Shroud doubled this year. Space doesn't change that fast.",
    "Someone's dropping relay buoys in the Deep Shroud. Concord or something else?",
    "Freighter picked up a distress call from the Shroud. By the time they got there, nothing.",

    -- Concord & law (13)
    "Concord patrol checkpoints doubled this month. Looking for someone specific.",
    "Station dockmaster got audited by Concord. They went through twenty years of logs.",
    "Concord's hiring border patrol crews. Good pay but they make you sign a gag order.",
    "Heard Concord Fleet Yard is running three shifts. They're building something and it's not commercial.",
    "Inspector from Lumen showed up unannounced at Port Vesper. Asked a lot of questions, left fast.",
    "Concord crew turned on each other near Waypoint Galen. One's in custody, the other's missing.",
    "Magistrate on Lumen stepped down. Resignation letter was three sentences. Nobody's talking.",
    "Concord put out a wanted notice then pulled it back an hour later. Clerical error, they said.",
    "Someone leaked Concord patrol routes to the independent net. Routes changed overnight.",
    "Heard a logistics officer went AWOL from Sentinel Fleet Yard. Concord's keeping it quiet.",
    "Concord's restricting access to some shipping records. Said it's a security matter.",
    "Station comms picked up encrypted Concord traffic. More than usual, and they're nervous.",
    "Patrol stopped a freighter for a random inspection and tore the hold apart. Found nothing, left without apologizing.",

    -- Hollow & the Maw (8)
    "Captain tried to scan a Hollow ship. His systems crashed and stayed offline for a week.",
    "Hollow don't hail, don't trade, don't explain. But they haven't attacked anyone in months. Why?",
    "Maw expeditions have a 90% loss rate. The ones who come back don't talk about it.",
    "Old deep-space probe sent back data from the Maw before it died. Concord classified it immediately.",
    "Hollow ships don't show up on some sensors. Like they're not made of normal matter.",
    "Defense platform near the Maw fired on a Hollow ship and the shots just... stopped. Didn't explode, didn't hit. Stopped.",
    "Legend says the Pale Sun isn't a sun at all. Nobody's gotten close enough to prove it.",
    "Freighter captain saw a Hollow ship dissolve into light near the Maw. He quit flying the next day.",

    -- Stations & local gossip (12)
    "Dockmaster at Port Vesper knows everyone's cargo manifest. Don't try to lie to him.",
    "Halcyon Rest shipwright can work miracles if you pay cash. Heard he used to work Concord military.",
    "Hob's Landing bar has the best food in the Rim. Cook won't say where he gets the spices.",
    "Saint Brennan's Mission takes anyone in, no questions. Even Corsairs, if they're hurt bad.",
    "Greywater Depot's automated defenses glitched and shot at a friendly last month. Nobody's fixed them yet.",
    "Calder's Reach miners are tough as nails but fair. Cross them and you're blacklisted for life.",
    "Dustmote Salvage Yard has parts for ships I didn't know existed. Junk or stolen? You decide.",
    "Lastchance Outpost lives up to its name. If you can't buy it there, you're not finding it.",
    "Port Vesper gets ships from outside the Drift sometimes. Different engine signatures. Nobody asks where from.",
    "Lumen Exchange dockmaster is an AI. Freaks people out but the turnaround's fast.",
    "Sentinel Fleet Yard used to build warships. Now they retrofit freighters. Times change.",
    "Waypoint Galen has the longest bar in the Drift. Crew from six stations drink there.",

}

-- ─── Injected rumors ──────────────────────────────────────────────────────────

RUMORS._injected = RUMORS._injected or {}
RUMORS._next_id  = RUMORS._next_id  or 1

function RUMORS.add(r)
    local id = r.id or ("rumor_" .. RUMORS._next_id)
    RUMORS._next_id = RUMORS._next_id + 1
    RUMORS._injected[#RUMORS._injected + 1] = {
        id       = id,
        text     = r.text,
        priority = r.priority or 1,
        faction  = r.faction,   -- nil = any source faction
        category = r.category,  -- nil = uncategorized; use e.g. "START_WITNESS_MISSION"
    }
    return id
end

function RUMORS.remove(id)
    for i = #RUMORS._injected, 1, -1 do
        if RUMORS._injected[i].id == id then
            table.remove(RUMORS._injected, i)
            return true
        end
    end
    return false
end

-- Remove all injected rumors with the given category.
-- Missions call this once the player has acted on the hook.
function RUMORS.removeCategory(category)
    for i = #RUMORS._injected, 1, -1 do
        if RUMORS._injected[i].category == category then
            table.remove(RUMORS._injected, i)
        end
    end
end

-- ─── Background pool cycling ──────────────────────────────────────────────────

local function _shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

if not RUMORS._shuffled then
    _shuffle(RUMORS.pool)
    RUMORS._shuffled = true
    RUMORS._index    = 1
end

local function _nextBackground()
    local text = RUMORS.pool[RUMORS._index]
    RUMORS._index = RUMORS._index + 1
    if RUMORS._index > #RUMORS.pool then
        RUMORS._index = 1
        _shuffle(RUMORS.pool)
    end
    return text
end

-- ─── Cooldown (background only) ───────────────────────────────────────────────

RUMORS._cooldowns      = RUMORS._cooldowns or {}
RUMORS.COOLDOWN_SECONDS = 300  -- 5 minutes between background rumors per source

RUMORS.no_news = {
    "Nothing new since you asked last time.",
    "Same stories making the rounds. Check back later.",
    "Haven't heard anything fresh. Give it a few minutes.",
    "You already got the latest. News doesn't travel that fast out here.",
    "Asked around. Nobody's talking right now.",
    "Rumor mill's gone quiet for the moment.",
    "Give the gossip a chance to catch up, friend.",
    "You've heard everything I've heard. For now.",
    "Word travels slow in the Drift. Try again in a bit.",
    "Nothing worth repeating at the moment.",
    "Same old stories. Come back after you've flown a leg or two.",
    "Fresh out of news. Check the net if you're bored.",
    "Crew's been quiet on the comms. Give it time.",
    "Haven't picked up anything new on the long-range.",
    "I don't get paid enough to make stuff up.",
    "All the good rumours are in other people's inboxes right now.",
    "Ask me again after the next freighter docks.",
    "Nothing I haven't already told you.",
    "News is slow today. Must be a quiet sector.",
    "The rumour you just heard is still the rumour.",
    "Folks are keeping their mouths shut at the moment.",
    "Give the scuttlebutt time to percolate.",
    "That's all the gossip budget for now.",
    "Same chatter as five minutes ago.",
    "Nobody's hailing with anything interesting yet.",
    "I'm not a news service. Check back later.",
    "If I hear something, you'll be the first to know. Eventually.",
    "Silence on the feeds. Unusual, but there it is.",
    "My sources are taking a coffee break.",
    "You're pushy. No new news.",
    "Asked the dock crew. They shrugged.",
    "Everyone's talking about what you already heard.",
    "Nothing's changed since last you asked.",
    "This isn't a subscription service, friend.",
    "Try the bar. Maybe someone there knows something I don't.",
    "When something interesting happens, I'll let you know.",
    "The galaxy didn't get more interesting in the last few minutes.",
    "Rumour velocity is low right now. Physics.",
    "Check back after the shift change.",
    "I can't manufacture gossip on demand.",
    "Whatever you heard last time is still current.",
    "Give the transponder chatter time to catch up.",
    "Not much moves faster than light. News included.",
    "Heard nothing new. Space is big and news is slow.",
    "Still chewing on the last batch of rumours.",
    "Same story, different minute.",
    "I'd tell you if I knew something. I don't.",
    "The well's dry for now. Check back later.",
    "Nobody's said anything worth repeating since you last asked.",
    "Patience. Good intel takes time.",
}

-- ─── Main entry point ─────────────────────────────────────────────────────────

-- Returns a rumor string for a comms source.
--   callsign     : player ship callsign (used for cooldown tracking)
--   source_faction: faction of the NPC being hailed (nil = any)
--
-- Priority >= 2 rumors bypass the cooldown so quest hooks always cut through.
-- Background cycling (priority 1) is subject to the per-source cooldown.
function RUMORS.get(callsign, source_faction)
    if WORLD and not WORLD.isEnabled("rumors") then return nil end
    -- Collect injected rumors matching the source faction, priority >= 2
    local high = {}
    for _, r in ipairs(RUMORS._injected) do
        if r.priority >= 2 then
            if r.faction == nil or r.faction == source_faction then
                high[#high + 1] = r
            end
        end
    end

    if #high > 0 then
        -- Pick from the highest priority tier available
        local best = 0
        for _, r in ipairs(high) do
            if r.priority > best then best = r.priority end
        end
        local tier = {}
        for _, r in ipairs(high) do
            if r.priority == best then tier[#tier + 1] = r end
        end
        local chosen = tier[math.random(#tier)]
        if chosen.once then RUMORS.remove(chosen.id) end
        return chosen.text
    end

    -- Fall through to background pool with cooldown
    local now  = getScenarioTime and getScenarioTime() or 0
    local last = RUMORS._cooldowns[callsign]
    if last and (now - last) < RUMORS.COOLDOWN_SECONDS then
        return RUMORS.no_news[math.random(#RUMORS.no_news)]
    end
    RUMORS._cooldowns[callsign] = now
    return _nextBackground()
end

-- ─── WORLD plugin ─────────────────────────────────────────────────────────────

local _P = {}
_P.id      = "rumors"
_P.name    = "Rumors"
_P.defaults = {}

function _P.gmMenu(addButton, showSelf)
    local on = WORLD.isEnabled("rumors")
    addButton("Rumors: " .. (on and "ON" or "OFF"), function()
        if on then WORLD.disable("rumors") else WORLD.enable("rumors") end
        showSelf()
    end)
    addButton("Clear injected", function()
        RUMORS._injected = {}
        showSelf()
    end)
end

function _P.init(state)
    -- Merge rumors declared in verse data (via VERSE.extend) into the pool.
    if VERSE and VERSE.RUMORS then
        for _, text in ipairs(VERSE.RUMORS) do
            if type(text) == "string" and text ~= "" then
                table.insert(RUMORS.pool, text)
            end
        end
        RUMORS._shuffled = false  -- trigger re-shuffle to include new entries
    end
end
function _P.update(state, delta, now) end
function _P.cleanup(state)
    RUMORS._injected = {}
end

WORLD.register(_P)
