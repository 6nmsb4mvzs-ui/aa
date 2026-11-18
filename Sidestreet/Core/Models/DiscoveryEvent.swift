import Foundation

/// A dated event (flea market, concert, exhibition, skate contest …).
/// Events are only created from sources that publish a concrete date or a
/// machine-readable recurring schedule — dates are never guessed.
struct DiscoveryEvent: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case fleaMarket, market, music, exhibition, skate, popUp, cultural, other

        var label: String {
            switch self {
            case .fleaMarket: return "Flea market"
            case .market: return "Market"
            case .music: return "Music"
            case .exhibition: return "Exhibition"
            case .skate: return "Skate"
            case .popUp: return "Pop-up"
            case .cultural: return "Culture"
            case .other: return "Event"
            }
        }

        var categories: Set<DiscoveryCategory> {
            switch self {
            case .fleaMarket: return [.events, .markets, .fashion]
            case .market: return [.events, .markets]
            case .music: return [.events, .music]
            case .exhibition: return [.events, .culture]
            case .skate: return [.events, .skate]
            case .popUp: return [.events, .fashion]
            case .cultural: return [.events, .culture]
            case .other: return [.events]
            }
        }

        var symbolName: String {
            switch self {
            case .fleaMarket, .market, .popUp: return "tag"
            case .music: return "music.note"
            case .exhibition: return "photo.artframe"
            case .skate: return "figure.skateboarding"
            case .cultural: return "theatermasks"
            case .other: return "calendar"
            }
        }
    }

    /// Describes how a recurring event's schedule was verified.
    struct Recurrence: Hashable, Codable, Sendable {
        /// Human-readable schedule, e.g. "Sa 08:00–15:00".
        var scheduleDescription: String
        /// The raw machine-readable rule (e.g. OSM opening_hours).
        var rule: String
    }

    var id: String
    var title: String
    var kind: Kind
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var recurrence: Recurrence?
    var venueName: String?
    var venuePlaceID: String?
    var coordinate: GeoCoordinate?
    var addressText: String?
    var url: URL?
    var imageURL: URL?
    var summary: String?
    var source: SourceRecord
    var confidence: ConfidenceLevel
    var timeZoneIdentifier: String?
    var isSample: Bool = false

    var categories: Set<DiscoveryCategory> { kind.categories }

    /// An event is upcoming while it has not ended.
    func isUpcoming(now: Date) -> Bool {
        if let end { return end >= now }
        if isAllDay {
            // All-day events stay visible for the whole day.
            return start.addingTimeInterval(24 * 3600) > now
        }
        // Without an end time, keep the event visible for 3 hours after start.
        return start.addingTimeInterval(3 * 3600) >= now
    }
}
