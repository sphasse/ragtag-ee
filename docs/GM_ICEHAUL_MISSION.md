# Ice Haul — GM guide

Module: `ee/ragtag/missions/icehaul.lua` (id `icehaul`). Test: `tests/arcs/icehaul.lua`.

## Premise

Two of the three water reclaimers at Hob's Landing are down and the parts are a month out; the
Landing is rationing. A comet broke up passing Kestrel last week, and its biggest piece, about forty
thousand tonnes of ice, is drifting round the sun. The Landing's water office fits the crew with a
tow rig and pays them to bring it home.

Where it sits in the campaign:

- **A short one-off money job**: 2,000 cr for the tow. It can come at any time after Rezkov.
- **Two raiders**: the ice drifts in the Rim, where nothing patrols, but the first time the line goes on
  two Shroud Raiders posing as rival recovery outfits come for it (the same intercept as the tow job's).
- **It tries out the tow line** (the engine's orbit component: `setOrbit(ship, 0)`), which could later
  became the tow job on the board (`jobs/tow.lua`).

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
   and our tugs take it from there. 2,000 credits."
2. **How do we tow it?**: "Get within 2U of the ice and your engineer makes it fast. Hauling it eats
   power, and the line takes half of warp 1, 15U a minute, no more: warp 1 with your warp drive at half
   power, about. Have your science officer watch the speed. Any faster and it snaps, and you go back
   for the ice." "And watch yourselves. Every scavenger in the Rim saw that comet break up. Once the
   ice is on your line, somebody's going to want it."

**We'll fetch it.** goes to Haul; **Not right now.** leaves the offer open.

### Haul

Objective **"Pick up the ice"**; the Science DB gets **Mission Briefings > The Kestrel ice** (the job, where the ice
is, how the tow works).

- **Kestrel Ice** (a big asteroid, pale blue on radar; it doesn't explode on touch) drifts round the
  gold sun Kestrel, 16U out, starting west of it (about 19U east of Hob's Landing). It goes round once
  an hour, about 1.7U a minute, clockwise on the map (north-west at first).
- Within **2U** of it, **Engineering** (and Single Pilot) gets an **"Attach tow line"** button. Pressed:
  the ice hangs **1.5U** behind the ship on the line and follows it. Speed is unchanged, but hauling
  it costs energy: up to **3 energy a second** on top of the engines, at full impulse or at warp (less
  at part throttle, nothing stopped). Engineering sees "Tow load: up to -3 energy/s".
  Objective **"Tow it to Hob's"**.
- **The raiders** (`TOW.intercept`), the first time the line goes on (once a session): two Shroud Raiders
  with recovery-outfit names ("Jake's Towing & Salvage", "Interspace AAA", ...; an Adder MK5 and an MT52
  Hornet) appear **10U** from the Magpie on a random bearing. The log: "[Science] Contacts closing fast,
  10U out: <name> and friends. They're coming for the tow." Their leader hails: "That's a lot of ice for
  one little freighter. Here's how this goes: you cut it loose, we tow it somewhere that pays better than
  Hob's, and you fly home with all your paint..." They attack at once, at **18U a minute** (20% over the
  line's limit), so the tow can't outrun them: fight, or cast off and fight. Casting off and back on
  brings no more.
- While towing, the button reads **"Release tow line"**: the ice stays where it is (out of its orbit
  for good). Objective back to "Pick up the ice".
- **Half of warp 1 is the line's limit**: the ship may tow at up to **15U a minute** (250 units/s).
  Stock warp 1 is twice that, so the crew tows at warp 1 with **Engineering's warp power at about 50%**,
  while **Science** watches **"Tow speed: 14.2 of 15 U/min"** on its screen (also Operations and Single
  Pilot). Anything faster snaps the line: "The tow line snapped: faster than half of warp 1, 15U a
  minute, is more than it can take. The ice is adrift: go back for it." No other cost.
- **The ice within 4U of Hob's Landing**: the water office hails: "We have it. Tugs are on their way out
  to take it in... 2,000 credits, and the Landing drinks this month." **2,000 cr, Independent +75**.
  Outcome `delivered`. Any raiders left break off and fly away. The ice (and the raiders) are taken in
  (removed) 20 seconds later.
- **The Magpie lost** while hauling: outcome `lost` (nothing paid; the raiders are removed).

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

Standing: Independent +75 when delivered. Science DB: Mission Briefings → **"The Kestrel ice"**.

News (`missions/_aftermath.lua`, category `ICEHAUL_DONE`, told once): "Hob's Landing lifted the water
rationing. Somebody towed in a whole chunk of the Kestrel comet, and the Landing's drinking it."

Achievement (hidden): **Water Bearer** (delivered).

## Design notes

### State (`st.*`)

`berg` (the ice), `towing`, `tow_ship` (the ship it is tied to), `raided` (the raiders came), `raiders` (their ships).

### Saved flags

`icehaul_briefed`, `icehaul_rewarded`, `icehaul_arc_done`.

### Engine notes

- **The tow line** is `TOW` (`ee/ragtag/tow.lua`), shared with the tow job on the board: the arc offers the
  ice to the arc ship (`TOW.offer`) and follows the line through its callbacks. It is the engine's orbit component with period 0 (`setOrbit(ship, 0)`, here set as
  `components.orbit = {target, center, distance = TOW_LENGTH, time = 0}`). Every frame the engine puts
  the ice TOW_LENGTH from the ship along its current bearing, so it trails behind like a rope; it
  moves the ice directly, so nothing knocks it off the line. Removing the component lets it go.
- **The visible line** is a beam (`beam_effect`, the engine's weapons-fire effect) from the ship to the ice, pale
  blue, held lit while towing (`fade_speed` 0) and fading out when it lets go. Shown on the main screen and on radar.
- **The drift round Kestrel** is the same component with a fixed centre and a period.
- **The ice** is an `Asteroid` with `explode_on_touch` and `avoid_object` removed, size 400, a pale blue
  radar trace and a description. Its physics is a sensor: it never pushes the ship.
- **Warp**: the Light Freighter has a warp drive (500 world units/s a level) and no jump drive. The line
  snaps on the ship's **speed** (`getVelocity`) above `TOW_MAX_SPEED` (250, half of stock warp 1) × `TOW_SLACK`
  (1.02), not on the warp level: the engine's warp speed is level × 500 × the drive's effectiveness, so
  the warp drive's power sets warp 1's speed: about 50% power gives 250. (A player ship's power follows
  Engineering's slider, the power request: a script setting `power_level` alone drifts back.)
- **The button**: custom buttons on `engineering`, `engineering+` and `singlepilot`, redrawn only when
  the label changes (`TOW.press`; the arc's `M.towPressed` calls it for the test).

### Tuning (top of `icehaul.lua`)

`PAY` 2,000, `REP` 75, `DELIVER_R` 4U, `RAIDERS` 2,
`KESTREL`, `ORBIT_R` 16U, `ORBIT_START` 160°, `ORBIT_PERIOD` 3,600 s.

The tow line's own numbers are `TOW.REACH` 2U, `TOW.LENGTH` 1.5U, `TOW.DRAIN` 3/s, `TOW.MAX_SPEED` 250
(15U a minute; `TOW.LIMIT_TEXT` says it for the crew) and `TOW.SLACK` 1.02, at the top of `ee/ragtag/tow.lua`; they apply to the tow job too.

### Open for playtest

- Does the tow feel like towing? Line length, the energy drain (enough to matter, not
  enough to strand the ship?), turning with the ice behind.
- Is the half-warp rule clear? Do Engineering (warp power) and Science (the tow speed) find the speed
  together, and is the snap fair?
- Is the ice easy to find (a sector name, pale blue on radar)?
- Two raiders always: too much for a crew that has just finished Rezkov? Is 2,000 cr right for it?

### History

- 2026-11-24: built as a short, unopposed job to try out the tow line.
- 2026-11-24: the tow no longer slows the ship (impulse 75% was dropped); it drains energy instead
  (`TOW_DRAIN`, scaled by the throttle), like the Ledger AI's drain.
- 2026-11-24: the tow line moved into `TOW` (`ee/ragtag/tow.lua`) for the new tow job; same behaviour.
- 2026-11-24 playtest: the mechanics all worked, but the job was a bit slow. The line now holds at warp 1
  (up to 30U a minute, measured as speed so a boosted drive can't cheat it); only faster snaps it.
- 2026-11-25: the limit is half of warp 1 (15U a minute), so Engineering turns the warp drive down to about
  half and Science reads "Tow speed" to tune it: towing becomes a two-station job. The tow job's raiders
  fly 20% faster than the limit.
- 2026-11-25: the tow line is visible: a pale blue beam from the ship to the tow, on screen and radar.
- 2026-11-25: two raiders come for the ice the first time the line goes on (`TOW.intercept`, `M.RAIDERS`),
  10U out, hailing and attacking at once; the water office warns about them. The tow job's raiders now
  come the same way (on the first hook-up, not as the crew arrives). Pay 1,500 -> 2,000 cr for the fight.

### Testing

`tools/game_tests.py --ee <EE dir> arcs/icehaul` (`tests/arcs/icehaul.lua`) covers the gate, the
seed rumor (it sets the objective), the two pages, the ice drifting round Kestrel, the button only
within reach, attaching (two raiders 10U out, attacking; no more on re-attach; breaking off on
delivery and gone with the ice; removed when the Magpie is lost) (the line, impulse unchanged), the energy it costs at full
impulse against flying free, the ice following a moved ship, casting off,
warp 1 at half warp power holding (about 15U a minute, the full drain, Science's tow speed), warp 1 at
full power snapping the line, the delivery and its pay and standing, the news, the achievement, the ice taken
in, the Magpie lost, every GM state (with next-session routing) and "-> Inactive". The tow line
behind a ship flying on impulse is in `tests/core/orbit.lua`. Not covered: flying the tow by hand.
