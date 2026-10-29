# GM Operations Guide — Sandbox Campaign

Running a full session: free exploration, The Witness arc, and wrap-up.

---

## Before You Start

### Scenario settings

| Setting | Recommendation | Notes |
|---|---|---|
| **Campaign** | Continue *or* Fresh start | Continue carries credits and upgrades from prior sessions. Fresh start for a new group. |
| **Starting Credits** | Comfortable (500 cr) | Lets the crew take their first mission and buy one upgrade without waiting. Modest (200 cr) works for a grittier feel. |
| **Director** | On | With a model running, NPCs answer hails and the Director can time events. Off is fully scripted — all beats still fire, just at fixed triggers. |

### What the GM screen shows

- **Campaign Status** — credits, reputation per faction, active flags (wanted), upgrades purchased
- **Active Jobs** — current mission type, tier, and phase
- **Session Info** — session number, time exploring, encounters, visited regions
- **GM Buttons** — trigger The Witness arc, fire Director beats, end session

> **Director tip:** Open the GM console at `http://localhost:8765/` on a second screen. You can send plain-English instructions ("have the patrol hail them about the cargo"), fire specific beats, and approve actions before they execute.

---

## Phase 1 — Free Exploration

Let the crew find their feet. Don't rush them into the story arc. This phase is about learning the map, running a few jobs, and accumulating their first upgrades.

### What to watch for

- **First docking** — crew learns the comms flow (hail → job board → accept). Let this happen naturally.
- **First combat** — a proximity spawn in the Shroud or Gauntlet. Engineering scrambles; Weapons celebrates. Good moment to let it breathe.
- **First upgrade** — usually around 300–500 cr. The shipwright menu at stations. Let them pick without guidance.
- **Concord shake-down** — if they wander into the Arbiter Line or Core, Concord will hail for an inspection. 50% credits fine on refusal plus a wanted flag. Let the relay officer handle it; the choice is theirs.

### When you're ready to move on

Look for two or more of these signals:

- At least 2 upgrades purchased
- Crew has visited 3+ regions (visible in Director session context)
- They've run at least one non-delivery mission (salvage, boarding, or hacking)
- About 45–60 minutes of play

> **GM tip:** If the crew is camped in safe space doing only delivery runs, use a Director instruction: *"Send a rumour to the ship suggesting there's good salvage in the Gauntlet."* The Director will voice it through the next station hail. Don't push — just nudge.

---

## Phase 2 — Introducing the Witness

When the crew is ready, trigger the arc from the GM button **"The Witness: Begin"**. This sets `S.witness_active = true`, suppresses proximity spawns, and starts the offer phase.

### What happens automatically

- A message appears on the relay console: Mira Sable is at Port Vesper requesting a private meeting
- The job board at Port Vesper is disabled until the arc resolves or is abandoned
- Hostile ambient spawns are suppressed for the duration

### What you need to do

Nothing immediately — wait for the crew to dock at Port Vesper. If they're far away and ignoring the message, you can have the Director repeat it: *"Have Mira send a second, more urgent hail to the ship."*

> **Timing note:** Trigger the arc when the crew has some credits but isn't wealthy — the 300–600 cr payout is meaningful at that stage. Too early and the reward feels huge; too late and it's pocket change.

---

## Phase 3 — The Witness Arc

The arc runs through seven phases automatically. Your main job is setting tone and responding to crew comms in-character through the Director.

### Phase 1 — Offer

**Trigger:** Crew docks at Port Vesper and hails Mira.

**What happens:** Mira offers the job — escort an escape pod through the Shroud.

**Your role:** Let the Director voice Mira, or prompt it: *"Voice Mira as guarded, urgent, and not giving details yet."* The crew may ask questions; that's good. Let them.

---

### Phase 2 — Transit

**Trigger:** Crew accepts the job. Mira's ship begins following them.

**What happens:** Travel toward the Shroud. Quiet phase — good for atmosphere.

**Your role:** This is dead air if you let it be. Have the Director send a check-in from Mira — nervous, watching scanners. A rumour from a passing freighter about Concord movements works well here.

---

### Phase 3 — Checkpoint

**Trigger:** Crew reaches the waypoint in Greywater.

**What happens:** The crew receives a comms choice — a message from an unknown party offering them money to hand over Mira's cargo. This is the arc's main moral decision.

**Your role:** Don't rush them. Let the table talk. The choice they make affects the ending. If they ask for more information, have the Director voice the unknown contact as cold and specific — they clearly know exactly what's in the pod.

**Options:** Comply (300 cr, bad ending) · Refuse (continue arc).

---

### Phase 4 — Revealed

