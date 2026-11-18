import Foundation

/// The data source a piece of information came from.
enum SourceProvider: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case openStreetMap
    case wikidata
    case wikipedia
    case wikimediaCommons
    case appleMaps
    case venueWebsite
    case youtube
    case panoramax
    case mapillary
    case sample

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openStreetMap: return "OpenStreetMap"
        case .wikidata: return "Wikidata"
        case .wikipedia: return "Wikipedia"
        case .wikimediaCommons: return "Wikimedia Commons"
        case .appleMaps: return "Apple Maps"
        case .venueWebsite: return "Venue website"
        case .youtube: return "YouTube"
        case .panoramax: return "Panoramax"
        case .mapillary: return "Mapillary"
        case .sample: return "Sample data"
        }
    }
}

/// Provenance for a place or event.
struct SourceRecord: Hashable, Codable, Sendable {
    var provider: SourceProvider
    /// Provider-specific identifier, e.g. "node/123", "Q42".
    var identifier: String
    var url: URL?
    var retrievedAt: Date
}

/// Postal address assembled from structured source data.
struct PostalAddress: Hashable, Codable, Sendable {
    var street: String?
    var houseNumber: String?
    var postcode: String?
    var city: String?
    var district: String?
    var country: String?
    /// Pre-formatted single-line address (e.g. from Apple Maps).
    var formatted: String?

    var singleLine: String? {
        if let formatted, !formatted.isEmpty { return formatted }
        var parts: [String] = []
        let streetLine = [street, houseNumber].compactMap { $0 }.joined(separator: " ")
        if !streetLine.isEmpty { parts.append(streetLine) }
        let cityLine = [postcode, city].compactMap { $0 }.joined(separator: " ")
        if !cityLine.isEmpty { parts.append(cityLine) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Short "street" or "district" hint for compact UI.
    var shortHint: String? {
        if let street, !street.isEmpty { return street }
        if let district, !district.isEmpty { return district }
        return city
    }

    var isEmpty: Bool { singleLine == nil }
}

/// A photo or visual reference with attribution.
struct PlaceImage: Hashable, Codable, Sendable {
    enum Origin: String, Codable, Hashable, Sendable {
        /// Image explicitly linked to this place by a data source.
        case linked
        /// Image taken near the place's coordinates (may show surroundings).
        case nearby
        /// Street-level picture looking towards the place.
        case streetLevel
    }

    var url: URL
    var pageURL: URL?
    var attribution: String?
    var license: String?
    var provider: SourceProvider
    var origin: Origin
}

/// Price information. Never fabricated: either sourced, explicitly free
/// (public space / `fee=no`), a clearly-labelled category estimate, or unknown.
enum PriceInfo: Hashable, Codable, Sendable {
    case unknown
    /// Price level 1–4 reported by a source.
    case level(Int, source: SourceProvider)
    /// The source states that access is free (e.g. OSM `fee=no`).
    case free(source: SourceProvider)
    /// Estimated from the type of place; shown with an "estimate" label.
    case estimated(AffordabilityTier, reason: String)

    var affordabilityScore: Double? {
        switch self {
        case .unknown: return nil
        case .level(let level, _): return max(0, min(1, 1.0 - Double(level - 1) / 3.0))
        case .free: return 1.0
        case .estimated(let tier, _): return tier.affordabilityScore
        }
    }

    var isEstimate: Bool {
        if case .estimated = self { return true }
        return false
    }

    var shortLabel: String? {
        switch self {
        case .unknown: return nil
        case .level(let level, _): return "Price \(max(1, min(4, level)))/4"
        case .free: return "Free"
        case .estimated(let tier, _): return tier == .free ? "Free" : tier.label
        }
    }
}

/// Brand / chain information.
struct BrandInfo: Hashable, Codable, Sendable {
    var name: String
    var wikidataID: String?
}

/// Raw signals collected from sources. The niche scorer turns these into
/// normalised score components.
struct PlaceSignals: Hashable, Codable, Sendable {
    /// Number of language Wikipedias linking the Wikidata item (fame proxy).
    var wikipediaSitelinks: Int?
    var hasWikipediaArticle = false
    /// Tagged as a tourist attraction in OSM.
    var isTouristAttraction = false
    /// Appeared in Apple Maps' results for a broad, generic query.
    var appleGenericVisibility = false
    /// How many other places in the same result set share this name.
    var sameNameCount = 0
    /// Matches of subculture keywords in name/description/tags.
    var subcultureKeywordHits = 0
    /// Community / cooperative / non-profit operation.
    var communityOperated = false
    /// 0…1, how complete the structured record is.
    var tagRichness: Double = 0
    /// Date the place was last confirmed by a mapper (OSM check_date etc.).
    var lastConfirmed: Date?
    /// Number of YouTube videos that mention the place (only when the user
    /// configured a YouTube API key and opened the profile).
    var socialMentions: Int?
}

/// Confidence classes shown in the UI.
enum ConfidenceLevel: String, Codable, Hashable, Sendable, Comparable {
    case uncertain, partial, verified

    var label: String {
        switch self {
        case .verified: return "Verified"
        case .partial: return "Partially verified"
        case .uncertain: return "Unverified"
        }
    }

    var explanation: String {
        switch self {
        case .verified: return "Confirmed by several independent sources or recently checked by a mapper."
        case .partial: return "Reported by one reliable source; some details may be missing or outdated."
        case .uncertain: return "Sparse or old information. Check before you go."
        }
    }

    private var order: Int {
        switch self {
        case .uncertain: return 0
        case .partial: return 1
        case .verified: return 2
        }
    }

    static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool { lhs.order < rhs.order }
}

/// One component of the transparent niche score.
struct ScoreComponent: Hashable, Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Hashable, Sendable {
        case independence, obscurity, uniqueness, subculture, community, sourceDiversity, socialSignal
    }

    var kind: Kind
    /// Normalised value 0…1.
    var value: Double
    /// Weight after renormalisation (weights of available components sum to 1).
    var weight: Double
    var explanation: String

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .independence: return "Independence"
        case .obscurity: return "Off the radar"
        case .uniqueness: return "Uniqueness"
        case .subculture: return "Subculture relevance"
        case .community: return "Community"
        case .sourceDiversity: return "Source diversity"
        case .socialSignal: return "Local buzz"
        }
    }
}

