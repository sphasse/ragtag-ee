# The Holdout — GM guide

Module: `ee/ragtag/missions/holdout.lua` (id `holdout`). Test: `tests/arcs/holdout.lua`.

## Premise

Breaker's Claim is a handful of rock crews working the asteroids just south of the Shroud. The Shroud
Raiders, Corsair crews who never answered to Blackwater, have hit the camp twice this year for a cut.
Now they have sent word: this time they are taking the whole claim. Foreman Ines Calloway has cutting
lasers bolted to the hull, one fighter and every credit the camp has. She hires the crew to stand with
the Claim until the raiders give up.

Where it sits in the campaign:

- **A one-off money job** (inspired by The Mandalorian's "Sanctuary" and Seven Samurai): 3,000 cr for
  holding the Claim. It can come at any time after Rezkov, before or after the heist.
- **A defense fight**, unlike the stealth and chase jobs: everyone on the bridge has something to do,
  and the crew chooses where to fight.
- **It introduces the Shroud Raiders** as their own faction: Blackwater can become the crew's friend,
  the Shroud's crews can't. They patrol the Shroud, Halcyon Rest and the Deep Shroud.
- **It introduces Breaker's Claim** (a new permanent port, with a job board) and **Ines Calloway**
  (Science DB profile), a Rim contact for later stories.
- **Kept for later**: negotiating with the raiders (half the ore for a peaceful leave).

## Triggers

- **Rezkov over** (`rezkov_arc_done`, or `rezkov_declined`) and **1,500 cr of upgrades** (a ship with
  some fight in it).
- It starts on its own (`auto_start`), in the hook phase. Nothing is seeded while it waits.

## Phases

```
hook ─► defend ─► done (defended | fallen | lost)
```

### Hook

**Seed rumors** at Independent ports, from the moment it starts (priority 3, mixed into the news):
- "Breaker's Claim is hiring guns. The Shroud Raiders have hit them twice this year, and this time they
  mean to stay." Hearing this one sets the objective **"Breaker's Claim"**.
- "The raiders in the Shroud never did take Blackwater's terms. They take whatever they like, and lately
  what they like is Breaker's Claim."
- "The miners at Breaker's Claim bolted cutting lasers to their hull. Brave. Won't be enough, I hear."

Docked at **Breaker's Claim** (south of the Shroud, about 18U north of Hob's Landing),
**"[SPECIAL] Calloway's offer"** opens two pages (Calloway's Science DB profile is added):
1. Calloway and the threat: the raiders are coming for "the whole claim, rocks, crews and all. We've
   got cutting lasers on the hull and one fighter. That won't hold them."
2. The raid and the pay: "They'll come out of the fog north of us, in waves, round both sides of the
   rocks. Some will go for the Claim, some for whoever's defending it." 3,000 credits, "every credit
   we've got". "Once you say yes, you'll have about a minute to get in position."

**We'll stay.** goes to Defend; **Not right now.** leaves the offer open.

### Defend

Objective **"Defend the Claim"**; the Science DB gets **Lore > The raid on Breaker's Claim** (the job,
the waves, the Claim, the raiders). "The raiders are coming out of the Shroud, north of the Claim.
About 60 seconds."

- **The Claim is reinforced** for the raid: hull 500 (stock 150), shields 300. Its two **cutting
  lasers** (3U, 6 damage every 4 s) fire on the nearest raider in range. Its station fighter (every
  Independent port has one) joins in.
- **Three waves** of Shroud Raiders come out of the nebula from two gates about 19U north of the Claim,
  west and east of its rocks, at impulse (no warp, no nukes):
  1. two MT52 Hornets and an Adder MK5
  2. two Adder MK5s and a Phobos T3
  3. two Phobos T3s, an Adder MK5 and an MT52 Hornet
- In each wave the first, third, ... raider **goes for the Claim**; the second, fourth, ... **for the
  Magpie**. The ones on the Claim ignore the Magpie: shoot them first.
- When the last raider of a wave is gone: "Wave N beaten. The next one is coming: 45 seconds."
  Objective **"Hold: wave N next"**, then **"Hold: wave N of 3"** while one is under way.
- Shroud patrols are held off for the raid (the Shroud zone is suspended).
- Destroying a raider costs no standing (the Shroud Raiders have none).

The end:
- **All three waves beaten:** Calloway hails: "That's the last of them. They're running for the fog...
  3,000 credits, as promised, and a name on our list." **3,000 cr, Independent +150**. Outcome
  `defended`.
- **The Claim's hull at 15%:** "Breaker's Claim is burning. Calloway's ordering the crews into the
  lifeboats." No pay. Outcome `fallen`. (Ports can't be destroyed; it is patched up afterwards.)
- **The Magpie lost** during the raid: "With the Magpie gone, the raiders took Breaker's Claim."
  Outcome `lost`.

### Done

The Claim's lasers come down and it goes back to its own hull and shields. Raiders still out there fly
back into the fog and are removed 90 seconds later. The news follows (Exports).

## GM console

