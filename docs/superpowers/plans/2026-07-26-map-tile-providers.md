# Map Tile Providers (Apple + OpenStreetMap) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user switch the Map screen between Apple's native map styles (Standard/Hybrid/Satellite) and three OpenStreetMap-tile styles (OSM Standard, CyclOSM, Cycle Map) via a bottom-right "layers" button, resolving [GitHub issue #9](https://github.com/pwheel/cyclestreets-ride-planner-ios/issues/9).

**Architecture:** Apple styles keep using the existing SwiftUI `Map`. OSM styles render through `MapLibreSwiftUI.MapView` (from the new `maplibre/swiftui-dsl` SPM package), pointed at a small self-authored MapLibre raster-style JSON built per style. `MapViewModel` is untouched; all new logic lives in a new `MapStyleOption` model and in `MapView.swift`'s rendering layer.

**Tech Stack:** SwiftUI, MapKit, MapLibre Native via `maplibre/swiftui-dsl` (SPM, pinned `v0.25.0`), Swift Testing.

## Global Constraints

- Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest, for all new unit tests.
- `@Observable @MainActor final class` for ViewModels; plain `Codable, Equatable` structs/enums for models. (No ViewModel changes in this plan — `MapViewModel` stays renderer-agnostic.)
- Don't hand-edit `project.pbxproj` to add/remove *source files* — the synced-folder target picks them up automatically. (SPM package references are the one exception requiring a `project.pbxproj` change, and that must go through Xcode's own "Add Package Dependencies" UI, not a raw text edit — see Task 1.)
- `docs/SPEC.md` must be updated in the same commit as any change that adds/removes/materially changes a screen, ViewModel contract, or cross-cutting pattern (Task 7).
- Full suite: `xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation`.
- **Known pre-existing flake:** `MapViewModelTests/testSearchTextChangedDoesNotSetErrorMessageWhenDebounceFires` occasionally fails under parallel-clone load (confirmed pre-existing, unrelated to this work, passes in isolation). If it's the *only* failure in a full-suite run, re-run with `-only-testing:` for that one test to confirm before treating the run as red.
- **Naming collision:** the new `MapLibreSwiftUI` package exports a type literally named `MapView` — the same name as this app's own `struct MapView: View` in `Features/Map/MapView.swift`. Inside that file, always write the fully-qualified `MapLibreSwiftUI.MapView(...)` when constructing the MapLibre view; a bare `MapView(...)` there is ambiguous and won't compile.
- **Missing real Thunderforest key:** unlike the CycleStreets key, there is no existing Thunderforest account/key anywhere in this project's history. Task 2 sets up the `skip-worktree` placeholder plumbing, but "OSM Standard" and "Cycle Map" styles will not actually load tiles until a real key is obtained (free signup at thunderforest.com) and placed in the local `ThunderforestAPIKey_dev.txt`. This doesn't block any coding task — it only limits how much of Task 8's manual verification can be completed for those 2 styles until a real key exists.

---

### Task 1: Add the MapLibre SPM package dependency

**Files:**
- Modify: `CycleStreets Ride Planner.xcodeproj/project.pbxproj` (via Xcode UI only)

**Interfaces:**
- Produces: the `MapLibreSwiftUI` and `MapLibreSwiftDSL` modules become importable from app target source files (used starting Task 4).

This step can't be scripted safely — Xcode's `project.pbxproj` package-reference format is easy to corrupt by hand, and this project has zero existing `XCRemoteSwiftPackageReference` entries to pattern-match against. Do it through Xcode itself:

- [x] **Step 1: Add the package in Xcode**

Open `CycleStreets Ride Planner.xcodeproj` in Xcode. File → Add Package Dependencies… Enter the URL:

```
https://github.com/maplibre/swiftui-dsl
```

Dependency Rule: **Exact Version** → `0.25.0` (not "Up to Next Major" — this is a pre-1.0 package per its own README, so pin exactly). When the product picker appears, add both **`MapLibreSwiftUI`** and **`MapLibreSwiftDSL`** to the **"CycleStreets Ride Planner"** app target (not the test targets).

- [x] **Step 2: Verify it resolved and the project still builds**

Run:
```bash
xcodebuild -resolvePackageDependencies -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner"
```
Expected: resolves without error, and a `Package.resolved` (or equivalent lock state) now references `swiftui-dsl` at `0.25.0`.

Then:
```bash
xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation
```
Expected: `** BUILD SUCCEEDED **` (no source changes yet, just confirming the new dependency links cleanly).

- [x] **Step 3: Commit**

