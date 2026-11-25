# The Bounty — GM guide

Module: `ee/ragtag/missions/bounty.lua` (id `bounty`). Test: `tests/arcs/bounty.lua`.

## Premise

Pell Ashby, the bookkeeper of the Rimward Haulers Guild, disappeared with the guild's payroll. The
guild has posted a bounty at Dustmote Salvage, the only port that would take its money: alive, no
exceptions. Ashby is hiding in the Deep Shroud aboard the Long Odds, with two hired guns. Once he is
caught, he tells his side: the guild had been skimming its own crews' pay for years. He has moved the
money into crypto credits and memorized the keys, and offers the crew a share to let him go.

Where it sits in the campaign:

- **A one-off money job** (inspired by The Mandalorian and Firefly's bounty hunters): 3,000 cr for
  the bounty, or 4,500 cr for letting him go. It can come before or after the heist.
- **A moral choice with a price**: the guild gets him and the crew's standing with the Independents
  rises, or Ashby walks free at Saint Brennan's and the guild hears who let him.
- **It sends the crew somewhere out of the way**: Dustmote Salvage and the Deep Shroud (the Drift's
  biggest nebula, with the black hole and the rift in it), and uses Thresh as the bounty broker.
- **Kept for later**: a rival bounty hunter (Cass Dunmore in the Last Word) who wants Ashby too.

## Triggers

- **Rezkov over** (`rezkov_arc_done`, or `rezkov_declined`) and **1,000 cr of upgrades** (boarding
  jobs unlocked).
- It starts on its own (`auto_start`), in the hook phase. Nothing is seeded while it waits.

## Phases

```
hook ─► hunt ─► deliver ─► done (bounty | released | lost)
```

### Hook

**Seed rumors** at Independent ports, from the moment it starts (priority 3, mixed into the news):
- "There's a guild bounty posted at Dustmote Salvage. Some bookkeeper ran off with a payroll. Alive
  only, they say." Hearing this one sets the objective **"Bounty at Dustmote"**.
- "A ship went into the Deep Shroud last week with two gunships riding along. Nobody takes an escort
  in there unless they're hiding."
- "The Rimward Haulers Guild is paying its crews late again. Their haulers say the books never added
  up."

Docked at **Dustmote Salvage**, **"[SPECIAL] Bounty: Pell Ashby, alive"** opens two pages (Thresh's
Science DB profile is added):
1. The notice: "BOUNTY: PELL ASHBY, bookkeeper, Rimward Haulers Guild. Ran with the guild payroll.
   3,000 credits. ALIVE. NO EXCEPTIONS." Thresh: "The guild posted it here because nobody else would
   take their money."
2. The trail: the Long Odds and two hired guns went into the Deep Shroud, "last ping was near
   <sector>" (where it really is); probes and Science; "take out its engines and its rear shield
   together and it'll stop. Then dock and collect him."

**We'll take it.** goes to Hunt; **Not right now.** leaves the notice up.

### Hunt

Objective **"Find Long Odds"**. The Science DB gets **Lore > Bounty: Pell Ashby** (the notice, where,
the ship, the disable rule, the escorts).

- **Long Odds** (a Phobos T3 with 300 hull and 150/150 shields, faction **Fugitive**) and two escorts,
  **Second Thoughts** and **Paid in Full** (Adder MK5s, Fugitive), wait in the Deep Shroud at one of
  three hiding places, all well clear of the black hole, the rift and the idle Unknown ships.
- **Found** when the Magpie is within **8U** or has fully scanned it: "That's the Long Odds. Ashby's
  running, and his escorts are turning on us." Ashby hails ("I'm not going back"). Objective
  **"Disable Long Odds"**. Long Odds runs across the nebula in 20U legs at impulse 55 (a stock Light
  Freighter does 60); the escorts attack the Magpie.
- **Long Odds cannot be destroyed** (the contract says alive). It stops when its **impulse and rear
  shield are both down at once**: each 90% hacked (Relay) or under 10% health (Science), as with the
  Hob Works transport. Then it turns Independent (nobody's enemy): "Long Odds is dead in space... Dock
  with it to take Ashby." Objective **"Dock with Long Odds"**. The escorts break off and leave.
- **The escorts can be destroyed**, at no standing cost (Fugitive ships).
- Talking to Thresh at Dustmote in this phase repeats where Ashby is.
- **Docking with the disabled Long Odds** takes Ashby aboard: "Ashby is aboard, in the brig. He wants
  to talk." → Deliver.

### Deliver

Objective **"Deliver Ashby"**. A few seconds in, **Pell Ashby hails** (from the brig) with his offer:
"...I moved it all into crypto credits and memorized the keys. They're in my head, nowhere else. The
Independents can probably beat it out of me, but none of us want to see that happen... Drop me at Saint
Brennan's Mission instead. The order will take me in, and 4,500 of those credits are yours." (If comms
are busy it goes to the ship log.) The Science DB gets **Lore > Pell Ashby's side**.

The crew chooses by where it docks:
- **Dustmote Salvage, "Hand Ashby to the guild":** "3,000. Alive, as ordered." **3,000 cr,
  Independent +100**. Outcome `bounty`.
- **Saint Brennan's Mission, "Let Ashby off here":** two sisters of the order take him in; a transfer
  of **4,500 cr** "from nowhere in particular". "Word will get back to the guild." **Independent
  −150**. Outcome `released`.
- **The Magpie lost** in this phase: Ashby and the money with it. Outcome `lost`. (Lost during the
  hunt, nothing happens: the hunt carries on.)

### Done

The empty Long Odds and any escorts left are removed two minutes later; the news follows (Exports).

## GM console

**Missions… → The Bounty**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ Hook` | The seed rumors again; not briefed |
| `→ Hunt` | Briefed; Long Odds and its escorts at a hiding place |
| `→ Deliver` | Ashby aboard; his offer again |
| `→ Done: Bounty` / `→ Done: Released` / `→ Done: Lost` | End states (no payment) |

Helpers, shown only in their phase:
- **Ship → Dustmote** (hook, deliver), **Ship → Long Odds** (hunt), **Ship → Brennan's** (deliver):
  put the Magpie 5U away, undocked and stopped. (5U from Long Odds finds it.)
- **Disable Long Odds** (hunt): found and disabled now.
- **Kill escorts** (hunt, deliver).

A jump resets the arc (the ships, the voice, the rumors, the objective, the `bounty_*` flags) and
replays the earlier phases. Reputation and credits are not applied by a jump. After a session ends
mid-hunt, the next session starts the hunt over (Long Odds back at a hiding place, maybe a different
one); mid-delivery, Ashby is still aboard.

## Exports

| Flag | Values |
|---|---|
| `bounty_arc_done` | `"bounty"` (handed to the guild) / `"released"` (let go at Saint Brennan's) / `"lost"` |

Standing: Independent +100 (bounty) or −150 (released).

Science DB: Thresh's profile; Lore → **"Bounty: Pell Ashby"** and **"Pell Ashby's side"**.

News (`missions/_aftermath.lua`, category `BOUNTY_DONE`, each told once):
- Bounty: "The Rimward Haulers Guild got its bookkeeper back. Nobody's seen him since, and nobody's
  seen the payroll either." / "Rimward Haulers' crews are asking why the guild wanted that bookkeeper
  alive so badly. Somebody's going through the old pay slips."
- Released: "Pell Ashby was seen at Saint Brennan's, sweeping the chapel floor. The guild's bounty is
  still posted. Nobody's collecting." / "Some Rimward Haulers crews got back pay this month from an
  account nobody can trace. The guild says it wasn't them."

Achievements (hidden): **Bring Him In** (bounty), **Everyone Has a Price** (released).

## Design notes

### State (`st.*`)

`long`, `escorts`, `hide_x` / `hide_y` (the hiding place Thresh names), `found`, `disabled`,
`leg_x` / `leg_y` / `leg_at` (the run), `force_disable` (GM).

### Saved flags

`bounty_briefed`, `bounty_found`, `bounty_captured`, `bounty_offered`, `bounty_rewarded`,
`bounty_arc_done`, `bounty_met_thresh` (profile).

### Factions

- **Fugitive** (new, `verse.lua`): hostile to Independent ships only, so the crew can fight Long Odds
  and its escorts; not a real faction, so destroying one costs no standing.
- Long Odds turns **Independent** when disabled, so nothing keeps fighting it and the Magpie can dock.

### Engine notes

- Long Odds has `setCanBeDestroyed(false)`; its hull can be shot to nothing, but it stays. The
  disable rule is `ARC.systemDown` (shared with the Hob Works).
- The Deep Shroud's nebulae block long-range radar: the crew needs probes and Science's scan.
- Since 2026-11-24 the Deep Shroud is a patrol zone: Shroud Raiders (always hostile) may join the hunt.
- Ashby's offer comes from an `RT.voice` (no ship), so it can reach the crew anywhere.
- The choice is made by docking, not by a reply, so the arc stays linear: one Deliver phase, two
  endings.

### Tuning (top of `bounty.lua`)

`UPGRADES_MIN` 1,000, `FOUND_R` 8U, `RUN_SPEED` 55, `RUN_LEG` 20U, `LONG_HULL` 300, `LONG_SHIELDS` 150,
`HACKED_AT` 0.90, `HEALTH_AT` 0.10, `ESCORT_GIVEUP` 20U, `PAY_BOUNTY` 3,000, `PAY_RELEASE` 4,500,
`REP_BOUNTY` 100, `REP_RELEASE` −150. Hiding places: `_HIDES`.

### Open for playtest

- Finding Long Odds in the nebula: do the crews use probes? Is Thresh's sector hint enough?
- Long Odds' toughness and speed, and the escorts: a real fight? (Template, hull, shields, speed.)
- Disabling it: hack one system, shoot the other, as in the heist. Too much like the heist, or
  welcome practice?
- The choice: does the crew argue about it? Is 1,500 cr more for letting him go enough temptation?

### History

- 2026-11-24: built from the plan (One-off contracts). The bounty moved from Port Vesper to Dustmote
  Salvage and the hunt to the Deep Shroud (out of the way, the biggest nebula); Long Odds tough and
  undestroyable with two destroyable escorts; Ashby's crypto-credits offer; the rival hunter left for
  later.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/bounty` (`tests/arcs/bounty.lua`) covers the gate, the seed
rumors (the notice's sets the objective), Thresh's two pages (the real hiding sector), the spawn
(factions, the nebula, the hull), not found at 20U and found within 8U, the run and the escorts'
attack, Long Odds surviving lethal damage, the disable rule (one system is not enough), boarding,
Ashby's offer and Science DB entry, both drops (pay and standing), the Magpie lost, the achievements,
every GM state (with next-session routing) and "-> Inactive". Not covered: a real fight, probes and
the nebula's radar blackout, a real dock, the flight.
