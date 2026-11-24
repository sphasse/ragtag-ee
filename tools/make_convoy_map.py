"""Draw the Hob Works convoy-route map for the Science database (the "Convoy intel: CTS Tithe" entry).

    python3 tools/make_convoy_map.py          # assets/maps/convoy_route.svg and ee/ragtag/img/convoy_route.png

Everything on it comes from the game's data, so re-run this after moving a station, a region or a
picket, or changing a range:
  - stations, regions and lane pickets: the universe data (drift.lua + extensions, via verse_data)
  - the port guards' and pickets' sight ranges: _P.defaults in ee/ragtag/world/defenders.lua
  - the escorts' sensor range: M.SCAN_R in ee/ragtag/missions/hob.lua

The PNG is made with macOS QuickLook (qlmanage) and sips, so that step needs a Mac; elsewhere it
writes the SVG only and says so. The PNG is committed (ee/ragtag/img/ is installed with the rest of
ee/ragtag/, and EmptyEpsilon reads images from scripts/), so players never run this.
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verse_data  # noqa: E402

ROOT = verse_data.ROOT
D = verse_data.load()

SVG_OUT = ROOT / "assets" / "maps" / "convoy_route.svg"
PNG_OUT = ROOT / "ee" / "ragtag" / "img" / "convoy_route.png"
PNG_W = 1024


def _lua_num(path, pattern, default):
    m = re.search(pattern, (ROOT / path).read_text(encoding="utf-8"))
    return float(m.group(1)) if m else default


GUARD_R = _lua_num("ee/ragtag/world/defenders.lua", r"guard_radar_u\s*=\s*(\d+)", 5000) / 1000
PICKET_R = _lua_num("ee/ragtag/world/defenders.lua", r"picket_radar_u\s*=\s*(\d+)", 10000) / 1000
SCAN_R = _lua_num("ee/ragtag/missions/hob.lua", r"M\.SCAN_R\s*=\s*(\d+)\s*\*\s*U", 15)

ST = {s["cs"]: s for s in D["stations"]}
RG = {r["name"]: r for r in D["regions"]}
LUMEN, SENTINEL, HOB = ST["Lumen Exchange"], ST["Sentinel Fleet Yard"], ST["Hob's Landing"]

# Viewport (universe units): the Concord regions, the route and the way home to Hob's Landing.
X0, Y0, X1, Y1 = -232, -152, 100, 118
S = PNG_W / (X1 - X0)
W, H = PNG_W, round((Y1 - Y0) * S)
px = lambda x: (x - X0) * S  # noqa: E731
py = lambda y: (y - Y0) * S  # noqa: E731

BLUE, RED, GOLD, ROUTE, TEXT, DIM = "#6fa8ff", "#ff5a5a", "#ffd45a", "#ff9a3c", "#e6e1d4", "#8fa0b3"

svg = [
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}"'
    f' font-family="Helvetica Neue, Helvetica, Arial, sans-serif">',
    '<defs>'
    '<pattern id="concord" width="16" height="16" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
    f'<rect width="16" height="16" fill="{BLUE}" opacity="0.07"/>'
    f'<line x1="0" y1="0" x2="0" y2="16" stroke="{BLUE}" stroke-width="3" opacity="0.22"/></pattern>'
    f'<marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto">'
    f'<path d="M0,0 L10,5 L0,10 z" fill="{ROUTE}"/></marker>'
    '</defs>',
    f'<rect width="{W}" height="{H}" fill="#0d1520"/>',
]

# Sector grid (20U).
g = (X0 // 20) * 20
while g <= X1:
    svg.append(f'<line x1="{px(g):.1f}" y1="0" x2="{px(g):.1f}" y2="{H}" stroke="#1a2635"/>')
    g += 20
g = (Y0 // 20) * 20
while g <= Y1:
    svg.append(f'<line x1="0" y1="{py(g):.1f}" x2="{W}" y2="{py(g):.1f}" stroke="#1a2635"/>')
    g += 20

# Concord space.
CONCORD_REGIONS = ["the Concord Core", "the Arbiter Line", "the Escrow Marches"]
for name in CONCORD_REGIONS:
    r = RG[name]
    svg.append(f'<circle cx="{px(r["x"]):.1f}" cy="{py(r["y"]):.1f}" r="{r["r"] * S:.1f}" fill="url(#concord)"'
               f' stroke="{BLUE}" stroke-width="2" stroke-opacity="0.55"/>')
LABEL_AT = {"the Concord Core": (-170, -138), "the Arbiter Line": (-40, -88), "the Escrow Marches": (-190, 70)}
for name, (lx, ly) in LABEL_AT.items():
    svg.append(f'<text x="{px(lx):.1f}" y="{py(ly):.1f}" fill="{BLUE}" font-size="17" font-weight="700"'
               f' text-anchor="middle" opacity="0.85">{name.upper()}</text>')

# Escort sensors round Lumen (the convoy waits docked there).
svg.append(f'<circle cx="{px(LUMEN["x"]):.1f}" cy="{py(LUMEN["y"]):.1f}" r="{SCAN_R * S:.1f}" fill="{ROUTE}"'
           f' fill-opacity="0.08" stroke="{ROUTE}" stroke-width="2" stroke-dasharray="6 5"/>')
svg.append(f'<text x="{px(LUMEN["x"] - SCAN_R - 1):.1f}" y="{py(LUMEN["y"]) + 5:.1f}" fill="{ROUTE}"'
           f' font-size="14" text-anchor="end">escort sensors {SCAN_R:.0f}U</text>')

# The route.
svg.append(f'<line x1="{px(LUMEN["x"]):.1f}" y1="{py(LUMEN["y"]):.1f}" x2="{px(SENTINEL["x"]):.1f}"'
           f' y2="{py(SENTINEL["y"]):.1f}" stroke="{ROUTE}" stroke-width="5" marker-end="url(#arrow)"/>')
mx, my = (LUMEN["x"] + SENTINEL["x"]) / 2, (LUMEN["y"] + SENTINEL["y"]) / 2
dist = ((LUMEN["x"] - SENTINEL["x"]) ** 2 + (LUMEN["y"] - SENTINEL["y"]) ** 2) ** 0.5
svg.append(f'<text x="{px(mx + 4):.1f}" y="{py(my):.1f}" fill="{ROUTE}" font-size="16" font-weight="700">'
           f'CTS Tithe</text>')
svg.append(f'<text x="{px(mx + 4):.1f}" y="{py(my) + 19:.1f}" fill="{ROUTE}" font-size="14">'
           f'{dist:.0f}U, no stops</text>')

# The way home.
svg.append(f'<line x1="{px(SENTINEL["x"]):.1f}" y1="{py(SENTINEL["y"]):.1f}" x2="{px(HOB["x"]):.1f}"'
           f' y2="{py(HOB["y"]):.1f}" stroke="{GOLD}" stroke-width="2" stroke-dasharray="3 7" opacity="0.6"/>')

# Lane pickets and their sight. Labels go above the ring unless a port's label is in the way.
PICKET_LABEL = {"CNS Lawgiver": "left", "CPV Vigilant": "below"}
for gr in D["garrisons"]:
    if gr.get("fac") == "Concord" and gr.get("beat_u"):
        x, y = gr["x"], gr["y"]
        name = gr.get("callsign") or " / ".join(gr.get("callsigns") or [])
        svg.append(f'<circle cx="{px(x):.1f}" cy="{py(y):.1f}" r="{PICKET_R * S:.1f}" fill="{RED}" fill-opacity="0.06"'
                   f' stroke="{RED}" stroke-width="1.5" stroke-dasharray="4 4"/>')
        svg.append(f'<path d="M{px(x):.1f},{py(y) - 7:.1f} L{px(x) + 6:.1f},{py(y) + 5:.1f}'
                   f' L{px(x) - 6:.1f},{py(y) + 5:.1f} z" fill="{RED}"/>')
        side = PICKET_LABEL.get(gr.get("callsign") or (gr.get("callsigns") or [""])[0], "above")
        tx, ty, anchor = {
            "above": (px(x), py(y) - PICKET_R * S - 6, "middle"),
            "below": (px(x), py(y) + PICKET_R * S + 15, "middle"),
            "left":  (px(x) - PICKET_R * S - 4, py(y) + 4, "end"),
        }[side]
        svg.append(f'<text x="{tx:.1f}" y="{ty:.1f}" fill="{RED}" font-size="13"'
                   f' text-anchor="{anchor}">{name}</text>')

# Stations: Concord ports with their guard's sight; the Independent ports for the way home.
for s in D["stations"]:
    x, y, fac = s["x"], s["y"], s["fac"]
    if not (X0 <= x <= X1 and Y0 <= y <= Y1) or fac not in ("Concord", "Independent"):
        continue
    c = BLUE if fac == "Concord" else TEXT
    if fac == "Concord":
        svg.append(f'<circle cx="{px(x):.1f}" cy="{py(y):.1f}" r="{GUARD_R * S:.1f}" fill="none"'
                   f' stroke="{RED}" stroke-width="1.5" stroke-dasharray="3 3"/>')
    big = s["cs"] in ("Lumen Exchange", "Sentinel Fleet Yard", "Hob's Landing")
    col = GOLD if s["cs"] == "Hob's Landing" else c
    d = 8 if big else 6
    svg.append(f'<rect x="{px(x) - d:.1f}" y="{py(y) - d:.1f}" width="{2 * d}" height="{2 * d}" fill="{col}"'
               f' transform="rotate(45 {px(x):.1f} {py(y):.1f})"/>')
    name = s["cs"].replace("&", "&amp;").replace("'", "&#39;")
    size, weight = (17, "700") if big else (13, "400")
    dx = -12 if s["cs"] == "Sentinel Fleet Yard" or px(x) > W - 190 else 12   # left of it near the edge
    anchor = "end" if dx < 0 else "start"
    svg.append(f'<text x="{px(x) + dx:.1f}" y="{py(y) + 5:.1f}" fill="{col}" font-size="{size}"'
               f' font-weight="{weight}" text-anchor="{anchor}">{name}</text>')
svg.append(f'<text x="{px(HOB["x"]) - 12:.1f}" y="{py(HOB["y"]) + 24:.1f}" fill="{GOLD}" font-size="14"'
           f' text-anchor="end">deliver the cash here</text>')

# Title and legend.
svg.append(f'<text x="{W - 16}" y="30" fill="{TEXT}" font-size="22" font-weight="700" text-anchor="end">'
           f'Treasury convoy: Lumen Exchange to Sentinel</text>')
legend = [
    (ROUTE, "line", "the convoy's route; escort sensors (dashed)"),
    (RED, "ring", f"Concord port guard: sees {GUARD_R:.0f}U once you are wanted"),
    (RED, "tri", f"lane picket: sees {PICKET_R:.0f}U once you are wanted"),
    (BLUE, "box", "Concord space"),
    (GOLD, "line", "the way home to Hob's Landing"),
]
ly0 = H - 40 - 22 * len(legend)
LX = W - 440
svg.append(f'<rect x="{LX - 10}" y="{ly0 - 14}" width="440" height="{22 * len(legend) + 14}" fill="#0d1520"'
           f' opacity="0.85" stroke="#2a3a4d"/>')
for i, (c, kind, text) in enumerate(legend):
    y = ly0 + 6 + 22 * i
    if kind == "line":
        svg.append(f'<line x1="{LX}" y1="{y - 5}" x2="{LX + 20}" y2="{y - 5}" stroke="{c}" stroke-width="4"/>')
    elif kind == "ring":
        svg.append(f'<circle cx="{LX + 10}" cy="{y - 5}" r="8" fill="none" stroke="{c}" stroke-width="1.5"'
                   f' stroke-dasharray="3 3"/>')
    elif kind == "tri":
        svg.append(f'<path d="M{LX + 10},{y - 12} L{LX + 16},{y} L{LX + 4},{y} z" fill="{c}"/>')
    else:
        svg.append(f'<rect x="{LX + 2}" y="{y - 13}" width="16" height="16" fill="url(#concord)" stroke="{c}"/>')
    svg.append(f'<text x="{LX + 30}" y="{y}" fill="{TEXT}" font-size="15">{text}</text>')
svg.append(f'<text x="{W - 16}" y="{H - 14}" fill="{DIM}" font-size="13" text-anchor="end">'
           f'Grid squares are 20U sectors.</text>')
svg.append("</svg>")

SVG_OUT.parent.mkdir(parents=True, exist_ok=True)
SVG_OUT.write_text("\n".join(svg), encoding="utf-8")
print("wrote", SVG_OUT.relative_to(ROOT))

if not (shutil.which("qlmanage") and shutil.which("sips")):
    print("No qlmanage/sips (not a Mac): the PNG was not regenerated.")
    sys.exit(0)
with tempfile.TemporaryDirectory() as tmp:
    # QuickLook fits the picture into a PNG_W square (centred, padded top and bottom); sips crops
    # the padding off. (With a width/height on the <svg> it renders larger and cuts it off instead.)
    subprocess.run(["qlmanage", "-t", "-s", str(PNG_W), "-o", tmp, str(SVG_OUT)],
                   check=True, capture_output=True)
    thumb = Path(tmp) / (SVG_OUT.name + ".png")
    PNG_OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["sips", "-c", str(H), str(W), str(thumb), "--out", str(PNG_OUT)],
                   check=True, capture_output=True)
print("wrote", PNG_OUT.relative_to(ROOT), f"({W}x{H})")