```bash
git add "CycleStreets Ride Planner.xcodeproj/project.pbxproj" "CycleStreets Ride Planner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
git commit -m "build: add maplibre/swiftui-dsl package dependency (v0.25.0)"
```
(Adjust the second path if Xcode places the resolved-package lock file elsewhere — check `git status` for the actual new/modified path under `project.xcworkspace/`.)

---

### Task 2: Generalize API key loading and add the Thunderforest key

**Files:**
- Modify: `CycleStreets Ride Planner/Networking/APIKey.swift`
- Modify: `CycleStreets Ride Planner/App/AppEnvironment.swift`
- Create: `CycleStreets Ride Planner/Resources/ThunderforestAPIKey_dev.txt`
- Modify: `.gitignore`
- Test: `CycleStreets Ride PlannerTests/Networking/APIKeyTests.swift`

**Interfaces:**
- Produces: `APIKey.loadThunderforestKey() throws -> String`, `EnvironmentValues.thunderforestAPIKey: String` (empty string if the key fails to load, mirroring the existing CycleStreets-key fallback behavior).
- Consumes: nothing new — mirrors the existing `APIKey.load()` pattern in the same file.

- [x] **Step 1: Write the failing test**

Add to `CycleStreets Ride PlannerTests/Networking/APIKeyTests.swift` (existing file — add alongside the existing `testAPIKeyLoadsFromBundle`):

```swift
    @Test func testThunderforestAPIKeyLoadsFromBundle() throws {
        let key = try APIKey.loadThunderforestKey()
        #expect(!key.isEmpty)
    }
```

- [x] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/APIKeyTests/testThunderforestAPIKeyLoadsFromBundle"
```
Expected: **build failure** — `APIKey.loadThunderforestKey()` doesn't exist yet. (A compile error is the correct "red" here, same as this codebase's other Swift Testing TDD steps where the method under test doesn't exist yet.)

- [x] **Step 3: Create the placeholder key resource file**

Create `CycleStreets Ride Planner/Resources/ThunderforestAPIKey_dev.txt` with exactly this content (a placeholder, mirroring `APIKey_dev.txt`'s existing placeholder convention):

```
YOUR_THUNDERFOREST_API_KEY_HERE
```

This lands under `Resources/`, an existing `PBXFileSystemSynchronizedRootGroup`-synced folder, so it's auto-included in the app target — no `project.pbxproj` edit needed.

- [x] **Step 4: Add the live-key gitignore entries**

In `.gitignore`, alongside the existing lines 10-11, add:

```
Resources/ThunderforestAPIKey_live.txt
**/Resources/ThunderforestAPIKey_live.txt
```

- [x] **Step 5: Refactor `APIKey.swift`**

Replace the full contents of `CycleStreets Ride Planner/Networking/APIKey.swift` with:

```swift
import Foundation

enum APIKey {
    enum Error: Swift.Error {
        case fileNotFound, empty
    }

    static func load() throws -> String {
        let name = Bundle.main.object(forInfoDictionaryKey: "APIKeyFileName") as? String
            ?? (ProcessInfo.processInfo.environment["CYCLESTREETS_ENV"] == "live"
                ? "APIKey_live" : "APIKey_dev")
        return try loadKey(named: name)
    }

    static func loadThunderforestKey() throws -> String {
        let name = ProcessInfo.processInfo.environment["CYCLESTREETS_ENV"] == "live"
            ? "ThunderforestAPIKey_live" : "ThunderforestAPIKey_dev"
        return try loadKey(named: name)
    }

    private static func loadKey(named name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            throw Error.fileNotFound
        }
        let key = (try String(contentsOf: url, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Error.empty }
        return key
    }
}
```

(`load()`'s behavior/signature is unchanged — same `APIKeyFileName` Info.plist override, same dev/live selection — only the shared file-read/trim/validate logic moved into the new private `loadKey(named:)`, reused by both key loaders.)

- [x] **Step 6: Run test to verify it passes**

```bash
xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/APIKeyTests"
```
Expected: both `APIKeyTests` pass (`testAPIKeyLoadsFromBundle` unaffected, new `testThunderforestAPIKeyLoadsFromBundle` green).

If it doesn't show up as run at all, check the `.xctest` bundle mtime against `APIKeyTests.swift`'s mtime per `CLAUDE.md`'s stale-incremental-build note, and `touch` the test file if stale.

- [x] **Step 7: Wire the environment value**

Modify `CycleStreets Ride Planner/App/AppEnvironment.swift` — add alongside the existing `APIClientKey`/`EnvironmentValues.apiClient`:

```swift
private struct ThunderforestAPIKeyKey: EnvironmentKey {
    static let defaultValue: String = (try? APIKey.loadThunderforestKey()) ?? ""
}

