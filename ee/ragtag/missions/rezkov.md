# Rezkov Arc — design notes

Three-mission story arc. Trigger: upgrades_min threshold + `rezkov_hook` not set + `arc_done` not
set. Module: `ee/ragtag/missions/rezkov.lua`.

---

## Arc overview

A series of jobs funneled through a Dustmote contact (Rezkov). The crew progressively uncovers
that a Concord ship — CWS Meridian — is carrying stolen colony data. M3 offers a moral choice
with lasting reputation consequences.

---

## Phases

| Phase | Description |
|---|---|
| `hook` | Rumors spread at stations; crew hails Dustmote to get the first job offer |
| `m1_navigate` | Navigate to a nav beacon and report back |
| `m2_active` | Hack a comms relay beacon; collect data package |
| `m2_deliver` | Deliver package to Rezkov's drop |
| `m3_active` | CWS Meridian is en route to Concord space; intercept and board; Kael comms offer |
| `m3_deliver` | Report data wipe to Thresh at Dustmote |

All phases have `no_skip = true` (GM uses the `→` buttons from `gm_states`: Inactive, Rumors, Meeting, Hacking, Intercept, Data run, and one `→ Done:` per outcome).

---

## State machine (in-memory, `st.*`)

| Field | Type | Description |
|---|---|---|
| `st.meridian` | entity | CWS Meridian ship (spawned M3) |
| `st.galen` | entity | Concord Waypoint Galen station ref |
| `st.hack_done` | bool | M2 hack threshold reached |
| `st.m3_hostile` | bool | Meridian switched to Concord Ops faction |
| `st.m3_disabled` | bool | Meridian has been disabled |
| `st.m3_boarded` | bool | Boarding success registered (Kael comms set up) |
| `st.nebulas` | list | Nebulas spawned for waypoint; despawned on phase exit |

---

## Persistent flags (`RT.flag / RT.clearFlag`)

| Flag | Value | Meaning |
|---|---|---|
| `rezkov_hook` | truthy | Arc has been triggered/seen |
| `rezkov_declined` | `"player_declined"` | Player refused the hook job at Dustmote |
| `rezkov_declined` | `"gm_inactivated"` | GM manually inactivated the arc |
| `rezkov_m1_done` | truthy | M1 complete |
| `rezkov_m2_done` | truthy | M2 complete |
| `rezkov_m3_accepted` | truthy | Player accepted M3 |
| `rezkov_m3_data` | `true` | Set when crew wipes Meridian's data; triggers m3_deliver Thresh hook |
| `rezkov_arc_done` | truthy | Full arc finished |

**Always use `RT.clearFlag(name)`** to clear these — `RT.flag(name, nil)` is a read, not a clear.

---

## M3 outcome and reputation consequences

| Outcome | Concord | Independent |
|---|---|---|
| Destroy CWS Meridian | −1000 | +200 |
| Let Concord go with data (Kael comms) | +500 | −1000 |
| Wipe data, report to Thresh | −1000 | +200 |
| Meridian reaches Concord space (player fails) | −1000 | −500 |

---

## CWS Meridian

- Template: `Phobos T3` (standard NPC frigate — not a playership-typed template)
- Spawned at M3 start; flies toward Concord Station Arbiter at high impulse
- **Faction lifecycle**: `Concord` (neutral on spawn) → `Concord Ops` (hostile, targetable) when
  player closes within 5U → `Independent` (after disabled) → `Concord` again if player lets her go
- `setCanBeDestroyed(false)` once disabled, re-enabled on destroy/arc-end
- Despawns 90s after `M.resolve` fires (covers all outcomes)
- **Kael comms** (after boarding): player chooses between letting Concord proceed (+500 Concord,
  −1000 Independent) or wiping the data (−1000 Concord, arc moves to `m3_deliver`)

---

## GM controls

The arc exposes these GM buttons in the MISSIONS detail panel:

| Button | Visible when | Effect |
|---|---|---|
| `State: <label>` | always (incl. done) | Info display only |
| `→ Hook` | active | Clear state, jump to hook phase |
| `→ Inactive` | active | Set `rezkov_declined = "gm_inactivated"`, jump to hook |
| `→ M1` | active | Clear state, jump to m1_navigate |
| `→ M2` | active | Clear state, jump to m2_active |
| `→ M3: Intercept` | active | Clear state, spawn Meridian, jump to m3_active |
| `→ Complete` | active | Clear state, mark arc done |
| `Restart arc` | done | Full clear + `MISSIONS.start("rezkov")` |

`→ Inactive` sets `rezkov_declined = "gm_inactivated"` (distinct from `"player_declined"` set
when players refuse the hook at Dustmote). The state label shows which.

---

## Rumor system

Rumors for this arc use category `REZKOV_HOOK`. They are added in `hook.enter` and removed by
`_gmClearFlags`. The hook phase checks `RT.flag("rezkov_declined")` on entry and skips rumor
injection if the arc has been inactivated.

## Rumors and jobs: seeds and hooks

- **Waiting seeds** (`REZKOV_SEED`, priority 3, via `M.on_load`/`M.on_unload`): eight vague
  Dustmote-adjacent rumors that never name Rezkov, loaded before the trigger fires.
- **Hook rumors** (`REZKOV_HOOK`, priority 5): name Dustmote. These are integral, not cosmetic:
  the rumors are how crews find Thresh, and no job or objective replaces them.
- **M2 cover jobs** (`REZKOV_COVER`, injected in `m2_active.enter`, removed in its `exit`):
  Rezkov says "pick up some jobs along the way to get you closer", so Halcyon Rest, Port Vesper,
  Calder's Reach and Arbiter each get an ordinary delivery to Concord Waypoint Galen
  (`JOBS.inject{priority=3, ensure=true}`), generated the first time the crew opens the board at
  that station while M2 is active. Deliberately not special: normal rewards, no `[SPECIAL]` tag,
  no story rules. They just read as a lucky break. No jobs are seeded for the Dustmote leg.

## GM jumps

Every `→` button goes through `MISSIONS.gmJump`: `M.gm_reset` wipes the station, nebula, Meridian, Galen's hack level, pending timers, cover jobs, rumors, objective, state and `rezkov_*`/`kael_*` flags (the `*_profile_known` flags stay); then `M.completed` replays the lasting effects of each earlier phase (flags, Thresh/Rezkov/Kael DB profiles, Rezkov's station going dark after the card is delivered); then the target phase enters. End states (`→ Done: …`) set the outcome flags and `kael_alive`; the two outcomes where the crew never met Kael skip her profile. Reputation and credits are not applied by a jump.
