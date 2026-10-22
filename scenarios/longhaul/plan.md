# Long Haul: session plans

Session 1 (`scenario_90_longhaul_1.lua`) is built and tested. This file plans sessions 2–5 at the level needed to write them. Each session should run 45–75 minutes. The world, cast and secrets are in `director/campaign_bible.md`; keep the two consistent.

## Contents
- Design rules for every session
- Flags written by session 1
- Session 2: Salvage Rights
- Session 3: The Arbiter Line
- Session 4: Old Debts
- Session 5: Last Light
- Upgrade economy

## Design rules for every session
- Use the shared universe (`VERSE`, see framework.md). Place session content with `VERSE.at(...)` in the region the plan names: session 2 in the Shroud and Deep Shroud east of Halcyon Rest; session 3 on the Arbiter Line (Waypoint Galen, CPV Vigilant, CPV Temperance already patrol it); session 4's hideout in the Gauntlet or near Blackwater; session 5 in the Deep Shroud. Don't rebuild stations the verse already has.
- File `scenario_9N_longhaul_N.lua`, session id `sN`, built from `assets/session_template.lua`.
- Start the ship docked or near a friendly shipwright so the crew can spend money first.
- Include `catchUpCampaign()` defaults so a session works if earlier ones were skipped or the save was lost.
- Give every station something to do: Helm (navigation hazards, chases), Weapons (fights), Engineering (damage, power juggling during stealth), Science (scans that unlock information), Relay (comms choices, waypoints).
- One meaningful choice per session that sets a flag later sessions read.
- 2–4 `ai = true` beats, each with a fallback trigger. Scripted beats for structure.
- End through a comms choice or arrival, then `finishSession`.

## Flags written by session 1
`s1_delivered`, `lantern_core` (recovered the core), `inspected` (submitted to Vashti), `bribed_concord`, `ran_from_concord`, `wanted` (tagged by Vashti), `escaped` is implied by `ran_from_concord` without `wanted`, `salo_knows`, `mags_knows`.

---

## Session 2: Salvage Rights
**Premise.** Mags (or Salo, if `salo_knows`) points the crew to the rest of the shipment: a convoy that broke up in the Shroud eight months ago. Rook's salvage crew on the *Second Chance* is already there. The lantern core starts humming, and something in the Shroud hums back.

**Map.** Start docked at Halcyon Rest. The Shroud: a large nebula field to the east with a debris field of three wrecked freighters ("Convoy 7" A/B/C). Rook's Second Chance (Independent, "Flavia" or "Tug") working wreck A. An Unknown ship hidden deep in the nebula. Navigation hazard: a mine field or black hole on the direct route.

**Beats.**
- `briefing` (script): job hail, objective "Salvage Convoy 7".
- `rook_meets` (script, on approach): Rook hails, competitive but friendly. Choice: split the salvage, race her, or threaten her. Flag `rook_relation` = "partner" / "rival" / "enemy".
- `salvage_wreck` ×3 (script): Science scans each wreck (setScanningParameters 2–3); scanning reveals a pickup (credits, missiles, and in one wreck a "jump drive core": `RT.grantUpgrade("jump_drive")` or 250 credits if already owned).
- `tones` (ai): the lantern core hums; an Unknown contact appears at the edge of radar and broadcasts tones. Science "decodes" by scanning it: log text with coordinates and a fragment, "MERIDIAN". Flag `heard_meridian`. Fallback: 3 minutes after the second wreck.
- `scavengers` (ai): Corsair scavengers arrive. If Rook is a partner she helps (`orderDefendTarget(player)`); if an enemy she leaves the crew to it, or tips off the raiders. Fallback: after the third wreck.
- `second_core` (script): the Ghost coordinates lead to a second lantern core in the deep nebula. Flag `lantern_cores` = 2.
- End: return to Halcyon Rest.

**Director guidance.** Voice Rook and the scavengers; keep the Unknown ship silent except for tones and log text. Spawn small salvage as rewards for exploring. Don't reveal what the lanterns are.

**Reward range.** 400–700 credits plus possibly the jump drive.

---

## Session 3: The Arbiter Line
**Premise.** The Ghost coordinates point past the Arbiter Line, a Concord customs blockade. Admiral Hesper Vane has arrived with orders to stop "smuggled navigation hazards". The crew must slip, talk, or fight past.

**Map.** A line of Concord patrols (Concord "Phobos M3", "Nirvana R5" as command ship *CNS Resolute*) between two nebula banks, with sensor buoys (`Artifact`s with descriptions). Concord Station Arbiter is the anchor. A smuggler's waystation (Independent) on the near side sells forged transponder codes.

**Mechanics.**
- Detection: each patrol checks `RT.dist(player, patrol)` against a detection radius that shrinks inside nebulae and with reactor power below 50% (`getSystemPower("reactor")`), rewarding Engineering. Detected → patrols hail and converge (`orderFlyTowards`), as in session 1's chase.
- `wanted` from session 1 halves the safe distance; `bribed_concord` gives one free "processing fee" option; `inspected` means Vashti vouches for them if hailed.
- Forged codes (150 credits at the waystation): one free pass through a checkpoint.

