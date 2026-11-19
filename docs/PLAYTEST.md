# Playtest checklist

Covers what the headless tests (`tools/game_tests.py`) cannot play: real fights and hacks, several
clients, and the numbers left for a playtest. Tick items off, and note what felt wrong and *where*
(grid, phase, which station). Last updated 2026-11-17, after `b47beb3`.

GM shortcuts: **Missions...** → an arc → `→ <phase>` jumps straight to a phase; the helper buttons
(e.g. **Kill fleet**) skip a fight. Use them to get to a section, then play the section for real.

## Before you start

- [ ] Install into the play build: `python3 tools/install.py --ee <EmptyEpsilon>/_build/EmptyEpsilon.app/Contents/Resources`
- [ ] **Backup campaign** (GM main screen) so a bad session can be undone with **Restore campaign**
- [ ] Two player ships: the Magpie plus one picked by name on "Create player ship" (e.g. "Light Freighter: Raven")
- [ ] GM screen open on a separate machine or window; the director is optional

## 1. Two ships

- [ ] Each ship's Relay/Operations shows its own `Credits: N`; a job pays only the ship that took it
- [ ] Arc work only reaches the Magpie: the second ship never sees `[SPECIAL]` contracts or arc seed jobs
      (e.g. Rezkov's cover deliveries to Galen), and arc hails and log lines go to the Magpie only
- [ ] Patrols: the second ship alone in the Gauntlet draws its own Corsairs; both ships together draw
      no more than one ship would
- [ ] Concord inspection of the second ship: it is judged by its *own* standing (give it a different
      Concord standing from the GM **Reputation...** menu first); the Magpie hailing that patrol is
      told to keep clear; refusing the fine makes the patrol attack the refusing ship only
- [ ] A patrol whose ship leaves the zone switches to the other ship if it is still in the zone
- [ ] GM **Reputation...** lists both ships; **Jobs...** has a credits pair per ship
- [ ] A wreck scanned by the second ship gives up salvage near the second ship
- [ ] Freighters never pop in or teleport next to either ship
- [ ] The "Create player ship" list: ten "Light Freighter: <name>" entries, the Magpie first; each
      description shows that ship's saved credits and upgrades; the ship list reads
      "Independent Light Freighter Raven"; picking a ship that is already flying makes nothing
- [ ] **Lose the Magpie** with the second ship still flying: the session goes on. Pick
      "Light Freighter: Magpie" on "Create player ship": it should log "Registry: Magpie is back on
      the books", with the Magpie's credits, upgrades and any active arc. *(Only tested from script.)*
- [ ] Note: does anything look wrong on a second client (screens, custom info lines, comms)?

## 2. Rezkov Arc (needs Independent ≥ 500 and 600 cr of upgrades, or GM jump)

- [ ] Hook: rumors lead to Dustmote; Thresh's job offer; declining works
- [ ] M1 navigate to the beacon and report back
- [ ] M2: a **real Relay hack** of Waypoint Galen (not the GM "Complete hack"); the cover jobs show up
      on the Magpie's board at Halcyon Rest / Port Vesper / Calder's Reach / Arbiter
- [ ] M3: intercept and **fight CWS Meridian for real** (not "Disable Meridian"); boarding and Kael's offer
- [ ] Try one run where the Meridian is left alone: does it reach the Arbiter Line, and is that ending
      clear to the crew? *(Never played in a test.)*
- [ ] Each ending's reputation change feels proportionate (±1000 is a lot: does the board shrink as expected?)

## 3. Ledger Arc (after Rezkov; 800 cr of upgrades)

- [ ] Hook at Dustmote → Rezkov's station in the nebula → three data cores (Valcourt, Ostia, Galen)
- [ ] Carrying the AI: the **3 energy/s drain** (eased from 5) — tense or just annoying? Does Engineering cope?
- [ ] The **60 s** before the Concord Audit Service fleet arrives: enough time?
- [ ] Energy at zero is an **instant loss**: fair, or should there be a warning or grace period?
- [ ] "Transmit the data" surrender ending reads clearly

## 4. Boneyard Arc (after Rezkov; 800 cr of upgrades)

- [ ] Find the Annex through the **lifeboat rescue job** (Port Vesper / Halcyon Rest / Saint Brennan's;
      20-minute clock): the survivors' hail and the Science DB "Boneyard Survivor Records".
      *(This path is not in any test.)*
- [ ] And once the other way: the 8U proximity to Ashgrave
- [ ] A **real Relay hack** of the Annex front shields to 100% (two successes; it decays over 180 s)
- [ ] The Concord battle group: two hunters plus four on posts. Survivable?
- [ ] Download (60 s) vs drone override (30 s): is the choice interesting? Drone stream limits
      (20 alive, 40 replacements) too strong or too weak?
- [ ] Each ending (Full / Data / Drones / Minimal) is reachable and reads clearly

## 5. Corsair Arc (1000 cr of upgrades)

- [ ] Hook: Greywater barkeep message, or entering the Gauntlet; "Not right now" re-offers after 10 min
- [ ] Escort: the guide **waits for a slow crew** (falls 8U behind). *(Not in a test.)*
- [ ] Raid on Forward Depot Anvil: the **escorts vs the two guards, for real** (headless it was still
      going after 45 s). Too long? Do the order buttons unlock at the right time?
- [ ] An escort lost → Reva names it and sends a replacement
- [ ] Return: the thickened mine ring round Blackwater; are the three lanes (north, ESE, WSW) findable?
- [ ] The **battle, for real** (7 Concord vs 12 Corsairs, frozen until you are within 5U of
      either line): does it stay spread out? How long does it take? Does the crew matter?
- [ ] **Magazine** (new): runs low → it hails with its grid and a "Rearm" objective appears;
      8 s alongside refills the racks. Is it reachable mid-battle? Is **3 loads** right? Is **8 s**
      too long under fire? Does the Concord ever get to it?
- [ ] Losing your ship in the battle ends the arc as failed; losing Corsairs does not

## 6. Jobs (all seven types, at least once each)

- [ ] Delivery · Salvage · Hacking (75% threshold, beam windows) · Destroy · Boarding · Escort · Tailing
- [ ] Rewards feel right for the risk (boarding pays ~1.8× a delivery)
- [ ] Standing below 0 / −200 / −400 shrinks then closes a faction's boards
- [ ] Work cooldown on: a taken slot refills after the cooldown

## Notes to bring back

- Numbers to retune (constant, arc, what felt wrong)
- Anything that broke, with the grid and phase; a `LUA-Error` line from the log if there was one
- Moments that worked well (so they are not "fixed" later)
