# Set-piece battles: large groups of NPC ships

What the Corsair battle at Blackwater, the Boneyard's Annex fight and many Battle Lab sessions taught
about fights between groups of 5–30 AI ships. Use the shared code (`ee/ragtag/battle.lua`, `BATTLE`)
instead of writing orders by hand, and tune in the Battle Lab (scenario 63) before touching the arc.

## Why the stock AI needs help

- **Groups collapse into one ball.** Every ship told to attack (or defend the same spot) converges on
  one point. Ships then shoot through each other (friendly fire), the fight becomes one unreadable
  blob, and a handful of tough ships in the middle can't be broken.
- **Heavy ships arrive late.** Stock impulse runs from 30 (Atlantis X23) to 120 (fighters), turn rate
  from 3.5 to 30 °/s. The light ships fight alone for a minute before the heavies arrive.
- **Long tails.** When a ship's own target dies, it often idles or wanders; the last few survivors
  sit at opposite ends of the field and the battle never ends.
- **Beamless missile boats leave.** The Piranha F12 has only broadside tubes. The stock AI keeps it
  2.5–4U off, and once it is out of missiles sends it off to find a restock: it drifts out of the fight.
- **Warp makes arrivals instant and chaotic.** A group warping in lands all at once on top of the
  crew; there is no build-up. (The Ledger arc's accountants had the same problem: playtesters asked
  for a fast impulse approach instead.)
- **`orderFlyTowards` takes coordinates, not an entity.** Passing a station once sent the Boneyard
  battle group roaming off toward independent traffic.

## The rules BATTLE applies

1. **Combat points.** A few invisible points (5 has worked well), 1.5U apart, on a line. Every
   ship *defends one point* (`orderDefendLocation`): it goes there and engages anything hostile nearby.
   The battle keeps track of which ship targets which point.
2. **Proportional lanes.** Each side's ships, ordered along the line by where they start, are mapped
   proportionally onto the points (the northernmost ships take point 1, ...). Ships fly straight
   across instead of through each other's lanes, and both sides cover every point. The line can run
   any direction (`line_heading`; the Annex's runs at 45°).
3. **Retargeting.** Every 2 s, a ship whose point has no living enemy targeting it moves to the
   nearest point that still has some (random on a tie). This removes the long tail.
4. **Normalized speeds.** Each hull's impulse, turn and acceleration are mapped linearly from the
   range the battle's hulls have stock onto `BATTLE.NORM` (impulse 80–120, turn 15–28, accel 15–25).
   The slowest hull gets the low end, the fastest the high end, so heavies still feel heavy but
   arrive in time. `BATTLE.HULL_TWEAKS` adjusts single hulls (the Piranha gets 1.3x turn and accel
   to swing its broadsides round). Concord groups normalize over `BATTLE.REF_HULLS` (the Battle Lab's
   hulls), so the Concord flies the same in every battle (Atlantis 80, Phobos 104).
5. **No warp or jump drive** for any battle ship. Distance and impulse set the arrival time.
6. **Missile top-ups** for sides listed in `topup`: at 25% of their racks a ship is refilled. Keeps
   the missile boats in the fight.
7. **No nukes** for the Concord: one nuke into a packed line wrecks its own side and the crew.
8. **Waiting ships are frozen, not idle.** Ships spawned before `start()` have impulse and turn rate
   0. Playtest: idle ships drift round to face away and then take a long time to swing back.
   Use a frozen start when the fight should begin on a trigger (Blackwater: the crew within 5U).
   Spawn active (the Annex) when the approach itself is the build-up.
9. **Late joiners** (spawned after `start()`) take the nearest point that has live enemies. After
   spawning a whole group at once, call `b:assign(side)` to re-deal it proportionally.
10. **Stat overrides** per ship (`spawn(..., over)`: impulse, turn, accel, beam_damage) for a
   special side, like the Annex's fast drones.

## Designing a battle

- **Pick factions so allies never hurt the crew**: a side fighting for the crew should be enemies
  only with the opponent (`Corsair Friendly`, `Relic Active`), not with Independent.
- **Spawn clear of terrain**: lines and spawn gates must keep off planets (radius + 2U), mine
  rings, and asteroid clusters. A Blackwater mine ring once killed a gunboat on its spawn slot; mine
  lanes need a margin. Check positions in the test.
- **Approach distance sets the tension.** 15U at impulse 80–104 is about 2 minutes. Compare it with
  whatever the crew is doing meanwhile (the Annex's operations: 60 s, 60 s, 4 min).
- **A stream beats a wave.** A fixed group against a stream of replacements (a dead drone is replaced
  from the gate it came from, while any enemy is left) gives a steady pressure and a clear end.
- **Spawn gates in cover.** Drones coming out of a nebula appear without warning; use existing
  clouds where possible (`VERSE.nebulaSpots` gives the seeded positions). Adding a nebula field to
  the universe data shifts every asteroid in the Drift (same random sequence).
- **Damage, not regen, is the usual problem.** 24 drones with 12-damage lasers could not break an
  Atlantis X23 (shields recharge between the drones' 4 s cycles). 18 did. Tune damage first.
- **Stations can fight.** A `SpaceStation` takes beams (`setBeamWeapon`, 360° arcs) but has no AI
  to aim them: set `station.components.weapons_target = {entity = ship}` from script (once a second,
  nearest enemy in range) and set heat and energy per shot to 0. Change its faction so it can't hit
  the crew (`BATTLE.annex`'s `armAnnex` / `aimLasers`).
- **Give the crew real levers.** The best fights let the crew change the outcome: hacking the big
  ships, choosing the order of the Annex's operations, a tender to rearm alongside.
- **Say when it's over.** Hail the crew when the last enemy dies (with a ship-log fallback: comms are
  often busy in a battle), and say what's left to do. Then send the survivors home (fly off and
  despawn after a few minutes) or have them guard something; never leave a frozen field.
- **Defeat needs a listener too** (the Corsair arc ends on `ship_lost` for the primary ship).

## The code

```lua
local b = BATTLE.new{x = cx, y = cy, points = 5, spacing_u = 1.5, line_heading = 180,
                     hulls = {...}, norm_hulls = BATTLE.REF_HULLS, topup = {"b"}}
b:spawn("a", "Atlantis X23", "Concord Hostile", "CNS Writ", x, y, 90)    -- frozen until start()
b:start()
-- every frame:
b:tick(getScenarioTime())
b:alive("a"); b:ships("b"); b:clear()
```

`BATTLE.annex(station)` wraps a whole scenario around one station (spawnConcord, spawnDrones,
armAnnex, tick, clear). Write a wrapper like it when the battle has more moving parts than two
lines, and run it from both the arc and the Battle Lab, so balancing done in the lab carries over.

## Battle Lab and testing

The labs are parked in `scenarios/_battlelab/` (not installed). Rename the folder to `battlelab` and run
`tools/install.py` to use them again.

- The Battle Lab (scenario 63) has an open-space mode (Concord vs Corsairs) and the Annex mode. Its GM
  buttons spawn each side separately, change counts and impulse multipliers, and report who targets
  which point. New battles should get a mode or buttons there.
- The Audit Lab (scenario 64) replays the Ledger arc's audit stop from the last fragment (`AUDIT` in
  `missions/_audit.lua`): the same pattern for a smaller encounter with a script (stop, hail, stalls).
- Balance by playtesting in the lab: headless runs are long and their outcomes vary from run to run.
- The arc's test checks what is deterministic: who spawns where (line, angle, distance), speeds,
  beam damage, no warp, factions, replacement from the same gate, a station picking a target, the
  victory message firing. It doesn't check who wins.
