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
- [ ] The way home with the cash: a Concord patrol every 30 s until out of Concord space (normal patrols until
      5 minutes before the convoy leaves). The 15-minute delivery: tight or easy?
- [ ] Paying: "We have the cash." (Quill: "...the other 2,000 is yours for the trouble.") then "Deliver 10,000 cr
      to the engineers" ends the arc ("...it is going to take some time. We'll reach out again..."). Clear?
- [ ] A missed delivery (GM: let it lapse): Independent standing to -100, the shaming port news for 30 min,
      the late delivery accepted
- [ ] Rumors afterwards: the robbery and the Concord fallout (the yard layoffs, the Senate)

## 5c. Cold Chain (the Hob Works funded, then 3 board jobs; or GM jump)

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

## 5d. The Bounty (Rezkov over, 1,000 cr of upgrades; or GM jump)

Details: [GM_BOUNTY_MISSION.md](GM_BOUNTY_MISSION.md).
- [ ] The seed rumors: hearing the Dustmote notice sets "Bounty at Dustmote". Does the crew go that far east?
- [ ] Thresh's two pages: the notice, then the trail (a real sector in the Deep Shroud) and how to stop Long Odds
- [ ] Finding Long Odds in the nebula: probes and Science? Found within 8U: it runs, the escorts attack
- [ ] Long Odds (Phobos T3, 300 hull, 150 shields) can't be destroyed: impulse and rear shield both down at once
      stops it. Tough enough? Too like the heist? The escorts (Adder MK5s) a real fight?
- [ ] Ashby's offer (crypto credits, the keys in his head): do they read it? Do they argue? Dustmote for 3,000 and
      Independent +100, or Saint Brennan's for 4,500 and Independent -150

## 5e. The Holdout (Rezkov over, 1,500 cr of upgrades; or GM jump)

Details: [GM_HOLDOUT_MISSION.md](GM_HOLDOUT_MISSION.md).
- [ ] The seed rumors: hearing "Breaker's Claim is hiring guns" sets "Breaker's Claim". Do they find the new port
      (south of the Shroud, 18U north of Hob's Landing)?
- [ ] Calloway's two pages, then "We'll stay.": is a minute enough to get in position?
- [ ] Three waves out of the Shroud from two gates, ~19U north: half go for the Claim, half for the Magpie. Too
      easy, too hard? (Wave hulls, the Claim's 500 hull and cutting lasers, the 45 s gap: top of `holdout.lua`)
- [ ] Does the Claim's fighter help? Does the Claim fall if the crew leaves? 3,000 cr and Independent +150 when held
- [ ] Shroud Raiders in the Shroud, Halcyon Rest and now the Deep Shroud: still hostile after the Corsair arc's
      alliance? Their taunt ("Blackwater's rules don't reach in here") reads right? Too many in the Bounty's hunt?

## 5f. Ice Haul (Rezkov over; or GM jump)

Details: [GM_ICEHAUL_MISSION.md](GM_ICEHAUL_MISSION.md).
- [ ] The seed rumor sets "Hob's Landing"; the water office's two pages. Is the ice easy to find (a
      sector name; pale blue on radar, drifting round Kestrel)?
- [ ] Engineering's "Attach tow line" within 2U: does the tow feel like towing (1.5U line, up to 3 energy/s at full impulse,
      turning with the ice behind)?
- [ ] Two raiders 10U out the first time the line goes on (hail, then attack at 18U a minute). The water office's
      warning reads right? Too much right after Rezkov? Do they break off on delivery?
- [ ] The line takes half of warp 1 (15U a minute): warp 1 with Engineering's warp power at ~50%, Science reading "Tow speed".
      Do the two stations find it together? Full-power warp 1 snaps it: clear? fair? "Release tow line" leaves it where it is
- [ ] The ice within 4U of Hob's Landing: 2,000 cr, Independent +75. Right pay with the two raiders?

## 5h. Tow jobs (the board; tier 0, rarer later)

- [ ] "We got a call..." details, then the "We'll get 'em home" button: reads right?
- [ ] The broken-down ship is somewhere quiet (no patrols), within 60U: easy to find from the grid?
- [ ] Engineering's "Attach tow line", home at half of warp 1, within 4U of the port, then dock: "Got 'em home". Pay right
      for the effort (like salvage, 1.2×)?
- [ ] How often they show up: common at tier 0, fewer at tiers 1 and 2?
- [ ] After upgrading: "Raiders about." tows. The raiders show up 10U out just after you hook up, their leader tells
      you to cut her loose, and they attack. Fair at one raider (tier 1)
      and two (tier 2)? They fly 20% faster than the tow line allows (18U a minute), so a tow can't outrun them: tense rather than hopeless? Hazard pay (+15% a raider, +100 cr for missiles) enough?
- [ ] Achievements: We Got a Call (first tow), Recovery Crew (ten); Jack of All Trades now needs a tow too

## 5g. The Deep Shroud's asteroid ring

- [ ] Rocks circling the black hole (7-13U out, about 3.7U a minute on the inside): visible, a hazard
      worth flying round, fun in the Bounty's hunt? Too many, too fast?

## 6. Ship handling upgrades and the Hob Works

- [ ] Turn I–III (200 / 800 / 2,000) and Accel I–III (300 / 1,000 / 2,500) at Hob's Landing: does
      each level feel like a step? Is double the stock turn and acceleration too much?
- [ ] Hob's Landing's shipwright (the Hob Works) sells sensors, engines, thrusters, reactor, shields
      and probes; its Science DB Ports entry has the new lore
- [ ] **Sniper beam** (350 cr, at beam shipwrights): the other choice for the forward mount, never both. A 5° arc
      that reaches 3U, 8 damage every 8 s. Can Helm hold a target in 5°? Worth giving up the 50° forward beam?
      Coils and heavy emitters apply to it too (heavy: 3.4U). Shipwright hides the other mount once one is fitted

## 7. The world

- [ ] Achievements show in the ship log (Relay) as "[Achievement] Name: ...". Science DB **Achievements** (top
      level) lists them all, earned [x] or not; hidden story ones show as ??? until earned
- [ ] Fake transponder codes (after paying the Hob Works): Marchetti's offer, the 500 cr code at the Hob Works
      shipwright, the pop-up on Engineering, "Change transponder" and "Code valid 9:59". With Concord standing
      below -200, do port guards, pickets and patrols really let the ship pass for the 10 minutes?

- [ ] The Concord lane pickets (CPV Vigilant, CPV Temperance, CNS Lawgiver and CPV Forbearance) walk a
      slow beat round their posts and read as pickets ("Concord lane picket…"), not lost defenders
- [ ] With Concord standing below −200, a Concord port's guard ("CPV …") turns hostile once the ship is within
      5U of it ("…you are wanted by the Concord…" in the log), and gives up 10U from the port. Is 5U the right
      radar? Can a wanted crew still slip in and out of a Concord port?
- [ ] The same for the lane pickets (CPV Vigilant, CPV Temperance, CNS Lawgiver and CPV Forbearance): hostile within
      10U, they chase to 20U from their post and then go back to their beat. Too much on the lanes?
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
