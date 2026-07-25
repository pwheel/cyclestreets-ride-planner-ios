# CycleStreets Ride Planner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a modern Swift/SwiftUI iOS app that lets cyclists plan routes, view turn-by-turn itineraries, export GPX, save favourite routes and locations, and manage their CycleStreets account — replacing the legacy Objective-C app.

**Architecture:** MVVM with `@Observable` ViewModels and `@MainActor` isolation; SwiftUI views throughout; protocol-based `APIClient` injected via SwiftUI `Environment` for testability. All networking uses `async/await` over `URLSession`. Persistence uses `Codable` + `FileManager`.

**Tech Stack:** Swift 5.9+, SwiftUI, MapKit, CoreLocation, XCTest, `URLSession`, `FileManager`, Security framework (Keychain). No third-party dependencies. iOS 16+ target.

---

## File Structure

```
CycleStreets Ride Planner/
├── App/
│   ├── CycleStreetsRidePlannerApp.swift   – @main, injects Environment
│   ├── RootView.swift                     – TabView root (Map / Saved / Account)
│   └── AppEnvironment.swift               – EnvironmentKey for APIClient + prefs
├── Networking/
│   ├── APIClient.swift                    – APIClientProtocol + live URLSession impl
│   ├── APIKey.swift                       – Loads key from bundle txt file
│   └── Endpoints.swift                    – URL construction helpers
├── Models/
│   ├── Journey.swift                      – Journey, Segment, Coordinate, RoutePlan
│   ├── Place.swift                        – Geocoder result
│   ├── SavedRoute.swift                   – Persisted journey stub
│   ├── SavedLocation.swift                – Named saved coordinate
│   └── UserSession.swift                  – Auth state (username, token)
├── Features/
│   ├── Map/
│   │   ├── MapView.swift                  – SwiftUI MapKit view + search bar
│   │   ├── MapViewModel.swift             – Route state, geocoding, planning
│   │   └── RoutePolyline.swift            – MKPolyline overlay helper
│   ├── Itinerary/
│   │   ├── ItineraryView.swift            – Turn-by-turn list
│   │   └── ItineraryViewModel.swift       – Formats segment data for display
│   ├── GPX/
│   │   └── GPXExportButton.swift          – Downloads GPX + presents share sheet
│   ├── SavedRoutes/
│   │   ├── SavedRoutesView.swift          – List of saved routes
│   │   └── SavedRoutesViewModel.swift
│   ├── SavedLocations/
│   │   ├── SavedLocationsView.swift       – List of saved locations
│   │   └── SavedLocationsViewModel.swift
│   ├── Account/
│   │   ├── AccountView.swift              – Login form / logged-in profile
│   │   ├── AccountViewModel.swift         – Auth logic
│   │   └── KeychainHelper.swift           – Token read/write via Security framework
│   └── Settings/
│       └── SettingsView.swift             – Route type + units (pure @AppStorage)
├── Persistence/
│   ├── RouteStore.swift                   – Save/load [SavedRoute] via Codable+FileManager
│   └── LocationStore.swift                – Save/load [SavedLocation]
└── Resources/
    ├── APIKey_live.txt
    └── APIKey_dev.txt

CycleStreets Ride PlannerTests/
├── Networking/
│   ├── APIClientTests.swift
│   └── MockAPIClient.swift                – Test double conforming to APIClientProtocol
├── Models/
│   └── JourneyTests.swift
├── Features/
│   ├── MapViewModelTests.swift
│   ├── ItineraryViewModelTests.swift
│   └── AccountViewModelTests.swift
└── Persistence/
    ├── RouteStoreTests.swift
    └── LocationStoreTests.swift
```

---

## Task 1: Xcode Project Scaffold

**Files:**
- Create: `CycleStreets Ride Planner/App/CycleStreetsRidePlannerApp.swift` (Xcode generates)
- Create: `LICENSE`
- Create: `Resources/APIKey_dev.txt`
- Create: `Resources/APIKey_live.txt`

- [ ] **Step 1: Create the Xcode project**

In Xcode: File → New → Project → iOS App.
- Product Name: `CycleStreets Ride Planner`
- Bundle ID: `net.cyclestreets.ride-planner`
- Interface: SwiftUI
- Language: Swift
- Include Tests: ✓
- Save to: `/Users/paulwheeler/Development/cyclestreets-ride-planner-ios`

- [ ] **Step 2: Set deployment target**

In Xcode project settings → General → Minimum Deployments: set to **iOS 16.0**.

- [ ] **Step 3: Add the GNU GPL license**

Create `LICENSE` in the project root:

```
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007

Copyright (C) CycleStreets Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
```

- [ ] **Step 4: Create placeholder API key files**

Create `Resources/APIKey_dev.txt` and `Resources/APIKey_live.txt`, each containing a single placeholder line:

```
YOUR_API_KEY_HERE
```

Add both files to the Xcode target (Copy Bundle Resources build phase).

- [ ] **Step 5: Add a .gitignore**

```gitignore
# Xcode
*.xcuserstate
xcuserdata/
DerivedData/
*.xccheckout
*.moved-aside
*.pbxuser

# Keys — never commit real keys
Resources/APIKey_live.txt

# SPM
.build/
.swiftpm/
```

- [ ] **Step 6: Initial commit**

```bash
cd /Users/paulwheeler/Development/cyclestreets-ride-planner-ios
git init
git add .
git commit -m "chore: initial Xcode project scaffold"
```

---

## Task 2: API Key Loading

**Files:**
- Create: `CycleStreets Ride Planner/Networking/APIKey.swift`
- Test: `CycleStreets Ride PlannerTests/Networking/APIClientTests.swift` (first test in this file)

- [ ] **Step 1: Write the failing test**

Create `CycleStreets Ride PlannerTests/Networking/APIClientTests.swift`:

```swift
import XCTest
@testable import CycleStreets_Ride_Planner

final class APIKeyTests: XCTestCase {
    func testAPIKeyLoadsFromBundle() throws {
        let key = try APIKey.load()
        XCTAssertFalse(key.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/APIKeyTests" \
  | tail -20
```

Expected: FAIL — `APIKey` type not found.

- [ ] **Step 3: Implement APIKey**

Create `CycleStreets Ride Planner/Networking/APIKey.swift`:

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

