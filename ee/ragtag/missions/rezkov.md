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
| `m3_active` | CWS Meridian is en route to Concord space; intercept and board |
| `m3_deliver` | Deliver seized data to Thresh; or let Meridian go |

All phases have `no_skip = true` (GM must use the explicit skip buttons in `gm_actions`).

---

## State machine (in-memory, `st.*`)

| Field | Type | Description |
|---|---|---|
| `st.meridian` | entity | CWS Meridian ship (spawned M3) |
| `st.galen` | entity | Concord Waypoint Galen station ref |
| `st.hack_done` | bool | M2 hack threshold reached |
| `st.m3_disabled` | bool | Meridian has been disabled |
| `st.m3_boarded` | bool | Boarding success registered |
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
| `rezkov_m3_data` | string | Outcome choice: `"destroyed"` / `"seized"` / `"escaped"` |
| `rezkov_arc_done` | truthy | Full arc finished |

**Always use `RT.clearFlag(name)`** to clear these — `RT.flag(name, nil)` is a read, not a clear.

---

## M3 outcome and reputation consequences

| Outcome | Concord | Independent |
|---|---|---|
| Destroy CWS Meridian | −1000 | +200 |
| Let Concord go with data | +500 | −1000 |
| Seize data, deliver to Thresh | −1000 | +200 |
| Meridian reaches Concord space (player fails) | −1000 | −500 |

---

## CWS Meridian

- Spawned at mission start in M3; flies toward Concord space (`orderFlyTowards(galen)`)
- Faction: Independent (until player within 8U → switches to Corsairs, attacks)
- `setCanBeDestroyed(false)` while boarding in progress
- Kill handler registered via `RT.trackShipForReputation("Concord", ship)` — callsign must be
  captured at registration time (`local cs = ship:getCallSign()`) because components are stripped
  at kill time

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
