import Foundation

/// Automatic, transparent niche scoring (no user-adjustable niche level).
///
/// Each place gets normalised components (0…1):
///
/// | Component        | Measures                                                     |
/// |------------------|--------------------------------------------------------------|
/// | independence     | chain/brand data, repeated names in the area, co-ops         |
/// | obscurity        | inverse of fame: Wikipedia editions, tourist-attraction tags |
/// | uniqueness       | how distinctive the type is + how rare it is in this area    |
/// | subculture       | skate/graffiti/vintage/DIY/club-culture relevance            |
/// | community        | community-run, co-operative, non-profit                      |
/// | sourceDiversity  | number of independent sources that confirm the place         |
/// | socialSignal     | YouTube mentions (only when available)                       |
///
/// The weighted sum is then damped by data confidence:
/// `score = raw × (0.55 + 0.45 × confidence)`, so an obscure place with
/// unreliable data cannot outrank a well-documented independent gem.
/// Low popularity alone never makes a place score highly: obscurity is one
/// component of seven.
struct NicheScorer: Sendable {
    struct Weights: Sendable {
        var independence = 0.22
        var obscurity = 0.15
        var uniqueness = 0.23
        var subculture = 0.18
        var community = 0.07
        var sourceDiversity = 0.07
        var socialSignal = 0.08
    }

    var weights = Weights()
    var now: Date

    /// Scores all places. Context-dependent signals (name repetition, kind
    /// rarity) are computed across the set.
    func score(_ places: [Place]) -> [Place] {
        guard !places.isEmpty else { return [] }
        var nameCounts: [String: Int] = [:]
        var kindCounts: [PlaceKind: Int] = [:]
        for place in places {
            if !place.isNameInferred { nameCounts[TextMatching.normalizedName(place.name), default: 0] += 1 }
            kindCounts[place.kind, default: 0] += 1
        }
        let total = Double(places.count)
        return places.map { original in
            var place = original
            place.signals.sameNameCount = place.isNameInferred ? 0 : max(0, (nameCounts[TextMatching.normalizedName(place.name)] ?? 1) - 1)
            let rarity = 1 - sqrt(Double(kindCounts[place.kind] ?? 1) / total)
            let result = score(place, kindRarity: rarity)
            place.score = result
            place.confidence = Self.confidenceLevel(for: place, confidence: result.confidence, now: now)
            return place
        }
    }

