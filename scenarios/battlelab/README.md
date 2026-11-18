# Battle Lab (scenario 63)

A test bed for the campaign's set-piece battles (the Boneyard's Annex fight, the Corsair battle at
the wall): a few tough Concord ships against a larger force of lighter Corsair ships, with the crew
on the Corsair side. Open space, no universe, its own save (`battlelab`), never the campaign's.

## The set-up
- A centre point (0, 0) and five invisible **combat points** on a north-south line through it,
  1.5U apart by default (the middle one on the centre).
- **Concord** (`Concord Hostile`, default 5): a line 10U west of the centre, 2U apart. Hulls by slot:
  Atlantis X23, Phobos T3, Phobos T3, Atlantis X23, Phobos T3, ... (no nukes).
- **Corsairs** (`Corsair Friendly`, default 12): a line 10U east of the centre, 2U apart. Hulls by slot:
  Adder MK5, Adder MK5, Piranha F12, ...
- The crew's Light Freighter starts 13U east, behind the Corsair line. Ships made on the "Create player ship"
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

## GM console
- **Battle status**: time, survivors per side, Corsair missile top-ups, each hull's normalized and stock speeds, how many of
  each side target each point (north to south), and how many times ships have moved to a new point.
- **Reset battle (apply settings)**: clear the field and start again with the current settings.
- **Re-deal points by position**: redo the proportional mapping from where the ships are now.
- **Concord impulse x1.00** / **Corsair impulse x1.00**: cycle 1.0, 1.25, 1.5, 1.75, 2.0, 2.5 on
  top of the normalized impulse; applies at once.
- **Points 1.5U apart: closer / further**: the spacing between points, 0.5U steps from 0.5 to 6U;
  applies at once (every ship goes to its point's new place).
- **Concord ships** / **Corsair ships** with +1 / -1 (1–12 and 1–24; apply on reset).

To try other hull mixes, edit `CONCORD_HULLS` / `CORSAIR_HULLS` at the top of the scenario. The battle
rules (normalization `BATTLE.NORM`, `BATTLE.HULL_TWEAKS`, points, retargeting, top-ups) live in
`ee/ragtag/battle.lua`, shared with the Corsair arc's battle at Blackwater, so tuning found here
carries over.

First version (six points in a ring 3U out, no retargeting), headless: the sides met after about a
minute; after 7 minutes 1 Concord ship of 5 against 4 Corsairs of 12, with a long tail as the last
survivors sat at different points. Retargeting is meant to remove that tail.
