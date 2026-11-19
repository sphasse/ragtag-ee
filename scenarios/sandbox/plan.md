# The Drift — five-arc story plan (plus an optional sixth)

The sandbox campaign's story layer: five arcs on top of the open-play job loop, with an
optional sixth serial that unlocks after the finale (Arc 6, below).
This is the master plan — detailed enough to rebuild any arc from scratch.
Built arcs have authoritative design docs in `ee/ragtag/missions/<id>.md`; this
file holds the connective tissue, the unbuilt arc specs, and the cross-arc state
contract.

Status at last update (2026-11-12):

| # | Arc | Status | Module |
|---|-----|--------|--------|
| 1 | Rezkov Arc | **BUILT** | `ee/ragtag/missions/rezkov.lua` + `rezkov.md` |
| 2 | Ledger Arc (accounting AI) | **BUILT** | `ee/ragtag/missions/ledger.lua` + `ledger.md` |
| 3 | Boneyard Arc | **BUILT** | `ee/ragtag/missions/boneyard.lua` + `boneyard.md` |
| 4 | Corsair Arc (redemption) | **BUILT** | `ee/ragtag/missions/corsair.lua` + `corsair.md` |
| 5 | Maw Arc (finale) | planned | — |
| 6 | Concord Republic Arc (optional serial) | planned | — |

## Shape of the campaign

```
            ┌─> 2. Ledger (evidence thread) ──┐
1. Rezkov ──┼─> 3. Boneyard (science thread) ─┼─> 5. Maw (finale)
            └─> 4. Corsair (ally thread) ─────┘
                                                    └─> 6. Concord Republic (optional serial)
```