extension EnvironmentValues {
    var thunderforestAPIKey: String {
        get { self[ThunderforestAPIKeyKey.self] }
        set { self[ThunderforestAPIKeyKey.self] = newValue }
    }
}
```

- [x] **Step 8: Full-file build-verify**

```bash
xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation
```
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 9: Commit**

```bash
git add "CycleStreets Ride Planner/Networking/APIKey.swift" "CycleStreets Ride Planner/App/AppEnvironment.swift" "CycleStreets Ride Planner/Resources/ThunderforestAPIKey_dev.txt" "CycleStreets Ride PlannerTests/Networking/APIKeyTests.swift" .gitignore
git commit -m "feat: add Thunderforest API key loading alongside the CycleStreets key"
git update-index --skip-worktree "CycleStreets Ride Planner/Resources/ThunderforestAPIKey_dev.txt"
```

(The `skip-worktree` flag goes on *after* committing the placeholder, exactly matching this project's existing `APIKey_dev.txt` convention — see `CLAUDE.md` → Secrets.)

---

### Task 3: `MapStyleOption` model and MapLibre style-JSON generation

**Files:**
- Create: `CycleStreets Ride Planner/Features/Map/MapStyleOption.swift`
- Test: `CycleStreets Ride PlannerTests/Features/MapStyleOptionTests.swift`

**Interfaces:**
- Produces: `enum MapStyleOption: String, CaseIterable, Identifiable` with `.group`, `.isApple`, `.displayName`, `.thumbnailColor`, `.thumbnailSymbolName`, `.appleMapStyle: MapStyle?`, `.mapLibreStyleDocument(thunderforestKey:) -> MapLibreStyleDocument?`, and static `.defaultOption`. Also `struct MapLibreStyleDocument: Encodable, Equatable` with `.writeToTemporaryFile(named:) throws -> URL`.
- Consumes: `MapKit.MapStyle` (Apple's native style type).

- [x] **Step 1: Write the failing tests**

Create `CycleStreets Ride PlannerTests/Features/MapStyleOptionTests.swift`:

```swift
import Testing
@testable import CycleStreets_Ride_Planner

struct MapStyleOptionTests {

    @Test func appleStylesHaveNoTileTemplatesOrAttributionOrStyleDocument() {
        for option in [MapStyleOption.appleStandard, .appleHybrid, .appleSatellite] {
            #expect(option.group == .apple)
            #expect(option.isApple)
            #expect(option.appleMapStyle != nil)
            #expect(option.mapLibreStyleDocument(thunderforestKey: "fake-key") == nil)
        }
    }

    @Test func osmStylesAreNotApple() {
        for option in [MapStyleOption.osmStandard, .cyclOSM, .cycleMap] {
            #expect(option.group == .openStreetMap)
            #expect(!option.isApple)
            #expect(option.appleMapStyle == nil)
        }
    }

    @Test func osmStandardUsesThunderforestAtlasWithInterpolatedKey() throws {
        let document = try #require(MapStyleOption.osmStandard.mapLibreStyleDocument(thunderforestKey: "fake-key"))
        let source = try #require(document.sources["raster-tiles"])
        #expect(source.tiles == ["https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=fake-key"])
        #expect(source.attribution.contains("Thunderforest"))
    }

    @Test func cycleMapUsesThunderforestCycleWithInterpolatedKey() throws {
        let document = try #require(MapStyleOption.cycleMap.mapLibreStyleDocument(thunderforestKey: "fake-key"))
        let source = try #require(document.sources["raster-tiles"])
        #expect(source.tiles == ["https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=fake-key"])
        #expect(source.attribution.contains("Thunderforest"))
    }

