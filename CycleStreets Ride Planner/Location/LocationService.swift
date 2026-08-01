//
//  LocationService.swift
//  CycleStreets Ride Planner
//

import CoreLocation

protocol LocationServiceProtocol {
    /// Fetches a single one-shot fix for the device's current location,
    /// requesting "when in use" authorization first if not yet determined.
    func currentLocation() async throws -> CLLocationCoordinate2D
}

enum LocationServiceError: Error, Equatable {
    case permissionDenied
    case restricted
    case unavailable
}

/// Wraps `CLLocationManager`'s delegate API behind `async/await`. Does a
/// single one-shot `requestLocation()` — no continuous tracking, since
/// route planning only needs one fix. If authorization is
/// `.notDetermined`, requests it in-context (the system prompt fires the
/// first time the user actually taps "Current Location," not at launch).
final class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func currentLocation() async throws -> CLLocationCoordinate2D {
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
        @unknown default:
            throw LocationServiceError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authContinuation?.resume(returning: manager.authorizationStatus)
        authContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location.coordinate)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: LocationServiceError.unavailable)
        locationContinuation = nil
    }
}
