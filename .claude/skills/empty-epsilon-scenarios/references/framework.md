# The Long Haul framework (RT + VERSE + DIR)

Three Lua libraries that every campaign session requires, plus a Python director. In the ragtag-ee repo they live in `ee/ragtag/` and install to EmptyEpsilon's `scripts/ragtag/` via `tools/install.py`; scenarios load them with `require("ragtag/core.lua")` etc.

## Contents
1. RT (ee/ragtag/core.lua): campaign, ship, credits, stations, objectives
1b. VERSE (ee/ragtag/verse.lua): the shared universe
2. DIR (ee/ragtag/director.lua): beats, events, state, actions
3. Mailbox protocol (for changing the Python side)
4. Adding a new director action

## 1. RT
| Function | What it does |
|---|---|
| `RT.loadCampaign(fresh)` | Load (or reset) the save into `RT.campaign`: `ship_name, credits, upgrades{}, sessions{}, flags{}, notes{}` |
| `RT.saveCampaign()` | Persist; also copies current credits from the ship |
| `RT.flag(name)` / `RT.flag(name, value)` | Read / write-and-save a story flag |
| `RT.note(text)` | Append a short campaign log line |
| `RT.completeSession(id, outcome, note)` | Record "success" / "partial" / "failed" and save |
| `RT.spawnPlayer(x, y, heading)` | Create the crew's ship with all purchased upgrades re-applied; sets `RT.player` |
| `RT.credits()`, `RT.addCredits(n, reason)` | Currency = player reputation points; logged and saved |
| `RT.UPGRADES`, `RT.hasUpgrade(id)`, `RT.grantUpgrade(id, reason)` | Upgrade table (id, name, cost, desc, requires, apply) and free story rewards |
| `RT.station{template, faction, callsign, x, y, shop, flavor, description}` | Station using the campaign comms menu (shipwright if `shop`, missile restock, "any news?") |
| `RT.addStationHook(callsign, fn(source, target, info))` | Add session-specific comms replies to a station's menu |
| `RT.setObjective(text)` | Show the job on Relay/Operations, log it, emit an `objective` event |
| `RT.hail(entity, text, speaker)` | Hail the player; falls back to the ship's log if comms are busy |
| `RT.find(callsign)`, `RT.register(entity, callsign)` | Callsign lookup with a registry |
| `RT.after(seconds, fn, name)`, `RT.cancelTimer(name)` | Scenario-time timers |
| `RT.valid(e)`, `RT.dist(a, b)`, `RT.cleanText(s, max)` | Helpers |
| `RT.update(delta)` | Call every frame: timers, autosave every 60 s, hull threshold events |
| `RT.addCampaignGMFunctions()` | GM buttons for credits and saving |

Upgrades are re-applied in purchase order at every session start, so each `apply(p)` must work on a fresh stock ship. To add one, append to `RT.UPGRADES`; the shipwright menu picks it up automatically.

## 1b. VERSE
`ee/ragtag/verse.lua` builds the same universe in every session: factions, suns, planets, 16 stations with their own shipwright stock, named regions with danger levels, nebulae, asteroid fields, minefields, hazards, hostile garrisons, scannable wrecks, salvage clusters, and freighter traffic. The layout comes from a fixed seed (`VERSE.SEED`), so it never moves; salvage is re-rolled per session.

Required order in `init()`: `VERSE.setupFactions()` first (before any entity uses the custom factions), then `RT.useCampaign("<campaign>")` and `RT.loadCampaign`, then `VERSE.build({session = N})` and `VERSE.requirePlaces{...}`, then session-specific objects and `RT.spawnPlayer`. Pass `campaign = "<campaign>"` in the `DIR.init` session table so the director loads `scenarios/<campaign>/bible.md`. In `update()`: `RT.update`, `VERSE.update`, `DIR.update`.

| Function / table | What it does |
|---|---|
| `VERSE.setupFactions()` | Creates Concord, Corsairs, Hollow, Relic, Unknown, Derelict and their relations |
| `VERSE.build({session, transports})` | Builds everything; `transports = false` skips traffic (testing) |
| `VERSE.at(name, dx_u, dy_u)` | World position of a named station/planet/star plus an offset in units. Use this instead of hard-coded coordinates |
| `VERSE.places[name]` | `{x, y}` of every named place |
| `VERSE.regionAt(x, y)` | Region record `{name, danger, desc}` (smallest containing region wins) |
| `VERSE.region` | The crew's current region |
| `VERSE.spawnCluster(x, y, tier, VERSE.rng_live)` | Drop a salvage cluster (tier 0–3) |
| `VERSE.spawnPod(x, y, value, kind, tier)` | One pod |
| `VERSE.spawnTransport(route, VERSE.rng_live, station)` | Add a freighter on a route |
| `VERSE.STATIONS / REGIONS / GARRISONS / SALVAGE / ROUTES / RUMORS / LORE` | Data lists, filled by `VERSE.extend` from `verse/drift.lua` and `verse/extensions/*.lua` (see `verse/schema.lua`) |
| `VERSE.requirePlaces{...}` | Declare the universe places a scenario depends on (GM warning if missing; `tools/check.py` enforces) |

