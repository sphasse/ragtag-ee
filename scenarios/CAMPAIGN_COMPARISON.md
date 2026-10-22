# Campaign Comparison: Sandbox vs Long Haul

## Quick Comparison

| Feature | Sandbox | Long Haul |
|---------|---------|-----------|
| **Story** | None—you make your own | 5-session narrative arc |
| **Structure** | Open-ended | Scripted beats + AI improvisation |
| **Objectives** | Whatever you want | Missions with specific goals |
| **Length** | Flexible (30min - 3hr) | 45-75 min per session |
| **Best For** | Learning, exploring, experimenting | Narrative experience, character arcs |
| **Replay Value** | High—different every time | Medium—story is the same, choices vary |
| **AI Director** | Optional, creates dynamic content | Required for best experience |
| **Campaign Save** | Credits + upgrades persist | Credits + upgrades + story flags |
| **Starting Location** | Port Vesper (safe) | Port Vesper (scripted introduction) |
| **Ending** | When you dock and call it | Scripted conclusion per session |

## Sandbox Campaign

### What You Get
- **Open universe**: All 16 stations, 17 regions accessible
- **Dynamic encounters**: AI director creates content based on location and actions
- **Flexible sessions**: Play for 30 minutes or 3 hours, end when you want
- **Your narrative**: Crew decides goals, AI supports their choices
- **Persistent progress**: Credits and upgrades carry between sessions
- **Safe learning**: Start in safe zones, explore dangerous areas as you upgrade

### Session Structure
1. Start docked at Port Vesper
2. Buy upgrades (if you have credits)
3. Undock and do whatever you want:
   - Explore stations
   - Hunt salvage
   - Trade cargo
   - Fight Corsairs
   - Follow rumours
   - Investigate mysteries
4. Dock when done, GM ends session
5. Next session: pick up where you left off

### Best For
- **First-time crews**: Learn controls without story pressure
- **Between campaigns**: Stay in the universe between story arcs
- **Casual play**: No commitment to multi-session story
- **Experimentation**: Test ship builds, try combat, explore freely
- **GM practice**: Learn the AI director without scripted timing

### Example Session
"The crew starts at Port Vesper, hears a rumour about salvage in the Gauntlet. They buy hull plating, fly there, fight two Corsair scouts, recover 180 credits in salvage, then limp to Halcyon Rest for repairs. Session ends; next week they continue from Halcyon Rest with their new credits."

## Long Haul Campaign

### What You Get
- **5-session story**: "Cold Cargo" (built) → "Salvage Rights" → "The Arbiter Line" → "Old Debts" → "Last Light" (planned)
- **Character arcs**: Recurring NPCs (Mags, Lt. Vashti, Grinning Teeth, Doc Salo)
- **Meaningful choices**: Decisions in session 1 affect sessions 2-5
- **Mystery plot**: Uncover secrets of the Meridian colony fleet
- **Scripted moments**: Key story beats happen, but AI improvises details
- **Epic conclusion**: Session 5 is a finale with callbacks to all earlier choices

### Session Structure (Example: Session 1)
1. Docked at Port Vesper, Mags offers a job (scripted)
2. Load cargo, fly to Halcyon Rest
3. CPV Diligence demands inspection (AI-timed, fallback if AI off)
4. Choice: submit, bribe, or run (flags set: affects sessions 2-5)
5. Corsair ambush en route (AI-timed)
6. Optional: explore the Shroud, find Wren's Folly derelict
7. Deliver cargo to Halcyon Rest (scripted payout)
8. Session ends, credits + story flags saved

### Best For
- **Narrative players**: Want a story with stakes and payoff
- **Committed groups**: Can do 5 sessions over weeks/months
- **Character investment**: Want to care about NPCs
- **Surprising AI direction**: Scripted structure + improvised details
- **Firefly fans**: Ragtag crew, scrappy ship, moral choices

### Example Session
"In Session 4, Grinning Teeth (the Corsairs from session 1) have taken Doc Salo hostage because Mags betrayed the crew (if `mags_knows` flag is set from session 1). The crew must rescue him from an asteroid hideout. If they befriended Rook in session 2 (`rook_relation == "partner"`), she arrives to help. After rescuing Salo, he reveals the first major secret: the 'lanterns' are Meridian fleet beacons."

## Which Should You Play First?

### Start with Sandbox if:
- ✅ Your group is new to EmptyEpsilon
- ✅ You want to learn the universe without time pressure
- ✅ You're testing the AI director for the first time
- ✅ You like open-ended gameplay
- ✅ You're not sure about a 5-session commitment

### Start with Long Haul if:
- ✅ Your group has played EmptyEpsilon before
- ✅ You want a narrative experience with stakes
- ✅ You can commit to 5 sessions (~6 hours total)
- ✅ You like Firefly-style scrappy-crew stories
- ✅ You want to see what the framework can do at full power

### Do Both!
Recommended progression:
1. **Sandbox Session 1-2**: Learn the universe, controls, AI director
2. **Long Haul Sessions 1-5**: Play the story campaign
3. **Sandbox**: Return for more open play with your upgraded ship

Or:
1. **Sandbox**: Play until comfortable (~3-5 sessions)
2. **Long Haul**: Jump into the story campaign
3. **Custom Campaign**: Create your own story using the framework

## AI Director Differences

### Sandbox Director
- **Role**: Creates dynamic content based on crew actions
- **Guidance**: "React to what the crew does and where they go"
- **Freedom**: High—AI invents encounters, opportunities, mysteries
- **Beats**: All AI-timed (no scripted fallbacks except session start)
- **Prompt**: Universe description + sandbox bible (open-ended)

### Long Haul Director
- **Role**: Voices NPCs, times story beats, adds improvised details
- **Guidance**: "Fire inspection when near Diligence; keep fights small"
- **Freedom**: Medium—scripted structure, AI fills in details
- **Beats**: Mix of scripted + AI-timed (with fallbacks)
- **Prompt**: Universe + story bible + session-specific cast/guidance

Both use the same director code and same LLM. The difference is how much structure the scenario provides.

## Campaign Saves

Both use `RT.useCampaign(<name>)` to keep saves separate:

- **Sandbox**: `ragtag.campaign.sandbox` in `scriptstorage.json`
- **Long Haul**: `ragtag.campaign.longhaul` in `scriptstorage.json`

You can have both campaign saves at once. Play sandbox on Mondays, Long Haul on Fridays—they won't interfere.

## Creating Your Own Campaign

Both are templates:

**From Sandbox:**
1. Copy `scenarios/sandbox/` to `scenarios/mycampaign/`
2. Edit `bible.md` with your story context
3. Add custom beats in `defineBeats()`
4. Adjust AI director guidance for your narrative

**From Long Haul:**
1. Follow `scenarios/longhaul/plan.md` structure
2. Use `scenarios/_template/` as starting point
3. Build 1-5 session story arcs
4. Mix scripted + AI-timed beats

## Summary

**Sandbox** = "Explore a living universe and make your own fun"  
**Long Haul** = "Play through a Firefly-style 5-session story"

Both use the same universe, same ship progression, same AI director technology. Pick based on your group's preferences and commitment level.

Can't decide? Start with Sandbox Session 1. If your group loves the universe and wants more structure, switch to Long Haul Session 1. If they love the freedom, stick with Sandbox.

Have fun! 🚀
