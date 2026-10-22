# Sandbox Campaign - GM Guide

## Quick Start

1. **Install**: `python tools/install.py --ee <EmptyEpsilon folder>`
2. **Start EmptyEpsilon server** (with `httpserver=8080` in options.ini)
3. **Select scenario**: "Sandbox: Open Play"
4. **Optional**: Start AI director on GPU PC: `cd director && python main.py`
5. **Crew connects** to their stations

## Scenario Settings

### Campaign
- **Continue** (default): Keeps credits and upgrades from previous sessions
- **Fresh start**: Wipes save, resets to stock ship

### Starting Credits (Fresh start only)
- **Modest (200)**: Enough for small repairs or one basic upgrade
- **Comfortable (500)**: Can buy a decent upgrade immediately
- **Well-off (1000)**: Multiple upgrades or a jump drive

### Danger Level
- **Relaxed**: Fewer hostiles, more breathing room (good for learning)
- **Normal** (default): Balanced encounters
- **Dangerous**: More frequent/stronger enemies

### Director
- **On** (default): AI creates dynamic encounters
- **Off**: Static universe with scripted random encounters

## What Players Can Do

### Explore
- **16 stations** across 5 suns (The Drift universe map is in `docs/verse_map.svg`)
- **Regions**: Safe (Core, Border, Rim) → Risky (Gauntlet, Deep Shroud) → Dangerous (Blackwater, Boneyard) → Deadly (Maw)
- Scanning objects reveals salvage, derelicts, interesting details

### Trade
- **Hail freighters** for rumours about profitable routes
- **Hail stations** for local news and "any jobs?" opportunities
- Some stations buy/sell specific goods (the AI may mention this)

### Salvage
- **Debris fields** in every region (scan to reveal value)
- **Better salvage** in dangerous zones (risk vs reward)
- **Derelict ships** have logs (scan fully to read them)

### Upgrade
- **16 upgrades** available across different stations
- Costs: 150-500 credits each
- Each station sells different upgrades (ask the shipwright)
- Jump drive (500cr) is the big one—enables long-range travel

### Combat
- **Corsairs** ambush in the Gauntlet and Blackwater
- **Relic drones** guard the Boneyard (war machines, hostile to all)
- **Hollow ships** in the Maw (deadly—avoid early game)
- **Concord patrols** are neutral unless you attack them or flee from inspections

## GM Tools (Buttons)

### Built-in Campaign Buttons (from framework)
- **Campaign: show status**: Display credits, upgrades, flags
- **Campaign: +200 credits**: Award money for clever play
- **Campaign: save now**: Manual save to scriptstorage.json

### Sandbox-Specific Buttons
- **Sandbox: End session**: Call when the crew docks and you're ready to wrap up
- **Sandbox: +500 credits**: Large reward for major accomplishments
- **Sandbox: Spawn salvage nearby**: Drop a supply pod near the player

### AI Director Buttons (if director is running)
- **AI: twist**: "Create a complication"
- **AI: escalate**: "Make things more dangerous"
- **AI: ease off**: "Give the crew a breather"
- **AI: chatter**: "Add colour (hails, rumours, character moments)"

## AI Director Console (Browser)

If the director is running, open `http://<director-pc>:8765/` for:

### GM Instructions
Type plain-English commands to the AI:
- "Have a freighter captain offer a delivery job to Hob's Landing"
- "Spawn two Corsair scouts near the asteroid field"
- "Create a mystery: derelict with a strange signal"
- "A Concord patrol hails asking about recent activity"

### Quick Buttons
- **Opportunity**: AI creates a job, rumour, or distress call
- **Encounter**: AI spawns an appropriate threat/mystery
- **Say (from NPC)**: AI voices a character
- **Salvage**: AI drops loot

### Standing Directives
Rules for the whole session:
- "We have 90 minutes tonight, keep it moving"
- "The crew is learning, go easy on combat"
- "Reward exploration with interesting finds"
- "If they seem lost, offer a rumour pointing to content"

### Model Action Approval
Toggle "wait for my approval" to vet every AI action before it happens.

## Session Flow

### Opening (5-10 min)
1. Crew spawns docked at Port Vesper
2. Port Vesper dockmaster hails with welcome/warning
3. Crew can:
   - Buy upgrades (if they have credits)
   - Hail for rumours
   - Check their current credits/upgrades
4. Crew undocks when ready

### Middle (30-60 min)
Crew decides what to do:
- **Explore**: Visit new stations, scan interesting objects
- **Salvage**: Hunt debris in asteroid fields or nebulae
- **Trade**: Follow rumours to profitable stations
- **Jobs**: Respond to distress calls or director-offered missions
- **Combat**: Test upgrades against Corsairs in the Gauntlet

