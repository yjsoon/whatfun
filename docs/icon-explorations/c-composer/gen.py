#!/usr/bin/env python3
"""Generator for WhatFun Icon Composer mockups + layer sources.
All geometry defined once; emits mode mockups 01-04, context 05-06, layer sources.
"""
import math, os

OUT = os.path.dirname(os.path.abspath(__file__))
CX = CY = 512.0

# ---------------------------------------------------------------- palette
# Rebalanced ember ramp (light -> deep), petal 1 deepened per client feedback.
RAMP = ["#F2AF89", "#EE9569", "#E67A4E", "#D95F38", "#C64828", "#A6371C"]
# Etched glyph tints = petal mixed 55% toward white.
def mix_white(hexc, t):
    r = int(hexc[1:3], 16); g = int(hexc[3:5], 16); b = int(hexc[5:7], 16)
    f = lambda c: round(c + t * (255 - c))
    return "#%02X%02X%02X" % (f(r), f(g), f(b))
TINT = [mix_white(c, 0.55) for c in RAMP]
CREAM_HI = "#FBF2E3"; CREAM_LO = "#EFDCC2"; CREAM = "#F6E7D3"

# ---------------------------------------------------------------- petal geometry
TIP_R      = 80.0
SHO_R      = 190.0; SHO_A = 28.0
OUT_R      = 415.0; OUT_A = 27.0
CTRL_Y     = 26.0          # outer-edge bulge control point y
SW         = 48.0          # nominal corner-rounding stroke

def pol(r, deg):
    a = math.radians(deg)
    return (CX + r * math.sin(a), CY - r * math.cos(a))

def petal_path():
    tx, ty = pol(TIP_R, 0)
    slx, sly = pol(SHO_R, -SHO_A)
    olx, oly = pol(OUT_R, -OUT_A)
    orx, ory = pol(OUT_R,  OUT_A)
    srx, sry = pol(SHO_R,  SHO_A)
    f = lambda v: ("%.1f" % v)
    return (f"M {f(tx)} {f(ty)} L {f(slx)} {f(sly)} L {f(olx)} {f(oly)} "
            f"Q {f(CX)} {f(CTRL_Y)} {f(orx)} {f(ory)} L {f(srx)} {f(sry)} Z")

PETAL = petal_path()

def petal_elem(i, fill, stroke=None, sw=SW, extra=""):
    stroke = stroke or fill
    rot = f' transform="rotate({i*60} {CX:.0f} {CY:.0f})"' if i else ""
    return (f'<path d="{PETAL}" fill="{fill}" stroke="{stroke}" stroke-width="{sw:.0f}" '
            f'stroke-linejoin="round"{rot}{extra}/>')

def petal_outline(i, stroke, sw, extra=""):
    rot = f' transform="rotate({i*60} {CX:.0f} {CY:.0f})"' if i else ""
    return (f'<path d="{PETAL}" fill="none" stroke="{stroke}" stroke-width="{sw:.0f}" '
            f'stroke-linejoin="round"{rot}{extra}/>')

# ---------------------------------------------------------------- glyphs
# Each glyph drawn in a local coord system centered at (0,0), ~160px box.
# Chunky etched outlines, stroke width ~16, round caps.
def g_squircle(c, sw=17):
    return (f'<rect x="-52" y="-52" width="104" height="104" rx="34" fill="none" '
            f'stroke="{c}" stroke-width="{sw}"/>')

def g_book(c, sw=15):
    return (
        f'<g fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">'
        f'<path d="M 0 -26 C -14 -42 -44 -46 -60 -38 L -60 30 C -44 22 -14 26 0 40"/>'
        f'<path d="M 0 -26 C 14 -42 44 -46 60 -38 L 60 30 C 44 22 14 26 0 40"/>'
        f'<path d="M 0 -26 L 0 40"/>'
        f'</g>')

