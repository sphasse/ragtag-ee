# The <Name> Arc — GM guide

<!-- Copy to docs/GM_<NAME>_MISSION.md. Examples: docs/GM_REZKOV_MISSION.md (shortest),
     docs/GM_CORSAIR_MISSION.md (a battle arc). Write for a GM running a session, not for a
     programmer: what the crew sees and does, what the GM can press. Code detail goes in Design notes. -->

A <Phase II / finale / ...> story arc of The Drift (sandbox campaign, scenario 80). **Spoilers**: keep
this away from players. Module: `ee/ragtag/missions/<name>.lua`. Back to the [GM guide](GM_GUIDE.md).

## Premise

<!-- One paragraph: the situation and what the crew does, in story terms. -->

Where it sits in the campaign:

<!-- Bullets, each starting with a bold claim. Cover: which thread it is (evidence / science / ally /
     ...); who it introduces and what they do later; what it does to the factions (e.g. the Concord
     weakened, the Corsairs friendly) and which later arcs or options that sets up; which flags the
     finale or later arcs read. Name the later arcs. -->

- **It is the <...> thread.** ...
- **It introduces <person>**, ... who later ...
- **It costs / gives <faction> ...** (`<flag>`), which sets up ...

## Triggers

<!-- Every condition, in GM words (standing, upgrades, other arcs over), then how it starts (auto,
     rumors, a hail) and any seed rumors or jobs loaded before it. -->

- ...

## Phases

```
hook ─► ... ─► done (<outcome> | <outcome>)
```

### <Phase, named as the GM sees it>

<!-- One ### per phase. What the crew sees (hails quoted briefly, objectives in quotes), what they
     must do, where (grid coords), the choices (bold reply text → result), and how it can fail.
     Numbers a GM needs (timers, ranges) stay here; constants go to Design notes. -->

### Done

<!-- What happens at the end: hails, clean-up, timers. -->

## GM console

**Missions… → <Name> Arc**:

| Button | Effect |
|---|---|
| `→ Inactive` | Back to waiting (engine button) |
| `→ <Phase>` | ... |
| `→ Done: <Outcome>` | End the arc |

Helpers, shown only in their phase:
- **<Helper>** (<phase>): what it does.

<!-- What a jump resets and replays; that reputation and credits are not applied by a jump, and that
     rewards pay once. -->

## Exports

| Flag | Values |
|---|---|
| `<name>_arc_done` | `"<outcome>"` / ... (who reads it) |

Rewards, once: ...

Science DB: ...

## Design notes

<!-- Everything a maintainer needs and a GM doesn't: state tables (`st.*`), saved flags, factions and
     their lifecycle, engine workarounds, tuning constants (with values), rumor/job categories,
     history (what a playtest changed and why), open playtest questions, and testing
     (`tools/game_tests.py --ee <EE dir> arcs/<name>`; what headless tests can't cover). -->

### Testing

`tools/game_tests.py --ee <EE dir> arcs/<name>` (`tests/arcs/<name>.lua`).
