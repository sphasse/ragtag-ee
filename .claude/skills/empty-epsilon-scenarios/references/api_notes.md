# EmptyEpsilon scripting: verified behaviours and gotchas

Everything here was checked against the EmptyEpsilon source and a running headless server (ECS-era engine, 2024+ releases). Older pre-ECS builds differ; if the crew's version predates 2024, check before relying on these.

## Contents
1. Scenario file format
2. Lifecycle and timing
3. Environments: scenario, required files, comms, HTTP
4. Entities and components (the crash traps)
5. Ships, weapons and upgrades
6. Comms
7. Persistence (ScriptStorage)
8. JSON
9. GM screen
10. Factions and templates
11. Headless testing

## 1. Scenario file format
- File name `scenario_NN_name.lua` in the `scripts/` folder. NN orders the list.
- Header comments are parsed by the game:
  ```
  -- Name: Long Haul 2: Salvage Rights
  -- Description: One line shown in the list.
  --- Extra description lines start with three dashes.
  -- Type: Long Haul Campaign          (groups scenarios in the list)
  -- Setting[Difficulty]: Description of the setting
  -- Difficulty[Easy]: Description
  -- Difficulty[Normal|Default]: Description    (|Default marks the default)
  ```
- Read settings with `getScenarioSetting("Difficulty")`; it returns the value string, or "" if absent.

## 2. Lifecycle and timing
- `init()` runs once. `update(delta)` runs every frame; `delta` is seconds since the last frame.
- Use `getScenarioTime()` for timers. Never count frames: a counter incremented per frame runs at different speeds on different machines. (This bug was caught in testing: a "20 second" chase timer was actually 20 frames.)
- `victory("Faction name")` ends the scenario immediately. Emit any final events and save first, then delay victory a few seconds if an external tool needs to read them.
- Errors inside `update()` are logged every frame but don't stop the game; errors in `init()` can leave the scenario half-built. Wrap risky callbacks in `pcall`.

## 3. Environments
- `require("file.lua")` runs the file with the *scenario's* environment, so globals defined in required files are scenario globals. Paths are relative to `scripts/`.
- Comms callbacks: `entity:setCommsFunction(function(comms_source, comms_target) ... end)`. Use the parameters. The old `comms_source`/`comms_target` globals exist only inside the callback and are not visible in required files. Reply callbacks get the same two parameters: `addCommsReply("Text", function(source, target) ... end)`.
- HTTP `/exec.lua` (enabled with `httpserver=8080` in `options.ini`, or as a command-line argument) runs posted code in a **separate environment built from the base API**. It can call any API function and see every entity, but it **cannot see scenario globals or functions**. Its return value must be a string (the handler converts with `run<string>`); use `return "ok"` for writes. `/get.lua` and `/set.lua` currently return "TODO".
- The only shared channel between scenario and HTTP environments, besides the entities themselves, is `getScriptStorage()`.