def g_film(c, sw=15):
    return (
        f'<g fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round">'
        f'<rect x="-56" y="-44" width="112" height="88" rx="12"/>'
        f'<line x1="-32" y1="-44" x2="-32" y2="44"/>'
        f'<line x1="32" y1="-44" x2="32" y2="44"/>'
        f'<line x1="-50" y1="-22" x2="-38" y2="-22"/><line x1="-50" y1="0" x2="-38" y2="0"/>'
        f'<line x1="-50" y1="22" x2="-38" y2="22"/>'
        f'<line x1="38" y1="-22" x2="50" y2="-22"/><line x1="38" y1="0" x2="50" y2="0"/>'
        f'<line x1="38" y1="22" x2="50" y2="22"/>'
        f'</g>')

def g_tv(c, sw=15):
    return (
        f'<g fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">'
        f'<rect x="-55" y="-26" width="110" height="78" rx="16"/>'
        f'<line x1="0" y1="-26" x2="-26" y2="-56"/>'
        f'<line x1="0" y1="-26" x2="26" y2="-56"/>'
        f'</g>')

def g_pad(c, sw=15):
    return (
        f'<g fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round">'
        f'<rect x="-58" y="-32" width="116" height="64" rx="32"/>'
        f'<line x1="-44" y1="0" x2="-16" y2="0"/><line x1="-30" y1="-14" x2="-30" y2="14"/>'
        f'<circle cx="26" cy="-9" r="8" fill="{c}" stroke="none"/>'
        f'<circle cx="42" cy="7" r="8" fill="{c}" stroke="none"/>'
        f'</g>')

def g_mic(c, sw=15):
    return (
        f'<g fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round">'
        f'<rect x="-18" y="-56" width="36" height="66" rx="18"/>'
        f'<path d="M -34 -12 C -34 30 34 30 34 -12" fill="none"/>'
        f'<line x1="0" y1="20" x2="0" y2="44"/>'
        f'<line x1="-20" y1="46" x2="20" y2="46"/>'
        f'</g>')

GLYPHS = [g_squircle, g_book, g_film, g_tv, g_pad, g_mic]
GLYPH_R = 268.0   # radial distance of glyph centers
GLYPH_S = 1.0

def glyph_group(colors=None, sw_scale=1.0, extra=""):
    colors = colors or TINT
    out = []
    for i, fn in enumerate(GLYPHS):
        gx, gy = pol(GLYPH_R, i * 60)
        out.append(f'<g transform="translate({gx:.1f} {gy:.1f}) scale({GLYPH_S})"{extra}>{fn(colors[i])}</g>')
    return "".join(out)

# ---------------------------------------------------------------- shared defs
SQUIRCLE = f'<rect x="32" y="32" width="960" height="960" rx="218"/>'

def svg(body, defs=""):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">' + (f"<defs>{defs}</defs>" if defs else "") + body + "</svg>")

# top-fade mask: white at top of canvas fading out ~62% down (userSpace)
def topfade_defs(mid=0.62, top_op=1.0):
    return (
        '<linearGradient id="tf" x1="0" y1="0" x2="0" y2="1024" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="#fff" stop-opacity="{top_op}"/>'
        f'<stop offset="{mid}" stop-color="#fff" stop-opacity="0"/>'
        '</linearGradient>'
        '<mask id="topfade" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
        '<rect width="1024" height="1024" fill="url(#tf)"/></mask>'
        '<linearGradient id="sheenG" x1="0" y1="40" x2="0" y2="620" gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#fff" stop-opacity="0.30"/>'
        '<stop offset="1" stop-color="#fff" stop-opacity="0"/>'
        '</linearGradient>')

def petal_stack(colors, rim="#FFFFFF", rim_op=0.9, sheen=True, glow=None):
    """Petals with specular rim (top-lit) and sheen. Draw order: for each petal:
    base sw=53 color -> white rim sw=53 (masked topfade) -> body sw=43 + fill."""
    parts = []
    if glow:
        for i in range(6):
            parts.append(petal_outline(i, glow, 62, ' opacity="0.4" filter="url(#glowblur)"'))
    for i in range(6):
        c = colors[i]
        parts.append(petal_elem(i, "none", c, 53).replace('fill="none"', 'fill="none"'))
        parts.append(petal_outline(i, rim, 53, f' opacity="{rim_op}" mask="url(#topfade)"'))
        parts.append(petal_elem(i, c, c, 43))
    if sheen:
        for i in range(6):
            parts.append(petal_elem(i, "url(#sheenG)", "none", 0,
                                    ' stroke="url(#sheenG)" stroke-width="43" stroke-linejoin="round"')
                         .replace('stroke="none" stroke-width="0"', ''))
    return "".join(parts)

