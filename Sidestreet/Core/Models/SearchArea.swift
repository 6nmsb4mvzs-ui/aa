import Foundation

/// Where the radius is centred.
enum CenterSource: String, Codable, Hashable, Sendable {
    /// The device's GPS position.
    case gps
    /// The centre of a city the user searched for.
    case city
}

/// The geographic area a discovery run covers.
struct SearchArea: Hashable, Codable, Sendable {
    var center: GeoCoordinate
    var radiusMeters: Double
    /// Display label, e.g. "Berlin" or "Near Kreuzberg".
    var label: String
    /// Optional secondary label, e.g. "Germany".
    var subtitle: String?
    var centerSource: CenterSource
    /// IANA time zone of the area (used for opening hours and event dates).
    var timeZoneIdentifier: String?
    /// ISO country code if known (used to localise search links).
    var countryCode: String?

    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    func contains(_ coordinate: GeoCoordinate) -> Bool {
        GeoMath.isWithin(coordinate, center: center, radius: radiusMeters)
    }
}

/// A selected city (from search or reverse geocoding).
struct CityChoice: Hashable, Codable, Sendable {
    var name: String
    var subtitle: String?
    var center: GeoCoordinate
    var timeZoneIdentifier: String?
    var countryCode: String?
}

/// Status of one data source during a discovery run.
enum SourceStatus: Hashable, Codable, Sendable {
    case idle
    case loading
    case loaded(count: Int)
    case cached(count: Int)
    case skipped(reason: String)
    case failed(message: String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// The merged, scored output of a discovery run.
struct DiscoverySnapshot: Hashable, Codable, Sendable {
    var area: SearchArea
    var places: [Place]
    var events: [DiscoveryEvent]
    var sourceStatuses: [SourceProvider: SourceStatus]
    var generatedAt: Date
    var isFromCache: Bool = false

    static func empty(area: SearchArea, now: Date) -> DiscoverySnapshot {
        DiscoverySnapshot(area: area, places: [], events: [], sourceStatuses: [:], generatedAt: now)
    }

    /// Returns a copy restricted to a (smaller or equal) radius around a centre.
    func restricted(to area: SearchArea, now: Date) -> DiscoverySnapshot {
        var copy = self
        copy.area = area
        copy.places = places.filter { area.contains($0.coordinate) }
        copy.events = events.filter { event in
            guard event.isUpcoming(now: now) else { return false }
            guard let coordinate = event.coordinate else { return true }
            return area.contains(coordinate)
        }
        return copy
    }
}

/// An entry in the discovery feed.
enum FeedEntry: Identifiable, Hashable, Sendable {
    case place(Place)
    case event(DiscoveryEvent)

    var id: String {
        switch self {
        case .place(let place): return "p:" + place.id
        case .event(let event): return "e:" + event.id
        }
    }

    /// Feed IDs of this entry, including IDs of records merged into it.
    var allIDs: [String] {
        switch self {
        case .place(let place): return place.allIDs.map { "p:" + $0 }
        case .event(let event): return ["e:" + event.id]
        }
    }

    var coordinate: GeoCoordinate? {
        switch self {
        case .place(let place): return place.coordinate
        case .event(let event): return event.coordinate
        }
    }

    var primaryCategory: DiscoveryCategory {
        switch self {
        case .place(let place): return place.primaryCategory
        case .event: return .events
        }
    }

    /// Fine-grained grouping key used to avoid near-identical neighbours.
    var varietyKey: String {
        switch self {
        case .place(let place): return place.kind.rawValue
        case .event(let event): return "event." + event.kind.rawValue
        }
    }
}
