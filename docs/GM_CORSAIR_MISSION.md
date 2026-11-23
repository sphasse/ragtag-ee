# The Corsair Arc — GM guide

A Phase II story arc of The Drift (sandbox campaign, scenario 80). **Spoilers**: keep this away from
players. Module: `ee/ragtag/missions/corsair.lua` (the battle: `ee/ragtag/battle.lua`). Back to the
[GM guide](GM_GUIDE.md). Linear: defend Blackwater, or don't.

## Premise

A Concord battle fleet is coming for Blackwater Reach to settle the Corsair problem for good while
the Drift is distracted. Many Corsairs are Settlement War Free Ship veterans and their children,
pushed into raiding by the "transitional" tariffs; most ships at Blackwater are families. A raider
that has been watching the crew brings them in. The crew raids a Concord forward depot so the
Corsairs can thicken Blackwater's mine ring with its mines, then stands in the Corsair line when the
fleet arrives.

Where it sits in the campaign:

- **It is the ally thread.** Win, and the Corsairs of the Gauntlet and Blackwater stay friendly to
  the crew for good (`corsair_ally`): Blackwater becomes a port they can dock at, and a Corsair wing
  flies with them in the finale. The arc turns the Drift's most dangerous faction into an option for
  future Corsair stories.
- **It introduces Reva Okonkwo**, Blackwater's quartermaster and an ex-Free Ship gunnery chief: the
  Corsairs' voice from here on.
- **It costs the Concord a battle fleet.** The rumors at the start of the Boneyard arc say two groups
  left Lumen; this is one of them (never numbered, since the crew may meet them in either order).
  Destroying it (`corsair_battlegroup_destroyed`) further destabilizes the Concord: with its battle
  groups gone it rebuilds at Sentinel Fleet Yard, which is the setting of the Hob Works heist and
  the start of the Concord's fracture.
- **It makes the Corsairs' side of the story.** Reva's briefing reframes "pirates" as families and
  tariff refugees, so the crew's choice to stand with them means something.

## Triggers

- **≥ 1,000 cr** of upgrades on the primary ship (the Magpie).
- The Rezkov arc finished (any outcome) **or declined**. Rewinding Rezkov resets a running Corsair arc.
- `corsair_arc_done` not set.

The arc starts and waits in its hook. *Long Memory* only appears after the crew has the Greywater
barkeep's message; entering the Gauntlet doesn't bring it.

## Phases

```
hook ─► escort ─► briefing ─► raid ─► return ─► battle ─► done
                                (an escort lost is replaced at once)
```

### Hook

