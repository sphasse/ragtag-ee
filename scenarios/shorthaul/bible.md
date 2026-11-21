## The Short Haul — scenario bible

A one-shot competition in the Drift. Several crews, each in a stock Light Freighter with the same
200 credits, race the clock (15 minutes, 30 minutes or 1 hour, a start-up setting) to make the most
money. Score is net worth: credits plus the list price of the upgrades a ship has bought, so
upgrading never costs a ship its place. Nothing is saved: every round starts fresh, and The Drift's
campaign is never touched (own save key `shorthaul`, saving switched off).

### Rules
- Same universe, factions, job types, rewards, upgrades and prices as The Drift. Reputation applies
  (a ship's standing gates its job boards; patrols judge it). No story arcs.
- Job boards never run dry (no new-job cooldown: the list is full on every visit) and favour short
  runs (`JOBS.config.mission_distance_mode = "short"`). Both can be changed from the GM's Jobs menu.
- The boards stay shut until the GM presses **Start the clock** (so every crew starts together).
- A live leaderboard (the clock, the top 5 by net worth, and your own place if lower) shows as status
  lines on Relay, Operations, Tactical, Engineering+, Single Pilot and the alt Relay: the consoles a
  short-handed crew combines. No pop-ups until the end.
- At zero (or **End the competition now**) the final standings pop up on every console of every
  ship and go in the ship log; the leaderboard and clock go away. The scenario carries on: the
  ships are on their own.
- A lost ship costs half its credits, as in The Drift; a ship rebuilt under the same name carries on
  with what it had left.

### Code
`ee/ragtag/race.lua` (`RACE`: clock, scoring, leaderboard lines, the result), loaded by
`scenario_81_shorthaul.lua`. Test: `tests/core/race.lua`.

### Tone
The Drift's: space-western, wry, a bit of a scramble. The AI director is not used.
