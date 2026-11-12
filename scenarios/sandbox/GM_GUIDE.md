# The Drift — GM Guide

## Quick Start

1. **Install**: `python tools/install.py --ee <EmptyEpsilon folder>`
2. **Start EmptyEpsilon server** (with `httpserver=8080` in options.ini)
3. **Select scenario**: "The Drift"
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

### Salvage
- **Debris fields** in every region — scan pods to reveal value (5–20 cr each, higher in dangerous zones)
- **Combat drops** — destroyed enemy ships leave 1–3 salvage pods; value scales with zone danger
- **Derelict ships** have logs (scan fully to read them)
- Salvage supplements missions rather than replacing them

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
| **Hacking** | 85–215 cr | Rep-neutral (relay hack is undetected) |
| **Destroy** | 100–250 cr | −200 Corsairs on kill; +reward with origin on complete |
| **Boarding** | 115–285 cr | −100 Corsairs on disable; +reward with origin on complete |
| **Escort** | 90–230 cr | +reward with origin on complete |

Time limits scale with distance. Failing or letting a mission expire costs the crew the **full reward amount** in reputation with the issuing faction.

**Hacking specifics:** The target is a stationary Concord comms relay beacon. Player must hack any system to 75%. Active relays jam scan probes within 5U.

### Combat
- **Corsairs** ambush in the Gauntlet and Blackwater
- **Relic drones** guard the Boneyard (war machines, hostile to all)
- **Hollow ships** in the Maw (deadly — avoid early game)
- **Concord patrols** do inspections when rep ≥ −200; below that threshold they spawn as hostile and attack on sight
- **Killing any faction ship costs −200 rep with that faction**

## GM Tools (Buttons)

### Built-in Campaign Buttons (from framework)
- **Campaign: show status**: Display credits, upgrades, reputation
- **Campaign: +200 credits**: Award money for clever play
- **Campaign: save now**: Manual save to scriptstorage.json

### Scenario-Specific Buttons
- **Sandbox: +500 credits**: Large reward for major accomplishments
- **Sandbox: Spawn salvage nearby**: Drop a supply pod near the player
- **Reputation...**: Opens faction list showing current standing. Select a faction to adjust it +100 or −100

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

### Model Action Approval
Toggle "wait for my approval" to vet every AI action before it happens.

## Session Flow

### Opening (5-10 min)
1. Crew spawns docked at Port Vesper
2. Port Vesper dockmaster hails with welcome/warning
3. Crew can buy upgrades, hail for rumours, check credits
4. Crew undocks when ready

### Middle (30-60 min)
Crew decides what to do. AI director (if on) creates encounters matching the region's danger level, opportunities based on what the crew seems interested in, rumours and hails from NPCs, and mysteries.

### Closing (5-10 min)
1. Crew docks at any friendly station
2. GM presses **Save campaign** (progress also saves as it happens), then quits
3. Credits, upgrades, reputation, stats and story flags persist
4. Can start a new session anytime with **Campaign: Continue**

## Tips for Great Sessions

### For First-Time Crews
- Use **Starting Credits: Comfortable (500)** — enough for a first upgrade right away
- Give them 10 minutes docked to explore the station menu
- Suggest they "hail Port Vesper for rumours" to get hooks
- Point out the danger zones on the map (Relay shows region names)

### Using the AI Director Effectively
- **Start with standing directives**: Tell it the session length and crew experience
- **Let it breathe**: Don't fire events every minute — quiet moments matter
- **Support player choices**: If they ignore a distress call, have consequences show up later
- **Build on previous sessions**: The director remembers what happened

### Without the AI Director
- Director=Off still works — scripted random encounters in dangerous zones
- Use GM buttons to spawn salvage, give credits, create situations manually
- Hail the crew as NPCs yourself (type in GM chat)

### Pacing
- **30-minute session**: One goal (visit station X, salvage the Gauntlet, escort a freighter)
- **60-minute session**: Multiple activities, 1-2 encounters, exploration
- **2-3 hour session**: Epic journey, multiple jobs, character development

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

### Concord turns hostile mid-session
- Concord spawns hostile when reputation drops below −200
- Rep drops from: failed inspections (−100 to −150), jammer destruction (−50), ship kills (−200)
- Raise rep via Concord Waypoint Galen donations (+50/100cr) or completing jobs with Concord-aligned stations
- GM can manually adjust rep via the **Reputation...** button

### Saving
- There is no End session button. Press **Save campaign** and quit; progress also saves as it happens
- **Campaign Status** shows credits, upgrades, reputation, stats, story arcs and achievements

## Files

- **Scenario**: `scenarios/sandbox/scenario_80_ragtag.lua`
- **Campaign save**: Server's `scriptstorage.json`, key `ragtag.campaign.sandbox`
- **Director memory**: `director/director_memory.json`
- **Bible**: `scenarios/sandbox/bible.md` (context for AI director)
