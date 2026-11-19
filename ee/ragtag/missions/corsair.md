# Corsair Arc — design notes

Phase II arc of the sandbox campaign (`ee/ragtag/missions/corsair.lua`). Campaign context:
`scenarios/sandbox/plan.md`, Arc 4. Linear: defend Blackwater, or don't do it.

## Premise

The Concord's second battle group (the Boneyard rumors' "two groups left Lumen") is coming for
Blackwater Reach. Many Corsairs are Settlement War Free Ship veterans and their children; most
ships at Blackwater are families. A raider that has been watching the crew brings them in, the
crew raids a Concord forward depot so the Corsairs can thicken Blackwater's mine ring with its
mines, and then stands in the Corsair line when Battle Group Two arrives.

## Trigger

`upgrades_min = 1000`, `corsair_arc_done` unset, and the Rezkov arc finished or declined (`requires`, like
Ledger and Boneyard: rewinding Rezkov resets a running Corsair arc). The arc starts and waits in `hook`; the hook
itself fires when the crew enters the Gauntlet (within 29U of (23, 69)).

## Phases

```
init ─► hook ─► escort ─► briefing ─► raid ─► return ─► battle ─► done
                                       (an escort lost is replaced at once)
```

| Phase | What happens | Leaves |
|---|---|---|
| `hook` | Three priority-5 rumors point to **Greywater Depot** ("the barkeep is holding a message for a freighter crew…"). Docked at Greywater: **"Heard you're holding a message for us."** → the barkeep's data chip: *Long Memory* waits at the Gauntlet's north edge (24, 45), objective set; it hails when the crew closes to 6U. Fallback: entering the Gauntlet spawns the raider 4.5U ahead. Either way the raider (Adder MK5, `Corsair Friendly`) opens comms: "We watch things in the Drift, and we know you are someone who is not intimidated by the Concord… Follow us." **Lead the way** / **Not right now** (raider leaves, hook stays open; Greywater and the Gauntlet re-offer after 10 min) / **Tell your people to forget us** (`declined`). | `corsair_hook` |
| `escort` | Corsair territory turns friendly (Gauntlet and Blackwater garrisons and the Blackwater station become `Corsair Friendly`; Gauntlet and Blackwater Reach PROX spawns suspended). Follow the guide. It paces the crew: once they are more than 5.5U behind it holds where it is (defending itself: `orderDefendLocation`, not idle) and leads on once they are back within 4.5U; it warps and the crew is slower, so it leads in short hops. Past 8U it says "Keep up. These rocks eat the careless." (once a minute at most). (It used to stop at 8U and only go on under 4U, so a crew that stopped and came back to 5-7U saw it sit there for good.) If Long Memory is destroyed on the way, the objective becomes "Dock at Blackwater" and the log gives Blackwater's grid; docking still moves on. Within 5U of Blackwater it hails: "I got you here safe. Dock with Blackwater to meet Reva and she'll fill you in." Docking at Blackwater moves on, and Long Memory flies off east and is removed a minute later. | `corsair_arrived` |
| `briefing` | Docked: "I'm Reva Okonkwo" (profile added): fierce fighters out in the Drift and guarding Blackwater, but most ships here are families; the Corsair tax ("only from Concord hulls or to defend our territory"); "Now the Concord means to settle the account for good, and we need help." "The Concord has provisioned a forward depot in preparation for a full-scale invasion and occupation of Blackwater. It sits between Cinder and Tamsin"; two ships for the crew. **We'll take the depot.** | `corsair_briefed` |
| `raid` | Forward Depot Anvil (-60, 62), two Concord Hostile Phobos guards. Escorts Hardtack and Ninth Life (Phobos T3, toughened to 100/100 shields and 120 hull, up from 50/40 and 70, so one mine (up to 160 damage) does not destroy one; replacements too. Corsair ships carry no prefix, they are ad hoc) answer comms. Always: **Form up on me**, **Hold position** (stand ground where they are), **Head to the depot** (fly to its east side, engaging on the way), **Head back to Blackwater** (to the Blackwater approach, north of its mine ring). Then **Attack the Concord defenders** (crew within 7U of the depot, guards alive) and **Board the depot and take the weapons** (guards dead). When the guards are down the depot crew surrenders: the depot turns `Concord Surrendered` (a Concord faction that is nobody's enemy, `verse.lua`; plain `Concord` would make the Corsair escorts fire on it whenever they are near and not docking), nobody keeps shooting at it, and the escorts dock with it to load. The crew does not board: the escorts dock (or close to 1.8U), load for 30 s, hailing as they start ("Gao yang jong duh goo yang... we hit the jackpot. Mines, missiles, the lot. Loading it all now.") and when done ("Haul's aboard: mines, missiles, the lot. Meet you back at Blackwater.") Each escort lost in the raid is replaced at once: Reva hails from Blackwater ("We lost Hardtack. I'm sending Second Wind out to you. Look after her.") and the new ship (an ad hoc name not already flying: Second Wind, Last Laugh, Scrap Iron, …) warps out and forms up on the crew. No limit. (This replaced the earlier rule that losing both restarted the raid.) | `corsair_raid_done` |
| `return` | Docked: Reva thanks the crew; **the haul's mines thicken Blackwater's mine ring now** (see "The mine ring"). No mines for the crew's rack. "And just in time too. News is the Concord attack fleet was just detected at grid … will you fly out and join our defense?" **We'll stand with you** / **This isn't our fight** (`failed`: the defense started without them). Standing with them (the battle phase starts here) brings Reva's advice: "I've heard your hackers are second to none. If you can hack their big ships, that gives us a much better shot at winning this thing. Also, since we took out their supply depot, they have a limited supply of missiles, so once they run out they'll be sitting ducks. Any distraction your awesome piloting can provide improves our odds." → **Understood. We're on our way.** → where the Corsair line is forming. | `corsair_joined` |
| `battle` | A set piece played like the Battle Lab (`ragtag/battle.lua`; see "The battle"). Both lines spawn frozen west of Blackwater; the battle starts when the crew's ship comes within 5U of any battle ship, Concord or Corsair. The raid escorts go home and dock at Blackwater, sitting it out. **All 7 Concord ships destroyed, however that happens → `defended`. The crew's ship destroyed → `failed`.** The Corsairs may all be lost without failing; Blackwater is indestructible for the battle. Rearming: see "The tender". | `corsair_arc_done` |

### The mine ring

The raid brought back mines and missiles (no jammers). The mines go into Blackwater's own ring
(drift.lua: 26 places at 9U, with gaps of ±25° at north and at west, 270°; the west gap is where
the raid escorts leave, since they start west of the station and cross the ring at about 282°): one more band, laid in a hurry: steps of
3.2–3.8° (0.5–0.6U), the radius drifting up to 0.12U a step within ±0.5U of 9U plus a slow wobble
(~80 mines). Three lanes stay open (angles are headings, 0 = north): the old **north** opening
(±25°), and two narrow lanes placed between two of the old ring's mines at **103.85°**
(east-south-east) and **256.15°** (west-south-west), ±6.9° (about 2.2U of open water). The new band
closes the rest of the west gap: after the raid the way west is the narrow WSW lane. New mines
keep a degree clear of every lane. Kept in `st.mines`; cleared on a reset and 3 minutes after the
arc ends. Laid at the debrief (`return`), or on entering `battle`.

### The battle

`BATTLE` (`ee/ragtag/battle.lua`), the same rules as the Battle Lab (scenario 63):
- **Where:** five invisible combat points on a north-south line through (30, 99), 1.5U apart, 25U
  west of Blackwater. The Concord line 10U west of them (x 20), the Corsair line 10U east (x 40,
  ~6U outside the ring), both 2U apart.
- **Who:** Battle Group Two, 7 ships: CNS Retribution, Remand, Injunction (Atlantis X23) and CNS
  Writ, Summons, Levy, Distraint (Phobos T3), no nukes. 12 fresh Corsairs: Adder MK5, Adder MK5,
  Piranha F12, … (Hearthstone, Second Chance, Long Odds, Short Fuse, Dead Weight, Hollis, Fair
  Warning, Low Tide, Tin Can, Hard Luck, Iron Will, Stray Dog).
- **Frozen start:** everything spawns as the battle phase begins, but waits (no impulse, no
  turning) until the crew's ship comes within 5U of any battle ship (Concord or Corsair). Then the Concord broadcasts its
  ultimatum, Reva calls "Here they come. Hold the line!" and the objective becomes "Destroy Battle
  Group Two".
- **Rules:** no warp; speeds normalized (Adder 120/28/25, Phobos 104/18.4/17.5, Piranha 88/21.2/21.5
  with its tweak, Atlantis 80/15/15); each side mapped north to south onto the points (Corsairs
  2/3/2/3/2, Concord 1/2/1/2/1 by position); a ship whose point has no enemies left moves to the
  nearest point that has some; Corsair missile top-ups at 25%.
- GM: **Start battle** (start it now), **Kill fleet** (destroy Battle Group Two: `defended`).

### The tender

The raid brought back more than mines. **Magazine** (Flavia, `Corsair Friendly`, stand ground) holds
the rest of the Anvil haul at (43, 82): behind the north end of the Corsair line, clear of
Blackwater's ring. When the crew's missile racks (homing, HVLI, mines, EMP, whatever the ship carries) are
at or below 25%, it hails ("Your racks are nearly empty… come alongside at <grid>") and a second
objective line appears: "Rearm alongside Magazine (<grid>)". Within 1.2U for 8 s refills every
rack to its maximum. Three loads aboard; it calls again each time the racks run low while loads are
left. Hailing it says how many loads are left, or "The haul is gone". It is destructible: if the
Concord gets to it, Reva says so and the objective goes. Arc ship only (other ships get "Corsair
business. Keep clear.").

### Keeping Corsairs out of their own mines

Blackwater has its mine ring (thickened by the haul). Corsair ships sent "to Blackwater" (Long
Memory, raid escorts coming home or told to head back) go to the **Blackwater approach**, (55, 87):
12U north of the station, in front of the ring's north opening, never inside the ring; with `dock`
(the raid escorts during the battle) they then dock at Blackwater through that opening. The battle
lines are outside the ring. (Playtest: ships flying to a point inside the ring hit its mines.)

## Exports

| Flag | Values |
|---|---|
| `corsair_arc_done` | `"defended"` / `"failed"` / `"declined"` |
| `corsair_ally` | true on defended: Gauntlet/Blackwater Corsairs stay `Corsair Friendly` and their PROX zones stay suspended (re-applied every session in `on_load`); Blackwater is dockable |
| `corsair_battlegroup_destroyed` | true on defended (Arc 6 trigger) |
| `corsair_met_reva` | Reva's Science DB profile |

Victory: Blackwater hails "The Concord battle group is destroyed! Victory is ours, but at a great cost.
The pirate families of Blackwater owe you our thanks. Safe flying and see you around, <ship>!" and
the arc ends; the surviving Corsairs head for the Blackwater approach and, with everything else the
battle left, are removed 5 minutes later.

Rewards (once): defended → Corsair standing to +500 if it was 0 or below, else +500 on top; Concord −300. Failed/declined → nothing; Corsair
territory reverts to hostile. `CORSAIR_DONE` rumors either way.

## GM console

`→ Hook`, `→ Escort`, `→ Briefing`, `→ Raid`, `→ Return`, `→ Battle`, `→ Done: Defended`,
`→ Done: Failed`, `→ Done: Declined` (+ engine `→ Inactive`). Helpers: **Raider now** (hook),
**Kill defenders** / **Finish loading** (raid), **Start battle** / **Kill fleet** (battle).
Resets restore Corsair territory to hostile, clear the ring's new mines, the depot and the battle.

## Tuning (top of `corsair.lua`)

The battle: `_BATTLE_X/Y` (30, 99), `_LINE_U` 10U, `_START_U` 5U, `_CONCORD_HULLS` / `_NAMES`,
`_CORSAIR_HULLS` / `_NAMES` (the rules themselves are in `ee/ragtag/battle.lua`); the ring:
`_RING_R` 9U, `_RING_LANES`; `_LOAD_TIME` 30 s, `_GUIDE_HOLD_D` 5.5U, `_GUIDE_GO_D` 4.5U, `_GUIDE_WAIT_D` 8U; tender: `_TENDER_X/Y`, `_RELOADS` 3, `_RELOAD_R` 1.2U, `_RELOAD_TIME` 8 s,
`_LOW_AT` 0.25. Playtest: whether three loads is the right amount, escort-vs-guard fight length (two Phobos each side was still
going after 45 s headless), battle length and ally count (the Blackwater garrisons fight too).
