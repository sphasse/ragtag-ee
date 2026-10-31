"""Draw docs/verse_map.svg from the universe data (drift.lua + extensions).

    python tools/make_map.py

Re-run after editing the verse so the GM's map matches the game.
"""
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verse_data  # noqa: E402

ROOT = verse_data.ROOT
D = verse_data.load()

# Far-margin placeholder regions are at ±400 — skip them when computing bounds.
_FAR_MARGIN_NAMES = {"the Outer Dark", "the Far Reach", "the Deep Black", "the Long Dark"}


def entries(key):
    return D.get(key) or []


def num(e, k):
    v = e.get(k)
    return float(v) if v is not None else None


def strv(e, k):
    return e.get(k)


def star_color(e):
    c = e.get("color") or [1, 1, 1]
    r, g, b = [int(v * 255) for v in c]
    return f"#{r:02x}{g:02x}{b:02x}"


# ── Viewport ──────────────────────────────────────────────────────────────────
# Tight around all meaningful content (excludes far-margin placeholder regions).
# Concord Core left edge ≈ −191, Deep Shroud right edge ≈ +200,
# Concord Core top ≈ −136, Maw bottom ≈ +148.
S = 4          # pixels per unit
X0, Y0 = -205, -148
X1, Y1 = 225, 168
W, H = (X1 - X0) * S, (Y1 - Y0) * S
px = lambda x: (x - X0) * S
py = lambda y: (y - Y0) * S

DANGER = {0: "#3d8f6e", 1: "#c9a227", 2: "#d0662c", 3: "#c0392b"}
FAC = {
    "Concord":     "#6fa8ff",
    "Independent": "#d9d4c7",
    "Corsairs":    "#ff8c3c",
    "Hollow":      "#e03030",
}

# Seeded RNG so asteroid scatter is deterministic across runs.
_rng = random.Random(42)

svg = [
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
    f'font-family="system-ui, sans-serif">',
    f'<rect width="{W}" height="{H}" fill="#0d1520"/>',
]

