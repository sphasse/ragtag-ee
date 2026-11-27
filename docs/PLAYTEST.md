# Playtest checklist

Covers what the headless tests (`tools/game_tests.py`) cannot play: real fights and hacks, several
clients, and the numbers left for a playtest. Tick items off, and note what felt wrong and *where*
(grid, phase, which station). Last updated 2026-11-25: everything built since the RC2 checklist (2026-11-19),
in the order to play it. Sessions 1–4 are new work; the sections after them were played in RC1/RC2 and are
regression checks if time allows.

GM shortcuts: **Missions...** → an arc → `→ <phase>` jumps straight to a phase; the helper buttons
(e.g. **Kill fleet**) skip a fight. In any phase that sends the crew somewhere, **Ship → <place>** (e.g.
**Ship → Hob's**) puts the Magpie 5U from it, undocked and stopped, to skip the flight. Use them to get to a
section, then play the section for real.

## Order of play

| Session | What | Sections |
|---|---|---|
| 1 | The Hob Works heist, with fake transponder codes | 1a, 1b |
| 2 | Tow jobs at tier 0 and tier 2 (raiders), then Ice Haul with its raiders | 2a, 2b |
| 3 | The one-off jobs: Cold Chain, The Bounty (and the asteroid ring), The Holdout | 3a–3d |
| 4 | The sniper beam, the faction-zone tint and the other world changes | 4a, 4b |
| Later | Regression: two ships, the older arcs, every job type | R1–R7 |

Already flown in spot checks: the tow line itself (it played well), the faction-zone tint, Ice Haul before its raiders
and the half-warp limit, the Boneyard fixes.

## Before you start

- [ ] Install into the play build: `python3 tools/install.py --ee <EmptyEpsilon>/_build/EmptyEpsilon.app/Contents/Resources`
- [ ] **Backup campaign** (GM main screen) so a bad session can be undone with **Restore campaign**
- [ ] Two player ships: the Magpie plus one picked by name on "Create player ship" (e.g. "Light Freighter: Raven")
- [ ] GM screen open on a separate machine or window; the director is optional
- [ ] For session 2's raiders, the ship needs tier 1+ (an upgrade bought); GM **Upgrades...** can grant one

---

# Session 1: the heist

## 1a. Hob Works Arc (after Ledger, Boneyard with survivors, Corsair; then 5 board jobs; or GM jump)

Details: [GM_HOB_WORKS_MISSION.md](GM_HOB_WORKS_MISSION.md).
- [ ] The hook: an Independent port's news leads with Quill's message; hearing it sets "Meet Quill at Hob's".
      Does the crew go to Hob's Landing on their own?
- [ ] The briefing at Hob's Landing: the four pages, then the four convoy pages. Does each fit the comms
      window without scrolling? Is the cash problem and the plan clear? The Lullaby and convoy-intel Science
      DB entries pop up on Science; the route map image in the convoy entry is readable
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
- [ ] The way home with the cash: a Concord patrol every 30 s until out of Concord space (normal patrols until
      5 minutes before the convoy leaves). The 15-minute delivery: tight or easy?
- [ ] Paying: "We have the cash." (Quill: "...the other 2,000 is yours for the trouble.") then "Deliver 10,000 cr
      to the engineers" ends the arc ("...it is going to take some time. We'll reach out again..."). Clear?
- [ ] A missed delivery (GM: let it lapse): Independent standing to -100, the shaming port news for 30 min,
      the late delivery accepted
- [ ] Rumors afterwards: the robbery and the Concord fallout (the yard layoffs, the Senate), each told once

## 1b. Wanted by the Concord, and the fake transponder

- [ ] Fake transponder codes (after paying the Hob Works): Marchetti's offer, the 500 cr code at the Hob Works
      shipwright, the pop-up on Engineering, "Change transponder" and "Code valid 9:59". With Concord standing
      below -200, do port guards, pickets and patrols really let the ship pass for the 10 minutes?
- [ ] With Concord standing below −200, a Concord port's guard ("CPV …") turns hostile once the ship is within
      5U of it ("…you are wanted by the Concord…" in the log), and gives up 10U from the port. Is 5U the right
      radius? Can a wanted crew still slip in and out of a Concord port?
- [ ] The Concord lane pickets (CPV Vigilant, CPV Temperance, CNS Lawgiver and CPV Forbearance) walk a
      slow beat round their posts and read as pickets ("Concord lane picket…"), not lost defenders
- [ ] The same pickets when wanted: hostile within 10U, they chase to 20U from their post and then go back to
      their beat. Too much on the lanes?

---

# Session 2: towing

Both use the same tow line (`ee/ragtag/tow.lua`): its numbers apply to each.

## 2a. Tow jobs (the board; common at tier 0, rarer later)

- [ ] "We got a call..." details, then the "We'll get 'em home" button: reads right?
- [ ] The broken-down ship is somewhere quiet (no patrols), within 60U: easy to find from the grid?
- [ ] Engineering's "Attach tow line" within 2U; the pale blue line from the ship to the tow (main screen and
      radar), fading when it lets go. Still readable among weapons fire?
