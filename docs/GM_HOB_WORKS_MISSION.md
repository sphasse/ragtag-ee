# The Hob Works Arc — GM guide

The story arc after Phase II of The Drift (sandbox campaign, scenario 80), and the bridge to the Maw
finale. **Spoilers**: keep this away from players. Module: `ee/ragtag/missions/hob.lua`. Back to the
[GM guide](GM_GUIDE.md).

## Premise

The lifeboat survivors from the Boneyard have taken the Concord's own research to Hob's Landing. There,
Dr. Mara Quill and the Hob Works' chief engineer, Anton Marchetti, have worked out how to undo the Maw:
a broadcast station they call **Lullaby**. The Works can build it, but the parts cost more than they
have. So the crew robs the Concord to pay for it: a one-time Treasury transfer is about to leave Lumen
Exchange for Sentinel Fleet Yard, carrying the money the Concord needs to rebuild its fleet.

Where it sits in the campaign:

- **It turns the science thread into the cure.** The Boneyard's archive (or the survivors' own notes)
  becomes a real device. Lullaby built (`hob_beacon_ready`) is what the Maw finale needs.
- **It introduces Anton Marchetti**, the Works' chief engineer, who came out of the Concord's Applied
  Research Division the year the Pale Sun was sealed, under Director Tan (a signatory in the Ledger).
  **Mara Quill**, met as a lifeboat survivor in the Boneyard arc, becomes a regular contact.
- **It costs the Concord again.** The stolen transfer was meant to replace the battle groups lost in
  the Boneyard and at Blackwater. Its loss stalls the rebuild at Sentinel Fleet Yard, and the news
  rumors that follow (layoffs at the yard, questions in the Senate) push the Concord further toward
  the fracture planned for later.
