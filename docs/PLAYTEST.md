# Playtest checklist

Covers what the headless tests (`tools/game_tests.py`) cannot play: real fights and hacks, several
clients, and the numbers left for a playtest. Tick items off, and note what felt wrong and *where*
(grid, phase, which station). Last updated 2026-11-19, after the round of arc fixes from the RC1 playtest (RC2).

GM shortcuts: **Missions...** → an arc → `→ <phase>` jumps straight to a phase; the helper buttons
(e.g. **Kill fleet**) skip a fight. In any phase that sends the crew somewhere, **Ship → <place>** (e.g.
**Ship → Hob's**) puts the Magpie 5U from it, undocked and stopped, to skip the flight. Use them to get to a
section, then play the section for real.

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
- [ ] GM **Jobs... → New delivery...**: select a port on the map → **Use map selection** sets From;
      post a `[SPECIAL]` for the second ship: it is on that port's board for that ship only, and
      delivering it pays the GM's amount; **Assign now** puts a job straight on a ship's Relay panel
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

- [ ] The hook comes after **2 board jobs** by the Magpie once Rezkov is over (jobs done before reaching
      800 cr of upgrades count now; that was the RC1 bug). It is quiet: rumors and Thresh at Dustmote.
      Noticeable enough? (GM: Missions → Ledger → Mission criteria shows the count.)
- [ ] Hook at Dustmote → Rezkov's station in the nebula → three data cores (Valcourt, Ostia, Galen)
- [ ] A **Power cell** beside each core refills the reactor to 100%: does Science spot them? Do they make the carry
      too easy, or just survivable?
- [ ] Rezkov's fragment directions end "Bring the assembled AI to me here." on screen, not cut off by
      the bottom of the comms window
- [ ] The AI's "Unidentified Signal" is **not** on the radar at Port Vesper
- [ ] Carrying the AI: the **3 energy/s drain** (eased from 5) — tense or just annoying? Does Engineering cope?
- [ ] The **60 s** before the Concord Audit Service fleet arrives: enough time?
- [ ] Energy at zero is an **instant loss**: fair, or should there be a warning or grace period?
- [ ] "Transmit the data" surrender ending reads clearly
- [ ] GM "+100 energy" helper (fragment hunt and carry) for a crew in trouble
- [ ] At Rezkov's: "You were right, this thing runs hot." reads naturally

## 4. Boneyard Arc (after Rezkov; 800 cr of upgrades)

- [ ] Find the Annex through the **lifeboat rescue job** (Port Vesper / Halcyon Rest / Saint Brennan's;
      20-minute clock): the survivors' hail and the Science DB "Boneyard Survivor Records".
      *(This path is not in any test.)*
- [ ] And once the other way: the 8U proximity to Ashgrave
- [ ] The survivors' hail asks for the Annex to be hacked; nothing more happens (no Annex, no hack
      objective, not even at Ashgrave) until they are handed in at the station the job came from
- [ ] Then just the "Hack the Annex" objective, no pop-up or instructions: does the crew work out
      how to hack it from the survivors' request alone?
- [ ] A **real Relay hack** of the Annex front shields to 100% (probes don't survive the drones, so
      the crew has to get close under fire)
      (two successes; it decays over 180 s). Do the drones stay docile, including new ones?
- [ ] Hailing the Annex undocked says "Station security has been reset. Dock for more options."; the
      **dock button** works on the Annex
- [ ] First docking: the "Incoming jump detected" pop-up on every console, the Concord fleet appears
- [ ] Download (5 min docked while the fleet is out, stops on undocking) vs drone reprogram (60 s) vs
      lasers (60 s): does the crew work out to reprogram the drones first? Does it get out into the fight?
- [ ] "All Concord forces in proximity have been eliminated." hail, then "Archive compressed": the
      download takes 1 min (a running one finishes within a minute); then "Report the success"
- [ ] Leaving the Boneyard (20U outside it) ends the arc with whatever the crew has (with the archive:
      report to the survivors)
- [ ] Back at the rescue job's station: "Talk with the lifeboat survivors" reads well and ends the arc
- [ ] Each ending (Full / Data) is reachable and reads clearly

## 5. Corsair Arc (1000 cr of upgrades)

- [ ] Hook: only the Greywater barkeep's message brings Long Memory (not the Gauntlet); "Not right now" re-offers after 10 min
- [ ] Escort: the guide **paces the crew** (holds past 5.5U behind, leads on within 4.5U). Stop for a
      while (a shake-down, a fight), then follow again: does it pick the crew back up? No warp now, top
      cruise at warp-1 speed (30 U/min): can the crew follow at warp 1? Does it take the crew through the north gap of the mine ring and dock at
      Blackwater? *(The test moves the ships; the real flight through the gap is not tested.)*
- [ ] The escorts leave through Blackwater's new **west gap** in the mine ring, and survive a stray
      mine (100/100 shields, 120 hull)
