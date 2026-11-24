# The Rezkov Arc — GM guide

The first story arc of The Drift (sandbox campaign, scenario 80). **Spoilers**: keep this away from
players. Module: `ee/ragtag/missions/rezkov.lua`. Back to the [GM guide](GM_GUIDE.md).

## Premise

A fixer at Dustmote Salvage wants an independent crew for "serious work". It starts as a quiet data
job and turns political: the Concord has been watching Dustmote, and the crew has to decide whether
to cooperate with a Concord investigator or protect the people who hired them.

Where it sits in the campaign:

- **It is the gate.** Every Phase II arc (Ledger, Boneyard, Corsair) waits until Rezkov is finished or
  declined. It establishes the crew as serious independent operators.
- **It plants the Ledger arc.** The "traffic log" hack at Waypoint Galen secretly installs a rogue AI
  in the Concord's accounting systems ("Rogue AI successfully installed…" in the ship log). Months
  later that AI finds the Concord's twenty-year black budget, and the Ledger arc is the crew carrying
  it out.
- **It introduces the cast the finale needs.** **Thresh** (Dustmote, the go-between for later hooks),
  **Orlan Rezkov** (who will hold the Containment Ledger until it can't be buried) and **Commander
  Kael** of Concord Intelligence (she/her). Kael is written as a Concord officer who turns out to be a
  force for good: if she lives, Rezkov later tells the crew she buried the Audit Service's report on
  them, and she is the natural lead for the Concord's eventual fracture. Only destroying the Meridian
  kills her.
- **It sets the crew's standing with the Concord.** Most outcomes cost 1,000 Concord standing, enough
  to turn Concord patrols hostile. That is the backdrop for the Ledger arc, which sends the crew into
  Concord space under its own reputation.

## Triggers

- Independent standing **≥ 500** and **≥ 600 cr** of upgrades on the primary ship (the Magpie).
- Not declined (`rezkov_declined`) and not finished (`rezkov_arc_done`).
- Auto-starts. Before the trigger, eight vague seed rumors about Dustmote mix into the rumor pool
  (`REZKOV_SEED`); none of them name Rezkov.
- **Concord standing ≥ 0** is needed to accept Rezkov's first job ("Not yet. The patrols are watching
  you."). The arc waits; the crew can come back.

Arc work is for the primary ship only: other ships never see its hails, rumors or jobs.

## Phases

```
hook ─► m1_navigate ─► m2_active ─► m2_deliver ─► m3_active ─┬─► done (Concord / Destroyed / Escaped)
                                                              └─► m3_deliver ─► done (Data)
```

### Hook (Rumors)

Three hook rumors name Dustmote Salvage ("a contact at Dustmote… looking for independent crews"). No
objective: the rumors are the only lead. Docked at Dustmote, the crew's reply **"Heard you were
looking for an independent operator."** brings Thresh (his Science DB profile is added). He offers a
meeting: "Head out at bearing 15. You'll hit a nebula cloud."

- **We'll head out** → objective "Find the waypoint".
- **Not right now** → the offer stays open.
- **Not interested** → the arc is declined for good (`rezkov_declined = "player_declined"`). Phase II
  still opens: declining counts as "over".

### M1: the meeting (Meeting)

Rezkov's station (a tumbling "Defense platform", faction Unknown, indestructible) sits in a ring of
seven nebulae at about (115, −72), bearing 15 from Dustmote. He only talks to a **docked** ship.
Rezkov introduces himself (profile added) and wants Waypoint Galen's 90-day traffic log ("I need to
know if someone in my organization is talking"). Accepting with Concord standing below 0 is refused.

### M2: the hack (Hacking)

Objective "Hack Waypoint Galen". Concord Waypoint Galen is at (−75, −52) on the Arbiter Line. Relay
hacks Galen's **front shield** until Relay's hacking screen shows it **100% hacked** (two successful hacks in a row; it
decays over 180 s). The ship log then says the AI was installed, and four seconds later that the
traffic is on the storage card. Objective "Card to Thresh".

**Cover jobs.** Rezkov says "pick up some jobs along the way". While M2 is active, docking at Halcyon
Rest, Port Vesper, Calder's Reach or Concord Station Arbiter adds an ordinary delivery to Galen to
that station's board (normal pay, no `[SPECIAL]` tag). They are meant to read as a lucky break.

### M2 delivery (Card run)

Docked at Dustmote: **"Delivery for Thresh."** He pays **600 cr**, takes an urgent call, and Rezkov's
station goes dark (it is removed). Thresh comes back with the twist: the Concord monitoring ship
**CWS Meridian** has three months of intercepts on all of them and is burning for Concord space. No
pay for this one.

- **We're on it** → objective "Board CWS Meridian".
- **Not right now** → the Meridian is already flying; Thresh re-offers it ("Thresh -- that Concord
  ship.") on the next docking. The clock runs either way.

### M3: the intercept (Intercept)

The Meridian (Phobos T3, no nukes, impulse 200) starts at about (110, −55) and flies for Concord
Station Arbiter (−21, −27). It is neutral `Concord` until the crew comes within **5U**, then turns
`Concord Hostile` (targetable) and hails with a threat. It is **disabled** at hull < 25% or impulse
health < 30%: it stops, turns Independent, can no longer be destroyed, and hails "You got us. We give
up…". Objective: dock with it (within 1U).

Docked, the crew hails **Commander Kael** (profile added). Her offer:
- **Let the Concord go.** → she flies on to Arbiter; ends **Concord**.
- **Wipe the data.** → "Until we meet again, Magpie." → M3 delivery.

Other endings while M3 is running:
- **The Meridian is destroyed** before it is disabled → ends **Destroyed** (Kael dies).
- **The Meridian gets within 10U of Arbiter** undisabled → ends **Escaped**.

### M3 delivery (Data run)

Objective "Report to Thresh". Docked at Dustmote: **"Thresh -- the Meridian data is wiped."** Thresh
says to lay low; ends **Data**.

### Done

"Rezkov Arc complete." on every screen. The Meridian is removed 90 s later, wherever it is.

## GM console

**Missions… → Rezkov Arc** shows the state, the trigger criteria and these buttons:

| Button | Effect |
|---|---|
| `→ Inactive` | Suppress the arc (`rezkov_declined = "gm_inactivated"`): no hook, no trigger |
| `→ Rumors` | The hook phase |
| `→ Meeting` | M1: Rezkov's station is out; Thresh already met |
| `→ Hacking` | M2: the Galen hack |
| `→ Card run` | M2 delivery: the hack is done, deliver to Thresh |
| `→ Intercept` | M3: the Meridian spawns and flies |
| `→ Data run` | M3 delivery: data wiped, report to Thresh |
| `→ Done: Concord` / `Data` / `Destroyed` / `Escaped` | End the arc with that outcome |

Helpers, shown only in their phase:
- **Travel shortcuts** (put the Magpie 5U away, undocked and stopped): **Ship → Dustmote** (rumors,
  card run, data run), **Ship → Rezkov** (meeting), **Ship → Galen** (hacking), **Ship → Meridian**
  (intercept; 5U is the Meridian's hostility range).
- **Complete hack** (M2): sets Galen's front shield fully hacked; the phase finishes normally.
- **Disable Meridian** (M3): drops its hull to 10%, so it is disabled and hails.

Every jump resets the arc first: Rezkov's station and nebulae, the Meridian, Galen's hack level,
pending timers, cover jobs, hook rumors, the arc's objective and the `rezkov_*` / `kael_*` flags. It then
replays what the earlier phases leave behind (flags, the Thresh / Rezkov / Kael profiles, Rezkov's
station going dark after the card run). **Reputation and credits are not applied by a jump**, and
those already given are not taken back. The two end states where the crew never met Kael (Destroyed,
Escaped) don't add her profile.

## Exports

| Outcome (`rezkov_arc_done`) | How | Concord | Independent | `kael_alive` |
|---|---|---|---|---|
| `concord_won` | "Let the Concord go." | +500 | −1000 | true |
| `data_delivered` | Wipe the data, report to Thresh | −1000 (at the wipe) | +200 (at the report) | true |
| `meridian_destroyed` | Meridian destroyed before disabled | −1000 | +200 | **false** |
| `meridian_escaped` | Meridian reached Arbiter | −1000 | −500 | true |

Plus **600 cr** at the card delivery, whatever follows.

Flags other arcs read:
- `rezkov_arc_done` (any value) or `rezkov_declined`: opens the Ledger, Boneyard and Corsair arcs.
- `rezkov_ai_planted`: set when the Galen hack lands. The Ledger briefing says "the card you carried
  had a second payload" instead of "I had a crew put a program…".
- `kael_alive`: the Ledger hand-over's line about Kael; Kael's role in the finale and after.

Science DB: profiles of Thresh, Orlan Rezkov and Commander Kael, added as the crew meets them.

## Design notes

### State (in memory, `st.*`)

| Field | Meaning |
|---|---|
| `st.waypoint` | Rezkov's station |
| `st.nebulas` | the seven nebulae round it (removed with it) |
| `st.galen` | Concord Waypoint Galen (the hack target) |
| `st.hack_done` | the Galen hack landed |
| `st.cover_given` | cover-job stations already used this M2 |
| `st.meridian` | CWS Meridian |
| `st.m3_hostile` / `st.m3_disabled` / `st.m3_boarded` | the Meridian's progress |

### Saved flags

| Flag | Meaning |
|---|---|
| `rezkov_hook` | the crew took Thresh's meeting |
| `rezkov_declined` | `"player_declined"` (told Thresh no) or `"gm_inactivated"` (GM `→ Inactive`) |
| `rezkov_m1_done` | Rezkov's job accepted |
| `rezkov_ai_planted` | the Galen hack landed |
| `rezkov_m2_done` | the card was delivered |
| `rezkov_m3_accepted` | the crew took the intercept |
| `rezkov_m3_data` | the data was wiped (M3 delivery) |
| `rezkov_arc_done` | the outcome (table above) |

Clear flags with `RT.clearFlag(name)`: `RT.flag(name, nil)` is a read, not a clear. On load, `init`
routes to the right phase from these flags.

### The Meridian's factions

`Concord` on spawn (so it ignores traffic) → `Concord Hostile` within 5U of the crew (targetable; no
automatic standing penalty, the arc applies its own) → `Independent` once disabled (dockable: a
docking bay is added for Frigate-class ships) → `Concord` again if let go. Its hails retry once after
15 s and fall back to the ship log if comms are busy.

### Hack threshold

EE decays every `hacked_level` by 1/180 per second before scripts run, so a finished hack reads just
under 1.0 when the arc checks it. The arc completes at `>= 0.99` (the Boneyard's Annex hack uses the
same threshold).

### Rumors

- `REZKOV_SEED` (priority 3): loaded while the arc waits (`M.on_load` / `M.on_unload`).
- `REZKOV_HOOK` (priority 5): added in the hook phase, removed on its exit. They are the only way to
  find Thresh; no job or objective replaces them.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/rezkov` (`tests/arcs/rezkov.lua`). Not covered headless: a
real fight with the Meridian, and the Escaped ending in a real game.
