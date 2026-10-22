"""Draw docs/verse_map.svg from the universe data (drift.lua + extensions).

    python tools/make_map.py

Re-run after editing the verse so the GM's map matches the game.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verse_data  # noqa: E402

ROOT = verse_data.ROOT
D = verse_data.load()


def entries(key):
    return D.get(key) or []


def num(e, k):
    v = e.get(k)
    return float(v) if v is not None else None


def strv(e, k):
    return e.get(k)


S = 4  # pixels per unit
X0, Y0, X1, Y1 = -150, -110, 160, 125
W, H = (X1 - X0) * S, (Y1 - Y0) * S
px = lambda x: (x - X0) * S
py = lambda y: (y - Y0) * S
DANGER = {0: "#3d8f6e", 1: "#c9a227", 2: "#d0662c", 3: "#c0392b"}
FAC = {"Concord": "#6fa8ff", "Independent": "#d9d4c7", "Corsairs": "#ff8c3c", "Hollow": "#e03030"}

svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="system-ui, sans-serif">',
       f'<rect width="{W}" height="{H}" fill="#0d1520"/>']
# sector grid (20u)
for gx in range(-140, 161, 20):
    svg.append(f'<line x1="{px(gx)}" y1="0" x2="{px(gx)}" y2="{H}" stroke="#1a2635" stroke-width="1"/>')
for gy in range(-100, 121, 20):
    svg.append(f'<line x1="0" y1="{py(gy)}" x2="{W}" y2="{py(gy)}" stroke="#1a2635" stroke-width="1"/>')
for e in entries("nebula_fields"):
    svg.append(f'<circle cx="{px(num(e,"x"))}" cy="{py(num(e,"y"))}" r="{num(e,"r")*S}" fill="#6a4c93" opacity="0.28"/>')
for e in entries("asteroid_fields"):
    if strv(e, "kind") == "belt":
        svg.append(f'<line x1="{px(num(e,"x1"))}" y1="{py(num(e,"y1"))}" x2="{px(num(e,"x2"))}" y2="{py(num(e,"y2"))}" '
                   f'stroke="#8a7f6a" stroke-width="{num(e,"width")*S}" stroke-dasharray="3 5" opacity="0.6"/>')
    else:
        svg.append(f'<circle cx="{px(num(e,"x"))}" cy="{py(num(e,"y"))}" r="{num(e,"r")*S}" fill="none" stroke="#8a7f6a" '
                   f'stroke-width="2" stroke-dasharray="3 5" opacity="0.7"/>')
for e in entries("regions"):
    d = int(num(e, "danger"))
    if d > 0:
        svg.append(f'<circle cx="{px(num(e,"x"))}" cy="{py(num(e,"y"))}" r="{num(e,"r")*S}" fill="{DANGER[d]}" opacity="0.12" '
                   f'stroke="{DANGER[d]}" stroke-width="2"/>')
for e in entries("stars"):
    svg.append(f'<circle cx="{px(num(e,"x"))}" cy="{py(num(e,"y"))}" r="{num(e,"r")*S}" fill="#ffe9a8"/>')
    svg.append(f'<text x="{px(num(e,"x"))}" y="{py(num(e,"y"))-num(e,"r")*S-6}" fill="#ffe9a8" font-size="12" text-anchor="middle">{strv(e,"name")}</text>')
for e in entries("planets"):
    svg.append(f'<circle cx="{px(num(e,"x"))}" cy="{py(num(e,"y"))}" r="{num(e,"r")*S}" fill="#5b7a99"/>')
    svg.append(f'<text x="{px(num(e,"x"))}" y="{py(num(e,"y"))+num(e,"r")*S+13}" fill="#9fb6cc" font-size="11" text-anchor="middle" font-style="italic">{strv(e,"name")}</text>')
for e in entries("stations"):
    fac, x, y = strv(e, "fac"), num(e, "x"), num(e, "y")
    c = FAC.get(fac, "#ccc")
    svg.append(f'<rect x="{px(x)-5}" y="{py(y)-5}" width="10" height="10" fill="{c}" transform="rotate(45 {px(x)} {py(y)})"/>')
    shop = " $" if e.get("shop") else ""
    svg.append(f'<text x="{px(x)+9}" y="{py(y)+4}" fill="{c}" font-size="12">{strv(e,"cs").replace("&","&amp;")}{shop}</text>')
for e in entries("regions"):
    d = int(num(e, "danger"))
    label = strv(e, "name")
    if d > 0:
        svg.append(f'<text x="{px(num(e,"x"))}" y="{py(num(e,"y"))-num(e,"r")*S+16}" fill="{DANGER[d]}" font-size="15" font-weight="700" '
                   f'text-anchor="middle">{label.upper()}</text>')
    elif label in ("the Shroud", "the Concord Core"):
        svg.append(f'<text x="{px(num(e,"x"))}" y="{py(num(e,"y"))-num(e,"r")*S+18}" fill="#a58fd0" font-size="15" font-weight="700" '
                   f'text-anchor="middle" opacity="0.8">{label.upper()}</text>')
for e in entries("hazards"):
    k = strv(e, "kind")
    svg.append(f'<circle cx="{px(num(e,"x"))}" cy="{py(num(e,"y"))}" r="7" fill="none" stroke="#fff" stroke-width="2"/>')
    svg.append(f'<text x="{px(num(e,"x"))+10}" y="{py(num(e,"y"))+4}" fill="#fff" font-size="11">{"black hole" if k=="blackhole" else "rift"}</text>')
# legend
lg = [("#6fa8ff", "Concord station"), ("#d9d4c7", "Independent station ($ = shipwright)"), ("#ff8c3c", "Corsair base"), ("#e03030", "Hollow"),
      (DANGER[1], "risky zone"), (DANGER[2], "dangerous zone"), (DANGER[3], "deadly zone"), ("#6a4c93", "nebula"), ("#8a7f6a", "asteroids")]
for i, (c, t) in enumerate(lg):
    y = H - 20 - (len(lg) - i) * 18
    svg.append(f'<rect x="16" y="{y-10}" width="12" height="12" fill="{c}"/><text x="34" y="{y}" fill="#d9d4c7" font-size="12">{t}</text>')
svg.append(f'<text x="{W-16}" y="{H-36}" fill="#d9d4c7" font-size="20" font-weight="700" text-anchor="end">The Drift</text>')
svg.append(f'<text x="{W-16}" y="{H-18}" fill="#93a1ab" font-size="12" text-anchor="end">Grid squares are EmptyEpsilon sectors (20u). Port Vesper is at the origin.</text>')
svg.append("</svg>")
if "--stdout" in sys.argv:
    sys.stdout.write("\n".join(svg))
else:
    out = ROOT / "docs" / "verse_map.svg"
    out.write_text("\n".join(svg))
    print("wrote", out)
