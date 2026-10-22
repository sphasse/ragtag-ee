# GM Ship Management Guide

The framework provides several GM buttons for managing the player ship's state during and between sessions. These are available in the GM screen (press `F5` in EmptyEpsilon server mode).

---

## Campaign Management Buttons

### Campaign: show status
**What it does:** Displays complete campaign state

**Output:**
```
Campaign: sandbox (or longhaul, etc.)
Ship: Magpie
Credits: 450
Upgrades (3): hull_plating, shield_mk2, repair_crew
Completed sessions: s1, sandbox_1, sandbox_2
```

**Use when:**
- Checking campaign progress
- Verifying credits and upgrades
- Debugging save issues

---

### Campaign: +200 credits
**What it does:** Awards 200 credits to the crew

**Use when:**
- Rewarding clever play
- Compensating for bugs
- Testing upgrade purchases

**Note:** Logged to ship's log as "+ 200 (GM)"

---

### Campaign: -200 credits
**What it does:** Removes 200 credits from the crew

**Use when:**
- Correcting accidental credit awards
- Applying story penalties
- Testing low-credit scenarios

**Note:** Won't go below 0 credits

---

### Campaign: save now
**What it does:** Immediately saves campaign to `scriptstorage.json`

**Output:**
```
Campaign saved. Credits: 450, Upgrades: 3
```

**Use when:**
- Before risky tests
- After manual credit/upgrade changes
- Before server shutdown
- Creating save point before story branch

**Note:** Campaign auto-saves every 60 seconds, but manual saves are instant

---

## Ship State Management Buttons

### Ship: reset to fresh (keep credits)
**What it does:**
1. Removes ALL purchased upgrades
2. Destroys current ship
3. Spawns fresh stock ship at same position
4. Keeps credits, story flags, and session history

**Output:**
```
Ship reset to stock template. Removed 3 upgrades. Credits preserved: 450
```

**Use when:**
- Testing scenarios with stock ship
- Resetting after upgrade testing
- Player wants to reallocate upgrade purchases (refund first via credits button)
- Debugging upgrade interactions

**Warning:** Irreversible (unless you saved beforehand). All upgrades are removed from campaign save.

---

### Ship: full repair + refuel
**What it does:**
1. Repairs hull to maximum
2. Restores shields (front and rear)
3. Refills energy
4. Restocks all missiles
5. Repairs all systems to 100%
6. Clears all system heat

**Output:**
```
Ship fully repaired and refueled: Hull, shields, energy, missiles, and all systems restored.
```

**Use when:**
- After testing combat
- Between story beats without docking
- Compensating for unfair encounter
- Starting a new session with full resources
- Testing ship capabilities at full strength

**Note:** Does NOT change upgrades or credits

---

### Ship: snapshot current state
**What it does:**
1. Records current hull % (e.g., 45% of max)
2. Records current shield levels (front/rear %)
3. Records current energy %
4. Records position and heading
5. Saves to campaign file

**Output:**
```
Ship snapshot saved: Hull 45%, Shields 60/80%, Energy 70%, Position recorded.
```

**Use when:**
- Before testing something dangerous
- Creating a save point mid-session
- Before GM experiments
- Setting up a specific scenario state

**How it works:**
- Saves percentages, not absolute values
- When restored, applies percentages to current max values
- If ship has been upgraded since snapshot, restores work correctly
- Example: Snapshot at 50% hull with 100 max → Upgrade to 150 max → Restore = 75 hull (50% of 150)

---

### Ship: restore from snapshot
**What it does:**
1. Restores hull to snapshot %
2. Restores shields to snapshot %
3. Restores energy to snapshot %
4. Moves ship to snapshot position
5. Restores heading

**Output:**
```
Ship restored from snapshot: Hull 45%, Shields 60/80%, Energy 70%
```

**Use when:**
- Reverting after test
- Retrying from save point
- Undoing accidental damage
- Testing scenario from specific state

**Note:**
- Requires prior snapshot
- If no snapshot exists, shows error: "No snapshot saved. Use 'Ship: snapshot current state' first."
- Does NOT restore upgrades or credits (those are in campaign save, not snapshot)

---

## Common Workflows

### Testing a Dangerous Encounter
1. **Ship: snapshot current state** (save point)
2. Test the encounter
3. If it goes badly: **Ship: restore from snapshot**
4. Adjust encounter and test again

---

### Giving Players a Fresh Start
1. **Campaign: show status** (note current upgrades/credits)
2. **Ship: reset to fresh (keep credits)**
3. Players can re-purchase different upgrades

---

### Quick Session Setup
Before starting:
1. **Campaign: show status** (verify save loaded correctly)
2. **Ship: full repair + refuel** (start with full resources)
3. **Campaign: save now** (create checkpoint)

---

### Testing Upgrades
1. **Campaign: +200 credits** (or more, as needed)
2. Dock at station, buy upgrade via Relay menu
3. Test upgrade in combat
4. If you want to undo: **Ship: reset to fresh (keep credits)**, redock, re-purchase different upgrade

---

### Creating a Save Point Before Story Branch
1. **Campaign: save now** (checkpoint campaign: credits, upgrades, flags)
2. **Ship: snapshot current state** (checkpoint ship: hull, shields, position)
3. Play story beat with choices
4. If you want to retry: **Ship: restore from snapshot**, manually revert story flags if needed

