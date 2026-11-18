import CoreLocation
import Foundation
import Observation

/// One-shot, when-in-use location access. No background tracking and no
/// continuous updates: each request asks CoreLocation for a single fix.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case notAuthorized
        case unavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Location access is off."
            case .unavailable: return "Your location couldn't be determined."
            case .timedOut: return "Finding your location took too long."
            }
        }
    }

    private(set) var authorization: LocationAuthorization = .notDetermined
    private(set) var lastFix: LocationFix?
    private(set) var lastRequestFailed = false
    private(set) var isLocating = false

    private let manager = CLLocationManager()
    @ObservationIgnored private var fixContinuations: [CheckedContinuation<LocationFix, Error>] = []
    @ObservationIgnored private var authContinuations: [CheckedContinuation<LocationAuthorization, Never>] = []
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        authorization = Self.map(manager.authorizationStatus)
    }

    static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedWhenInUse, .authorizedAlways: return .authorizedWhenInUse
        @unknown default: return .denied
        }
    }

    /// Requests when-in-use permission (only if not decided yet).
    func requestAuthorization() async -> LocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// A single location fix. Reuses a fix younger than two minutes.
    func currentLocation(timeout: TimeInterval = 12) async throws -> LocationFix {
        guard authorization.allowsLocation else { throw LocationError.notAuthorized }
        if let fix = lastFix, Date().timeIntervalSince(fix.timestamp) < 120 { return fix }
        return try await withCheckedThrowingContinuation { continuation in
            fixContinuations.append(continuation)
            guard fixContinuations.count == 1 else { return }
            isLocating = true
            manager.requestLocation()
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(with: .failure(LocationError.timedOut))
            }
        }
    }

    private func finish(with result: Result<LocationFix, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        isLocating = false
        let pending = fixContinuations
        fixContinuations.removeAll()
        switch result {
        case .success(let fix):
            lastFix = fix
            lastRequestFailed = false
        case .failure:
            lastRequestFailed = true
        }
        for continuation in pending { continuation.resume(with: result) }
    }

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        let mapped = Self.map(status)
        authorization = mapped
        guard mapped != .notDetermined else { return }
        let pending = authContinuations
        authContinuations.removeAll()
        for continuation in pending { continuation.resume(returning: mapped) }
        if !mapped.allowsLocation && !fixContinuations.isEmpty {
            finish(with: .failure(LocationError.notAuthorized))
        }
    }

    // MARK: CLLocationManagerDelegate (called on the main thread)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.handleAuthorization(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(
            coordinate: GeoCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        Task { @MainActor in self.finish(with: .success(fix)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor in
            // kCLErrorLocationUnknown is transient; CoreLocation keeps trying until the timeout.
            if code == .locationUnknown { return }
            self.finish(with: .failure(code == .denied ? LocationError.notAuthorized : LocationError.unavailable))
        }
    }

    /// City name, country and time zone for a coordinate (Apple geocoder).
    func describe(_ coordinate: GeoCoordinate) async -> CityChoice? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        let name = placemark.subLocality ?? placemark.locality ?? placemark.administrativeArea ?? "Current location"
        let subtitle = [placemark.locality == name ? nil : placemark.locality, placemark.country]
            .compactMap { $0 }.joined(separator: ", ")
        return CityChoice(name: name, subtitle: subtitle.isEmpty ? nil : subtitle, center: coordinate,
                          timeZoneIdentifier: placemark.timeZone?.identifier, countryCode: placemark.isoCountryCode)
    }
}
