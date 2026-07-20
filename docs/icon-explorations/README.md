# Icon explorations

First-round riffs on the current pinwheel app icon, produced July 2026. All icons are
1024×1024 vector SVGs; every variation ships in a light and a dark build. `gallery.html`
is a self-contained side-by-side viewer for all of them (open it in any browser).

The brief, from feedback on the current icon:

- Replace the mixed palette with progressive shades of a single hue.
- Keep the negative-space center sparkle; explore other shapes the center could form.
- Make the media glyphs lighter — etched out of the surface rather than dark stamps.
- Provide a dark-mode version of everything.
- Explore what the iOS 26 Icon Composer layered format could add.

## a-shades — progressive shades, etched glyphs

Four single-hue tonal ramps (ember, ocean, plum, moss). Six petals step light → deep
clockwise from the blank top card; glyphs are debossed tone-on-tone with a subtle
highlight/shadow fringe. `gen.py` regenerates all eight SVGs; ramps are one-line edits.

## b-centers — negative-space center shapes

Same pinwheel language and ember ramp, with the petal tips re-carved so the true
negative space forms a play button, a camera aperture, a five-point rating star, or a
heart. `gen_b_centers.py` regenerates the set.

## c-composer — iOS 26 Icon Composer rebuild

A three-layer Liquid Glass version: background gradient, petal slab (the sparkle is a
transparent hole in this layer), and glyph layer. Includes mockups of the Default,
Dark, Clear, and Tinted dynamic modes, the separated layer sources ready to drag into
Icon Composer, and `ICON-COMPOSER-NOTES.md` with per-layer settings and Xcode wiring.
