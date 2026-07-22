#!/usr/bin/env python3
"""WhatFun icon exploration D: rating-star negative space, lapped cards, 5 color schemes.

Construction:
- 5 petals at 72deg; petal k spans [P_k, P_k + 88deg] (16deg extension laps over the
  next-drawn neighbor's sector; drawn light->deep, so the deepest card closes the
  loop over the lightest at the top star point -- one deliberate seam).
- Every petal has the 5-point star polygon subtracted, so the negative-space star
  is crisp regardless of lapping.
- Rounded corners via morphological opening (buffer -30 / +30), which rounds card
  corners but keeps the star tips sharp.
- Mark outer diameter 740 (72% of canvas) per Apple icon-grid proportion.
- Letterpress glyphs: highlight dup (y+3, lighten), shadow dup (y-3, darken),
  tone-on-tone main on top (a-shades recipe).
"""
import math, os
from shapely.geometry import Polygon, MultiPolygon

OUT = "/tmp/claude-0/-home-user-whatfun/bb502722-18e9-50e5-9328-dea22a981794/scratchpad/d-star"
os.makedirs(OUT, exist_ok=True)
C = 512.0
R_OUT = 370.0        # mark radius -> 740 diameter
STAR_R = 220.0       # star outer radius
STAR_r = 105.0       # star inner radius
OV = 16.0            # lap extension (deg)
ROUND = 30.0         # corner rounding radius

# ---------- color helpers ----------
def h2rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb2h(r, g, b):
    return '#%02X%02X%02X' % (round(r), round(g), round(b))

def mix(c, t, amt):
    a = h2rgb(c); b = h2rgb(t)
    return rgb2h(*[a[i] + (b[i] - a[i]) * amt for i in range(3)])

def lighten(c, amt): return mix(c, '#FFFFFF', amt)
def darken(c, amt):  return mix(c, '#000000', amt)

def lum(c):
    r, g, b = h2rgb(c)
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255

# ---------- geometry ----------
def pt(ang_deg, r):
    a = math.radians(ang_deg)
    return (C + r * math.cos(a), C + r * math.sin(a))

def star_polygon():
    pts = []
    for j in range(5):
        pts.append(pt(-90 + 72 * j, STAR_R))
        pts.append(pt(-54 + 72 * j, STAR_r))
    return Polygon(pts)

def wedge(a0, a1, R, n=64):
    pts = [(C, C)]
    for i in range(n + 1):
        pts.append(pt(a0 + (a1 - a0) * i / n, R))
    return Polygon(pts)

def build_petals():
    star = star_polygon()
    petals = []
    for k in range(5):
        a0 = -90 + 72 * k
        raw = wedge(a0, a0 + 72 + OV, R_OUT).difference(star)
        p = raw.buffer(-ROUND, quad_segs=10).buffer(ROUND, quad_segs=10)
        if isinstance(p, MultiPolygon):
            p = max(p.geoms, key=lambda g: g.area)
        petals.append(p)
    return petals

def poly_path(poly, prec=1):
    def ring(coords):
        return "M" + " L".join(f"{x:.{prec}f} {y:.{prec}f}" for x, y in coords[:-1]) + " Z"
    d = ring(list(poly.exterior.coords))
    for interior in poly.interiors:
        d += " " + ring(list(interior.coords))
    return d

