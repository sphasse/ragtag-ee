#!/usr/bin/env python3
"""Generate higher-resolution radar icons for EmptyEpsilon (stdlib only).

The stock radar traces in EmptyEpsilon's resources/radar/ are 32x32 line art, drawn on radar at
up to 256 screen pixels, so they look blocky when zoomed in. This draws replacements at 128x128
(the largest size that still goes into EE's shared sprite atlas) as white shapes with an
anti-aliased alpha channel; EE tints them by faction at draw time. Same filenames as the stock
icons, so a machine without them just shows the stock art.

    python3 tools/gen_radar.py                      # writes assets/radar/*.png
    python3 tools/gen_radar.py --out DIR --sheet sheet.png --stock <EE>/resources/radar

Shapes are described in a 128x128 space (origin top-left, y down, centre 64,64) and rendered
with 4x4 supersampling.
"""
import argparse
import math
import os
import struct
import zlib

SIZE = 128
SS = 4          # supersampling per axis
C = SIZE / 2


# ── Shapes: each is a function (x, y) -> bool in icon space ───────────────────

def rect(cx, cy, w, h, angle=0.0):
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    hw, hh = w / 2, h / 2

    def f(x, y):
        dx, dy = x - cx, y - cy
        u = dx * ca + dy * sa
        v = -dx * sa + dy * ca
        return -hw <= u <= hw and -hh <= v <= hh
    return f


def disc(cx, cy, r):
    return lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def ring(cx, cy, r_out, r_in):
    return lambda x, y: r_in * r_in <= (x - cx) ** 2 + (y - cy) ** 2 <= r_out * r_out


def square_ring(cx, cy, outer, inner, angle=0.0):
    o, i = rect(cx, cy, outer, outer, angle), rect(cx, cy, inner, inner, angle)
    return lambda x, y: o(x, y) and not i(x, y)


def arm(angle, r0, r1, width, pad_len=0, pad_w=0):
    """A spoke from radius r0 to r1 at `angle` (0 = east, clockwise on screen), optionally
    ending in a docking pad (a bar across the spoke)."""
    a = math.radians(angle)
    mid = (r0 + r1) / 2
    parts = [rect(C + math.cos(a) * mid, C + math.sin(a) * mid, r1 - r0, width, angle)]
    if pad_len:
        parts.append(rect(C + math.cos(a) * (r1 - pad_w / 2), C + math.sin(a) * (r1 - pad_w / 2),
                          pad_w, pad_len, angle))
    return lambda x, y: any(p(x, y) for p in parts)


def union(*fs):
    return lambda x, y: any(f(x, y) for f in fs)


def minus(f, *cut):
    return lambda x, y: f(x, y) and not any(c(x, y) for c in cut)


def gaps(angles, r0, r1, width):
    """Cut-outs along the given angles (to break a ring where spokes cross it)."""
    return [arm(a, r0, r1, width) for a in angles]


# ── The four stations ─────────────────────────────────────────────────────────
# One language for all four, getting more elaborate with size: a square hub with a hollow core,
# docking spokes ending in pads, then diagonal arms, then an outer ring, then a second ring and
# pods. Strokes stay bold (>= 8px at 128) so the icon survives being drawn at 16 screen pixels.

CARDINAL = [0, 90, 180, 270]
DIAGONAL = [45, 135, 225, 315]


def small_station():
    hub = square_ring(C, C, 40, 18)
    spokes = [arm(a, 18, 50, 10, pad_len=30, pad_w=9) for a in CARDINAL]
    return union(hub, *spokes)


def medium_station():
    hub = square_ring(C, C, 42, 18)
    spokes = [arm(a, 18, 52, 10, pad_len=30, pad_w=9) for a in CARDINAL]
    diag = [arm(a, 24, 50, 9, pad_len=20, pad_w=8) for a in DIAGONAL]
    return union(hub, *spokes, *diag)


def large_station():
    hub = square_ring(C, C, 44, 18, 45)
    spokes = [arm(a, 16, 60, 10, pad_len=28, pad_w=8) for a in CARDINAL]
    diag = [arm(a, 26, 42, 9) for a in DIAGONAL]
    outer = minus(ring(C, C, 48, 40), *gaps(CARDINAL, 30, 60, 18))
    return union(hub, *spokes, *diag, outer)


def huge_station():
    hub = union(square_ring(C, C, 40, 16), square_ring(C, C, 40, 16, 45))
    spokes = [arm(a, 14, 62, 10, pad_len=26, pad_w=8) for a in CARDINAL]
    diag = [arm(a, 22, 58, 9, pad_len=18, pad_w=8) for a in DIAGONAL]
    inner = minus(ring(C, C, 36, 29), *gaps(CARDINAL + DIAGONAL, 20, 40, 14))
    outer = minus(ring(C, C, 52, 45), *gaps(CARDINAL, 40, 56, 20))
    return union(hub, *spokes, *diag, inner, outer)


def scaled(make, k):
    """Shrink a design about the centre so its footprint matches the stock icon (the stock small
    and medium stations leave a margin; the icon's drawn size is fixed by the station radius)."""
    def build():
        f = make()
        return lambda x, y: f(C + (x - C) / k, C + (y - C) / k)
    return build


ICONS = {
    "smallstation.png": scaled(small_station, 0.78),    # stock spans ~60% of the icon
    "mediumstation.png": scaled(medium_station, 0.82),  # stock spans ~66%
    "largestation.png": large_station,                   # stock spans the full icon
    "hugestation.png": huge_station,
}


