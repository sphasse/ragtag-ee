# GM Operations Guide — The Drift

Running a session of The Drift: free exploration, job contracts, faction consequences, and wrap-up.
For the competition scenario, see **The Short Haul** below.

> Ragtag needs Empty Epsilon **EE-2026.09.22PR or newer** and has only been tested on the
> EE-2026.09.22PR pre-release. Install from a release zip: unzip it into your EmptyEpsilon folder
> (on macOS, `EmptyEpsilon.app/Contents/Resources`). More detail: `scenarios/sandbox/GM_GUIDE.md`
> (buttons and settings), [GM_SHIP_MANAGEMENT.md](GM_SHIP_MANAGEMENT.md) (several ships),
> [REPUTATION.md](REPUTATION.md).

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
- **Concord inspection** — if they wander into the Core, the Arbiter Line or the Escrow Marches (south of both) with middling rep, Concord will warp-jam and hail. The relay officer has 60 seconds to respond. Their choice.
- **Rep consequences** — the Relay console logs every rep change and flags threshold crossings. Good moments for a line from you (the Director console's "Say", or a GM hail).

### Story arcs

Five story arcs unlock as the **primary ship** (the Magpie) earns standing and invests in upgrades;
other ships work the job boards only. **Missions...** on the GM screen shows each arc's conditions
(**Mission criteria**: each condition met or not, "Result: ALL MET / do not start", and once it is
over, whether it was completed and how), its state, "→" buttons to jump to any phase, and helpers.
In every phase that sends the crew somewhere there is a travel shortcut, **Ship → <place>** (e.g. **Ship →
Hob's**): it puts the Magpie 5U from the place, undocked and stopped, so a playtest can skip the flight.

| Arc | Starts when | What it is | GM guide |
|---|---|---|---|
| Rezkov | Independent standing 500+ and 600 cr of upgrades | A fixer's job that turns political | [GM_REZKOV_MISSION.md](GM_REZKOV_MISSION.md) |
| Ledger | Rezkov over (or declined), 800 cr of upgrades, 2 board jobs since | A data heist in Concord space, and an audit | [GM_LEDGER_MISSION.md](GM_LEDGER_MISSION.md) |
| Boneyard | Rezkov over, 800 cr of upgrades | A rescue that leads to a Concord archive and a fleet battle | [GM_BONEYARD_MISSION.md](GM_BONEYARD_MISSION.md) |
| Corsair | Rezkov over, 1000 cr of upgrades | Blackwater asks for help against a Concord fleet | [GM_CORSAIR_MISSION.md](GM_CORSAIR_MISSION.md) |
| Hob Works | Ledger, Boneyard (survivors rescued) and Corsair over, then 5 board jobs | The cure gets designed; the crew robs a Treasury convoy to pay for it | [GM_HOB_WORKS_MISSION.md](GM_HOB_WORKS_MISSION.md) |
| Cold Chain | The Hob Works funded, then 3 board jobs | One-off money job: lift the Tamsin fever cure from Ostia's depot (3,000 cr) | [GM_COLD_CHAIN_MISSION.md](GM_COLD_CHAIN_MISSION.md) |

Each arc's GM guide (spoilers) covers its premise and place in the campaign, triggers, phases, GM
buttons and what it leaves for later arcs, with design notes at the end. Arc objectives show as one
short line on Relay and Operations.

### Closing (5-10 min)

GM quits any time (the campaign autosaves; use **Backup campaign** for a restore point). Resume with Continue next session.

---

## Quick Reference

### Reputation effects

See **[REPUTATION.md](REPUTATION.md)** for the full mechanics reference — reward formula, all thresholds, Concord inspection flow, and donation opportunities.

**Quick summary:** Rep is unbounded. Changes log to Relay immediately with current standings. Destroying a ship that was not your enemy costs −200 rep with that ship's faction (Independent, Concord or Corsairs; a friendly Corsair counts as Corsairs), charged to the ship that made the kill. Enemies cost nothing (Corsair patrols and raiders, hostile Concord ships, job targets that turned on the crew), nor do ships in a story-arc fight, Relic or Hollow ships; failed or expired jobs cost −(reward amount).

- **Concord:** inspections at rep ≥ −200; spawn hostile at rep < −200. Below −200 the Concord port guards (one defender per Concord port) also attack a ship that comes within 5U of them, and stand down once it is 10U from the port or its standing recovers. The lane pickets do the same within 10U of them, chasing to 20U from their post before resuming their beat. Raise rep via Concord Waypoint Galen donations or Concord-faction jobs.
- **Independent:** job board thins below 0, goes dark below −400. Raise via Saint Brennan's Mission donations or any job completion.
- **Corsairs:** patrol frequency scales with rep; job board same thresholds as Independent.

> Watch the Relay console for threshold-crossing alerts — good moments to lean in with a hail of your own.

### Danger by zone

| Zone | Threat | Max spawn |
|---|---|---|
| Safe (Core, Border, Rim safe zones) | Concord inspections only | Scout |
| Risky — the Gauntlet, Shroud | Corsairs | Medium (with upgrades) |
| Dangerous — Blackwater, Boneyard | Corsairs / Relic drones (and three old gun platforms in the Boneyard) | Heavy |
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
- **Player ship destroyed** — its crew loses half its credits (upgrades and standing are kept). The session goes on while any player ship is left; it ends only when every ship is lost. Rebuild a lost ship by picking its name on the **Create player ship** list (see [GM_SHIP_MANAGEMENT.md](GM_SHIP_MANAGEMENT.md)).
- **Concord patrol stuck or hostile** — raising rep with the **Reputation...** button stops new hostile patrols but does not call off one already there. **World Plugins... → Proximity Spawns**: switch it off and on again to remove every patrol.
- **LUA-Error in log** — check `EmptyEpsilon.log` for file and line number. Most errors are API calls on invalid objects after a ship is destroyed.

---

## The Short Haul

A one-shot competition (scenario 81, in the same release). Every crew flies a stock Light Freighter
with 200 credits; the richest ship when the clock runs out wins. Score is **net worth**: credits plus
the list price of the ship's upgrades. Nothing is saved, and The Drift's campaign is never touched.

- **Setting: Length** — 15 minutes, 30 minutes (default) or 1 hour.
- **Ships:** the Magpie starts at Port Vesper; other crews pick a named Light Freighter on
  **Create player ship**. Every ship starts with the same loadout and credits.
- **Start the clock** (GM button) when every crew is in: the job boards stay shut until then.
- During the race a **live leaderboard** (time left, the top five, your own place, at most 20 characters
  a line) shows on Relay, Operations, Tactical, Engineering+, Single Pilot and the alt Relay. No pop-ups.
- **At zero** (or **End the competition now**) the final standings pop up on every console and go in the
  ship logs; the leaderboard and clock go away and the ships fly on, on their own.
- Same universe, jobs, rewards, upgrade prices and reputation as The Drift; no story arcs, no survey
  pay. A taken job is replaced on the board at once, and boards favour short runs (**Jobs...** can change
  the distance). A lost ship costs half its credits, as in The Drift.
- GM buttons: **Start the clock**, **Standings** (each ship's credits and upgrade value), **End the
  competition now**, plus Reputation, Jobs (including **New delivery...**, a GM-written job: see the
  sandbox GM guide) and Ship Upgrades.
