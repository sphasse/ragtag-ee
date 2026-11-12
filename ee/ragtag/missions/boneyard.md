# Boneyard Arc — Design Notes

## Summary

The crew breaches the Ashgrave Annex — a Concord Level-5 research archive buried in the Settlement War debris field — before a battle group arrives to lock it down permanently. The arc is combat-heavy, time-pressured, and reveals the core lore secret of the Drift.

## Trigger

- Rezkov arc finished (`rezkov_arc_done`) or declined (`rezkov_declined`)
- Upgrade investment ≥ 800 credits
- Not yet completed (`boneyard_arc_done` unset)
- Auto-starts; no reputation gate
- Rumors: ten vague "up north" seed rumors (priority 3) load as soon as the arc is enabled, via `M.on_load`, and are removed on start/disable. Three actionable hook rumors (priority 5) replace them in the hook phase and name Ashgrave and the Boneyard. No objective is set: crews have to follow the leads themselves.
- Jobs: five seed deliveries (priority 3) among Halcyon Rest, Port Vesper, Arbiter and Saint Brennan's load with the arc, via `JOBS.inject`. In the hook phase a priority-5 `story` salvage contract, an URGENT rescue of "a lifeboat of survivors" (350 cr, 20 minute clock, no reputation penalty), is offered at Port Vesper, Halcyon Rest and Saint Brennan's Mission (shared id `boneyard_buoy`), on the board only: no rumor and no objective. The pods spawn on the Boneyard south rim at (22, -72). Picking up the target pod fires `on_found`, which sets `boneyard_buoy_found` and logs that the survivors are archive staff locked out of Ashgrave, with Ashgrave's grid. A missed clock re-offers the job; once the survivors are recovered (flag `boneyard_buoy_found`, any session) it never returns. On pickup the survivors hail the ship from a position-less `Artifact` (never on radar; ship-log fallback if comms are busy), and a Science DB entry, Lore → "Boneyard Survivor Records", is added (re-added at the start of each later session). The entry is in-world testimony: the Annex's location, that the drones' IFF is slaved to the Annex access net, that Concord will arrive within minutes and jam warp, and a tease of the vault index ("Ashgrave Synthesis", "reversal protocol"). The 8U Ashgrave proximity trigger still drives the phase change.

## Phase Diagram

```
hook → annex_hack → annex_control → extract → done
```

### hook
Rumor injection: Concord is mobilising a heavy response group, destination unknown. Rumors are re-injected each session while the arc is unfinished and removed on phase exit. The Ashgrave Annex spawns at (43, -104) verse coords (grid zz7), deeper in the debris field than the visible battle damage, in either of two ways: when the lifeboat survivors are recovered (their telemetry log names the grid), or, for a crew following the rumors instead, when they fly within 8U of Ashgrave (planet radius 3.4U). Spawning removes the hook rumors and the lifeboat job (the lead has paid off). Arc advances to `annex_hack` when the player closes to 2.5U of the Annex. There is no separate approach phase.

### annex_hack
Annex comms are encrypted. Relay must hack the `frontshield` system to 100% (hacking is a Relay-screen function; each success adds 50% and it decays over 180 s, so two successes in a row). At 50% a mid-hack science log fires: the files are marked Concord Level 5 — not a standard military installation. When hack completes:
- All Relic drones in Boneyard radius set to Derelict/idle (the IFF is offline)
- Concord battle group spawns at grid zy6 (30, -130 verse, ~26U NW of the Annex) at warp. Two ships (CNS Vanguard and the first escort) hunt the player; their orders are re-issued every 10 s (with no living player they defend the Annex). The other four Atlantis hold fixed posts on a ring 2U from the Annex (defend-location), so the group doesn't clump
- Proximity spawns for the Boneyard are suspended
- No warp jammer: the crew keeps warp throughout (removed 2026-11-12; the Concord fight is hard enough)

### annex_control
Comms on the Annex show two operations (Relay/Captain drives these):

| Operation | Time | Effect |
|---|---|---|
| Download research archive | 60s | Sets `boneyard_hack_done`; unlocks Science DB lore on completion |
| Reprogram drone IFF targets | 30s | Sets `boneyard_drone_flip`; idle drones flip to `Relic Active` and attack Concord; reinforcement wave of 8 drones warps in from the north |

The two operations run one at a time: while one is in progress the other shows as [LOCKED] and cannot be started. Once the drone override completes, destroyed friendly drones are replaced (one every 4 s, up to 20 alive and 40 replacements per battle, while any Concord ship survives), so the drones are a stream, not a one-off wave. Tuning constants: `_DRONE_TARGET_CAP`, `_DRONE_RESPAWN_MAX`, `_DRONE_RESPAWN_GAP`, `_CIRCLE_R`, `_HUNTERS` in `boneyard.lua`. Replacements warp in from the north (the same spawn points as the first wave).

The player can attempt both, one after the other. Battle group arrives in ~85 seconds. The first operation the player completes determines the dominant outcome.

### extract
Player must exit the Boneyard boundary (29U radius from center 36, -96). Warp stays available. The command ship `CNS Vanguard` is `setCanBeDestroyed(false)` until hull falls below 20%, at which point it becomes vulnerable and flags `boneyard_battlegroup_destroyed`.

Remaining combat ships clean up 120 seconds after resolve.

### done / M.resolve
- `Concord` rep: -300 base, -200 extra if drones were reprogrammed
- `Corsairs` rep: +150 if drones were reprogrammed (enemy of their enemy)
- Credits: +600 if data downloaded, +200 if drones flipped
- Science DB: `hollow_true_nature`, `ashgrave_research`, `synthesis_details` unlocked if data downloaded
- Outcome rumors seeded for the Maw arc

## Concord Battle Group
1× Phobos T3 (`CNS Vanguard`, command) + 5× Atlantis X23 (escort). All `Concord Hostile` faction — targetable by player. Command ship invulnerable until < 20% hull.

## Relic Active Faction
Added to `verse.lua`. Hostile to Concord / Concord Hostile, neutral to Independent and Corsairs. Used for reprogrammed drones and reinforcement wave.

## Reinforcement Wave (reprogram only)
8 ships (`4× WX-Lindworm`, `2× Stalker Q7`, `2× Stalker R7`) spawn ~35U south of Annex (43, -139 verse), outside scan range. `setWarpDrive(true)` — arrive in ~35 seconds. Faction: `Relic Active`.

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
- GM skip buttons cover all phase transitions
- `→ Complete arc` sets both `boneyard_hack_done` and `boneyard_drone_flip` for the full outcome
- Confirm: idle drones go `Derelict` on hack complete; faction `Relic Active` exists before reprogram fires
- Confirm: `tools/check.py` passes after adding `require` to `missions.lua`

## GM jumps

Every `→` button goes through `MISSIONS.gmJump`: `M.gm_reset` destroys the Annex, Concord group and reinforcement drones, restores flagged drones, cancels timers, removes rumors/jobs, resumes the zone, resets the state table and clears `boneyard_*` flags (`boneyard_buoy_found` only when jumping to Hook, so the lifeboat job is offered again); then `M.completed` replays earlier phases (hook: Annex spawned; annex_hack: drones idled, zone suspended, Concord group spawned); then the target enters. End states skip the replay so the world ends clean. `resolve` pays reputation and credits once (`boneyard_rewarded`), so jumping between end states does not pay twice. Reputation, credits and Science DB unlocks already given cannot be undone.