# ── Rendering and PNG I/O ─────────────────────────────────────────────────────

def render(shape, size=SIZE):
    """Coverage (0..255) per pixel, supersampled."""
    out = []
    step = 1.0 / SS
    k = SIZE / size
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(SS):
                y = (py + (sy + 0.5) * step) * k
                for sx in range(SS):
                    x = (px + (sx + 0.5) * step) * k
                    if shape(x, y):
                        hits += 1
            out.append(round(255 * hits / (SS * SS)))
    return out


def _chunk(t, c):
    return struct.pack(">I", len(c)) + t + c + struct.pack(">I", zlib.crc32(t + c) & 0xFFFFFFFF)


def write_gray_alpha(path, w, h, alpha):
    """White (gray 255) with the given alpha: the format of EE's stock radar icons."""
    raw = b"".join(b"\0" + bytes(v for a in alpha[y * w:(y + 1) * w] for v in (255, a)) for y in range(h))
    data = (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 4, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(raw, 9)) + _chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def write_gray(path, w, h, pix):
    raw = b"".join(b"\0" + bytes(pix[y * w:(y + 1) * w]) for y in range(h))
    data = (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(raw, 9)) + _chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(data)


def read_alpha(path):
    """Read an 8-bit PNG (gray/gray+alpha/RGB/RGBA) and return (w, h, coverage list)."""
    d = open(path, "rb").read()
    i, idat = 8, b""
    while i < len(d):
        n = struct.unpack(">I", d[i:i + 4])[0]
        t, c = d[i + 4:i + 8], d[i + 8:i + 8 + n]
        i += 12 + n
        if t == b"IHDR":
            w, h, _bd, ct = struct.unpack(">IIBB", c[:10])
        elif t == b"IDAT":
            idat += c
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[ct]
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = bytearray(stride)
    out, o = [], 0
    for _ in range(h):
        f = raw[o]; o += 1
        cur = bytearray(raw[o:o + stride]); o += stride
        for x in range(stride):
            a = cur[x - bpp] if x >= bpp else 0
            b = prev[x]
            cc = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                cur[x] = (cur[x] + a) & 255
            elif f == 2:
                cur[x] = (cur[x] + b) & 255
            elif f == 3:
                cur[x] = (cur[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - cc), abs(a - cc), abs(a + b - 2 * cc)
                cur[x] = (cur[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else cc)) & 255
        for x in range(w):
            px = cur[x * bpp:(x + 1) * bpp]
            out.append(px[0] * px[1] // 255 if bpp == 2 else px[3] * px[0] // 255 if bpp == 4 else px[0])
        prev = cur
    return w, h, out


def scale_nearest_linear(src, sw, sh, dw, dh):
    """Bilinear resample (what EE's GL_LINEAR does, without mipmaps)."""
    out = []
    for y in range(dh):
        fy = (y + 0.5) * sh / dh - 0.5
        y0 = max(0, min(sh - 1, int(math.floor(fy)))); y1 = min(sh - 1, y0 + 1); ty = min(1, max(0, fy - y0))
        for x in range(dw):
            fx = (x + 0.5) * sw / dw - 0.5
            x0 = max(0, min(sw - 1, int(math.floor(fx)))); x1 = min(sw - 1, x0 + 1); tx = min(1, max(0, fx - x0))
            v = (src[y0 * sw + x0] * (1 - tx) * (1 - ty) + src[y0 * sw + x1] * tx * (1 - ty)
                 + src[y1 * sw + x0] * (1 - tx) * ty + src[y1 * sw + x1] * tx * ty)
            out.append(int(v))
    return out


def contact_sheet(path, names, new_dir, stock_dir=None, sizes=(256, 64, 24)):
    """Rows: each icon. Columns: stock and new at each draw size, bilinear-scaled like EE."""
    pad, bg = 8, 24
    cols = []
    for s in sizes:
        if stock_dir:
            cols.append(("stock", s))
        cols.append(("new", s))
    col_w = [s + pad for _, s in cols]
    row_h = max(sizes) + pad
    W, H = sum(col_w) + pad, row_h * len(names) + pad
    pix = [bg] * (W * H)
    for r, name in enumerate(names):
        x0 = pad
        for (kind, s), cw in zip(cols, col_w):
            d = stock_dir if kind == "stock" else new_dir
            w, h, a = read_alpha(os.path.join(d, name))
            img = scale_nearest_linear(a, w, h, s, s)
            oy = pad + r * row_h + (max(sizes) - s) // 2
            for y in range(s):
                for x in range(s):
                    v = img[y * s + x]
                    pix[(oy + y) * W + x0 + x] = max(bg, v)
            x0 += cw
    write_gray(path, W, H, pix)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default=os.path.join(here, "..", "assets", "radar"))
    ap.add_argument("--sheet", help="also write a preview contact sheet (PNG)")
    ap.add_argument("--stock", help="EE resources/radar dir, to put the stock icons beside the new ones")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, make in ICONS.items():
        write_gray_alpha(os.path.join(args.out, name), SIZE, SIZE, render(make()))
        print("wrote", os.path.join(args.out, name))
    if args.sheet:
        contact_sheet(args.sheet, list(ICONS), args.out, args.stock)
        print("wrote", args.sheet)


if __name__ == "__main__":
    main()
