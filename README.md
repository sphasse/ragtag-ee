# The Long Haul — an AI-directed EmptyEpsilon campaign

A five-session space-western campaign for EmptyEpsilon. Your crew flies the *Magpie*, a battered light freighter, earning credits to buy upgrades between jobs. A local language model running on another PC acts as a live director: it voices characters, answers hails, times ambushes and reacts to your instructions, so the GM doesn't have to do everything by hand on the GM screen.

Status: the framework and Session 1 are built and tested against EmptyEpsilon (build 20261019) running headless. Sessions 2–5 are planned in detail in the skill (`references/campaign_plan.md`) but not yet written.

## How it fits together

```
 Game server PC                                 AI PC (with GPU)
┌───────────────────────────────┐   LAN       ┌───────────────────────────────────┐
│ EmptyEpsilon (server)         │  HTTP       │ director/main.py                  │
│  scenario_70_longhaul_1.lua   │◄───────────►│  polls the mailbox every 1.5 s    │
│   ragtag_core.lua    (RT)     │ /exec.lua   │  asks the model when needed       │
│   ragtag_director.lua (DIR)   │  :8080      │  validates and sends actions      │
│  ScriptStorage mailbox        │             │  GM web console on :8765          │
│   rt.from_scenario  ──────────┼─ events ───►│        │                          │
│   rt.from_director  ◄─────────┼─ actions ───┤        ▼ OpenAI-compatible API    │
└───────────────────────────────┘             │  Ollama / llama.cpp / LM Studio   │
     ▲ crew stations (LAN)                     └───────────────────────────────────┘
```

Scenario Lua can't make network calls, and EmptyEpsilon's `/exec.lua` endpoint runs code in a separate environment from the scenario. Both can see the process-wide ScriptStorage, so the scenario and director exchange JSON through two storage keys, each written by one side only. The model never sends Lua: it chooses from a fixed list of actions, and the scenario checks and clamps every argument. Every AI-timed story beat also has a scripted fallback, so the scenario plays fine with the director off.

## Contents

| Path | What |
|---|---|
| `ee_scripts/` | Copy into EmptyEpsilon's `scripts/` folder on the game server |
| `ee_scripts/ragtag_core.lua` | Campaign save, ship and upgrades, credits, stations, shipwright, objectives |
| `ee_scripts/ragtag_director.lua` | Mailbox, events, state snapshot, the action list, AI buttons on the GM screen |
| `ee_scripts/scenario_70_longhaul_1.lua` | Session 1: Cold Cargo |
| `director/` | The AI director (Python 3.11+, standard library only) |
| `director/campaign_bible.md` | World, cast and arc the model is given; edit freely |
| `director/prompts/system.md` | The director's instructions |
| `tools/smoke_test.py` | Tests the bridge and plays through Session 1 against a live server |

## Setup

### 1. Game server PC
1. Copy everything in `ee_scripts/` into EmptyEpsilon's `scripts/` folder.
2. Enable the HTTP API: in `options.ini`, change `httpserver=` to `httpserver=8080`.
   - Windows: `options.ini` is in the EmptyEpsilon folder.
   - Linux/macOS: `~/.emptyepsilon/options.ini` (Flatpak and Steam installs differ; see the EmptyEpsilon wiki "Preferences file" page).
3. Allow inbound TCP 8080 from the AI PC in the firewall. Don't expose it to the internet: anyone who can reach it can run Lua on your server.
4. Start EmptyEpsilon as the server and pick **Long Haul 1: Cold Cargo** (Type: Long Haul Campaign). Crew stations connect as usual.

You need a 2024-or-later EmptyEpsilon (the ECS engine). The director's `--probe` reports a problem if `toJSON` is missing.