- [ ] **Step 4: Add a test-bundle key file**

In Xcode, add `Resources/APIKey_dev.txt` to the **test target** as well (Build Phases → Copy Bundle Resources). The file contains `test_api_key_placeholder`.

- [ ] **Step 5: Run test to verify it passes**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/APIKeyTests" \
  | tail -20
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "CycleStreets Ride Planner/Networking/APIKey.swift" \
        "CycleStreets Ride PlannerTests/Networking/APIClientTests.swift"
git commit -m "feat: load API key from bundle text file"
```

---

## Task 3: Core Models

**Files:**
- Create: `CycleStreets Ride Planner/Models/Journey.swift`
- Create: `CycleStreets Ride Planner/Models/Place.swift`
- Test: `CycleStreets Ride PlannerTests/Models/JourneyTests.swift`

- [ ] **Step 1: Write the failing test**

Create `CycleStreets Ride PlannerTests/Models/JourneyTests.swift`:

```swift
import XCTest
@testable import CycleStreets_Ride_Planner

final class JourneyTests: XCTestCase {
    func testJourneyDecodesFromJSON() throws {
        let json = """
        {
          "journey": {
            "number": 12345678,
            "plan": "balanced",
            "lengthMetres": 4200,
            "timeSeconds": 1080,
            "segments": [
              {
                "number": 1,
                "name": "High Street",
                "distanceMetres": 450,
                "timeSeconds": 120,
                "turn": "Straight on",
                "points": [
                  {"longitude": -0.1278, "latitude": 51.5074},
                  {"longitude": -0.1280, "latitude": 51.5080}
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(JourneyResponse.self, from: json)
        XCTAssertEqual(response.journey.number, 12345678)
        XCTAssertEqual(response.journey.plan, .balanced)
        XCTAssertEqual(response.journey.segments.count, 1)
        XCTAssertEqual(response.journey.segments[0].name, "High Street")
        XCTAssertEqual(response.journey.segments[0].points.count, 2)
    }

    func testSegmentFormattedDistance() {
        let segment = Segment(
            number: 1, name: "Mill Road",
            distanceMetres: 1500, timeSeconds: 360,
            turn: "Turn left",
            points: []
        )
        XCTAssertEqual(segment.formattedDistance(metric: true), "1.5 km")
        XCTAssertEqual(segment.formattedDistance(metric: false), "0.9 mi")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/JourneyTests" \
  | tail -20
```

Expected: FAIL — types not found.

- [ ] **Step 3: Implement Journey.swift**

Create `CycleStreets Ride Planner/Models/Journey.swift`:

```swift
import Foundation
import CoreLocation

enum RoutePlan: String, Codable, CaseIterable {
    case balanced, quietest, fastest

    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .quietest: return "Quietest"
        case .fastest:  return "Fastest"
        }
    }
}

struct Coordinate: Codable, Equatable {
    let longitude: Double
    let latitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Segment: Codable, Identifiable, Equatable {
    let number: Int
    let name: String
    let distanceMetres: Int
    let timeSeconds: Int
    let turn: String?
    let points: [Coordinate]

    var id: Int { number }

    func formattedDistance(metric: Bool) -> String {
        if metric {
            let km = Double(distanceMetres) / 1000.0
            return String(format: "%.1f km", km)
        } else {
            let miles = Double(distanceMetres) / 1609.344
            return String(format: "%.1f mi", miles)
        }
    }
}

struct Journey: Codable, Identifiable, Equatable {
    let number: Int
    let plan: RoutePlan
    let lengthMetres: Int
    let timeSeconds: Int
    let segments: [Segment]

    var id: Int { number }

    func formattedDistance(metric: Bool) -> String {
        if metric {
            let km = Double(lengthMetres) / 1000.0
            return String(format: "%.1f km", km)
        } else {
            let miles = Double(lengthMetres) / 1609.344
            return String(format: "%.1f mi", miles)
        }
    }

    func formattedDuration() -> String {
        let minutes = timeSeconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    var allCoordinates: [CLLocationCoordinate2D] {
        segments.flatMap(\.points).map(\.clCoordinate)
    }
}

struct JourneyResponse: Decodable {
    let journey: Journey
}
```

- [ ] **Step 4: Implement Place.swift**

Create `CycleStreets Ride Planner/Models/Place.swift`:

```swift
import Foundation
import CoreLocation

struct Place: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let near: String?
    let coordinate: Coordinate

    var displayName: String {
        if let near { return "\(name), \(near)" }
        return name
    }

    var clCoordinate: CLLocationCoordinate2D { coordinate.clCoordinate }
}

struct PlaceSearchResponse: Decodable {
    let results: PlaceResults
}

struct PlaceResults: Decodable {
    let place: [Place]
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/JourneyTests" \
  | tail -20
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "CycleStreets Ride Planner/Models/"
git add "CycleStreets Ride PlannerTests/Models/"
git commit -m "feat: add Journey, Segment, Coordinate, Place models"
```

---

## Task 4: API Client

**Files:**
- Create: `CycleStreets Ride Planner/Networking/Endpoints.swift`
- Create: `CycleStreets Ride Planner/Networking/APIClient.swift`
- Create: `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift`

> **Note:** Verify exact request parameters against https://api.cyclestreets.net/ before shipping. The endpoint shapes below match the CycleStreets v2 public API.

- [ ] **Step 1: Write the failing test**

Add to `CycleStreets Ride PlannerTests/Networking/APIClientTests.swift`:

```swift
final class LiveAPIClientTests: XCTestCase {
    func testJourneyPlanBuildsCorrectURL() throws {
        let key = "testkey123"
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        let url  = try Endpoints.journeyPlan(from: from, to: to, plan: .balanced, apiKey: key)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["key"], key)
        XCTAssertEqual(items["plan"], "balanced")
        XCTAssertTrue(items["waypoints"]?.contains("0.1132") == true)
    }

    func testGeocodeBuildsCorrectURL() throws {
        let url = try Endpoints.geocode(query: "Cambridge", apiKey: "k")
        XCTAssertTrue(url.absoluteString.contains("Cambridge"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/LiveAPIClientTests" \
  | tail -20
```

Expected: FAIL — `Endpoints` not found.

- [ ] **Step 3: Implement Endpoints.swift**

Create `CycleStreets Ride Planner/Networking/Endpoints.swift`:

```swift
import Foundation
import CoreLocation

enum Endpoints {
    private static let base = "https://api.cyclestreets.net/v2"

    static func journeyPlan(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        plan: RoutePlan,
        apiKey: String
    ) throws -> URL {
        var c = URLComponents(string: "\(base)/journey.json")!
        // CycleStreets waypoints format: lon,lat:lon,lat
        let waypoints = "\(from.longitude),\(from.latitude):\(to.longitude),\(to.latitude)"
        c.queryItems = [
            .init(name: "key",       value: apiKey),
            .init(name: "plan",      value: plan.rawValue),
            .init(name: "waypoints", value: waypoints),
            .init(name: "format",    value: "json"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }

    static func geocode(query: String, apiKey: String) throws -> URL {
        var c = URLComponents(string: "\(base)/geocoder")!
        c.queryItems = [
            .init(name: "key",     value: apiKey),
            .init(name: "q",       value: query),
            .init(name: "results", value: "6"),
            .init(name: "format",  value: "json"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }

    static func gpxExport(journeyID: Int, apiKey: String) throws -> URL {
        var c = URLComponents(string: "https://www.cyclestreets.net/api/journey.gpx")!
        c.queryItems = [
            .init(name: "itinerary", value: "\(journeyID)"),
            .init(name: "key",       value: apiKey),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }

    static func login(username: String, password: String, apiKey: String) throws -> URL {
        var c = URLComponents(string: "\(base)/user.authenticate")!
        c.queryItems = [
            .init(name: "key",      value: apiKey),
            .init(name: "username", value: username),
            .init(name: "password", value: password),
            .init(name: "format",   value: "json"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return url
    }

}
```

- [ ] **Step 4: Implement APIClient.swift**

Create `CycleStreets Ride Planner/Networking/APIClient.swift`:

```swift
import Foundation
import CoreLocation

protocol APIClientProtocol {
    func planJourney(from: CLLocationCoordinate2D,
                     to: CLLocationCoordinate2D,
                     plan: RoutePlan) async throws -> Journey
    func geocode(query: String) async throws -> [Place]
    func downloadGPX(journeyID: Int) async throws -> Data
    func login(username: String, password: String) async throws -> String
}

final class APIClient: APIClientProtocol {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func planJourney(from: CLLocationCoordinate2D,
                     to: CLLocationCoordinate2D,
                     plan: RoutePlan) async throws -> Journey {
        let url = try Endpoints.journeyPlan(from: from, to: to, plan: plan, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(JourneyResponse.self, from: data).journey
    }

    func geocode(query: String) async throws -> [Place] {
        let url = try Endpoints.geocode(query: query, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(PlaceSearchResponse.self, from: data).results.place
    }

    func downloadGPX(journeyID: Int) async throws -> Data {
        let url = try Endpoints.gpxExport(journeyID: journeyID, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        return data
    }

    func login(username: String, password: String) async throws -> String {
        let url = try Endpoints.login(username: username, password: password, apiKey: apiKey)
        let (data, _) = try await session.data(from: url)
        struct AuthResponse: Decodable {
            struct User: Decodable { let token: String }
            let user: User
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data).user.token
    }
}
```

- [ ] **Step 5: Create MockAPIClient**

Create `CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift`:

```swift
import Foundation
import CoreLocation
@testable import CycleStreets_Ride_Planner

final class MockAPIClient: APIClientProtocol {
    var journeyToReturn: Journey?
    var placesToReturn: [Place] = []
    var gpxDataToReturn = Data("gpx content".utf8)
    var tokenToReturn = "mock_token"
    var shouldThrow: Error?

    private func checkThrow() throws {
        if let e = shouldThrow { throw e }
    }

    func planJourney(from: CLLocationCoordinate2D,
                     to: CLLocationCoordinate2D,
                     plan: RoutePlan) async throws -> Journey {
        try checkThrow()
        return journeyToReturn ?? makeJourney()
    }

    func geocode(query: String) async throws -> [Place] {
        try checkThrow()
        return placesToReturn
    }

    func downloadGPX(journeyID: Int) async throws -> Data {
        try checkThrow()
        return gpxDataToReturn
    }

    func login(username: String, password: String) async throws -> String {
        try checkThrow()
        return tokenToReturn
    }

    // MARK: - Helpers

    func makeJourney(id: Int = 1, plan: RoutePlan = .balanced) -> Journey {
        Journey(
            number: id, plan: plan, lengthMetres: 4200, timeSeconds: 1080,
            segments: [
                Segment(number: 1, name: "High Street", distanceMetres: 450,
                        timeSeconds: 120, turn: "Straight on",
                        points: [
                            Coordinate(longitude: 0.1132, latitude: 52.2054),
                            Coordinate(longitude: 0.1140, latitude: 52.2060),
                        ])
            ]
        )
    }
}
```

- [ ] **Step 6: Run tests**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/LiveAPIClientTests" \
  | tail -20
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add "CycleStreets Ride Planner/Networking/"
git add "CycleStreets Ride PlannerTests/Networking/MockAPIClient.swift"
git commit -m "feat: add APIClient, Endpoints, and MockAPIClient"
```

---

## Task 5: App Environment

**Files:**
- Create: `CycleStreets Ride Planner/App/AppEnvironment.swift`

This task wires the API client into SwiftUI's Environment so all views can access it without direct injection.

- [ ] **Step 1: Create AppEnvironment.swift**

```swift
import SwiftUI

private struct APIClientKey: EnvironmentKey {
    static let defaultValue: any APIClientProtocol = {
        let key = (try? APIKey.load()) ?? ""
        return APIClient(apiKey: key)
    }()
}

extension EnvironmentValues {
    var apiClient: any APIClientProtocol {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Update CycleStreetsRidePlannerApp.swift**

```swift
import SwiftUI

@main
struct CycleStreetsRidePlannerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 3: Create stub RootView.swift**

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Text("Map")
                .tabItem { Label("Map", systemImage: "map") }
            Text("Saved")
                .tabItem { Label("Saved", systemImage: "bookmark") }
            Text("Account")
                .tabItem { Label("Account", systemImage: "person") }
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add "CycleStreets Ride Planner/App/"
git commit -m "feat: app entry point, environment key, stub root tab view"
```

---

## Task 6: Map View Model

**Files:**
- Create: `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`
- Test: `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import CycleStreets_Ride_Planner

@MainActor
final class MapViewModelTests: XCTestCase {
    var client: MockAPIClient!
    var vm: MapViewModel!

    override func setUp() {
        client = MockAPIClient()
        vm = MapViewModel(apiClient: client)
    }

    func testSearchUpdatesPlaces() async throws {
        client.placesToReturn = [
            Place(id: "1", name: "Cambridge", near: "Cambridgeshire",
                  coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
        ]
        await vm.search(query: "Cambridge")
        XCTAssertEqual(vm.searchResults.count, 1)
        XCTAssertEqual(vm.searchResults[0].name, "Cambridge")
    }

    func testPlanRoutePopulatesJourney() async throws {
        let journey = client.makeJourney()
        client.journeyToReturn = journey
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        XCTAssertNotNil(vm.currentJourney)
        XCTAssertEqual(vm.currentJourney?.number, journey.number)
    }

    func testPlanRouteErrorSetsErrorMessage() async {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testClearRouteResetsState() async {
        client.journeyToReturn = client.makeJourney()
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        vm.clearRoute()
        XCTAssertNil(vm.currentJourney)
        XCTAssertNil(vm.fromPlace)
        XCTAssertNil(vm.toPlace)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/MapViewModelTests" \
  | tail -20
```

Expected: FAIL — `MapViewModel` not found.

- [ ] **Step 3: Implement MapViewModel**

Create `CycleStreets Ride Planner/Features/Map/MapViewModel.swift`:

```swift
import Foundation
import CoreLocation
import Observation

@Observable
@MainActor
final class MapViewModel {
    var searchResults: [Place] = []
    var fromPlace: Place?
    var toPlace: Place?
    var currentJourney: Journey?
    var isLoading = false
    var errorMessage: String?
    var routePlan: RoutePlan = .balanced

    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func search(query: String) async {
        guard !query.isEmpty else { searchResults = []; return }
        do {
            searchResults = try await apiClient.geocode(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func planRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async {
        isLoading = true
        errorMessage = nil
        do {
            currentJourney = try await apiClient.planJourney(from: from, to: to, plan: routePlan)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func clearRoute() {
        currentJourney = nil
        fromPlace = nil
        toPlace = nil
        searchResults = []
        errorMessage = nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/MapViewModelTests" \
  | tail -20
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/MapViewModel.swift"
git add "CycleStreets Ride PlannerTests/Features/MapViewModelTests.swift"
git commit -m "feat: MapViewModel with route planning and geocoding"
```

---

## Task 7: Map View

**Files:**
- Create: `CycleStreets Ride Planner/Features/Map/RoutePolyline.swift`
- Create: `CycleStreets Ride Planner/Features/Map/MapView.swift`

No unit tests for pure SwiftUI views — verify visually in the simulator.

- [ ] **Step 1: Create RoutePolyline helper**

Create `CycleStreets Ride Planner/Features/Map/RoutePolyline.swift`:

```swift
import MapKit

final class RoutePolyline: MKPolyline {
    static func from(journey: Journey) -> RoutePolyline {
        let coords = journey.allCoordinates
        return RoutePolyline(coordinates: coords, count: coords.count)
    }
}
```

- [ ] **Step 2: Create MapView**

Create `CycleStreets Ride Planner/Features/Map/MapView.swift`:

```swift
import SwiftUI
import MapKit

struct MapView: View {
    @State private var vm: MapViewModel
    @Environment(\.apiClient) private var apiClient
    @State private var searchText = ""
    @State private var selectingFor: WaypointRole = .from
    @State private var position = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2053, longitude: 0.1218),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )

    enum WaypointRole { case from, to }

    init(apiClient: any APIClientProtocol) {
        _vm = State(initialValue: MapViewModel(apiClient: apiClient))
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 0) {
                searchBar
                if !vm.searchResults.isEmpty { resultsList }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Plan Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.currentJourney != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") { vm.clearRoute() }
                }
            }
        }
        .overlay {
            if vm.isLoading { ProgressView().scaleEffect(1.5) }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var map: some View {
        Map(position: $position) {
            if let journey = vm.currentJourney {
                MapPolyline(coordinates: journey.allCoordinates)
                    .stroke(.blue, lineWidth: 4)
            }
            if let from = vm.fromPlace {
                Marker("Start", coordinate: from.clCoordinate).tint(.green)
            }
            if let to = vm.toPlace {
                Marker("End", coordinate: to.clCoordinate).tint(.red)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(
                selectingFor == .from ? "Search start location" : "Search end location",
                text: $searchText
            )
            .submitLabel(.search)
            .onSubmit { Task { await vm.search(query: searchText) } }
            if !searchText.isEmpty {
                Button { searchText = ""; vm.searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $selectingFor) {
                Text("From").tag(WaypointRole.from)
                Text("To").tag(WaypointRole.to)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var resultsList: some View {
        List(vm.searchResults) { place in
            Button {
                selectPlace(place)
            } label: {
                VStack(alignment: .leading) {
                    Text(place.name).font(.body)
                    if let near = place.near {
                        Text(near).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func selectPlace(_ place: Place) {
        searchText = ""
        vm.searchResults = []
        if selectingFor == .from {
            vm.fromPlace = place
            selectingFor = .to
        } else {
            vm.toPlace = place
        }
        if let from = vm.fromPlace, let to = vm.toPlace {
            Task { await vm.planRoute(from: from.clCoordinate, to: to.clCoordinate) }
        }
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: place.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
    }
}
```

- [ ] **Step 3: Wire MapView into RootView**

Update `CycleStreets Ride Planner/App/RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    @Environment(\.apiClient) private var apiClient

    var body: some View {
        TabView {
            NavigationStack {
                MapView(apiClient: apiClient)
            }
            .tabItem { Label("Map", systemImage: "map") }

            Text("Saved")
                .tabItem { Label("Saved", systemImage: "bookmark") }

            Text("Account")
                .tabItem { Label("Account", systemImage: "person") }
        }
    }
}
```

- [ ] **Step 4: Build and run in simulator to verify map loads**

```bash
xcodebuild build \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  | tail -5
```

Expected: BUILD SUCCEEDED. Open in simulator and confirm map tiles appear and the search bar is visible.

- [ ] **Step 5: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Map/"
git add "CycleStreets Ride Planner/App/RootView.swift"
git commit -m "feat: map view with location search and route overlay"
```

---

## Task 8: Itinerary View

**Files:**
- Create: `CycleStreets Ride Planner/Features/Itinerary/ItineraryViewModel.swift`
- Create: `CycleStreets Ride Planner/Features/Itinerary/ItineraryView.swift`
- Test: `CycleStreets Ride PlannerTests/Features/ItineraryViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `CycleStreets Ride PlannerTests/Features/ItineraryViewModelTests.swift`:

```swift
import XCTest
@testable import CycleStreets_Ride_Planner

final class ItineraryViewModelTests: XCTestCase {
    func testFormatsDistanceMetric() {
        let vm = ItineraryViewModel(journey: makeJourney(), useMetric: true)
        XCTAssertEqual(vm.totalDistance, "4.2 km")
    }

    func testFormatsDistanceImperial() {
        let vm = ItineraryViewModel(journey: makeJourney(), useMetric: false)
        XCTAssertEqual(vm.totalDistance, "2.6 mi")
    }

    func testFormatsTime() {
        let vm = ItineraryViewModel(journey: makeJourney(), useMetric: true)
        XCTAssertEqual(vm.totalTime, "18 min")
    }

    func testSegmentRowHasTurnInstruction() {
        let vm = ItineraryViewModel(journey: makeJourney(), useMetric: true)
        XCTAssertEqual(vm.rows[0].instruction, "Straight on")
        XCTAssertEqual(vm.rows[0].streetName, "High Street")
    }

    private func makeJourney() -> Journey {
        Journey(
            number: 1, plan: .balanced, lengthMetres: 4200, timeSeconds: 1080,
            segments: [
                Segment(number: 1, name: "High Street", distanceMetres: 450,
                        timeSeconds: 120, turn: "Straight on", points: [])
            ]
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/ItineraryViewModelTests" \
  | tail -20
```

Expected: FAIL — `ItineraryViewModel` not found.

- [ ] **Step 3: Implement ItineraryViewModel**

Create `CycleStreets Ride Planner/Features/Itinerary/ItineraryViewModel.swift`:

```swift
import Foundation

struct SegmentRow: Identifiable {
    let id: Int
    let streetName: String
    let instruction: String
    let distance: String
    let duration: String
}

final class ItineraryViewModel {
    let journey: Journey
    let rows: [SegmentRow]
    let totalDistance: String
    let totalTime: String

    init(journey: Journey, useMetric: Bool) {
        self.journey = journey
        self.totalDistance = journey.formattedDistance(metric: useMetric)
        self.totalTime = journey.formattedDuration()
        self.rows = journey.segments.map { seg in
            SegmentRow(
                id: seg.id,
                streetName: seg.name,
                instruction: seg.turn ?? "Continue",
                distance: seg.formattedDistance(metric: useMetric),
                duration: "\(seg.timeSeconds / 60) min"
            )
        }
    }
}
```

- [ ] **Step 4: Implement ItineraryView**

Create `CycleStreets Ride Planner/Features/Itinerary/ItineraryView.swift`:

```swift
import SwiftUI

struct ItineraryView: View {
    let journey: Journey
    @AppStorage("useMetric") private var useMetric = true

    private var vm: ItineraryViewModel {
        ItineraryViewModel(journey: journey, useMetric: useMetric)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label(vm.totalDistance, systemImage: "arrow.left.and.right")
                    Spacer()
                    Label(vm.totalTime, systemImage: "clock")
                }
                .font(.headline)
            } header: {
                Text(journey.plan.displayName + " route")
            }

            Section("Turn-by-turn") {
                ForEach(vm.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.instruction).font(.body)
                        Text(row.streetName).font(.caption).foregroundStyle(.secondary)
                        Text("\(row.distance) · \(row.duration)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Itinerary")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                GPXExportButton(journeyID: journey.number)
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/ItineraryViewModelTests" \
  | tail -20
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Itinerary/"
git add "CycleStreets Ride PlannerTests/Features/ItineraryViewModelTests.swift"
git commit -m "feat: itinerary view with turn-by-turn segments"
```

---

## Task 9: GPX Export

**Files:**
- Create: `CycleStreets Ride Planner/Features/GPX/GPXExportButton.swift`

- [ ] **Step 1: Create GPXExportButton**

Create `CycleStreets Ride Planner/Features/GPX/GPXExportButton.swift`:

```swift
import SwiftUI

struct GPXExportButton: View {
    let journeyID: Int
    @Environment(\.apiClient) private var apiClient
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await export() }
        } label: {
            if isExporting {
                ProgressView().scaleEffect(0.7)
            } else {
                Label("Export GPX", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isExporting)
        .sheet(item: $exportedFileURL) { url in
            ShareSheet(items: [url])
        }
        .alert("Export Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func export() async {
        isExporting = true
        do {
            let data = try await apiClient.downloadGPX(journeyID: journeyID)
            let filename = "route_\(journeyID).gpx"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            exportedFileURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
        isExporting = false
    }
}

// UIActivityViewController wrapper
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "CycleStreets Ride Planner/Features/GPX/"
git commit -m "feat: GPX export via API + share sheet"
```

---

## Task 10: Persistence Layer

**Files:**
- Create: `CycleStreets Ride Planner/Models/SavedRoute.swift`
- Create: `CycleStreets Ride Planner/Models/SavedLocation.swift`
- Create: `CycleStreets Ride Planner/Persistence/RouteStore.swift`
- Create: `CycleStreets Ride Planner/Persistence/LocationStore.swift`
- Test: `CycleStreets Ride PlannerTests/Persistence/RouteStoreTests.swift`
- Test: `CycleStreets Ride PlannerTests/Persistence/LocationStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `CycleStreets Ride PlannerTests/Persistence/RouteStoreTests.swift`:

```swift
import XCTest
@testable import CycleStreets_Ride_Planner

final class RouteStoreTests: XCTestCase {
    var store: RouteStore!

    override func setUp() {
        store = RouteStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    func testSaveAndLoadRoute() throws {
        let route = SavedRoute(journeyID: 42, name: "My Commute", plan: .balanced,
                               distanceMetres: 3200, timeSeconds: 900,
                               savedAt: Date())
        try store.save(route)
        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].journeyID, 42)
        XCTAssertEqual(loaded[0].name, "My Commute")
    }

    func testDeleteRoute() throws {
        let route = SavedRoute(journeyID: 99, name: "Park Ride", plan: .quietest,
                               distanceMetres: 1500, timeSeconds: 400,
                               savedAt: Date())
        try store.save(route)
        try store.delete(id: route.id)
        let loaded = try store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }
}
```

Create `CycleStreets Ride PlannerTests/Persistence/LocationStoreTests.swift`:

```swift
import XCTest
@testable import CycleStreets_Ride_Planner

final class LocationStoreTests: XCTestCase {
    var store: LocationStore!

    override func setUp() {
        store = LocationStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    func testSaveAndLoadLocation() throws {
        let loc = SavedLocation(name: "Home", coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
        try store.save(loc)
        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Home")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/RouteStoreTests" \
  -only-testing:"CycleStreets Ride PlannerTests/LocationStoreTests" \
  | tail -20
```

Expected: FAIL.

- [ ] **Step 3: Implement SavedRoute.swift and SavedLocation.swift**

Create `CycleStreets Ride Planner/Models/SavedRoute.swift`:

```swift
import Foundation

struct SavedRoute: Codable, Identifiable, Equatable {
    let id: UUID
    let journeyID: Int
    var name: String
    let plan: RoutePlan
    let distanceMetres: Int
    let timeSeconds: Int
    let savedAt: Date

    init(id: UUID = UUID(), journeyID: Int, name: String, plan: RoutePlan,
         distanceMetres: Int, timeSeconds: Int, savedAt: Date) {
        self.id = id
        self.journeyID = journeyID
        self.name = name
        self.plan = plan
        self.distanceMetres = distanceMetres
        self.timeSeconds = timeSeconds
        self.savedAt = savedAt
    }
}

extension Journey {
    func asSavedRoute(name: String? = nil) -> SavedRoute {
        SavedRoute(journeyID: number, name: name ?? "Route \(number)",
                   plan: plan, distanceMetres: lengthMetres,
                   timeSeconds: timeSeconds, savedAt: Date())
    }
}
```

Create `CycleStreets Ride Planner/Models/SavedLocation.swift`:

```swift
import Foundation

struct SavedLocation: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let coordinate: Coordinate

    init(id: UUID = UUID(), name: String, coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}
```

- [ ] **Step 4: Implement RouteStore.swift**

Create `CycleStreets Ride Planner/Persistence/RouteStore.swift`:

```swift
import Foundation

final class RouteStore {
    private let fileURL: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("saved_routes.json")
    }

    func loadAll() throws -> [SavedRoute] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedRoute].self, from: data)
    }

    func save(_ route: SavedRoute) throws {
        var routes = (try? loadAll()) ?? []
        routes.removeAll { $0.id == route.id }
        routes.append(route)
        try JSONEncoder().encode(routes).write(to: fileURL, options: .atomic)
    }

    func delete(id: UUID) throws {
        var routes = try loadAll()
        routes.removeAll { $0.id == id }
        try JSONEncoder().encode(routes).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 5: Implement LocationStore.swift**

Create `CycleStreets Ride Planner/Persistence/LocationStore.swift`:

```swift
import Foundation

final class LocationStore {
    private let fileURL: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("saved_locations.json")
    }

    func loadAll() throws -> [SavedLocation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedLocation].self, from: data)
    }

    func save(_ location: SavedLocation) throws {
        var locations = (try? loadAll()) ?? []
        locations.removeAll { $0.id == location.id }
        locations.append(location)
        try JSONEncoder().encode(locations).write(to: fileURL, options: .atomic)
    }

    func delete(id: UUID) throws {
        var locations = try loadAll()
        locations.removeAll { $0.id == id }
        try JSONEncoder().encode(locations).write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/RouteStoreTests" \
  -only-testing:"CycleStreets Ride PlannerTests/LocationStoreTests" \
  | tail -20
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add "CycleStreets Ride Planner/Models/SavedRoute.swift" \
        "CycleStreets Ride Planner/Models/SavedLocation.swift" \
        "CycleStreets Ride Planner/Persistence/"
git add "CycleStreets Ride PlannerTests/Persistence/"
git commit -m "feat: Codable persistence for saved routes and locations"
```

---

## Task 11: Saved Routes & Locations Views

**Files:**
- Create: `CycleStreets Ride Planner/Features/SavedRoutes/SavedRoutesViewModel.swift`
- Create: `CycleStreets Ride Planner/Features/SavedRoutes/SavedRoutesView.swift`
- Create: `CycleStreets Ride Planner/Features/SavedLocations/SavedLocationsViewModel.swift`
- Create: `CycleStreets Ride Planner/Features/SavedLocations/SavedLocationsView.swift`

- [ ] **Step 1: Implement SavedRoutesViewModel**

Create `CycleStreets Ride Planner/Features/SavedRoutes/SavedRoutesViewModel.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class SavedRoutesViewModel {
    var routes: [SavedRoute] = []
    var errorMessage: String?

    private let store: RouteStore

    init(store: RouteStore = RouteStore()) {
        self.store = store
    }

    func load() {
        routes = (try? store.loadAll()) ?? []
    }

    func save(journey: Journey, name: String? = nil) {
        let route = journey.asSavedRoute(name: name)
        try? store.save(route)
        load()
    }

    func delete(at offsets: IndexSet) {
        offsets.map { routes[$0].id }.forEach { try? store.delete(id: $0) }
        load()
    }
}
```

- [ ] **Step 2: Implement SavedRoutesView**

Create `CycleStreets Ride Planner/Features/SavedRoutes/SavedRoutesView.swift`:

```swift
import SwiftUI

struct SavedRoutesView: View {
    @State private var vm = SavedRoutesViewModel()
    @AppStorage("useMetric") private var useMetric = true

    var body: some View {
        List {
            ForEach(vm.routes) { route in
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name).font(.headline)
                    HStack {
                        Text(route.plan.displayName)
                        Spacer()
                        let j = Journey(number: route.journeyID, plan: route.plan,
                                        lengthMetres: route.distanceMetres,
                                        timeSeconds: route.timeSeconds, segments: [])
                        Text(j.formattedDistance(metric: useMetric))
                        Text("·")
                        Text(j.formattedDuration())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: vm.delete)
        }
        .navigationTitle("Saved Routes")
        .toolbar { EditButton() }
        .onAppear { vm.load() }
    }
}
```

- [ ] **Step 3: Implement SavedLocationsViewModel**

Create `CycleStreets Ride Planner/Features/SavedLocations/SavedLocationsViewModel.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class SavedLocationsViewModel {
    var locations: [SavedLocation] = []

    private let store: LocationStore

    init(store: LocationStore = LocationStore()) {
        self.store = store
    }

    func load() {
        locations = (try? store.loadAll()) ?? []
    }

    func save(name: String, coordinate: Coordinate) {
        let loc = SavedLocation(name: name, coordinate: coordinate)
        try? store.save(loc)
        load()
    }

    func delete(at offsets: IndexSet) {
        offsets.map { locations[$0].id }.forEach { try? store.delete(id: $0) }
        load()
    }
}
```

- [ ] **Step 4: Implement SavedLocationsView**

Create `CycleStreets Ride Planner/Features/SavedLocations/SavedLocationsView.swift`:

```swift
import SwiftUI
import MapKit

struct SavedLocationsView: View {
    @State private var vm = SavedLocationsViewModel()

    var body: some View {
        List {
            ForEach(vm.locations) { location in
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading) {
                        Text(location.name).font(.body)
                        Text(String(format: "%.4f, %.4f",
                                    location.coordinate.latitude,
                                    location.coordinate.longitude))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: vm.delete)
        }
        .navigationTitle("Saved Locations")
        .toolbar { EditButton() }
        .onAppear { vm.load() }
    }
}
```

- [ ] **Step 5: Wire into RootView's Saved tab**

Update `CycleStreets Ride Planner/App/RootView.swift` — replace the `Text("Saved")` placeholder:

```swift
NavigationStack {
    List {
        NavigationLink("Saved Routes") { SavedRoutesView() }
        NavigationLink("Saved Locations") { SavedLocationsView() }
    }
    .navigationTitle("Saved")
}
.tabItem { Label("Saved", systemImage: "bookmark") }
```

- [ ] **Step 6: Build and verify**

```bash
xcodebuild build \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add "CycleStreets Ride Planner/Features/SavedRoutes/"
git add "CycleStreets Ride Planner/Features/SavedLocations/"
git add "CycleStreets Ride Planner/App/RootView.swift"
git commit -m "feat: saved routes and locations views"
```

---

## Task 12: User Account

**Files:**
- Create: `CycleStreets Ride Planner/Features/Account/KeychainHelper.swift`
- Create: `CycleStreets Ride Planner/Features/Account/AccountViewModel.swift`
- Create: `CycleStreets Ride Planner/Features/Account/AccountView.swift`
- Create: `CycleStreets Ride Planner/Models/UserSession.swift`
- Test: `CycleStreets Ride PlannerTests/Features/AccountViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `CycleStreets Ride PlannerTests/Features/AccountViewModelTests.swift`:

```swift
import XCTest
@testable import CycleStreets_Ride_Planner

@MainActor
final class AccountViewModelTests: XCTestCase {
    var client: MockAPIClient!
    var vm: AccountViewModel!

    override func setUp() {
        client = MockAPIClient()
        vm = AccountViewModel(apiClient: client, keychain: MockKeychainHelper())
    }

    func testLoginSuccessSetsSession() async {
        client.tokenToReturn = "abc123"
        await vm.login(username: "alice", password: "secret")
        XCTAssertTrue(vm.isLoggedIn)
        XCTAssertEqual(vm.username, "alice")
    }

    func testLoginFailureSetsError() async {
        client.shouldThrow = URLError(.userAuthenticationRequired)
        await vm.login(username: "alice", password: "wrong")
        XCTAssertFalse(vm.isLoggedIn)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testLogoutClearsSession() async {
        client.tokenToReturn = "abc123"
        await vm.login(username: "alice", password: "secret")
        vm.logout()
        XCTAssertFalse(vm.isLoggedIn)
        XCTAssertNil(vm.username)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/AccountViewModelTests" \
  | tail -20
```

Expected: FAIL.

- [ ] **Step 3: Implement UserSession.swift**

Create `CycleStreets Ride Planner/Models/UserSession.swift`:

```swift
import Foundation

struct UserSession: Codable {
    let username: String
    let token: String
}
```

- [ ] **Step 4: Implement KeychainHelper.swift**

Create `CycleStreets Ride Planner/Features/Account/KeychainHelper.swift`:

```swift
import Foundation
import Security

protocol KeychainHelperProtocol {
    func save(token: String, username: String) throws
    func load() -> UserSession?
    func delete()
}

final class KeychainHelper: KeychainHelperProtocol {
    private let service = "net.cyclestreets.ride-planner"
    private let account = "user-session"

    func save(token: String, username: String) throws {
        let session = UserSession(username: username, token: token)
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    func load() -> UserSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(UserSession.self, from: data)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}

// For tests only — lives in test target
final class MockKeychainHelper: KeychainHelperProtocol {
    private var stored: UserSession?
    func save(token: String, username: String) { stored = UserSession(username: username, token: token) }
    func load() -> UserSession? { stored }
    func delete() { stored = nil }
}
```

> **Note:** Move `MockKeychainHelper` to `CycleStreets Ride PlannerTests/` — it should only be in the test target.

- [ ] **Step 5: Implement AccountViewModel**

Create `CycleStreets Ride Planner/Features/Account/AccountViewModel.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AccountViewModel {
    var isLoggedIn = false
    var username: String?
    var isLoading = false
    var errorMessage: String?

    private let apiClient: any APIClientProtocol
    private let keychain: any KeychainHelperProtocol

    init(apiClient: any APIClientProtocol, keychain: any KeychainHelperProtocol = KeychainHelper()) {
        self.apiClient = apiClient
        self.keychain = keychain
        if let session = keychain.load() {
            self.isLoggedIn = true
            self.username = session.username
        }
    }

    func login(username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let token = try await apiClient.login(username: username, password: password)
            try keychain.save(token: token, username: username)
            self.username = username
            self.isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() {
        keychain.delete()
        isLoggedIn = false
        username = nil
    }
}
```

- [ ] **Step 6: Implement AccountView**

Create `CycleStreets Ride Planner/Features/Account/AccountView.swift`:

```swift
import SwiftUI

struct AccountView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var vm: AccountViewModel
    @State private var username = ""
    @State private var password = ""

    init(apiClient: any APIClientProtocol) {
        _vm = State(initialValue: AccountViewModel(apiClient: apiClient))
    }

    var body: some View {
        if vm.isLoggedIn {
            loggedInView
        } else {
            loginForm
        }
    }

    private var loggedInView: some View {
        List {
            Section {
                Label(vm.username ?? "", systemImage: "person.circle")
                    .font(.headline)
            }
            Section {
                Button("Sign Out", role: .destructive) { vm.logout() }
            }
        }
        .navigationTitle("Account")
    }

    private var loginForm: some View {
        Form {
            Section("Sign in to CycleStreets") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            Section {
                Button {
                    Task { await vm.login(username: username, password: password) }
                } label: {
                    if vm.isLoading { ProgressView() }
                    else { Text("Sign In").frame(maxWidth: .infinity) }
                }
                .disabled(username.isEmpty || password.isEmpty || vm.isLoading)
            }
        }
        .navigationTitle("Account")
        .alert("Sign In Failed", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}
```

- [ ] **Step 7: Move MockKeychainHelper to test target**

In Xcode, move `MockKeychainHelper` out of `KeychainHelper.swift` and into a new file `CycleStreets Ride PlannerTests/Features/MockKeychainHelper.swift`. Remove it from the main target's membership.

- [ ] **Step 8: Wire AccountView into RootView**

Update `CycleStreets Ride Planner/App/RootView.swift` — replace `Text("Account")` placeholder:

```swift
NavigationStack {
    AccountView(apiClient: apiClient)
}
.tabItem { Label("Account", systemImage: "person") }
```

- [ ] **Step 9: Run tests to verify they pass**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:"CycleStreets Ride PlannerTests/AccountViewModelTests" \
  | tail -20
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Account/"
git add "CycleStreets Ride Planner/Models/UserSession.swift"
git add "CycleStreets Ride PlannerTests/Features/"
git commit -m "feat: user account login/logout with Keychain token storage"
```

---

## Task 13: Settings

**Files:**
- Create: `CycleStreets Ride Planner/Features/Settings/SettingsView.swift`

Settings are pure `@AppStorage` — no ViewModel needed.

- [ ] **Step 1: Implement SettingsView**

Create `CycleStreets Ride Planner/Features/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultRoutePlan") private var defaultRoutePlan = RoutePlan.balanced.rawValue
    @AppStorage("useMetric") private var useMetric = true

    var body: some View {
        Form {
            Section("Routing") {
                Picker("Default route type", selection: $defaultRoutePlan) {
                    ForEach(RoutePlan.allCases, id: \.rawValue) { plan in
                        Text(plan.displayName).tag(plan.rawValue)
                    }
                }
            }
            Section("Units") {
                Toggle("Use metric (km)", isOn: $useMetric)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersionString)
                Link("CycleStreets website", destination: URL(string: "https://www.cyclestreets.net")!)
                Link("GNU GPL License", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
        }
        .navigationTitle("Settings")
    }
}

private extension Bundle {
    var appVersionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
```

- [ ] **Step 2: Add Settings to RootView**

In `RootView.swift`, add a fourth tab inside the `TabView`:

```swift
NavigationStack {
    SettingsView()
}
.tabItem { Label("Settings", systemImage: "gear") }
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild build \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add "CycleStreets Ride Planner/Features/Settings/"
git add "CycleStreets Ride Planner/App/RootView.swift"
git commit -m "feat: settings view (route type, units, about)"
```

---

## Task 14: Full Test Suite Pass

- [ ] **Step 1: Run all tests**

```bash
xcodebuild test \
  -scheme "CycleStreets Ride Planner" \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  | grep -E "Test Suite|PASSED|FAILED|error:"
```

Expected: All test suites PASSED, zero failures.

- [ ] **Step 2: Fix any failures before proceeding**

If any test fails, resolve it before moving to Task 16.

- [ ] **Step 3: Commit any fixes**

```bash
git add -u
git commit -m "fix: resolve test failures before variant task"
```

---

## Out of Scope

The following features are explicitly excluded from this implementation. They may be considered for a future phase.

| Feature | Reason |
|---|---|
| **Photo capture & upload** | Not required for v1. The CycleStreets API supports `photomap.add` — see the legacy app's `PhotoManager.m` and `PhotoWizardViewController.m` for reference when this is revisited. |
| **CycleNorthStaffs build variant** | Not required for v1. When needed: duplicate the Xcode target, set a `CYCLENORTHSTAFFS` Swift compilation flag, add a variant `APIKey_cyclestaffs.txt`, and update `APIKey.load()` to branch on the flag. |

---

## Task 15: GitHub Repository Setup

- [ ] **Step 1: Create the remote repository**

```bash
gh repo create cyclestreets-ride-planner-ios \
  --public \
  --description "CycleStreets Ride Planner — iOS cycling route planner" \
  --license gpl-3.0 \
  --source . \
  --remote origin
```

- [ ] **Step 2: Push**

```bash
git push -u origin master
```

- [ ] **Step 3: Verify on GitHub**

Open `https://github.com/cyclestreets/cyclestreets-ride-planner-ios` and confirm the repository is public, has the GPL-3.0 license badge, and all commits are present.

---

## Self-Review

### Spec coverage

| Requirement | Task |
|---|---|
| Map display | Task 7 |
| Route planning (start/end + API) | Tasks 4, 6, 7 |
| Itinerary (turn-by-turn) | Task 8 |
| GPX export | Task 9 |
| Saved routes | Tasks 10, 11 |
| Saved locations | Tasks 10, 11 |
| User account (login) | Task 12 |
| Settings (route type + units) | Task 13 |
| GNU GPL license | Task 1 |
| No third-party dependencies | All tasks — only system frameworks used |
| APIKey from bundle txt file | Task 2 |
| iOS 16+ / Swift 5.9+ / SwiftUI | Task 1 (project setup) |
| GitHub repo `cyclestreets-ride-planner-ios` | Task 15 |
| Photo capture & upload | Out of Scope |
| CycleNorthStaffs variant | Out of Scope |

All in-scope requirements covered. ✓