Map facts for writing sessions: Port Vesper is at (0, 0). The Core is to the north-west, the Border around the origin, the Rim and Shroud to the east, the Gauntlet and Blackwater to the south, the Boneyard to the north, and the Maw far south-east. Danger: 0 safe, 1 risky (the Gauntlet, the Deep Shroud), 2 dangerous (Blackwater, the Boneyard), 3 deadly (the Maw). Session content should use `VERSE.at(...)` positions in the region the story needs, and must not place story-critical objects inside a garrison's defend radius unless the fight is the point.

Events VERSE emits: `region_entered` {region, danger, first_visit}, `transport_destroyed` {callsign, route, by, region}, `wreck_scanned`, `pickup` (with kind, value, tier, region).

Factions available to sessions: player "Independent"; "Concord" (law, neutral); "Corsairs" (pirates, hostile); "Hollow" (deadly raiders, hostile to everyone); "Relic" (war drones, hostile to everyone); "Unknown" (silent watchers, neutral); "Derelict" (dead hulls). Don't use the stock Human Navy/Exuari/Ghosts factions in campaign sessions.

## 2. DIR
| Function | What it does |
|---|---|
| `DIR.init(session)` | Start the mailbox and send `session_start`. Call at the end of `init()` |
| `DIR.defineBeat(id, {desc, ai, fn(source)})` | A story beat. `ai = true` lets the director choose when to fire it |
| `DIR.fireBeat(id, source)` | Fire once; source is "script", "fallback", "gm" or "ai". Returns ok, msg |
| `DIR.beatFired(id)` | Has it fired? Use for fallbacks |
| `DIR.emit(type, data, priority)` | Send an event. "high" = director reacts now; "normal" batches; "low" for ticks |
| `DIR.addStateProvider(fn)` | Return a table merged into the state's `extra` (phase, choices, counters) |
| `DIR.allowControl(entity)` | The director may hail as / give orders to this NPC |
| `DIR.npcComms` | Comms function that turns "Who are you? / What do you want? / Any work?" into `npc_hailed` events. Set `DIR.npc_info[callsign] = {greeting=..., role=...}` |
| `DIR.config` | `max_ai_hostiles`, `spawn_cooldown`, `glitch_cooldown`, `credit_cap_per_action`, `credit_cap_per_session`, `tick_minutes`, `allowed_factions`, `hostile_factions` |
| `DIR.GROUPS` | Ship templates per strength (scout/light/medium/heavy) |
| `DIR.enabled` | Set false (Director=Off setting) to skip the mailbox entirely |
| `DIR.update(delta)` | Call every frame |

**The session dictionary** passed to `DIR.init` is the director's briefing: `id, title, premise, tone, cast{name, where, role, voice}, locations{name, note}, director_guidance`. Make `where` the exact callsign of the character's ship or station so the director's `say` actions arrive as real hails. `director_guidance` should name the ai beats, roughly when to fire them, and what to avoid.

**Events the framework emits:** `region_entered`, `transport_destroyed`, `wreck_scanned`, `session_start`, `objective`, `beat`, `upgrade`, `player_damaged` (75/50/25%), `comms_ask` (station "any news?"), `npc_hailed`, `destroyed` (director-spawned and ambush ships), `pickup`, `gm_request` (GM buttons), `tick`, plus whatever the session emits. Conventions for session events: `choice` with `{beat, choice}` for player decisions, `session_end` with `{session, outcome, note, flags, credits}`.

**Built-in GM buttons:** AI twist / escalate / ease off / chatter (emit `gm_request`), pause/resume (refuses model actions in-game), status.

## 3. Mailbox protocol
Two ScriptStorage keys, each written by exactly one side, both JSON strings:

`rt.from_scenario` (scenario writes, ~1/s when changed and every 3 s):
```
{proto: 1, run: "s1-123-456", seq, events: [{id, t, type, data, pri}], cmd_ack, results: [{id, action, ok, msg}], state: {...}}
```
`rt.from_director` (director writes every poll):
```
{proto: 1, run, hb, event_ack, paused, cmds: [{id, action, args, source: "llm"|"gm"}]}
```
- `run` changes on every scenario start; the director resets its counters when it sees a new one, and the scenario ignores director messages for other runs.
- Events stay in `from_scenario` until acknowledged (`event_ack`); commands stay in `from_director` until acknowledged (`cmd_ack`). Both are idempotent by id.
- `hb` changing tells the scenario the director is alive (GM gets "AI director connected/offline").
- `/exec.lua` reads: `return getScriptStorage():get("rt.from_scenario") or ""`. Writes: `getScriptStorage():set("rt.from_director", "<escaped json>") return "ok"`. See `director/ee_link.py` for string escaping.

## 4. Adding a new director action
1. Lua: `DIR.ACTIONS.my_action = function(args, cmd) ... return true, "message" end` in ee/ragtag/director.lua (or in a session file, for a session-only action). Validate and clamp every argument; return `false, "reason"` instead of erroring. Check `cmd.source == "gm"` for GM-only actions.
2. Python: add a matching `Action(...)` to `director/actions.py` with argument specs and help text. Set `llm_allowed=False` for GM-only actions. The help text is what the model sees, so say when to use it.
3. Test with `tools/smoke_test.py` (add a case) against a headless server.

Session-only actions are fine: an unknown action just fails with "unknown action" in other sessions, and the model sees the failure. But it is cleaner to express session-specific moves as `ai = true` beats.
