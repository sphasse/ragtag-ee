# Boneyard Arc — Design Notes

## Summary

The crew breaches the Ashgrave Annex — a Concord Level-5 research archive buried in the Settlement War debris field — before a battle group arrives to lock it down permanently. The arc is combat-heavy, time-pressured, and reveals the core lore secret of the Drift.

## Trigger

- Rezkov arc finished (`rezkov_arc_done`) or declined (`rezkov_declined`)
- Upgrade investment ≥ 800 credits
- Not yet completed (`boneyard_arc_done` unset)
- Auto-starts; no reputation gate
- Rumors: ten vague "up north" seed rumors (priority 3) load as soon as the arc is enabled, via `M.on_load`, and are removed on start/disable. Three actionable hook rumors (priority 5) replace them in the hook phase and name Ashgrave and the Boneyard. No objective is set: crews have to follow the leads themselves.
- Jobs: five seed deliveries (priority 3) among Halcyon Rest, Port Vesper, Arbiter and Saint Brennan's load with the arc, via `JOBS.inject`. In the hook phase a priority-5 `story` salvage contract, an URGENT rescue of "a lifeboat of survivors" (350 cr, 20 minute clock, no reputation penalty), is offered at Port Vesper, Halcyon Rest and Saint Brennan's Mission (shared id `boneyard_buoy`), on the board only: no rumor and no objective. The pods spawn on the Boneyard south rim at (22, -72). Picking up the target pod fires `on_found`, which sets `boneyard_buoy_found` and logs that the survivors are archive staff locked out of Ashgrave, with Ashgrave's grid. A missed clock re-offers the job; once the survivors are recovered (flag `boneyard_buoy_found`, any session) it never returns. On pickup the survivors hail the ship from a position-less `Artifact` (never on radar; ship-log fallback if comms are busy), and a Science DB entry, Lore → "Boneyard Survivor Records", is added (re-added at the start of each later session). The entry is in-world testimony: the Annex's location, that the drones' IFF is slaved to the Annex access net, that a Concord battle group is expected soon to seal the Annex, and a tease of the vault index ("Ashgrave Synthesis", "reversal protocol"). The 8U Ashgrave proximity trigger still drives the phase change.

## Phase Diagram

```
hook → annex_hack → annex_control → done   (leaving the Boneyard ends annex_control)
```

### hook
Rumor injection: Concord is mobilising a heavy response group, destination unknown. Rumors are re-injected each session while the arc is unfinished and removed on phase exit. The Ashgrave Annex spawns at (43, -104) verse coords (grid zz7), deeper in the debris field than the visible battle damage, in either of two ways: when the lifeboat survivors are recovered (their telemetry log names the grid), or, for a crew following the rumors instead, when they fly within 8U of Ashgrave (planet radius 3.4U). Spawning removes the hook rumors and the lifeboat job (the lead has paid off). Arc advances to `annex_hack` when the player closes to 2.5U of the Annex. There is no separate approach phase.

### annex_hack
Annex comms are encrypted. Relay must hack the `frontshield` system to 100% (hacking is a Relay-screen function; each success adds 50% and it decays over 180 s, so two successes in a row). At 50% a mid-hack science log fires: the files are marked Concord Level 5 — not a standard military installation. When hack completes:
- All Relic drones in Boneyard radius set to Derelict/idle (the IFF is offline); they stay idle for the rest of the arc
- The Concord battle group spawns (see "The Annex fight" below) and CNS Vanguard orders all vessels to stand down
- Proximity spawns for the Boneyard are suspended
- No warp jammer: the crew keeps warp throughout (removed 2026-11-12)

### annex_control
Comms on the Annex offer three operations (Relay/Captain drives these). They run **one at a time**: while one is in progress the others show as [LOCKED].

| Operation | Time | Effect |
|---|---|---|
| 1) Download research archive | 4 min | Sets `boneyard_hack_done`; unlocks the Science DB lore |
| 2) Reprogram drone IFF targets | 60 s | Sets `boneyard_drone_flip`; 24 Relic drones launch from the two nebulae |
| 3) Enable station defense lasers | 60 s | Arms the Annex's lasers against the Concord |

The order decides the fight: the Concord group is already on its way when the menu opens (about 2 minutes to its points), the drones and lasers only help once their operation finishes, and the long download keeps the crew at the Annex for most of the battle. The operations are `_OPS` in `boneyard.lua`.

When the last Concord ship dies, the Annex hails the crew once ("All Concord battle group ships destroyed. Perimeter clear. You can leave the Boneyard when ready.", with a warning if the download is unfinished; ship-log fallback if comms are busy) and the drones fall back to defend the Annex.

The phase ends, finished or not, when the crew leaves the Boneyard (29.5U from its centre, 36, -96). Warp stays available. Remaining combat ships are cleaned up 120 seconds after resolve.

