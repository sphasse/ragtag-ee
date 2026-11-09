---
name: sandbox-missions
description: Add or extend a story arc in the ragtag sandbox campaign using the MISSIONS phase-machine engine. Use for new arc modules, extending or debugging existing arcs (Witness, Rezkov), or understanding how the arc engine works. For scenario writing, job types, universe extensions, proximity spawns, or core campaign changes, use the empty-epsilon-scenarios skill instead.
---

# Adding a story arc (sandbox-missions)

**Read `references/missions_api.md` now.** It is the authoritative reference.
**Note**: this file is also kept in `.claude/skills/empty-epsilon-scenarios/references/missions_api.md` — update both when it changes.
The reference implementation is `ee/ragtag/missions/rezkov.lua`; design notes live in `ee/ragtag/missions/rezkov.md`.

---

## Quick start

1. Create `ee/ragtag/missions/<name>.lua`.
2. Create `ee/ragtag/missions/<name>.md` — design notes, state diagram, lore. Arc-specific details go here; don't add them to CLAUDE.md.
3. Add `require("ragtag/missions/<name>.lua")` to `ee/ragtag/missions.lua`.
4. Run `python tools/check.py` after any change.

That's the entire integration surface. The arc is self-contained; core gameplay (jobs board, proximity spawns, reputation) keeps working while it's inactive.

---

## What belongs in the arc module

- Phase definitions with `enter`, `update`, `exit` functions
- Trigger conditions (rep thresholds, upgrade totals, flags)
- GM skip buttons via `M.gm_actions`
- World objects spawned in `enter`, cleaned up in `on_cancel`
- State mutations via `RT.flag`, `RT.addReputation`, `RT.addCredits`

## What does NOT belong in the arc module

- Changes to `ee/ragtag/jobs/` or the JOBS board — use a job module
- Changes to `ee/ragtag/world/` plugins — use a WORLD plugin
- Changes to `verse/drift.lua` or extensions — use a verse extension
- Logic in scenario `update()` or `init()` beyond the three MISSIONS wiring calls

---

## Interaction with other layers

- **Suspend the job board** while the arc is active: set `M.locks_jobs = true`.
- **Add a rumor as an arc hook**: `RUMORS.add({text=..., once=true, priority=5})` from an `enter` function.
- **Proximity spawn suspension**: the Witness arc sets `S.witness_active = true` to suspend all proximity spawns. If your arc also needs to suppress spawns, coordinate with that flag or add a parallel one the scenario exposes.
- **Cross-session state**: `RT.flag(name, true)` to persist, `RT.clearFlag(name)` to clear. Never use `RT.flag(name, nil)` to clear — that is a read, not a write.

---

## Common mistakes

- **`MISSIONS.goto()` doesn't exist** — `goto` is a Lua 5.4 reserved keyword. Use `MISSIONS.phase()`.
- **`RT.flag("x", nil)` is a no-op read** — it does not clear the flag. Use `RT.clearFlag("x")`.
- **Not cleaning up in `on_cancel`** — world objects persist across GM restarts.
- **Double-registering station hooks** — if the GM restarts the arc in the same session, hooks fire twice. Guard with a file-level `_hook_registered` boolean.
- **Forgetting the require** — if `ee/ragtag/missions.lua` doesn't require your file, the arc never loads and no error is thrown.

---

## Checklist before shipping

- [ ] `M.on_cancel` destroys all spawned objects
- [ ] Every GM skip action calls a `_clearState()` helper first (idempotent skips)
- [ ] `RT.after` timers cancelled in `exit` if they shouldn't fire after the phase ends
- [ ] Arc triggers use `not_flagged` to prevent re-triggering after completion
- [ ] Design doc exists at `ee/ragtag/missions/<name>.md`
- [ ] `python tools/check.py` passes
