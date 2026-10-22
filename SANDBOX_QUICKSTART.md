# Sandbox Campaign - Quick Start

## What Is This?

An **open-play EmptyEpsilon scenario** for exploring the ragtag universe with no fixed story. Perfect for:
- First-time crews learning EmptyEpsilon
- Getting oriented to the Drift setting before starting story campaigns
- Experimenting with the AI director
- Just having fun flying a spaceship with friends

## The 5-Minute Setup

### 1. Game Server PC
```bash
# Install the scenarios
python tools/install.py --ee /path/to/EmptyEpsilon

# Enable HTTP API in options.ini:
httpserver=8080

# Start EmptyEpsilon as server
# Select scenario: "Sandbox: Open Play"
```

### 2. AI PC (Optional but Recommended)
```bash
# Install Ollama (or another local LLM server)
ollama pull qwen2.5:14b  # or any 8B-14B instruction model

# Set context length (important!)
export OLLAMA_CONTEXT_LENGTH=8192

# Configure director
cd director
cp config.example.toml config.toml
# Edit config.toml: set [ee] url to game server IP, [llm] model to your model

# Run director
python main.py

# Open web console
# http://<ai-pc-ip>:8765
```

### 3. Players Connect
Crew connects to stations as usual. Start docked at Port Vesper with a modest ship and some credits.

## What to Expect

### First Session (1-2 hours)
- Learn the controls and stations
- Get welcomed by Port Vesper dockmaster
- Buy your first upgrade (hull plating or shields)
- Explore nearby safe zones (Border, Rim)
- Try some salvage in asteroid fields
- Maybe encounter some Corsair scouts
- Dock at another station, end session

### Later Sessions
- Credits and upgrades carry over
- Explore more dangerous regions (better salvage)
- The AI director remembers your choices
- Build your own narrative through actions
- Get powerful enough to visit deadly zones

## Files Created

```
scenarios/sandbox/
├── scenario_80_sandbox.lua     # Main scenario (already validated)
├── bible.md                    # Story context for AI director
├── README.md                   # Campaign overview
└── GM_GUIDE.md                 # Detailed GM reference
```

## Testing Status

✅ **Validated**: `python tools/check.py` passes (0 errors, 0 warnings)  
✅ **Syntax**: Lua syntax is correct  
⚠️ **Not tested**: Headless run (requires EmptyEpsilon installation)

## Recommended Settings for First Session

- **Campaign**: Fresh start
- **Starting Credits**: Comfortable (500)
- **Danger Level**: Relaxed
- **Director**: On (if you have the AI PC set up)

## Quick AI Director Instructions

Once the web console is open, try:
- "Have a freighter captain offer a delivery job"
- "Spawn some salvage in a nearby asteroid field"
- "Create a mystery: a derelict with a strange signal"
- "A Concord patrol hails asking about suspicious activity"

Or use quick buttons: **Opportunity**, **Encounter**, **Salvage**

## The Universe At A Glance

**Safe Zones** (start here):
- The Core: Rich Concord stations, expensive upgrades
- The Border: Port Vesper, independent traders
- The Rim: Frontier stations, good variety

**Risky Zones** (2-3 upgrades needed):
- The Gauntlet: Corsair ambush territory, good salvage
- The Shroud: Nebula with mysteries

**Dangerous Zones** (5+ upgrades needed):
- Blackwater Reach: Corsair haven
- The Boneyard: War drones guard wrecks

**Deadly Zone** (avoid until very upgraded):
- The Maw: Unknown hostile faction, nobody comes back

## Campaign Save Location

Server's `scriptstorage.json`, key: `ragtag.campaign.sandbox`

Director keeps a backup in `director/director_memory.json`

## Next Steps After Sandbox

1. **Story Campaign**: Try `scenarios/longhaul/` (5-session Firefly-style narrative)
2. **Create Your Own**: Use sandbox as a template
3. **Contribute**: Add universe extensions or new scenarios (see CONTRIBUTING.md)

## Need Help?

- **GM Guide**: `scenarios/sandbox/GM_GUIDE.md` (detailed reference)
- **Framework docs**: `.claude/skills/empty-epsilon-scenarios/references/`
- **Architecture**: `docs/architecture.md`
- **Main README**: `README.md`

## Known Limitations

- No scripted story beats (by design—it's sandbox!)
- Director is optional but recommended for dynamic content
- Sessions are as long/short as you want (no fixed length)
- Universe is large—players might feel lost at first (AI director helps)

Have fun exploring the Drift! 🚀