/// The computed niche score with its breakdown.
struct NicheScore: Hashable, Codable, Sendable {
    /// Final score 0…1 (raw score damped by confidence).
    var value: Double
    /// Weighted score before the confidence damping.
    var rawValue: Double
    /// Data confidence 0…1.
    var confidence: Double
    var components: [ScoreComponent]

    /// Score on a 0…100 scale for display.
    var display: Int { Int((value * 100).rounded()) }
}

/// A discovered place, possibly merged from several sources.
struct Place: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier, e.g. "osm:node/123", "wd:Q42", "apple:…".
    var id: String
    var name: String
    /// True when the source had no name and the title was derived from the
    /// type (e.g. "Untitled mural"). Such names are never used for matching.
    var isNameInferred: Bool = false
    var coordinate: GeoCoordinate
    var kind: PlaceKind
    var categories: Set<DiscoveryCategory>
    /// Human-readable descriptors such as "second-hand", "vegan", "techno".
    var descriptors: [String] = []
    var address: PostalAddress?
    var openingHoursRaw: String?
    var website: URL?
    var phone: String?
    var summary: String?
    var images: [PlaceImage] = []
    var price: PriceInfo = .unknown
    var brand: BrandInfo?
    var wikidataID: String?
    /// "lang:Title" as used by OSM's `wikipedia` tag.
    var wikipediaTitle: String?
    var sources: [SourceRecord] = []
    var signals = PlaceSignals()
    var score: NicheScore?
    var confidence: ConfidenceLevel = .uncertain
    /// True only for clearly-labelled sample data used in previews/demo mode.
    var isSample: Bool = false
    /// IDs of records that were merged into this place (e.g. an Apple Maps
    /// record that turned out to be the same shop as an OSM node).
    var aliasIDs: [String]? = nil

    var primaryCategory: DiscoveryCategory { kind.primaryCategory }

    /// This place's ID and every merged record's ID.
    var allIDs: [String] { [id] + (aliasIDs ?? []) }

    var providers: Set<SourceProvider> { Set(sources.map(\.provider)) }

    var primaryImage: PlaceImage? {
        images.first(where: { $0.origin == .linked }) ?? images.first
    }

    var osmSource: SourceRecord? { sources.first { $0.provider == .openStreetMap } }

    func distance(from point: GeoCoordinate) -> Double {
        GeoMath.distance(coordinate, point)
    }
}