**Trigger:** Crew refuses the offer at the checkpoint.

**What happens:** A transmission from inside the pod — *Kael*, an AI consciousness Mira has been sheltering. They explain what they are and why they matter.

**Your role:** Key moment. Let the crew react before moving on. The Director can voice Kael — calm, precise, unexpectedly warm. Prompt: *"Voice Kael as someone who has thought carefully about their own existence, not afraid, and grateful."*

---

### Phase 5 — Shroud Run

**Trigger:** Arc continues after the revelation.

**What happens:** The ship must reach Halcyon Rest with Kael's pod intact. Time pressure. Pod has a stability meter tied to ship energy — Engineering needs to stay above 45% to keep it healthy.

**Watch for:** Engineering under pressure, Helm navigating. This is the tension sequence. Don't over-fill it with dialogue — let the crew focus.

---

### Phase 6 — Halcyon

**Trigger:** Crew arrives at Halcyon Rest.

**What happens:** They dock Kael's pod at the station. Pod stability matters here — if Kael survived intact, the good ending is possible. A 5-minute timer plays out while Kael uploads.

**Your role:** Good moment for one final comms exchange. Prompt the Director: *"Have Kael say something to the crew as the upload runs — something specific to what happened on this run."*

---

### Phase 7 — Broadcast

**Trigger:** Upload completes.

**What happens:** Kael broadcasts across the Drift. Session ends, credits paid, campaign saved.

**Your role:** Epilogue flavour. Prompt the Director: *"Give a one-line coda — what does the broadcast mean for the factions?"* Don't linger; the moment carries itself.

---

## Endings

| Payout | Outcome | Condition |
|---|---|---|
| **600 cr** | Full Success | Kael alive, crew refused the checkpoint offer. Broadcast sent. Mira pays in full. |
| **400 cr** | Partial Success | Kael's stability hit zero but the broadcast still transmitted. Pod reached Halcyon; the data got out. |
| **300 cr** | Complied | Crew handed over the cargo at the checkpoint. The broadcast never happened. |

> **After the arc:** The session saves automatically. The crew's choice and outcome are logged for the Director in future sessions. If you continue playing, proximity spawns resume, the job board re-opens, and the Director will reference what happened in NPC dialogue.

---

## Post-Arc Sandbox

If the table wants to keep playing after the arc, the campaign continues normally. A few things to know:

- **Proximity spawns resume** — the Witness guard lifts. If the crew is in dangerous space, they may get a fight immediately.
- **Higher-tier missions unlock** — with 3+ upgrades, the job board now offers boarding, hacking, and destroy contracts at tier 2. These pay significantly more and hit harder.
- **Wanted flag carries** — if Concord issued a warrant during the arc (or during free play), it persists. Concord zones are hostile until the flag is cleared. Currently no in-game way to clear it — treat it as a story consequence.
- **Director continuity** — prompt the Director to reference what the crew did: *"In any NPC dialogue, acknowledge that the Kael broadcast happened and that people are talking about it."*

### Good stopping points

- After one post-arc mission (natural wind-down)
- After a significant purchase — a jump drive or max-tier weapon unlock feels like a chapter ending
- After a dramatic combat — the Boneyard or Maw if the crew is feeling bold

Wrap with a Director prompt: *"Give a brief out-of-character session summary — what the crew accomplished, what changed."* The GM console will generate a short debrief based on the session log.

---

## Quick Reference

### Reputation effects

| Faction | High rep (>+20) | Low rep (<−20) |
|---|---|---|
| Corsairs | Patrols leave you alone (longer spawn cooldown) | Shorter cooldown — they hunt you |
| Concord | Shake-downs dismissed, no fine | Skip shake-down, immediate attack |
| Independent | Full station access | No current effect |

### Danger levels

| Zone | Threat | Max spawn |
|---|---|---|
| Safe (Vesper Drift, Core…) | Concord inspections only | Scout |
| Risky — the Gauntlet | Corsairs | Medium (with upgrades) |
| Dangerous — Blackwater, Boneyard | Corsairs / Relic drones | Heavy |
| Deadly — the Maw | Hollow | Heavy (always) |

### If something breaks

- **Witness arc won't trigger** — check that the crew isn't mid-mission. The arc disables the job board; avoid triggering it while a job is active.
- **Director offline** — all beats still fire on scripted fallback timers. The session is playable without it.
- **Player ship destroyed** — session ends with a "ship lost" outcome. Credits and upgrades already saved are preserved. Start a new session to continue the campaign.
- **LUA-Error in log** — check `EmptyEpsilon.log` for file and line number. Most errors are API calls on invalid objects after a ship is destroyed.
