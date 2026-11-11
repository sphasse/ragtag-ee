# The Drift — five-arc story plan

The sandbox campaign's story layer: five arcs on top of the open-play job loop.
This is the master plan — detailed enough to rebuild any arc from scratch.
Built arcs have authoritative design docs in `ee/ragtag/missions/<id>.md`; this
file holds the connective tissue, the unbuilt arc specs, and the cross-arc state
contract.

Status at last update (2026-11-10):

| # | Arc | Status | Module |
|---|-----|--------|--------|
| 1 | Rezkov Arc | **BUILT** | `ee/ragtag/missions/rezkov.lua` + `rezkov.md` |
| 2 | Ledger Arc (accounting AI) | planned | — |
| 3 | Boneyard Arc | **BUILT** | `ee/ragtag/missions/boneyard.lua` + `boneyard.md` |
| 4 | Corsair Arc (redemption) | planned | — |
| 5 | Maw Arc (finale) | planned | — |

## Shape of the campaign

```
            ┌─> 2. Ledger (evidence thread) ──┐
1. Rezkov ──┼─> 3. Boneyard (science thread) ─┼─> 5. Maw (finale)
            └─> 4. Corsair (ally thread) ─────┘
```

- **Rezkov is the gate**: it establishes the crew as serious independent
  operators and plants the seed for the Ledger arc (the M2 "traffic log" hack
  actually installed a rogue AI in Concord's accounting systems — that line is
  already in the built arc's ship log).
- **Arcs 2–4 run in any order.** Each one surfaces a different facet of the same
  secret — Project Ashgrave Synthesis — and each exports one *thread* the finale
  consumes: evidence, science, allies.
- **The Maw arc pays everything off.** The more threads the crew brings, the
  better the ending. It should be playable (brutally) with only the science
  thread, since the reversal protocol is the core mechanism.
- Director stays observation-only. All beats are scripted; no `ai = true`.

The through-line, in one sentence: *the Concord engineered the Hollow, buried
it, and twenty years of the Drift's misery — the drones, the sealed Maw, the
tariffs, the battle groups — is the cost of keeping it buried.*

---

## Arc 1 — Rezkov Arc (BUILT)

Full detail: `ee/ragtag/missions/rezkov.md`. Summary of what matters downstream.

- **Trigger**: Independent rep ≥ +500, upgrade spend ≥ 600cr, not declined/done.
  Concord rep ≥ 0 required at M1 accept (Rezkov won't use a flagged crew).
- **Structure**: hook (Dustmote rumors → Thresh) → m1_navigate (meet Rezkov at
  hidden waypoint) → m2_active (hack Waypoint Galen frontshield to 100%) →
  m2_deliver (card to Thresh) → m3_active (intercept CWS Meridian) →
  m3_deliver / done.
- **The M3 choice** (Commander Kael, Concord Intelligence, aboard the disabled
  Meridian): cooperate with Concord, or wipe the surveillance data.
- **Exports** (long-term flags):
  - `rezkov_arc_done` = `"concord_won"` | `"data_delivered"` |
    `"meridian_destroyed"` | `"meridian_escaped"`
  - `kael_alive` = true unless the Meridian was destroyed

## Arc 2 — Ledger Arc (accounting AI) — PLANNED

**Premise.** Rezkov re-establishes contact: the Galen job was never about a
traffic log. The hack implanted a rogue AI in the Concord accounting system,
and it has spent months reading the books. It found a black budget that never
closed: line items flowing for twenty years to "Maw containment" and "Ashgrave
remediation" — paying for drone maintenance that officially doesn't happen and
a research archive that officially doesn't exist. Now a Concord financial audit
sweep is closing in on the implant. Get the findings out before the AI is found
and burned — and before Concord traces the implant back to the crew.

**Hook by Rezkov outcome** (the arc must work for every `rezkov_arc_done`):
- `data_delivered` / `meridian_escaped`: Rezkov hails directly (respawn his
  waypoint, same pattern as M1).
- `concord_won`: Rezkov is burned and gone. The AI itself makes contact — a
  stilted, anonymous hail relayed through Dustmote. Thresh brokers.
- `meridian_destroyed`: as above, but Concord patrol pressure in the arc is
  elevated (they're already angry).

**Structure sketch** (phases):
1. `hook` — rumor category `LEDGER_HOOK`: "Concord auditors crawling all over
   Lumen Exchange", "word is something's wrong with Concord's books".
2. `contact` — Rezkov/Thresh briefing; accept.
3. `relay_run` — the AI can't push the full ledger through Concord comms. It
   stages encrypted fragments at three dead drops (derelicts / a signal buoy —
   science scan to locate, short time window per drop as the audit sweep
   advances). Two of three fragments suffice; all three improve the finale
   evidence quality.
4. `exfil` — Concord Hostile audit-escort squadron intercepts after the second
   pickup (spawned at scan edge, comms-first: "surrender the data"). Fight or
   run; a warp-out escape is legitimate here (no jammer — contrast with
   Boneyard).
5. `deliver` — hand the assembled ledger to Thresh at Dustmote → done.

**Exports**:
- `ledger_arc_done` = `"full"` (3 fragments) | `"partial"` (2) | `"lost"`
- `ledger_evidence` = true when done with full/partial
- Rep: Concord -200 on completion (they know *someone* has the books);
  Independent +200. Credits ~500.
- SCIDB: add a new locked Lore entry **"The Containment Ledger"** at build time
  (lock key `ledger_findings`): twenty years of black-budget flows, signed at
  senior level — the *names* thread the finale's broadcast ending needs.

**Trigger sketch**: `rezkov_arc_done` set (any value), upgrades ≥ 800,
`not_flagged = {ledger_arc_done}`.

## Arc 3 — Boneyard Arc (BUILT)

Full detail: `ee/ragtag/missions/boneyard.md`. Summary of what matters downstream.

- **Trigger**: upgrade spend ≥ 800cr, not done.
- **Structure**: hook (battle-group rumors; fly within 8U of Ashgrave) →
  approach (Ashgrave Annex spawns) → annex_hack (Science hacks frontshield to
  100%; drones go idle) → annex_control (60s archive download and/or 30s drone
  IFF reprogram, while a 6-ship Concord Hostile battle group closes at warp and
  a jammer seals the region at ~90s) → extract (fly out past the Boneyard
  boundary) → done.
- **Exports**:
  - `boneyard_arc_done`; `boneyard_hack_done` (archive downloaded);
    `boneyard_drone_flip` (drones now `Relic Active`, hostile to Concord);
    `boneyard_battlegroup_destroyed` (CNS Vanguard killed)
  - SCIDB unlocks on data: `hollow_true_nature`, `ashgrave_research`,
    `synthesis_details` — these contain the finale's core mechanic: **Phase II
    reversal = targeted EM broadcast at a documented frequency, within range of
    the subject population, 90 seconds minimum; Phase III efficacy untested.**
  - Rep: Concord -300 (-500 with drone flip); Corsairs +150 with drone flip.
    Credits 600 (data) + 200 (flip).

## Arc 4 — Corsair Arc (redemption) — PLANNED

**Premise.** The second battle group (seeded by the Boneyard hook rumors: two
groups left Lumen) gets its destination: Blackwater Reach. Concord has decided
to solve its Corsair problem permanently — and quietly, while the Drift is
distracted. The arc humanizes the Corsairs: many crews are Settlement War Free
Ship veterans and their children, pushed into the Gauntlet by the "transitional"
tariffs that never transitioned. The crew learns the strike is coming before
the Corsairs do.

**Hook.** A Corsair ship *doesn't* attack: a damaged raider limps out of the
Gauntlet broadcasting a general distress — half her crew dead, hit by Concord
"survey pickets" that are actually the battle group's vanguard. Rendering aid
(or even just hearing her out) opens the arc. Alternative hook at Saint
Brennan's Mission: wounded Corsairs in the clinic, and the sister who runs it
asks the crew to carry a warning no one else will.

**Structure sketch** (phases):
1. `hook` — rumor category `CORSAIR_HOOK` + the distress encounter.
2. `parley` — escorted (blind-jump style: follow a Corsair guide ship) to
   Blackwater; meet the Corsair quartermaster (name her — proposed: **Reva
   Okonkwo**, ex-Free Ship gunnery chief). She doesn't want saving; she wants
   *options*. Crew chooses a track:
   - **Evacuate**: convoy of civilian hulls (families, wounded) out of
     Blackwater through the Gauntlet to Saint Brennan's / the Rim before the
     hammer falls. Escort mission against Concord Hostile interceptors.
   - **Defend**: help prep Blackwater — reseed the minefield gap, hack the
     battle group's targeting relay (reuse hacking mechanics), then fight the
     vanguard at the Veil.
   - **Walk away / sell them out**: report the Corsair disposition to Concord
     at Sentinel Fleet Yard. Big Concord rep payoff, permanent Corsair
     hostility, and the finale loses the ally thread. This must be a real,
     payable choice.
3. `strike` — the battle group arrives either way; outcome depends on track.
4. `done`.

**Exports**:
- `corsair_arc_done` = `"evacuated"` | `"defended"` | `"betrayed"` | `"failed"`
- `corsair_ally` = true on evacuated/defended → Corsair comms turn
  `Corsair Friendly` for the crew (existing faction, already wired); Blackwater
  becomes dockable staging for the Maw run.
- Rep: Corsairs +400 (ally paths) / set to floor (betrayed); Concord -300 (ally
  paths) / +400 (betrayed).
- Rumor category `CORSAIR_DONE` seeds the finale either way.

**Trigger sketch**: upgrades ≥ 1000, `not_flagged = {corsair_arc_done}`;
Corsairs rep > -400 for the ally hooks (below that, only the Saint Brennan's
hook works — the sister vouches for the crew).

## Arc 5 — Maw Arc (finale) — PLANNED

**Premise.** Everything converges on the Pale Sun. The crew has some or all of:
the *science* (Phase II reversal broadcast — Boneyard), the *evidence* (the
Containment Ledger — Ledger arc), and the *allies* (Corsair staging and escort
— Corsair arc). Lastchance Outpost is the staging door; The Maw station is the
target: get a broadcast source inside Hollow space and hold it on the
documented frequency for 90+ seconds while everything the Pale Sun has
converges on the ship.

**Thread effects** (design rule: each thread removes one layer of pain, none is
individually mandatory except science — see open questions):
- **Science** (`boneyard_hack_done`): unlocks the reversal broadcast objective
  at all. Without it, the finale offers a desperate fallback: recover the
  protocol from a wrecked Concord research hulk *inside* the Maw first (one
  extra deadly phase).
- **Evidence** (`ledger_evidence`): adds the political ending — after the
  broadcast, transmit the ledger Drift-wide from the Maw relay. Concord can't
  bury what everyone has read. Gates the best ending.
- **Allies** (`corsair_ally`): Blackwater staging (repair/rearm inside the
  approach), plus a Corsair escort wing in the final hold. Without it, the
  approach runs from Lastchance with no support.
- **Drones** (`boneyard_drone_flip`): the `Relic Active` wing arrives as
  late-battle cavalry during the 90-second hold. Pure payoff, no gate.
- **Kael** (`kael_alive` + `rezkov_arc_done`): if alive, Kael resurfaces at
  Lastchance — as a quiet defector handing over Concord patrol schedules
  (`concord_won` path: the crew's cooperation earned his trust, and the ledger
  broke his faith), or as a pursuer who must be shaken or turned
  (`data_delivered` path). If dead, a Concord hunter group replaces him.

**Structure sketch** (phases):
1. `hook` — rumor category `MAW_HOOK` (fed by `BONEYARD_DONE`/`CORSAIR_DONE`
   rumors already in place); briefing at Lastchance Outpost.
2. `staging` — gather threads; Kael beat; fit the broadcast rig (one-off
   "upgrade" granted via `RT.grantUpgrade`-style story reward or a mission
   item flag).
3. `approach` — cross the Maw boundary. Hollow proximity spawns suspended via
   `PROX.suspendZone("the Maw")`; the arc runs its own scripted waves so the
   pacing is authored, not ambient.
4. `broadcast` — hold within ~10U of The Maw station for 90 continuous seconds
   of broadcast (timer pauses if the ship leaves range — comms-as-timer pattern
   from the Boneyard Annex). Scripted Hollow waves; defense platforms;
   cavalry/escort per threads. GM skip buttons for every wave.
5. `aftermath` — the Hollow go dormant (Derelict-style idle, mirroring the
   Boneyard drones going quiet — deliberate echo). Optional ledger transmission
   beat. Exit the Maw.
6. `done` / `M.resolve`.

**Endings matrix** (resolve on flags):

| Science | Evidence | Outcome flag `maw_arc_done` | Ending |
|---|---|---|---|
| yes | yes | `"liberation"` | Hollow dormant, cover-up exposed, Concord in crisis — the Drift changes |
| yes | no  | `"mercy"` | Hollow dormant; Concord spins it; the crew knows the truth, the Drift doesn't |
| fallback | any | `"pyrrhic"` | Broadcast ran on a recovered, degraded protocol — partial dormancy, Maw still dangerous |
| failed hold | — | arc restartable | retreat; Maw unchanged |

- SCIDB: unlock `maw_full` on any completion; update the Hollow/Maw entries'
  key-values post-broadcast (via `SCIDB.get` — entries are mutable).
- Rep: Independent +500 on any success; Concord per ending (−500 liberation,
  −200 mercy); Corsairs +200 if they flew escort.

**Trigger sketch**: upgrades ≥ 1500 AND (`boneyard_arc_done` or a GM override)
AND at least one other arc done, `not_flagged = {maw_arc_done}`.

---

## Cross-arc state contract

Flags any future arc may rely on (never rename these):

| Flag | Written by | Values |
|---|---|---|
| `rezkov_arc_done` | Rezkov | `concord_won` / `data_delivered` / `meridian_destroyed` / `meridian_escaped` |
| `kael_alive` | Rezkov | true / false |
| `ledger_arc_done`, `ledger_evidence` | Ledger | outcome string / bool |
| `boneyard_arc_done`, `boneyard_hack_done`, `boneyard_drone_flip`, `boneyard_battlegroup_destroyed` | Boneyard | bool |
| `corsair_arc_done`, `corsair_ally` | Corsair | outcome string / bool |
| `maw_arc_done` | Maw | ending string |

SCIDB lock keys: `hollow_true_nature`, `ashgrave_research`, `synthesis_details`
(Boneyard); `maw_full` (Maw); `ledger_findings` (Ledger, to be added in
`ee/ragtag/world/sciencedb.lua`).

Rumor categories: `<ARC>_HOOK` injected in hook enter / removed in hook exit;
`<ARC>_DONE` injected at resolve (persistent flavor for the session).

## Rebuild notes

If an arc module is lost, rebuild against these rails:

- **Engine**: MISSIONS phase machine — `ee/ragtag/missions/_engine.lua`,
  reference docs in `.claude/skills/sandbox-missions/references/missions_api.md`
  (authoritative; checklist in that skill's SKILL.md). Reference
  implementations: `rezkov.lua` (comms/choice-heavy), `boneyard.lua`
  (combat/timer-heavy).
- **Integration surface per arc**: one module file + one design md in
  `ee/ragtag/missions/`, one `require` line in `ee/ragtag/missions.lua`
  (`check.py` errors if forgotten), `MISSIONS.register(M)` at the bottom.
  Retired arcs go to `ee/ragtag/missions/attic/`.
- **Key patterns**: `PROX.suspendZone`/`resumeZone` when an arc owns a region;
  `RT.onKill` for all destruction hooks (never `entity:onDestruction`);
  `SCIDB.unlock`/`SCIDB.addEntry` from `M.resolve`; comms-as-timer for held
  operations; `RT.flag`/`RT.clearFlag` for cross-session state; GM skip action
  per phase, each calling `_clearState` first.
- **Factions available**: `Concord Hostile` (targetable law), `Corsair
  Friendly` (allied pirates), `Relic Active` (reprogrammed drones, anti-Concord)
  — all defined in `VERSE.setupFactions()`.
- Run `python tools/check.py` after every change; headless smoke test before
  calling an arc done.

## Open questions / tuning

- Should the Maw arc hard-require `boneyard_hack_done`, or is the in-Maw
  fallback recovery enough? (Current plan: fallback exists, tuned brutal.)
- Ledger arc fragment count and audit-sweep timing need playtest numbers.
- Corsair "betrayed" path: does it lock the Maw arc's ally thread only, or
  should Corsair hunters also appear during the finale approach?
- Does the Maw broadcast hold (90s) need a mid-hold breather wave gap for
  Engineering to recover? Boneyard playtests should inform this.
- Kael's defector beat assumes `concord_won`; decide whether `data_delivered`
  Kael can also be turned with `ledger_evidence` in hand.
