# Ice Haul — GM guide

Module: `ee/ragtag/missions/icehaul.lua` (id `icehaul`). Test: `tests/arcs/icehaul.lua`.

## Premise

Two of the three water reclaimers at Hob's Landing are down and the parts are a month out; the
Landing is rationing. A comet broke up passing Kestrel last week, and its biggest piece, about forty
thousand tonnes of ice, is drifting round the sun. The Landing's water office fits the crew with a
tow rig and pays them to bring it home.

Where it sits in the campaign:

- **A short one-off money job**: 1,500 cr for the tow. It can come at any time after Rezkov.
- **No resistance**: the job is the tow itself. The ice drifts in the Rim, where nothing patrols.
- **It tries out the tow line** (the engine's orbit component: `setOrbit(ship, 0)`), which could later
  become a job type of its own (salvage tows, a lifeboat, an iceberg chased by raiders).

## Triggers

- **Rezkov over** (`rezkov_arc_done`, or `rezkov_declined`). No upgrade threshold.
- It starts on its own (`auto_start`), in the hook phase.

## Phases

```
hook ─► haul ─► done (delivered | lost)
```

### Hook

**Seed rumor** at Independent ports (priority 3): "Hob's Landing is paying for ice. A comet broke up
passing Kestrel, and the Landing's reclaimers are failing. Nobody out here owns a tow rig, but they'll
fit you one." Hearing it sets the objective **"Hob's Landing"**.

Docked at **Hob's Landing**, **"[SPECIAL] The water office"** opens two pages:
1. The rationing, the comet, where the ice is (a sector name), "Tow it here, within 4U of the Landing,
   and our tugs take it from there. 1,500 credits."
2. **How do we tow it?**: "Get within 2U of the ice and your engineer makes it fast. It'll slow you
   down, and don't touch the warp drive with the line on: it snaps, and you go back for the ice."

**We'll fetch it.** goes to Haul; **Not right now.** leaves the offer open.

### Haul

Objective **"Pick up the ice"**; the Science DB gets **Lore > The Kestrel ice** (the job, where the ice
is, how the tow works).

- **Kestrel Ice** (a big asteroid, pale blue on radar; it doesn't explode on touch) drifts round the
  gold sun Kestrel, 16U out, starting west of it (about 19U east of Hob's Landing). It goes round once
  an hour, about 1.7U a minute, clockwise on the map (north-west at first).
- Within **2U** of it, **Engineering** (and Single Pilot) gets an **"Attach tow line"** button. Pressed:
  the ice hangs **1.5U** behind the ship on the line and follows it; impulse drops to **75%**.
  Objective **"Tow it to Hob's"**.
- While towing, the button reads **"Release tow line"**: the ice stays where it is (out of its orbit
  for good). Objective back to "Pick up the ice".
- **Spinning up the warp drive snaps the line**: "The tow line snapped when the warp drive spun up. The
  ice is adrift: go back for it." No other cost.
- **The ice within 4U of Hob's Landing**: the water office hails: "We have it. Tugs are on their way out
  to take it in... 1,500 credits, and the Landing drinks this month." **1,500 cr, Independent +75**.
  Outcome `delivered`. The ice is taken in (removed) 20 seconds later.
- **The Magpie lost** while hauling: outcome `lost` (nothing paid).

## GM console

**Missions… → Ice Haul**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ Hook` | The seed rumor again; not briefed |
| `→ Haul` | Briefed; the ice back at its start |
| `→ Done: Delivered` / `→ Done: Lost` | End states (no payment) |

Helpers, shown only in their phase:
- **Ship → Hob's** (hook): the Magpie 5U from Hob's Landing.
- **Ship → Ice** (haul): the Magpie 5U from the ice.
- **Attach the line** (haul): ties the ice on, pulling it to the ship first if it is out of reach.

The state line reads e.g. "Adrift, 19U" or "Towing, 7U" (the ice's distance from Hob's Landing).

A jump resets the arc (the ice, the line, the impulse, the rumor, the objective, the `icehaul_*`
flags). After a session ends mid-haul, the next session puts the ice back at its start, untied.

## Exports

| Flag | Values |
|---|---|
| `icehaul_arc_done` | `"delivered"` / `"lost"` |

Standing: Independent +75 when delivered. Science DB: Lore → **"The Kestrel ice"**.

News (`missions/_aftermath.lua`, category `ICEHAUL_DONE`, told once): "Hob's Landing lifted the water
rationing. Somebody towed in a whole chunk of the Kestrel comet, and the Landing's drinking it."

Achievement (hidden): **Water Bearer** (delivered).

## Design notes

### State (`st.*`)

`berg` (the ice), `towing`, `tow_ship` (the ship it is tied to). Each ship's own impulse is kept
outside the state (by entity) while it tows, so a jump or a restart never notes the slowed value.

### Saved flags

`icehaul_briefed`, `icehaul_rewarded`, `icehaul_arc_done`.

### Engine notes

- **The tow line** is the engine's orbit component with period 0 (`setOrbit(ship, 0)`, here set as
  `components.orbit = {target, center, distance = TOW_LENGTH, time = 0}`). Every frame the engine puts
  the ice TOW_LENGTH from the ship along its current bearing, so it trails behind like a rope; it
  moves the ice directly, so nothing knocks it off the line. Removing the component lets it go.
- **The drift round Kestrel** is the same component with a fixed centre and a period.
- **The ice** is an `Asteroid` with `explode_on_touch` and `avoid_object` removed, size 400, a pale blue
  radar trace and a description. Its physics is a sensor: it never pushes the ship.
- **Warp**: the Light Freighter has a warp drive and no jump drive; the line snaps when
  `warp_drive.current` is above 0.
- **The button**: custom buttons on `engineering`, `engineering+` and `singlepilot`, redrawn only when
  the label changes (`M.towPressed` is what they call; the test presses it directly).

### Tuning (top of `icehaul.lua`)

`PAY` 1,500, `REP` 75, `TOW_REACH` 2U, `TOW_LENGTH` 1.5U, `TOW_DRAG` 0.75, `DELIVER_R` 4U,
`KESTREL`, `ORBIT_R` 16U, `ORBIT_START` 160°, `ORBIT_PERIOD` 3,600 s.

### Open for playtest

- Does the tow feel like towing? Line length, the 75% impulse, turning with the ice behind.
- Is the warp rule clear, and is a snap annoying or fun?
- Is the ice easy to find (a sector name, pale blue on radar)?
- 1,500 cr for a job with no fight: about right?
- Later: a tow job type (salvage hulks, lifeboats), raiders cutting the line.

### History

- 2026-11-24: built as a short, unopposed job to try out the tow line.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/icehaul` (`tests/arcs/icehaul.lua`) covers the gate, the
seed rumor (it sets the objective), the two pages, the ice drifting round Kestrel, the button only
within reach, attaching (the line, the slower impulse), the ice following a moved ship, casting off,
warp snapping the line, the delivery and its pay and standing, the news, the achievement, the ice taken
in, the Magpie lost, every GM state (with next-session routing) and "-> Inactive". The tow line
behind a ship flying on impulse is in `tests/core/orbit.lua`. Not covered: flying the tow by hand.
