# Battle Lab (scenario 63)

A test bed for the campaign's set-piece battles (the Boneyard's Annex fight, the Corsair battle at
the wall): a few tough Concord ships against a larger force of lighter Corsair ships, with the crew
on the Corsair side. Open space, no universe, its own save (`battlelab`), never the campaign's.

## The set-up
- A centre point (0, 0) and five invisible **combat points** on a north-south line through it,
  1.5U apart by default (the middle one on the centre).
- **Concord** (`Concord Hostile`, default 5): a line 10U west of the centre, 2U apart. Hulls by slot:
  Atlantis X23, Phobos T3, Phobos T3, Atlantis X23, Phobos T3, ... (no nukes).
- **Corsairs** (`Corsair Friendly`, default 12): a 120° arc 10U east of the centre. Hulls by slot:
  Adder MK5, Adder MK5, Piranha F12, ...
- The crew's Light Freighter starts 13U east, behind the arc. Ships made on the "Create player ship"
  screen join beside it.
- No warp or jump drive for any NPC; impulse at 1.5x each hull's normal by default.
- Every ship, on both sides, **defends one combat point**, and the scenario keeps track of which.
  At the start each side is dealt round-robin over a random order of the points, so both sides
  cover all five and the fight stays spread out instead of collapsing into one mass.
- Every 2 s, a ship whose point has no living enemy targeting it any more moves to a random point
  that still has some.
- When one side is wiped out, the time and survivors go to the GM and the crew.

## GM console
- **Battle status**: time, survivors per side, how many of each side target each point (north to
  south), and how many times ships have moved to a new point.
- **Reset battle (apply settings)**: clear the field and start again with the current settings.
- **Reshuffle positions**: deal every ship a new point now.
- **Concord impulse x1.50** / **Corsair impulse x1.50**: cycle 1.0, 1.25, 1.5, 1.75, 2.0, 2.5;
  applies at once.
- **Points 1.5U apart: closer / further**: the spacing between points, 0.5U steps from 0.5 to 6U;
  applies at once (every ship goes to its point's new place).
- **Concord ships** / **Corsair ships** with +1 / -1 (1–12 and 1–24; apply on reset).

To try other hull mixes, edit `CONCORD_HULLS` / `CORSAIR_HULLS` at the top of the scenario.

First version (six points in a ring 3U out, no retargeting), headless: the sides met after about a
minute; after 7 minutes 1 Concord ship of 5 against 4 Corsairs of 12, with a long tail as the last
survivors sat at different points. Retargeting is meant to remove that tail.