- **Rezkov is the gate**: it establishes the crew as serious independent
  operators and plants the seed for the Ledger arc (the M2 "traffic log" hack
  actually installed a rogue AI in Concord's accounting systems — that line is
  already in the built arc's ship log).
- **Arcs 2–4 run in any order.** Each one surfaces a different facet of the same
  secret — Project Ashgrave Synthesis — and each exports one *thread* the finale
  consumes: evidence, science, allies. Two arcs being eligible at once is fine
  (it thins the rumor pressure and gives the crew a choice).
- **The Maw arc pays everything off, and requires all three.** It is a
  Death-Star run, not a siege: one warhead, one target, one shot. The *how* of
  each earlier arc (did the ledger survive, did the Corsairs become allies,
  were the drones flipped) shapes the run and the ending; the arcs themselves
  are hard prerequisites. No in-Maw fallback for a missing thread.
- **The Hollow are people.** They are victims, not a boss. The finale is built so
  the crew never has to grind through them: the climax is finding and hitting
  the rift, then getting out while the reversal takes hold.
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
- **The M3 choice** (Commander Kael — she/her — Concord Intelligence, aboard
  the disabled Meridian): cooperate with Concord, or wipe the surveillance data.
- **Exports** (long-term flags):
  - `rezkov_arc_done` = `"concord_won"` | `"data_delivered"` |
    `"meridian_destroyed"` | `"meridian_escaped"`
  - `kael_alive` = true unless the Meridian was destroyed
- **Kael downstream**: a Concord officer who turns out to be a force for good.
  She has a small information role in the finale's staging (below) and is the
  natural lead for a post-campaign follow-on (Kael rises in the Concord;
  relations normalise). Keep her alive-by-default in writing: only the
  `meridian_destroyed` path kills her.

## Arc 2 — Ledger Arc (accounting AI) (BUILT)

Built 2026-11-13; full design in `ee/ragtag/missions/ledger.md`. Summary:

- **Premise.** The Galen hack planted an AI in the Concord books. It found the twenty-year
  black budget ("Maw containment", "Ashgrave remediation"), split itself into three fragments
  inside Concord space, and needs a pickup.
- **Trigger.** Upgrades ≥ 800, Rezkov arc finished or declined, then 2 board jobs by the primary ship, `ledger_arc_done` unset.
  Briefing variant on `rezkov_ai_planted` ("you planted it" vs "I had a crew plant it").
- **Flow.** Vague rumors → Thresh at Dustmote → Rezkov's station (briefing) → fly into three
  data cores near Valcourt, Ostia and Waypoint Galen → the assembled AI drains 3 energy/s and
  60 s later a three-ship Concord Audit Service fleet spawns ahead → dock at Rezkov's station.
  Concord hostility comes from the crew's own reputation (no override).
- **Exports.** `ledger_arc_done` = `"full"` | `"lost"` (energy hit zero, or surrendered to the
  audit fleet); `ledger_evidence` on full; 600 cr, Concord −200, Independent +200 on full.
  SCIDB Lore "The Containment Ledger" (`ledger_findings`) names the signatories: Voss
  (Treasury), Hale (Fleet Logistics), Tan (Applied Research), the Council's Standing Committee.
- **Rezkov holds the ledger.** He will not release it until it cannot be buried; the Maw
  finale's aftermath is where it goes public.

## Arc 3 — Boneyard Arc (BUILT)

Full detail: `ee/ragtag/missions/boneyard.md`. Summary of what matters downstream.

- **Trigger**: upgrade spend ≥ 800cr, Rezkov arc finished or declined (`requires`), not done.
  Rezkov is the gate for every Phase II arc (Ledger, Boneyard, Corsair).
- **Structure**: hook (battle-group rumors; the Annex spawns when the survivors are recovered, or at 8U from Ashgrave) →
  annex_hack (Relay hacks frontshield to
  100%, from range by probe; drones go idle, later ones too; the Annex becomes dockable) →
  annex_control (docked only, one operation at a time: 2 min archive download that stops on
  undocking, 60s drone reprogram, 60s station defense lasers; the first docking brings a
  7-ship Concord Hostile battle group 15U out; the reprogram launches 24 fast drones from
  two nebulae; no warp jammer; CNS Vanguard fights like any other ship) → report (archive
  in and fleet gone: talk with the lifeboat survivors, docked at the rescue job's station) → done.
  Without the survivors, the won fight with the archive is the end.
- **Exports**:
  - `boneyard_arc_done`; `boneyard_hack_done` (archive downloaded);
    `boneyard_drone_flip` (drones now `Relic Active`, hostile to Concord);
    `boneyard_battlegroup_destroyed` (CNS Vanguard killed)
  - SCIDB unlocks on data: `hollow_true_nature`, `ashgrave_research`,
    `synthesis_details` — these contain the finale's core mechanic. The
    current entry text says *broadcast, within range, 90 seconds*; the Maw
    build revises it (entries are mutable via `SCIDB.get`) to the warhead
    version: **Phase II reversal = a modulated EM pulse delivered into the
    spatial rift the Synthesis collective is anchored on; the dormancy cascade
    takes ~90 seconds to propagate; Concord shelved it because no delivery
    vehicle survived the Maw.** The archive also carries the warhead schematic
    — that is what `boneyard_hack_done` means to the finale.
  - Rep: Concord -300 (-500 with drone flip); Corsairs +150 with drone flip.
    Credits 600 (data) + 200 (flip).

## Arc 4 — Corsair Arc (redemption) — BUILT 2026-11-15 (details: `ee/ragtag/missions/corsair.md`)

**Premise.** The Concord's second battle group (seeded by the Boneyard hook rumors: two groups
left Lumen) is coming for Blackwater Reach, to settle the Corsair problem quietly while the Drift
is distracted. Many Corsairs are Settlement War Free Ship veterans and their children, pushed into
raiding by the "transitional" tariffs. A raider who has been watching the crew brings them in;
the crew raids a Concord forward depot so the Corsairs can thicken Blackwater's mine ring with its
mines, then stands in the Corsair line when the fleet arrives. Linear: defend, or don't do it.

**Trigger:** upgrades >= 1000, Rezkov arc finished or declined, `corsair_arc_done` unset, and the crew enters the Gauntlet.

**Phases:** `hook` -> `escort` -> `briefing` -> `raid` -> `return` -> `battle` -> `done`
1. `hook` — rumors point to Greywater Depot, where the barkeep passes a message: *Long Memory*
   waits at the Gauntlet's edge (fallback: entering the Gauntlet). Replies: Follow / Not right
   now (hook stays open, re-offered after 10 min) / Tell your people to forget us (`declined`).
   The raider closes without attacking and hails:
   "We watch things in the Drift, and we know you are someone who is not intimidated by the Concord.
   Somebody at Blackwater wants to talk to you. Follow us." Follow / Not interested
   (-> `declined`). Only this hook (no distress call, no Saint Brennan's hook).
2. `escort` — follow the *Long Memory* to Blackwater. Corsair territory is temporarily friendly
   (garrisons + Blackwater), Corsair PROX spawns suspended. Straying > ~8U: warning hail, guide waits.
3. `briefing` — docked at Blackwater, quartermaster **Reva Okonkwo** (ex-Free Ship gunnery chief):
   "We have some fierce fighters out in the Drift and guarding Blackwater, but most of the ships
   here are families." The Corsair tax: "we only take back what the tariffs took, and only from
   Concord hulls or to defend our territory." The Concord has provisioned a forward depot for the
   invasion between Cinder and Tamsin (~(-60, 62)): mines and missiles, guarded by two Concord ships. Reva gives the crew two decent Corsair ships to take it.
4. `raid` — the two Corsair ships are commanded through comms like escort-job ships, with the
   orders unlocking in sequence: "Form up on me" -> (within ~5U of the depot) "Attack the Concord
   defenders" -> (defenders dead) "Board the depot and take the weapons". The crew does not
   board: the Corsairs dock, load (~30 s) and hail: "We're loading up the haul. Meet you back at
   Blackwater." Defenders are `Concord Hostile` (no auto rep penalty; the arc applies its own).
5. `return` — dock at Blackwater. Reva thanks the crew: every mine from the haul is going into
   Blackwater's mine ring, thick enough that only a few lanes are open (no jammers, no mines for
   the crew). Then: "And just in time too. News is the Concord attack fleet was just detected at
   <grid> and is closing fast. … will you fly out and join our defense?" Join / Decline
   (-> `failed`: the defense started without them).
6. `battle` — reworked 2026-11-18 after the Battle Lab: a set piece with its rules
   (`ee/ragtag/battle.lua`). 7 Concord ships and 12 Corsairs in two lines 25U west of Blackwater,
   frozen until the crew comes within 5U of the Corsair line; then fought over five combat points.
   All 7 Concord destroyed -> `defended`; the crew's ship destroyed -> `failed` (the Corsairs may
   all be lost). Details: `ee/ragtag/missions/corsair.md`, "The battle" and "The mine ring".