- **Rezkov stays in the picture without a part.** He refers the crew to the Works ("one of the few
  crews capable of pulling off this job"): he holds the Containment Ledger and wants the cover-up made
  impossible to bury, and a cure does that.
- **The crew's choices show.** Boarding the transport costs Concord standing −800, destroying it −1,000.
  Keeping the cash costs the crew its Independent standing and, eventually, the cure.

## Triggers

- The **Rezkov arc over** (finished or declined).
- The **Ledger, Boneyard and Corsair arcs all finished**, any outcome, **with the Boneyard's lifeboat
  survivors rescued** (`boneyard_buoy_found`). A crew that skipped the survivors never gets this arc.
- Then **5 board jobs** finished by the primary ship (story contracts don't count), counted from the
  moment the last of those arcs ended. **Mission criteria** on the GM screen shows the count.
- While it waits, two vague seed rumors join the rotation ("The Hob Works took in some Concord archive
  refugees…").

It starts by itself. There is no hail: the lead comes as port news.

## Phases

```
hook ─► heist ─► deliver ─► build ─► done (built)
                    └──────────────► done (abandoned: the cash never reached the Works)
```

### Hook

At **Independent ports**, "Any news worth hearing?" now leads with: "Mara Quill left a message for your
crew. Something about a breakthrough at the Works. She asked you to come by Hob's Landing when you can."
Concord ports don't pass it on. Hearing it sets the objective **"Meet Quill at Hob's"**.

Docked at **Hob's Landing**, **"We got Mara Quill's message."** opens four short pages, each moved on
with **"Go on."**:
1. **Quill:** what the archive showed. The Maw was a Concord program to make the Pale Sun colonists
   docile; the Hollow are those colonists. (Her Science DB profile is added.)
2. **Marchetti:** it can be undone. A station broadcasting the right frequency throughout the Maw puts
   the Hollow to sleep and then starts to bring them back: Lullaby. (His profile is added.)
3. **The problem:** the Concord was very close, but stopped for political reasons. The Works can build
   it, but the parts cost **10,000 cr** (**15,000** without the archive) and the work has stalled.
4. **The pitch:** "…Which brings us to you. We think we've got a creative way to get the cash. Your
   friend Rezkov is a supporter of our research…" The Science DB gets **"Lullaby (Phase II reversal
   beacon)"**, which covers everything the briefing said.

Variants: if the crew sold Rezkov out (Rezkov ending `concord_won`): "Rezkov hasn't forgotten the
Meridian business, but he still says…". If the Ledger AI was lost: "…even after the Lumen business".

**Interested.** goes on to the convoy brief; **Not right now.** leaves the offer open. Next docking it is
**"About Lullaby and the cash..."**. There is no permanent "no": the finale needs the beacon.

**The convoy brief**, four more pages:
1. The money: a one-time Treasury transfer leaving Lumen Exchange for Sentinel **in 15 minutes**, to
   rebuild the fleet (or "reinforce" it if neither battle group was destroyed). One chance only.
2. **CTS Tithe**, the transport: big, slow, armoured, one small beam aft; it won't stop. Kill its
   engines and drop its rear shield to board it; blow it up and pick cash out of the wreckage.
3. **CNS Surety and CNS Bond**, the escorts: fast, a heavy forward beam each, they'll come for you.
   **Their sensors reach about 15U.**
4. The **fake transponder** on Engineering: ten minutes, once. "Bring the cash here. It only counts
   once it is in our hands."

**We'll do it.** starts the heist; **Not right now.** keeps the offer open.

### Heist

- **The countdown:** "Departs in 14:59" on Relay and Operations, under the objective "Rob the convoy".
  Hob's Landing to Lumen is about 249U: ~8 minutes at warp 1, ~4 at warp 2.
- **The convoy waits** alongside Lumen Exchange: CTS Tithe and its two escorts, all plain Concord.
  Science can scan them (the intel is in the Science DB as "Convoy intel: CTS Tithe").
- **Concord patrols are off** in the Core, on the Arbiter Line and in the Escrow Marches until the
  heist ends.
- **The escorts' 15U scan.** Only the Magpie matters to them: any other ship is just traffic. If the
  Magpie comes within 15U before departure without a working fake code, they hail once ("We see you,
  Magpie. Head the other direction or you are in for trouble. This is a fight you cannot win."), turn
  hostile and come for it. The convoy still leaves on schedule.
- **The fake transponder:** Engineering's **"Change transponder"** button. It takes effect at once,
  works once, and shows **"Code valid 9:59"** on Engineering. Inside 15U with a good code the Magpie is
  not seen. When the code runs out ("Code expired"), a Magpie inside 15U is spotted as above.
- **Departure:** at zero the transport turns hostile and runs for Sentinel at **125 u/s (7.5U a
  minute)**, about 8 minutes. It never stops or turns to fight. The escorts fly with it, and once
  the run is on they go for the Magpie whenever it is inside 15U, code or no code. Objective "Stop
  CTS Tithe".
- **Disabling it:** the transport's **impulse drive and rear shield** must both be down at the same
  time. A system is down when **Relay's hacking screen shows it 90% hacked or more**, or when
  **Science's scan shows its health under 10%**. A hack fades (from 100% it drops under 90% in about
  18 s), so it is divide and conquer: e.g. Relay hacks one while Weapons shoot the other down. Hacked
  or damaged impulse also slows the transport. Disabled, it surrenders and goes dead in space:
  objective "Board CTS Tithe". **Dock with it** to take the four cash boxes: **12,000 cr**, Concord −800.
- **Destroying it:** three cash boxes tumble in the wreck (the fourth is lost): fly into them
  (objective "Cash boxes 0/3"). All three: **9,000 cr**. Concord −1,000 when it dies.
- **Missing it:** the transport reaches Sentinel (within 3U), or the **Magpie is lost**. The money is
  gone; there is no second run.

### Deliver

The way home has the ordinary Concord patrols again. Escorts still chasing give up once the Magpie is
20U away.

- **With cash:** "Deliver by 14:59" counts down (objective "Cash to Hob's"). The cash only counts
  when it is delivered. Docked at Hob's Landing, **"We have the cash."** adds it to the ship's credits,
  then **"Deliver 10,000 cr to the engineers"** (15,000 without the archive) pays the Works. The rest is
  the crew's.
- **Late:** the deadline passes, the crew's **Independent standing is set to −100** whatever it was,
  and for **30 minutes** Independent ports' news shames them ("Mara Quill says the Works are still
  waiting on the Magpie. Twenty years those people have been Hollow, and the Magpie is sitting on their
  cure money."). A late delivery is still taken ("Better late. Not by much."). After 30 minutes the arc
  ends **abandoned**: no cash, no beacon.
- **No cash** (missed, lost, or delivered but short): objective "Pay the Works". At Hob's Landing,
  **"Talk to Quill and Marchetti"** says how many credits short the crew is; the pay button appears
  once they can afford it. Job-board work makes up the difference.

### Build

Paid: "Lullaby in 9:59" counts down (objective "Lullaby being built"). Ten minutes, or until the next
session, whichever comes first.

### Done

- **Built:** "Lullaby is built and waiting at Hob's Landing." `hob_beacon_ready` is set.
- **Abandoned:** "The Works have given up on the Magpie."
- Either way the convoy's leftovers are removed 2 minutes later, and the news rumors of the robbery
  start (see Exports).

## GM console

**Missions… → Hob Works Arc**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ Hook` | Quill's message is port news again |
| `→ Heist` | Briefed; the convoy at Lumen with a fresh 15-minute countdown |
| `→ Deliver` | Boarded: carrying 12,000 cr with a fresh 15-minute deadline |
| `→ Build` | Paid: the 10-minute build |
| `→ Done: Built` | Lullaby built (`hob_beacon_ready`) |
| `→ Done: Abandoned` | The cash never reached the Works |

Helpers, shown only in their phase:
- **Travel shortcuts** (put the Magpie 5U away, undocked and stopped): **Ship → Hob's** (hook, deliver,
  build), **Ship → Lumen** and **Ship → Tithe** (heist; 5U from the convoy is inside the escorts' 15U,
  so without a working code they spot the Magpie).
- **Satisfy done jobs** (waiting): the 5-job count is met at once; the other conditions still apply, and if
  one is not met the button says which (e.g. "Boneyard survivors not rescued"). The other arcs' GM `→ Done`
  buttons all meet them (Boneyard's `→ Done` counts the survivors as rescued).
- **Depart now** (heist): the convoy leaves now.
- **Transport faster / Transport slower** (heist): ±25 u/s, with the new speed in a GM message. For
  playtesting the run's length.
- **Disable transport** (heist): it surrenders now (leaving first if it hadn't).
- **Kill escorts** (heist, deliver).
- **Give cash** (heist): as if boarded: 12,000 cr to deliver.
- **Finish build** (build).

A jump resets the arc (the convoy, the cash boxes, timers, Engineering's button and line, the rumors,
the arc's objective, the `hob_*` flags) and replays the earlier phases. Reputation and credits are not
applied by a jump. The Concord standing loss is applied once (`hob_penalized`). After a session ends
mid-heist, the next session starts the heist over with a fresh countdown. A paid build is finished at
the next session.

## Exports

| Flag | Values |
|---|---|
| `hob_beacon_ready` | true once Lullaby is built (the Maw finale's input) |
| `hob_arc_done` | `"built"` / `"abandoned"` |
| `hob_heist` | `"boarded"` / `"destroyed"` / `"missed"` / `"lost"` |
| `hob_haul` | 12000 / 9000 (until delivered) |

Standing: Concord −800 (boarded) or −1,000 (destroyed); Independent set to −100 on a missed delivery.

Science DB: profiles of **Dr. Mara Quill** and **Anton Marchetti**; Lore → **"Lullaby (Phase II reversal
beacon)"** (from the meeting) and **"Convoy intel: CTS Tithe"** (from the brief).

News (port rumors, each told once; `missions/_aftermath.lua`), after a boarding or a wreck:
- boarded: a Treasury transport stripped inside the Core, "a training exercise";
- destroyed: a Treasury convoy blown up on the lane to Sentinel, and the Senate asking why a payroll
  needed warships;
- either: Sentinel Fleet Yard laying off half its crews, and senators asking how the Treasury lost a
  convoy inside the Core.

## Design notes

### State (`st.*`)

`transport`, `escorts`, `boxes` / `boxes_got` (the wreck), `depart_at`, `departed`, `spotted` / `warned`,
`disabled`, `code_until` / `code_used` (the fake code), `speed` (the transport's, GM-adjustable),
`tx` / `ty` (its last position, for the wreck), `deliver_due`, `pester_until`, `build_due`.

### Saved flags

`hob_jobs_base` (the job count's start; kept through resets), `hob_met`, `hob_briefed`, `hob_heist`,
`hob_haul`, `hob_penalized`, `hob_delivered`, `hob_late`, `hob_paid`, `hob_beacon_ready`,
`hob_arc_done`, `hob_met_quill` / `hob_met_marchetti` (profiles).

### Factions

The convoy is plain **Concord** while it waits. Spotted escorts and the departing transport become
**Concord Hostile**, which the Magpie can fight. The disabled transport becomes **Concord Surrendered**:
nobody's enemy, so it can be docked with and is left alone. It also gets a docking bay for Frigate-class
ships, like the boarding job's targets.

### Engine notes

- **What the crew sees.** EE keeps a system's health (damage) and hacked level apart. Science's scan
  shows health only; Relay's hacking screen shows "hacked N%", counting up. A system's real power
  combines them (`ShipSystem::getSystemEffectiveness`: a hack takes off up to 75%, damage scales the
  rest), but no console shows that. So the disable rule (`M.systemDown`) uses the two numbers the crew
  can see, `HACKED_AT` 90% hacked or `HEALTH_AT` 10% health, not real power. (The first build used
  real power under 10%, which a hack alone could never reach; changed the same day.)
- **The transport runs on impulse**, not warp, so an impulse hack or damage really slows it (EE scales
  impulse speed by the system's power). It uses blind fly orders, because the freighter's stock
  "evasion" AI would otherwise flee off the lane. Acceleration is raised from the stock 10 to 25 so it
  reaches speed in about 5 s.
- **The escorts** are Adder MK8s with hull raised to 100, impulse 150 (above the transport's) and no
  nukes. The transport is an Equipment Freighter 5 (not the Jump variant): hull 100, shields 50/50 and
  one 3-damage rear beam.
- **The countdowns** are custom info lines (`hob_timer` on Relay/Operations, `hob_code_*` on
  Engineering/Engineering+), not objectives, so the per-second updates don't fire an objective event
  each time.

### Tuning (top of `hob.lua`)

`JOBS_AFTER_PHASE2` 5, `HEIST_DELAY` 900 s, `TRANSPORT_SPEED` 125, `SPEED_STEP` 25, `TRANSPORT_ACCEL` 25,
`ESCORT_SPEED` 150, `SCAN_R` 15U, `CODE_TIME` 600 s, `HACKED_AT` 0.90, `HEALTH_AT` 0.10, `ARRIVE_R` 3U, `BOX_VALUE` 3,000
(4 boarded, `WRECK_BOXES` 3), `DELIVER_TIME` 900 s, `PESTER_TIME` 1,800 s, `BUILD_TIME` 600 s,
`PRICE` 10,000 / `PRICE_NO_ARCHIVE` 15,000, `CONCORD_BOARDED` −800, `CONCORD_DESTROYED` −1,000,
`LATE_INDEPENDENT` −100.

### Open for playtest

- The transport's speed (use the GM buttons), and the escort and transport numbers.
- Disabling the transport: does the crew split the work (hack one system, shoot the other) and time
  it before the hack fades? Is 90% / 10% the right bar?
- Whether the escorts ignore other player ships well enough. They are Concord Hostile with orders
  to attack the Magpie, so they may still shoot back at a ship that shoots them.
- The way home: only the ordinary patrols for now. Chasers, pickets or a jammer stop are on hold until
  after the Ledger audit playtest (`scenarios/sandbox/plan.md`).

### History

- 2026-11-23: built from the plan (Arc 5a). Designed over several sessions: a train job instead of a
  Ledger-AI hack; Sentinel moved south and the Escrow Marches added; a scheduled departure instead of a
  proximity trigger; the fake transponder kept only for scanning the docked convoy.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/hob` (`tests/arcs/hob.lua`) covers:
- the gate, and the hook through real port news (Concord ports silent);
- the four briefing pages and the convoy brief;
- the transponder (one use, ten minutes, its lapse) and the 15U scan, ignoring a second ship;
- departure, the GM speed buttons and the transport moving at speed;
- the disable rule (a full hack alone is not enough), boarding, delivery, payment and the build;
- the wreck's three boxes, a late delivery, an abandoned one, a missed convoy (and paying from job
  credits) and the Magpie lost;
- the briefing variants, every GM state (with next-session routing) and "-> Inactive".

Not covered: a real fight with the escorts, a real Relay hack (hack levels are set directly), a real
docking, the whole 8-minute run.
