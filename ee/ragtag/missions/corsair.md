# Corsair Arc — design notes

Phase II arc of the sandbox campaign (`ee/ragtag/missions/corsair.lua`). Campaign context:
`scenarios/sandbox/plan.md`, Arc 4. Linear: defend Blackwater, or don't do it.

## Premise

The Concord's second battle group (the Boneyard rumors' "two groups left Lumen") is coming for
Blackwater Reach. Many Corsairs are Settlement War Free Ship veterans and their children; most
ships at Blackwater are families. A raider that has been watching the crew brings them in, the
crew raids a Concord forward depot so the Corsairs can turn its mines and jammers into a trap,
and then helps hold the wall when Battle Group Two arrives.

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
| `escort` | Corsair territory turns friendly (Gauntlet and Blackwater garrisons and the Blackwater station become `Corsair Friendly`; Gauntlet and Blackwater Reach PROX spawns suspended). Follow the guide; it waits if the crew is > 8U behind ("Keep up. These rocks eat the careless."). Within 5U of Blackwater it hails: "I got you here safe. Dock with Blackwater to meet Reva and she'll fill you in." Docking at Blackwater moves on, and Long Memory flies off east and is removed a minute later. | `corsair_arrived` |
| `briefing` | Docked: "I'm Reva Okonkwo" (profile added): fierce fighters out in the Drift and guarding Blackwater, but most ships here are families; the Corsair tax ("only from Concord hulls or to defend our territory"); "Now the Concord means to settle the account for good, and we need help." "The Concord has provisioned a forward depot in preparation for their invasion of Blackwater", between Cinder and Tamsin; two ships for the crew. **We'll take the depot.** | `corsair_briefed` |
| `raid` | Forward Depot Anvil (-60, 62), two Concord Hostile Phobos guards. Escorts Hardtack and Ninth Life (Phobos T3; Corsair ships carry no prefix, they are ad hoc) answer comms. Always: **Form up on me**, **Hold position** (stand ground where they are), **Head to the depot** (fly to its east side, engaging on the way), **Head back to Blackwater** (through the gap once the wall exists). Then **Attack the Concord defenders** (crew within 7U of the depot, guards alive) and **Board the depot and take the weapons** (guards dead). When the guards are down the depot crew surrenders: the depot turns `Derelict` (neutral), nobody keeps shooting at it, and the escorts dock with it to load. The crew does not board: the escorts dock (or close to 1.8U), load for 30 s, then hail "We're loading up the haul now… Meet you back at Blackwater." Each escort lost in the raid is replaced at once: Reva hails from Blackwater ("We lost Hardtack. I'm sending Second Wind out to you. Look after her.") and the new ship (an ad hoc name not already flying: Second Wind, Last Laugh, Scrap Iron, …) warps out and forms up on the crew. No limit. (This replaced the earlier rule that losing both restarted the raid.) | `corsair_raid_done` |
| `return` | Docked: Reva thanks the crew. **The trap spawns now** and the crew's rear rack gets 4 mines. "And just in time too. News is the Concord attack fleet was just detected at grid … will you fly out and join our defense?" **We'll hold the wall** / **This isn't our fight** (`failed`: the defense started without them). | `corsair_joined` |
| `battle` | Battle Group Two spawns west of the wall and flies scripted waypoints (FlyTowards, advance within 1.5U) along the wall's west face, through the gap, to Blackwater. Concord ships drop combat warp jammers on the crew (`PROX.tickCombatJammers`). Allies: two Piranha missile boats beside the gap (Blackwater side), two retrofitted family gunboats (Adder MK5) at Blackwater, raid survivors, plus Blackwater's own garrisons. All six Concord ships destroyed → `defended`. Blackwater hull < 20% → `failed` (the station is made indestructible for the battle). Rearming: see "The tender" below. | `corsair_arc_done` |

### The trap

- Wall at x ≈ 36U from the Gauntlet belt (y 75U) south to y 120U, on the western edge of the Veil.
- Stock scripted `Mine()`s laid pirate-style: steps of 0.45–0.55U, sideways drift ≤ 0.3U per
  step, a slow bend; neighbours are never more than 0.7U apart (trigger radius 0.6U). Headless:
  86 mines, max neighbour distance 0.62U.
