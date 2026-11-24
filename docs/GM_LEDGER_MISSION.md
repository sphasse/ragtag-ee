# The Ledger Arc — GM guide

A Phase II story arc of The Drift (sandbox campaign, scenario 80). **Spoilers**: keep this away from
players. Module: `ee/ragtag/missions/ledger.lua` (the carry and the audit stop: `_audit.lua`). Back to
the [GM guide](GM_GUIDE.md).

## Premise

The Rezkov arc's Galen hack planted a program in the Concord's books. It has finished reading them:
an account that hasn't closed in twenty years pays for "Maw containment" and "Ashgrave remediation",
and every transfer is signed. It can't leave over Concord comms, so it split itself into three
fragments and went dark inside Concord space. Rezkov wants the crew to bring it out.

Where it sits in the campaign:

- **It is the evidence thread.** Of the three Phase II arcs, the Ledger proves the cover-up on paper.
  The Containment Ledger names the people who signed for it: Deputy Treasury Secretary **Aurelian
  Voss**, Rear Admiral **Corin Hale** (Fleet Logistics), Director **Mireille Tan** (Applied Research
  Division) and the Council's Standing Committee on Security. Tan's division matters again in the
  Hob Works mission, whose chief engineer came out of Applied Research under her.
- **Rezkov holds it.** He won't release it yet: "Put it out today and they bury it by the end of the
  week." The finale (the Maw) is where it goes public. With the ledger (`ledger_evidence`) the finale
  can reach its two best endings, and the cover-up becomes public; without it, only the crew knows.
- **It shows the Concord's machinery.** The Concord Audit Service is the Treasury's own strike force.
  Meeting it here makes the Concord's interest in staying hidden concrete.
- **Kael comes back, offstage.** If Commander Kael survived the Rezkov arc, Rezkov's hand-over says
  she buried the Audit Service's report on the crew, and that "our interests might now be more aligned
  than we thought". It is the first sign that the Concord is divided.
- **It gates the Hob Works.** The Hob Works mission waits until this arc is over (any outcome), so the
  two never overlap.

The challenge is navigation, not combat: Concord space, where the Concord may be hostile because of the
crew's own standing (the arc doesn't change it). Science watches and scans, Helm stays off the patrol
lanes, and at the end Engineering keeps the reactor alive under a heavy drain while three audit ships
block the way out.

## Triggers

