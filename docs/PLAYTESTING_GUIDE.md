# Playtesting Guide — Sandbox Campaign

Guide for systematically testing the ragtag-ee sandbox campaign experience.

---

## Prerequisites

### Required:
- EmptyEpsilon 2024+ (ECS engine)
- ragtag-ee installed (`python tools/install.py --ee <path>`)
- `httpserver=8080` in `options.ini`
- 2-6 players (or solo with multiple stations)
- 30-90 minutes per test session

### Optional:
- AI Director running (`cd director && python main.py`)
- Second monitor for GM console
- Screen recording software for bug reports

---

## Setup Checklist

Before each test session:

1. **Fresh or Continue?**
   - Fresh start: Clean slate, test early-game balance
   - Continue: Test progression, reputation effects, upgrades

2. **Settings:**
   - Campaign: Continue (recommended for longer tests)
   - Starting Credits: Comfortable (500cr) for normal testing
   - Difficulty: Normal (unless testing difficulty scaling)
   - Director: On (if AI is running)

3. **GM Console:**
   - Note starting credits and reputation
   - Have GM guide open: `docs/GM_GUIDE.md`

4. **What You're Testing:**
   - Pick 1-3 systems to focus on per session (see test areas below)
   - Don't try to test everything at once

---

## Test Session Types

### Quick Test (15-30 min)
**Goal:** Smoke test — does it work at all?

1. Start at Port Vesper
2. Hail for work
3. Accept one mission (any type)
4. Complete or fail the mission
5. Dock somewhere and end session

**Look for:**
- LUA-Error messages in console
- Mission generation failures
- Station/ship spawning issues
- Obvious UI problems

---

### Short Session (30-60 min)
**Goal:** Test one system deeply

Pick ONE focus area:
- **Missions:** Run 2-3 missions of the same type
- **Proximity spawns:** Visit 3-4 different danger zones
- **Reputation:** Do actions that affect one faction
- **Upgrades:** Buy 2-3 upgrades, test effectiveness

**Look for:**
- System-specific bugs
- Balance issues (too easy/hard)
- Reward scaling (mission payouts vs. upgrade costs)

---

### Full Session (60-120 min)
**Goal:** Complete gameplay loop

1. Start with modest credits
2. Run 3-5 missions across different types
3. Buy 2-4 upgrades
4. Visit safe, risky, and dangerous zones
5. Trigger at least one proximity spawn
6. End session docked with savings

**Look for:**
- Progression pacing (can you afford upgrades?)
- Difficulty curve (does danger scale appropriately?)
- Session flow (too grindy? too easy?)
- Variety (does it feel repetitive?)

---

## System-by-System Testing

### 1. Mission System

#### Delivery Missions (1.0x pay)
- [ ] Mission generates at station
- [ ] Target station shows on map
- [ ] Grid coordinates match destination
- [ ] Log message includes station name + grid
- [ ] Pay scales with distance (check 10U vs 30U missions)
- [ ] Pay scales with danger (check safe vs. dangerous destinations)
- [ ] Completion registers correctly

**Edge cases:**
- Accept mission to distant station, then dock there without traveling
- Accept 2 missions, complete in wrong order
- Fly past destination without docking

---

#### Salvage Missions (1.2x pay)
- [ ] Cargo pod spawns at mission accept
- [ ] Pod visible on Science scanner
- [ ] Pod has correct cargo name as callsign
- [ ] Pickup triggers log message
- [ ] Objective updates to "Return to [origin]"
- [ ] Return and completion works

**Edge cases:**
- Destroy the cargo pod (does mission fail gracefully?)
- Pick up pod, then dock at wrong station
- Two salvage missions active at once

---

#### Hacking Missions (1.4x pay)
- [ ] Relay beacon spawns at mission accept
- [ ] Beacon visible on Science scanner
- [ ] Relay jamming destroys probes within 5U
- [ ] Hacking any system to 75% completes mission
- [ ] Log message confirms breach + system name
- [ ] Return and completion works

**Edge cases:**
- Destroy the relay (does mission fail?)
- Hack to 74% and leave (mission should persist)
- Launch 10 probes to test jamming performance

---

#### Destroy Missions (1.6x pay)
- [ ] Target spawns at mission accept
- [ ] Target has creative Corsair name
- [ ] Log shows target name + heading toward [station]
- [ ] Target flies toward the logged destination (verify!)
- [ ] Target switches to Corsairs at 8U and attacks
- [ ] Destroying target completes mission
- [ ] Return and completion works