- One 3U gap at y 91U (grid J6). Wall mines' AI avoid bubble is 0.8U (stock 1.2U would leave the
  AI no gap); trigger and blast stay stock.
- Corsair warp jammers: (30, 97) r 3U on the approach and (37.5, 91) r 2.5U at the gap.
- Battle Group Two: CNS Retribution and CNS Remand (Atlantis X23), CNS Writ, Summons, Levy and
  Distraint (Phobos T3). Spawn (14, 112); waypoints (31,110) → (31,95) → (33.5,91) → (39,91) →
  Blackwater.
- Headless: the fleet threads the gap with no mine casualties and no stalls, slowly (Atlantis at
  impulse in the jammer field: about 2 minutes from the gap mouth to the far side).

### The tender

The raid brought back more than mines. **Magazine** (Flavia, `Corsair Friendly`, stand ground) holds
the rest of the Anvil haul at (43, 82): behind the wall, north of the fleet's road from the gap to
Blackwater. When the crew's missile racks (homing, HVLI, mines, EMP, whatever the ship carries) are
at or below 25%, it hails ("Your racks are nearly empty… come alongside at <grid>") and a second
objective line appears: "Rearm alongside Magazine (<grid>)". Within 1.2U for 8 s refills every
rack to its maximum. Three loads aboard; it calls again each time the racks run low while loads are
left. Hailing it says how many loads are left, or "The haul is gone". It is destructible: if the
Concord gets to it, Reva says so and the objective goes. Arc ship only (other ships get "Corsair
business. Keep clear.").

### Keeping Corsairs out of their own mines

Corsair ships never cross the wall: any that is west of it when sent to Blackwater (the raid escorts
coming home, "Head back to Blackwater", the survivors joining the battle) flies to the gap's west
mouth (33.5, 91), through to (39, 91), then on to Blackwater (`_sendHome`, `_tickRoutes`). The two
gap missile boats (Long Odds, Hollis) stand ground instead of defending a location, so they fire on
the fleet from where they are and never chase it into the mines. (Playtest: a Corsair ship hit its
own mine.)

## Exports

| Flag | Values |
|---|---|
| `corsair_arc_done` | `"defended"` / `"failed"` / `"declined"` |
| `corsair_ally` | true on defended: Gauntlet/Blackwater Corsairs stay `Corsair Friendly` and their PROX zones stay suspended (re-applied every session in `on_load`); Blackwater is dockable |
| `corsair_battlegroup_destroyed` | true on defended (Arc 6 trigger) |
| `corsair_met_reva` | Reva's Science DB profile |

Rewards (once): defended → Corsairs +400, Concord −300. Failed/declined → nothing; Corsair
territory reverts to hostile. `CORSAIR_DONE` rumors either way.

## GM console

`→ Hook`, `→ Escort`, `→ Briefing`, `→ Raid`, `→ Return`, `→ Battle`, `→ Done: Defended`,
`→ Done: Failed`, `→ Done: Declined` (+ engine `→ Inactive`). Helpers: **Raider now** (hook),
**Kill defenders** / **Finish loading** (raid), **Fleet to gap** / **Kill fleet** (battle).
Resets restore Corsair territory to hostile, clear the trap, depot, fleet and allies.

## Tuning (top of `corsair.lua`)

Wall geometry (`_WALL_*`, `_GAP_*`, `_MINE_*`), `_TRAP_JAMMERS`, `_FLEET` and
`_FLEET_WAYPOINTS`, `_LOAD_TIME` 30 s, `_PLAYER_MINES` 4, `_BW_FALLS_AT` 0.2,
`_GUIDE_WAIT_D` 8U; tender: `_TENDER_X/Y`, `_RELOADS` 3, `_RELOAD_R` 1.2U, `_RELOAD_TIME` 8 s,
`_LOW_AT` 0.25. Playtest: whether three loads is the right amount, escort-vs-guard fight length (two Phobos each side was still
going after 45 s headless), battle length and ally count (the Blackwater garrisons fight too).