### 2. AI PC
1. Install Python 3.11 or newer.
2. Install a local model server. With [Ollama](https://ollama.com): `ollama pull <model>`. An instruction-tuned model in the 8B–14B range that's good at JSON (current Qwen, Llama, Mistral or Gemma families) is plenty and replies in a few seconds on a mid-range GPU.
3. **Give the model enough context.** The director's prompt is about 3,000 tokens. Older Ollama defaults (2,048) silently truncate it. Set `OLLAMA_CONTEXT_LENGTH=8192` in the environment before starting Ollama.
4. `cd director`, copy `config.example.toml` to `config.toml`, and set `[ee] url` to the game server's address and `[llm] model` to your model's name.
5. Check both connections: `python main.py --probe`
6. Run it: `python main.py`, then open `http://<ai-pc>:8765/` (or `http://localhost:8765/`) on whichever PC the GM uses.

Start order doesn't matter. The director waits for a scenario and picks up new runs automatically; the scenario tells the GM screen when the director connects or drops out.

### Trying it without the game or a model
`python main.py --mock --mock-llm` runs a fake scenario and canned model replies so you can explore the console. `--mock` alone uses your real model with the fake scenario, which is handy for tuning prompts.

## Running a session

**On the GM screen** (in EmptyEpsilon): campaign buttons (credits, save), session buttons (fire specific beats, end the session) and AI buttons: *twist*, *escalate*, *ease off*, *chatter*, *pause/resume*, *status*.

**In the director console** (browser):
- *Tell the director what you want*: plain-English instructions, e.g. "Have Grinning Teeth taunt them about the bribe, then send two scouts from behind." Quick buttons cover the common asks.
- *Standing directives*: rules for the whole evening, e.g. "We have an hour; keep fights short."
- *Model actions: wait for my approval* lets you vet everything the model does before it happens.
- *Story beats*: see what's fired and fire any beat yourself.
- *Do it yourself*: send any action directly, no model involved.
- *Campaign memory*: the model's summary of each finished session and the characters it has voiced, plus a backup of the campaign save you can push back to the server.

**What the crew sees:** hails from characters (Relay), ship's log entries, objectives on the Relay/Operations screens, credits as reputation on Relay, and a shipwright menu when docked at Port Vesper or Halcyon Rest. Station and NPC comms include "Any news?", "Who are you?" and similar options; the director answers those with a hail a few seconds later.

## Campaign progress
Progress is stored on the **game server** in `scriptstorage.json` (`~/.emptyepsilon/` on Linux, the EmptyEpsilon folder on Windows) under the key `ragtag.campaign`: ship name, credits, upgrades, session outcomes and story flags. Each session re-applies purchased upgrades to a fresh ship. Choose *Campaign: Fresh start* in the scenario settings to reset.

If the lab reimages its PCs, that file may vanish. The director keeps a copy in `director/director_memory.json`; use *Restore campaign save to the game server* in the console, then restart the scenario.

## Session 1: Cold Cargo
Fixer Mags Oduya hires the crew to haul twelve sealed crates from Port Vesper to Halcyon Rest. On the way: a Concord patrol demanding an inspection (submit, bribe, or run, and each sets a flag later sessions remember), Exuari raiders, and a crate that hums. After delivery, an optional detour into the Shroud nebula leads to a derelict and the first lantern core. 45–70 minutes. Easy / Normal / Hard settings change raider numbers and the director's hostile budget.

## Testing
On a test server running a Long Haul scenario, with the director stopped:
```
python tools/smoke_test.py --ee http://<server>:8080               # every director action
python tools/smoke_test.py --ee http://<server>:8080 --playthrough # plus a teleporting Session 1 run
```
The playthrough cheats (teleports, forced scans) and changes the campaign save, so don't run it on your real campaign. Restore with Campaign: Fresh start afterwards. Latest result: 26 passed, 0 failed.

## Troubleshooting
| Symptom | Fix |
|---|---|
| `--probe`: EmptyEpsilon not reachable | `httpserver=8080` missing from `options.ini`, the server wasn't restarted after editing it, or a firewall blocks 8080 |
| Probe OK but "scenario mailbox empty" | Start a Long Haul scenario; make sure its Director setting is On |
| GM screen says "AI director offline" | The director isn't running or can't reach the server |
| Director connected but never acts | Check the console log for model errors; run `--probe`; try a GM instruction to force a call |
| Model replies are cut off or ignore the rules | Raise the model context length (setup step 3) or use a larger model |
| Actions show "FAILED: spawn cooldown" | Working as intended; the limits are in `DIR.config` in `ragtag_director.lua` |
| Lua errors on the server | Read `EmptyEpsilon.log`; the error names the file and line |

## Writing more sessions
Install the `empty-epsilon-scenarios` skill (shipped alongside this project) and ask Claude to write Session 2. The skill contains the session plans, a tested template, the framework reference and API notes verified against the engine source.