- [ ] **The half-warp limit**: the line takes half of warp 1 (15U a minute): warp 1 with Engineering's warp power
      at ~50%, Science (or Operations) reading "Tow speed: X of 15 U/min". Do the two stations find it together?
      Full-power warp 1 snaps it: clear? fair?
- [ ] The energy drain while towing (up to 3 energy/s at full impulse or warp): noticeable, not stranding?
- [ ] Home within 4U of the port, then dock: "Got 'em home". Pay right for the effort (like salvage, 1.2×)?
- [ ] How often they show up: common at tier 0, fewer at tiers 1 and 2? None with raiders at tier 0
- [ ] After upgrading: "Raiders about." tows; the brief warns ("expect company", hazard pay, 100 cr for missiles).
      The raiders show up 10U out just after you first hook up (rival-tow names: "Interspace AAA"...), their
      leader tells you to cut her loose, and they attack. Fair at one raider (tier 1) and two (tier 2)?
      They fly 20% faster than the line allows (18U a minute), so a tow can't outrun them: tense rather than
      hopeless? Cast off to fight, then re-attach: no new raiders. Hazard pay (+15% a raider, +100 cr) enough?
- [ ] Achievements: We Got a Call (first tow), Recovery Crew (ten); Jack of All Trades now needs a tow too

## 2b. Ice Haul (Rezkov over; or GM jump)

Details: [GM_ICEHAUL_MISSION.md](GM_ICEHAUL_MISSION.md).
- [ ] The seed rumor sets "Hob's Landing"; the water office's two pages (now warning about the raiders and
      half warp). Is the ice easy to find (a sector name; pale blue on radar, drifting round Kestrel)?
- [ ] Does the tow feel like towing (1.5U line, turning with 40,000 tonnes behind)?
- [ ] Two raiders 10U out the first time the line goes on (hail, then attack at 18U a minute). Too much right
      after Rezkov? Do they break off on delivery?
- [ ] The half-warp limit over a long haul (about 19U): tedious, or a good two-station job?
- [ ] "Release tow line" leaves the ice where it is
- [ ] The ice within 4U of Hob's Landing: 2,000 cr, Independent +75. Right pay with the two raiders?

---

# Session 3: the one-off jobs

## 3a. Cold Chain (the Hob Works funded, then 3 board jobs; or GM jump)

Details: [GM_COLD_CHAIN_MISSION.md](GM_COLD_CHAIN_MISSION.md).
- [ ] The seed rumors at Independent ports (the fever, the cure, Varga asking): hearing Varga's sets
      "Dr. Varga at Tamsin". Does the crew go?
- [ ] Varga's three pages at Tamsin Hollow: is the plan (dock at Ostia, Relay hacks the port to 75%) clear?
- [ ] At Ostia: does Relay find the port's shields on its hacking screen while docked? Does a wanted crew
      use a fake code to get past the port guard, and time it?
- [ ] With a code: "an unknown freighter", no chase. Without: Concord -300 and a patrol every 30 s until out
      of Concord space
- [ ] "Serum good for 14:59" on Relay: is 15 minutes tight or easy? Delivery at Tamsin: 3,000 cr in time,
      1,000 spoiled

## 3b. The Bounty (Rezkov over, 1,000 cr of upgrades; or GM jump)

Details: [GM_BOUNTY_MISSION.md](GM_BOUNTY_MISSION.md).
- [ ] The seed rumors: hearing the Dustmote notice sets "Bounty at Dustmote". Does the crew go that far east?
- [ ] Thresh's two pages: the notice, then the trail (a real sector in the Deep Shroud) and how to stop Long Odds
- [ ] Finding Long Odds in the nebula: probes and Science? Found within 8U: it runs, the escorts attack
- [ ] Long Odds (Phobos T3, 300 hull, 150 shields) can't be destroyed: impulse and rear shield both down at once
      stops it. Tough enough? Too like the heist? The escorts (Adder MK5s) a real fight?
- [ ] Ashby's offer (crypto credits, the keys in his head): do they read it? Do they argue? Dustmote for 3,000 and
      Independent +100, or Saint Brennan's for 4,500 and Independent -150

## 3c. The Deep Shroud's asteroid ring (during the Bounty)

- [ ] Rocks circling the black hole (7-13U out, about 3.7U a minute on the inside): visible, a hazard
      worth flying round, fun in the Bounty's hunt? Too many, too fast?