    func score(_ place: Place, kindRarity: Double) -> NicheScore {
        var components: [ScoreComponent] = []
        let kind = place.kind
        let s = place.signals

        // Independence
        var independence: Double
        var independenceWhy: String
        if let brand = place.brand, brand.wikidataID != nil {
            independence = 0.05
            independenceWhy = "Part of the \(brand.name) chain"
        } else if place.brand != nil || kind == .fashionChain {
            independence = 0.2
            independenceWhy = "Branded / chain store"
        } else if s.sameNameCount >= 3 {
            independence = 0.25
            independenceWhy = "\(s.sameNameCount + 1) locations with this name nearby"
        } else if s.sameNameCount >= 1 {
            independence = 0.55
            independenceWhy = "Another location with the same name nearby"
        } else if s.communityOperated {
            independence = 1.0
            independenceWhy = "Community or co-operatively run"
        } else if !kind.isBusiness {
            independence = 0.95
            independenceWhy = "Public, non-commercial place"
        } else {
            independence = 0.85
            independenceWhy = "No chain or brand found"
        }
        components.append(ScoreComponent(kind: .independence, value: independence, weight: weights.independence, explanation: independenceWhy))

        // Obscurity (inverse fame)
        var fame = 0.0
        var fameReasons: [String] = []
        if let sitelinks = s.wikipediaSitelinks, sitelinks > 0 {
            fame += min(1, log10(1 + Double(sitelinks)) / log10(60))
            fameReasons.append("\(sitelinks) Wikipedia edition\(sitelinks == 1 ? "" : "s")")
        } else if s.hasWikipediaArticle {
            fame += 0.25
            fameReasons.append("has a Wikipedia article")
        }
        if s.isTouristAttraction {
            fame += 0.35
            fameReasons.append("tagged as a tourist attraction")
        }
        if s.appleGenericVisibility {
            fame += 0.12
            fameReasons.append("prominent in generic map search")
        }
        let obscurity = max(0, 1 - min(1, fame))
        components.append(ScoreComponent(
            kind: .obscurity, value: obscurity, weight: weights.obscurity,
            explanation: fameReasons.isEmpty ? "Not covered by encyclopaedias or tourist listings" : "Known: " + fameReasons.joined(separator: ", ")
        ))

        // Uniqueness
        let uniqueness = min(1, 0.72 * kind.intrinsicNiche + 0.28 * max(0, kindRarity))
        components.append(ScoreComponent(
            kind: .uniqueness, value: uniqueness, weight: weights.uniqueness,
            explanation: kindRarity > 0.85 ? "\(kind.label) — rare in this area" : "\(kind.label)"
        ))

        // Subculture
        let keywordBoost = min(0.4, Double(s.subcultureKeywordHits) * 0.15)
        let subculture = min(1, kind.subcultureAffinity * 0.8 + keywordBoost)
        components.append(ScoreComponent(
            kind: .subculture, value: subculture, weight: weights.subculture,
            explanation: s.subcultureKeywordHits > 0 ? "Alternative-culture keywords in its description" : "Based on the type of place"
        ))

        // Community
        let communityKinds: Set<PlaceKind> = [.socialCentre, .communityCentre, .communityGarden, .hackerspace, .publicBookcase, .giveBox, .diySkatepark, .creativeHub]
        let community = s.communityOperated ? 1.0 : (communityKinds.contains(kind) ? 0.75 : 0.3)
        components.append(ScoreComponent(
            kind: .community, value: community, weight: weights.community,
            explanation: s.communityOperated ? "Run by a community, co-op or non-profit" : (communityKinds.contains(kind) ? "Community-oriented space" : "Commercial or unspecified operator")
        ))

        // Source diversity
        let providerCount = place.providers.subtracting([.sample]).count
        let diversity: Double = providerCount >= 3 ? 1.0 : (providerCount == 2 ? 0.75 : 0.35)
        components.append(ScoreComponent(
            kind: .sourceDiversity, value: diversity, weight: weights.sourceDiversity,
            explanation: "Confirmed by \(providerCount) independent source\(providerCount == 1 ? "" : "s")"
        ))

        // Social signal (only when measured)
        if let mentions = s.socialMentions {
            let value: Double
            switch mentions {
            case 0: value = 0.35
            case 1...5: value = 0.9
            case 6...15: value = 0.65
            default: value = 0.35
            }
            components.append(ScoreComponent(
                kind: .socialSignal, value: value, weight: weights.socialSignal,
                explanation: mentions == 0 ? "No video mentions found" : "\(mentions) recent video mention\(mentions == 1 ? "" : "s")"
            ))
        }

        // Renormalise weights of available components.
        let totalWeight = components.reduce(0) { $0 + $1.weight }
        components = components.map { var c = $0; c.weight = $0.weight / totalWeight; return c }
        let raw = components.reduce(0) { $0 + $1.value * $1.weight }
        let confidence = Self.confidence(for: place, now: now)
        let value = raw * (0.55 + 0.45 * confidence)
        return NicheScore(value: max(0, min(1, value)), rawValue: raw, confidence: confidence, components: components)
    }

    /// Data confidence 0…1.
    static func confidence(for place: Place, now: Date) -> Double {
        var c = 0.0
        if !place.isNameInferred { c += 0.2 } else { c += 0.08 }
        c += 0.25 * min(1, place.signals.tagRichness)
        if let confirmed = place.signals.lastConfirmed {
            let years = now.timeIntervalSince(confirmed) / (365 * 24 * 3600)
            c += years <= 2 ? 0.2 : (years <= 5 ? 0.1 : 0.03)
        }
        let providers = place.providers.subtracting([.sample]).count
        c += providers >= 2 ? 0.25 : 0.08
        var details = 0.0
        if place.address?.isEmpty == false { details += 0.04 }
        if place.openingHoursRaw != nil { details += 0.04 }
        if place.website != nil { details += 0.03 }
        if !place.images.isEmpty { details += 0.02 }
        c += details
        // Public spaces (art, viewpoints) don't need hours/addresses to be reliable.
        if !place.kind.isBusiness { c += 0.07 }
        // A business known only from encyclopaedic sources may have closed
        // since: without a map or business-directory record it stays unverified.
        if place.kind.isBusiness && isEncyclopedicOnly(place) { c *= 0.6 }
        return min(1, c)
    }

    static func isEncyclopedicOnly(_ place: Place) -> Bool {
        let providers = place.providers
        return !providers.isEmpty && providers.isSubset(of: [.wikidata, .wikipedia, .wikimediaCommons])
    }

    static func confidenceLevel(for place: Place, confidence: Double, now: Date) -> ConfidenceLevel {
        let providers = place.providers.subtracting([.sample]).count
        if place.kind.isBusiness && isEncyclopedicOnly(place) { return .uncertain }
        let recentlyChecked = place.signals.lastConfirmed.map { now.timeIntervalSince($0) <= 2 * 365 * 24 * 3600 } ?? false
        if confidence >= 0.62 && (providers >= 2 || recentlyChecked) { return .verified }
        if confidence >= 0.38 { return .partial }
        return .uncertain
    }
}