# ---------- glyphs (a-shades letterpress set, centered on 0,0; currentColor) ----------
GLYPHS = {
    "book": '''
  <g id="g-book">
    <path fill="currentColor" fill-rule="evenodd" d="M 0 -34
      C -20 -50 -60 -55 -86 -46 L -86 38 C -60 29 -20 32 0 47
      C 20 32 60 29 86 38 L 86 -46 C 60 -55 20 -50 0 -34 Z
      M -13 -20 C -27 -31 -50 -36 -68 -33 L -68 21 C -50 18 -27 21 -13 29 Z
      M 13 -20 C 27 -31 50 -36 68 -33 L 68 21 C 50 18 27 21 13 29 Z"/>
  </g>''',
    "film": '''
  <g id="g-film">
    <path fill="currentColor" fill-rule="evenodd" d="M -54 -78
      L 54 -78 Q 66 -78 66 -66 L 66 66 Q 66 78 54 78 L -54 78 Q -66 78 -66 66 L -66 -66 Q -66 -78 -54 -78 Z
      M -28 -46 L 28 -46 Q 32 -46 32 -42 L 32 42 Q 32 46 28 46 L -28 46 Q -32 46 -32 42 L -32 -42 Q -32 -46 -28 -46 Z
      M -55 -66 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M -55 -36 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M -55 -6  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M -55 24  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M -55 54  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 -66 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 -36 h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 -6  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 24  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z
      M 43 54  h 12 q 3 0 3 3 v 10 q 0 3 -3 3 h -12 q -3 0 -3 -3 v -10 q 0 -3 3 -3 Z"/>
  </g>''',
    "tv": '''
  <g id="g-tv">
    <path fill="none" stroke="currentColor" stroke-width="13" stroke-linecap="round"
          d="M 0 -30 L -30 -64 M 0 -30 L 28 -64"/>
    <path fill="currentColor" fill-rule="evenodd" d="M -68 -28
      L 68 -28 Q 84 -28 84 -12 L 84 50 Q 84 66 68 66 L -68 66 Q -84 66 -84 50 L -84 -12 Q -84 -28 -68 -28 Z
      M -62 -12 L 34 -12 Q 40 -12 40 -6 L 40 44 Q 40 50 34 50 L -62 50 Q -68 50 -68 44 L -68 -6 Q -68 -12 -62 -12 Z
      M 62 -4 a 7 7 0 1 0 0.0001 0 Z
      M 62 16 a 7 7 0 1 0 0.0001 0 Z
      M 62 36 a 7 7 0 1 0 0.0001 0 Z"/>
  </g>''',
    "pad": '''
  <g id="g-pad">
    <path fill="currentColor" fill-rule="evenodd" d="M -44 -40
      L 44 -40 Q 84 -40 84 0 Q 84 40 44 40 L -44 40 Q -84 40 -84 0 Q -84 -40 -44 -40 Z
      M -51 -21 L -37 -21 L -37 -7 L -23 -7 L -23 7 L -37 7 L -37 21 L -51 21 L -51 7 L -65 7 L -65 -7 L -51 -7 Z
      M 44 -22 a 8 8 0 1 0 0.0001 0 Z
      M 60 -3 a 8 8 0 1 0 0.0001 0 Z
      M 28 -3 a 8 8 0 1 0 0.0001 0 Z
      M 44 16 a 8 8 0 1 0 0.0001 0 Z"/>
  </g>''',
    "mic": '''
  <g id="g-mic">
    <path fill="none" stroke="currentColor" stroke-width="13" stroke-linecap="round"
          d="M -46 -34 A 46 46 0 0 0 46 -34 M 0 11 L 0 44 M -27 50 L 27 50"/>
    <path fill="currentColor" fill-rule="evenodd" d="M -26 -50
      Q -26 -76 0 -76 Q 26 -76 26 -50 L 26 -30 Q 26 -4 0 -4 Q -26 -4 -26 -30 Z
      M -14 -56 L 14 -56 Q 18 -56 18 -52 Q 18 -48 14 -48 L -14 -48 Q -18 -48 -18 -52 Q -18 -56 -14 -56 Z
      M -14 -40 L 14 -40 Q 18 -40 18 -36 Q 18 -32 14 -32 L -14 -32 Q -18 -32 -18 -36 Q -18 -40 -14 -40 Z"/>
  </g>''',
}

ORDER = ["book", "film", "tv", "pad", "mic"]     # petal draw order = ramp order
JITTER = [4, -6, 5, -4, 6]
GLYPH_SCALE = 0.8
GLYPH_R = 258.0

