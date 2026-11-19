# Battle Lab (scenario 63)

A test bed for the campaign's set-piece battles, in two modes (switched from the GM screen). Its own
save (`battlelab`), never the campaign's; no universe beyond what each mode needs.

## Annex mode (the default): the Boneyard arc's climax
Ashgrave, the Ashgrave Annex and the Boneyard's six nebulae, at their real places in the Drift (the
nebulae come from the universe's seed, so they are the campaign's clouds). The crew's Light Freighter
starts 2U south-east of the Annex. The fight is `BATTLE.annex` in `ee/ragtag/battle.lua`, the same code
the Boneyard arc runs, tuned by `BATTLE.ANNEX`:

- **Concord** (`Concord Hostile`, default 7): spawns active on a line 15U north-west of the Annex,
  running north-east / south-west, 2U apart, facing the Annex. Atlantis X23 and Phobos T3
  alternating; the middle one is CNS Vanguard (Phobos T3). No warp, no nukes, the open-space mode's
  speeds (normalized over `BATTLE.REF_HULLS`: Atlantis 80, Phobos 104 impulse).
- **Combat points**: five, 1.5U apart, on a line 3U north-west of the Annex running the same way.
- **Drones** (`Relic Active`: enemies of the Concord only, default 24): MT52 Hornets with 18-damage
  lasers (3x a stock drone's 6), impulse 156 (1.5x the fastest Concord ship), turn 30, acceleration
  35, no warp. Half come out of the nebula north-east of the Annex (12.5U), half out of the one
  south-west (11.5U, clear of Ashgrave). Every drone that dies is replaced from its own nebula
  (checked every second) while any Concord ship is left. When the last Concord ship dies, the drones
  fall back to defend the Annex (spawning more Concord sends them back to the points).
- **The Annex's lasers** arm with the drones: the Annex turns `Relic Active` and its three beams
  (360°, 4.5U, 32 damage every 3 s) fire on the nearest Concord ship in range.

GM console: **Battle status** (survivors, drones per nebula, replacements, what the Annex is firing at,
ships per point), **Start (Concord + drones)**, **Spawn Concord (n)** and **Spawn drones (n)** separately
(hold the drones back for tension), **Clear the battle**, **Concord +1 / -1** (1–12), **Drones +2 / -2**
(2–48), **Concord impulse** and **Drone impulse** multipliers (apply at once), and **Mode: Annex -> open
space**. When the last Concord ship dies, the time and drone losses go to the GM and the crew.

## Open-space mode: Concord against Corsairs

### The set-up
- A centre point (0, 0) and five invisible **combat points** on a north-south line through it,
  1.5U apart by default (the middle one on the centre).
- **Concord** (`Concord Hostile`, default 5): a line 10U west of the centre, 2U apart. Hulls by slot:
  Atlantis X23, Phobos T3, Phobos T3, Atlantis X23, Phobos T3, ... (no nukes).
- **Corsairs** (`Corsair Friendly`, default 12): a line 10U east of the centre, 2U apart. Hulls by slot:
  Adder MK5, Adder MK5, Piranha F12, ...
- Switching to this mode starts a battle and moves the crew's Light Freighter 13U east, behind the Corsair line. Ships made on the "Create player ship"
  screen join beside it.
- No warp or jump drive for any NPC.
- **Speeds are normalized.** Each hull's impulse, turn rate and acceleration are mapped linearly
  from the range the lab's hulls have stock onto 80–120 impulse, 15–28 °/s and 15–25 acceleration
  (`BATTLE.NORM` in `ee/ragtag/battle.lua`): the slowest hull gets the low end, the fastest the high end.

  | Hull | Stock | Normalized |
  |---|---|---|
  | Adder MK5 | 80 / 28 / 25 | 120 / 28 / 25 |
  | Phobos T3 | 60 / 10 / 10 | 104 / 18.4 / 17.5 |
  | Piranha F12 | 40 / 6 / 8 | 88 / 16.3 / 16.5 |
  | Atlantis X23 | 30 / 3.5 / 5 | 80 / 15 / 15 |

  On top of that, `BATTLE.HULL_TWEAKS` adjusts single hulls: the Piranha F12 gets x1.3 turn and
  acceleration (21.2 °/s, 21.5) so it can swing its broadsides round. The impulse multipliers
  (default x1.0) scale the result.
- Every ship, on both sides, **defends one combat point**, and the scenario keeps track of which.
  Each side's ships, ordered north to south, are mapped **proportionally** onto the points (also
  north to south): the northernmost ships take point 1, the middle ones the middle point, the
  southernmost point 5. Ships head straight across instead of through each other's lanes (less
  friendly fire), and both sides cover all five points.
- Every 2 s, a ship whose point has no living enemy targeting it any more moves to the **nearest**
  point (along the line) that still has some; a tie is broken at random.
- **Corsair missile top-ups:** a Corsair ship down to a quarter of its missiles is refilled to full
  (checked every 2 s). The Piranhas have only broadside tubes and no beams; the stock AI keeps them
  2.5–4U off and, once a beamless ship is out of missiles, sends it off to look for a restock, so
  without top-ups they drift out of the fight.
- When one side is wiped out, the time and survivors go to the GM and the crew.

### GM console
- **Battle status**: time, survivors per side, Corsair missile top-ups, each hull's normalized and stock speeds, how many of
  each side target each point (north to south), and how many times ships have moved to a new point.
- **Reset battle (apply settings)**: clear the field and start again with the current settings.
- **Re-deal points by position**: redo the proportional mapping from where the ships are now.
- **Concord impulse x1.00** / **Corsair impulse x1.00**: cycle 1.0, 1.25, 1.5, 1.75, 2.0, 2.5 on
  top of the normalized impulse; applies at once.
- **Points 1.5U apart: closer / further**: the spacing between points, 0.5U steps from 0.5 to 6U;
  applies at once (every ship goes to its point's new place).
- **Concord ships** / **Corsair ships** with +1 / -1 (1–12 and 1–24; apply on reset).
- **Mode: open space -> Annex**: clears the field and moves the crew back to the Annex.

To try other hull mixes, edit `CONCORD_HULLS` / `CORSAIR_HULLS` at the top of the scenario. The battle
rules (normalization `BATTLE.NORM`, `BATTLE.HULL_TWEAKS`, points, retargeting, top-ups) live in
`ee/ragtag/battle.lua`, shared with the Corsair arc's battle at Blackwater, so tuning found here
carries over.

First version (six points in a ring 3U out, no retargeting), headless: the sides met after about a
minute; after 7 minutes 1 Concord ship of 5 against 4 Corsairs of 12, with a long tail as the last
survivors sat at different points. Retargeting is meant to remove that tail.
