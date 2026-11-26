"""Draw the Science database's region maps: the whole Drift (the Regions section) and one per region entry.

    python3 tools/make_region_maps.py           # assets/maps/regions/*.svg and ee/ragtag/img/maps/*.png
    python3 tools/make_region_maps.py --check   # exit 1 if any SVG is out of date (tools/check.py runs this)

Everything on the maps comes from the universe data (drift.lua + extensions, via verse_data), so they follow
the universe: tools/check.py fails when one is stale, and `check.py --fix` redraws them. These are the crew's
maps, not the GM's: no garrisons, minefields, wormhole or Hollow station (docs/verse_map.svg has those).

Which Science DB entry gets which map is MAPS below; the entries themselves name their image in
ee/ragtag/world/sciencedb.lua ("ragtag/img/maps/<key>.png"). A new map needs both.

The PNGs are made with macOS QuickLook (qlmanage) and sips, so that step needs a Mac; elsewhere it writes the
SVGs only and says so. The PNGs are committed (ee/ragtag/img/ is installed with the rest of ee/ragtag/, and
EmptyEpsilon reads images from scripts/), so players never run this.
"""
import math
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verse_data  # noqa: E402

ROOT = verse_data.ROOT
SVG_DIR = ROOT / "assets" / "maps" / "regions"
PNG_DIR = ROOT / "ee" / "ragtag" / "img" / "maps"
PNG_W = 1024

# key (the file name; sciencedb.lua names "ragtag/img/maps/<key>.png"), title, the universe regions it shows
# (None: the whole Drift).
MAPS = [
    ("drift", "The Drift", None),
    ("region_core", "The Core", ["the Concord Core"]),
    ("region_escrow", "The Escrow Marches", ["the Escrow Marches"]),
    ("region_border", "The Border", ["Vesper Drift", "Calder's Reach", "the Cinder Fields", "Greywater"]),
    ("region_rim", "The Rim", ["the Rim", "Hob's Landing"]),
    ("region_shroud", "The Shroud", ["the Shroud", "Halcyon Rest", "the Deep Shroud"]),
    ("region_gauntlet", "The Gauntlet", ["the Gauntlet"]),
    ("region_blackwater", "Blackwater Reach", ["Blackwater Reach"]),
    ("region_boneyard", "The Boneyard", ["the Boneyard"]),
    ("region_maw", "The Maw", ["the Maw"]),
]

FAR_MARGIN = {"the Outer Dark", "the Far Reach", "the Deep Black", "the Long Dark"}
# Regions named on the overview (the rest are a port's own pocket, named by the port).
OVERVIEW_LABELS = {"the Concord Core", "the Arbiter Line", "the Escrow Marches", "Vesper Drift", "the Cinder Fields",
                   "the Gauntlet", "Blackwater Reach", "the Shroud", "the Deep Shroud", "the Rim", "the Boneyard",
                   "the Maw"}
CONCORD_REGIONS = {"the Concord Core", "the Arbiter Line", "the Escrow Marches"}
# Where a region's name goes when the top of its circle is crowded (default: just inside the top; a pair is an
# offset from the centre in U).
LABEL_AT = {"the Escrow Marches": "centre", "the Shroud": "centre", "the Rim": (0, -12), "the Gauntlet": "centre",
            "Vesper Drift": "bottom"}
HIDDEN_STATIONS = {"The Maw"}
LABEL_LEFT = {"Concord Station Arbiter"}   # name to the left of the port (clear of Halcyon Rest's)       # "Long-range scans show no stations" (the Maw's entry)

BG, GRID, TEXT, DIM = "#0d1520", "#1c2a3a", "#e6e1d4", "#8fa0b3"
BLUE, NEUTRAL, FOCUS = "#6fa8ff", "#a58fd0", "#f2ead8"
DANGER = {1: "#c9a227", 2: "#d0662c", 3: "#d0403a"}
STATION = {"Concord": BLUE, "Independent": "#e6e1d4", "Corsairs": "#ff8c3c"}


