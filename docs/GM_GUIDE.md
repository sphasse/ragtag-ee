# GM Operations Guide — The Drift

Running a session of The Drift: free exploration, job contracts, faction consequences, and wrap-up.

---

## Before You Start

### Scenario settings

| Setting | Recommendation | Notes |
|---|---|---|
| **Campaign** | Continue *or* Fresh start | Continue carries credits and upgrades from prior sessions. Fresh start for a new group. |
| **Starting Credits** | Comfortable (500 cr) | Lets the crew take their first mission and buy one upgrade without waiting. Modest (200 cr) works for a grittier feel. |
| **Director** | On | With a model running, the Director watches the session and keeps notes and summaries for you. It observes only: the game plays the same with it On, Off or not running. |

### What the GM screen shows

- **Campaign Status** — credits, reputation per faction, upgrades purchased
- **Active Jobs** — current mission type, tier, and phase
- **Session Info** — session number, time exploring, encounters, visited regions
- **GM Buttons** — Campaign Status, Reputation, World Plugins, Jobs, Ship Upgrades (per ship), Missions (story arcs), campaign backup / restore

> **Director tip:** Open the GM console at `http://localhost:8765/` on a second screen to see event summaries and track what's happening.

---

## Session Flow

### Opening (5-10 min)

Crew spawns docked at Port Vesper. Let them explore the station menu, buy a first upgrade if they have the credits, and hail for rumours before undocking.

### Middle (30-60 min)

Crew runs jobs, explores regions, and accumulates credits and rep. Encounters come from the zone the ship is in (the Proximity plugin) and from the story arcs. Watch for:

- **First docking** — crew learns the comms flow (hail → job board → accept). Let it happen naturally.
- **First combat** — a proximity spawn in the Shroud or Gauntlet. Good moment to let it breathe.
- **Concord inspection** — if they wander into the Arbiter Line or Core with middling rep, Concord will warp-jam and hail. The relay officer has 60 seconds to respond. Their choice.
- **Rep consequences** — the Relay console logs every rep change and flags threshold crossings. Good moments for a line from you (the Director console's "Say", or a GM hail).

### Closing (5-10 min)

GM quits any time (the campaign autosaves; use **Backup campaign** for a restore point). Resume with Continue next session.

---

## Quick Reference

### Reputation effects

See **[REPUTATION.md](REPUTATION.md)** for the full mechanics reference — reward formula, all thresholds, Concord inspection flow, and donation opportunities.

**Quick summary:** Rep is unbounded. Changes log to Relay immediately with current standings. Destroying a ship costs −200 rep with that faction; failed or expired jobs cost −(reward amount).

- **Concord:** inspections at rep ≥ −200; spawn hostile at rep < −200. Raise rep via Concord Waypoint Galen donations or Concord-faction jobs.
- **Independent:** job board thins below 0, goes dark below −400. Raise via Saint Brennan's Mission donations or any job completion.
- **Corsairs:** patrol frequency scales with rep; job board same thresholds as Independent.

> Watch the Relay console for threshold-crossing alerts — good moments to lean in with a hail of your own.

### Danger by zone

| Zone | Threat | Max spawn |
|---|---|---|
| Safe (Core, Border, Rim safe zones) | Concord inspections only | Scout |
| Risky — the Gauntlet, Shroud | Corsairs | Medium (with upgrades) |
| Dangerous — Blackwater, Boneyard | Corsairs / Relic drones | Heavy |
| Deadly — the Maw | Hollow | Heavy (always) |

### Upgrade tiers

| Investment | Mission tier | Unlocks |
|---|---|---|
| 0–499 cr | Tier 0 | Delivery, salvage |
| 500–999 cr | Tier 1 | Hacking, tailing |
| 1000 cr+ | Tier 2 | Boarding, destroy |

---

## If Something Breaks

- **Director offline** — nothing in the game depends on it. It only observes.
- **Player ship destroyed** — session ends with a "ship lost" outcome. Credits and upgrades already saved are preserved.
- **Concord patrol stuck or hostile** — raising rep with the **Reputation...** button stops new hostile patrols but does not call off one already there. **World Plugins... → Proximity Spawns**: switch it off and on again to remove every patrol.
- **LUA-Error in log** — check `EmptyEpsilon.log` for file and line number. Most errors are API calls on invalid objects after a ship is destroyed.