- **≥ 800 cr** of upgrades on the primary ship (the Magpie).
- The Rezkov arc finished (any outcome) **or declined**.
- Then **two board jobs** finished by the primary ship after that (story contracts don't count). The
  count starts the first time Rezkov is seen as over, even before the crew reaches 800 cr of upgrades.
- `ledger_arc_done` not set.

It auto-starts quietly: no hail, no job. **Mission criteria** on the GM screen shows the job count.

## Phases

```
hook ─► meet ─► relay_run ─► carry ─► done (full | lost)
```

### Hook

Priority-5 rumors (`LEDGER_HOOK`): "A guy at Dustmote was asking about you", and similar. Docked at
Dustmote, the crew's line is **"Heard Thresh was looking for us again."** if they know Thresh, or
**"Heard someone here was asking about us."** if they don't. Thresh says the big guy wants to see them
in person, at the same place. A crew that never met Rezkov gets directions: bearing 15.

### Meet Rezkov

Rezkov's station is back in the nebula at about (115, −72). Docked, the real briefing: the
twenty-year account and the AI's three fragments. Rezkov gives the fragments' grid references and
warns the crew to "stay off the patrol lanes. The Concord accounting unit has a notorious strike force
that you really don't want to run across. Bring the assembled AI to me here." On accepting: "You will
want full energy when the AI is assembled. It runs hot."

The briefing changes with the Rezkov arc: "The card you carried had a second payload" if the crew did
the Galen hack, else "I had a crew put a program into the Concord accounting system at Waypoint Galen".

### Relay run

Three data cores (`Artifact`, picked up by flying into them): near **Valcourt** (−172, −70), near
**Ostia** (−128, −120) and near **Waypoint Galen** (−80, −62). The objective counts 0/3. Beside each
core (2U east, 1.5U south) is an emergency **Power cell** that refills the ship's energy to 100% once.
The cells stay out through the carry.

### Carry AI

The third core assembles the AI, and it hails ("Unidentified Signal"): thanks, sorry about the power,
keep energy above zero. From now on it **drains 3 energy/s**. Engineering shows an "Unknown process"
line and an **Eject the AI** button.

**60 s later the Concord Audit Service** arrives 7U ahead in a 35° arc: CAS *Double Entry* (Phobos T3)
with CAS *Debit* and *Credit* (Adder MK5). They are plain `Concord` and make it a stop: Double Entry
drops a warp jammer that rides behind the crew and brakes them, then Debit and Credit drop two more,
three jammers in a triangle round the ship. Double Entry then hails:

- **Transmit the data.** → surrender (ends **lost**).
- **Up to two stalls**: accounting excuses, each buying another 60 s (the second gets the final notice).
- **Not today.** → they attack.

The auditors turn **Concord Hostile** and attack if the crew refuses, says nothing for 60 s after the
hail or a stall, shoots a jammer or an auditor, or flies 3U off the stop. Hostile, they drop combat
jammers like hostile patrols (2 min apart). "Transmit the data." still works then. Auditors that end up
more than 25U from the crew are removed.

Docking at any Independent station recharges the reactor: that is how a crew survives the long haul
from the Core back to the nebula.

### Done

- **Full**: docked at Rezkov's station, he watches the transfer finish: "You were right, this thing
  runs hot." With Kael alive, he adds her back-channel news. The arc ends on the delivery.
- **Lost**: energy reached 0 (`power`, instant), "Transmit the data." (`surrender`), the ship destroyed
  with the AI aboard (`destroyed`), or Engineering ejected it (`ejected`: one press arms it, "CONFIRM:
  eject the AI" for 10 s, a second press ejects).

## GM console

**Missions… → Ledger Arc**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ Hook` / `→ Meet Rezkov` / `→ Relay run` / `→ Carry AI` | Jump to that phase |
| `→ Done: Full` / `→ Done: Lost` | End the arc (Lost is the `power` reason) |

Helpers, shown only in their phase:
- **Travel shortcuts** (put the Magpie 5U away, undocked and stopped): **Ship → Dustmote** (hook),
  **Ship → Rezkov** (meet, carry), **Ship → fragment** (relay run: the next core not yet picked up).
- **Satisfy done jobs** (waiting): the two-job count is met at once; the Rezkov and upgrade conditions
  still apply.
- **Give fragment** (relay run): one more core collected.
- **Fleet now** (carry): the audit fleet arrives now.
- **Pause drain / Resume drain**, **Refill energy** (carry).
- **+100 energy** (relay run and carry): never past the maximum. For a crew in trouble.

A jump resets the world first (Rezkov's station, the nebula, the cores, the power cells, the fleet, the
drain, the AI's voice, rumors, the arc's objective and the `ledger_*` flags), then replays the earlier
phases. The job count's starting point (`ledger_jobs_base`) survives every reset, so a jump or
Enable/Disable doesn't restart the count; only rewinding the Rezkov arc does. Reputation and credits
are not applied by a jump.

## Exports

| Flag | Values |
|---|---|
| `ledger_arc_done` | `"full"` / `"lost"` (Hob Works and the finale: any value) |
| `ledger_lost_reason` | `"power"` / `"surrender"` / `"destroyed"` / `"ejected"` |
| `ledger_evidence` | true on full: the finale's transmission and its two best endings |
| `ledger_rewarded` | pays once |

Rewards, once: **full** → 600 cr, Concord −200, Independent +200. **Lost** → nothing.

**News** (rumors at any port from the end of the arc; each is told once, then retired from later
sessions):
- Full: the audit at Lumen "just stopped. Nobody closed it… The auditors look scared.", and two senior
  Treasury clerks resigned the same morning, while Deputy Secretary Voss has stopped taking meetings.
- Lost: the audit closed as "an accounting error, corrected", and the Audit Service got a commendation
  and a bigger budget.
- The lines are in `ee/ragtag/missions/_aftermath.lua`.

Science DB: Lore → "The Containment Ledger" (lock key `ledger_findings`), unlocked on full and readable
exactly while `ledger_evidence` is set. It names Voss, Hale, Tan and the Standing Committee.

## Design notes

### Why the hook waits for two jobs

The Rezkov arc ends at Dustmote, where this hook lives, so without a wait the hook was on offer the
moment Rezkov ended. The count is noted in the `requires` check (`_rezkovOver`), which the engine runs
every frame. It used to be noted in the custom trigger, which only runs once `upgrades_min` holds, so
jobs done before the crew reached 800 cr of upgrades didn't count (the RC1 playtest bug). Each ship
counts its own finished board jobs (`jobs_done` in its record).

### Rezkov holds it

The ledger isn't broadcast in this arc on purpose: the finale's aftermath is where it goes public. The
Kael paragraph in the hand-over is a seed for the planned Concord storyline; the arc still ends on the
delivery, with no extra hail.

### Tuning (top of `_audit.lua`)

The carry (drain, the AI's hello, the eject button, the audit fleet and its stop) is `AUDIT` in
`ee/ragtag/missions/_audit.lua`, shared with the Audit Lab (scenario 64, parked in
`scenarios/_battlelab`) so it can be replayed and tuned on its own. The arc keeps its endings and passes
them to `AUDIT` as hooks.

| Constant | Value |
|---|---|
| `DRAIN_PER_S` | 3 (eased from 5 after a playtest) |
| `FLEET_DELAY` | 60 s |
| `FLEET_DIST` | 7U |
| `FLEET_SPREAD` | 35° |
| `FLEET_IMPULSE` | 1.5× |
| `TRI_R` | 0.6U (the jammer triangle) |
| `TIMEOUT` | 60 s |
| `MAX_STALLS` | 2 |
| `LOSE_FLEET_R` | 25U |
| `EJECT_CONFIRM` | 10 s |

Open for playtest: whether energy at zero should stay an instant loss, and whether three audit ships
are enough of a wall.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/ledger` (`tests/arcs/ledger.lua`).