    @Test func cyclOSMUsesThreeRotatingSubdomainsAndNoKey() throws {
        let document = try #require(MapStyleOption.cyclOSM.mapLibreStyleDocument(thunderforestKey: "unused"))
        let source = try #require(document.sources["raster-tiles"])
        #expect(source.tiles == [
            "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
            "https://b.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
            "https://c.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
        ])
        #expect(!source.tiles.contains { $0.contains("unused") })
        #expect(source.attribution.contains("OpenStreetMap"))
    }

    @Test func allCasesHaveDisplayNameAndDistinctThumbnailSymbol() {
        var seenSymbols = Set<String>()
        for option in MapStyleOption.allCases {
            #expect(!option.displayName.isEmpty)
            #expect(!option.thumbnailSymbolName.isEmpty)
            seenSymbols.insert(option.thumbnailSymbolName)
        }
        #expect(seenSymbols.count == MapStyleOption.allCases.count)
    }

    @Test func styleDocumentWritesValidJSONToDisk() throws {
        let document = try #require(MapStyleOption.cyclOSM.mapLibreStyleDocument(thunderforestKey: "unused"))
        let url = try document.writeToTemporaryFile(named: "test-cyclosm-style")
        let data = try Data(contentsOf: url)
        let roundTripped = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(roundTripped?["version"] as? Int == 8)
        #expect((roundTripped?["sources"] as? [String: Any])?["raster-tiles"] != nil)
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/MapStyleOptionTests"
```
Expected: build failure — `MapStyleOption` doesn't exist yet.

- [x] **Step 3: Write the implementation**

Create `CycleStreets Ride Planner/Features/Map/MapStyleOption.swift`:

```swift
import Foundation
import MapKit

enum MapStyleGroup {
    case apple
    case openStreetMap
}

enum MapStyleOption: String, CaseIterable, Identifiable {
    case appleStandard
    case appleHybrid
    case appleSatellite
    case osmStandard
    case cyclOSM
    case cycleMap

    static let defaultOption: MapStyleOption = .appleStandard

    var id: String { rawValue }

    var group: MapStyleGroup {
        switch self {
        case .appleStandard, .appleHybrid, .appleSatellite: return .apple
        case .osmStandard, .cyclOSM, .cycleMap: return .openStreetMap
        }
    }

    var isApple: Bool { group == .apple }

    var displayName: String {
        switch self {
        case .appleStandard: return "Apple Standard"
        case .appleHybrid: return "Apple Hybrid"
        case .appleSatellite: return "Apple Satellite"
        case .osmStandard: return "OSM Standard"
        case .cyclOSM: return "CyclOSM"
        case .cycleMap: return "Cycle Map"
        }
    }

    /// Apple's native `MapStyle` for the 3 Apple-provider cases; `nil` for OSM cases.
    var appleMapStyle: MapStyle? {
        switch self {
        case .appleStandard: return .standard
        case .appleHybrid: return .hybrid
        case .appleSatellite: return .imagery
        case .osmStandard, .cyclOSM, .cycleMap: return nil
        }
    }

    /// Tile URL templates in rotation order for the 3 OSM-provider cases; `nil` for Apple cases.
    /// Thunderforest-backed templates contain a `<key>` placeholder substituted in `mapLibreStyleDocument`.
    private var tileURLTemplates: [String]? {
        switch self {
        case .osmStandard:
            return ["https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=<key>"]
        case .cycleMap:
            return ["https://tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=<key>"]
        case .cyclOSM:
            return [
                "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
                "https://b.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
                "https://c.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
            ]
        case .appleStandard, .appleHybrid, .appleSatellite:
            return nil
        }
    }

    private var attribution: String? {
        switch self {
        case .osmStandard, .cycleMap:
            return "© OpenStreetMap contributors, Maps © Thunderforest"
        case .cyclOSM:
            return "© OpenStreetMap contributors, Tiles courtesy of OpenStreetMap France (CyclOSM)"
        case .appleStandard, .appleHybrid, .appleSatellite:
            return nil
        }
    }

    /// A small swatch color for `MapStyleThumbnail`, distinct per style.
    var thumbnailColor: Color {
        switch self {
        case .appleStandard: return .blue
        case .appleHybrid: return .indigo
        case .appleSatellite: return .brown
        case .osmStandard: return .green
        case .cyclOSM: return .orange
        case .cycleMap: return .teal
        }
    }

    /// An SF Symbol name for `MapStyleThumbnail`, distinct per style.
    var thumbnailSymbolName: String {
        switch self {
        case .appleStandard: return "map"
        case .appleHybrid: return "globe.americas.fill"
        case .appleSatellite: return "camera.fill"
        case .osmStandard: return "map.fill"
        case .cyclOSM: return "bicycle"
        case .cycleMap: return "bicycle.circle.fill"
        }
    }

    /// Builds the minimal MapLibre raster-style document for this OSM style, substituting
    /// `<key>` in its tile URL templates with `thunderforestKey` (a no-op for templates without
    /// the placeholder, e.g. CyclOSM). Returns `nil` for Apple cases.
    func mapLibreStyleDocument(thunderforestKey: String) -> MapLibreStyleDocument? {
        guard let templates = tileURLTemplates, let attribution else { return nil }
        let tiles = templates.map { $0.replacingOccurrences(of: "<key>", with: thunderforestKey) }
        let source = MapLibreStyleDocument.Source(tiles: tiles, attribution: attribution)
        let layer = MapLibreStyleDocument.Layer(id: "raster-tiles", source: "raster-tiles")
        return MapLibreStyleDocument(name: displayName, sources: ["raster-tiles": source], layers: [layer])
    }
}

/// A minimal MapLibre style-spec (version 8) document describing a single raster tile layer.
struct MapLibreStyleDocument: Encodable, Equatable {
    struct Source: Encodable, Equatable {
        var type = "raster"
        var tiles: [String]
        var tileSize = 256
        var attribution: String
    }

    struct Layer: Encodable, Equatable {
        var id: String
        var type = "raster"
        var source: String
    }

    var version = 8
    var name: String
    var sources: [String: Source]
    var layers: [Layer]

    /// Writes this document to `<tmp>/<name>.json` (overwriting any existing file with that
    /// name) and returns its file URL, for use as `MapLibreSwiftUI.MapView`'s `styleURL`.
    func writeToTemporaryFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
        return url
    }
}
```

Note: `Color` here is `SwiftUI.Color` — add `import SwiftUI` alongside `import MapKit` at the top of the file.

- [x] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation -only-testing:"CycleStreets Ride PlannerTests/MapStyleOptionTests"
```
Expected: all tests pass.

