# ragtag-ee — an AI-directed EmptyEpsilon universe

Space-western scenarios for [EmptyEpsilon](https://daid.github.io/EmptyEpsilon/), set in a shared,
living universe of trade lanes, frontier stations, pirate havens and places your crew isn't ready for yet.
An optional local language model on another PC acts as a live director: it voices characters, answers
hails, times ambushes and takes plain-English instructions from the GM.

**Two campaigns available:**
- **Sandbox**: Open-play exploration, make your own story (perfect for learning the universe)
- **The Long Haul**: 5-session narrative with the *Magpie* freighter (Session 1 built, 2-5 planned)

![The Drift](docs/verse_map.svg)

## For Players

**New to the Drift?** Start here:
- 📖 **[Player Documentation Index](docs/PLAYER_DOCS_INDEX.md)** — Find the right guide for you
- 🎮 **[Station Quick Reference](docs/STATION_REFERENCE.md)** — 2-page printable reference card
- 🚀 **[Player Guide](docs/PLAYER_GUIDE.md)** — Complete manual (read after your first session)
- 🌌 **[The Drift Setting](docs/THE_DRIFT_SETTING.md)** — Universe lore and backstory

**First session prep:** Read your station's section in the [Station Reference](docs/STATION_REFERENCE.md) (5 minutes). That's it—learn the rest by playing!

## Repository layout

| Path | What | Who edits it |
|---|---|---|
| `ee/ragtag/` | Lua framework installed into EmptyEpsilon's `scripts/ragtag/` | framework contributors |
| `ee/ragtag/verse/drift.lua` | The base universe, as data | rarely; see CONTRIBUTING |
| `ee/ragtag/verse/extensions/` | Community additions to the universe | **anyone** |
| `scenarios/<campaign>/` | Scenarios, plus each campaign's story bible and plans | **anyone** |
| `scenarios/_template/` | Starting point for new scenarios | |
| `director/` | AI director and GM web console (Python, standard library only) | |
| `tools/` | `check.py`, `install.py`, `smoke_test.py`, `ci_headless.sh`, map and world generators | |
| `docs/` | Architecture, GM map, example extension | |
| `.claude/skills/` | Claude Code skill with EmptyEpsilon scripting knowledge | |

Universe and scenarios are decoupled: scenarios refer to universe places by name and declare them, extensions
only add, and `tools/check.py` (also run in CI) fails if a universe change would break any scenario.
See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/architecture.md](docs/architecture.md).

## The Drift

Five suns, loosely modelled on the shape of the Firefly 'Verse with names of our own: a rich Concord Core around the white sun Lumen, Border worlds around Port Vesper, a lawless Rim, a dead world bombed in the Settlement War, and at the far edge, under the blue Pale Sun, the Hollow. See `docs/verse_map.svg`.

- **It's the same map every session.** The layout is generated from a fixed seed. Salvage is re-rolled each session so there's always something to find.
- **Traffic:** 15 freighters on Core, Border and Rim routes dock, linger, and move on. Hail them for rumours (several point at places worth exploring, or avoiding); fuel haulers sell energy and equipment haulers sell missiles. Ships lost to pirates are replaced later, out of sight.
- **Danger tiers.** Each region shows on Helm, Relay and Operations with its danger level:
  - *Safe:* the Core, the Border, the Rim, the Shroud.
  - *Risky:* the Gauntlet, an asteroid belt with Corsair ambush packs (a stock Magpie can win small fights here); the uncharted Deep Shroud.
  - *Dangerous:* Blackwater Reach, the mined Corsair haven; the Boneyard, where war drones guard wrecks.
  - *Deadly:* the Maw, Hollow territory with heavy warships and defense platforms. A turn-back warning appears on every main screen.
- **Salvage:** 25 clusters of pods (credits, missiles, hull patches, data chips). Safe pods are worth 15–30 credits; Maw pods 120–200. Scanning a wreck fully reveals extra salvage. Freighters occasionally lose a crate on the lanes. Charting a region for the first time pays a survey bonus.
- **Upgrades:** 16 in total, spread across different shipwrights; each yard tells you where to find what it doesn't stock. Concord stations refuse service to a ship flagged wanted. The second-tier upgrades (armoured hull, military shields, heavy beams, combat thrusters, warp and reactor overhauls) are what it takes to survive the dangerous zones.
- **Hazards:** a black hole, minefields around the hostile bases, and a rift in the Deep Shroud whose far end you won't like.

## Setup

### 1. Game server PC
1. Install the framework and scenarios: `python tools/install.py --ee <EmptyEpsilon folder>` (the folder containing `scripts/`). Re-run it after pulling updates.
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
Progress is stored on the **game server** in `scriptstorage.json` (`~/.emptyepsilon/` on Linux, the EmptyEpsilon folder on Windows) under one key per campaign (`ragtag.campaign.longhaul` for the Long Haul): ship name, credits, upgrades, session outcomes and story flags. Each session re-applies purchased upgrades to a fresh ship. Choose *Campaign: Fresh start* in the scenario settings to reset.

If the lab reimages its PCs, that file may vanish. The director keeps a copy in `director/director_memory.json`; use *Restore campaign save to the game server* in the console, then restart the scenario.

## Testing
- `python tools/check.py`: universe validation, scenario dependencies, numbering, generated files, syntax. Needs Lua 5.4.
- `tools/ci_headless.sh` (Linux): builds EmptyEpsilon at a pinned commit (or uses `EE_DIR`), installs, runs Session 1 headless and plays through it with `tools/smoke_test.py`. Latest: 38 passed, 0 failed.
- The smoke test's playthrough cheats (teleports, forced scans) and changes the campaign save. Don't run it against your real campaign.

## Troubleshooting
| Symptom | Fix |
|---|---|
| `--probe`: EmptyEpsilon not reachable | `httpserver=8080` missing from `options.ini`, the server wasn't restarted after editing it, or a firewall blocks 8080 |
| Probe OK but "scenario mailbox empty" | Start a Long Haul scenario; make sure its Director setting is On |
| GM screen says "AI director offline" | The director isn't running or can't reach the server |
| Director connected but never acts | Check the console log for model errors; run `--probe`; try a GM instruction to force a call |
| Model replies are cut off or ignore the rules | Raise the model context length (setup step 3) or use a larger model |
| Actions show "FAILED: spawn cooldown" | Working as intended; the limits are in `DIR.config` in `ee/ragtag/director.lua` |
| Lua errors on the server | Read `EmptyEpsilon.log`; the error names the file and line |

## Contributing
Universe extensions, new scenarios and campaigns are all welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md).
If you use Claude Code, `CLAUDE.md` and the project skill give it the project's conventions and the engine's quirks.