---

## Technical Details

### What's Persisted in Campaign Save
- **Credits** (auto-saves every 60s)
- **Upgrades** (list of upgrade IDs, applied at session start)
- **Story flags** (RT.flag calls)
- **Session history** (which sessions completed)
- **Ship name**
- **Notes** (campaign log)
- **Ship snapshot** (if taken)

**Location:** Server's `scriptstorage.json`, key `ragtag.campaign.<campaign_id>`

**Example:**
- Sandbox: `ragtag.campaign.sandbox`
- Long Haul: `ragtag.campaign.longhaul`

### What's NOT in Campaign Save
- Current hull/shields/energy (except snapshot)
- System damage (except snapshot)
- Ship position (except snapshot)
- Missile counts (except via full max on session start)

### How Upgrades Work Between Sessions
1. Session 1: Buy "hull_plating" and "shield_mk2"
2. Campaign save stores: `upgrades: ["hull_plating", "shield_mk2"]`
3. Session 2 starts: `RT.spawnPlayer()` creates fresh stock ship
4. Applies "hull_plating" (hull +50)
5. Applies "shield_mk2" (shields to 100/100)
6. Result: Ship has both upgrades as if just purchased

**This is why "Ship: reset to fresh" is safe** — next session will re-apply upgrades from save.

### Snapshot vs Campaign Save
- **Campaign save**: Persists between scenarios, survives restarts
- **Snapshot**: Only exists during current scenario run, lost on scenario end
- Use snapshot for: mid-session save points, testing
- Use campaign save for: between-session persistence

---

## Troubleshooting

### "No player ship to [action]"
**Problem:** Player ship doesn't exist or was destroyed  
**Fix:** Scenario must create player ship first (happens in `init()`)

### "No snapshot saved"
**Problem:** Trying to restore without creating snapshot first  
**Fix:** Use "Ship: snapshot current state" before "Ship: restore from snapshot"

### Upgrades don't persist between sessions
**Problem:** Scenario not calling `RT.loadCampaign()` or using different campaign ID  
**Fix:** Check scenario's `RT.useCampaign("<id>")` matches between sessions

### Credits reset to default
**Problem:** Campaign save not loading  
**Fix:**
1. Check `scriptstorage.json` exists (server's EmptyEpsilon folder or `~/.emptyepsilon/`)
2. Verify scenario calls `RT.loadCampaign(false)` not `RT.loadCampaign(true)` (true = fresh)
3. Use "Campaign: show status" to verify save loaded

### Ship snapshot restores wrong values
**Problem:** Snapshot taken with different upgrade set  
**Fix:** This is expected — snapshot stores percentages, not absolutes. If you upgrade hull from 100→150 after snapshot, 50% = 75 hull instead of 50 hull.

---

## GM Button Reference Card

| Button | Effect | Saves? |
|--------|--------|--------|
| **Campaign: show status** | Display credits, upgrades, sessions | No |
| **Campaign: +200 credits** | Award 200 credits | Yes |
| **Campaign: -200 credits** | Remove 200 credits | Yes |
| **Campaign: save now** | Manual save | Yes |
| **Ship: reset to fresh (keep credits)** | Remove all upgrades, respawn stock ship | Yes |
| **Ship: full repair + refuel** | Restore hull, shields, energy, missiles, systems | No |
| **Ship: snapshot current state** | Save current ship state (%, position) | Yes |
| **Ship: restore from snapshot** | Load snapshot state | No |

**"Saves?" = Writes to `scriptstorage.json` campaign save**

---

## Advanced: Manual Save File Editing

**Location:** Server's `scriptstorage.json`

**Structure:**
```json
{
  "ragtag.campaign.sandbox": "{\"version\":1,\"ship_name\":\"Magpie\",\"credits\":450,\"upgrades\":[\"hull_plating\",\"shield_mk2\"],\"sessions\":{\"sandbox_1\":{\"outcome\":\"success\",\"at\":3600}},\"flags\":{},\"notes\":[],\"discovered\":{}}"
}
```

**To manually edit:**
1. Stop EmptyEpsilon server
2. Open `scriptstorage.json`
3. Find key `ragtag.campaign.<your_campaign>`
4. Value is JSON-encoded string (note the escaped quotes)
5. Decode JSON string to object
6. Edit fields (e.g., add upgrade IDs, change credits)
7. Re-encode to JSON string
8. Save file
9. Restart server

**Easier method:** Use GM buttons — they handle JSON encoding correctly.

---

## For Modders: Adding Your Own GM Buttons

See `ee/ragtag/core.lua` function `RT.addCampaignGMFunctions()` for examples.

**Pattern:**
```lua
addGMFunction("Button Label", function()
    -- Your code here
    -- Use RT.campaign, RT.player, RT.saveCampaign()
    addGMMessage("Result message shown to GM")
end)
```

**Tips:**
- Check `RT.valid(RT.player)` before ship operations
- Call `RT.saveCampaign()` after modifying `RT.campaign.*`
- Use `addGMMessage()` to report results
- Group related buttons with prefixes (e.g., "Campaign:", "Ship:", "Debug:")