- [x] **Step 5: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/MapStyleOption.swift" "CycleStreets Ride PlannerTests/Features/MapStyleOptionTests.swift"
git commit -m "feat: add MapStyleOption model with MapLibre raster style-document generation"
```

---

### Task 4: Wire `MapView.swift` for dual Apple/OSM rendering

**Files:**
- Modify: `CycleStreets Ride Planner/Features/Map/MapView.swift`

**Interfaces:**
- Consumes: `MapStyleOption` (Task 3), `EnvironmentValues.thunderforestAPIKey` (Task 2), `MapLibreSwiftUI.MapView`/`MapLibreSwiftDSL` types (Task 1), `MapStyleSheet` (Task 5 — this task references it, so do Task 5 first or expect a compile error until both land; recommended order is 4 then 5 since 5 is small and self-contained, then build-verify at the end of 5).
- Produces: no new public interface — this is the screen itself.

This task is pure SwiftUI wiring — build-verify-only per this project's test-coverage convention (see `docs/SPEC.md` → Test coverage), same bucket as the existing legend row/marker code it sits alongside.

- [x] **Step 1: Add imports**

At the top of `CycleStreets Ride Planner/Features/Map/MapView.swift`, change:
```swift
import SwiftUI
import MapKit
```
to:
```swift
import SwiftUI
import MapKit
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
```

- [x] **Step 2: Replace the camera/position state with a shared region-driven helper**

Replace:
```swift
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
```
with:
```swift
    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    @State private var position = MapCameraPosition.region(MapView.initialRegion)
    @State private var mapLibreCamera = MapView.mapViewCamera(for: MapView.initialRegion)
    @State private var isPresentingMapStyleSheet = false
    @AppStorage("mapStyle") private var mapStyleRawValue = MapStyleOption.defaultOption.rawValue
    @Environment(\.thunderforestAPIKey) private var thunderforestAPIKey
```

Then add these as new private members of `MapView` (near the other private helpers, e.g. right after `init`):

```swift
    private static func mapViewCamera(for region: MKCoordinateRegion) -> MapViewCamera {
        let center = region.center
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let sw = CLLocationCoordinate2D(latitude: center.latitude - halfLat, longitude: center.longitude - halfLon)
        let ne = CLLocationCoordinate2D(latitude: center.latitude + halfLat, longitude: center.longitude + halfLon)
        return .boundingBox(MLNCoordinateBounds(sw: sw, ne: ne))
    }

    private func updateCamera(to region: MKCoordinateRegion) {
        position = .region(region)
        mapLibreCamera = MapView.mapViewCamera(for: region)
    }

    private var selectedMapStyle: MapStyleOption {
        get { MapStyleOption(rawValue: mapStyleRawValue) ?? .defaultOption }
        set { mapStyleRawValue = newValue.rawValue }
    }

    private var mapStyleBinding: Binding<MapStyleOption> {
        Binding(get: { selectedMapStyle }, set: { selectedMapStyle = $0 })
    }