**Edge cases:**
- Board target instead of destroying (should fail)
- Target reaches destination and docks (what happens?)
- Destroy target before getting within 8U (should still complete)

---

#### Boarding Missions (1.8x pay)
- [ ] Target spawns at mission accept
- [ ] Target flies toward destination
- [ ] Target switches to Corsairs at 8U
- [ ] Disabling target (impulse to 0%) allows boarding
- [ ] Boarding triggers log message + objective update
- [ ] Return and completion works
- [ ] Pay is highest of all mission types

**Edge cases:**
- Destroy target instead of boarding (should fail)
- Board target with impulse at 10% (does it work?)
- Disable but don't board, fly away (mission should persist)

---

### 2. Proximity Spawn System

#### Safe Zones (Vesper Drift, Core)
- [ ] No spawns within 20U of stations
- [ ] Concord shake-downs in Arbiter Line / Core
- [ ] Shake-down offers 3 choices (submit, declare, refuse)
- [ ] Submit: 30s scan, fine if rep < 0
- [ ] Declare: dismissed if rep ≥ +10, fine otherwise
- [ ] Refuse: wanted flag set, Concord attacks
- [ ] Shake-down log message mentions opening comms

**Edge cases:**
- Get wanted flag, then return to Core (immediate attack?)
- Submit with negative Concord rep (correct fine calculation?)
- Two shake-downs in one session

---

#### Risky Zones (Gauntlet, Shroud)
- [ ] Corsairs spawn after ~90s in zone
- [ ] Scout/light groups in safe areas
- [ ] Medium groups if you have 2-4 upgrades
- [ ] Ships attack on sight (no comms)
- [ ] Ships recall when you leave region
- [ ] Ships despawn after 120s if you don't return

**Edge cases:**
- Enter Gauntlet, immediately leave (ships should recall)
- Kill one ship of a group, leave region (what happens to survivors?)
- High Corsair rep (+25) — longer spawn cooldowns?

---

#### Dangerous Zones (Blackwater, Boneyard)
- [ ] Heavier spawn groups
- [ ] Boneyard has Relic drones (WX-Lindworm, Stalker)
- [ ] Relic drones attack on sight, no comms
- [ ] Station exclusion zones work (no spawns near stations)
- [ ] Multiple spawn groups possible if you stay long

**Edge cases:**
- Fly through Boneyard at max warp (do spawns trigger?)
- Low Corsair rep (-25) — shorter spawn cooldowns?

---

#### Deadly Zone (The Maw)
- [ ] Hollow ships spawn
- [ ] Heavy groups even with few upgrades
- [ ] Attack on sight, no comms
- [ ] Turn-back warnings present

---

### 3. Reputation System

#### Gaining Reputation
- [ ] Complete mission: +10 to origin station's faction
- [ ] Destroy Corsair: +10 Concord (if in their space?)
- [ ] Multiple missions to same faction stack

#### Losing Reputation
- [ ] Destroy Concord ship: -10 Concord
- [ ] Destroy Corsair: -10 Corsairs
- [ ] Destroy Independent: -10 Independent
- [ ] Refuse Concord shake-down: wanted flag

#### Reputation Effects
- [ ] Corsairs >+20: Longer spawn cooldowns (fewer encounters)
- [ ] Corsairs <-20: Shorter cooldowns (more encounters)
- [ ] Concord >+20: Shake-downs dismissed, no fine
- [ ] Concord <-20: Immediate attack in their zones
- [ ] Wanted flag: Concord always hostile in their zones

**Test sequence:**
1. Note Corsair rep
2. Complete 3 missions from Corsair-aligned station (if any exist — actually none, all are Independent/Concord)
3. Actually: destroy 3 Corsair ships to lose rep
4. Check spawn frequency in Gauntlet (should increase)

---

### 4. Upgrade System

#### Credits vs. Upgrade Costs
- [ ] Starting credits (500cr) enough for 1-2 basic upgrades
- [ ] Mission payouts scale appropriately
- [ ] Tier 2 missions (5+ upgrades) pay enough for expensive upgrades

