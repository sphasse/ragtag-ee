# ragtag-ee — notes for Claude Code

EmptyEpsilon (bridge simulator) scenarios built on a shared universe, with an
optional local-LLM "director" that drives NPCs and pacing over EE's HTTP API.
Contributors add **universe extensions** and **scenarios** independently.

## Layout
- `ee/ragtag/` — Lua framework, installed to EmptyEpsilon `scripts/ragtag/`
  - `core.lua` (RT: campaign saves, ship, upgrades, credits, stations, objectives)
  - `verse.lua` (VERSE engine: builds the universe from data) + `verse/schema.lua` (VERSE.extend, validation)
  - `verse/drift.lua` — base universe **data** (no engine calls)
  - `verse/extensions/*.lua` — community universe additions; `index.lua` is generated
  - `director.lua` (DIR: mailbox to the AI director, events, beats, whitelisted actions)
- `scenarios/<campaign>/scenario_NN_name.lua` (+ `bible.md`, `plan.md`); `scenarios/_template/` is not installed
- `director/` — Python 3.11+ stdlib-only AI director; `generated/world.md` is generated
- `tools/` — `check.py`, `install.py`, `smoke_test.py`, `ci_headless.sh`, `make_map.py`, `gen_world.py`, `dump_verse.lua`
- `.claude/skills/empty-epsilon-scenarios/` — EE scripting knowledge and gotchas. **Read it before writing EE Lua.**

## Commands
- `python tools/check.py` (add `--fix` to regenerate generated files) — run after every change
- `python tools/install.py --ee <EmptyEpsilon dir> [--link]` — install into a game
- `EE_DIR=<EmptyEpsilon checkout with _build/EmptyEpsilon> tools/ci_headless.sh` — headless run + smoke test (Linux).
  Without `EE_DIR` it builds EmptyEpsilon at the pinned commits into `.ee-build/` (~20 min first time).
- `cd director && python main.py --mock --mock-llm` — director + GM console without game or model
- Requires `lua5.4`/`luac5.4` for the tools.

## Contracts (don't break these)
1. **Scenarios never rebuild or hard-code the universe.** They call `VERSE.build`, place their own objects with
   `VERSE.at("Place", dx, dy)`, and list every universe place they rely on in `VERSE.requirePlaces{...}`.
2. **Extensions only add.** Renaming/removing a place in `drift.lua` is a breaking change; `check.py` lists every scenario it breaks.
3. **The model never sends Lua.** Director actions are whitelisted in `ee/ragtag/director.lua` (`DIR.ACTIONS`) and mirrored in
   `director/actions.py`; change both together and clamp every argument on the Lua side.
4. **Every `ai = true` beat has a deterministic fallback**; scenarios must play with Director=Off.
5. **Each campaign has its own save** via `RT.useCampaign("<folder name>")` and its own `scenarios/<campaign>/bible.md`.
6. Scenario numbers must not collide with stock EmptyEpsilon or each other (`check.py` enforces; ranges in CONTRIBUTING.md).
7. Generated files (`extensions/index.lua`, `director/generated/world.md`, `docs/verse_map.svg`) come from `check.py --fix`; never hand-edit.

## Engine gotchas that have bitten this project
(Details in the skill's `references/api_notes.md`.)
- `/exec.lua` runs in a separate Lua environment (no scenario globals, no utils.lua) and must return a string.
- `ship:getDockedWith()` returns `false`, not nil, when undocked — test truthiness.
- `getTypeName()` errors on non-ships; filter with `obj.components.typename ~= nil`. Unknown component names raise errors.
- Freighter impulse is ~0.05u/s; AI traffic on this map needs warp, a spawn on the destination side of stations, 4u clearance, and the stall watchdog.
- `setWeaponTubeCount` resets all tubes; `sendCommsMessage` fails when comms are busy (use `RT.hail`).
- Headless EE: start detached (`setsid nohup ...`) and poll; one server per port.

## Definition of done
`python tools/check.py` passes, and for Lua changes a headless run shows no `LUA-Error` and the smoke test passes.
Say plainly in PR descriptions what was and wasn't tested.