def sector_row(sy: int) -> str:
    """EmptyEpsilon's sector row letters (getSectorName in gameGlobalInfo.cpp; C integer division)."""
    if sy >= 0:
        return chr(65 + sy) if sy < 26 else chr(64 + sy // 26) + chr(65 + sy % 26)
    q = int((sy + 1) / 26)
    rem = sy - int(sy / 26) * 26
    return chr(ord("z") + q) + ("a" if rem == 0 else chr(ord("z") + 1 + rem))


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("'", "&#39;").replace("<", "&lt;")


def region_color(r: dict) -> str:
    if r["name"] in CONCORD_REGIONS:
        return BLUE
    return DANGER.get(int(r.get("danger") or 0), NEUTRAL)


def viewport(D: dict, names):
    """The map's universe box (x0, y0, x1, y1): the named regions with a margin, no taller than wide."""
    regs = [r for r in D["regions"] if r["name"] not in FAR_MARGIN and (names is None or r["name"] in names)]
    pad = 6 if names is None else 12
    x0 = min(r["x"] - r["r"] for r in regs) - pad
    x1 = max(r["x"] + r["r"] for r in regs) + pad
    y0 = min(r["y"] - r["r"] for r in regs) - pad
    y1 = max(r["y"] + r["r"] for r in regs) + pad
    if names is None:                       # the stars and ports outside every region too
        for s in D["stars"] + D["stations"]:
            x0, x1 = min(x0, s["x"] - pad), max(x1, s["x"] + pad)
            y0, y1 = min(y0, s["y"] - pad), max(y1, s["y"] + pad)
    w, h = x1 - x0, y1 - y0
    if h > w:                               # QuickLook renders into a square: keep it landscape
        x0, x1 = x0 - (h - w) / 2, x1 + (h - w) / 2
    elif w > 1.7 * h:                       # and not a sliver
        y0, y1 = y0 - (w / 1.7 - h) / 2, y1 + (w / 1.7 - h) / 2
    return x0, y0, x1, y1


def render(D: dict, key: str, title: str, names) -> tuple[str, int, int]:
    x0, y0, x1, y1 = viewport(D, names)
    S = PNG_W / (x1 - x0)
    W, H = PNG_W, round((y1 - y0) * S)
    px = lambda x: (x - x0) * S  # noqa: E731
    py = lambda y: (y - y0) * S  # noqa: E731
    inside = lambda x, y, m=0: x0 - m <= x <= x1 + m and y0 - m <= y <= y1 + m  # noqa: E731
    overview = names is None
    focus = set(names or [])
    fs = 15 if overview else 19                     # base font size (px of a 1024-wide picture)
    es = 2 * fs - 4                                 # the sector names on the edges (twice the old size)
    rng = random.Random(key)                        # deterministic scatter

    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}"'
           f' font-family="Helvetica Neue, Helvetica, Arial, sans-serif">',
           f'<rect width="{W}" height="{H}" fill="{BG}"/>']

    # Sector grid (20U) with EmptyEpsilon's sector names on the edges.
    gx = math.floor(x0 / 20) * 20
    while gx <= x1:
        svg.append(f'<line x1="{px(gx):.1f}" y1="0" x2="{px(gx):.1f}" y2="{H}" stroke="{GRID}"/>')
        if 0 <= px(gx) and px(gx) + 4 < W - 2 * es:          # a sector starting off the picture: no name
            svg.append(f'<text x="{px(gx) + 5:.1f}" y="{H - 8}" fill="{DIM}" font-size="{es}" font-weight="700"'
                       f' opacity="0.85" stroke="{BG}" stroke-width="5" paint-order="stroke">{gx // 20 + 5}</text>')
        gx += 20
    gy = math.floor(y0 / 20) * 20
    while gy <= y1:
        svg.append(f'<line x1="0" y1="{py(gy):.1f}" x2="{W}" y2="{py(gy):.1f}" stroke="{GRID}"/>')
        if 0 <= py(gy) and py(gy) + es < H - es - 8:
            svg.append(f'<text x="6" y="{py(gy) + es + 2:.1f}" fill="{DIM}" font-size="{es}" font-weight="700"'
                       f' opacity="0.85" stroke="{BG}" stroke-width="5" paint-order="stroke">'
                       f'{sector_row(gy // 20 + 5)}</text>')
        gy += 20

    # Nebulae.
    for n in D["nebula_fields"]:
        if inside(n["x"], n["y"], n["r"]):
            svg.append(f'<circle cx="{px(n["x"]):.1f}" cy="{py(n["y"]):.1f}" r="{n["r"] * S:.1f}"'
                       f' fill="#6a4c93" opacity="0.26"/>')

    # Asteroids.
    dot = 1.6 if overview else 2.4
    for a in D["asteroid_fields"]:
        kind, n = a.get("kind"), int(a.get("visual") or 20) * (1 if overview else 2)
        pts = []
        if kind == "belt":
            dx, dy = a["x2"] - a["x1"], a["y2"] - a["y1"]
            ln = math.hypot(dx, dy)
            hw = (a.get("width") or 4) / 2
            for _ in range(n):
                t, p = rng.random(), rng.uniform(-hw, hw)
                pts.append((a["x1"] + dx * t - dy / ln * p, a["y1"] + dy * t + dx / ln * p))
        elif kind == "ring":
            for _ in range(n):
                ang, rad = rng.uniform(0, 2 * math.pi), rng.uniform(a["r1"], a["r2"])
                pts.append((a["x"] + math.cos(ang) * rad, a["y"] + math.sin(ang) * rad))
        else:
            for _ in range(n):
                ang, rad = rng.uniform(0, 2 * math.pi), a["r"] * math.sqrt(rng.random())
                pts.append((a["x"] + math.cos(ang) * rad, a["y"] + math.sin(ang) * rad))
        for x, y in pts:
            if inside(x, y):
                svg.append(f'<circle cx="{px(x):.1f}" cy="{py(y):.1f}" r="{dot}" fill="#b0a080" opacity="0.7"/>')

    # Regions: the map's own bright, the rest faint.
    regs = [r for r in D["regions"] if r["name"] not in FAR_MARGIN]
    for r in sorted(regs, key=lambda r: r["name"] in focus):
        c = region_color(r)
        on = overview or r["name"] in focus
        fill = (0.10 if overview else 0.16) if on else 0.05
        stroke = 0.75 if on else 0.3
        sw = 2 if overview else (3 if on else 1.5)
        svg.append(f'<circle cx="{px(r["x"]):.1f}" cy="{py(r["y"]):.1f}" r="{r["r"] * S:.1f}" fill="{c}"'
                   f' fill-opacity="{fill}" stroke="{c}" stroke-opacity="{stroke}" stroke-width="{sw}"/>')

    # Stars and planets.
    for s in D["stars"]:
        if not inside(s["x"], s["y"], 5):
            continue
        r, g, b = [int(v * 255) for v in s.get("color") or [1, 1, 1]]
        c = f"#{r:02x}{g:02x}{b:02x}"
        rad = max(s["r"] * S, 5)
        svg.append(f'<circle cx="{px(s["x"]):.1f}" cy="{py(s["y"]):.1f}" r="{rad:.1f}" fill="{c}"/>')
        svg.append(f'<text x="{px(s["x"]):.1f}" y="{py(s["y"]) - rad - 6:.1f}" fill="{c}" font-size="{fs - 1}"'
                   f' text-anchor="middle">{esc(s["name"])}</text>')
    for p in D["planets"]:
        if not inside(p["x"], p["y"], 3):
            continue
        r, g, b = [int(v * 200) for v in p.get("atmo") or [0.36, 0.47, 0.6]]
        rad = max(p["r"] * S, 4)
        svg.append(f'<circle cx="{px(p["x"]):.1f}" cy="{py(p["y"]):.1f}" r="{rad:.1f}" fill="#{r:02x}{g:02x}{b:02x}"/>')
        if not overview:
            svg.append(f'<text x="{px(p["x"]):.1f}" y="{py(p["y"]) + rad + fs:.1f}" fill="#9fb6cc"'
                       f' font-size="{fs - 3}" font-style="italic" text-anchor="middle">{esc(p["name"])}</text>')
    for hz in D["hazards"]:
        if hz.get("kind") == "blackhole" and inside(hz["x"], hz["y"]):
            cx, cy = px(hz["x"]), py(hz["y"])
            svg.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="6" fill="#000" stroke="{TEXT}" stroke-width="2"/>')
            svg.append(f'<text x="{cx:.1f}" y="{cy + fs + 6:.1f}" fill="{TEXT}" font-size="{fs - 3}"'
                       f' text-anchor="middle">black hole</text>')

    # Region names: at the top of the circle (or LABEL_AT), in the middle when that is off the map.
    for r in regs:
        if overview and r["name"] not in OVERVIEW_LABELS:
            continue
        if not overview and r["r"] < 15:
            continue                        # a port's own pocket: the port names it
        big = not overview and r["name"] in focus
        size = fs + 5 if big else fs
        at = LABEL_AT.get(r["name"], "top")
        x = r["x"]
        if isinstance(at, tuple):
            x, ly = r["x"] + at[0], py(r["y"] + at[1]) + size / 3
        else:
            ly = {"top": py(r["y"] - r["r"]) + size + 6, "centre": py(r["y"]) + size / 3,
                  "bottom": py(r["y"] + r["r"]) - 10}[at]
        if not (size + 4 < ly < H - 30):
            ly = py(r["y"]) + size / 3
        half = 0.36 * size * len(r["name"]) + 8          # roughly half the label's width
        lx = min(max(px(x), half), W - half)
        if not (size < ly < H - 30) or not (0 < px(x) < W) and abs(lx - px(x)) > r["r"] * S:
            continue
        c = region_color(r)
        svg.append(f'<text x="{lx:.1f}" y="{ly:.1f}" fill="{c}" font-size="{size}"'
                   f' font-weight="700" text-anchor="middle" opacity="{0.95 if big or overview else 0.6}"'
                   f' letter-spacing="1" stroke="{BG}" stroke-width="4" stroke-opacity="0.6" paint-order="stroke">'
                   f'{esc(r["name"]).upper()}</text>')

    # Ports.
    d = 6 if overview else 8
    for s in D["stations"]:
        if s["cs"] in HIDDEN_STATIONS or not inside(s["x"], s["y"]):
            continue
        c = STATION.get(s["fac"], TEXT)
        x, y = px(s["x"]), py(s["y"])
        svg.append(f'<rect x="{x - d:.1f}" y="{y - d:.1f}" width="{2 * d}" height="{2 * d}" fill="{c}"'
                   f' stroke="{BG}" stroke-width="1.5" transform="rotate(45 {x:.1f} {y:.1f})"/>')
        left = x > W - 210 or (s["cs"] in LABEL_LEFT and x > 230)
        svg.append(f'<text x="{x + (-d - 5 if left else d + 5):.1f}" y="{y + fs / 3:.1f}" fill="{c}"'
                   f' font-size="{fs}" text-anchor="{"end" if left else "start"}"'
                   f' stroke="{BG}" stroke-width="4" paint-order="stroke">{esc(s["cs"])}</text>')

    # Title, key, scale.
    svg.append(f'<text x="{W - 16}" y="{fs + 18}" fill="{TEXT}" font-size="{fs + 13}" font-weight="700"'
               f' text-anchor="end" stroke="{BG}" stroke-width="5" paint-order="stroke">{esc(title)}</text>')
    key_rows = [(BLUE, "box", "Concord space"), (DANGER[1], "box", "risky"), (DANGER[2], "box", "dangerous"),
                (DANGER[3], "box", "deadly"), (STATION["Independent"], "port", "port"),
                (BLUE, "port", "Concord port")]
    if overview:
        kx, ky, step = 3 * es, H - 2 * es - 20 * len(key_rows), 20   # clear of the sector names
        svg.append(f'<rect x="{kx - 8}" y="{ky - 18}" width="170" height="{20 * len(key_rows) + 10}" fill="{BG}"'
                   f' opacity="0.85" stroke="#2a3a4d"/>')
        for i, (c, kind, text) in enumerate(key_rows):
            y = ky + step * i
            if kind == "box":
                svg.append(f'<rect x="{kx}" y="{y - 11}" width="13" height="13" fill="{c}" fill-opacity="0.3"'
                           f' stroke="{c}"/>')
            else:
                svg.append(f'<rect x="{kx + 2}" y="{y - 9}" width="9" height="9" fill="{c}"'
                           f' transform="rotate(45 {kx + 6.5} {y - 4.5})"/>')
            svg.append(f'<text x="{kx + 22}" y="{y}" fill="{TEXT}" font-size="{fs - 1}">{text}</text>')
    svg.append(f'<text x="{W - 16}" y="{2 * fs + 42}" fill="{DIM}" font-size="{fs - 3}" text-anchor="end"'
               f' stroke="{BG}" stroke-width="4" paint-order="stroke">Grid: 20U sectors, named as on Relay</text>')
    svg.append("</svg>")
    return "\n".join(svg) + "\n", W, H


