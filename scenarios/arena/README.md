# Combat Arena (scenario 65)

A balancing range for multiplayer sessions: what is a fair fight for one, two or more crews with a given set
of upgrades? Open space, no universe, no jobs or arcs, nothing saved. The rules are in `ee/ragtag/arena.lua`
(`ARENA`); its test is `tests/core/arena.lua`.

## Setting up
- Crews join from the **Create player ship** list ("Light Freighter: Raven" ...), in a line at the centre.
  A ship lost in a fight and made again under the same name keeps the upgrades the GM gave it.
- **Ship Upgrades...**: pick a ship, then grant or revoke any upgrade (the campaign's own menu; Ship Status
  shows its numbers).

## A round
1. **Enemies...**: the armed AI ship types the Drift uses (from `SCIDB.SHIPS_USED`). Pick one to add +1 / +5,
   take away -1 / -5, or None; its first button shows the type's hull, shields, speed, beams and strength
   next to your primary ship's. Up to 20 of a type.
2. **Distance - / +**: how far ahead they appear, 2U to 10U from the centre of the player ships, along the
   primary ship's heading. Rows of 8 across that line, 0.8U apart; further rows stand behind.
3. **Faction**: Corsairs, Shroud Raiders, Concord Hostile, Relic or Hollow (all hostile to the crews).
4. **Spawn enemies (frozen)**: they appear idle (no moving, no targeting, no firing). The report pops up
   with both sides' strength. Anything the crews shoot before the start is their head start.
5. **START COMBAT**: they hunt the nearest player ship. **Freeze enemies** pauses them; START carries on.
6. When every enemy (or every player ship) is gone, the report pops up: who won, the time, each crew's hull
   lost, shields and energy. **Report** shows it at any time.
7. **Restore player ships**: full hull, shields, energy, probes and missiles; every system repaired, cool,
   unhacked, at 100% power with no coolant. **Reset positions** puts the ships back at the centre, facing
   north. **Clear enemies** removes what is left.

Strength is `RT.shipStrength`: hull + shields, plus 30 x damage a second (beams, and missiles spread over
30 s). A rough guide for comparing sides, not a prediction.
