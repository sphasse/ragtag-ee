# Boneyard Arc — Design Notes

## Summary

The crew breaches the Ashgrave Annex — a Concord Level-5 research archive buried in the Settlement War debris field — before a battle group arrives to lock it down permanently. The arc is combat-heavy, time-pressured, and reveals the core lore secret of the Drift.

## Trigger

- Rezkov arc finished (`rezkov_arc_done`) or declined (`rezkov_declined`)
- Upgrade investment ≥ 800 credits
- Not yet completed (`boneyard_arc_done` unset)
- Auto-starts; no reputation gate
- Rumors: ten vague "up north" seed rumors (priority 3) load as soon as the arc is enabled, via `M.on_load`, and are removed on start/disable. Three actionable hook rumors (priority 5) replace them in the hook phase and name Ashgrave and the Boneyard. No objective is set: crews have to follow the leads themselves.
- Jobs: five seed deliveries (priority 3) among Halcyon Rest, Port Vesper, Arbiter and Saint Brennan's load with the arc, via `JOBS.inject`. In the hook phase a priority-5 `story` salvage contract, an URGENT rescue of "a lifeboat of survivors" (350 cr, 20 minute clock, no reputation penalty), is offered at Port Vesper, Halcyon Rest and Saint Brennan's Mission (shared id `boneyard_buoy`), on the board only: no rumor and no objective. The pods spawn on the Boneyard south rim at (22, -72). Picking up the target pod fires `on_found`, which sets `boneyard_buoy_found` and logs that the survivors are archive staff locked out of Ashgrave, with Ashgrave's grid. A missed clock re-offers the job; once the survivors are recovered (flag `boneyard_buoy_found`, any session) it never returns. On pickup the survivors hail the ship through an `RT.voice` (an `Artifact` with no position: never on radar; ship-log fallback if comms are busy). The hail is a statement with nothing to answer: the speaker introduces herself as **Mara Quill, senior researcher at the Ashgrave Annex** (the voice is named "Mara Quill"), they upload their records and ask for the Annex ("Please get us out of here, but somebody needs to take a look at our records and come back and investigate. Those drones are whacko, but if the Annex could be hacked and all the research extracted, someone might actually be held accountable."), and a Science DB entry, Lore → "Boneyard Survivor Records", is added (re-added at the start of each later session). The entry is in-world testimony: the Annex's location, that the drones' IFF is slaved to the Annex access net, that a Concord battle group is expected soon to seal the Annex, and a tease of the vault index ("Ashgrave Synthesis", "reversal protocol"). Picking them up also stops the job's air clock (they are aboard and breathing: the job cannot fail on the way home). **Nothing more happens until they are home**: handing the job in at the station it came from (`on_complete`) sets `boneyard_survivors_home`, gives the "Hack the Annex" objective and makes the Annex appear. While they are aboard, even flying past Ashgrave reveals nothing. (A session that ends with them aboard counts them as taken home: the next session starts with the Annex out.) Whichever way the Annex appears (the survivors home, or 8U from Ashgrave without them), the arc moves straight to `annex_hack`.

## Phase Diagram

```
hook → annex_hack → annex_control → report → done
                         └──────────────────→ done   (no survivors were picked up: the fight is the end)
```

### hook
Rumor injection: Concord is mobilising a heavy response group, destination unknown. Rumors are re-injected each session while the arc is unfinished and removed on phase exit. The Ashgrave Annex spawns at (43, -104) verse coords (grid zz7), deeper in the debris field than the visible battle damage, in either of two ways: when the lifeboat survivors are brought home (their telemetry, logged at pickup, names the grid; in a later session it comes back at once), or, for a crew following the rumors instead, when they fly within 8U of Ashgrave (planet radius 3.4U). Spawning removes the hook rumors and the lifeboat job (the lead has paid off), and the arc moves straight to `annex_hack`.

### annex_hack
Entering the phase sets the objective "Hack the Annex" and nothing else: **no pop-up, no instructions**. The survivors' request is the prompt; working out how is the crew's puzzle. Hailing the Annex only says it is under an encrypted lockdown. Relay must hack the `frontshield` system to 100% (the crew sees it fall to 0%) (hacking is a Relay-screen function; each success adds 50% and it decays over 180 s, so two successes in a row). A probe parked near the Annex does not last (playtest: the drones kill probes), so in practice the crew has to get close, under the drones' fire, until the hack lands. At 50% a mid-hack science log fires: the files are marked Concord Level 5 — not a standard military installation. When the hack completes:
- Every Relic drone in the Boneyard goes Derelict and idle (the IFF is offline). They stay idle for the rest of the arc, and so does any Relic drone that turns up later (checked every 2 s until the arc ends)
- The Boneyard's three gun platforms (`PLATFORMS`, the universe's `gun_platforms`) go Derelict too and hold fire; a GM reset gives them back to the Relic with the drones
- Proximity spawns for the Boneyard are suspended
- The Annex turns `Relic Active` (no longer an enemy of the crew, so it can be docked; enemy of the Concord). Its comms say "Station security has been reset. Dock for more options."
- The objective becomes "Download Annex data"
- No warp jammer: the crew keeps warp throughout (removed 2026-11-12)