# ── Sector grid (20u) ─────────────────────────────────────────────────────────
gx0 = (X0 // 20) * 20
gy0 = (Y0 // 20) * 20
gx = gx0
while gx <= X1:
    svg.append(f'<line x1="{px(gx):.1f}" y1="0" x2="{px(gx):.1f}" y2="{H}"'
               f' stroke="#1a2635" stroke-width="1"/>')
    gx += 20
gy = gy0
while gy <= Y1:
    svg.append(f'<line x1="0" y1="{py(gy):.1f}" x2="{W}" y2="{py(gy):.1f}"'
               f' stroke="#1a2635" stroke-width="1"/>')
    gy += 20

# ── Nebulae ───────────────────────────────────────────────────────────────────
for e in entries("nebula_fields"):
    svg.append(
        f'<circle cx="{px(num(e,"x")):.1f}" cy="{py(num(e,"y")):.1f}"'
        f' r="{num(e,"r") * S:.1f}" fill="#6a4c93" opacity="0.28"/>'
    )

# ── Asteroid fields — individual dot scatter ──────────────────────────────────
for e in entries("asteroid_fields"):
    kind = strv(e, "kind")
    n = int(num(e, "visual") or 20)
    if kind == "belt":
        x1, y1, x2, y2 = num(e, "x1"), num(e, "y1"), num(e, "x2"), num(e, "y2")
        hw = (num(e, "width") or 4) / 2
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        # perpendicular unit vector
        nx, ny = -dy / length, dx / length
        for _ in range(n):
            t = _rng.random()
            perp = _rng.uniform(-hw, hw)
            ax = x1 + dx * t + nx * perp
            ay = y1 + dy * t + ny * perp
            svg.append(
                f'<circle cx="{px(ax):.1f}" cy="{py(ay):.1f}"'
                f' r="2" fill="#b0a080" opacity="0.75"/>'
            )
    else:
        cx, cy, r = num(e, "x"), num(e, "y"), num(e, "r")
        for _ in range(n):
            ang = _rng.uniform(0, 2 * math.pi)
            rad = r * math.sqrt(_rng.random())
            ax = cx + math.cos(ang) * rad
            ay = cy + math.sin(ang) * rad
            svg.append(
                f'<circle cx="{px(ax):.1f}" cy="{py(ay):.1f}"'
                f' r="2" fill="#b0a080" opacity="0.75"/>'
            )

# ── Danger regions (fill + border) ────────────────────────────────────────────
for e in entries("regions"):
    if strv(e, "name") in _FAR_MARGIN_NAMES:
        continue
    d = int(num(e, "danger"))
    if d > 0:
        svg.append(
            f'<circle cx="{px(num(e,"x")):.1f}" cy="{py(num(e,"y")):.1f}"'
            f' r="{num(e,"r") * S:.1f}" fill="{DANGER[d]}" opacity="0.12"'
            f' stroke="{DANGER[d]}" stroke-width="2"/>'
        )

# ── Stars ─────────────────────────────────────────────────────────────────────
for e in entries("stars"):
    sc = star_color(e)
    r_px = num(e, "r") * S
    svg.append(
        f'<circle cx="{px(num(e,"x")):.1f}" cy="{py(num(e,"y")):.1f}"'
        f' r="{r_px:.1f}" fill="{sc}"/>'
    )
    svg.append(
        f'<text x="{px(num(e,"x")):.1f}" y="{py(num(e,"y")) - r_px - 6:.1f}"'
        f' fill="{sc}" font-size="12" text-anchor="middle">{strv(e,"name")}</text>'
    )

# ── Planets ───────────────────────────────────────────────────────────────────
for e in entries("planets"):
    atmo = e.get("atmo") or [0.36, 0.47, 0.6]
    r, g, b = [int(v * 200) for v in atmo]
    pc = f"#{r:02x}{g:02x}{b:02x}"
    r_px = num(e, "r") * S
    svg.append(
        f'<circle cx="{px(num(e,"x")):.1f}" cy="{py(num(e,"y")):.1f}"'
        f' r="{r_px:.1f}" fill="{pc}"/>'
    )
    svg.append(
        f'<text x="{px(num(e,"x")):.1f}" y="{py(num(e,"y")) + r_px + 13:.1f}"'
        f' fill="#9fb6cc" font-size="11" text-anchor="middle"'
        f' font-style="italic">{strv(e,"name")}</text>'
    )

# ── Stations ──────────────────────────────────────────────────────────────────
for e in entries("stations"):
    fac, x, y = strv(e, "fac"), num(e, "x"), num(e, "y")
    c = FAC.get(fac, "#ccc")
    svg.append(
        f'<rect x="{px(x) - 5:.1f}" y="{py(y) - 5:.1f}" width="10" height="10"'
        f' fill="{c}" transform="rotate(45 {px(x):.1f} {py(y):.1f})"/>'
    )
    shop = " $" if e.get("shop") else ""
    svg.append(
        f'<text x="{px(x) + 9:.1f}" y="{py(y) + 4:.1f}" fill="{c}" font-size="12">'
        f'{strv(e,"cs").replace("&","&amp;")}{shop}</text>'
    )

# ── Region labels ─────────────────────────────────────────────────────────────
_SHROUD_LABELS = {"the Shroud", "the Concord Core", "the Rim", "the Cinder Fields",
                  "Greywater", "Vesper Drift", "the Arbiter Line", "Calder's Reach"}
for e in entries("regions"):
    name = strv(e, "name")
    if name in _FAR_MARGIN_NAMES:
        continue
    d = int(num(e, "danger"))
    label = name
    if d > 0:
        svg.append(
            f'<text x="{px(num(e,"x")):.1f}" y="{py(num(e,"y")) - num(e,"r") * S + 16:.1f}"'
            f' fill="{DANGER[d]}" font-size="15" font-weight="700"'
            f' text-anchor="middle">{label.upper()}</text>'
        )
    elif label in _SHROUD_LABELS:
        svg.append(
            f'<text x="{px(num(e,"x")):.1f}" y="{py(num(e,"y")) - num(e,"r") * S + 18:.1f}"'
            f' fill="#a58fd0" font-size="15" font-weight="700"'
            f' text-anchor="middle" opacity="0.8">{label.upper()}</text>'
        )

# ── Hazards ───────────────────────────────────────────────────────────────────
for e in entries("hazards"):
    k = strv(e, "kind")
    label = "black hole" if k == "blackhole" else "rift"
    cx, cy = px(num(e, "x")), py(num(e, "y"))
    svg.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="7" fill="none" stroke="#fff" stroke-width="2"/>')
    svg.append(f'<text x="{cx + 10:.1f}" y="{cy + 4:.1f}" fill="#fff" font-size="11">{label}</text>')
    if k == "wormhole" and e.get("tx") is not None:
        tx, ty = px(num(e, "tx")), py(num(e, "ty"))
        svg.append(
            f'<line x1="{cx:.1f}" y1="{cy:.1f}" x2="{tx:.1f}" y2="{ty:.1f}"'
            f' stroke="#ffffff" stroke-width="1" stroke-dasharray="4 4" opacity="0.4"/>'
        )

# ── Legend ────────────────────────────────────────────────────────────────────
lg = [
    ("#6fa8ff",   "Concord station"),
    ("#d9d4c7",   "Independent station ($ = shipwright)"),
    ("#ff8c3c",   "Corsair base"),
    ("#e03030",   "Hollow"),
    (DANGER[1],   "risky zone"),
    (DANGER[2],   "dangerous zone"),
    (DANGER[3],   "deadly zone"),
    ("#6a4c93",   "nebula"),
    ("#b0a080",   "asteroids"),
]
for i, (c, t) in enumerate(lg):
    yy = H - 20 - (len(lg) - i) * 18
    svg.append(
        f'<rect x="16" y="{yy - 10:.0f}" width="12" height="12" fill="{c}"/>'
        f'<text x="34" y="{yy:.0f}" fill="#d9d4c7" font-size="12">{t}</text>'
    )
svg.append(
    f'<text x="{W - 16}" y="{H - 36}" fill="#d9d4c7"'
    f' font-size="20" font-weight="700" text-anchor="end">The Drift</text>'
)
svg.append(
    f'<text x="{W - 16}" y="{H - 18}" fill="#93a1ab"'
    f' font-size="12" text-anchor="end">'
    f'Grid squares are EmptyEpsilon sectors (20u). Port Vesper is at the origin.</text>'
)
svg.append("</svg>")

if "--stdout" in sys.argv:
    sys.stdout.write("\n".join(svg))
else:
    out = ROOT / "docs" / "verse_map.svg"
    out.write_text("\n".join(svg))
    print("wrote", out)