- [ ] The surrendered depot shows as **Concord Surrendered**; the escorts dock and nobody keeps firing
      at it; they dock, dwell 15 s, then one hail: the jackpot, all aboard, heading back to Blackwater
- [ ] Raid on Forward Depot Anvil: the **escorts vs the two guards, for real** (headless it was still
      going after 45 s). Too long? Do the order buttons unlock at the right time?
- [ ] An escort lost → Reva names it and sends a replacement
- [ ] Return: the thickened mine ring round Blackwater; are the three lanes (north, ESE, WSW) findable?
- [ ] The **battle, for real** (7 Concord vs 12 Corsairs, frozen until any player ship is within
      5U of either line): does it stay spread out? How long does it take? Does the crew matter?
- [ ] **Magazine** (new): runs low → it hails with its grid and a "Rearm" objective appears;
      8 s alongside refills the racks. Is it reachable mid-battle? Is **3 loads** right? Is **8 s**
      too long under fire? Does the Concord ever get to it?
- [ ] Losing your ship in the battle ends the arc as failed; losing Corsairs does not

## 5b. Hob Works Arc (after Ledger, Boneyard with survivors, Corsair; then 5 board jobs; or GM jump)

Details: [GM_HOB_WORKS_MISSION.md](GM_HOB_WORKS_MISSION.md).
- [ ] The hook: an Independent port's news leads with Quill's message; hearing it sets "Meet Quill at Hob's".
      Does the crew go to Hob's Landing on their own?
- [ ] The briefing at Hob's Landing: the four pages, then the four convoy pages. Does each fit the comms
      window without scrolling? Is the cash problem and the plan clear? The Lullaby and convoy-intel Science
      DB entries pop up on Science
- [ ] The 15-minute countdown: enough time to reach Lumen, pick a spot and scan? Too much?
- [ ] The fake transponder ("Change transponder" on Engineering, "Code valid 9:59"): does Engineering notice
      it? Do they time it to the departure? Inside 15U without it, the escorts' warning hail, then a fight
- [ ] The run: the transport at 7.5U a minute (GM **Transport faster / slower** to tune). Does it feel like
      chasing a train?
- [ ] Disabling it: impulse **and** rear shield both down at once, each 90% hacked (Relay) or under 10%
      health (Science). Do they divide and conquer before the hack fades (~18 s from 100%)? Too hard?
      Does Relay hack while Weapons shoot? Docking to board
- [ ] Destroying it: the three cash boxes. Does the crew find and collect them?
- [ ] The escorts (Adder MK8, hull 100): a real fight? Do they leave a second player ship alone?
- [ ] The way home with the cash: the Concord patrols are back. The 15-minute delivery: tight or easy?
- [ ] Paying: "We have the cash." then "Deliver 10,000 cr to the engineers"; the 10-minute build
- [ ] A missed delivery (GM: let it lapse): Independent standing to -100, the shaming port news for 30 min,
      the late delivery accepted
- [ ] Rumors afterwards: the robbery and the Concord fallout (the yard layoffs, the Senate)

## 6. Ship handling upgrades and the Hob Works

- [ ] Turn I–III (200 / 800 / 2,000) and Accel I–III (300 / 1,000 / 2,500) at Hob's Landing: does
      each level feel like a step? Is double the stock turn and acceleration too much?
- [ ] Hob's Landing's shipwright (the Hob Works) sells sensors, engines, thrusters, reactor, shields
      and probes; its Science DB Ports entry has the new lore

## 7. The world

- [ ] The Concord lane pickets (CPV Vigilant, CPV Temperance, CNS Lawgiver and CPV Forbearance) walk a
      slow beat round their posts and read as pickets ("Concord lane picket…"), not lost defenders
- [ ] Science DB **Ship Upgrades** (top level): one entry per component with every upgrade's effect, price, prerequisite
      and the ports that fit it. Does it read well on the Science screen? Do crews use it to plan purchases?
- [ ] Science DB changes show in the ship log with where they are ("Database entry added: Lore > …") and pop up on
      Science (and Operations / Single Pilot): does Science notice them now? The Boneyard archive's three entries
      should arrive as one pop-up
- [ ] An empty job board says "check back in a while / a few / a bit"
- [ ] GM **Enable arc / Disable arc** on a finished arc resets it (its done flag too)

## 8. Jobs (all seven types, at least once each)

- [ ] Delivery · Salvage · Hacking (75% threshold, beam windows) · Destroy · Boarding · Escort · Tailing
- [ ] Rewards feel right for the risk (boarding pays ~1.8× a delivery)
- [ ] Standing below 0 / −200 / −400 shrinks then closes a faction's boards
- [ ] Work cooldown on: a taken slot refills after the cooldown

## Notes to bring back

- Numbers to retune (constant, arc, what felt wrong)
- Anything that broke, with the grid and phase; a `LUA-Error` line from the log if there was one
- Moments that worked well (so they are not "fixed" later)