**Beats.**
- `vane_broadcast` (script): Vane's sector-wide announcement (`globalMessage` + log).
- `vashti_returns` (ai): Lt. Vashti is on the line. Her attitude depends on session 1: inspected → friendly warning; bribed → nervous and hush; tagged or ran → hostile. Fallback on approach to her checkpoint.
- `buoy_glitch` (ai): a sensor buoy malfunctions near the crew; Science can spoof it or Weapons can destroy it (which raises the alert).
- `vane_hails` (script, on crossing or capture): Vane offers 2000 credits for the lantern cores. Choice: sell (flag `sold_cores`: the campaign continues with Mags betraying Vane instead), refuse (flag `defied_vane`), or stall (flag `stalled_vane`).
- End: cross the line and reach the far-side relay station.

**Reward range.** 300–500 credits; if they sell, 2000 but the cores are gone (session 4 becomes a heist to steal them back).

---

## Session 4: Old Debts
**Premise.** Someone sold the crew out. If `mags_knows`, it's Mags; if only `salo_knows`, Mags found out anyway, but Salo warns the crew in time. Grinning Teeth (Corsairs), paid by Mags, have taken Doc Salo hostage at an asteroid hideout to trade for the cores.

**Map.** The hideout: a Corsair "Small Station" inside an asteroid field with mines, two patrolling raiders, and a turret platform ("Defense platform"). Port Vesper is two jumps away (Mags is there).

**Beats.**
- `ransom_call` (script): Grinning Teeth's demand. Objective: rescue Salo.
- `approach` options: fight in; sneak through the asteroids (helm challenge); or negotiate with fake cores (Science "builds" a decoy by scanning debris, flag `decoy_cores`).
- `rook_arrives` (ai): if `rook_relation == "partner"`, Rook shows up to help; if "enemy", she's working for the Teeth. Fallback at mid-fight.
- `salo_rescued` (script): dock with the hideout once its defences are down, or complete the trade. Salo reveals the first secret: the lanterns are Meridian fleet beacons (bible secret 1).
- `mags_confrontation` (script, comms at Port Vesper): Mags admits she was selling to Vane. Choice: forgive (flag `mags_ally`: she sends help in session 5), cut her off, or turn her in to the Concord (flag `mags_arrested`; Vashti approves).
- `vane_secret` (ai): an intercepted transmission hints that Vane signed the order abandoning Meridian. Fallback after Salo is rescued.

**Reward range.** 300–600 credits plus whatever is looted from the hideout. Last chance to buy upgrades before the finale; make sure there's a shipwright on the way.

---

## Session 5: Last Light
**Premise.** In the heart of the Shroud is the Meridian beacon array. Lit with the lantern cores, it guides the lost fleet home and broadcasts the truth across the Drift. Vane's task force arrives to stop it.

**Map.** The array: three beacon platforms ("Defense platform", Independent, `setCanBeDestroyed(false)` until activated) in a triangle inside dense nebula. Vane's task force arrives in waves from the west. The Ghost fleet waits to the east, unseen until the array is lit.

**Mechanics.** Activate each beacon by holding position within 1u for 30 seconds while docked or stationary (Engineering must keep power up as the array drains energy: `setEnergy` drain). Each lit beacon reveals more of the truth via log and main-screen messages.

**Allies (from flags).** Rook if partner; Mags' hired guns if `mags_ally`; Lt. Vashti defects with CPV Diligence if `inspected` or `bribed_concord` and the crew defied Vane; Doc Salo broadcasting from Halcyon Rest if rescued. Each ally appears as an `ai = true` beat with a fallback, so the director can time the cavalry.

**Ending.**
- All three beacons lit: the Ghost fleet emerges (Unknown-faction ships, friendly), Vane's ships stand down or flee; Vane's final hail depends on `defied_vane` / `stalled_vane`. Victory.
- Magpie destroyed: campaign ends in tragedy; the director narrates an epilogue.
- If cores were sold in session 3 and not recovered, the array can still be lit at half strength with Salo's decoys; a bittersweet ending.

**Director guidance.** This is the finale. Escalate steadily, give every ally a moment, and voice the Unknown ships ("the Ghosts") for the first time: careful, old-fashioned, grateful. Avoid wiping the crew before the last beacon.

---

## Upgrade economy
The crew earns roughly 500 credits per session and upgrades cost 150–500 each, so they'll own 5–7 of the 10 by the finale. The jump drive (500) is the big one; session 2 can grant it. Raise enemy strength each session: session 1 uses scout/light groups, session 3 medium, and session 5 heavy waves. Adjust `DIR.config.max_ai_hostiles` per session too (5, 5, 6, 7, 8 on Normal).
