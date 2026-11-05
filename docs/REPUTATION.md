# Reputation — The Drift

## How the Drift remembers you

The Drift is a small world. Word travels fast, and word travels far. Every job you take or walk away from, every Concord inspection you cooperate with or dodge, every ship you disable or destroy — it all gets around. The factions keep their own reckoning, and your standing with each one shapes what the Drift will and won't do for you.

There are three factions that matter:

**The Independent network** — everyone who isn't Concord or Corsairs. Port operators, independent traders, the mission boards at neutral stations. High Independent standing opens doors and fills the board with better-paying work. Run enough jobs, treat people square, and stations in the rougher parts of the Drift start routing the worthwhile contracts your way. Let jobs go sideways, fail on delivery, leave people hanging — word gets out, and the board goes quiet.

**The Concord** — the law, such as it is out here. They run inspections on the Arbiter Line and in the Core. A good record means they wave you through without stopping. A bad one means more scrutiny, then fines, then warrants, and eventually — well past the point a reasonable crew would have cleared their name — their patrols stop hailing and start shooting.

**The Corsairs** — pirates, toll-takers, opportunists. They don't offer work and they're not interested in your reputation the way the other factions are. What they're interested in is whether you look like easy money. Where they spawn and how much trouble they give you depends on where you fly; your standing with them mostly determines what jobs you can pick up at their-adjacent ports, and how few other options the job board shows you when things go south.

Reputation carries across sessions. The Drift doesn't forget.

---

**Practical consequences at a glance:**

Concord standing high → wave-through on the Arbiter Line, no fine, no paperwork. Standing low → fines and warrants. Standing very low → they come for you.

Independent standing high → more work available, better contracts offered. Standing low → the board thins out. Standing very low → almost nothing.

Corsair standing high → more work available at Border ports, fewer obstacles in rough space. Standing low → the board thins out. Standing very low → almost nothing, plus warrants from previous jobs go unresolved.

Donations at **Saint Brennan's Mission** and **Concord Waypoint Galen** are a way to rebuild Independent standing when other options are thin — slow but reliable.

---

*If you want to understand how the system works under the hood, keep reading.*

---

## Mechanics reference

### Tracking and display

Reputation is stored per-faction in the campaign save as an unbounded integer — no cap in either direction. It starts at zero for all factions.

Every reputation change logs three lines to the Relay console:
1. The change: `Concord reputation +100 — completed: Delivery run`
2. Current standings: `Current reputation: Independent: +0 | Concord: +100 | Corsairs: +0`
3. If a threshold was crossed: `[Rep] Concord will now wave you through inspections without stopping.`

### How reputation changes

| Trigger | Faction affected | Change |
|---|---|---|
| Complete a job | Origin station's faction | +(job reward in cr) |
| Job expires or is failed | Origin station's faction | −(job reward in cr) |
| Destroy any ship | That ship's faction | −200 |
| Board and disable a ship | Corsairs | −100 |
| Concord fine paid (shake-down) | Concord | +100 |
| Evade Concord inspection (flee 10U) | Concord | −100 |
| Donate $100 at Saint Brennan's Mission | Independent | +100 |
| Donate $100 at Concord Waypoint Galen | Independent | +50 |

**Mission reward formula** (affects how much rep moves per job):

```
reward = base × type_mult
       × distance_bonus (0–30% scaled across mission range)
       × danger_bonus   (+15% per danger level, 0–4)
       rounded to nearest 5cr
```

| Tier | Base reward | Ship upgrade count |
|---|---|---|
| Tier 0 | 50cr | 0–1 upgrades |
| Tier 1 | 65cr | 2–4 upgrades |
| Tier 2 | 80cr | 5+ upgrades |

| Mission type | Type multiplier |
|---|---|
| Delivery | 1.0× |
| Salvage | 1.2× |
| Hacking | 1.4× |
| Destroy | 1.6× |
| Boarding | 1.8× |

A completed Tier 0 delivery at minimum range moves about +50 rep. A failed Tier 2 boarding mission at max range can move −200+ rep.

### Concord reputation thresholds

| Threshold | Crossing up | Crossing down |
|---|---|---|
| +500 | Wave through inspections — no stop, no fine | Concord resumes inspections |
| +200 | Accept cargo declarations without proof | No longer accepts declarations without proof |
| 0 | Benefit of doubt on ignored hails | Patrols will issue warrants for ignored inspections |
| −200 | More work becoming available at Concord ports | Very few jobs at Concord ports |
| −400 | Concord ports may offer limited work again | Concord ports will no longer offer work |
| −500 | Inspection protocols restored | **Concord patrols will now attack on sight** |

**How Concord inspections work:**
- Concord patrols spawn in the **Concord Core** and **Arbiter Line** zones only.
- On spawn they fly toward the player ("approaching"). When they close to 5U and the player is more than 20U from any station, they deploy a 1U WarpJammer, hail via comms, and begin the shake-down.
- Player options: submit (30-second scan, −50% credits fine if contraband found, +100 rep on fine paid), stall (3 stalls allowed, each resets the 45-second clock, 4th stall triggers an out-of-patience fine), or run (requires getting 10U clear of all patrol ships, −100 rep).
- Rep ≥ +500: immediate wave-through, no jammer, no fine.
- Rep ≥ +200: Concord accepts a cargo declaration without a scan.
- Rep < −500: no shake-down — Concord ships spawn and immediately `orderAttack`.

### Independent and Corsair thresholds

Both factions use the same job-access thresholds:

| Threshold | Crossing up | Crossing down |
|---|---|---|
| 0 | Full job access restored at this faction's ports | Fewer jobs offered at this faction's ports |
| −200 | More work becoming available | Very limited jobs available |
| −400 | Some jobs may return | This faction will no longer offer work |

Corsairs have no patrol shake-down. Their spawn zones and ship strength are determined by geography (see **Danger levels** in the GM guide); reputation affects job access at Corsair-adjacent ports only.

### Donation opportunities

Two stations offer a way to rebuild Independent standing outside of jobs:

| Station | Faction | Location | Donation | Rep gained |
|---|---|---|---|---|
| Saint Brennan's Mission | Independent | Border, x=72 y=−62 | $100 | +100 Independent |
| Concord Waypoint Galen | Concord | Arbiter Line, x=−75 y=−52 | $100 | +50 Independent |

Requires docking. No limit on number of donations per session.

### GM controls

**Spawn frequency** is controlled by a GM button that cycles four modes per zone:

| Mode | Frequency | Max active ships |
|---|---|---|
| None | Disabled | 0 |
| Low | 0.5× | 6 |
| Medium (default) | 1.0× | 12 |
| High | 2.0× | 24 |

Concord zones cap at **1 active ship** regardless of mode (zone-level override), with per-zone cooldowns of 600s (Core) and 720s (Arbiter Line).

Corsair zone cooldowns by region at Medium mode:
- Shroud, Halcyon Rest: 240s
- Gauntlet, Blackwater Reach: 180s

**In session:** Watch for the Relay console logging a threshold crossing — it's the right moment to have the Director lean in with flavour (a Concord patrol commenting on your record, a Corsair backing off after a job goes wrong). The rep logging happens immediately when the trigger fires, so the crew will see it before you do if you're not watching.