AI director (if on) creates:
- Encounters matching the region's danger level
- Opportunities based on what the crew seems interested in
- Rumours and hails from NPCs
- Mysteries and derelicts

### Closing (5-10 min)
1. Crew docks at any friendly station
2. GM presses **"Sandbox: End session"** button
3. Campaign saves (credits, upgrades, flags persist)
4. Session end message shows final credits
5. Can start a new session anytime with **Campaign: Continue**

## Tips for Great Sandbox Sessions

### For First-Time Crews
- Start with **Danger Level: Relaxed** and **Starting Credits: Comfortable (500)**
- Give them 10 minutes docked to explore the station menu and buy first upgrade
- Suggest they "hail Port Vesper for rumours" to get hooks
- Point out the danger zones on the map (Relay shows region names)
- Let them try combat in a safe area first (spawn 1 MT52 Hornet near Port Vesper)

### Using the AI Director Effectively
- **Start with standing directives**: Tell it the session length and crew experience
- **Let it breathe**: Don't fire events every minute—quiet moments matter
- **Support player choices**: If they ignore a distress call, have consequences show up later
- **Build on previous sessions**: The director remembers what happened (in its session summaries)
- **Experiment**: Try "unusual encounter" or "what would make this interesting?" prompts

### Without the AI Director
- Director=Off still works—scripted random encounters in dangerous zones
- Use GM buttons to spawn salvage, give credits, create situations manually
- Hail the crew as NPCs yourself (type in GM chat)
- Still a great way to learn the universe and ship systems

### Pacing
- **30-minute session**: One goal (visit station X, salvage the Gauntlet, escort a freighter)
- **60-minute session**: Multiple activities, 1-2 encounters, exploration
- **2-3 hour session**: Epic journey (Core → Rim), multiple jobs, character development

### When Players Seem Lost
Offer hooks:
- Hail from station: "We need someone to haul cargo to X station, pays 300cr"
- Freighter rumour: "Heard there's good salvage in the Shroud, if you're brave"
- Distress call: "Mayday, under attack near coordinates X,Y"
- Director instruction: "Create an opportunity that plays to what they've been doing"

### Upgrade Progression
- Session 1-2: Basic upgrades (hull, shields mk2, repair crew, forward beams)
- Session 3-4: Advanced upgrades (jump drive, combat thrusters, sensor suite)
- Session 5+: Top-tier (heavy beams, warp overhaul, reactor overhaul) unlocks dangerous zones

### Region Recommendations by Upgrade Level
- **Stock ship**: Core, Border, Rim safe zones
- **2-3 upgrades**: Gauntlet (risky but good salvage), Shroud edge
- **5+ upgrades**: Deep Shroud, Boneyard (dangerous but valuable)
- **8+ upgrades**: Blackwater Reach, Maw approaches (deadly)

## Troubleshooting

### "AI director offline" on GM screen
- Director isn't running, or can't reach EmptyEpsilon server
- Check `director/config.toml` has correct `[ee] url`
- Ensure `httpserver=8080` in EmptyEpsilon `options.ini`
- Scenario still works in Director=Off mode

### Crew is overwhelmed by enemies
- Use GM button **AI: ease off**
- Give standing directive: "Keep combat light, they're learning"
- Or manually destroy some enemies (GM → click ship → destroy)

### Crew has too much money
- Reduce spawned salvage value
- Make upgrades more expensive (edit `ee/ragtag/core.lua` RT.UPGRADES table)
- Or let them be space-rich! It's sandbox—no wrong way to play

### Crew is bored
- AI instruction: "Create an interesting mystery"
- Spawn something unusual: derelict in a strange location, signal that shouldn't exist
- Hail them with a moral dilemma: "Freighter under attack, but they're smugglers"

### Session won't end
- Crew must be **docked at a friendly station**
- Then GM presses "Sandbox: End session" button
- If button doesn't work, check EmptyEpsilon.log for errors

## Files

- **Scenario**: `scenarios/sandbox/scenario_80_sandbox.lua`
- **Campaign save**: Server's `scriptstorage.json`, key `ragtag.campaign.sandbox`
- **Director memory**: `director/director_memory.json` (backup of campaign save)
- **Bible**: `scenarios/sandbox/bible.md` (context for AI director)

## Next Steps

After a few sandbox sessions, your crew might want:
1. **Story campaign**: Try `scenarios/longhaul/` (5-session narrative)
2. **Custom campaign**: Use sandbox as a template for your own story
3. **Harder sandbox**: Increase danger level, start in a riskier location
4. **PvP sandbox**: Spawn two player ships, let them compete for salvage

Have fun exploring the Drift!
