# Universe extensions

Each `.lua` file here adds to the base universe (`../drift.lua`) with one
`VERSE.extend{...}` call: stations, regions, planets, nebulae, asteroid fields,
garrisons, salvage, hazards, wrecks, freighter route stops, rumours and lore.
Every scenario picks extensions up automatically.

1. Copy `docs/examples/extension_example.lua` here and rename it (lowercase, underscores).
2. Give it a unique `id` and edit the content.
3. Run `python tools/check.py --fix`: it validates the data, regenerates
   `index.lua`, the GM map and the director's world description.
4. Install (`python tools/install.py --ee <EmptyEpsilon folder>`) and fly around.

Rules: don't remove or rename anything from other files (extensions only add);
keep stations and asteroid fields at least 4u apart; keep new hostile garrisons
away from trade routes unless that's the point. `index.lua` is generated; don't edit it.