### annex_control
The Annex's operations are offered **only to a ship docked at it**. The Annex is an ordinary station: docked, it repairs the ship, shares energy and restocks probes.

**The first docking brings the fleet**: every console gets the pop-up "Incoming jump detected. A Concord battle fleet has arrived." and the Concord battle group appears (see "The Annex fight" below); CNS Vanguard orders all vessels to stand down.

Three operations, **one at a time** (while one is in progress the others show as [LOCKED]; **Refresh** redraws the menu with the current countdown, and every screen reached from it leads back to it):

| Operation | Time | Effect |
|---|---|---|
| 1) Download research archive | 5 min; 1 min once the fleet is gone | Sets `boneyard_hack_done`; unlocks the Science DB lore. **Needs the dock the whole time**: undocking stops it, and it starts again from the beginning |
| 2) Reprogram the drones to be hostile to the Concord | 60 s | Sets `boneyard_drone_flip`; 24 Relic drones launch from the two nebulae |
| 3) Enable station defense lasers | 60 s | Arms the Annex's lasers against the Concord |

When the download completes, a crew that never picked up the survivors gets the Hob's Landing pointer as a Science log line from the reversal folder (the Concord was very close to a cure; lead researcher Dr. Mara Quill; forwarding address Hob's Landing); with the survivors, Quill says it at the report. The reprogram and the lasers keep running if the crew undocks. The intended order is the drones first (the defence starts), then the lasers or the fight, then the archive: while the Concord fleet is out the download takes 5 minutes docked (`_DOWNLOAD_SLOW`). When the last Concord ship dies the Annex compresses the archive (log: "Archive compressed"): a download not yet started takes 1 minute (`_DOWNLOAD_FAST`), and one already running finishes within a minute of that moment.

When the last Concord ship dies, the Annex hails the crew once, "All Concord forces in proximity have been eliminated." (ship-log fallback if comms are busy), and the drones fall back to defend the Annex. If the archive is in but the fleet is not beaten, the objective is "Defeat Concord fleet".

With the archive downloaded **and** the fleet gone, the arc moves to `report`, or, for a crew that found the Annex without rescuing the survivors, straight to `done`. **Leaving the Boneyard** (20U outside it: 49U from its centre, `_LEAVE_R`) also ends the phase with whatever the crew has: with the archive (and the survivors rescued earlier) it moves to `report`, otherwise to `done` (no archive: no 600 cr; the fleet left alive: the "Concord swept the Boneyard" rumor). The GM also has `Destroy Concord`.