## 4. Entities and components (the crash traps)
- Entities are component bags. Every `Entity:` method is callable on every entity, but some index a component directly and **raise an error if it's missing**. Verified crasher: `getTypeName()` on asteroids, nebulae, artifacts and other non-ship objects (`attempt to index a nil value (field 'typename')`).
- Safe on anything: `getCallSign()` (returns "?"), `getFaction()` (returns nil), `isEnemy(x)` / `isFriendly(x)` (return false), `getPosition()`.
- When scanning objects from `getObjectsInRadius(x, y, r)`, filter to ships and stations with `obj.components.typename ~= nil`, and wrap per-object reads in `pcall`.
- **Identifying entity types**: Use `isObjectType(entity, "TypeName")` from `utils.lua` (automatically loaded). This is the correct way to identify specific entity types like scan probes, which don't have a `typename` component. Example: `if isObjectType(obj, "ScanProbe") then obj:destroy() end`. Common types: `"ScanProbe"`, `"CpuShip"`, `"PlayerSpaceship"`, `"SpaceStation"`. Reference: [EmptyEpsilon utils.lua:351](https://github.com/daid/EmptyEpsilon/blob/b492ea94326c229ec8c0047872451129c4338871/scripts/utils.lua#L351)
- **Do NOT** try to identify types with `obj:typeName()` (doesn't exist) or `obj:getTypeName()` (fails on objects without typename component) or heuristics like faction/method presence (matches unintended objects). Always use `isObjectType()`.
- `entity:isValid()` checks if an entity still exists; `entity:destroy()` removes it silently; `entity:explode()` removes it with an explosion. Entities compare with `==`.
- `onDestruction(fn(self, instigator))` fires when destroyed by damage; `onDestroyed(fn)` fires for any removal.
- Use `setCanBeDestroyed(false)` on anything the story depends on (a derelict that must be scanned, a key station). A stray missile otherwise softlocks the session.

- In `/exec.lua` and other non-scenario environments, `utils.lua` helpers (`angleHeading`, `distance`, `vectorFromAngle`...) are not loaded. Use plain math there.
- Reading a component that doesn't exist *as a component type* (e.g. `obj.components.planet`) raises "Tried to get non-existing component". Valid names come from the API files: `typename`, `pickup`, `planet_render`, `orbit`, `physics`, `impulse_engine`, ... A valid component type that the entity lacks just returns nil.
- `FactionInfo():setName("X")` creates a custom faction at runtime (limit 32; the stock file uses 10). Call it in `init()` before any entity uses the faction. Relations: `a:setEnemy(b)` / `a:setFriendly(b)` take FactionInfo objects (`getFactionInfo("Independent")`) and are reciprocal; anything unset is neutral.

## 5. Ships, weapons and upgrades
- `PlayerSpaceship():setTemplate("Flavia P.Falcon"):setFaction("Independent"):setCallSign("Magpie"):setPosition(x, y)`.
- Units: 1u on the radar = 1000 in coordinates. Impulse speed is in coordinate units per second: a 60-speed ship covers 1u in about 17 s, and a 45-speed freighter takes over 20 minutes for a 60u leg. On maps wider than ~80u, give AI traffic a warp drive (`setWarpDrive(true)`, `setWarpSpeed(300)`); CpuShip AI uses it on long legs automatically.
- CpuShip AI pathing around stations is weak: a ship placed on the far side of a station from its destination can push against the hull indefinitely. Spawn ships on the side facing where they're going. Likewise keep asteroid fields at least ~4u clear of stations, or freighters can't reach the dock.
- Two CpuShips flying opposite directions along the same line can deadlock nose to nose at zero speed indefinitely. Any long-running AI traffic needs a stall watchdog (`ee/ragtag/verse.lua` nudges a freighter sideways if it moves under 0.8u in 60 s). Small stations dock one ship at a time; others circle and wait, which is normal.
- `orderDefendLocation(x, y)` keeps a ship near a point and engages enemies that come close: ideal for zone garrisons that shouldn't wander. `orderRoaming()` lets ships wander the whole map.
- Planets: `Planet():setPosition():setPlanetRadius(r):setPlanetSurfaceTexture("planets/planet-1.png")`, optional `setPlanetCloudTexture`, `setPlanetAtmosphereTexture("planets/atmosphere.png")` + `setPlanetAtmosphereColor(r, g, b)`, `setDistanceFromMovementPlane(-r * 0.4)`. A sun is a planet with only `setPlanetAtmosphereTexture("planets/star-1.png")` and a colour. Textures: planet-1..5, planet-earth, gas-1..3, moon-1..3, clouds-1..3, atmosphere, star-1. Avoid `setOrbit` near stations: orbiting bodies collide with whatever is on their path.
- Freighter templates: `"<Personnel|Goods|Garbage|Equipment|Fuel> Freighter <1-5>"` and `"... Jump Freighter <3-5>"`. Higher numbers are bigger and slower.
- `setBeamWeapon(index, arc, direction, range, cycle_time, damage)`: indices are 0-based, and setting a higher index adds new beam mounts. Direction 0 is forward, 180 rear.
- `setWeaponTubeCount(n)` **rebuilds every tube**, wiping their directions and settings. Re-apply `setWeaponTubeDirection(i, deg)` for all tubes afterwards.
- `setShieldsMax(front, rear)` is variadic; the number of arguments sets the number of shield segments.
- `setImpulseMaxSpeed(forward, reverse)`, `setJumpDrive(true)` + `setJumpDriveRange(min, max)`, `setWarpDrive(true)` + `setWarpSpeed(v)`, `setRepairCrewCount(n)`, `setLongRangeRadarRange(r)`.
- Missiles: `setWeaponStorageMax("Homing", n)` then `setWeaponStorage("Homing", n)`. Types: "Homing", "Nuke", "Mine", "EMP", "HVLI".
- System names for `getSystemHealth`/`setSystemHealth`/`hasSystem`: "reactor", "beamweapons", "missilesystem", "maneuver", "impulse", "warp", "jumpdrive", "frontshield", "rearshield". Health ranges -1..1.
- Player reputation points (`getReputationPoints`, `addReputationPoints`, `setReputationPoints`) are shown on Relay and make a natural currency.
- Docking: `player:isDocked(station)`; `ship:getDockedWith()` returns the station entity, or **`false` (not nil) when undocked**. Test it with `if ship:getDockedWith() then`, never `~= nil` (older scripts, including well-known community ones, use `~= nil` and silently break on the ECS engine). `player:commandDock(station)` only works within docking range.
- Scanning: `ship:setScanningParameters(complexity, depth)`, `ship:setDescriptions(unscanned_text, scanned_text)`, `ship:isFullyScannedBy(player)`.

## 6. Comms
- `sender:sendCommsMessage(player, text)` opens a hail and logs the text. **It returns false if the player's comms are busy**, and the message is then lost. Always check the result and fall back to `player:addToShipLog(text, color)` or retry later (`RT.hail` does the fallback).
- Inside a comms function: `setCommsMessage(text)` once, then any number of `addCommsReply(label, fn)`. Rebuild the menu by calling your menu function again from a reply.
- Comms are menu-driven; players can't type free text to a scripted NPC. To fake live conversation, have a reply emit an event and let something answer a few seconds later with a hail.
- `player:addCustomInfo(station, key, text, order)` and `addCustomButton(station, key, label, fn, order)` put info or buttons on crew screens. Station names are lowercase: "helms", "weapons", "engineering", "science", "relay", "tactical", "engineering+", "operations", "single".
- `globalMessage(text, seconds)` shows text on all main screens.

## 7. Persistence (ScriptStorage)
- `local s = getScriptStorage()`, `s:set(key, value)`, `s:get(key)`. One process-wide store, saved to `$HOME/.emptyepsilon/scriptstorage.json` (on Windows without HOME set, `scriptstorage.json` in the working folder).
- Values are stored as JSON; tables work, but store a `toJSON(...)` string for predictable round-trips.
- **Every `set` rewrites the whole file.** Fine a few times a second, but don't call it every frame.
- It survives server restarts, which is what makes multi-session campaigns possible. It lives on the *server* machine: if the lab reimages PCs, keep a backup elsewhere (the director mirrors the campaign save).

## 8. JSON
- `toJSON(value)` and `fromJSON(string)` are globals (ECS-era builds).
- A table with keys 1..n becomes an array; anything else becomes an object. **An empty table becomes `{}`, not `[]`**, so consumers must accept either for empty lists.
- Entities and functions serialise to null. Convert to callsigns first.

## 9. GM screen
- `addGMFunction(label, fn)` adds a button; `removeGMFunction(label)`, `clearGMFunctions()`.
- `addGMMessage(text)` shows a dismissable message to the GM.
- Prefix button labels with the session (e.g. "S2: fire ambush") so the GM can tell campaign tools from session tools.

## 10. Factions and templates
- Factions: "Independent", "Human Navy", "Kraylor", "Arlenians", "Exuari", "Ghosts", "Ktlitans", "TSN", "USN", "CUF". Exuari are hostile to Independent; Human Navy and Ghosts are neutral to Independent.
- An Independent player ship can't be attacked by `orderAttack` from a non-hostile faction. For "the law chases you" scenes, use `orderFlyTowards`/`orderFlyTowardsBlind` toward the player and resolve the outcome with distance checks.
- Useful templates: player "Flavia P.Falcon" (rear beams, rear tube, warp), "Phobos M3P", "Atlantis". Small hostiles: "MT52 Hornet", "Adder MK5", "Piranha F12". Medium: "Phobos T3", "Stalker Q7". Heavy: "Nirvana R5", "Atlantis X23". Civilians: "Flavia", "Tug". Patrol: "Phobos M3". Stations: "Small Station", "Medium Station", "Large Station", "Huge Station".
- CpuShip orders: `orderIdle()`, `orderRoaming()`, `orderAttack(target)`, `orderDefendTarget(t)`, `orderFlyTowards(x, y)`, `orderFlyTowardsBlind(x, y)`, `orderFlyFormation(leader, dx, dy)`, `orderDock(station)`, `orderRetreat()`.

## 11. Headless testing
- Launch from the EmptyEpsilon folder: `EmptyEpsilon headless=scenario_90_longhaul_1.lua httpserver=8080`. On a machine without a display, also set `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy`.
- Then drive it over HTTP: `curl --data 'return tostring(getScenarioTime())' http://localhost:8080/exec.lua`.
- Lua errors appear in the terminal / `EmptyEpsilon.log` as `LUA-Error:` with a traceback.
- Only one server can bind port 8080; a second launch crashes. Stop the old one first.
- `luac -p file.lua` (Lua 5.4) catches syntax errors without the game.
