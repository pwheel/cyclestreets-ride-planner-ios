//
//  LocationService.swift
//  CycleStreets Ride Planner
//

import CoreLocation

/// Isolated to the main actor so the continuation state below can only ever
/// be touched from one place: `CLLocationManager` delivers its delegate
/// callbacks on the run loop the manager was created on (main, here), and
/// the `async` entry point is main-actor-isolated too, so there is no
/// cross-thread access to synchronize.
@MainActor
protocol LocationServiceProtocol: Sendable {
    /// Fetches a single one-shot fix for the device's current location,
    /// requesting "when in use" authorization first if not yet determined.
    /// Throws `LocationServiceError.alreadyInProgress` if a previous call
    /// hasn't resolved yet — callers must not assume serialization.
    func currentLocation() async throws -> CLLocationCoordinate2D
}

enum LocationServiceError: Error, Equatable {
    case permissionDenied
    case restricted
    case unavailable
    /// A fetch was requested while a previous one was still in flight. The
    /// earlier call still owns the request and will deliver its own result;
    /// this one is rejected rather than silently stranding it.
    case alreadyInProgress
}

/// Wraps `CLLocationManager`'s delegate API behind `async/await`. Does a
/// single one-shot `requestLocation()` — no continuous tracking, since
/// route planning only needs one fix. If authorization is
/// `.notDetermined`, requests it in-context (the system prompt fires the
/// first time the user actually taps "Current Location," not at launch).
@MainActor
final class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    /// Ceiling on how long `requestAuthorization()` waits for a *determined*
    /// status before giving up. Needed because there is a real state —
    /// Location Services switched off device-wide while the app's own status
    /// is still `.notDetermined` — in which `requestWhenInUseAuthorization()`
    /// shows the system "Turn On Location Services?" prompt but never
    /// transitions the app's authorization status, so the only callback we
    /// would ever see is a `.notDetermined` one (which we deliberately
    /// ignore, since the system also emits those spuriously). Without this
    /// ceiling the continuation would never resume and the caller would hang.
    private static let authorizationTimeout: Duration = .seconds(5)

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var authTimeoutTask: Task<Void, Never>?
    private var isFetchInFlight = false

    override init() {
        super.init()
        manager.delegate = self
    }

    func currentLocation() async throws -> CLLocationCoordinate2D {
        // Overwriting `locationContinuation`/`authContinuation` while an
        // earlier call is still suspended on them would leak that
        // continuation ("SWIFT TASK CONTINUATION MISUSE") and hang its task
        // forever, so reject the duplicate instead. The UI also suppresses
        // repeat taps while loading; this is the backstop.
        guard !isFetchInFlight else { throw LocationServiceError.alreadyInProgress }
        isFetchInFlight = true
        defer { isFetchInFlight = false }

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .denied:
            throw LocationServiceError.permissionDenied
        case .restricted:
            throw LocationServiceError.restricted
        case .notDetermined:
            // Either the authorization wait timed out, or the user dismissed
            // the prompt without deciding. Nothing to link to in Settings —
            // this is a "try again" condition, not a denial.
            throw LocationServiceError.unavailable
        @unknown default:
            // A status this build doesn't know about is more likely a
            // transient/unsupported condition than an outright denial, so
            // prefer the generic "try again" path over sending the user to
            // Settings on a guess. Matches the `.notDetermined` fallback.
            throw LocationServiceError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.authContinuation = continuation
            self.authTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.authorizationTimeout)
                guard !Task.isCancelled else { return }
                // Resume with the still-undetermined status; `currentLocation()`
                // maps it to `.unavailable`.
                self?.resumeAuthorization(with: .notDetermined)
            }
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Resumes a pending authorization wait exactly once, cancelling the
    /// timeout that races it.
    private func resumeAuthorization(with status: CLAuthorizationStatus) {
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        continuation.resume(returning: status)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // `CLLocationManager` delivers delegate callbacks on the run loop it
        // was created on — main, because this class is `@MainActor` — so the
        // assumption below is sound, and it lets a main-actor-isolated type
        // satisfy this non-isolated protocol requirement without hopping
        // (which would reorder callbacks relative to the continuation state).
        MainActor.assumeIsolated {
            let status = manager.authorizationStatus
            // The system emits `.notDetermined` callbacks spuriously (e.g. on
            // delegate assignment), so only a determined status resolves the
            // wait. `authorizationTimeout` is what stops that guard from
            // hanging forever when `.notDetermined` is genuinely all we'll get.
            guard status != .notDetermined else { return }
            resumeAuthorization(with: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            locationContinuation?.resume(returning: location.coordinate)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            // `CLError.denied` means Location Services are off system-wide even
            // though the app's own status is authorized — that's fixable in
            // Settings, so route it to the Settings-linking alert rather than
            // the generic "try again" one.
            let mapped: LocationServiceError =
                (error as? CLError)?.code == .denied ? .permissionDenied : .unavailable
            locationContinuation?.resume(throwing: mapped)
            locationContinuation = nil
        }
    }
}
