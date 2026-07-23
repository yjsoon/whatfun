#!/usr/bin/env python3
"""WhatFun icon variations: single-hue progressive ramps, etched glyphs, sparkle center."""
import os

OUT = os.path.dirname(os.path.abspath(__file__))

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

# ---------- petal geometry (local coords, center=512,512, petal points up) ----------
# tip near center, flaring to wide rounded outer edge; corners rounded via same-color stroke.
# The body is tilted about the tip for the hand-placed pinwheel feel; tips stay radially exact.
import math

TIP = (0.0, -94.0)
BODY = [(-144.0, -242.0), (-172.0, -428.0), (172.0, -428.0), (144.0, -242.0)]  # SL BL BR SR
TILT = 9.0    # degrees, clockwise, about the tip
STROKE_W = 44

def _tilt(p):
    t = math.radians(TILT)
    dx, dy = p[0] - TIP[0], p[1] - TIP[1]
    return (TIP[0] + dx * math.cos(t) - dy * math.sin(t),
            TIP[1] + dx * math.sin(t) + dy * math.cos(t))

def petal_d():
    pts = [TIP] + [_tilt(p) for p in BODY]
    cmds = []
    for j, (x, y) in enumerate(pts):
        cmds.append(('M' if j == 0 else 'L') + f' {512 + x:.1f} {512 + y:.1f}')
    return ' '.join(cmds) + ' Z'

PETAL_D = petal_d()
# glyph anchor = tilted body centroid-ish point, in canvas coords for the unrotated petal
_ga = _tilt((0.0, -330.0))
GLYPH_X = 512 + _ga[0]
GLYPH_YC = 512 + _ga[1]

# ---------- glyphs (centered on 0,0; fill/stroke = currentColor; evenodd cutouts) ----------
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
    "app": '''
  <g id="g-app">
    <path fill="currentColor" fill-rule="evenodd" d="M -20 -64
      L 20 -64 C 52 -64 64 -52 64 -20 L 64 20 C 64 52 52 64 20 64
      L -20 64 C -52 64 -64 52 -64 20 L -64 -20 C -64 -52 -52 -64 -20 -64 Z
      M -14 -47 L 14 -47 C 38 -47 47 -38 47 -14 L 47 14 C 47 38 38 47 14 47
      L -14 47 C -38 47 -47 38 -47 14 L -47 -14 C -47 -38 -38 -47 -14 -47 Z
      M 0 -10 a 10 10 0 1 0 0.0001 0 Z"/>
  </g>''',
}

# petal i -> glyph (i=0 top petal stays blank, like the original)
ORDER = [None, "film", "mic", "pad", "tv", "book"]
# v2 order: top petal carries a generic app squircle instead of staying blank
ORDER_V2 = ["app", "film", "mic", "pad", "tv", "book"]
JITTER = [-4, 5, -6, 4, -5, 6]         # glyph-only rotation jitter, petals stay exact
GLYPH_SCALE = 1.0

def build_svg(bg, ramp, etch_fill_amt, etch_hi_amt, etch_sh_amt, order=ORDER):
    parts = []
    parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">')
    parts.append(f'  <rect width="1024" height="1024" fill="{bg}"/>')
    parts.append('  <defs>')
    used = {n for n in order if n}
    for name, g in GLYPHS.items():
        if name in used:
            parts.append(g)
    parts.append('  </defs>')
    # petals: light -> deep clockwise; later petals overlap earlier (stacked-card feel)
    for i in range(6):
        c = ramp[i]
        parts.append(
            f'  <path d="{PETAL_D}" fill="{c}" stroke="{c}" stroke-width="{STROKE_W}" '
            f'stroke-linejoin="round" transform="rotate({60*i} 512 512)"/>')
    # etched glyphs: highlight dup (down), shadow dup (up), tone-on-tone main on top
    for i in range(6):
        name = order[i]
        if not name:
            continue
        c = ramp[i]
        fill = darken(c, etch_fill_amt)
        hi = lighten(c, etch_hi_amt)
        sh = darken(c, etch_sh_amt)
        tf = (f'rotate({60*i} 512 512) translate({GLYPH_X:.1f} {GLYPH_YC:.1f}) '
              f'rotate({JITTER[i] - 60*i}) scale({GLYPH_SCALE})')
        parts.append(f'  <g transform="{tf}">')
        parts.append(f'    <use href="#g-{name}" y="3" color="{hi}"/>')
        parts.append(f'    <use href="#g-{name}" y="-3" color="{sh}"/>')
        parts.append(f'    <use href="#g-{name}" color="{fill}"/>')
        parts.append('  </g>')
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'

