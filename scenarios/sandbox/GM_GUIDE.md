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
- **On** (default): the game reports events to the AI director, if one is running. The director
  observes and keeps notes for you; it does not change the game.
- **Off**: nothing is reported. The game plays exactly the same.

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
- Upgrades belong to the ship that bought them: a second player ship has its own credits,
  standing, upgrades and job tier
- **Mission tiers are gated by a ship's total upgrade investment**, not upgrade count:
  - **<500cr invested** — delivery and salvage only (tier 0)
  - **500–999cr invested** — hacking and tailing unlock (tier 1)
  - **1000cr+ invested** — boarding and destroy unlock (tier 2)
- Check current investment in the **Campaign Status** GM button

### Jobs

Dock at any friendly station and ask "Any work available?" — the station offers one to three
contracts, depending on its size and the ship's standing there. A ship can hold two at a time.
Types:

| Type | Pay range | Faction rep |
|---|---|---|
| **Delivery** | 50–130 cr | +reward with origin faction on complete; −reward on fail/expire |
| **Salvage** | 60–155 cr | Same; urgent salvage pays 1.5× |
| **Hacking** | 85–215 cr | Rep-neutral (relay hack is undetected) |
| **Destroy** | 100–250 cr | −200 Corsairs on kill; +reward with origin on complete |
| **Boarding** | 115–285 cr | −100 Corsairs on disable; +reward with origin on complete |
| **Escort** | 90–230 cr | +reward with origin on complete |
| **Tailing** | tier 1+ | +reward with origin on complete; −2× reward if the target is lost to the clock |

Time limits scale with distance. Failing or letting a mission expire costs the crew the **full reward amount** in reputation with the issuing faction.

**Hacking specifics:** The target is a stationary Concord comms relay beacon. Player must hack any system to 75%. Active relays jam scan probes within 5U.

### Combat
- **Corsairs** ambush in the Gauntlet and Blackwater
- **Relic drones** guard the Boneyard (war machines, hostile to all)
- **Hollow ships** in the Maw (deadly — avoid early game)
- **Concord patrols** do inspections when rep ≥ −200; below that threshold they spawn as hostile and attack on sight
- **Killing any faction ship costs −200 rep with that faction**

## GM Tools (Buttons)

The GM screen's buttons, top to bottom:

- **Campaign Status**: the primary ship's credits, upgrades (with investment and job tier) and
  reputation; a line for every other player ship; then statistics, story arcs and achievements
- **Reputation...**: a ship's standing per faction, with what each level means (with several ships,
  pick the ship first). Select a faction to adjust it by +50 or −50
- **World Plugins...**: switch each ambient system on or off and tune it: Proximity Spawns
  (per-zone None / Low / Medium / High, "Trigger Spawn Now"), Station Defenders, Salvage Clusters
  (density, reward), Station Traffic (density), Rumors, Science Database
- **Jobs...**: work cooldown on/off, job distance (short / medium / long), credits +50 / −50 (a pair
  of buttons per ship when there are several)
- **Ship Upgrades...**: pick a ship, then grant or revoke upgrades on **that ship** and view its
  status sheet (see `docs/GM_SHIP_MANAGEMENT.md`)
- **Missions...**: the story arcs (Rezkov, Boneyard, Ledger, Corsair): trigger conditions, state,
  and "→" buttons to jump an arc to any phase
- **Backup campaign / Restore campaign**: six numbered save slots (see Saving, below)
- **Sounds...**: sound cues on or off, with test buttons

## AI Director Console (Browser)

If the director is running, open `http://<director-pc>:8765/`. **The director is
observation-only**: the model watches the session and can write you private notes. It cannot
hail the crew, spawn anything, or change credits, standing or the story.

- **Live view**: the event feed, the ships' state, active jobs, beats, the model's notes
- **GM instructions / standing directives**: tell the model what to watch for or summarise
  ("keep a running tally of what the crew promised to whom")
- **Say (from NPC)**: you speak to the crew as a station or ship. The model can help draft the
  line; you send it. Arrives as a real hail when the speaker is a callsign in the game
- **Set objective / Rename ship / Restore campaign**: GM-only console actions

Requests like "spawn two Corsair scouts" do nothing: there is no such action. Use the World
Plugins menu ("Trigger Spawn Now") or EmptyEpsilon's own GM tools to create ships.

## Session Flow

### Opening (5-10 min)
1. Crew spawns docked at Port Vesper
2. Port Vesper dockmaster hails with welcome/warning
3. Crew can buy upgrades, hail for rumours, check credits
4. Crew undocks when ready

### Middle (30-60 min)
Crew decides what to do: jobs from the station boards, salvage, exploration. Encounters come from the world itself (patrols by zone, see the Proximity plugin) and from the story arcs as their conditions are met. The AI director, if on, keeps notes for you.

### Closing (5-10 min)
1. Crew docks at any friendly station
2. Optionally press **Backup campaign** and pick a slot to keep a restore point (the campaign also autosaves every minute and on every story or credit event), then quit
3. Credits, upgrades, reputation, stats and story flags persist
4. Can start a new session anytime with **Campaign: Continue**

## Tips for Great Sessions

### For First-Time Crews
- Use **Starting Credits: Comfortable (500)** — enough for a first upgrade right away
- Give them 10 minutes docked to explore the station menu
- Suggest they "hail Port Vesper for rumours" to get hooks
- Point out the danger zones on the map (Relay shows region names)

### Using the AI Director Effectively
- **Start with standing directives**: tell it the session length and what you want tracked
- **Read its notes at quiet moments**: it summarises where the crew is, what changed, and what is open
- **Build on previous sessions**: it keeps a summary of each session for the next one
- **Speak through it**: use "Say" on the console to voice a station or ship yourself

### Without the AI Director
- Nothing in the game depends on it: jobs, patrols, arcs and saves all work the same
- Use the GM buttons to give credits, adjust standing, tune patrols and drive the story arcs
- Hail the crew as NPCs yourself (EmptyEpsilon's GM hail)

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
- The game is unaffected: the director only observes

### Crew is overwhelmed by enemies
- **World Plugins... → Proximity Spawns → Spawn Zones...**: set the zone to Low or None
- Or switch Proximity Spawns off for a while (existing patrols are removed)
- Or manually destroy some enemies (GM → click ship → destroy)

### Concord turns hostile mid-session
- Concord spawns hostile when reputation drops below −200
- Rep drops from: failed inspections (−100 to −150), jammer destruction (−50), ship kills (−200)
- Raise rep via Concord Waypoint Galen donations (+50/100cr) or completing jobs with Concord-aligned stations
- GM can manually adjust rep via the **Reputation...** button

### Saving
- There is no End session or Save campaign button: the campaign autosaves every minute and on every story, reputation, credit and job event
- **Backup campaign** copies the campaign into one of 6 numbered slots (labelled with play time and credits); pressing a slot again saves over it
- **Restore campaign** replaces the live save with a slot after a confirmation, then asks you to restart the scenario and choose Continue. Saving is paused until you restart, and your previous save is kept under `<campaign key>.before_restore`
- **Campaign Status** shows credits, upgrades, reputation, stats, story arcs and achievements

## Files

- **Scenario**: `scenarios/sandbox/scenario_80_ragtag.lua`
- **Campaign save**: Server's `scriptstorage.json`, key `ragtag.campaign.sandbox`
- **Director memory**: `director/director_memory.json`
- **Bible**: `scenarios/sandbox/bible.md` (context for AI director)
- **Other ships' records**: in the same save, under `extra_ships` (one per ship, by callsign)
