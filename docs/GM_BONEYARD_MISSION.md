# The Boneyard Arc — GM guide

A Phase II story arc of The Drift (sandbox campaign, scenario 80). **Spoilers**: keep this away from
players. Module: `ee/ragtag/missions/boneyard.lua` (the fight: `BATTLE.annex` in
`ee/ragtag/battle.lua`). Back to the [GM guide](GM_GUIDE.md).

## Premise

A lifeboat of archive staff is adrift on the Boneyard's rim. They escaped the **Ashgrave Annex**, a
Concord Level-5 research archive buried in the Settlement War debris field, and a Concord battle group
is on its way to seal it for good. The crew breaches the Annex and downloads its archive before the
fleet can stop them. The arc is combat-heavy and time-pressured, and it reveals the Drift's central
secret.

Where it sits in the campaign:

- **It is the science thread.** The archive proves that the Hollow are people: the Pale Sun
  colonists, changed by the Concord's Ashgrave Synthesis compound. The Synthesis entry describes the
  cure the finale is built on (a broadcast at the documented frequency, within range, about 90 s).
- **It introduces Dr. Mara Quill**, senior researcher on the shut-down reversal program, and three
  catalogue technicians. At the report Quill says the Concord "was very close to a cure, but the
  political fallout from building and deploying it would have been too great", and that they're
  headed to Hob's Landing. That is the hook for the **Hob Works** mission, where the cure gets built.
  Rescuing the survivors is required for the Hob Works.
- **It costs the Concord a battle group.** Destroying it (`boneyard_battlegroup_destroyed`) is one of
  the two fleet losses that leave the Concord rebuilding at Sentinel Fleet Yard, the backdrop of the
  Hob Works heist and of the Concord's later fracture.
- **It can win the crew an ally.** Reprogramming the Relic drones against the Concord
  (`boneyard_drone_flip`) gives the finale a drone defense wing, and the Corsairs like it (the enemy
  of their enemy).

## Triggers

- The Rezkov arc finished (any outcome) **or declined**.
- **≥ 800 cr** of upgrades on the primary ship (the Magpie).
- `boneyard_arc_done` not set. Auto-starts; no standing gate.

Before the trigger, while the arc is enabled, ten vague "up north" seed rumors and five seed deliveries
among Halcyon Rest, Port Vesper, Arbiter and Saint Brennan's join the boards.

## Phases

```
hook ─► annex_hack ─► annex_control ─► report ─► done
                            └────────────────────► done   (no survivors picked up: the fight is the end)
```

### Hook

Three hook rumors name Ashgrave and the Boneyard (the Concord is mobilising a heavy response group).
No objective: the crew follows the leads. There are two ways in.

**The lifeboat rescue (the intended way).** An URGENT `[SPECIAL]` salvage job, "a lifeboat of
survivors" (350 cr, 20-minute clock, no standing penalty), is on the boards at Port Vesper, Halcyon
Rest and Saint Brennan's Mission (one shared job). The pods are on the Boneyard's south rim at
(22, −72); one Science scan shows which is the lifeboat.
- Picking it up: the log says the survivors are archive staff locked out of Ashgrave, with Ashgrave's
  grid. Mara Quill hails (an invisible voice; the ship log if comms are busy): she uploads their
  records and asks for someone to hack the Annex and extract the research. A Science DB entry, Lore →
  "Boneyard Survivor Records", is added. The job's clock stops (they're aboard and breathing).
- **Nothing more happens until they are home.** Handing the job in at the station it came from adds
  the "Hack the Annex" objective, and the Annex appears. Flying past Ashgrave with them aboard reveals
  nothing.
- A missed clock re-offers the job; once they're rescued it never returns. A session that ends with
  them aboard counts them as home.

**Ashgrave without the survivors.** Flying within 8U of Ashgrave reveals the Annex too.

The Annex is at (43, −104), grid zz7, deeper in the debris than the visible battle damage. When it
appears the hook rumors and the lifeboat job go, and the arc moves to the hack.

### Annex hack

The objective is "Hack the Annex", and **nothing else: no pop-up, no instructions**. The survivors'
request is the prompt; working out how is the crew's puzzle. Hailing the Annex only says it is under
an encrypted lockdown.

