# Design: Map Tile Providers (Apple + OpenStreetMap)

> Resolves [GitHub issue #9](https://github.com/pwheel/cyclestreets-ride-planner-ios/issues/9).

## The ask

The Map view currently renders only via Apple's MapKit. Add OpenStreetMap-tile rendering as an
alternative, since CycleStreets' own routing data is OSM-based, with a "layers" control to switch
between Apple and OSM styles — including OSM's own sub-styles (Standard, CyclOSM, Cycle Map).

## Decisions made

1. **Tile sources.** Thunderforest (free-tier API key, same pattern as the existing CycleStreets
   key) provides "Atlas" (stands in for "OSM Standard") and "Cycle" (the official Cycle Map
   style). CyclOSM's own public tile server (no key) provides "CyclOSM".
2. **Scope.** Apple's Hybrid/Satellite styles are included in the same picker alongside Apple
   Standard, since the picker UI generalizes to "map style" rather than just "Apple vs OSM" — 6
   styles total.
3. **Rendering engine.** This project's original "no third-party dependencies" decision was
   explicitly relaxed for this feature: MapLibre Native (via the `maplibre/swiftui-dsl` SPM
   package) renders all 3 OSM styles through one `MapLibreSwiftUI.MapView`, each pointed at a
   small self-authored MapLibre raster-style JSON (a `MKTileOverlay`-based approach was
   considered and rejected — it would need a hand-rolled `{s}`-subdomain-rotation subclass for
   CyclOSM, versus MapLibre's native `tiles: [...]` array rotation).
4. **UI.** A bottom-right layers button opens a sheet listing all 6 styles grouped Apple/OSM,
   each with a small thumbnail and a checkmark on the active style.
5. **Thumbnails.** Rendered as small SwiftUI color+SF-Symbol swatches (`MapStyleThumbnail`)
   rather than bundled screenshot images — equally cheap/static, but avoids an asset pipeline and
   can't go stale if the real tile styles change upstream.
6. **Persistence.** `@AppStorage("mapStyle")`, declared directly in `MapView`, matching the
   existing decentralized `@AppStorage("defaultRoutePlan")`/`@AppStorage("useMetric")` pattern.

## Architecture

`MapViewModel` is untouched — it already only deals in `Place`/`Journey`/`CLLocationCoordinate2D`.
All new logic lives in:
- `MapStyleOption` (`Features/Map/MapStyleOption.swift`): the 6-case style enum, Apple/OSM
  dispatch, and MapLibre raster-style JSON generation (`MapLibreStyleDocument`).
- `MapView.swift`: branches its `map` view between the existing Apple `Map` path and a new
  `MapLibreSwiftUI.MapView`-based OSM path, sharing one canonical `MKCoordinateRegion`-driven
  camera translated into both `MapCameraPosition` (Apple) and `MapViewCamera.boundingBox(...)`
  (OSM, via `MLNCoordinateBounds`).
- `MapStyleSheet`/`MapStyleThumbnail`: the picker UI.

Route polylines and start/end markers are duplicated between the two rendering paths (SwiftUI
`MapPolyline`/`Marker` for Apple; `ShapeSource`+`LineStyleLayer`/`SymbolStyleLayer` for OSM) since
they're different underlying APIs with no shared abstraction worth building for 2 call sites.

## Attribution

MapLibre's default map controls already include an `AttributionButton` (on by default per the
`swiftui-dsl` package), so no custom overlay was needed — just ensuring each OSM style's raster
style-JSON source carries the correct `attribution` string (surfaced natively by that button).

## Testing

`MapStyleOptionTests` covers tile-URL-template correctness, key interpolation, attribution
content, and generated-document JSON validity per style — the one piece of genuinely new logic.
`MapView`'s branching, the layers button, and `MapStyleSheet`/`MapStyleThumbnail` are pure SwiftUI
wiring — build-verify-only, per this project's established convention.

## Known limitation

There is no pre-existing Thunderforest account/key in this project (unlike CycleStreets). "OSM
Standard" and "Cycle Map" won't load real tiles until a real key is obtained (free signup at
thunderforest.com) and placed in the local, `skip-worktree`-flagged `ThunderforestAPIKey_dev.txt`.
CyclOSM requires no key and works immediately.

## Files touched

`Features/Map/MapStyleOption.swift`, `Features/Map/MapStyleSheet.swift`,
`Features/Map/MapStyleThumbnail.swift`, `Features/Map/MapView.swift`, `Networking/APIKey.swift`,
`App/AppEnvironment.swift`, `Resources/ThunderforestAPIKey_dev.txt` (+ `_live.txt` gitignored),
`CycleStreets Ride PlannerTests/Features/MapStyleOptionTests.swift`,
`CycleStreets Ride PlannerTests/Networking/APIKeyTests.swift`,
`CycleStreets Ride Planner.xcodeproj/project.pbxproj` (new SPM package reference). Deleted:
`Features/Map/RoutePolyline.swift`. `docs/SPEC.md` updated in the same commit per
`docs/REVIEW_CHECKLIST.md`.
