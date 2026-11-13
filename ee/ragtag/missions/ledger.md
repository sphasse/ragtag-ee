# Ledger Arc — design notes

Phase II arc of the sandbox campaign (`ee/ragtag/missions/ledger.lua`). Runs in parallel with
the Boneyard arc. Campaign context: `scenarios/sandbox/plan.md`, Arc 2.

## Premise

The Rezkov arc's Galen hack ("Rogue AI successfully installed in the Concord accounting
systems") planted a program in the Concord books. It has finished reading them: an account
that has not closed in twenty years pays for "Maw containment" and "Ashgrave remediation",
and every transfer is signed. It cannot leave over Concord comms, so it split itself into
three fragments and went dark inside Concord space. The crew carries it out.

The challenge is navigation, not combat: Concord space with Concord hostile (from the crew's
own reputation; the arc does not override it). Science watches and scans, Helm stays off the
patrol lanes, and at the end Engineering keeps the reactor alive under a heavy drain while a
three-ship audit fleet blocks the way out.

## Trigger

`upgrades_min = 800`, Rezkov arc finished (any outcome) **or declined**, `ledger_arc_done`
not set. Auto-starts; no hail, no job, so it competes quietly with the other Phase II leads.

## Phases

```
init ─► hook ─► meet ─► relay_run ─► carry ─► done (full | lost)
```

| Phase | What happens | Leaves |
|---|---|---|
| `hook` | Priority-5 rumors (`LEDGER_HOOK`): "A guy at Dustmote was asking about you", etc. Docked at Dustmote: "Heard someone here was asking about us." Thresh: the big guy wants to see you in person, same place (bearing 15 directions if the crew never met Rezkov). | `ledger_thresh` |
| `meet` | Rezkov's station is back in the nebula (~115, −72). Docked: the real briefing, then fragment grid refs. Accept. | `ledger_accepted` |
| `relay_run` | Three `Artifact` data cores (`allowPickup`): near Valcourt (−172, −70), near Ostia (−128, −120), near Waypoint Galen (−80, −62). Flying into one picks it up. Objective counts 0/3. | `ledger_frag_1..3` |
| `carry` | The AI hails (RT.voice "Unidentified Signal"): thank you, sorry about the power, keep energy above zero. Drain 5 energy/s (the Witness pod's rate); Engineering info line "Unknown process". 60 s later the Concord Audit Service fleet (CAS Double Entry, Phobos T3; CAS Debit and CAS Credit, Adder MK5) spawns 7U ahead in a 35° arc, Concord Hostile, attacking, and hails: transmit the data for reconciliation. Ships > 25U away despawn (lost the crew). Each audit ship drops a warp jammer behind the crew when within 5U (`PROX.tickCombatJammers`: one at a time, 2 min life, 2 min cooldown, 10 hull = two beam hits). | — |
| `done` | Dock at Rezkov's station → "Hand over the AI" → `full`. Energy at 0 → `lost` (`lost_reason = power`). "Transmit the data." to the fleet → `lost` (`surrender`). | `ledger_arc_done` |

Docking at an independent station recharges the reactor, which is how a crew survives the
long haul from the Core to the nebula.

### Briefing variant

`rezkov_ai_planted` (set by the Rezkov arc when the Galen hack lands; `rezkov_m2_done` counts
too, for saves from before the flag existed): "The card you carried had a second payload."
Otherwise (the crew declined Rezkov): "I had a crew put a program into the Concord accounting
system at Waypoint Galen." The rest of the arc is identical.

### Rezkov holds it

Rezkov does not broadcast the ledger: "Put it out today and they bury it by the end of the
week. I will release it when it cannot be buried." The Maw finale's aftermath is where it goes
public.

## Exports

| Flag | Values |
|---|---|
| `ledger_arc_done` | `"full"` / `"lost"` |
| `ledger_lost_reason` | `"power"` / `"surrender"` |
| `ledger_evidence` | true on `full` (Maw finale input) |
| `ledger_rewarded` | pay-once guard |

Rewards (once): `full` → 600 cr, Concord −200, Independent +200; `lost` → nothing.
Science DB: Lore "The Containment Ledger" (lock key `ledger_findings`, built in
`sciencedb.lua`), unlocked on `full` and re-unlocked from `on_load` each later session. It
names the signatories the finale needs: Deputy Treasury Secretary Aurelian Voss, Rear Admiral
Corin Hale (Fleet Logistics), Director Mireille Tan (Applied Research Division), and the
Council's Standing Committee on Security.

## GM console

`→ Hook`, `→ Meet Rezkov`, `→ Relay run`, `→ Carry AI`, `→ Done: Full`, `→ Done: Lost`
(plus the engine's `→ Inactive`). Jumps reset the world (station, nebula, cores, fleet, drain,
voice, rumors, `ledger` objective, `ledger_*` flags) and replay earlier phases via
`M.completed`. Helpers: `Give fragment` (relay_run); `Fleet now`, `Pause/Resume drain`,
`Refill energy` (carry).

## Tuning (top of `ledger.lua`)

`_DRAIN_PER_S` 5, `_FLEET_DELAY` 60 s, `_FLEET_DIST` 7U, `_FLEET_SPREAD` 35°,
`_LOSE_FLEET_R` 25U. Playtest: whether energy-zero should be instant loss (currently instant),
and whether three audit ships are enough of a wall.
