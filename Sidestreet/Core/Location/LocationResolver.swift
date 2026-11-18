import Foundation

/// Platform-independent mirror of CoreLocation's authorization states.
enum LocationAuthorization: String, Codable, Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorizedWhenInUse

    var allowsLocation: Bool { self == .authorizedWhenInUse }
}

/// What the user asked the radius to be centred on.
enum CenterPreference: Hashable, Codable, Sendable {
    /// Use the GPS position (the default).
    case currentLocation
    /// Use a searched city. If `preferGPSInside` is true and the user is
    /// physically inside that city, the GPS position is used instead.
    case city(CityChoice, preferGPSInside: Bool)
}

/// A GPS fix as seen by the core.
struct LocationFix: Hashable, Codable, Sendable {
    var coordinate: GeoCoordinate
    var horizontalAccuracy: Double
    var timestamp: Date
}

/// The outcome of resolving where to centre the search.
enum CenterResolution: Hashable, Sendable {
    case gps(LocationFix)
    case city(CityChoice, fallbackReason: FallbackReason?)
    /// Location permission has not been requested yet.
    case needsPermission
    /// Waiting for a GPS fix.
    case locating
    /// No usable centre — the user must pick a city.
    case needsCity(FallbackReason)

    enum FallbackReason: String, Hashable, Sendable {
        case permissionDenied
        case permissionRestricted
        case locationUnavailable
        case outsideCity
    }

    var coordinate: GeoCoordinate? {
        switch self {
        case .gps(let fix): return fix.coordinate
        case .city(let city, _): return city.center
        default: return nil
        }
    }
}

/// Pure decision logic for "where is the centre of my radius?". Kept free of
/// CoreLocation so the behaviour for every permission state is unit tested.
enum LocationResolver {
    /// GPS fixes older than this are not trusted for centring.
    static let maxFixAge: TimeInterval = 10 * 60
    /// Fixes less accurate than this are not used.
    static let maxAccuracy: Double = 1_500
    /// Distance within which the user counts as "inside" a searched city.
    static let insideCityDistance: Double = 25_000

    static func isUsable(_ fix: LocationFix?, now: Date) -> Bool {
        guard let fix else { return false }
        return fix.coordinate.isValid
            && fix.horizontalAccuracy >= 0
            && fix.horizontalAccuracy <= maxAccuracy
            && now.timeIntervalSince(fix.timestamp) <= maxFixAge
    }

    static func resolve(
        preference: CenterPreference,
        authorization: LocationAuthorization,
        fix: LocationFix?,
        locationFailed: Bool,
        now: Date
    ) -> CenterResolution {
        let usableFix = isUsable(fix, now: now) ? fix : nil
        switch preference {
        case .currentLocation:
            switch authorization {
            case .notDetermined:
                return .needsPermission
            case .denied:
                return .needsCity(.permissionDenied)
            case .restricted:
                return .needsCity(.permissionRestricted)
            case .authorizedWhenInUse:
                if let usableFix { return .gps(usableFix) }
                return locationFailed ? .needsCity(.locationUnavailable) : .locating
            }
        case let .city(city, preferGPSInside):
            guard preferGPSInside else { return .city(city, fallbackReason: nil) }
            switch authorization {
            case .denied:
                return .city(city, fallbackReason: .permissionDenied)
            case .restricted:
                return .city(city, fallbackReason: .permissionRestricted)
            case .notDetermined:
                return .city(city, fallbackReason: nil)
            case .authorizedWhenInUse:
                guard let usableFix else {
                    return .city(city, fallbackReason: locationFailed ? .locationUnavailable : nil)
                }
                if GeoMath.distance(usableFix.coordinate, city.center) <= insideCityDistance {
                    return .gps(usableFix)
                }
                return .city(city, fallbackReason: .outsideCity)
            }
        }
    }
}