# cleaner: rebuild petal_stack without hacky replaces
def petal_stack2(colors, rim="#FFFFFF", rim_op=0.9, sheen_op=0.30, glow=None, shadow_filter=None):
    parts = []
    grp_open = f'<g filter="url(#{shadow_filter})">' if shadow_filter else "<g>"
    parts.append(grp_open)
    if glow:
        for i in range(6):
            parts.append(petal_outline(i, glow, 56, ' opacity="0.15" filter="url(#glowblur)"'))
    for i in range(6):
        c = colors[i]
        parts.append(petal_outline(i, c, 53))                       # base rim body (full size)
        parts.append(petal_outline(i, rim, 53, f' opacity="{rim_op}" mask="url(#topfade)"'))
        parts.append(petal_elem(i, c, c, 43))                       # body covers interior
    if sheen_op > 0:
        for i in range(6):
            rot = f' transform="rotate({i*60} 512 512)"' if i else ""
            parts.append(f'<path d="{PETAL}" fill="url(#sheenG)" stroke="url(#sheenG)" '
                         f'stroke-width="43" stroke-linejoin="round"{rot}/>')
    parts.append("</g>")
    return "".join(parts)

# ---------------------------------------------------------------- mode builders
def icon_default(idp=""):
    defs = (
        f'<radialGradient id="bg{idp}" cx="0.5" cy="0.42" r="0.75">'
        f'<stop offset="0" stop-color="{CREAM_HI}"/><stop offset="1" stop-color="{CREAM_LO}"/></radialGradient>'
        + topfade_defs()
        + f'<clipPath id="sq{idp}">{SQUIRCLE}</clipPath>'
        '<filter id="petshadow" x="-20%" y="-20%" width="140%" height="140%">'
        '<feDropShadow dx="0" dy="11" stdDeviation="16" flood-color="#7A3014" flood-opacity="0.30"/></filter>'
        '<filter id="glyshadow" x="-20%" y="-20%" width="140%" height="140%">'
        '<feDropShadow dx="0" dy="2" stdDeviation="2.5" flood-color="#7A3014" flood-opacity="0.18"/></filter>'
    )
    body = (
        f'<g clip-path="url(#sq{idp})">'
        f'<rect width="1024" height="1024" fill="url(#bg{idp})"/>'
        + petal_stack2(RAMP, shadow_filter="petshadow")
        + f'<g filter="url(#glyshadow)">{glyph_group()}</g>'
        '</g>'
    )
    return defs, body

def icon_dark(idp=""):
    defs = (
        f'<radialGradient id="bgd{idp}" cx="0.5" cy="0.42" r="0.8">'
        '<stop offset="0" stop-color="#3A2118"/><stop offset="1" stop-color="#1C0F0A"/></radialGradient>'
        + topfade_defs(mid=0.60, top_op=0.85)
        + f'<clipPath id="sqd{idp}">{SQUIRCLE}</clipPath>'
        '<filter id="glowblur" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur stdDeviation="16"/></filter>'
        '<filter id="petshadowd" x="-20%" y="-20%" width="140%" height="140%">'
        '<feDropShadow dx="0" dy="12" stdDeviation="18" flood-color="#000000" flood-opacity="0.55"/></filter>'
    )
    body = (
        f'<g clip-path="url(#sqd{idp})">'
        f'<rect width="1024" height="1024" fill="url(#bgd{idp})"/>'
        + petal_stack2(RAMP, rim_op=0.6, sheen_op=0.18, glow="#FF9E6E", shadow_filter="petshadowd")
        + glyph_group()
        + '</g>'
    )
    return defs, body

