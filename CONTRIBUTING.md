# Contributing

There are three ways to contribute, and they're deliberately independent:

| You want to… | Touch | Don't touch |
|---|---|---|
| **Add to the universe** (stations, regions, hazards, pirate zones, salvage, rumours) | a new file in `ee/ragtag/verse/extensions/` | scenarios, `drift.lua` |
| **Write a scenario or campaign** | a folder in `scenarios/` | the universe |
| **Improve the framework or director** | `ee/ragtag/*.lua`, `director/`, `tools/` | — (but keep the contracts below) |

Using Claude Code? The repo's `CLAUDE.md` and the project skill in `.claude/skills/` give it the
context; ask it things like "add a universe extension with a smugglers' moon near Cinder" or
"write Long Haul session 2 from scenarios/longhaul/plan.md".

## Setup
- EmptyEpsilon 2024 or newer (the ECS engine).
- Python 3.11+, and Lua 5.4 for the tools (`apt install lua5.4`, `brew install lua`, `scoop install lua`).
- `python tools/install.py --ee <your EmptyEpsilon folder> --link` installs everything as symlinks, so edits show up after restarting the scenario.

## Adding to the universe
1. Copy `docs/examples/extension_example.lua` into `ee/ragtag/verse/extensions/<your_name>.lua`.
2. Give it a unique `id`; add what you like. Field formats match `ee/ragtag/verse/drift.lua`.
3. `python tools/check.py --fix` validates it and regenerates the GM map, the extension index and the director's world description.
4. Fly it: install, start any scenario, and look around (`docs/verse_map.svg` shows where your additions landed).

Extensions **only add**. If you think the base map itself should change (moving or renaming a place),
open an issue first: scenarios depend on those names, and `check.py` will list each one you'd break.
Keep new stations and asteroid fields at least 4u apart, and dangerous garrisons off the trade routes
unless ambushing freighters is the point.

## Writing a scenario
1. Make `scenarios/<campaign>/` (a one-shot can be a campaign of one).
2. Start from `scenarios/_template/scenario_99_template.lua`; rename to `scenario_NN_<name>.lua` with a free number (below).
3. Call `RT.useCampaign("<campaign>")`, `VERSE.build{session = N}`, and list every universe place you use in
   `VERSE.requirePlaces{...}`. Place your own objects with `VERSE.at("Place", dx, dy)`, never fixed coordinates
   for universe places, and don't recreate stations the universe has.
4. Optional: `scenarios/<campaign>/bible.md` gives the AI director your story (cast, secrets, tone). The universe
   description is added automatically.
5. Every beat the AI may trigger needs a scripted fallback; the scenario must work with Director=Off.
6. `python tools/check.py`, then play it or run `tools/ci_headless.sh` with `SCENARIO=scenario_NN_<name>.lua`.

### Scenario numbers
Stock EmptyEpsilon uses 00–62, 74, 79, 81, 88 and 99. Reserved here:

| Numbers | For |
|---|---|
| 90–94 | The Long Haul (sessions 1–5) |
| 63–69, 71–73 | Community one-shots |
| 75–78, 80, 82–87 | Community campaigns (claim a block in your PR) |
| 89, 95–98 | Spare |

## Framework and director changes
- Director actions live in two places that must match: `DIR.ACTIONS` in `ee/ragtag/director.lua` (the safety
  boundary: validate and clamp everything) and `director/actions.py` (what the model is told). Add a smoke-test case.
- Python stays standard-library only, so lab PCs need nothing but Python.
- Read `.claude/skills/empty-epsilon-scenarios/references/api_notes.md` before writing EE Lua; most bugs
  this project hit are listed there.

## Pull requests
CI runs `tools/check.py`, starts the director against a mock game, and runs a headless EmptyEpsilon
smoke test. Say in your PR what you tested by hand and what you didn't.
