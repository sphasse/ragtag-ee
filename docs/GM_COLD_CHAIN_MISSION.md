# Cold Chain — GM guide

Module: `ee/ragtag/missions/coldchain.lua` (id `coldchain`). Test: `tests/arcs/coldchain.lua`.

## Premise

A fever is spreading through Tamsin Hollow, the farm depot that feeds half the Border: forty of the
farm crews down and three dead. The cure exists. The Concord makes it and keeps it in the medical
depot at Ostia Highport, and it won't release it to an Independent port. Dr. Nell Varga, Tamsin's
doctor, applied through the proper channels six weeks ago. Now she is asking any crew with a fast
ship and a flexible conscience to go and get it.

Where it sits in the campaign:

- **A one-off money job** between the Hob Works and the Lullaby pickup (inspired by Firefly's
  hospital break-in): 3,000 cr for a clean run.
- **The first job built around fake transponder codes.** It becomes available once the Hob Works is
  funded, when Marchetti starts selling codes. A crew that lifts the serum with a code running is
  never identified; a crew that doesn't is hunted out of Concord space.
- **It introduces Dr. Nell Varga** (Science DB profile), a Border contact for later stories.
- **It adds to the Concord's troubles**: the aftermath news is either a theft the Concord says never
  happened, or a notice on a freighter the Border is buying drinks for.

## Triggers

- The Hob Works funded (`hob_arc_done = "funded"`), then **3 board jobs** by the primary ship
  (`JOBS_AFTER_FUNDED`). The count starts when the Hob Works is funded (`coldchain_jobs_base`).
- It starts on its own (`auto_start`), in the hook phase. Nothing is seeded while it waits.

## Phases

```
hook ─► approach ─► run ─► done (delivered | spoiled | lost)
```

### Hook

**Seed rumors** at Independent ports, from the moment it starts (priority 3, mixed into the normal
news):
- "Tamsin Hollow's turning ships away. Some fever in the farm crews, and it's spreading."
- "The Concord makes the cure for that Tamsin fever. Keeps it in the medical depot at Ostia, they
  say. Not for Rim folk."
- "Dr. Varga at Tamsin Hollow is asking for any crew with a fast ship and a flexible conscience. Says
  she can pay." Hearing this one sets the objective **"Dr. Varga at Tamsin"**.

Docked at **Tamsin Hollow**, **"[SPECIAL] Dr. Varga's medical run"** opens three pages, each moved on
with **"Go on."**:
1. Varga and the fever: "…They won't release it to us: Independent ports must apply through the
   proper channels. I applied. Six weeks ago." (Her Science DB profile is added.)
2. The plan: "The depot's release orders run on Ostia's own systems. Dock at Highport and have your
   Relay officer break into the port: get it to 75% hacked while you're docked, and the depot sees an
   approved order and loads the serum onto your ship. Hack it from anywhere else and their security
   just resets it."
3. The cold run and the pay: fifteen minutes cold-packed; "if they see who took it, they'll come for
   you. If they don't... well. I hear the Hob Works sells a very good transponder code." 3,000 credits.

**We'll do it.** goes to Approach; **Not right now.** leaves the offer open.

### Approach

Objective **"Hack Ostia Highport"**. The Science DB gets **Lore > The Tamsin fever**, which covers
everything Varga said.

- Fly to **Ostia Highport**, about 166U from Tamsin, deep in the Concord Core. A wanted crew (Concord
  standing below −200, likely after the heist) has the port guard on it within 5U and hostile patrols
  in the Core: a fake code (10 minutes) gets it in.
- **Dock**, then Relay hacks **the port itself**: a station's shields are hackable systems, so Relay's
  hacking screen lists Ostia's front and rear shields. Either one at **75% hacked** loads the serum.
- Only a hack made while docked counts: whenever the Magpie is not docked at Ostia, the port's hack
  levels are reset to 0.
- Talking to Varga at Tamsin in this phase: "Ostia Highport. Dock, hack the port to 75%, and the serum
  is yours."

**Who saw it** is decided the moment the serum is loaded:
- **A fake code running:** "The depot logged an unknown freighter. Nobody knows it was the Magpie." No
  standing loss, no chase.
- **No code:** "Ostia's security has the Magpie's transponder on the release order. The Concord is
  hunting the Magpie. Get out of Concord space." **Concord −300**, and the Core, the Arbiter Line and
  the Escrow Marches send a patrol **every 30 seconds** (up to 4 per zone) until the Magpie is out of
  all three ("Out of Concord space. The patrols are back to their usual rounds.").

### Run

Objective **"Serum to Tamsin"**; **"Serum good for 14:59"** counts down on Relay and Operations.

- At zero: "The cold pack has run out. The serum is warming: some of it will still be good." The line
  reads "Serum spoiling".
- Docked at Tamsin Hollow, **"We have the serum."** ends it:
  - **In time:** "It's good. It's all good." **3,000 cr** and **Independent +150**. Outcome
    `delivered`.
  - **Spoiled:** "Some of it's still good. Enough for the worst of them." **1,000 cr**. Outcome
    `spoiled`.
- **The Magpie lost** in this phase: the serum is lost with it. Outcome `lost`. (Lost during Approach,
  before loading, nothing happens: the job carries on.)