### done / M.resolve
- `Concord` rep: -300 base, -200 extra if drones were reprogrammed
- `Corsairs` rep: +150 if drones were reprogrammed (enemy of their enemy)
- Credits: +600 if data downloaded, +200 if drones flipped (the lasers pay nothing)
- Science DB: `hollow_true_nature`, `ashgrave_research`, `synthesis_details` unlocked if data downloaded
- The objective is cleared; outcome rumors seeded for the Maw arc

## The Annex fight
`BATTLE.annex` in `ee/ragtag/battle.lua`, tuned by `BATTLE.ANNEX`; the Battle Lab's Annex mode (`scenarios/_battlelab`, parked) runs the same code. All positions are relative to the Annex.

- **Concord battle group** (`Concord Hostile`, targetable): seven ships, Atlantis X23 and Phobos T3 alternating, with `CNS Vanguard` (Phobos T3, an ordinary ship: it can be destroyed like the rest, which sets `boneyard_battlegroup_destroyed`) in the middle. They spawn active on a line 15U north-west of the Annex running north-east / south-west, 2U apart. No warp, no nukes; the Battle Lab's normalized speeds (Phobos 104, Atlantis 80 impulse). They defend five combat points 1.5U apart on a parallel line 3U north-west of the Annex and fight whoever is there; they do not chase the crew.
- **Drones** (reprogram only; `Relic Active`): 24 MT52 Hornets, 18-damage lasers (3x a stock drone's 6), impulse 156 (1.5x the fastest Concord ship), turn 30, acceleration 35, no warp. Half come out of the Boneyard nebula north-east of the Annex (12.5U), half out of the one south-west (11.5U, clear of Ashgrave). A drone that dies is replaced from its own nebula within a second while any Concord ship is left. With the Concord gone they defend the Annex.
- **The Annex's lasers** (operation 3): the Annex turns `Relic Active`; three 360° beams, 4.5U range, 32 damage every 3 s, aimed by script at the nearest Concord ship in range. They never fire on the crew.
- The fight uses the ordinary Boneyard nebulae (placed from the universe's seed); none are added for it.

## Relic Active Faction
Added to `verse.lua`. Hostile to Concord / Concord Hostile, neutral to Independent and Corsairs. Used for the reprogrammed drones and the armed Annex.

## Lore Payoff
If the archive is downloaded, Science gains three locked database entries:
- **Hollow true nature** — the Hollow are transformed human colonists from the Synthesis project
- **Ashgrave Research** — Project Ashgrave Synthesis, full timeline
- **The Synthesis** — compound properties, Phase II reversal protocol (seeds Maw arc)

## RT.flag Keys

| Key | Set When |
|---|---|
| `boneyard_arc_done` | Arc resolves |
| `boneyard_hack_done` | Archive download completed |
| `boneyard_drone_flip` | IFF override completed |
| `boneyard_battlegroup_destroyed` | CNS Vanguard destroyed |

## Proximity Interactions
- `PROX.suspendZone("the Boneyard")` called when hack completes; `PROX.resumeZone` called in resolve and on_cancel
- Two Concord battle group rumors injected at hook enter (category `BONEYARD_HOOK`); removed on hook exit and on cancel
- Outcome rumors injected at resolve (category `BONEYARD_DONE`)

## Testing
- `tools/game_tests.py --ee <EE dir> arcs/boneyard` plays the arc headless (`tests/arcs/boneyard.lua`): hook, hack,
  the three operations and their locks, where and how fast everything spawns, drone replacement from the same
  nebula, the Annex's lasers picking a target, the victory hail, leaving the Boneyard, rewards, and every GM state.
- How the battle plays out is tuned in the Battle Lab (scenario 63, Annex mode).

## GM jumps

Every `→` button goes through `MISSIONS.gmJump`: `M.gm_reset` destroys the Annex, the Concord group and the drones, restores flagged drones, cancels timers, removes rumors/jobs, resumes the zone, resets the state table and clears `boneyard_*` flags (`boneyard_buoy_found` only when jumping to Hook, so the lifeboat job is offered again); then `M.completed` replays earlier phases (hook: Annex spawned; annex_hack: drones idled, zone suspended, Concord group spawned); then the target enters. End states skip the replay so the world ends clean. `resolve` pays reputation and credits once (`boneyard_rewarded`), so jumping between end states does not pay twice. Reputation, credits and Science DB unlocks already given cannot be undone.

**Helper (Annex hack state): `Complete hack`.** Sets the Annex frontshield fully hacked, so the
phase completes normally on the next frame (drones idle, zone suspended, Concord battle group
inbound) and moves to Annex control. If the ship is more than 5U from the Annex it is first moved
to 2U south of it, where a real hack would have left it.

**Hack threshold.** EE decays every `hacked_level` by 1/180 per second before scripts run
(`shipsystemssystem.cpp`), so a finished hack reads just under 1.0 when the arc checks it. The
arc completes at `>= 0.99` (Rezkov's Galen hack uses the same threshold).