### report
The objective becomes "Report the success", and the log says to report to the lifeboat survivors at the station they were taken to (the rescue job's station, saved in `boneyard_survivors_at`; Port Vesper if unknown). Docked there, the station's menu offers "Talk with the lifeboat survivors": Quill (if the Concord fleet was destroyed: "You got the archive out, and a whole Concord battle group destroyed? That'll set them back."), who has now been through the reversal folder, says the Concord was very close to a cure, but the political fallout from building and deploying it would have been too great, and that they are headed to Hob's Landing to keep their work moving forward ("We heard they have some exceptional engineers there"): the hook for the planned Hob Works mission (`scenarios/sandbox/plan.md`). That ends the arc. The drones keep guarding the Annex until the cleanup after resolve.

### done / M.resolve
- `Concord` rep: -300 base, -200 extra if drones were reprogrammed
- `Corsairs` rep: +150 if drones were reprogrammed (enemy of their enemy)
- Credits: +600 for the data, +200 if drones flipped (the lasers pay nothing)
- Science DB: `hollow_true_nature`, `ashgrave_research`, `synthesis_details` unlocked
- The objective is cleared; outcome rumors seeded for the Maw arc; the Boneyard's patrols resume
- Remaining combat ships are cleaned up 120 seconds after resolve

## The Annex fight
`BATTLE.annex` in `ee/ragtag/battle.lua`, tuned by `BATTLE.ANNEX`; the Battle Lab's Annex mode (`scenarios/_battlelab`, parked) runs the same code. All positions are relative to the Annex.

- **Concord battle group** (`Concord Hostile`, targetable): seven ships, Atlantis X23 and Phobos T3 alternating, with `CNS Vanguard` (Phobos T3, an ordinary ship: it can be destroyed like the rest, which sets `boneyard_battlegroup_destroyed`) in the middle. They spawn active on a line 15U north-west of the Annex running north-east / south-west, 2U apart. No warp, no nukes; the Battle Lab's normalized speeds (Phobos 104, Atlantis 80 impulse). They defend five combat points 1.5U apart on a parallel line 3U north-west of the Annex and fight whoever is there; they do not chase the crew.
- The group spawns when the crew first docks at the Annex (the "jump" the pop-up announces).
- **Drones** (reprogram only; `Relic Active`): 24 MT52 Hornets, 18-damage lasers (3x a stock drone's 6), impulse 156 (1.5x the fastest Concord ship), turn 30, acceleration 35, no warp. Half come out of the Boneyard nebula north-east of the Annex (12.5U), half out of the one south-west (11.5U, clear of Ashgrave). A drone that dies is replaced from its own nebula within a second while any Concord ship is left. With the Concord gone they defend the Annex.
- **The Annex's lasers** (operation 3): the Annex turns `Relic Active`; three 360° beams, 4.5U range, 32 damage every 3 s, aimed by script at the nearest Concord ship in range. They never fire on the crew.
- The fight uses the ordinary Boneyard nebulae (placed from the universe's seed); none are added for it.

## Relic Active Faction
Added to `verse.lua`. Hostile to Concord / Concord Hostile, neutral to Independent and Corsairs. Used for the reprogrammed drones and the armed Annex.

## Hailing a drone
Every Relic drone (the universe's Boneyard garrisons, Boneyard patrols, the Annex fight's drones)
answers a hail with one line of base64 (`VERSE.droneComms`, `verse.lua`), picked at random: a
threat (`VERSE.DRONE_HOSTILE`, e.g. "PREPARE TO BE DESTROYED.") while it is the hailing ship's
enemy, a welcome (`VERSE.DRONE_NEUTRAL`, e.g. "WELCOME. PROCEED.") when it is not: idled by the
hack (Derelict) or reprogrammed (Relic Active). A joke for a crew that decodes it.

## Lore Payoff
If the archive is downloaded, Science gains three locked database entries:
- **Hollow true nature** — the Hollow are transformed human colonists from the Synthesis project
- **Ashgrave Research** — Project Ashgrave Synthesis, full timeline
- **The Synthesis** — compound properties, Phase II reversal protocol (seeds Maw arc)

## RT.flag Keys

| Key | Set When |
|---|---|
| `boneyard_arc_done` | Arc resolves |
| `boneyard_buoy_found` | Lifeboat survivors recovered |
| `boneyard_survivors_home` | The survivors were brought back to the rescue job's station (the Annex and the hack wait for it) |
| `boneyard_survivors_at` | The rescue job's station (where the crew reports) |
| `boneyard_hack_done` | Archive download completed |
| `boneyard_drone_flip` | IFF override completed |
| `boneyard_battlegroup_destroyed` | CNS Vanguard destroyed |

## Proximity Interactions
- `PROX.suspendZone("the Boneyard")` called when hack completes; `PROX.resumeZone` called in resolve and on_cancel
- Relic drones that enter the Boneyard after the hack are idled too, until the arc ends
- Two Concord battle group rumors injected at hook enter (category `BONEYARD_HOOK`); removed on hook exit and on cancel
- Outcome rumors injected at resolve (category `BONEYARD_DONE`)

## Testing
- `tools/game_tests.py --ee <EE dir> arcs/boneyard` plays the arc headless (`tests/arcs/boneyard.lua`): hook, hack,
  nothing until the survivors are home, no hack hints, late drones idled, no operations undocked, the fleet arriving on the first dock (its pop-up),
  the three operations and their locks, the download stopping on undocking, where and how fast everything spawns,
  drone replacement from the same nebula, the Annex's lasers picking a target, the victory, the report at the right
  station only, rewards, the no-survivors ending, and every GM state.
- How the battle plays out is tuned in the Battle Lab (scenario 63, Annex mode).

## GM jumps

Every `→` button goes through `MISSIONS.gmJump`: `M.gm_reset` destroys the Annex, the Concord group and the drones, restores flagged drones, cancels timers, removes rumors/jobs, resumes the zone, resets the state table and clears `boneyard_*` flags (`boneyard_buoy_found`, `boneyard_survivors_at` and `boneyard_survivors_home` only when jumping to Hook, so the lifeboat job is offered again); then `M.completed` replays earlier phases (hook: Annex spawned; annex_hack: drones idled, zone suspended, Annex dockable; annex_control: archive downloaded, fleet beaten, never spawned); then the target enters. `→ Annex control` lands before the first docking: the fleet arrives when the crew docks. `→ Report` marks the survivors as recovered if they were not. End states: Full (archive + drones) and Data (archive only); the archive is required now, so there are no Drones or Minimal endings. End states skip the replay so the world ends clean. `resolve` pays reputation and credits once (`boneyard_rewarded`), so jumping between end states does not pay twice. Reputation, credits and Science DB unlocks already given cannot be undone.

**Helper (Annex hack state): `Complete hack`.** Sets the Annex frontshield fully hacked, so the
phase completes normally on the next frame (drones idle, zone suspended, the Annex opens to docking)
and moves to Annex control. The ship is not moved.

**Helper (Annex control state): `Destroy Concord`.** Destroys every Concord ship left, once the
fleet has jumped in; the Annex's hail and the rest follow as in a won fight.

**Hack threshold.** EE decays every `hacked_level` by 1/180 per second before scripts run
(`shipsystemssystem.cpp`), so a finished hack reads just under 1.0 when the arc checks it. The
arc completes at `>= 0.99` (Rezkov's Galen hack uses the same threshold).