```

- [x] **Step 3: Replace the 3 direct `position = .region(...)` assignments with `updateCamera(to:)`**

In `.onChange(of: pendingJourney)`, replace:
```swift
                withAnimation {
                    position = .region(MKCoordinateRegion(
                        center: end,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
```
with:
```swift
                withAnimation {
                    updateCamera(to: MKCoordinateRegion(
                        center: end,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
```

In `.onChange(of: pendingPlaceSelection)`, replace:
```swift
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: selection.place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
```
with:
```swift
            withAnimation {
                updateCamera(to: MKCoordinateRegion(
                    center: selection.place.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
```

In `selectPlace(_:)`, replace:
```swift
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: place.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
```
with:
```swift
        withAnimation {
            updateCamera(to: MKCoordinateRegion(
                center: place.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
```

- [x] **Step 4: Split `map` into an Apple branch and an OSM branch**

Replace the existing `private var map: some View { Map(position: $position) { ... } ... }` block entirely with:

```swift
    @ViewBuilder
    private var map: some View {
        if let appleStyle = selectedMapStyle.appleMapStyle {
            appleMap(style: appleStyle)
        } else if let document = selectedMapStyle.mapLibreStyleDocument(thunderforestKey: thunderforestAPIKey) {
            osmMap(document: document)
        }
    }

    private func appleMap(style: MapStyle) -> some View {
        Map(position: $position) {
            ForEach(nonSelectedRouteOptions) { option in
                if let journey = option.journey {
                    MapPolyline(coordinates: journey.allCoordinates)
                        .stroke(color(for: option.plan), lineWidth: 3)
                }
            }
            if let selectedOption = vm.routeOptions.first(where: { $0.plan == vm.selectedPlan }),
               let journey = selectedOption.journey {
                MapPolyline(coordinates: journey.allCoordinates)
                    .stroke(color(for: selectedOption.plan), lineWidth: 5)
            }
            if let from = vm.fromPlace {
                Marker("Start", coordinate: from.clCoordinate).tint(.green)
            }
            if let to = vm.toPlace {
                Marker("End", coordinate: to.clCoordinate).tint(.red)
            }
        }
        .mapStyle(style)
        .ignoresSafeArea(edges: .bottom)
        .onTapGesture { isSearchFieldFocused = false }
    }

    private func osmMap(document: MapLibreStyleDocument) -> some View {
        MapLibreSwiftUI.MapView(styleURL: osmStyleURL(for: document), camera: $mapLibreCamera) {
            for option in nonSelectedRouteOptions {
                if let journey = option.journey {
                    let source = ShapeSource(identifier: "route-\(option.plan.rawValue)") {
                        MLNPolylineFeature(coordinates: journey.allCoordinates)
                    }
                    LineStyleLayer(identifier: "route-\(option.plan.rawValue)-line", source: source)
                        .lineCap(.round)
                        .lineJoin(.round)
                        .lineColor(uiColor(for: option.plan))
                        .lineWidth(3)
                }
            }
            if let selectedOption = vm.routeOptions.first(where: { $0.plan == vm.selectedPlan }),
               let journey = selectedOption.journey {
                let source = ShapeSource(identifier: "route-\(selectedOption.plan.rawValue)-selected") {
                    MLNPolylineFeature(coordinates: journey.allCoordinates)
                }
                LineStyleLayer(identifier: "route-\(selectedOption.plan.rawValue)-selected-line", source: source)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(uiColor(for: selectedOption.plan))
                    .lineWidth(5)
            }
            if let from = vm.fromPlace {
                let startSource = ShapeSource(identifier: "waypoint-start") {
                    MLNPointFeature(coordinate: from.clCoordinate)
                }
                SymbolStyleLayer(identifier: "waypoint-start-symbol", source: startSource)
                    .iconImage(UIImage(systemName: "mappin.circle.fill")!.withRenderingMode(.alwaysTemplate))
                    .iconColor(.systemGreen)
            }
            if let to = vm.toPlace {
                let endSource = ShapeSource(identifier: "waypoint-end") {
                    MLNPointFeature(coordinate: to.clCoordinate)
                }
                SymbolStyleLayer(identifier: "waypoint-end-symbol", source: endSource)
                    .iconImage(UIImage(systemName: "mappin.circle.fill")!.withRenderingMode(.alwaysTemplate))
                    .iconColor(.systemRed)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onTapGesture { isSearchFieldFocused = false }
    }

    private func osmStyleURL(for document: MapLibreStyleDocument) -> URL {
        (try? document.writeToTemporaryFile(named: selectedMapStyle.rawValue))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("map-style-fallback.json")
    }

    private func uiColor(for plan: RoutePlan) -> UIColor {
        switch plan {
        case .quietest: return .systemGreen
        case .balanced: return .systemYellow
        case .fastest: return .systemRed
        }
    }
```

(`color(for:) -> Color`, used by `legendRow`, is untouched — `uiColor(for:)` is the OSM-path equivalent since `LineStyleLayer.lineColor(_:)` takes `UIColor`, not SwiftUI `Color`.)

- [x] **Step 5: Add the layers button and sheet**

In `body`, change:
```swift
    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 0) {
                searchBar
                if !vm.searchResults.isEmpty { resultsList }
                if !vm.routeOptions.isEmpty { legendRow.padding(.top, 8) }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Plan Route")
```
to:
```swift
    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 0) {
                searchBar
                if !vm.searchResults.isEmpty { resultsList }
                if !vm.routeOptions.isEmpty { legendRow.padding(.top, 8) }
            }
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) { layersButton }
        .navigationTitle("Plan Route")
```

Then add this private computed property alongside `legendRow`/`searchBar`:

```swift
    private var layersButton: some View {
        Button {
            isPresentingMapStyleSheet = true
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title2)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .padding()
        .sheet(isPresented: $isPresentingMapStyleSheet) {
            MapStyleSheet(selection: mapStyleBinding)
        }
    }
```

- [x] **Step 6: Build-verify**

This won't fully build until `MapStyleSheet` exists (Task 5) — proceed directly to Task 5, then come back and run:
```bash
xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation
```
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 7: Commit** (after Task 5's files exist, so the commit builds cleanly on its own)

```bash
git add "CycleStreets Ride Planner/Features/Map/MapView.swift"
git commit -m "feat: render OSM map styles via MapLibre alongside Apple's MapKit styles"
```

---

### Task 5: `MapStyleSheet` and `MapStyleThumbnail` UI

**Files:**
- Create: `CycleStreets Ride Planner/Features/Map/MapStyleSheet.swift`
- Create: `CycleStreets Ride Planner/Features/Map/MapStyleThumbnail.swift`

**Interfaces:**
- Consumes: `MapStyleOption` (Task 3).
- Produces: `MapStyleSheet(selection: Binding<MapStyleOption>)`, used by `MapView`'s `layersButton` (Task 4).

Pure SwiftUI wiring — build-verify-only, per this project's test-coverage convention. (Note: thumbnails are small SwiftUI-rendered color/symbol swatches, not bundled screenshot images — cheap to render statically like a bundled image would be, but need no asset-catalog entries or manual screenshot capture, and can't go visually stale relative to the real tile styles the way a captured screenshot could.)

- [x] **Step 1: Create `MapStyleThumbnail.swift`**

```swift
import SwiftUI

struct MapStyleThumbnail: View {
    let option: MapStyleOption

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(option.thumbnailColor.gradient)
            .overlay {
                Image(systemName: option.thumbnailSymbolName)
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 44)
    }
}
```

- [x] **Step 2: Create `MapStyleSheet.swift`**

```swift
import SwiftUI

struct MapStyleSheet: View {
    @Binding var selection: MapStyleOption
    @Environment(\.dismiss) private var dismiss

    private var appleOptions: [MapStyleOption] {
        MapStyleOption.allCases.filter { $0.group == .apple }
    }

    private var osmOptions: [MapStyleOption] {
        MapStyleOption.allCases.filter { $0.group == .openStreetMap }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Apple") {
                    ForEach(appleOptions) { option in
                        row(for: option)
                    }
                }
                Section("OpenStreetMap") {
                    ForEach(osmOptions) { option in
                        row(for: option)
                    }
                }
            }
            .navigationTitle("Map Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(for option: MapStyleOption) -> some View {
        Button {
            selection = option
            dismiss()
        } label: {
            HStack {
                MapStyleThumbnail(option: option)
                Text(option.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if option == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
```

- [x] **Step 3: Build-verify (this also completes Task 4's build)**

```bash
xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation
```
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 4: Commit** (this commit plus Task 4's — do Task 4's Step 7 commit now if not already done)

```bash
git add "CycleStreets Ride Planner/Features/Map/MapStyleSheet.swift" "CycleStreets Ride Planner/Features/Map/MapStyleThumbnail.swift"
git commit -m "feat: add the map style picker sheet"
```

---

### Task 6: Remove dead `RoutePolyline.swift`

**Files:**
- Delete: `CycleStreets Ride Planner/Features/Map/RoutePolyline.swift`

**Interfaces:** none — confirmed unreferenced anywhere in the app or test target (only its own definition matched a repo-wide grep).

- [ ] **Step 1: Delete the file and confirm nothing references it**

```bash
git rm "CycleStreets Ride Planner/Features/Map/RoutePolyline.swift"
grep -rn "RoutePolyline" "CycleStreets Ride Planner" "CycleStreets Ride PlannerTests" 2>/dev/null
```
Expected: the grep returns nothing.

- [ ] **Step 2: Build-verify**

```bash
xcodebuild build -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation
```
Expected: `** BUILD SUCCEEDED **` (confirms it really was unused).

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: remove dead RoutePolyline (superseded by SwiftUI's MapPolyline)"
```

---

### Task 7: Documentation — `docs/SPEC.md` and the design doc

**Files:**
- Modify: `docs/SPEC.md`
- Create: `docs/superpowers/specs/2026-07-26-map-tile-providers-design.md`

**Interfaces:** none — docs only.

- [ ] **Step 1: Update `docs/SPEC.md`**

In the **Architecture** section, add a bullet after the DI bullet:
```markdown
- Map rendering supports two providers, switched via `MapStyleOption` (`Features/Map/MapStyleOption.swift`): Apple's native styles (`MapStyle.standard/.hybrid/.imagery`) via SwiftUI's `Map`, and 3 OpenStreetMap-tile styles (OSM Standard/CyclOSM/Cycle Map) via `MapLibreSwiftUI.MapView` (the `maplibre/swiftui-dsl` SPM package, pinned `v0.25.0`) pointed at a small self-authored MapLibre raster-style JSON. `MapViewModel` is unaware of the distinction — it stays in `MapView.swift`.
```

In the **Map (`Features/Map/`)** section, update the `MapView` bullet to mention the layers button and both rendering paths, and remove the stale `RoutePolyline` bullet (now deleted):
```markdown
- `MapView`: search bar with From/To segmented picker, results list (tap to select, bookmark icon to save as a Saved Location), map showing one colored polyline per successfully-fetched `RouteOption` (quietest=green, balanced=yellow, fastest=red; the selected plan draws with a heavier stroke), a legend/chip row below the search bar for picking the active plan, Start/End markers (green/red), "Clear" button, toolbar link to `ItineraryView` once a route exists. A bottom-right layers button opens `MapStyleSheet`, letting the user pick between 3 Apple styles and 3 OpenStreetMap-tile styles (persisted via `@AppStorage("mapStyle")`); route/marker rendering is duplicated between the Apple (`Map`/`MapPolyline`/`Marker`) and OSM (`MapLibreSwiftUI.MapView`/`ShapeSource`+`LineStyleLayer`/`SymbolStyleLayer`) code paths since they're different underlying APIs. Tapping the map (not the search UI) dismisses the keyboard.
```
(Delete the old `RoutePolyline: MKPolyline subclass, .from(journey:) factory.` bullet entirely.)

In the **Secrets** section, add after the existing paragraph:
```markdown
Thunderforest tile-provider key follows the identical pattern: `Resources/ThunderforestAPIKey_dev.txt` (tracked, `skip-worktree`, placeholder in history) / `Resources/ThunderforestAPIKey_live.txt` (gitignored). `APIKey.loadThunderforestKey()` shares its file-read/validate logic with `APIKey.load()` via a private `loadKey(named:)` helper.
```

In **Test coverage**, add `MapStyleOptionTests` to the tested list (`Features/{...}`) and add to the "Known gaps" (build-verify-only) list: `MapStyleSheet`, `MapStyleThumbnail`.

In **Known limitations / roadmap**, remove/replace the line that pointed at the OSM-tiles roadmap item (if present) with:
```markdown
OSM tile-based map rendering (GitHub #9) is implemented — see the Map screen section above and Architecture. Design record: `docs/superpowers/specs/2026-07-26-map-tile-providers-design.md`.
```

- [ ] **Step 2: Write the design doc**

Create `docs/superpowers/specs/2026-07-26-map-tile-providers-design.md`, mirroring the structure of `docs/superpowers/specs/2026-07-25-multi-route-comparison-design.md`:

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add docs/SPEC.md docs/superpowers/specs/2026-07-26-map-tile-providers-design.md
git commit -m "docs: document the map tile provider architecture in SPEC.md and a design record"
```

---

### Task 8: Full verification pass

**Files:** none — verification only.

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17" -skipMacroValidation
```
Expected: all green. If the only failure is `MapViewModelTests/testSearchTextChangedDoesNotSetErrorMessageWhenDebounceFires`, re-run just that test in isolation (`-only-testing:` flag) per the Global Constraints note above before treating the suite as red — it's a confirmed pre-existing flake unrelated to this work.

- [ ] **Step 2: Manual simulator check**

Launch the app in the iPhone 17 simulator. Tap the bottom-right layers button — confirm the sheet opens with 6 rows grouped Apple/OpenStreetMap, each with a distinct colored thumbnail, and a checkmark on "Apple Standard" (the default). Switch to each Apple style (Standard/Hybrid/Satellite) — confirm the base map visibly changes and existing route-planning still works (search, plan a route, see 3 colored polylines + legend + Start/End markers). Switch to "CyclOSM" — confirm OSM-style tiles render (no Thunderforest key needed) with an attribution control visible, and that a previously-planned route's polylines/markers still show on top of it. If a real Thunderforest key has been placed in `ThunderforestAPIKey_dev.txt` by this point, also check "OSM Standard" and "Cycle Map" render real tiles; otherwise confirm they at least don't crash (an empty/gray map from a failed tile fetch is the expected degraded state without a real key). Relaunch the app and confirm the last-selected style persisted.

- [ ] **Step 3: Final review pass**

Work through `docs/REVIEW_CHECKLIST.md` end to end (tests, SPEC.md accuracy, historical record, secrets, commit hygiene) before considering this plan done.