**Flags:** `corsair_hook`, `corsair_briefed`, `corsair_raid_done`, `corsair_joined`,
`corsair_arc_done`, `corsair_battlegroup_destroyed`, `corsair_ally`, `corsair_rewarded`,
`corsair_met_reva` (new SCIDB profile via `SCIDB.meet`).

**Exports / outcomes (`corsair_arc_done`):**
- `"defended"` — `corsair_ally` (Corsairs `Corsair Friendly` for the crew; Blackwater dockable
  staging for the Maw run) and `corsair_battlegroup_destroyed` (Arc 6 trigger input).
  Corsairs +400, Concord -300.
- `"failed"` — Blackwater falls, or the crew declined the final battle after the raid. No ally,
  no Arc 6.
- `"declined"` — turned down the hook. No ally.
- Rumor category `CORSAIR_DONE` seeds the finale either way.

**Decided (2026-11-15):**
1. One prep mission: the depot raid only.
2. Each raid escort lost is replaced at once: Reva hails with the lost ship's and the new ship's
   names (changed 2026-11-18 from "losing both restarts the raid").
3. Declining the final battle after the raid counts as `"failed"` (the defense started and did
   not finish successfully); `"declined"` only comes from turning down the hook.

## Arc 5 — Maw Arc (finale) — PLANNED

