# WhatFun — Icon Composer rebuild notes

Rebuild of the flat pinwheel icon as a 3-layer Liquid Glass icon (.icon) for iOS 26,
using Icon Composer (Xcode 26 / WWDC25 tooling).

## Files

Mockups (how each dynamic mode should render):
- `01-composer-default.svg` — Default (light)
- `02-composer-dark.svg` — Dark
- `03-composer-clear.svg` — Clear (frosted glass)
- `04-composer-tinted.svg` — Tinted (mono, user tint)

Layer sources (drag these into Icon Composer, bottom to top):
- `layer-1-background.svg` — cream radial gradient
- `layer-2-petals.svg` — six-petal pinwheel, transparent background; the center
  sparkle is a *hole* in this layer
- `layer-3-glyphs.svg` — five tone-on-tone media glyphs, transparent background

## Layer stack and per-layer settings

Order in Icon Composer (bottom → top):

### 1. Background
- Content: don't import the SVG if you prefer native controls — set the icon
  background to a radial-ish gradient in Composer: `#FBF1E4` (center-top) →
  `#F6E7D3` → `#EDD7BC` (edges). Otherwise import `layer-1-background.svg`.
- Settings: no specular, no blur, no shadow. This layer is what the sparkle
  reveals, so keep it calm.

### 2. Petals (the hero glass layer)
- Content: `layer-2-petals.svg`. One group containing all six petals.
  Ramp, clockwise from top: `#FFD9C7 #FFB59B #FF9270 #F76F4E #E14F33 #B93A24`.
- Settings:
  - **Specular: ON.** This is what the mockups simulate with the white
    top-edge rim — Composer does it live and it tracks device tilt.
  - **Shadow: Neutral, soft**, small offset (the mockups use dy≈13/blur≈15 at
    ~30% of a deep ember `#8A3A1C`). Chromatic shadow also works but keep it subtle
    on the cream background.
  - **Translucency/opacity: 100%** in Default/Dark. Do not add blur — the petals
    should read as solid enamel-glass, not frosted (Clear mode frosts them for free).
  - Keep all six petals in ONE group so specular and shadow treat them as one
    slab and internal overlaps never double-shade.

### 3. Glyphs
- Content: `layer-3-glyphs.svg`. Fills are lighter tints of each host petal
  (`#FFE4D6 #FFCFBE #FFC0A8 #F9B096 #EC9D86`) so they read as etched, not stamped.
- Settings:
  - **Specular: OFF** (they are engravings, not separate glass).
  - **Shadow: minimal or off.** The mockups use a 3px whisper of shadow plus a
    1–2px darker offset copy to fake a deboss; in Composer the separate layer
    already gives a slight parallax lift, which sells the same idea.
  - Opacity 100%.

## The sparkle as negative space

The 6-point sparkle is not drawn anywhere — it is the transparent gap between
the six inward-pointing petal tips in layer 2. Because it is a hole in a floating
glass layer:

- **Default:** reveals the cream gradient background; specular catches the hole's
  upper inside edges, so the star looks *carved into* the glass.
- **Dark:** reveals the deep ember background — the sparkle inverts to a dark
  star, still crisp, and reads as depth rather than a printed mark.
- **Clear:** reveals wallpaper through the frosted slab — the strongest version
  of the effect; the star is literally a window.
- **Tinted:** reveals the dark platter; the mono ramp keeps the star silhouette.
- Bonus: as the user tilts the device, parallax between layer 2 and the
  background makes the sparkle appear to sit deeper than the petals. Free.

## How each dynamic mode treats the design

- **Default:** cream gradient bg; petals full-color ramp light→deep clockwise
  from top; specular rim + soft shadow give the float.
- **Dark:** Composer darkens/keeps the background per your Dark variant — set the
  background Dark appearance to `#3A1D12 → #150803`. Nudge the petal ramp very
  slightly desaturated/darker if you want (mockup uses `#F5C6AE…#A0311D`), or let
  the defaults ride. Glass edges pick up a warm glow.
- **Clear:** system replaces fills with frosted glass over the wallpaper. Your
  ramp survives as a *lightness* ramp (mockup: greys `#F4F5F7…#959BA5` at ~60%
  translucency). No work needed beyond checking the Clear preview.
- **Tinted:** system maps luminance → user tint. Because the ramp is a single
  hue stepped by lightness, it degrades perfectly to a brightness ramp of one
  tint (mockup tint `#FF9670`, lightest petal brightest). This is the payoff of
  the single-hue-ramp direction: mono modes keep the pinwheel legible.

Check all four in Composer's mode picker; only Background needs an explicit
Dark variant — everything else is derived.

## Wiring the .icon into the Xcode project

1. In Icon Composer: New icon → import the three layer SVGs bottom-to-top →
   apply the settings above → save as `AppIcon.icon`.
2. Drag `AppIcon.icon` into the Xcode project root (target membership: WhatFun).
   It lives beside the asset catalog, not inside it.
3. Target → General → App Icons and Launch Screen → **App Icon** = `AppIcon`
   (equivalently Build Settings → Asset Catalog Compiler:
   `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; the .icon file wins over a
   same-named appiconset).
4. Remove or keep `WhatFun/Resources/Assets.xcassets/AppIcon.appiconset/` —
   keep it only if you still build with Xcode < 26 or target iOS < 26 fallbacks;
   the 1024 flat PNG is the automatic fallback rendition. If you keep both,
   the names must match so older OSes get the flat PNG.
5. Build & run on iOS 26: check Home Screen in Default, Dark, Clear, Tinted,
   plus Settings/Spotlight sizes — the sparkle must stay open at 60×60.

## Mockup caveats

These SVGs *simulate* Liquid Glass: the specular rim is a static top-lit white
gradient stroke, the sheen a fixed vertical wash, shadows are flat drop shadows,
and Clear-mode frosting is opacity math over a fake wallpaper gradient. Real
rendering is dynamic — specular tracks device motion, blur samples the actual
wallpaper, and the system masks to the squircle and enforces its own shadow
curves. Treat the mockups as art direction, not pixel truth; the .icon built
from the three layer files is the source of record. Also note the mockups show
the full 1024 square — the OS will crop to the squircle, which trims the outer
petal corners slightly (geometry keeps all content inside r≈466 so nothing
important is lost).