def icon_clear(idp=""):
    op   = [0.14, 0.20, 0.27, 0.35, 0.44, 0.55]
    defs = (
        f'<linearGradient id="bgc{idp}" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#31343F"/><stop offset="1" stop-color="#181A22"/></linearGradient>'
        + topfade_defs(mid=0.58, top_op=0.9)
        + f'<clipPath id="sqc{idp}">{SQUIRCLE}</clipPath>'
    )
    petals = []
    for i in range(6):
        petals.append(petal_outline(i, "#FFFFFF", 56, ' opacity="0.32" mask="url(#topfade)"'))
        rot = f' transform="rotate({i*60} 512 512)"' if i else ""
        petals.append(f'<g opacity="{op[i]:.2f}"><path d="{PETAL}" fill="#FFFFFF" '
                      f'stroke="#FFFFFF" stroke-width="48" '
                      f'stroke-linejoin="round"{rot}/></g>')
    body = (
        f'<g clip-path="url(#sqc{idp})">'
        f'<rect width="1024" height="1024" fill="url(#bgc{idp})"/>'
        # glass plate
        f'<rect x="32" y="32" width="960" height="960" rx="218" fill="#FFFFFF" fill-opacity="0.07"/>'
        f'<rect x="40" y="40" width="944" height="944" rx="212" fill="none" stroke="#FFFFFF" '
        f'stroke-opacity="0.20" stroke-width="5" mask="url(#topfade)"/>'
        + "".join(petals)
        + glyph_group(colors=["#FFFFFF"] * 6, extra=' opacity="0.62"')
        + '</g>'
    )
    return defs, body

def icon_tinted(idp=""):
    tint = "#F2A278"; gly = "#FFD9C2"
    op   = [0.32, 0.42, 0.53, 0.65, 0.78, 0.92]
    defs = (
        f'<linearGradient id="bgt{idp}" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#232326"/><stop offset="1" stop-color="#151517"/></linearGradient>'
        + topfade_defs(mid=0.58, top_op=0.55)
        + f'<clipPath id="sqt{idp}">{SQUIRCLE}</clipPath>'
    )
    petals = []
    for i in range(6):
        rot = f' transform="rotate({i*60} 512 512)"' if i else ""
        petals.append(f'<g opacity="{op[i]}"><path d="{PETAL}" fill="{tint}" '
                      f'stroke="{tint}" stroke-width="48" '
                      f'stroke-linejoin="round"{rot}/></g>')
        petals.append(petal_outline(i, "#FFFFFF", 48, ' opacity="0.22" mask="url(#topfade)"'))
    body = (
        f'<g clip-path="url(#sqt{idp})">'
        f'<rect width="1024" height="1024" fill="url(#bgt{idp})"/>'
        + "".join(petals)
        + glyph_group(colors=[gly] * 6, extra=' opacity="0.85"')
        + '</g>'
    )
    return defs, body

# ---------------------------------------------------------------- mockup writers
def write(name, content):
    with open(os.path.join(OUT, name), "w") as f:
        f.write(content)
    print("wrote", name)

def mode_mockup(name, defs, body, page_bg):
    tile_shadow = ('<filter id="tileshadow" x="-20%" y="-20%" width="140%" height="140%">'
                   '<feDropShadow dx="0" dy="14" stdDeviation="22" flood-color="#000" flood-opacity="0.25"/></filter>')
    content = svg(
        f'<rect width="1024" height="1024" fill="{page_bg}"/>'
        f'<g filter="url(#tileshadow)"><rect x="32" y="32" width="960" height="960" rx="218" fill="{page_bg}"/></g>'
        + body,
        defs + tile_shadow)
    write(name, content)

# ---------------------------------------------------------------- layer sources
def write_layers():
    write("layer-1-background.svg", svg(
        '<rect width="1024" height="1024" fill="url(#bgl)"/>',
        '<radialGradient id="bgl" cx="0.5" cy="0.42" r="0.75">'
        f'<stop offset="0" stop-color="{CREAM_HI}"/><stop offset="1" stop-color="{CREAM_LO}"/></radialGradient>'))
    write("layer-2-petals.svg", svg("".join(petal_elem(i, RAMP[i]) for i in range(6))))
    write("layer-3-glyphs.svg", svg(glyph_group()))