Three rumors point to **Greywater Depot** ("the barkeep is holding a message for a freighter
crew…"). Docked at Greywater: **"Heard you're holding a message for us."** The barkeep's data chip
says *Long Memory* is waiting at the Gauntlet's north edge (24, 45), and the objective is set.

The raider (Adder MK5, `Corsair Friendly`) hails when the crew closes to 6U: "We watch things in the
Drift, and we know you are someone who is not intimidated by the Concord… Follow us."
- **Lead the way** → the escort.
- **Not right now** → the raider leaves; Greywater re-offers the message after 10 minutes.
- **Tell your people to forget us** → ends **declined**.

### Escort

Corsair territory turns friendly for now: the Gauntlet and Blackwater garrisons and Blackwater itself
become `Corsair Friendly`, and Corsair patrols in the Gauntlet and Blackwater are suspended.

The crew follows *Long Memory*. It paces them: more than 5.5U behind, it holds (and defends itself);
within 4.5U, it leads on. It has no warp but cruises at warp-1 speed (30 U/min), so the crew follows at
warp 1. It goes through the north gap of Blackwater's mine ring, slows within 3U of the station, and
docks. Past 8U it says "Keep up. These rocks eat the careless." (once a minute at most). Within 5U of
Blackwater it hails: "Dock with Blackwater to meet Reva and she'll fill you in."

If *Long Memory* is destroyed on the way, the objective becomes "Dock at Blackwater" with its grid;
docking still moves the arc on.

### Briefing

Docked at Blackwater: **"I'm Reva Okonkwo"** (profile added). Fierce fighters out in the Drift, but
most ships here are families; the Corsair tax is "only from Concord hulls or to defend our territory".
The Concord has provisioned a **forward depot between Cinder and Tamsin** for a full-scale invasion,
and Reva lends the crew two ships to take it. **We'll take the depot.**

### Raid

**Forward Depot Anvil** at (−60, 62), guarded by two Concord Hostile Phobos T3. The escorts, *Hardtack*
and *Ninth Life* (Phobos T3, toughened to 100/100 shields and 120 hull), take orders over comms:
- Always: **Form up on me**, **Hold position**, **Head to the depot**, **Head back to Blackwater**.
- Within 7U of the depot, guards alive: **Attack the Concord defenders**.
- Guards dead: **Board the depot and take the weapons**.

When the guards are down the depot surrenders (`Concord Surrendered`: nobody fires on it). The crew
doesn't board: the escorts dock, load for 15 s, and hail: "…we hit the jackpot. Mines, missiles, the
lot, all aboard. Heading back to Blackwater. Meet you there."

**An escort lost is replaced at once**, with no limit: Reva hails ("We lost Hardtack. I'm sending Second
Wind out to you. Look after her.") and the new ship warps out to form up.

### Return

Docked at Blackwater: Reva thanks the crew, and **the haul's mines go into Blackwater's mine ring now**
(no mines for the crew's racks). "News is the Concord attack fleet was just detected at grid … will you
fly out and join our defense?"
- **We'll stand with you** → Reva's advice (hack their big ships; they're short of missiles since the
  depot fell; any distraction helps), then **Understood. We're on our way.** → the battle.
- **This isn't our fight** → ends **failed** (the defense went on without them).

### Battle

Seven Concord ships and twelve Corsairs spawn in two lines 25U west of Blackwater, **frozen** until any
player ship comes within 5U of any battle ship. Then the Concord broadcasts its ultimatum, Reva calls
"Here they come. Hold the line!", and the objective is "Destroy the Concord battle fleet". The raid
escorts go home and sit it out.

- **All seven Concord ships destroyed**, by anyone → ends **defended**.
- **The crew's ship destroyed** → ends **failed**. The Corsairs can all be lost without failing.

**Rearming.** The tender **Magazine** waits at (43, 82), behind the north end of the Corsair line. When
the crew's missile racks fall to 25%, it hails with its grid and a second objective appears, "Rearm:
Magazine <grid>". Within 1.2U for 8 s refills every rack. Three loads; it can be destroyed.

### Done

On a win Blackwater hails: "The Concord battle group is destroyed! Victory is ours, but at a great
cost…". The surviving Corsairs head home, and everything the battle left is removed 5 minutes later.

## GM console

**Missions… → Corsair Arc**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ Hook` / `→ Escort` / `→ Briefing` / `→ Raid` / `→ Return` / `→ Battle` | Jump to that phase |
| `→ Done: Defended` / `→ Done: Failed` / `→ Done: Declined` | End the arc |

Helpers, shown only in their phase:
- **Raider now** (hook): *Long Memory* appears 4.5U from the crew and hails, without the barkeep's message.
- **Kill defenders** (raid): destroys the depot guards. **Finish loading**: the guards go, the depot
  surrenders and the escorts' loading is done.
- **Start battle** (battle): unfreeze the lines now. **Kill fleet**: destroy the Concord fleet
  (ends defended).

A reset turns Corsair territory hostile again and removes the ring's new mines, the depot and the
battle. Rewards are paid once (`corsair_rewarded`).

## Exports

| Flag | Values |
|---|---|
| `corsair_arc_done` | `"defended"` / `"failed"` / `"declined"` (the finale: any value) |
| `corsair_ally` | true on defended: the Gauntlet and Blackwater Corsairs stay `Corsair Friendly`, their patrols stay suspended (re-applied every session) and Blackwater is dockable. The finale's Corsair wing |
| `corsair_battlegroup_destroyed` | true on defended: the Concord rebuilding (Hob Works backstory; Arc 6 option) |
| `corsair_met_reva` | Reva's Science DB profile |

Rewards, once: **defended** → Corsair standing to +500 if it was 0 or below, otherwise +500 on top;
Concord −300. **Failed / declined** → nothing, and Corsair territory turns hostile again.

**News** (rumors at any port from the end of the arc; each is told once, then retired from later
sessions; the lines are in `ee/ragtag/missions/_aftermath.lua`):
- Defended: "A whole Concord battle group died off Blackwater. The Corsairs are calling it the Second
  Settlement.", and Fleet Command pulled two squadrons off the Arbiter Line to cover the hole, leaving the
  Border stretched thin and the tariff collectors nervous.
- Failed: "Blackwater's burning, they say…", and the Concord is handing out medals for it, though half
  the Border stations wouldn't fly the flag for the ceremony.
- Declined: none.

## Design notes

### The mine ring

Blackwater's own ring (`drift.lua`): 26 mines at 9U, with gaps of ±25° at north and at west (270°). The
west gap is where the raid escorts leave. The haul adds one band, laid in a hurry: steps of 3.2–3.8°
(0.5–0.6U), the radius drifting within ±0.5U of 9U with a slow wobble, about 80 mines. Three lanes stay
open (headings, 0 = north):
- the old **north** opening (±25°);
- **103.85°** (east-south-east), ±6.9°, about 2.2U of open water;
- **256.15°** (west-south-west), ±6.9°.

The new band closes the rest of the west gap. New mines keep a degree clear of every lane. They are kept
in `st.mines`, laid at the debrief (or on entering the battle), and cleared on a reset and 3 minutes
after the arc ends.

### Keeping Corsairs out of their own mines

Corsair ships sent "to Blackwater" (*Long Memory*, the raid escorts) go to the **Blackwater approach**,
(55, 87), 12U north of the station in front of the north opening, never inside the ring. With `dock`
they then dock through that opening. (Playtest: ships flying to a point inside the ring hit its mines.)

### The battle

`BATTLE` (`ee/ragtag/battle.lua`), the Battle Lab's rules (scenario 63):
- **Where:** five invisible combat points on a north-south line through (30, 99), 1.5U apart. The
  Concord line 10U west of them, the Corsair line 10U east (about 6U outside the ring), ships 2U apart.
- **Who:** CNS *Retribution*, *Remand*, *Injunction* (Atlantis X23) and CNS *Writ*, *Summons*, *Levy*,
  *Distraint* (Phobos T3), no nukes. Twelve fresh Corsairs (Adder MK5, Piranha F12, …: *Hearthstone*,
  *Second Chance*, *Long Odds*, …).
- **Rules:** no warp; normalized speeds (Adder 120, Phobos 104, Piranha 88, Atlantis 80); each side
  mapped north to south onto the points (Corsairs 2/3/2/3/2, Concord 1/2/1/2/1); a ship whose point
  has no enemies left moves to the nearest one that has; Corsair missile top-ups at 25%.
- **Why frozen:** ships that wait don't fight back, so nobody gets to pick them off before it starts.

### The escort's pacing

*Long Memory* used to warp in short hops (awkward to follow) and to stop at 8U and only go on under 4U,
so a crew that came back to 5–7U saw it sit there for good. It now cruises on impulse at warp-1 speed
(`_GUIDE_IMPULSE` 500), slows to 100 within 3U of Blackwater to dock, and holds and leads at 5.5U / 4.5U.
It used to stop at the approach; now it takes the crew all the way to the port.

### Depot loading

The escorts dock with the depot (EE docks on contact) and load for 15 s (`_LOAD_TIME`). The clock
starts on a real docking, or after 30 s alongside within 1.8U without one (`_DOCK_GRACE`), so it can't
stall. Plain `Concord` on the surrendered depot would have made the escorts fire on it; `Concord
Surrendered` is a Concord faction that is nobody's enemy (`verse.lua`).

### History

- Escort replacement (one at a time, no limit) replaced "losing both restarts the raid" (2026-11-18).
- The battle was reworked after the Battle Lab (2026-11-18).
- The Gauntlet no longer brings *Long Memory* (a playtest found it hailing before the crew had heard
  of it).
- Decided 2026-11-15: one prep mission (the depot raid only); declining the battle after the raid
  counts as failed, and declined only comes from turning down the hook.

### Tuning (top of `corsair.lua`)

The battle: `_BATTLE_X/Y` (30, 99), `_LINE_U` 10U, `_START_U` 5U, `_CONCORD_HULLS` / `_NAMES`,
`_CORSAIR_HULLS` / `_NAMES`. The ring: `_RING_R` 9U, `_RING_LANES`. The raid: `_LOAD_TIME` 15 s,
`_DOCK_GRACE` 30 s. The guide: `_GUIDE_HOLD_D` 5.5U, `_GUIDE_GO_D` 4.5U, `_GUIDE_WAIT_D` 8U. The tender:
`_TENDER_X/Y`, `_RELOADS` 3, `_RELOAD_R` 1.2U, `_RELOAD_TIME` 8 s, `_LOW_AT` 0.25.

Open for playtest: whether three loads is right; how long the escorts take against the depot guards (two
Phobos a side were still fighting after 45 s headless); the battle's length and ally count (the
Blackwater garrisons fight too).

### Testing

`tools/game_tests.py --ee <EE dir> arcs/corsair` (`tests/arcs/corsair.lua`). The real flight through
the mine gap and the real battle are playtest items.
