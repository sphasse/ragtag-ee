# Architecture

## Layers

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
