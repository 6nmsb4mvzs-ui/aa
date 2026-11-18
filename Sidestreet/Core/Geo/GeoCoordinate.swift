import Foundation

/// A WGS84 coordinate. Platform independent (CoreLocation is not available to
/// the shared core), convertible to `CLLocationCoordinate2D` in the app layer.
struct GeoCoordinate: Hashable, Codable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// True when the coordinate lies inside the valid WGS84 range and is not the
    /// common "null island" placeholder (0, 0) that broken data often contains.
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
            && !(abs(latitude) < 0.000_001 && abs(longitude) < 0.000_001)
    }
}

/// Geographic helper math. All distances are in metres.
enum GeoMath {
    static let earthRadius: Double = 6_371_008.8

    /// Great-circle distance using the haversine formula.
    static func distance(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
        return earthRadius * c
    }

    /// Whether `point` lies within `radius` metres of `center` (inclusive).
    static func isWithin(_ point: GeoCoordinate, center: GeoCoordinate, radius: Double) -> Bool {
        guard point.isValid, center.isValid, radius >= 0 else { return false }
        return distance(point, center) <= radius
    }

    /// The coordinate reached by travelling `distance` metres from `origin`
    /// along the initial `bearing` (degrees clockwise from north).
    static func destination(from origin: GeoCoordinate, distance: Double, bearing: Double) -> GeoCoordinate {
        let δ = distance / earthRadius
        let θ = bearing * .pi / 180
        let φ1 = origin.latitude * .pi / 180
        let λ1 = origin.longitude * .pi / 180
        let φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))
        var lon = λ2 * 180 / .pi
        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
        return GeoCoordinate(latitude: φ2 * 180 / .pi, longitude: lon)
    }

    /// Bounding box (south, west, north, east) that contains the circle.
    static func boundingBox(center: GeoCoordinate, radius: Double) -> (south: Double, west: Double, north: Double, east: Double) {
        let north = destination(from: center, distance: radius, bearing: 0).latitude
        let south = destination(from: center, distance: radius, bearing: 180).latitude
        let east = destination(from: center, distance: radius, bearing: 90).longitude
        let west = destination(from: center, distance: radius, bearing: 270).longitude
        return (south, west, north, east)
    }

    /// Clamp a requested search radius into the range the app supports.
    static func clampRadius(_ radius: Double) -> Double {
        min(max(radius, SearchRadius.minimumMeters), SearchRadius.maximumMeters)
    }
}

/// Limits for the user-adjustable search radius.
enum SearchRadius {
    static let minimumMeters: Double = 500
    static let maximumMeters: Double = 25_000
    static let defaultMeters: Double = 2_500
}
