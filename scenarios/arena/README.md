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

## Three opponents
**Offer three opponents** builds every group of one to four ships from the arena's types and picks one near
each target: **Easy** (R about 2.0), **Good match** (1.3) and **Hard** (0.9). R is a race: the time the enemies
need to destroy the crews divided by the time the crews need to destroy them (`MATCH`, `ee/ragtag/match.lua`:
effective hit points are hull + 1.2 x shields; damage a second is beams plus missiles; an enemy the crews
out-reach with their beams lands fewer of its beam shots, 0.6, or 0.85 when it is much faster). **Take** one to make it
the roster, then spawn as usual. Every spawn's R is reported and logged, whether it came from an offer or not.

## The fight log (for balancing)
Every fight, from START to its end (or Clear enemies, logged as "stopped"), writes one row per player ship to the
**fight log**: JSON in EmptyEpsilon's `scriptstorage.json` under the key `ragtag.fightlog`. On Windows that file
is in the EmptyEpsilon folder (next to EmptyEpsilon.exe); on macOS and Linux it is
`~/.emptyepsilon/scriptstorage.json`. It survives restarts; nothing needs stdout.
- **Crews...**: give each ship a crew number, 1 to 10, before fighting (the button says how many are
  unassigned). Rows carry it, so each group's data stays separate. Numbers are remembered by ship name.
- After each fight, Relay (and Operations / single pilot) gets five buttons: **Fight 1 Far too easy, 2 Easy,
  3 Good fight, 4 Hard, 5 Far too hard**. That rating is what the stats are measured against. **Rate last fight...** lets the GM rate too.
- A row: hull lost (and %), cumulative shield damage, cumulative system damage (damage repaired mid-fight still
  counts), fight time and time since first damage, lowest hull and shield %, seconds with a shield down, top heat
  and seconds over 90% heat, lowest energy %, missiles fired, damage dealt, kills, the enemies and their strength,
  the predicted R and the offer slot, the outcome and the rating.
- **Mobility** (each row): both sides' speed, turn rate, acceleration, combat boost and strafe, beam coverage (share
  of the circle) and reach, and their ratios; and from the fight: the share of it the crew spent inside an enemy's
  beam arc and range (`exposed_pct`) and with an enemy inside its own (`firing_pct`; `aim_edge` is the difference),
  the average distance to the nearest enemy, seconds of combat boost or strafe, missiles fired at the crew and how
  many hit (`dodge_pct`), the crew's missiles and how many landed, and the damage that landed per second each side
  could fire, beside what the model expects. Missile hits are judged approximately: a missile that vanishes within
  1.2U of its target in a half-second where the target took damage.
- **Fight log...** shows the counts by crew and the last few rows, or deletes the log (crew numbers kept).
- Read it: `python3 tools/fight_stats.py scriptstorage.json [more.json ...] [--crew N] [--csv fights.csv]
  [--correlate]`. Files from several machines merge without double counting. `--correlate` ranks every stat by
  how closely it follows the crews' rating; about 30 rated fights give a first reading.

Strength is `RT.shipStrength`: hull + shields, plus 30 x damage a second (beams, and missiles spread over
30 s). A rough guide for comparing sides, not a prediction.