Relay hacks the Annex's **front shield** until the crew sees it at **0%** (each success is 50%, and it
decays over 180 s, so two in a row). Probes don't last near the drones, so the crew has to get close
under fire. At 50% a log line notes that the files are marked Concord Level 5.

When the hack lands:
- Every Relic drone in the Boneyard and its three gun platforms go Derelict and idle, and so does any
  drone that turns up later in the arc.
- Boneyard patrols are suspended.
- The Annex turns `Relic Active` and can be docked: "Station security has been reset. Dock for more
  options."
- Objective: "Download Annex data". The crew keeps warp.

### Annex control

The Annex's operations are offered **only to a docked ship**. Docked, it also repairs, shares energy
and restocks probes.

**The first docking brings the fleet**: every console gets "Incoming jump detected. A Concord battle
fleet has arrived.", and seven Concord ships appear 15U north-west. CNS *Vanguard* orders all vessels
to stand down.

Three operations, **one at a time** (the others show [LOCKED]; **Refresh** shows the countdown):

| Operation | Time | Effect |
|---|---|---|
| Download research archive | 5 min while the fleet is out, 1 min once it's gone | The archive. **Must stay docked**: undocking stops it, and it starts again from zero |
| Reprogram the drones to be hostile to the Concord | 60 s | 24 fast drones launch from the two nearby nebulae and fight the fleet |
| Enable station defense lasers | 60 s | The Annex fires on the Concord |

The reprogram and the lasers keep running if the crew undocks. The intended order is drones first,
then lasers or the fight, then the archive. When the last Concord ship dies:
- The Annex hails once: "All Concord forces in proximity have been eliminated."
- The archive is compressed: a download not yet started takes 1 minute, and a running one finishes
  within a minute.
- The drones fall back to guard the Annex.

If the archive is in but the fleet isn't beaten, the objective is "Defeat Concord fleet". A crew that
never rescued the survivors gets the Hob's Landing pointer as a Science log line when the download
completes.

The phase ends when the archive is in **and** the fleet is gone. Then the arc goes to the report, or
straight to done without the survivors. **Leaving the Boneyard** (20U outside it) also ends the phase
with whatever the crew has: with the archive (and the survivors rescued), go to the report; otherwise
done.

### Report