#### Upgrade Effectiveness
- [ ] Hull plating: Survive one extra hit?
- [ ] Shield upgrades: Noticeable in combat?
- [ ] Beam/missile upgrades: Faster kills?
- [ ] Engines: Noticeable speed increase?
- [ ] Jump drive (500cr): Can reach distant regions?

**Test sequence:**
1. Run mission with stock ship, note time-to-kill enemy
2. Buy weapon upgrade
3. Run similar mission, note time-to-kill
4. Should be measurably faster

---

### 5. Witness Arc (Optional)

If testing the scripted story:

- [ ] GM can trigger "Witness: Start arc"
- [ ] Mira's message appears
- [ ] Job board disables at Port Vesper
- [ ] Proximity spawns suspend during arc
- [ ] Arc phases progress correctly
- [ ] Checkpoint presents choices
- [ ] Broadcast completes
- [ ] Payout matches outcome (300-600cr)
- [ ] Proximity spawns resume after arc
- [ ] Job board re-enables

---

## Balance Testing

### Mission Payouts
**Test:** Complete one of each mission type at similar distances/danger

| Type | Expected Multiplier | Actual Payout | Feels Fair? |
|------|---------------------|---------------|-------------|
| Delivery | 1.0x | ___cr | Y / N |
| Salvage | 1.2x | ___cr | Y / N |
| Hacking | 1.4x | ___cr | Y / N |
| Destroy | 1.6x | ___cr | Y / N |
| Boarding | 1.8x | ___cr | Y / N |

**Questions:**
- Do harder missions feel worth the extra risk?
- Can you afford upgrades at a reasonable pace?
- Do you feel pressured to grind?

---

### Difficulty Curve

| Scenario | Expected | Actual | Notes |
|----------|----------|--------|-------|
| Stock ship vs. Scout in Gauntlet | Tough but winnable | ___ | ___ |
| 2 upgrades vs. Medium group | Even fight | ___ | ___ |
| 5+ upgrades vs. Heavy group | Winnable with skill | ___ | ___ |
| Stock ship in Boneyard | Death sentence | ___ | ___ |

**Questions:**
- Does danger feel proportional to location?
- Can skilled players punch above their weight?
- Do upgrades feel meaningful?

---

### Pacing

**30-minute session:**
- Starting credits: 500cr
- Missions completed: ___
- Credits earned: ___cr
- Upgrades bought: ___
- Ending credits: ___cr

**Questions:**
- Did the session feel complete?
- Too grindy? Too easy?
- Want to play another session?

---

## Bug vs. Balance vs. Design

### It's a Bug if:
- Game crashes or throws LUA-Error
- Mission doesn't spawn or complete
- Ships spawn inside stations
- UI elements overlap or disappear
- Saved campaign doesn't load
- Math is obviously wrong (negative credits, 1000% reputation)

**Report:** File GitHub issue with steps to reproduce

---

### It's a Balance Issue if:
- Missions pay too much/little
- Upgrades too expensive/cheap
- Enemies too hard/easy for the zone
- Progression too fast/slow
- One mission type always best choice

**Report:** Note in playtesting session doc with numbers (payouts, time-to-kill, etc.)

---

### It's a Design Question if:
- Feature exists but feels wrong ("Why can't I sell cargo?")
- Missing feature you expected ("Where's the jump drive at start?")
- Unclear how something works ("How do I complete this mission?")
- Doesn't match the fiction ("Why do Corsairs attack on sight?")

**Report:** Note as feedback, explain what you expected and why

---

## Reporting Template

### Session Report

**Date:** YYYY-MM-DD  
**Duration:** ___ minutes  
**Players:** ___ (list stations)  
**Campaign:** Fresh start / Continue (session \___)  
**Focus:** (what you were testing)

**What Worked:**
- List 3-5 things that felt good
- Note positive surprises

**Issues Found:**
- **[BUG]** Description + steps to reproduce
- **[BALANCE]** Description + numbers/evidence
- **[UX]** Description + what was unclear

**Questions:**
- Things you weren't sure about
- Features you wanted but didn't find

**Overall Feel:**
- Would you play again? (Yes/No/Maybe)
- Did the session feel complete?
- One sentence summary of the experience

---

## Quick Smoke Test Checklist

Use this for rapid "does it work at all?" testing after code changes:

- [ ] Start scenario, no LUA-Error
- [ ] Spawn player at Port Vesper
- [ ] Hail Port Vesper, see welcome message
- [ ] "Any work available?" shows 2 missions
- [ ] Accept delivery mission
- [ ] Mission log appears
- [ ] Fly 10U away, no crashes
- [ ] Dock at destination
- [ ] Mission completes, credits awarded
- [ ] Undock, fly to another region
- [ ] Proximity spawn triggers (if in danger zone)
- [ ] Combat works (damage, shields, weapons)
- [ ] Dock at station, end session
- [ ] Campaign saves

If all 14 steps pass: basic systems working ✅

---

## Advanced Testing

### Stress Tests

**Mission spam:**
1. Accept 2 missions
2. Complete both rapidly
3. Accept 2 more immediately
4. Repeat 5 times in one session
5. Look for: memory leaks, slowdown, broken state

**Reputation extremes:**
1. Use GM console: set Corsairs to +100
2. Fly through Gauntlet for 10 minutes
3. Should see zero spawns
4. Set Corsairs to -100
5. Should see spawns every ~45s

**Long session:**
1. Play for 2+ hours
2. Complete 10+ missions
3. Buy 8+ upgrades
4. Visit every region
5. Look for: slowdown, broken state, save corruption

---

### Edge Cases

**Wanted flag persistence:**
1. Refuse Concord shake-down (wanted flag)
2. End session
3. Start new session (Continue)
4. Fly to Core
5. Should still be wanted, immediate attack

**Mission timer expiry:**
1. Accept mission
2. Do nothing for 20 minutes
3. Mission should expire and disappear

**Docking during combat:**
1. Start combat with Corsairs
2. Emergency dock at nearby station
3. Combat should end
4. Ships should despawn (station safety)

---

## Test Data Collection

Keep a spreadsheet tracking:

| Session | Duration | Missions | Credits Earned | Deaths | Bugs Found | Fun Rating (1-10) |
|---------|----------|----------|----------------|--------|------------|-------------------|
| 1 | 45min | 3 | 380cr | 0 | 1 | 8 |
| 2 | 60min | 5 | 640cr | 1 | 0 | 7 |

After 5+ sessions, look for patterns:
- Average credits per hour
- Mission completion rate
- Death frequency
- Common bug types

---

## When to Stop Testing

**A test session is complete when:**
1. You've covered your focus area thoroughly
2. You've documented all issues found
3. You're no longer finding new issues in that area
4. Time is up (don't burn out!)

**The system is ready for players when:**
1. Quick smoke test passes consistently
2. No critical bugs (crashes, broken missions) in 3+ full sessions
3. Balance feels reasonable (not perfect, just reasonable)
4. Players can complete a session and want another

---

## Questions for Playtesters

After each session, answer:

1. **Did you understand what to do?** (Yes/No/Mostly)
2. **Did missions feel rewarding?** (Yes/No/Sometimes)
3. **Did danger feel fair?** (Yes/No/Too easy/Too hard)
4. **Did you want to keep playing?** (Yes/No/Maybe)
5. **One thing that felt great:**
6. **One thing that frustrated you:**
7. **One thing you wanted but didn't find:**

---

## GM Notes

### Things to Watch For:

**Player confusion:**
- Not finding mission objectives
- Not understanding how to complete missions
- Not knowing where to go next
- Unclear UI elements

**Player frustration:**
- Dying repeatedly in "safe" zones
- Can't afford upgrades
- Missions feel samey
- Too much travel time

**Player boredom:**
- Always choosing same mission type
- Avoiding dangerous zones entirely
- Not engaging with systems (reputation, etc.)
- Asking "what's next?"

**Player delight:**
- Excited about narrow escapes
- Planning multi-mission routes
- Discussing upgrade strategies
- Creating their own stories

---

## Final Checklist

Before declaring "ready to play":

- [ ] 3+ full sessions with no critical bugs
- [ ] All 5 mission types work end-to-end
- [ ] Proximity spawns work in all zone types
- [ ] Reputation effects are noticeable
- [ ] Upgrades feel meaningful
- [ ] Progression pacing feels right (not too grindy)
- [ ] Witness arc can complete (if testing it)
- [ ] Campaign save/load works
- [ ] Documentation matches actual behavior
- [ ] Playtesters say "yes" to playing again

---

**Remember:** Perfect is the enemy of good. You're looking for "fun and functional," not "flawless." Ship when it's playable, iterate based on real play sessions.
