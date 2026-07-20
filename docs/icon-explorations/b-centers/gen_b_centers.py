#!/usr/bin/env python3
"""WhatFun icon exploration B: negative-space center shapes.
Construction: each petal = angular wedge MINUS the center shape polygon,
then buffer(-shrink).buffer(+grow) for rounded corners + seam channels.
The center shape is therefore pure negative space (background shows through).
"""
import math, os
from shapely.geometry import Polygon, MultiPolygon
from shapely import affinity

OUT = "/tmp/claude-0/-home-user-whatfun/bb502722-18e9-50e5-9328-dea22a981794/scratchpad/b-centers"
os.makedirs(OUT, exist_ok=True)
C = 512.0

# ---------- palettes ----------
LIGHT = dict(bg="#F6E7D3",
             ramp=["#FFC4A6", "#FFA685", "#FF8763", "#F26644", "#DB482C", "#B23520"])
DARK = dict(bg="#1C1210",
            ramp=["#FFC9AF", "#FF9E7C", "#F87A55", "#E2583A", "#C4432A", "#A03623"])

def hex2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb2hex(r):
    return '#%02X%02X%02X' % tuple(max(0, min(255, round(v))) for v in r)

def mix(c1, c2, t):
    a, b = hex2rgb(c1), hex2rgb(c2)
    return rgb2hex(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))

def lum(c):
    r, g, b = hex2rgb(c)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255

def glyph_color(petal):
    # tone-on-tone: darker tint on light petals, lighter tint on deep petals
    if lum(petal) > 0.62:
        return mix(petal, "#8A2A14", 0.30)
    else:
        return mix(petal, "#FFE9DC", 0.30)

# ---------- geometry helpers ----------
def pt(ang_deg, r, cx=C, cy=C):
    a = math.radians(ang_deg)
    return (cx + r * math.cos(a), cy + r * math.sin(a))

def wedge(a0, a1, R=470.0, n=48):
    pts = [(C, C)]
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        pts.append(pt(a, R))
    return Polygon(pts)

def rounded(poly, shrink=52, grow=42):
    p = poly.buffer(-shrink, quad_segs=10).buffer(grow, quad_segs=10)
    if isinstance(p, MultiPolygon):
        p = max(p.geoms, key=lambda g: g.area)
    return p

def poly_path(poly, prec=1):
    def ring(coords):
        return "M" + " L".join(f"{x:.{prec}f} {y:.{prec}f}" for x, y in coords[:-1]) + " Z"
    d = ring(list(poly.exterior.coords))
    for interior in poly.interiors:
        d += " " + ring(list(interior.coords))
    return d

