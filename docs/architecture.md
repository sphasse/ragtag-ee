# Architecture

## Engine layers

```
scenarios/<campaign>/scenario_NN.lua      stories: beats, NPCs, objectives, choices
        │ uses (by place name only)
ee/ragtag/verse/drift.lua + extensions/   universe data (pure data, VERSE.extend)
        │ built by
ee/ragtag/verse.lua                       universe engine: factions, objects, traffic, salvage, regions
ee/ragtag/core.lua                        campaign saves, ship, upgrades, credits, stations, objectives
ee/ragtag/director.lua                    mailbox, events, beats, whitelisted director actions
        │ ScriptStorage mailbox, polled over HTTP /exec.lua
director/ (Python)                        AI director + GM web console → local model (OpenAI-compatible API)
```

Generated from the universe data by `tools/check.py --fix`:
`ee/ragtag/verse/extensions/index.lua`, `docs/verse_map.svg`, `director/generated/world.md`.

## Sandbox campaign systems

The sandbox scenario layers additional systems on top of the core engine:

```
VERSE / core         — world foundation: stations, regions, factions, traffic, comms
  ├── JOBS           — player economy: paid contracts offered at stations
  ├── RUMORS         — information economy: circulating intel, quest hooks
  ├── WORLD plugins  — ambient features: patrols, defenders (run every frame)
  └── MISSIONS arcs  — story events: multi-phase scripted arcs with GM controls
```

**VERSE / core** is the complete world by itself. Stations have buy/sell/news
comms; freighters have travel comms; the universe is flyable without any
campaign system loaded.

**JOBS** adds a job board to every station. Players hail "Any work available?"
to get offers. Each contract type (delivery, salvage, hacking, boarding,
destroy, escort, tailing) is a self-contained module in `ee/ragtag/jobs/`.

**RUMORS** powers every "heard any news?" comms reply, on both stations and
freighters. Rumors have priority (1–10), optional faction filter, optional
category, and an optional `once` flag. Low-priority (1) rumors form background
chatter and are subject to a per-source cooldown. Higher-priority rumors bypass
the cooldown so quest hooks always reach the player; `once=true` rumors
self-remove after first delivery.

**WORLD plugins** run every frame and manage their own state. Current plugins:
`rumors` (information economy: rumor pool, injected quest hooks, delivery cooldowns),
`proximity` (zone-based faction patrols with per-zone intensity),
`defenders` (loitering escorts at Concord/Independent stations),
`salvage` (dynamic debris clusters with density/reward settings), and
`traffic` (freighter routes and ambient crate drops with density setting).
Plugins can be toggled and tuned by the GM at runtime.

**MISSIONS arcs** are multi-phase story events with trigger conditions and GM
controls. Each arc is a module in `ee/ragtag/missions/`. Arcs can inject and
remove rumors to set up and tear down quest hooks, and can lock the job board
while they run. Current arcs: `witness` (the Kael Voss whistleblower arc).

For contributor details see
`.claude/skills/empty-epsilon-scenarios/references/expansion_model.md`.

## Decoupling contracts
- Scenarios reference universe places by name and declare them with `VERSE.requirePlaces`; `check.py`
  fails if the universe stops providing one, so universe changes can't silently break scenarios.
- Extensions are append-only, loaded alphabetically after `drift.lua`.
- Campaign saves are per campaign (`ragtag.campaign.<id>` in `scriptstorage.json`).
- The director's prompt = system rules + generated world description + the running campaign's own `bible.md`
  (chosen by the `campaign` field the scenario sends).

## The director bridge
Scenario Lua can't make network calls, and EmptyEpsilon's `/exec.lua` runs in a separate Lua environment from
the scenario. Both see the process-wide ScriptStorage, so they exchange JSON through two keys with one writer each:

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

The model only picks from named actions; the scenario validates and clamps every argument, enforces
budgets and cooldowns, and keeps GM-only actions away from the model. Every AI-timed beat has a scripted
fallback, so scenarios play the same with the director off.