**Premise.** The Synthesis collective is anchored on a spatial rift near the
Pale Sun — the "electromagnetic anomalies" in the Maw entry. The Ashgrave
archive's Phase II reversal was never a broadcast: it is a modulated EM pulse
delivered *into* the rift, which the collective then carries to every subject
at once. Concord shelved it because nothing they sent into the Maw came back.
The crew has the schematic (Boneyard), the proof of who did this (Ledger), and
the only fleet in the Drift willing to fly cover (Corsairs). The Hob Works at
Hob's Landing (the Drift's independent science and engineering yard) builds one
warhead from the schematic, with Thresh brokering and paying for it. The crew
gets one shot. (Decided 2026-11-19: the Works, not Dustmote, builds it; Thresh
keeps Rezkov's network in the finale.)

**Shape of the run** — a Death-Star trench run, every station busy:
- **Science** finds the rift (it is hidden in the Maw nebula; three EM
  anomalies must be scanned to triangulate it) and reads the anchor field.
- **Helm / Engineering** fly the run: Hollow waves, the nebula, the anchor
  platforms, and after the shot a backlash-crippled ship that has to get out.
- **Weapons** drops the two anchor platforms that screen the rift, then makes
  the one shot that matters.
- **Relay** hacks the anchor platforms (the no-kill route), holds the thread to Lastchance, Kael and the escort wing, and after
  the shot transmits the Containment Ledger to the whole Drift.

**The warhead** ("the Ashgrave warhead" — one EMP, one rack):
- Granted in `staging`: `maw_warhead = "fitted"` (RT.flag). On every player
  spawn while the flag is `"fitted"`: `setWeaponStorageMax("EMP", 1)`,
  `setWeaponStorage("EMP", 1)`, make sure a tube exists
  (`getWeaponTubeCount() == 0` → add one as `front_tube` does) and allows EMP
  (`weaponTubeAllowMissle(i, "EMP")`). It is a flag, not an `RT.UPGRADES`
  entry, so it never appears in the shipwright and can be cleanly revoked.
- When EMP storage drops to 0 (polled in `update`): `setWeaponStorageMax("EMP",
  0)` immediately — the rack is gone and no station or dock can refill it.
  `RT.restockMenu` only lists Homing/HVLI already. Flag → `"spent"`.
- The shot only counts if it hits the rift while the anchor field is down (see
  `run`). A spent warhead with no hit is the fail state: the arc restarts from
  `staging`, and the Hob Works can build a second one for 500cr, ordered through
  Thresh ("the schematic was the easy part") — GM button to re-grant for free.
- Hit detection — **the rift is an entity** (verified against the engine
  source, EE commit b492ea94): a stationary `CpuShip` ("Defense platform"
  template, Hollow, `setCanBeDestroyed(false)`, shields 0, beams zeroed,
  radar trace restyled) at the rift position. Weapons can lock it and the EMP
  detonates on it because it has a `Hull`. Set
  `hull.damaged_by_emp = true` and `damaged_by_energy/kinetic = false` so only
  the warhead registers, then `onTakingDamage(fn(anchor, instigator))` *is*
  the hit (fires even with destruction disabled). The anchor-field rule is a
  guard inside that callback (platform alive → "the pulse didn't take" →
  miss). EMP facts: 0.2 U/s, 27 s lifetime (~5.4 U reach), 0.5 U homing,
  1 U blast — a 20 s flight from 4 U, and any Hollow hull in the path eats it.
- **No `WormHole` until after the hit.** A live wormhole pulls every physics
  entity in range to its centre and teleports it (`gravity.cpp`) — including
  the missile, which would arrive at Lastchance undetonated, and the anchor
  itself. On the hit: destroy the anchor, spawn the `WormHole` in its place as
  the exit (`setTargetPosition` 4U off Lastchance). The shot opens the door.

**Thread effects** (all arcs are prerequisites; their *outcomes* shape the run):
- **Ledger** (`ledger_evidence`): the ledger transmission beat in `aftermath`
  and the two best endings. `ledger_arc_done = "lost"` still unlocks the arc
  but the Drift never learns why.
- **Corsairs** (`corsair_ally`): a Corsair escort wing (3–4 ships, `Corsair
  Friendly`) joins at Lastchance and flies the whole run; Blackwater is a
  repair/rearm stop on the way. `"failed"` / `"declined"` → no wing, nothing else.
- **Drones** (`boneyard_drone_flip`): a `Relic Active` wing warps in at the
  start of `cascade` to cover the exit. Pure payoff.
- **Kael** (`kael_alive`): she meets the crew at Lastchance in `staging` with
  the Concord research addendum the archive didn't have — the rift is screened
  by two anchor platforms and the pulse won't take while their field is up
  (the "exhaust port" brief). She turns if `rezkov_arc_done == "concord_won"`
  *or* `ledger_evidence` is set; otherwise the same brief comes anonymously
  through Thresh and Kael is saved for the follow-on. If dead, Thresh alone.
  Concord does not appear in the climax.
- **The face of the finale**: **Marit Sauvola**, Lastchance stationmaster. Her
  parents stayed on a Pale Sun colony when the sector was sealed. She is the
  one who asks the question the arc is about: *"Can you bring them back?"* She
  gives the hook briefing, keeps the relay open during the run, and gets the
  last line in `aftermath`.

**Structure** (phases):
1. `hook` — rumor category `MAW_HOOK` (alongside the `BONEYARD_DONE` /
   `CORSAIR_DONE` rumors already in place): Lastchance is calling for any ship
   that has been to Ashgrave. Advance when the player docks at Lastchance:
   Sauvola's briefing, objective set.
2. `staging` — at Lastchance: Kael/Thresh brief; a freighter from the Hob Works
   (Hob's Landing, ~54U away) arrives with the warhead (comms "Transfer warhead" → `maw_warhead = "fitted"`,
   EMP rack appears); Corsair wing arrives if allied. Advance when the player
   undocks with the warhead fitted and enters the Maw boundary (39U from
   156,109). Restart point for every fail.
3. `approach` — `PROX.suspendZone("the Maw")`. Clear the verse's Hollow
   garrisons (five groups, two platforms) and place the arc's own: two outer
   pickets, the Maw station's guard, and the two **anchor platforms** flanking
   the (not yet revealed) rift. Spawn three **EM anomaly** artifacts (scannable,
   `setCanBeDestroyed(false)`) around the nebula; each scan logs a bearing,
   the third reveals the rift: spawn the `WormHole` (target position:
   Lastchance, see `cascade`) and log its grid. Scripted Hollow waves on a
   timer; GM skip reveals the rift.
4. `run` — the rift is screened by the two anchor platforms (Hollow, 4U either
   side). While either is alive the anchor field is up: Science log + Sauvola
   make it explicit that the shot will not take. Platforms are destroyed or
   hacked (Relay, reusing the hacking mechanic: `beamweapons` to 100% drops
   that platform's field — the no-kill option). Field down → "Fire when ready."
   Weapons fires the EMP at the rift from inside ~4U. Waves continue through
   the run; GM skip for each wave and for "field down". Hit → big
   `ElectricExplosionEffect` at the rift, backlash on the player (shields to 0,
   warp health −0.5) → `cascade`. Miss → fail, restart `staging`.
5. `cascade` — the 90 seconds the archive promised, played as the escape, not
   a hold. Every Hollow ship in 20U gets a dormancy timer: at 30/60/90s a third
   of them flip to `Derelict` and `orderIdle` (the fight gets quieter as it
   works). The ones still awake at each step rush the player. The rift stays
   open until 90s and **leads out**: flying through it drops the ship 4U off
   Lastchance (`setTargetPosition`). Helm chooses — dive through the thing
   they just shot, or run the long way on a crippled drive. Relic Active wing
   warps in at 0s if flipped. At 90s the rift collapses (destroy it), all
   remaining Hollow go dormant → `aftermath`.
6. `aftermath` — Sauvola on comms. Ledger beat (if `ledger_evidence`): Rezkov, who has
   held it since the Ledger arc, releases it, and Relay transmits the Containment Ledger
   from Lastchance's relay to every station;
   Kael, if turned, sets out for Ostia Highport to put it before the Concord government;
   Imperial hardliners cut her off and she is trapped at Concord Waypoint Galen — her
   last hail to the crew is the hook for Arc 6. Resolve. Seed Arc 6's rumors now (see Arc 6
   "Seeding").

**Endings** (resolve on flags + a Hollow kill tally kept via `RT.onKill`
through `approach`–`cascade`; `instigator` = player or escort):

| `ledger_evidence` | Hollow destroyed | `maw_arc_done` | Ending |
|---|---|---|---|
| yes | ≤ threshold (tune; ~6) | `"liberation"` | The Pale Sun wakes up human; the cover-up is public; Concord in crisis |
| yes | > threshold | `"mercy"` | The truth is out, but the Pale Sun is mostly a graveyard |
| no (ledger lost) | any | `"quiet"` | The Hollow are dormant; Concord calls it a "stabilisation"; only the crew knows |
| warhead spent, no hit / ship lost | — | unset, restart `staging` | second warhead 500cr |

- SCIDB: unlock `maw_full`; rewrite the Hollow / Maw entries' text and
  key-values post-cascade (`SCIDB.get` — entries are mutable).
- Rep: Independent +500 on any success; Concord −500 (liberation/mercy), −200
  (quiet); Corsairs +200 if the wing flew. Credits 1000.
- **World after** (integration outside the arc module; `VERSE`/`PROX`/world
  plugins read `maw_arc_done` at build): Hollow garrisons spawn as dormant
  `Derelict` hulks; the Maw PROX zone is off; region danger 3 → 1; The Maw
  station becomes Independent and dockable with a new description. On
  `liberation` only: Concord shakedown spawns in the Core stop (Concord has
  bigger problems). Rumor category `MAW_DONE`.
- **Follow-on**: Kael rises in the Concord on the back of the ledger; relations
  normalise; the "transitional" tariffs finally transition. That is Arc 6 below, an
  optional sixth arc, available only on `liberation` or `mercy`.

**Trigger**: upgrades ≥ 1500 AND `boneyard_hack_done` AND `ledger_arc_done`
(any) AND `corsair_arc_done` (any), `not_flagged = {maw_arc_done}`. The
Boneyard GM "→ Complete arc" button already sets `boneyard_hack_done` for
crews that skipped the download.

---

## Arc 6 — The Concord Republic (optional serial after Arc 5) — PLANNED

**Premise.** The Maw cover-up is public. Concord's two battle groups are gone (the
Boneyard group and the Blackwater strike group) and the government has split. Loyalist
hardliners under **Marshal Irenaeus Vane** (proposed name) call themselves the *Concord
Imperial* forces and hold the capital. Commander **Kael** (she/her) leads the reformers,
the *Concord Republic*, but she is trapped on a remote Concord station and cannot reach
the seat of government to take control and turn the Concord into a force for good. The
crew must rally Corsair, Ashgrave and Independent forces and escort Kael's ship from
station to station through Imperial-held space, then hold her at the capital while she
takes the government.