# ---------------------------------------------------------------- context mockups
def context(name, dark):
    # wallpaper
    if dark:
        wp_defs = ('<linearGradient id="wp" x1="0" y1="0" x2="1" y2="1">'
                   '<stop offset="0" stop-color="#1B2033"/><stop offset="0.55" stop-color="#2A2137"/>'
                   '<stop offset="1" stop-color="#12151F"/></linearGradient>')
        blobs = ('<g filter="url(#blob)">'
                 '<circle cx="230" cy="260" r="260" fill="#3E2E56" opacity="0.55"/>'
                 '<circle cx="820" cy="720" r="300" fill="#233B54" opacity="0.5"/>'
                 '<circle cx="700" cy="180" r="180" fill="#54312E" opacity="0.35"/></g>')
        tile_fill, tile_op, tile_str = "#FFFFFF", 0.10, 0.14
        defs, body = icon_dark("c")
    else:
        wp_defs = ('<linearGradient id="wp" x1="0" y1="0" x2="1" y2="1">'
                   '<stop offset="0" stop-color="#BFD3D8"/><stop offset="0.5" stop-color="#E4CDBD"/>'
                   '<stop offset="1" stop-color="#C9AE9F"/></linearGradient>')
        blobs = ('<g filter="url(#blob)">'
                 '<circle cx="250" cy="240" r="260" fill="#F3E1C8" opacity="0.7"/>'
                 '<circle cx="810" cy="740" r="300" fill="#A9C4C6" opacity="0.6"/>'
                 '<circle cx="720" cy="200" r="170" fill="#E6B29A" opacity="0.45"/></g>')
        tile_fill, tile_op, tile_str = "#FFFFFF", 0.42, 0.55
        defs, body = icon_default("c")

    T = 180.0; gap = 81.0
    xs = [161, 422, 683]; ys = [292, 553]
    rx = 41
    tiles = []
    slots = [(x, y) for y in ys for x in xs]
    our = slots[1]  # top row middle
    for (x, y) in slots:
        if (x, y) == our:
            continue
        tiles.append(f'<g filter="url(#ctshadow)"><rect x="{x}" y="{y}" width="180" height="180" rx="{rx}" '
                     f'fill="{tile_fill}" fill-opacity="{tile_op}"/></g>'
                     f'<rect x="{x+2}" y="{y+2}" width="176" height="176" rx="{rx-1}" fill="none" '
                     f'stroke="#FFFFFF" stroke-opacity="{tile_str*0.5}" stroke-width="2.5" mask="url(#topfade)"/>')
    s = T / 1024.0
    ox, oy = our
    our_tile = (f'<g filter="url(#ctshadow)"><g transform="translate({ox} {oy}) scale({s:.5f})">'
                + body + "</g></g>")
    extra_defs = (wp_defs
                  + '<filter id="blob" x="-60%" y="-60%" width="220%" height="220%">'
                    '<feGaussianBlur stdDeviation="70"/></filter>'
                  + '<filter id="ctshadow" x="-30%" y="-30%" width="160%" height="160%">'
                    f'<feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#000" '
                    f'flood-opacity="{0.35 if dark else 0.22}"/></filter>')
    content = svg(
        '<rect width="1024" height="1024" fill="url(#wp)"/>' + blobs
        + "".join(tiles) + our_tile,
        extra_defs + defs)
    write(name, content)

# ---------------------------------------------------------------- main
if __name__ == "__main__":
    d, b = icon_default();  mode_mockup("01-composer-default.svg", d, b, "#ECECEF")
    d, b = icon_dark();     mode_mockup("02-composer-dark.svg", d, b, "#0F0F13")
    d, b = icon_clear();    mode_mockup("03-composer-clear.svg", d, b, "#101116")
    d, b = icon_tinted();   mode_mockup("04-composer-tinted.svg", d, b, "#101013")
    write_layers()
    context("05-context-default.svg", dark=False)
    context("06-context-dark.svg", dark=True)