Objective "Report the success"; the log names the station the survivors were taken to. Docked there,
**"Talk with the lifeboat survivors"**: Quill (who adds "a whole Concord battle group destroyed? That'll
set them back." if it was) says the Concord was very close to a cure, and that they're headed to Hob's
Landing ("We heard they have some exceptional engineers there"). That ends the arc.

### Done

The objective clears, the rewards are paid, outcome rumors go out, the Boneyard's patrols resume, and
the remaining combat ships are removed 2 minutes later.

## GM console

**Missions… → Boneyard Arc**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ Hook` | Rumors and the lifeboat job (also forgets the survivors, so the job is offered again) |
| `→ Annex hack` | The Annex is out, unhacked |
| `→ Annex control` | Hacked and dockable; the fleet arrives when the crew docks |
| `→ Report` | Archive in, fleet beaten; marks the survivors rescued if they weren't |
| `→ Done: Full` / `→ Done: Data` | End with archive + drones / archive only |

Helpers, shown only in their phase:
- **Complete hack** (annex hack): sets the front shield fully hacked; the phase finishes normally. The
  ship isn't moved.
- **Destroy Concord** (annex control, once the fleet is out): destroys the rest of the fleet; the
  Annex's hail and the rest follow as in a won fight.

A jump resets the arc (the Annex, the fleet, the drones, timers, rumors, jobs, the suspended zone, the
`boneyard_*` flags), restores the idled drones and platforms to the Relic, then replays the earlier
phases. End states skip the replay so the world ends clean. Rewards are paid once (`boneyard_rewarded`),
so jumping between end states doesn't pay twice; reputation, credits and Science DB entries already
given are not undone.

## Exports

| Flag | Set when |
|---|---|
| `boneyard_arc_done` | the arc resolves |
| `boneyard_buoy_found` | the lifeboat survivors were picked up (Hob Works trigger) |
| `boneyard_survivors_home` | they were handed in at the rescue job's station |
| `boneyard_survivors_at` | that station (where the crew reports) |
| `boneyard_hack_done` | the archive was downloaded (Hob Works price: 10,000 with it, 15,000 without) |
| `boneyard_drone_flip` | the drones were reprogrammed (finale defense wing) |
| `boneyard_battlegroup_destroyed` | CNS *Vanguard* destroyed (the Concord rebuilding; Arc 6 option) |

Rewards, once:
- Concord −300, and another −200 if the drones were reprogrammed.
- Corsairs +150 if the drones were reprogrammed.
- 600 cr for the archive, 200 cr for the drones. The lasers pay nothing.

Science DB with the archive: **Hollow true nature**, **Ashgrave Research** and **The Synthesis**
(`hollow_true_nature`, `ashgrave_research`, `synthesis_details`).

## Design notes

### The Annex fight

`BATTLE.annex` in `ee/ragtag/battle.lua`, tuned by `BATTLE.ANNEX`; the Battle Lab's Annex mode
(`scenarios/_battlelab`, parked) runs the same code. Positions are relative to the Annex.

- **Concord battle group** (`Concord Hostile`): seven ships, Atlantis X23 and Phobos T3 alternating,
  CNS *Vanguard* (Phobos T3) in the middle, which fights and dies like the rest. A line 15U north-west
  running north-east to south-west, 2U apart. No warp, no nukes, normalized speeds (Phobos 104,
  Atlantis 80). They defend five combat points 1.5U apart, 3U north-west of the Annex, and fight
  whoever is there; they don't chase the crew.
- **Drones** (reprogram; `Relic Active`): 24 MT52 Hornets, 18-damage lasers (3× stock), impulse 156,
  turn 30, acceleration 35, no warp. Half from the nebula 12.5U north-east, half from the one 11.5U
  south-west. One that dies is replaced from its own nebula within a second while any Concord ship is
  left.
- **The Annex's lasers**: three 360° beams, 4.5U range, 16 damage every 3 s (halved from 32 after a
  playtest where they took the fleet apart), aimed by script at the nearest Concord ship. They never
  fire on the crew.
- The fight uses the ordinary Boneyard nebulae.

### Relic Active

A faction added in `verse.lua`: hostile to Concord and Concord Hostile, neutral to Independent and
Corsairs. Used for the reprogrammed drones and the armed Annex.

### Hailing a drone

Every Relic drone answers a hail with one line of base64 (`VERSE.droneComms`): a threat
("PREPARE TO BE DESTROYED.") while it is the caller's enemy, a welcome ("WELCOME. PROCEED.") once
idled or reprogrammed. A joke for a crew that decodes it.

### The survivors

The survivor records are in-world testimony: the Annex's location, that the drones' IFF is slaved to
the Annex access net, that a Concord battle group is due to seal it, and a tease of the vault index
("Ashgrave Synthesis", "reversal protocol"). Quill worked the reversal program until it was shut down;
the technicians were never cleared for those folders. The entry is re-added at the start of each later
session.

### Hack threshold

EE decays every `hacked_level` by 1/180 per second before scripts run, so a finished hack reads just
under 1.0. The arc completes at `>= 0.99`.

### Patrols and rumors

- `PROX.suspendZone("the Boneyard")` when the hack lands; resumed at resolve and on cancel.
- `BONEYARD_HOOK` rumors in the hook phase; `BONEYARD_DONE` outcome rumors at resolve.

### History

- The warp jammer at the Annex was removed (2026-11-12).
- The archive is required for every ending now, so there are no Drones or Minimal endings.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/boneyard` (`tests/arcs/boneyard.lua`) plays the arc headless:
the hook, the hack, nothing until the survivors are home, no hack hints, late drones idled, no
operations undocked, the fleet arriving on the first dock, the operations and their locks, the download
stopping on undocking, spawn positions and speeds, drone replacement, the lasers' targeting, the
victory, the report at the right station only, rewards, the no-survivors ending and every GM state.
How the battle plays is tuned in the Battle Lab (scenario 63, Annex mode).