ETCH = {
    "light": dict(fill_amt=0.14, hi_amt=0.22, sh_amt=0.30),
    "dark":  dict(fill_amt=0.16, hi_amt=0.18, sh_amt=0.34),
}

# ---------- svg assembly ----------
def build_svg(bg, ramp, mode, petals):
    e = ETCH[mode]
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
             'viewBox="0 0 1024 1024">',
             f'  <rect width="1024" height="1024" fill="{bg}"/>',
             '  <defs>']
    parts += [g for g in GLYPHS.values()]
    parts.append('  </defs>')
    # interleave petal + its glyph so later laps stack correctly
    for k in range(5):
        c = ramp[k]
        parts.append(f'  <path d="{poly_path(petals[k])}" fill="{c}" fill-rule="evenodd"/>')
        name = ORDER[k]
        psi = -54 + 72 * k + 2          # nudge away from the trailing lap edge
        ax, ay = pt(psi, GLYPH_R)
        fill = darken(c, e["fill_amt"])
        hi = lighten(c, e["hi_amt"])
        sh = darken(c, e["sh_amt"])
        tf = f'translate({ax:.1f} {ay:.1f}) rotate({JITTER[k]}) scale({GLYPH_SCALE})'
        parts.append(f'  <g transform="{tf}">')
        parts.append(f'    <use href="#g-{name}" y="3" color="{hi}"/>')
        parts.append(f'    <use href="#g-{name}" y="-3" color="{sh}"/>')
        parts.append(f'    <use href="#g-{name}" color="{fill}"/>')
        parts.append('  </g>')
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'

SCHEMES = {
    "01-ember-mono": {
        "light": dict(bg="#F6E7D3",
                      ramp=["#FFB491", "#FF9268", "#F76F4A", "#DC4F30", "#AE3722"]),
        "dark":  dict(bg="#1C1210",
                      ramp=["#FFA277", "#F07C50", "#D65C38", "#B44328", "#8C2F1B"]),
    },
    "02-analogous": {
        "light": dict(bg="#F6E7D3",
                      ramp=["#F2B24E", "#F28E52", "#EF6B55", "#DE4E68", "#B93D77"]),
        "dark":  dict(bg="#1D1114",
                      ramp=["#E8A445", "#E37F47", "#DD5F4B", "#C9445E", "#A3356C"]),
    },
    "03-spectrum": {
        "light": dict(bg="#F6EAD8",
                      ramp=["#E8785A", "#D0923F", "#8CA463", "#55A8A0", "#AC7DB2"]),
        "dark":  dict(bg="#171317",
                      ramp=["#D96A4E", "#BD8437", "#7E9459", "#479690", "#9A6CA0"]),
    },
    "04-duotone": {
        "light": dict(bg="#F4E9D7",
                      ramp=["#FF8A5C", "#2E8C89", "#F2653C", "#16646B", "#C43D20"]),
        "dark":  dict(bg="#101A1B",
                      ramp=["#F07A4E", "#2A7E7C", "#DB5733", "#135158", "#A33218"]),
    },
    "05-jewel": {
        "light": dict(bg="#F3EADF",
                      ramp=["#D8933B", "#B23A48", "#7C4FA3", "#3C6DB0", "#2F8F6B"]),
        "dark":  dict(bg="#14121C",
                      ramp=["#E5A045", "#C24856", "#8D5FB8", "#4A7EC4", "#37A47B"]),
    },
}

def main():
    petals = build_petals()
    for slug, modes in SCHEMES.items():
        for mode, spec in modes.items():
            svg = build_svg(spec["bg"], spec["ramp"], mode, petals)
            path = os.path.join(OUT, f"{slug}-{mode}.svg")
            with open(path, 'w') as f:
                f.write(svg)
            print("wrote", os.path.basename(path))
    # greyscale value report for the spectrum scheme
    for mode in ("light", "dark"):
        vals = [f"{c} L={lum(c):.2f}" for c in SCHEMES["03-spectrum"][mode]["ramp"]]
        print("spectrum", mode, "|", "  ".join(vals))

if __name__ == "__main__":
    main()