**Missions… → The Holdout**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ Hook` | The seed rumors again; not briefed |
| `→ Defend` | Briefed; the Claim reinforced; the first wave in a minute |
| `→ Done: Defended` / `→ Done: Fallen` / `→ Done: Lost` | End states (no payment) |

Helpers, shown only in their phase:
- **Ship → Claim** (hook, defend): put the Magpie 5U away, undocked and stopped.
- **Next wave now** (defend, between waves): skip the wait.
- **Kill this wave** (defend): remove the raiders of the wave under way (the next one follows after the gap).
- **Repair the Claim** (defend): full hull.

The state line reads e.g. "Wave 2: 3 left, Claim 84%" or "Wave 3 next, Claim 60%".

A jump resets the arc (the raiders, the Claim's lasers and hull, the rumors, the objective, the
`holdout_*` flags) and replays the earlier phases. Reputation and credits are not applied by a jump.
After a session ends mid-raid, the next session starts the raid over (a minute, then wave 1).

## Exports

| Flag | Values |
|---|---|
| `holdout_arc_done` | `"defended"` / `"fallen"` / `"lost"` |

Standing: Independent +150 when defended.

Science DB: the profile of **Ines Calloway**; Lore → **"The raid on Breaker's Claim"**. The Shroud
Raiders have a Factions entry and Breaker's Claim a Ports entry from the start (not arc entries).

News (`missions/_aftermath.lua`, category `HOLDOUT_DONE`, each told once):
- Defended: "Breaker's Claim held off the Shroud Raiders. Calloway's crews are back on the rocks, and
  they've put a new name on their wall." / "The Shroud Raiders lost three waves of ships at Breaker's
  Claim. They're quieter in the fog these days."
- Fallen or lost: "The Shroud Raiders burned Breaker's Claim. Calloway's crews got out in the lifeboats.
  She says they'll be back on the rocks by spring."

Achievement (hidden): **Hold the Line** (defended).

## Design notes

### State (`st.*`)

`wave` (under way, 0 before the first), `raiders` (the wave's ships), `next_at` (when the next wave
comes; nil while one is under way), `armed`, `laser_target`, `lasers_at`, `serial` (raider names).
The Claim's own hull and shields are kept outside the state (by entity), so a jump or a restart never
notes the reinforced values as its own.

### Saved flags

`holdout_briefed`, `holdout_rewarded`, `holdout_arc_done`, `holdout_met_calloway` (profile).

### The Shroud Raiders (world change, 2026-11-24)

- Faction **Shroud Raiders** (`verse.lua`): enemy of Independent, Concord, Concord Hostile, Corsair
  Friendly, Hollow and Relic; neutral to Blackwater's Corsairs (they are Corsairs by origin). In
  `VERSE.HOSTILE_FACTIONS`, not in `RT.KILL_PENALTY_FACTIONS`.
- Patrol zones (`world/proximity.lua`): the Shroud and Halcyon Rest moved from Corsairs to Shroud
  Raiders, and **the Deep Shroud** is a new zone (240 s). Their own names and taunt ("Blackwater's rules
  don't reach in here. Cut your engines and open your hold."). Corsair standing no longer changes their
  rate.

### Breaker's Claim

A Small Station at (80, 27) in `verse/drift.lua`, south of the Claim's rocks (78, 16, r 8) and 6U clear
of the Shroud's nebulae; in the Rim, not the Shroud region. Like every port it can't be destroyed, so
"fallen" is the hull at `FALL_AT`. Shop: repair.

### Engine notes

- The Claim's lasers: a station has no AI to aim, so once a second the arc sets
  `components.weapons_target` to the nearest raider in range (as the Boneyard's Annex). Heat and energy
  per shot are 0.
- Raiders on the Claim use `orderAttack(claim)`, so they don't turn on the Magpie; the others
  `orderAttack(magpie)`. Not `BATTLE`: one small wave at a time against a station needs no combat points.

### Tuning (top of `holdout.lua`)

`UPGRADES_MIN` 1,500, `PREP_TIME` 60 s, `WAVE_GAP` 45 s, `OUTPOST_HULL` 500, `OUTPOST_SHIELDS` 300,
`FALL_AT` 0.15, `PAY` 3,000, `REP` 150, `LASERS`, `WAVES`, `GATES`.

### Open for playtest

- The balance: the waves' hulls, the Claim's hull and lasers. Does the Claim fall if the crew fights
  only the ships on the Magpie?
- A minute to get in position; 45 s between waves.
- The raiders' approach (about 19U at impulse): too long a wait?
- Shroud Raiders in the Deep Shroud during the Bounty's hunt: too much?

### History

- 2026-11-24: built (just the fight; negotiation kept for later). The Shroud Raiders split from the
  Corsairs at the same time, and Breaker's Claim added to the universe.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/holdout` (`tests/arcs/holdout.lua`) covers the port and the
faction, the gate, the seed rumors (the hiring one sets the objective), Calloway's two pages, the Claim
reinforced, its lasers picking and hitting a raider, the three waves (faction, no warp, gates, targets),
the gap, the pay and standing, the Claim falling, the Magpie lost, the achievement and news, every GM
state (with next-session routing) and "-> Inactive". The Shroud zones' faction is in
`tests/world/proximity.lua`. Not covered: a real fight and who wins, the flight.
