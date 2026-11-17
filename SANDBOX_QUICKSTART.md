# Sandbox Campaign - Quick Start

## What Is This?

An **open-play EmptyEpsilon scenario** for exploring the ragtag universe with no fixed story. Perfect for:
- First-time crews learning EmptyEpsilon
- Getting oriented to the Drift setting before starting story campaigns
- Trying the AI director as a GM's note-taker
- Just having fun flying a spaceship with friends

## The 5-Minute Setup

### 1. Game Server PC
```bash
# Install the scenarios
python tools/install.py --ee /path/to/EmptyEpsilon

# Enable HTTP API in options.ini:
httpserver=8080

# Start EmptyEpsilon as server
# Select scenario: "The Drift"
```

### 2. AI PC (Optional)
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
- The AI director (if you run it) keeps a summary of each session for the GM
- Build your own narrative through actions
- Get powerful enough to visit deadly zones

## Files Created

```
scenarios/sandbox/
├── scenario_80_ragtag.lua      # Main scenario
├── bible.md                    # Story context for AI director
├── README.md                   # Campaign overview
└── GM_GUIDE.md                 # Detailed GM reference
```

## Testing Status

Run `python tools/check.py`, then `python3 tools/smoke_test.py --launch <EmptyEpsilon dir>` and
`python3 tools/game_tests.py --ee <EmptyEpsilon dir>` (see README, "Testing").

## Recommended Settings for First Session

- **Campaign**: Fresh start
- **Starting Credits**: Comfortable (500)
- **Director**: On (it makes no difference to the game; it only lets a running director listen)

## The AI Director

The director is observation-only: it watches the session and writes private notes and summaries
for the GM. It cannot hail the crew, spawn anything or change the campaign. Once the web console
is open, try a standing directive such as "summarise what the crew has done every ten minutes",
or use **Say** to speak to the crew as a station yourself.

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

1. **Story Arc**: Try a story arc (GM "Missions..." button: Rezkov, Boneyard, Ledger, Corsair)
2. **Create Your Own**: Use sandbox as a template
3. **Contribute**: Add universe extensions or new scenarios (see CONTRIBUTING.md)

## Need Help?

- **GM Guide**: `scenarios/sandbox/GM_GUIDE.md` (detailed reference)
- **Framework docs**: `.claude/skills/empty-epsilon-scenarios/references/`
- **Architecture**: `docs/architecture.md`
- **Main README**: `README.md`

## Known Limitations

- No fixed plot: story arcs start when their conditions are met (or from the GM "Missions..." menu)
- The director is optional and does not create content
- Sessions are as long/short as you want (no fixed length)
- Universe is large—players might feel lost at first (the Science database and station rumours help)

Have fun exploring the Drift! 🚀
