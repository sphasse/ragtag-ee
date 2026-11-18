# Architecture

## Engine layers

```
scenarios/<campaign>/scenario_NN.lua      stories: beats, NPCs, objectives, choices
        │ uses (by place name only)
ee/ragtag/missions/, jobs/, world/        story arcs, the job board, ambient world plugins
        │ built on
ee/ragtag/verse.lua                       universe engine: factions, objects, regions
ee/ragtag/verse/drift.lua + extensions/   universe data (pure data, VERSE.extend)
ee/ragtag/core.lua + core/*.lua           campaign save, per-ship records, stations, objectives,
        │                                 the event bus (RT.emit / RT.on)
        │ events out (RT.emit)  ─────────►  anyone listening
ee/ragtag/director.lua                    ONE listener: the AI director's mailbox
        │ ScriptStorage mailbox, polled over HTTP /exec.lua
director/ (Python)                        AI director + GM web console → local model (OpenAI-compatible API)
```

Dependencies point down. Core knows nothing of the missions layer (`ARC`, `MISSIONS`), and
nothing below `director.lua` names `DIR`: game code reports what happened with `RT.emit` and
never knows whether a director is listening. `tools/check.py` enforces both.

Generated from the universe data by `tools/check.py --fix`:
`ee/ragtag/verse/extensions/index.lua`, `ee/ragtag/director/actions/index.lua`,
`docs/verse_map.svg`, `director/generated/world.md`.

## Sandbox campaign systems

The sandbox scenario layers additional systems on top of the core engine:

```
VERSE / core         — world foundation: stations, regions, factions, comms, ship records
  ├── JOBS           — player economy: paid contracts offered at stations
  ├── WORLD plugins  — ambient features: rumors, patrols, defenders, salvage, traffic, Science DB
  └── MISSIONS arcs  — story events: multi-phase scripted arcs with GM controls
```

**VERSE / core** is the complete world by itself. Stations have buy/sell/news comms and the
universe is flyable without any campaign system loaded.

**JOBS** adds a job board to every friendly station. Players hail "Any work available?" to get
offers. Each contract type (delivery, salvage, hacking, boarding, destroy, escort, tailing) is a
self-contained module in `ee/ragtag/jobs/`. The engine has two halves: `JOBS.board(cs, ship)`
decides what a station offers a ship (slots, cooldowns, the reputation gate, injected story jobs)
without touching comms, and a small renderer shows it and wires the "Take:" replies.

**WORLD plugins** run every frame and manage their own state (`ee/ragtag/world/`):
`rumors` (the "any news?" replies: a background pool, injected seeds and quest hooks),
`proximity` (zone-based faction patrols and Concord shake-downs, with per-zone intensity),
`defenders` (a fighter posted at each Concord/Independent station),
`salvage` (debris clusters with density/reward settings; never within 20U of a station),
`traffic` (freighters on their routes, with a density setting) and
`sciencedb` (the Drift's Science database, which follows the campaign flags).
Plugins can be toggled and tuned by the GM at runtime. Each has a regression test in
`tests/world/`.

**MISSIONS arcs** are multi-phase story events with trigger conditions and GM controls. Each arc
is a module in `ee/ragtag/missions/`. Arcs inject and remove rumors to set up and tear down
quest hooks, seed the job boards with filler work and a special story contract (`JOBS.inject`),
can lock the job board while they run, and can suspend patrols in a zone (`PROX.suspendZone`).
Current arcs: `rezkov`, `boneyard`, `ledger`, `corsair`. Retired arcs are parked in
`missions/attic/` and are not loaded.

For contributor details see
`.claude/skills/empty-epsilon-scenarios/references/expansion_model.md`.

## Ships and ownership

More than one player ship can be in the game. Everything a ship owns is in **one record per
ship** with the same three fields: `credits`, `reputation` (faction → standing) and `upgrades`.
The primary ship's record is the campaign table itself (`campaign.credits`, `.reputation`,
`.upgrades`); every other ship's is an entry of `campaign.extra_ships`. `RT.shipRecord(ship)`
returns the right one, and `RT.credits`, `RT.addReputation`, `RT.hasUpgrade` and friends are thin
wrappers over it, so changing a record changes the save.