def main() -> int:
    D = verse_data.load()
    check = "--check" in sys.argv
    stale, made = [], []
    for key, title, names in MAPS:
        svg, w, h = render(D, key, title, names)
        path = SVG_DIR / f"{key}.svg"
        if not path.exists() or path.read_text(encoding="utf-8") != svg:
            stale.append(key)
            if not check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(svg, encoding="utf-8")
                made.append((path, w, h))
        elif not check and not (PNG_DIR / f"{key}.png").exists():
            made.append((path, w, h))
    if check:
        for key in stale:
            print(f"assets/maps/regions/{key}.svg is out of date")
        return 1 if stale else 0
    for path, _, _ in made:
        print("wrote", path.relative_to(ROOT))
    if not made:
        return 0
    if not (shutil.which("qlmanage") and shutil.which("sips")):
        print("No qlmanage/sips (not a Mac): the PNGs were not regenerated; run this on a Mac.")
        return 0
    PNG_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for path, w, h in made:
            # QuickLook fits the picture into a PNG_W square (centred, padded); sips crops the padding off.
            subprocess.run(["qlmanage", "-t", "-s", str(PNG_W), "-o", tmp, str(path)], check=True, capture_output=True)
            out = PNG_DIR / (path.stem + ".png")
            subprocess.run(["sips", "-c", str(h), str(w), str(Path(tmp) / (path.name + ".png")), "--out", str(out)],
                           check=True, capture_output=True)
            print("wrote", out.relative_to(ROOT), f"({w}x{h})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