VARIANTS = {
    "01-ember": {
        "light": dict(bg="#F4E6CE",
                      ramp=["#F6BE6E", "#F2A054", "#EA8044", "#DE5F38", "#C4432C", "#9C2F23"]),
        "dark":  dict(bg="#201310",
                      ramp=["#EBA958", "#E18D46", "#D66F3A", "#C25330", "#A03B26", "#78291D"]),
    },
    "02-ocean": {
        "light": dict(bg="#EDF3EC",
                      ramp=["#ABDCD2", "#7AC6BB", "#4FABA4", "#2E8C89", "#1A6A6E", "#104A54"]),
        "dark":  dict(bg="#091A1D",
                      ramp=["#93CFC5", "#65B5AB", "#40988F", "#27797A", "#175A61", "#0E414C"]),
    },
    "03-plum": {
        "light": dict(bg="#F6EDF0",
                      ramp=["#E5BAD0", "#D496BE", "#BF74A9", "#A35590", "#823C76", "#5D2A5C"]),
        "dark":  dict(bg="#1B0F1E",
                      ramp=["#D9A5C3", "#C685B1", "#AE659C", "#914984", "#70326A", "#4C2151"]),
    },
    "04-moss": {
        "light": dict(bg="#F2EFE1",
                      ramp=["#C2CF9E", "#A8BC83", "#8DA669", "#728E54", "#587440", "#3F582F"]),
        "dark":  dict(bg="#121A0F",
                      ramp=["#B1C28E", "#97AD74", "#7D975C", "#637E48", "#4B6437", "#354A27"]),
    },
    # v2: whole ramp rebalanced deeper so the top (lightest) card holds against the bg;
    # top petal carries the generic app-squircle glyph
    "05-ember-v2": {
        "light": dict(bg="#F4E6CE", order=ORDER_V2,
                      ramp=["#EFA758", "#E98C48", "#E0713C", "#D05532", "#B33E28", "#8C2B1F"]),
        "dark":  dict(bg="#201310", order=ORDER_V2,
                      ramp=["#DE9448", "#D57C3C", "#C76433", "#B14C2B", "#933723", "#6E241A"]),
    },
    # v3: alternative rebalance — deeper start still, top two steps compressed,
    # deep end stretched for a more molten ember read
    "06-ember-v3": {
        "light": dict(bg="#F4E6CE", order=ORDER_V2,
                      ramp=["#E8973F", "#E28839", "#D66C34", "#C24F2D", "#A03824", "#75251B"]),
        "dark":  dict(bg="#201310", order=ORDER_V2,
                      ramp=["#D5822F", "#CC732C", "#BD5B29", "#A54424", "#86301D", "#5D1F15"]),
    },
}

ETCH = {
    "light": dict(etch_fill_amt=0.13, etch_hi_amt=0.22, etch_sh_amt=0.30),
    "dark":  dict(etch_fill_amt=0.16, etch_hi_amt=0.18, etch_sh_amt=0.34),
}

for slug, modes in VARIANTS.items():
    for mode, spec in modes.items():
        svg = build_svg(spec["bg"], spec["ramp"], order=spec.get("order", ORDER), **ETCH[mode])
        path = os.path.join(OUT, f"{slug}-{mode}.svg")
        with open(path, "w") as f:
            f.write(svg)
        print(path)