- A ship that buys an upgrade pays for it, gets it, and is the only ship that has it. Job tier
  and patrol strength follow each ship's own upgrades.
- A job belongs to the ship that took it; a donation, a fine or a kill is credited or charged to
  the ship that made it.
- Story arcs belong to the primary ship. "No ship given" means the primary ship, and that
  default is for arcs only: everywhere else `tools/check.py` requires the ship to be passed.

**Identity.** A callsign is a name, not an identity: two ships can share one and a ship can be
renamed. Code that spawns a ship keeps the entity (`m.target`, `group.ships`, `slot.ship`) and
never looks it up again; `RT.find(callsign)` is for things addressed by name (universe places, a
speaker the GM typed). A ship's record is bound to the ship entity for the session; the callsign
is only how a crew that rejoins in a later session finds its record.

## Decoupling contracts
- Scenarios reference universe places by name and declare them with `VERSE.requirePlaces`; `check.py`
  fails if the universe stops providing one, so universe changes can't silently break scenarios.
- Extensions are append-only, loaded alphabetically after `drift.lua`.
- Campaign saves are per campaign (`ragtag.campaign.<id>` in `scriptstorage.json`).
- The director's prompt = system rules + generated world description + the running campaign's own `bible.md`
  (chosen by the `campaign` field the scenario sends).

## Events and the director bridge

`RT.emit(type, data, priority)` is the campaign's event bus (`ee/ragtag/core/events.lua`). Core,
jobs, world plugins and arcs call it; `RT.on(fn)` subscribes. With no subscriber an event goes
nowhere, so every layer plays the same with or without a director. Scripted story beats
(`RT.defineBeat` / `RT.fireBeat`) and state providers (`RT.addStateProvider`) live there too.

The director's mailbox (`ee/ragtag/director.lua`) is one subscriber. Scenario Lua can't make
network calls, and EmptyEpsilon's `/exec.lua` runs in a separate Lua environment from the
scenario. Both see the process-wide ScriptStorage, so they exchange JSON through two keys with
one writer each:

| Key | Writer | Contents |
|---|---|---|
| `rt.from_scenario` | scenario | run id, unacknowledged events, command acks and results, state snapshot (incl. session briefing) |
| `rt.from_director` | director | run id, heartbeat, event ack, queued commands |

```
 Game server PC                                 AI PC (with GPU)
┌───────────────────────────────┐   LAN       ┌───────────────────────────────────┐
│ EmptyEpsilon (server)         │  HTTP       │ director/main.py                  │
│  scenario + scripts/ragtag/   │◄───────────►│  polls the mailbox every 1.5 s    │
│  ScriptStorage mailbox        │ /exec.lua   │  asks the model when needed       │
│   rt.from_scenario  ──────────┼─ events ───►│  validates and sends actions      │
│   rt.from_director  ◄─────────┼─ actions ───┤  GM web console on :8765          │
└───────────────────────────────┘   :8080     │        ▼ OpenAI-compatible API    │
     ▲ crew stations (LAN)                     │  Ollama / llama.cpp / LM Studio   │
                                               └───────────────────────────────────┘
```

**The director is observation-only.** It hears events and reads the state snapshot. The model
may send two actions, neither of which touches the game: `gm_note` (a private note to the human
GM) and `noop`. Everything the crew can see or that changes the campaign (`say`,
`set_objective`, `rename_ship`, `restore_campaign`) is GM-only: `director/actions.py` keeps it
from the model, and the Lua side refuses it again unless the command came from the GM console.
The model never sends Lua, only names from the whitelist in `ee/ragtag/director/actions/`.
`check.py` checks that the two lists match and that every action other than `gm_note` and `noop`
carries the GM-only guard; `tests/core/events.lua` checks it in a running game.
