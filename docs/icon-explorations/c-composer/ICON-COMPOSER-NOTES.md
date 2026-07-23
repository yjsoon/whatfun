# WhatFun — Icon Composer (Liquid Glass) rebuild notes

Layered rebuild of the WhatFun pinwheel icon for iOS 26 Icon Composer (.icon format, WWDC25).
All mockups in this folder are **simulations** — see caveats at the bottom.

## Files

Mode mockups (1024×1024 SVG): `01-composer-default.svg`, `02-composer-dark.svg`,
`03-composer-clear.svg`, `04-composer-tinted.svg`.
Home-screen context: `05-context-default.svg`, `06-context-dark.svg` (~180 px tile among
neutral squircles).
Layer sources: `layer-1-background.svg`, `layer-2-petals.svg`, `layer-3-glyphs.svg`.
Best-effort Icon Composer document: `AppIcon.icon/` (see confidence section).
Generator: `gen.py` (all geometry defined once; re-run to regenerate everything).

## What changed in this revision (client fixes)

- **Ramp rebalanced** (fix 1): the six-step ember ramp now starts deeper so the top petal no
  longer dissolves into the cream background.
  New ramp, light → deep, clockwise from the top petal:
  `#F2AF89  #EE9569  #E67A4E  #D95F38  #C64828  #A6371C`
  (Background cream stays `#F6E7D3`; mockups use a subtle radial `#FBF2E3 → #EFDCC2`.)
- **Sixth glyph added** (fix 2): the top petal now carries a **generic app squircle** — a
  chunky rounded-square outline — same etched tone-on-tone treatment as the other five
  (book, filmstrip, TV, gamepad, microphone). Glyph tints are each petal's color mixed 55%
  toward white: `#F9DBCA #F7CFBB #F4C3AF #EEB7A5 #E5AD9E #D7A599`.
- **Negative-space sparkle**: the six petal tips stop ~80 px short of center; the hole between
  them *is* the sparkle. In the layered icon it is literally transparent in the petal layer, so
  whatever the background layer (or, in Clear mode, the wallpaper) does shows through — the
  sparkle re-themes itself for free in every mode.

## Layer stack (bottom → top)

| # | Layer | Source file | Content |
|---|-------|-------------|---------|
| 1 | Background | `layer-1-background.svg` (or just the Composer background fill) | cream radial gradient |
| 2 | Petals | `layer-2-petals.svg` | six-petal pinwheel, one group, sparkle = transparent hole |
| 3 | Glyphs | `layer-3-glyphs.svg` | six etched glyphs, transparent elsewhere |

Petal construction: one irregular-pentagon path (tip at r≈80 from center, shoulders r≈190 at
±28°, outer corners r≈415 at ±27°, bulged outer edge), instanced six times with
`rotate(60·i, 512, 512)`; corners rounded via fill + same-color 48 px stroke with
`stroke-linejoin="round"`. Neighboring petals just overlap mid-radius (closes the sparkle) and
part again at the rim (keeps the pinwheel articulation).

## Recommended Icon Composer settings per layer

**Background** — don't import an image layer; use the document background fill instead:
- Fill: automatic gradient from `#F6E7D3` (Composer derives the light gradient).
- Dark-appearance override: automatic gradient from `#311C13` (deep warm brown, not black —
  keeps the sparkle warm in dark mode).

**Petals group** (the Liquid Glass carrier):
- Specular: **ON** (this gives the top-edge glass highlight simulated in the mockups).
- Shadow: **Neutral**, opacity ≈ 0.5 → soft lift off the background; the sparkle hole reads as
  a die-cut with real depth.
- Translucency: **ON**, value ≈ 0.35 → faint background glow through the petals.
- Blur (material): **none** — the petals should read as tinted glass, not frosted mush.
- Lighting: **Individual** — each petal catches the specular independently, so the pinwheel
  glints petal-by-petal as the device tilts.

**Glyphs group**:
- Specular: **OFF**, Shadow: **none**, Translucency: **OFF** — the glyphs are etched into the
  petals, not floating chips of glass. (If you want a touch of parallax lift, a *Layer-color*
  shadow at ≈0.2 is the most you should add; anything more reads as stickers.)
- Being the top group it still gets the strongest parallax offset, which gives the etching a
  gentle engraved shimmer on tilt.