def bezier(p0, c1, c2, p1, n=36):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * c1[0] + 3 * mt * t**2 * c2[0] + t**3 * p1[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * c1[1] + 3 * mt * t**2 * c2[1] + t**3 * p1[1]
        pts.append((x, y))
    return pts

# ---------- glyphs (local box ~ +/-48, y down) ----------
def g_book(m, p):
    return (f'<path d="M0 -8 L-46 -24 L-46 16 L0 32 L46 16 L46 -24 Z" fill="{m}"/>'
            f'<path d="M0 -8 L0 32" stroke="{p}" stroke-width="6" stroke-linecap="round"/>')

def g_film(m, p):
    holes = ''.join(f'<rect x="{cx}" y="{cy}" width="9" height="11" rx="2.5" fill="{p}"/>'
                    for cx in (-25, 16) for cy in (-31, -6, 19))
    return f'<rect x="-31" y="-40" width="62" height="80" rx="8" fill="{m}"/>{holes}'

def g_tv(m, p):
    return (f'<rect x="-42" y="-24" width="84" height="60" rx="12" fill="{m}"/>'
            f'<rect x="-30" y="-12" width="44" height="36" rx="6" fill="{p}"/>'
            f'<path d="M-15 -42 L0 -25 L15 -42" stroke="{m}" stroke-width="8" '
            f'stroke-linecap="round" stroke-linejoin="round" fill="none"/>')

def g_pad(m, p):
    return (f'<rect x="-46" y="-20" width="92" height="46" rx="23" fill="{m}"/>'
            f'<path d="M-24 -7 L-24 13 M-34 3 L-14 3" stroke="{p}" stroke-width="8" stroke-linecap="round"/>'
            f'<circle cx="20" cy="-4" r="5.5" fill="{p}"/><circle cx="30" cy="9" r="5.5" fill="{p}"/>')

def g_mic(m, p):
    return (f'<rect x="-13" y="-44" width="26" height="48" rx="13" fill="{m}"/>'
            f'<path d="M-24 -8 a24 24 0 0 0 48 0" stroke="{m}" stroke-width="8" '
            f'stroke-linecap="round" fill="none"/>'
            f'<path d="M0 16 L0 30 M-14 32 L14 32" stroke="{m}" stroke-width="8" stroke-linecap="round"/>')

def g_note(m, p):
    return (f'<path d="M-13 24 L-13 -20 L33 -30 L33 16" stroke="{m}" stroke-width="10" '
            f'stroke-linejoin="round" fill="none"/>'
            f'<ellipse cx="-22" cy="25" rx="12" ry="10" fill="{m}"/>'
            f'<ellipse cx="24" cy="16" rx="12" ry="10" fill="{m}"/>')

GLYPHS6 = [g_book, g_film, g_tv, g_pad, g_mic, g_note]
GLYPHS5 = [g_book, g_film, g_tv, g_pad, g_mic]

def glyph_group(fn, petal_color, x, y, rot, scale=1.55):
    m = glyph_color(petal_color)
    return (f'<g transform="translate({x:.1f} {y:.1f}) rotate({rot:.1f}) scale({scale})">'
            f'{fn(m, petal_color)}</g>')

# ---------- variation builders ----------
def petals_from_seams(shape, seams, shrink=52, grow=42):
    seams = sorted(seams)
    out = []
    for i in range(len(seams)):
        a0 = seams[i]
        a1 = seams[(i + 1) % len(seams)]
        if a1 <= a0:
            a1 += 360
        w = wedge(a0, a1)
        out.append(rounded(w.difference(shape), shrink, grow))
    return out

def var_play():
    R = 250
    tri = Polygon([pt(0, R), pt(120, R), pt(240, R)])
    return petals_from_seams(tri, [0, 60, 120, 180, 240, 300])

def var_star():
    R, r = 268, 128
    pts = []
    for j in range(5):
        pts.append(pt(-90 + 72 * j, R))
        pts.append(pt(-54 + 72 * j, r))
    star = Polygon(pts)
    return petals_from_seams(star, [-90 + 72 * j for j in range(5)])

def heart_polygon():
    segs = [
        ((512, 452), (498, 414), (472, 346), (430, 334)),
        ((430, 334), (386, 322), (346, 354), (344, 414)),
        ((344, 414), (342, 486), (430, 580), (512, 706)),
    ]
    left = [(512, 452)]
    for p0, c1, c2, p1 in segs:
        left += bezier(p0, c1, c2, p1)
    right = [(2 * 512 - x, y) for x, y in reversed(left[:-1])]
    return Polygon(left + right)

def var_heart():
    # seams avoid cleft and bottom point: top petal owns the cleft (two-pronged
    # tip), bottom petal wraps the point
    return petals_from_seams(heart_polygon(), [-120, -60, 0, 60, 120, 180],
                             shrink=42, grow=32)

def var_aperture():
    # overlapping shutter blades clipped to a lens circle;
    # opening = hexagonal iris (negative space)
    from shapely.geometry import Point
    lens = Point(C, C).buffer(448, quad_segs=64)
    base = Polygon([(-310, -205), (310, -135), (445, -230), (258, -437),
                    (-196, -464)])
    base = affinity.translate(base, C, C)
    blades = []
    for k in range(6):
        b = affinity.rotate(base, 60 * k, origin=(C, C))
        b = b.buffer(-40, quad_segs=10).buffer(40, quad_segs=10)
        b = b.intersection(lens)
        blades.append(b)
    return blades

# ---------- svg assembly ----------
def petal_meta(poly):
    c = poly.centroid
    ang = math.degrees(math.atan2(c.y - C, c.x - C))
    return c.x, c.y, ang

def build_svg(petals, pal, glyphs=None, start_angle=-90):
    metas = [petal_meta(p) for p in petals]
    idx = sorted(range(len(petals)), key=lambda i: (metas[i][2] - start_angle) % 360)
    body = [f'<rect width="1024" height="1024" fill="{pal["bg"]}"/>']
    ramp = pal["ramp"]
    n = len(petals)
    for rank, i in enumerate(idx):
        col = ramp[rank] if n == len(ramp) else ramp[min(rank + 1, len(ramp) - 1)]
        body.append(f'<path d="{poly_path(petals[i])}" fill="{col}" fill-rule="evenodd"/>')
        if glyphs:
            gx, gy, ga = metas[i]
            r = math.hypot(gx - C, gy - C)
            rr = r + 28
            gx2 = C + (gx - C) / r * rr
            gy2 = C + (gy - C) / r * rr
            body.append(glyph_group(glyphs[rank % len(glyphs)], col, gx2, gy2, ga + 90))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">' + ''.join(body) + '</svg>')

def build_aperture_svg(blades, pal):
    body = [f'<rect width="1024" height="1024" fill="{pal["bg"]}"/>']
    for k, b in enumerate(blades):
        body.append(f'<path d="{poly_path(b)}" fill="{pal["ramp"][k]}"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">' + ''.join(body) + '</svg>')

def write(name, svg):
    with open(os.path.join(OUT, name), 'w') as f:
        f.write(svg)
    print("wrote", name, len(svg), "bytes")

def main():
    play = var_play()
    star = var_star()
    heart = var_heart()
    ap = var_aperture()
    for mode, pal in (("light", LIGHT), ("dark", DARK)):
        write(f"01-play-{mode}.svg", build_svg(play, pal, GLYPHS6))
        write(f"02-aperture-{mode}.svg", build_aperture_svg(ap, pal))
        write(f"03-star-{mode}.svg", build_svg(star, pal, GLYPHS5))
        write(f"04-heart-{mode}.svg", build_svg(heart, pal, GLYPHS6, start_angle=150))

if __name__ == "__main__":
    main()
