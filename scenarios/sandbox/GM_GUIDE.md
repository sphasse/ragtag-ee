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
- **Well-off (1000)**: Multiple upgrades immediately

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
- **Debris fields** in every region — scan pods to reveal value (5–20 cr each, higher in dangerous zones)
- **Combat drops** — destroyed enemy ships leave 1–3 salvage pods; value scales with zone danger
- **Derelict ships** have logs (scan fully to read them)
- Salvage is intentionally lower than job pay — it supplements missions rather than replacing them

### Upgrade
- **15 upgrades** available across different stations
- Costs: 150–450 credits each; each station sells a different selection
- Warp coil overhaul (250cr) is the key mobility upgrade
- **Mission tiers are gated by total upgrade investment**, not upgrade count:
  - **<500cr invested** — delivery and salvage only (tier 0)
  - **500–999cr invested** — hacking and tailing unlock (tier 1)
  - **1000cr+ invested** — boarding and destroy unlock (tier 2)
- Check current investment in the **Campaign Status** GM button

### Jobs

Hail any station and ask "Any work available?" — the station offers two missions. Five types:

| Type | Pay range | Faction rep |
|---|---|---|
| **Delivery** | 50–130 cr | +reward with origin faction on complete; −reward on fail/expire |
| **Salvage** | 60–155 cr | Same; urgent salvage pays 1.5× |
| **Hacking** | 85–215 cr | Rep-neutral (relay hack is undetected); rotating defence platform at 5U range |
| **Destroy** | 100–250 cr | −200 Corsairs on kill; +reward with origin on complete |
| **Boarding** | 115–285 cr | −100 Corsairs on disable; +reward with origin on complete |
| **Escort** | 90–230 cr | +reward with origin on complete; Corsair intercepts at 33% and 67% of route |

Time limits scale with distance — short-range delivery might be 3–5 minutes, a long boarding run could be 25+. Urgent missions are explicitly flagged and pay 1.5× but have tighter windows.

Failing or letting a mission expire costs the crew the **full reward amount** in reputation with the issuing faction. Reputation is unbounded — it accumulates across sessions with no cap. Job availability thins as standing drops, and stations stop offering work entirely below −400. See **[docs/REPUTATION.md](../../docs/REPUTATION.md)** for the full thresholds and mechanics.

**Hacking specifics:** The target is a comms relay running automated war-drone defence protocols. It is a rotating Defence Platform with six 30° beam mounts at 5U range, slowly spinning (one revolution every 45 seconds). There are 30° gaps between beams — Helm needs to find and hold those windows while Engineering manages shields and Science hacks any system to 75%. Weapons can grind down the platform's shields to reduce incoming damage. The hack is undetected, so the mission is rep-neutral. Scan probes are destroyed naturally when a beam arc sweeps over them.

### Combat
- **Corsairs** ambush in the Gauntlet and Blackwater
- **Relic drones** guard the Boneyard (war machines, hostile to all)
- **Hollow ships** in the Maw (deadly—avoid early game)
- **Concord patrols** are neutral unless you attack them or flee from inspections
- **Killing any faction ship costs −200 rep with that faction** — one fight can tank Corsair standing significantly
- Reputation is unbounded (no ±100 cap), so a long campaign can see standing in the hundreds or deep negative

## GM Tools (Buttons)

### Built-in Campaign Buttons (from framework)
- **Campaign: show status**: Display credits, upgrades, flags
- **Campaign: +200 credits**: Award money for clever play
- **Campaign: save now**: Manual save to scriptstorage.json

### Sandbox-Specific Buttons
- **Sandbox: End session**: Call when the crew docks and you're ready to wrap up
- **Sandbox: +500 credits**: Large reward for major accomplishments
- **Sandbox: Spawn salvage nearby**: Drop a supply pod near the player
- **Reputation...**: Opens faction list showing current standing. Select a faction to adjust it +100 or −100 (self-refreshes after each press)

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

| Investment | Typical point | Mission tier | Notes |
|---|---|---|---|
| 0–499cr | Session 1 | Tier 0 | Delivery and salvage only |
| 500–999cr | Session 2–3 | Tier 1 | Hacking and tailing available |
| 1000cr+ | Session 3–4 | Tier 2 | Boarding and destroy available |

### Region Recommendations by Investment
- **Stock / <300cr**: Core, Border, Rim safe zones
- **300–600cr**: Gauntlet (risky but good salvage), Shroud edge
- **600–1000cr**: Deep Shroud, Boneyard (dangerous but valuable)
- **1000cr+**: Blackwater Reach, Maw approaches (deadly)

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
- Salvage and job pay are balanced — 50–300 cr/mission, 5–20 cr/salvage pod
- If they're still swimming in credits, the upgrade shop caps out at 8–10 upgrades; that's intentional
- Or let them be space-rich! It's sandbox — no wrong way to play

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