## How each dynamic mode treats the design (mockups 01–04)

- **Default** (`01`): cream gradient bg; petals get specular top edge + neutral shadow;
  sparkle = cream showing through the hole.
- **Dark** (`02`): background swaps to deep warm brown (the dark fill override); petal colors
  are kept by the system; glass edges pick up a subtle warm glow; sparkle inverts to a dark
  star punched in a glowing ember wheel — strong identity carry-over.
- **Clear** (`03`): system re-renders layers as translucent glass over the wallpaper. The value
  ramp survives as an opacity ramp (mockup uses white fills at 0.14 → 0.55), so light → deep
  still reads. The sparkle is now a hole straight through to the wallpaper — the one element
  that gets *more* interesting in Clear.
- **Tinted** (`04`): mono rendering; the hue ramp collapses to a brightness/opacity ramp of the
  user's tint (mockup: one tint at 0.32 → 0.92), glyphs a lighter tint. Ordering stays legible
  because the ramp was built on value steps, not hue steps.

Context mockups `05`/`06` place the icon on a 3×2 grid of neutral frosted squircles over
abstract gradient wallpapers (light and dark) at a realistic ~180 px tile, to judge
presence-at-size: the wheel silhouette and sparkle stay legible; glyphs read as texture, which
is the intended behavior at home-screen size.

## AppIcon.icon bundle (best-effort — read this)

`AppIcon.icon/` is a hand-built Icon Composer document: `icon.json` + `Assets/petals.svg` +
`Assets/glyphs.svg`, wired with the settings above (background as document fill with a dark
specialization; petals group specular+shadow+translucency; glyphs group inert).

**Confidence: schema PARTIALLY VERIFIED, bundle itself UNVERIFIED on a Mac.**
- Field names/types (`fill`, `automatic-gradient`, `groups[].layers[].image-name`, `specular`,
  `shadow{kind,opacity}`, `translucency{enabled,value}`, `blur-material`, `lighting`,
  `supported-platforms`, `*-specializations`, `color-space-for-untagged-svg-colors`, color
  strings as `srgb:r,g,b,a` with 5-decimal components, assets in `Assets/` referenced with
  extension) were cross-checked against the open-source `ethbak/icon-composer-mcp` project,
  which reads and writes real Icon Composer bundles. It has NOT been opened in a live
  Icon Composer.
- **Group z-order in the JSON array could not be verified.** The bundle lists Glyphs first,
  Petals second (sidebar-style, top first). If Icon Composer opens it with petals covering the
  glyphs, drag the Petals group below Glyphs in the sidebar — content is unaffected.
- If the bundle refuses to open at all, fall back to the reliable path below; you lose nothing
  but two minutes of toggle-clicking.

**Reliable path (always works):** open Icon Composer → New Icon → drag in
`layer-2-petals.svg`, then `layer-3-glyphs.svg` (keep glyphs above petals) → set the background
fill and per-group toggles listed above → check all four appearance tabs → save as
`AppIcon.icon`.

## Wiring the .icon file into the Xcode project (iOS 26)

1. Drag `AppIcon.icon` into the WhatFun project in Xcode 26 (copy if needed; add to the app
   target). It sits alongside `Assets.xcassets` — it does **not** go inside the catalog.
2. Target → **General → App Icons and Launch Screen → App Icon → `AppIcon`** (equivalently the
   build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`). Because the .icon document
   and the legacy set share the name, Xcode uses the .icon for iOS 26+ and falls back to the
   `AppIcon.appiconset` in `WhatFun/Resources/Assets.xcassets` for older OS versions — keep a
   re-exported flat PNG (with the rebalanced ramp) there for iOS ≤ 18.
3. Build & run on iOS 26: verify Settings → Home Screen appearance switches
   (Default / Dark / Clear / Tinted) against mockups 01–04.

## Caveats — mockups vs. real Liquid Glass

The SVGs fake, with static gradients and blurs, what Liquid Glass computes dynamically:
real specular highlights are lighting-model driven and move with device tilt; Clear and Tinted
are generated by the system from the layer structure (the real ones will differ in exact
opacity and blur — the mockups only demonstrate that the *structure* survives); real shadows
and translucency respond to the wallpaper behind the icon. Treat 01–06 as design intent, and
the Icon Composer preview (all four modes, multiple sizes) as the source of truth before
shipping.