It is the escort job at campaign scale: the job template (`jobs/escort.lua`: one slow
convoy ship, impulse only, a couple of escorts, two intercept waves) becomes a multi-leg
convoy with several rallied wings and a fierce, scripted opponent.

**Kael's backstory (her Science DB entry).** She was a fighter pilot on the Concord side
of the Settlement War who questioned her superiors' orders, went on to become a
Concord special-operations investigator, and has spent twenty years trying to find the
truth about what was buried. The entry (lock key `kael_profile`) is unlocked in the
Rezkov arc as soon as the crew meets her at M3 and `kael_alive` is set, whichever choice
they make, including "Let the Concord go". **Built** (2026-11-12): `SCIDB.addProfile("kael_profile")` in `sciencedb.lua`, called when the Kael
comms opens, flag `rezkov_met_kael` (via `SCIDB.meet`) keeps it each session. The shipped text is a
character sketch only (capable officer; no hint of her later role), shorter than the
draft below:

> **Commander Kael** — *Concord Intelligence, Special Operations Investigations.*
> Flew in the Settlement War on the Concord side, and was one of a handful of officers
> who put their doubts about the orders in writing. She was not punished; she was moved.
> After the war she transferred to special-operations investigation, where for twenty years
> she has followed the gaps in the official record. Colleagues describe her as patient,
> precise and unwilling to let a file close. Key values: Service: Concord Intelligence;
> War record: fighter pilot, Settlement War; Reputation: asks the questions nobody wants asked.

**Trigger — a bonus arc, earned by how the earlier arcs played out.** All of:
`maw_arc_done` ∈ {`liberation`, `mercy`} (the cover-up is public; `quiet` leaves Concord
intact, so no split), `kael_alive`, `boneyard_battlegroup_destroyed` (the Boneyard fleet),
`corsair_battlegroup_destroyed` (the Blackwater strike group, new flag written by the
Corsair arc when the crew kills the vanguard at the Veil), and
`not_flagged = {republic_arc_done}`. If any is missing the arc simply never fires and the
campaign ends at the Maw: that is intended, not a gap to patch. Upgrade spend is already
≥ 1500 by the Maw. Because the two fleets are really gone (the crew destroyed them), the
Imperial forces in Arc 6 are the loyalist remnant and recalled home squadrons, and the
Kael hook can say "your handiwork" without caveats.

**The factions.** Two new factions (defined in `VERSE.setupFactions`, alongside Concord
Hostile / Corsair Friendly / Relic Active):
- **Concord Imperial** — the loyalists. Hostile to the player, Corsair Friendly, Relic Active
  and Concord Republic. Friendly to `Concord` (the legacy faction on the stations).
- **Concord Republic** — Kael's side. Friendly to the player, Independent, Corsair Friendly
  and Relic Active; hostile to Concord Imperial. Reputation for it is an alias of `Concord`
  (add `RT.repAlias["Concord Republic"] = "Concord"`; today `RT.getReputation` returns 0
  for any faction without a table entry).

**Seeding (before it triggers).** Arc 5's resolve injects ~10 vague seed rumors (`REPUBLIC_SEED`,
priority 3: "the Concord senate hasn't sat in weeks", "Sentinel Fleet Yard is taking orders
from nobody the Magistrate knows") so the world already feels split. Kael's hook is an
`RT.voice` hail from nobody-in-particular (an artifact with no position: never on radar), not a rumor.

**Structure** (phases; each has a GM skip button, ≤ 18 chars):
1. `hook` — Kael hails the crew by voice from Concord Waypoint Galen: the Imperials sealed her
   in, she needs an escort to Ostia Highport. Accept by flying to Galen (the station where the
   crew started the Rezkov chain: pay it off). Docking at Galen opens her briefing and the
   rally plan.