## 3d. The Holdout (Rezkov over, 1,500 cr of upgrades; or GM jump)

Details: [GM_HOLDOUT_MISSION.md](GM_HOLDOUT_MISSION.md).
- [ ] The seed rumors: hearing "Breaker's Claim is hiring guns" sets "Breaker's Claim". Do they find the new port
      (south of the Shroud, 18U north of Hob's Landing)?
- [ ] Calloway's two pages, then "We'll stay.": is a minute enough to get in position?
- [ ] Three waves out of the Shroud from two gates, ~19U north: half go for the Claim, half for the Magpie. Too
      easy, too hard? (Wave hulls, the Claim's 500 hull and cutting lasers, the 45 s gap: top of `holdout.lua`)
- [ ] Does the Claim's fighter help? Does the Claim fall if the crew leaves? 3,000 cr and Independent +150 when held
- [ ] Shroud Raiders in the Shroud, Halcyon Rest and now the Deep Shroud: still hostile after the Corsair arc's
      alliance? Their taunt ("Blackwater's rules don't reach in here") reads right? Too many in the Bounty's hunt?

---

# Session 4: ships and the world

## 4a. Upgrades

- [ ] **Sniper beam** (350 cr, at beam shipwrights): the other choice for the forward mount, never both. A 5° arc
      that reaches 3U, 8 damage every 8 s. Can Helm hold a target in 5°? Worth giving up the 50° forward beam?
      The shipwright hides the other mount once one is fitted
- [ ] Beam upgrades (coils, heavy emitters) apply to every beam, whenever it was bought: buy coils first, then the
      sniper beam, and the sniper still gets them (heavy: 3.4U). Removing a beam upgrade (GM) takes it off
- [ ] Faster probes (120 and 180 U a minute): worth the price? Do they change how Science scouts?
- [ ] **Coolant I / II** (300 / 800 cr, at reactor shipwrights): coolant 100% -> 110% -> 125%. Does Engineering use the
      extra to run more systems hot at once? Cheap enough to matter, not so much it breaks the heat game?
- [ ] Science DB **Ships > ... > Light Freighter**: the crew's own ship has an entry beside the Flavia P.Falcon
- [ ] Turn I–III (200 / 800 / 2,000) and Accel I–III (300 / 1,000 / 2,500) at Hob's Landing: does
      each level feel like a step? Turn III now stops at 18°/s (above every stock frigate, below the fighters):
      still worth 2,000 cr for the last +2? Is double the stock acceleration too much?
- [ ] Hob's Landing's shipwright (the Hob Works) sells sensors, engines, thrusters, reactor, shields
      and probes; its Science DB Ports entry has the new lore
- [ ] Science DB **Ship Upgrades** (top level): one entry per component with every upgrade's effect, price, prerequisite
      and the ports that fit it. Does it read well on the Science screen? Do crews use it to plan purchases?
- [ ] Science DB **People**: each profile shows its portrait beside the description. Readable at the Science
      screen's size? Do the faces fit the people as the crew meets them?
- [ ] GM **Ship Upgrades**: Accel and Turn are listed; revoking a level (e.g. Shield II) also revokes the levels above
      it, and the status sheet shows acceleration and turn rate
- [ ] **Tier-2 work** (1,000 cr of upgrades): the board now offers tier-2 variants (about a third of jobs), paying
      more (base 80). Do they read and play right? They had never been offered before
- [ ] Concord standing notices (`[Rep]` in the log) match what happens: at +500 the patrol still stops you but knows
      your callsign; below 0 a fee; below −200 attack on sight. A crew short of 100 cr can't pay the fee

## 4c. The Combat Arena (scenario 65; for the balancing itself)

Details: [scenarios/arena/README.md](../scenarios/arena/README.md).
- [ ] Two or more crews join from "Create player ship"; the GM fits upgrades per ship (Ship Upgrades...)
- [ ] Enemies...: the list, +1/+5/-1/-5/None, a type's info; Distance 2-10U and Faction; Spawn shows them frozen in
      rows ahead of the crews (do they sit still and hold fire?)
- [ ] START COMBAT, Freeze, START again; the report at the end (time, hull lost, both sides' strength): useful for
      judging a fair fight? Restore and Reset positions between rounds
- [ ] A ship lost in a round and made again under its name keeps the GM's upgrades

## 4d. The Pit (tier 2; south of the Deep Shroud)

- [ ] Do the rumors get the crew there ("south of the Deep Shroud ... not as far as the Maw")? Is the ring easy to
      find once close, and the opening obvious?
- [ ] The pit boss: the three offers and purses read right; the rules are clear before signing
- [ ] 60 s to get in through the opening: enough from the station? Is the rock dense enough that going over it
      hurts (35 a rock)?
- [ ] The fights: do the easy / good / hard labels feel right? (Rate each on Relay: it goes in the fight log.) Do
      the opponents stay in the ring? Purses worth the risk (about 150 / 250 / 375 cr)?
- [ ] Losing: leaving the ring, yielding (hail the station: "We yield."), the 2-minute wait before the next bout

## 4b. The world

- [ ] Control tint: each faction's patrol zones show a faint colour on Relay's map and Science's long-range radar (Concord
      blue, Corsair orange, Shroud Raider rust, Relic olive, Hollow red). Still readable at half strength? Does it help
      crews plan routes? GM: World Plugins → "Faction zones: ON/OFF" (top of the list) turns it off and on
- [ ] Science DB **Regions**: a map of the whole Drift on the section, and one of its region on each entry, with the
      sector letters and numbers on the edges. Readable on the Science screen? Do crews use them to find places?
- [ ] The Escrow Marches (new Concord region south of the Core; Sentinel Fleet Yard and Valcourt moved 25U south):
      shake-downs there like the Core? Do old routes to Valcourt still make sense?
- [ ] Shroud Raiders: their own always-hostile faction; the two rumors that name them
- [ ] Aftermath news after arc outcomes: each told once across sessions, plus the Concord's reaction lines
- [ ] Science DB changes show in the ship log with where they are ("Database entry added: People > …") and pop up on
      Science (and Operations / Single Pilot): does Science notice them now? The Boneyard archive's three entries
      should arrive as one pop-up
- [ ] Each job has its own countdown on Relay, in whole minutes; side-panel lines fit
- [ ] Salvage pods are identified with one Science scan
- [ ] Achievements show in the ship log (Relay) as "[Achievement] Name: ...". Science DB **Achievements** (top
      level) lists them all in one column, "Earned N of M" on top, a gold ◆ when earned and a grey ◇ when not;
      hidden story ones show as ??? until earned
- [ ] An empty job board says "check back in a while / a few / a bit"
- [ ] GM **Enable arc / Disable arc** on a finished arc resets it (its done flag too)

---

# Regression (played in RC1/RC2; if time allows)

## R1. Two ships

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

## R2. Rezkov Arc (needs Independent ≥ 500 and 600 cr of upgrades, or GM jump)

- [ ] Hook: rumors lead to Dustmote; Thresh's job offer; declining works
- [ ] M1 navigate to the beacon and report back
- [ ] M2: a **real Relay hack** of Waypoint Galen (not the GM "Complete hack"); the cover jobs show up
      on the Magpie's board at Halcyon Rest / Port Vesper / Calder's Reach / Arbiter
- [ ] M3: intercept and **fight CWS Meridian for real** (not "Disable Meridian"); boarding and Kael's offer
- [ ] Try one run where the Meridian is left alone: does it reach the Arbiter Line, and is that ending
      clear to the crew? *(Never played in a test.)*
- [ ] Each ending's reputation change feels proportionate (±1000 is a lot: does the board shrink as expected?)

## R3. Ledger Arc (after Rezkov; 800 cr of upgrades)

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

## R4. Boneyard Arc (after Rezkov; 800 cr of upgrades)

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
      The Annex lasers (halved to 16) and the operations menu's Refresh button
- [ ] "All Concord forces in proximity have been eliminated." hail, then "Archive compressed": the
      download takes 1 min (a running one finishes within a minute); then "Report the success"
- [ ] Leaving the Boneyard (20U outside it) ends the arc with whatever the crew has (with the archive:
      report to the survivors)
- [ ] Back at the rescue job's station: "Talk with the lifeboat survivors" reads well and ends the arc
- [ ] Each ending (Full / Data) is reachable and reads clearly

## R5. Corsair Arc (1000 cr of upgrades)

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
- [ ] **Magazine**: runs low → it hails with its grid and a "Rearm" objective appears;
      8 s alongside refills the racks. Is it reachable mid-battle? Is **3 loads** right? Is **8 s**
      too long under fire? Does the Concord ever get to it?
- [ ] Losing your ship in the battle ends the arc as failed; losing Corsairs does not

## R6. Jobs (all eight types, at least once each)

- [ ] Delivery · Salvage · Hacking (75% threshold, beam windows) · Destroy · Boarding · Escort · Tailing · Tow
- [ ] Rewards feel right for the risk (boarding pays ~1.8× a delivery)
- [ ] Standing below 0 / −200 / −400 shrinks then closes a faction's boards
- [ ] Work cooldown on: a taken slot refills after the cooldown

## Notes to bring back

- Numbers to retune (constant, arc, what felt wrong)
- Anything that broke, with the grid and phase; a `LUA-Error` line from the log if there was one
- Moments that worked well (so they are not "fixed" later)
