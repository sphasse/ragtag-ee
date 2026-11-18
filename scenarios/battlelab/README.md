# Battle Lab (scenario 63)

A test bed for the campaign's set-piece battles (the Boneyard's Annex fight, the Corsair battle at
the wall): a few tough Concord ships against a larger force of lighter Corsair ships, with the crew
on the Corsair side. Open space, no universe, its own save (`battlelab`), never the campaign's.

## The set-up
- A centre point (0, 0) and six **battle positions** evenly spaced around it (default 3U out).
- **Concord** (`Concord Hostile`, default 5): a line 10U west of the centre, 2U apart. Hulls by slot:
  Atlantis X23, Phobos T3, Phobos T3, Atlantis X23, Phobos T3, ... (no nukes).
- **Corsairs** (`Corsair Friendly`, default 12): a 120° arc 10U east of the centre. Hulls by slot:
  Adder MK5, Adder MK5, Piranha F12, ...
- The crew's Light Freighter starts 13U east, behind the arc. Ships made on the "Create player ship"
  screen join beside it.
- No warp or jump drive for any NPC; impulse at 1.5x each hull's normal by default.
- Each side's ships **defend the six positions**, spread round-robin over a random order of them,
  so the fight stays spread out instead of collapsing into one mass.
- When one side is wiped out, the time and survivors go to the GM and the crew.

## GM console
- **Battle status**: time, survivors per side, and how many of each side hold each position.
- **Reset battle (apply settings)**: clear the field and start again with the current settings.
- **Reshuffle positions**: every ship gets a new position now (useful when a battle's survivors
  sit apart and the fight stalls).
- **Concord impulse x1.50** / **Corsair impulse x1.50**: cycle 1.0, 1.25, 1.5, 1.75, 2.0, 2.5;
  applies at once.
- **Positions at 3U**: cycle 2, 3, 4, 5, 6, 8 (applies on reset).
- **Concord ships** / **Corsair ships** with +1 / -1 (1–12 and 1–24; apply on reset).

To try other hull mixes, edit `CONCORD_HULLS` / `CORSAIR_HULLS` at the top of the scenario.

Headless (default settings, 2026-11-18): the sides meet after about a minute; after 7 minutes it
was 1 Concord ship of 5 against 4 Corsairs of 12, with a long tail as the last survivors sat at
different positions.