2. `rally` — three wings, in any order, each its own mini-arc and each yielding a named
   escort squadron. The crew needs at least two to proceed; the third is the difference
   between the good ending and the narrow one.
   - **Corsair wing** (Blackwater; Reva Okonkwo from Arc 4): 6 raiders, `Corsair Friendly`.
     Requires `corsair_ally`. Reva wants proof Kael is serious: a story delivery
     (`JOBS.inject`, priority 5, `story = true`) carries Kael's signed amnesty writ for the
     Free Ship veterans from Galen to Blackwater. She holds the writ up and commits the wing.
     (Always available: the trigger already requires the `defended` path.)
   - **Ashgrave wing** (the Annex): 8 war drones refitted with warp drives, `Relic Active`.
     Requires `boneyard_hack_done` (the crew has the Annex's access codes). The arc respawns
     the Annex (the Boneyard arc destroys it in `_clearState`, so `_spawnAnnex` must be
     exported or copied). Retasking the drone net is a 45-second hold under attack by an
     Imperial raider squadron (comms-as-timer, like the Boneyard download). If the survivors
     were rescued (`boneyard_buoy_found`) they staff the console and vouch.
   - **Independent wing** (the stations): 6 gunships. Not a reputation check: the crew
     carries Kael's charter to Port Vesper, Calder's Reach and Halcyon Rest (three `story`
     deliveries injected at Galen), and each station contributes two ships. Reputation
     only changes how many extras show up; Rezkov's `concord_won` path leaves Independent
     reputation at -1000 and it must not lock the wing out.
   - The Republic loyalists already at Galen (4 ships) and Kael's flagship round out the
     escort: ~24 escorts at full strength.
3. `muster` — at Galen. The wings arrive over a minute or two, Kael's ship (the Meridian,
   or her replacement) stands by, and the crew gets **wing orders** via comms with each wing's
   lead (Screen / Hunt / Hold). Break the Galen siege to leave. **Restart point for every
   fail.**
4. `leg_1` — Galen to Lumen Exchange (~63U). Kael's ship is impulse-only (~125 u/s, about
   eight minutes). Imperial pickets (4 ships) and a Sentinel Fleet Yard sortie midway
   (a command Phobos and five escorts). Lumen flips to `Concord Republic` on arrival and
   becomes a dockable repair and rearm stop. No sabotage or assault objective: the loyalist
   fleet is finite and the crew wins by exhausting it (Sentinel's sortie and the pickets are
   ships that will not be there for leg 2). The escort is the challenge, not a side objective.
5. `leg_2` — Lumen to Ostia Highport (~37U): Marshal Vane's main fleet. This is the fierce
   one: two Atlantis X23, a Phobos T3 flagship, and fighter screens, plus a minefield the
   hardliners laid. About 18 ships, spawned in two surges so the entity count stays sane.
6. `ostia` — break the station's defense platforms and the last fleet, dock Kael, and hold
   60 seconds while she broadcasts to the government (comms-as-timer, the Boneyard control
   pattern) with the Imperial flagship still contesting. Destroying or disabling it, or
   surviving the hold, ends the battle. Vane stands down.
7. `done` — resolve: Kael takes the seat; the Concord becomes a force for good.

**Failure.** Kael's ship destroyed: restart from the last station checkpoint (`muster` if before
Lumen, `leg_2` start if after). Wings re-form at full strength at the checkpoint; only the
Imperials reset. No reputation penalty.

