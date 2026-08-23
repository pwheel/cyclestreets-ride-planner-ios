# Design: Wheel Routes app icon and wordmark

> No app icon exists yet — `Assets.xcassets/AppIcon.appiconset/Contents.json`
> declares the 3 required iOS slots (any/dark/tinted appearance, 1024x1024)
> but has never had artwork assigned. This spec locks the visual concept;
> producing the actual `.appiconset` PNGs/SVG source is a follow-up
> implementation task, not covered here.

## Summary

An icon built from two motifs specific to what the app does — a bicycle
wheel (the "Wheel" in Wheel Routes) and a route/waypoint (the "Routes") —
rather than generic bike or map clip art. A compass needle stands in for
one spoke, tying the wheel to navigation without adding a separate map-pin
or compass glyph.

## Icon concept

- **Rim**: a plain circle outline (the tire).
- **Spokes**: 12 thin straight spokes, evenly spaced (every 30°), running
  from a small hub disc to just inside the rim. Spoke *count and thinness*
  is the deliberate choice that reads as "bicycle wheel" rather than
  "steering wheel" — a steering wheel silhouette almost always shows 3
  thick spokes, so density alone disambiguates it at a glance, including at
  small (tab bar / notification) sizes.
- **Compass needle**: one additional element, not one of the 12 spokes —
  a two-tone kite/diamond shape pivoting through the hub, tip pointing
  outward past the rim. Colored so the two ends are visually distinct
  (accent color tip / white tail), the way a real compass needle reads.
  - **Angle**: 60° clockwise from vertical (compass-bearing convention,
    i.e. measured from north/12 o'clock, not from the horizontal axis).
    At this angle the needle deliberately overlaps the nearest plain spoke
    (the one at the 60°-from-vertical position) rather than sitting in the
    gap between two spokes — tried both and the overlapping version reads
    as more integrated with the wheel rather than a separate object stuck
    on top.
  - **Hub**: the needle's pivot point is a small filled disc (fill =
    background color, white stroke) that sits on top of both the needle
    base and the converging spoke ends, giving a clean pivot rather than a
    cluster of lines meeting at a point.

## Color

**Terracotta** background (`#B5472E`), white spokes/rim, with the compass
needle in **teal** (`#123C36`, tip) and white (tail).

Considered and rejected in favor of terracotta:
- Deep teal (`#123C36` as background) and forest green (`#1E4630`) — both
  read as generic "eco/outdoors transport app" green, no stronger a fit for
  a *cycling* app specifically than for any green-branded app.
- Navy (`#16233F`) — reads more "maps/routing," a reasonable alternative,
  but less distinctive in an iOS home screen full of blue app icons.

Terracotta is uncommon among iOS app icons generally, so it stands out in
a home screen grid; it also forced the needle's accent color off coral
(which was the accent on the other three background options but loses
contrast against terracotta) onto teal instead — teal-on-terracotta is the
combination now used everywhere the icon appears.

## Wordmark lockups

Three pairings of the icon with "Wheel Routes" text, for contexts outside
the app-icon slot itself:

1. **Horizontal, light background** — icon square (terracotta bg, same
   glyph as above) at left, "Wheel Routes" set in bold sans-serif, warm
   near-black (`#2A2420`) to the right, vertically centered. For the
   Settings → About section, README, and other light-background UI.
2. **Full-bleed banner** — the icon's linework drawn directly on a
   terracotta field with no separate icon square (the terracotta *is* the
   background), white "Wheel Routes" text to the right. For a splash
   screen or any dark/terracotta context.
3. **Stacked** — icon square centered above tracked, uppercase "WHEEL
   ROUTES" text, both centered on a light background. For a square-format
   use (splash screen, social/App Store thumbnail) where a horizontal
   lockup wouldn't fit.

Typeface is left as system sans-serif (`-apple-system`/Helvetica Neue) for
now — no custom typeface has been evaluated or chosen.

## Out of scope for this spec

- Producing final vector artwork and the actual iOS `AppIcon.appiconset`
  PNG exports (all required sizes, plus the dark/tinted appearance
  variants the `Contents.json` already declares slots for).
- Wiring a wordmark lockup into any actual screen (About section, splash
  screen) — none of the three lockups above are used anywhere in the app
  yet; this spec only fixes what they should look like when that work
  happens.
- Typeface selection for the wordmark.
