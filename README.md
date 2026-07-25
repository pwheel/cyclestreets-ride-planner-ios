# CycleStreets Ride Planner

An iOS app for planning cycle routes using the [CycleStreets](https://www.cyclestreets.net/) API — search for a start and end point, get a quiet/balanced/fastest cycle route, view turn-by-turn directions, export to GPX, and save routes and locations for later.

## Features

- Search locations via the CycleStreets geocoder, with live typeahead
- Plan a route (quietest / balanced / fastest) and view it on the map
- Turn-by-turn itinerary with distance and duration (metric or imperial)
- Export a planned route as a GPX file
- Save routes and locations locally, and reload/reuse them to prefill a new route

No user account is required — the app works entirely off a single API key.

## Requirements

- Xcode 16+
- iOS 26+ simulator or device
- A CycleStreets API key ([register here](https://www.cyclestreets.net/api/apply/))

## Setup

1. Clone the repo and open `CycleStreets Ride Planner.xcodeproj` in Xcode.
2. Add your API key to `CycleStreets Ride Planner/Resources/APIKey_dev.txt` (used for local/debug builds). This file is tracked as a placeholder in git; keep your real key out of commits with:
   ```
   git update-index --skip-worktree "CycleStreets Ride Planner/Resources/APIKey_dev.txt"
   ```
3. Build and run.

## Testing

```
xcodebuild test -project "CycleStreets Ride Planner.xcodeproj" -scheme "CycleStreets Ride Planner" -destination "platform=iOS Simulator,name=iPhone 17"
```

Tests use [Swift Testing](https://developer.apple.com/documentation/testing), not XCTest.

## Architecture

SwiftUI + MVVM (`@Observable` view models). See [`docs/SPEC.md`](docs/SPEC.md) for the full architecture and feature reference, and [`AGENTS.md`](AGENTS.md) for contributor/agent conventions.

## License

[GPL v3](LICENSE)