**Stats, voice and jobs hooks.** Wings are `RT.voice` leads (Reva, the Annex console, the
Vesper militia captain) and Marshal Vane taunts by voice during the legs; the writ and
charter run as story jobs; `STATS.arcEvent` and a handful of `ACH` entries ("Standing
Beside Kael", "No Wing Left Behind", "Three Wings") track it.

**Exports**:
- `republic_arc_done` = `"ascendant"` (all three wings, Kael's ship above 50% hull at the end)
  | `"coalition"` (two wings, or a battered Kael) — success either way; failure restarts.
- `republic_wings` (count), `republic_corsair`, `republic_ashgrave`, `republic_independent`
  (bools).
- Rep: Concord (and so Concord Republic) reset to at least +300 at the hook and to +500 on
  success; Independent +300; Corsairs +200 per Corsair wing that flew. Credits ~1500.
- SCIDB: unlock a locked Lore entry **"The Concord Republic"** (lock key `republic_formed`):
  who won, the first acts (tariffs that finally transition, the Core's shakedowns ended).

**World after** (integration outside the arc module, like Arc 5): `Concord Imperial` is gone;
Concord stations stay faction `Concord` but Concord shakedown spawns stop for good (they
already stop on `liberation`; on `mercy` this finishes the job); Core prices drop (the
"transitional" tariffs); Concord ports offer full job access again; rumor category
`REPUBLIC_DONE`. On `ascendant` Sentinel Fleet Yard sells a Republic shipwright upgrade
(design TBD) as the campaign's last reward.

### What changes in the built arcs (small retrofits)

- **Rezkov**: add the **Commander Kael** SCIDB entry (above) in `sciencedb.lua` and unlock
  it from the M3 comms where `kael_alive` is set (all alive outcomes). No other change.
- **Boneyard**: export `_spawnAnnex` (or a thin `BONEYARD.spawnAnnex()`), so Arc 6 can
  respawn it. Nothing else; `boneyard_hack_done` already means "has the codes".
- **Maw (planned)**: change the aftermath Kael beat (done above) and seed Arc 6's rumors in
  `M.resolve`; set `maw_arc_done` before the seeds so Arc 6's `on_load` sees it.
- **Factions / core**: the two new factions and the `RT.repAlias` lookup (see above).

### Where the current plot does not support this (and the plan for each)

1. **"Both fleets destroyed" is not guaranteed.** `boneyard_battlegroup_destroyed` is only
   set if the crew kills CNS Vanguard, and the Corsair arc has no equivalent flag yet.
   *Decision (user, 2026-11-12):* Arc 6 is a bonus; it requires both fleets destroyed. The
   Corsair arc must write `corsair_battlegroup_destroyed` when the vanguard dies at the
   Veil (only the `defended` path fights it). Otherwise Arc 6 does not happen.
2. **The Maw `quiet` ending has no split.** The ledger is not public, so Concord is intact.
   *Plan:* Arc 6 only triggers on `liberation`/`mercy`. `quiet` ends the campaign (a GM
   override can force it).
3. **Kael may be dead.** `meridian_destroyed` sets `kael_alive = false`. *Decision:* no
   Arc 6 in that case (trigger requires `kael_alive`).
4. **The Maw aftermath sent Kael to the senate.** That contradicted her being trapped.
   *Plan:* fixed in the Maw section above (she is intercepted and cornered at Galen).
5. **Independent reputation can be deeply negative.** Rezkov `concord_won` is -1000.
   *Plan:* the Independent wing is a task chain, not a reputation gate.
6. **The Corsair ally may not exist.** `corsair_ally` is false on `failed`/`declined`, but
   Arc 6 needs `corsair_battlegroup_destroyed`, which only the `defended` path sets, so
   `corsair_ally` is always true when Arc 6 runs. The Corsair wing is always available.
7. **The Annex is destroyed when the Boneyard arc ends.** *Plan:* respawn it for Arc 6
   (export `_spawnAnnex`); drone flip is not required, since the Annex visit performs it.
8. **Drones are slow and the Core is ~145U from the Boneyard.** The Ashgrave wing needs
   warp. *Plan:* the Annex refit gives them a warp drive and a throttle to match Kael's
   impulse speed while escorting.
9. **No faction fits.** `Concord Hostile` is a targetable-law stand-in. *Plan:* the two
   new factions above, plus reputation aliasing. Stations stay `Concord` (the Imperials
   treat them as friendly); they flip to `Concord Republic` only on arrival, so
   `JOBS.stationFaction` and rep lookups keep working.
10. **The escort job is too small.** One convoy ship, two escorts, two waves, a single
    destination. *Plan:* a new arc-owned convoy with checkpoints, wing orders, scripted waves
    and a hard entity budget (stay under ~45 active `CpuShip`s; spawn by leg, retire
    beaten waves, two-surge spawns for leg 2).
11. **The Core is "safe" (danger 0, shakedowns only).** The arc makes it a war zone. *Plan:*
    suspend the Core/Arbiter PROX zones (`PROX.suspendZone`) for the whole arc; region
    danger is cosmetic and left alone.
12. **The Maw aftermath said the Concord "stops shaking down".** That holds on `liberation` but
    not `mercy`. *Plan:* Arc 6 finishes it in the world-after step.

---

## Cross-arc state contract

Flags any future arc may rely on (never rename these):

| Flag | Written by | Values |
|---|---|---|
| `rezkov_arc_done` | Rezkov | `concord_won` / `data_delivered` / `meridian_destroyed` / `meridian_escaped` |
| `kael_alive` | Rezkov | true / false |
| `rezkov_ai_planted` | Rezkov | true when the Galen hack installed the AI (Ledger briefing variant) |
| `ledger_arc_done`, `ledger_evidence` | Ledger | `full` / `lost`; bool |
| `boneyard_arc_done`, `boneyard_hack_done`, `boneyard_drone_flip`, `boneyard_battlegroup_destroyed` | Boneyard | bool |
| `corsair_arc_done`, `corsair_ally`, `corsair_battlegroup_destroyed` | Corsair | outcome string / bool / bool |
| `maw_warhead` | Maw | `fitted` / `spent` (read at player spawn to fit the EMP rack) |
| `maw_arc_done` | Maw | `liberation` / `mercy` / `quiet` |
| `republic_arc_done`, `republic_wings`, `republic_corsair`, `republic_ashgrave`, `republic_independent` | Republic | `ascendant` / `coalition`; count; bools |

SCIDB lock keys: `hollow_true_nature`, `ashgrave_research`, `synthesis_details`
(Boneyard); `maw_full` (Maw); `ledger_findings` (Ledger, built in `ee/ragtag/world/sciencedb.lua`); `kael_profile` (Rezkov M3, to be added) and
`republic_formed` (Republic, to be added).

Rumor categories: `<ARC>_HOOK` injected in hook enter / removed in hook exit;
`<ARC>_DONE` injected at resolve (persistent flavor for the session).

World-state readers (not arcs) that consume these flags: `VERSE` build and the
PROX zone table read `maw_arc_done` (dormant Maw, danger, Concord shakedowns);
`RT.spawnPlayer` (or a hook on it) reads `maw_warhead`.

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
  Friendly` (allied pirates), `Relic Active` (reprogrammed drones, anti-Concord), `Concord
  Surrendered` (a Concord post that gave up: nobody's enemy, so allies can board it)
  — all defined in `VERSE.setupFactions()`.
- **One-shot story weapons**: a flag read at player spawn, not an `RT.UPGRADES`
  entry (upgrades re-apply every session and show in the shipwright). Fit with
  `setWeaponStorageMax`/`setWeaponStorage`; revoke by setting the max to 0 the
  frame storage hits 0, so docking can't refill it. Missile types: Homing,
  Nuke, Mine, EMP, HVLI.
- **Arc-owned regions**: suspend the PROX zone, destroy the verse garrisons in
  the region on phase enter, and place the arc's own; restore nothing on
  resolve (the next session rebuilds the verse), but `on_cancel` must clean up
  what the arc spawned.
- Run `python tools/check.py` after every change; headless smoke test before
  calling an arc done.

## Decisions made (2026-11-10)

- The Maw arc hard-requires all three Phase II arcs; no in-Maw fallback.
- The finale's objective is one warhead into the rift, not a 90-second hold.
  The 90 seconds is the escape (`cascade`).
- Concord is absent from the climax; Kael (she/her) is a small staging beat and
  the follow-on lead.
- Corsair `failed`/`declined` costs the escort wing only; no hunters in the finale (2026-11-15: the betrayal branch was dropped).
- Fail state restarts from `staging`, never `hook`.
- Two arcs eligible at once is acceptable; no trigger staggering.
- The verse's Maw garrisons are cleared and replaced by the arc's own.

## Decisions made (2026-11-15)

- Corsair arc reworked: single hook (non-hostile raider hail on entering the Gauntlet), escort to
  Blackwater, Reva's briefing, a forward-depot raid with commandable Corsair escorts, and the
  battle. No betrayal branch: defend or decline. (The mine wall, its gap and corridor were replaced
  on 2026-11-18 by a thickened ring round Blackwater and a Battle Lab set piece.)
- Corsair arc: one prep mission (the raid); each raid escort lost is replaced from Blackwater; declining
  the final battle after the raid is `failed`, only a refused hook is `declined`.

## Decisions made (2026-11-13)

- **Arcs are linear.** One phase path; from a phase an arc goes to the next phase, to `done`
  with an outcome flag, or back to an earlier phase (failure restart). Decisions end the arc or
  continue it; variation lives inside phases as flags. Rule and engine warning: missions_api.md,
  "Linear arcs".
- Corsair arc: Defend is the single path (superseded 2026-11-15 by the Corsair design: no
  betrayal branch; defend or decline).
- Ledger arc built: rumor → Thresh → Rezkov → three fragments → power drain + audit fleet →
  Rezkov holds the ledger. The audit sweep and `partial` outcome were dropped.

## Decisions made (2026-11-12)

- Arc 6 (the Concord Republic) is an optional serial after the finale. It requires `liberation`
  or `mercy` and a living Kael; `quiet` ends the campaign.
- The two factions are `Concord Imperial` (loyalists, hostile) and `Concord Republic` (Kael's
  side, friendly); Republic reputation aliases Concord.
- The rally is three wings (Corsair, Ashgrave, Independent), at least two required. The
  Independent wing is a task chain, never a reputation check.
- The convoy is an arc-owned multi-leg escort, not the stock escort job.
- Kael's Science DB entry: Settlement War fighter who questioned her superiors, then a Concord
  special-operations investigator seeking the truth; unlocked at Rezkov M3.
- Fail restarts from the last station, with no penalty.

## Open questions / tuning

- Should the crew carry the Boneyard schematic to the Hob Works themselves (a beat at Hob's Landing
  before the finale), or does Thresh send it? Today's plan: Thresh brokers it, nothing to fly.

- ~~Arc 6, 1: Kael dead~~ — decided 2026-11-12: Arc 6 does not happen (no deputy).
- ~~Arc 6, 2: no Corsair ally~~ — decided 2026-11-12: Arc 6 requires both fleets destroyed,
  which implies the Corsair `defended` path, so the ally always exists.
- **Arc 6, 3: which station is the seat of government?** The plan uses Ostia Highport (the
  Core's largest port) as the final fight and Lumen Exchange (the trading floor, where the
  Magistrate sat) as the mid-route stop. Confirm.
- ~~Arc 6, 3: seat of government~~ — confirmed: Ostia Highport final, Lumen Exchange mid-route.
- ~~Arc 6, 4: Sentinel Fleet Yard~~ — decided 2026-11-12: no hack and no assault. The Imperial
  fleet is a finite pool; the crew exhausts it by destroying each wave. The escort itself is
  the challenge. Tune by wave size and Kael's hull, not by side objectives.

- ~~Boneyard trigger gate~~ — decided: gated on `rezkov_arc_done` (or `rezkov_declined`). Phase II arcs load ~10 vague seed rumors (priority 2) via `M.on_load` while waiting, and 3 actionable hooks (priority 5) once started.
- Rift anchor: confirm in a headless run that `hull.damaged_by_emp` and
  `onTakingDamage` behave as the source reads (callback fires on the EMP
  blast; beams and homings do nothing to it).
- Liberation kill threshold, anchor platform strength, wave sizes, and whether
  three anomaly scans is too slow for Science under fire — playtest numbers.
- Does the player template's tube accept EMP without `weaponTubeAllowMissle`?
  Verify on the actual `Flavia P.Falcon` template.
- Ledger arc: drain rate (3/s after the 2026-11-17 playtest; was 5), audit fleet delay (60 s) and size, and whether energy-zero
  should be instant loss — playtest numbers. (The audit sweep was dropped 2026-11-13.)
- Follow-on arc (Kael / normalisation): in scope for this campaign or a new one?