### Done

- Delivered or spoiled: the news follows (see Exports).
- Lost: "The serum went down with the ship. Tamsin Hollow is still waiting."

## GM console

**Missions… → Cold Chain**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ Hook` | The seed rumors again; not briefed |
| `→ Approach` | Briefed; the port's hack reset |
| `→ Run` | Serum loaded (as with a code: no chase), a fresh 15-minute timer |
| `→ Done: Delivered` / `→ Done: Spoiled` / `→ Done: Lost` | End states (no payment) |

Helpers, shown only in their phase:
- **Ship → Tamsin** (hook, run), **Ship → Ostia** (approach): put the Magpie 5U away, undocked and
  stopped.
- **Satisfy done jobs** (waiting): the 3-job count is met at once; the Hob Works must be funded.
- **Complete hack** (approach): load the serum now, wherever the Magpie is (who saw it is still
  judged by the code).
- **Spoil now** (run): the cold pack runs out.

A jump resets the arc (the timer line, the chase, the rumors, the objective, the `coldchain_*` flags)
and replays the earlier phases. Reputation and credits are not applied by a jump. After a session ends
mid-run, the next session starts the run again with a fresh 15-minute timer (the timer is not saved).

## Exports

| Flag | Values |
|---|---|
| `coldchain_arc_done` | `"delivered"` / `"spoiled"` / `"lost"` |
| `coldchain_seen` | `"code"` (an unknown freighter) / `"seen"` (the Magpie identified) |

Standing: Concord −300 when identified; Independent +150 for an in-time delivery.

Science DB: the profile of **Dr. Nell Varga**; Lore → **"The Tamsin fever"**.

News (`missions/_aftermath.lua`, category `COLDCHAIN_DONE`, each told once):
- Delivered: "Tamsin's fever broke. Dr. Varga's sending fresh bread to every crew that docks there."
- Spoiled: "Half of Tamsin's sick are back on their feet. The other half are still waiting on the
  Concord's proper channels."
- With a code: "Somebody walked into Ostia's medical depot with an approved order and walked out with
  a case of fever cure. The Concord says it never happened."
- Identified: "The Concord's posted a notice on a freighter that robbed its own medical depot at
  Ostia. Border captains keep buying that crew drinks."

Achievements (hidden): **Cold Chain** (delivered in time), **No Fingerprints** (lifted with a code
running).

## Design notes

### State (`st.*`)

`spoil_at`, `spoiled`, `chase`, `timer_text`, `force_load` (GM "Complete hack").

### Saved flags

`coldchain_jobs_base` (the job count's start; kept through resets), `coldchain_briefed`,
`coldchain_loaded`, `coldchain_seen`, `coldchain_penalized`, `coldchain_rewarded`,
`coldchain_arc_done`, `coldchain_met_varga` (profile).

### Engine notes

- **Hacking a port.** Relay's hacking screen lists any hackable ship system on a target that is not
  friendly. Stations have shields (`components.shields`, front and rear systems), so a Concord port
  can be hacked; Lua reads and writes `front_hacked_level` / `rear_hacked_level`. Relay could hack the
  port from anywhere in range, so the arc resets the levels whenever the Magpie is not docked.
- **Docking while wanted.** The Concord is not the Independents' enemy as a faction, so a wanted
  Magpie can still dock at Ostia; only the port guard (5U, `world/defenders.lua`) and the patrols react.
- **The chase** is `PROX.chaseZone` on the three Concord zones, ended by `ARC.inRegions` (shared with
  the Hob Works).
- **Why not a job-board contract:** board jobs must be one of the seven job types, and this job's cargo
  is loaded at Ostia, not at the port that offers it. Varga's request is a [SPECIAL] comms reply at
  Tamsin Hollow instead, like the Hob Works meeting.

### Tuning (top of `coldchain.lua`)

`JOBS_AFTER_FUNDED` 3, `HACK_AT` 0.75, `SPOIL_TIME` 900 s, `PAY_FRESH` 3,000, `PAY_SPOILED` 1,000,
`REP_FRESH` 150, `CONCORD_SEEN` −300, `CHASE_COOLDOWN` 30 s, `CHASE_MAX` 4.

### Open for playtest

- Does Relay think of hacking the port itself? Do the hacking screen's shield systems read as "the
  port"? Is 75% the right bar?
- 15 minutes for the ~166U run home: tight or generous?
- Does a wanted crew use a code, and time it to the dock and the hack (10 minutes)?
- Is "identified + chase + Concord −300" the right price for a clean crew that skips the code?

### History

- 2026-11-24: built from the plan (One-off contracts). The plan's cargo-lock hack became a hack of the
  port itself, made while docked; seed rumors start the job.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/coldchain` (`tests/arcs/coldchain.lua`) covers the gate, the
seed rumors (Varga's sets the objective), the three-page brief, the hack reset away from the dock and
the 75% bar docked, both "who saw it" outcomes (standing, the chase and its end out of Concord space),
the spoil timer, in-time and spoiled delivery, the Magpie lost, the achievements, every GM state (with
next-session routing) and "-> Inactive". Not covered: Relay's real hacking screen on a station (hack
levels are set), a real dock, the flight.
