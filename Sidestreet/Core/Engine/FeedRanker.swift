import Foundation

/// Category on/off filters. An empty selection means "everything".
struct CategoryFilter: Hashable, Codable, Sendable {
    var selected: Set<DiscoveryCategory> = []

    var isShowingAll: Bool { selected.isEmpty }

    func matches(_ place: Place) -> Bool {
        selected.isEmpty || !selected.isDisjoint(with: place.categories)
    }

    func matches(_ event: DiscoveryEvent) -> Bool {
        selected.isEmpty || !selected.isDisjoint(with: event.categories)
    }

    /// How strongly a place matches (primary category counts more).
    func relevance(of place: Place) -> Double {
        if selected.isEmpty { return 0.6 }
        if selected.contains(place.primaryCategory) { return 1.0 }
        return selected.isDisjoint(with: place.categories) ? 0 : 0.7
    }

    mutating func toggle(_ category: DiscoveryCategory) {
        if selected.contains(category) { selected.remove(category) } else { selected.insert(category) }
    }
}

/// Hybrid feed ranking with variety-aware re-ranking.
///
/// Base score = 0.38 niche + 0.17 quality + 0.10 affordability
///            + 0.20 distance + 0.15 relevance
///
/// Then a greedy re-ranking picks, at each position, the best remaining
/// entry after penalties for repeating the previous category, repeating a
/// type seen in the last few cards, or sitting right next to the previous
/// place — so the feed doesn't show five cafés in a row.
struct FeedRanker: Sendable {
    struct Weights: Sendable {
        var niche = 0.38
        var quality = 0.17
        var affordability = 0.10
        var distance = 0.20
        var relevance = 0.15
    }

    struct Penalties: Sendable {
        var sameCategoryAsPrevious = 0.10
        var sameTypeInWindow = 0.08
        var categoryCrowding = 0.06
        var adjacentLocation = 0.04
        var window = 4
        var candidatePool = 40
    }

    var weights = Weights()
    var penalties = Penalties()

    func baseScore(_ place: Place, area: SearchArea, filter: CategoryFilter) -> Double {
        let niche = place.score?.value ?? 0
        let confidence = place.score?.confidence ?? NicheScorer.confidence(for: place, now: Date())
        var completeness = 0.0
        if place.primaryImage != nil { completeness += 0.4 }
        if place.openingHoursRaw != nil || !place.kind.isBusiness { completeness += 0.3 }
        if place.address?.isEmpty == false || !place.kind.isBusiness { completeness += 0.3 }
        let quality = 0.6 * confidence + 0.4 * completeness
        let affordability = place.price.affordabilityScore ?? 0.5
        let d = GeoMath.distance(place.coordinate, area.center)
        let distance = exp(-d / max(250, 0.45 * area.radiusMeters))
        let relevance = filter.relevance(of: place)
        return weights.niche * niche + weights.quality * quality + weights.affordability * affordability
            + weights.distance * distance + weights.relevance * relevance
    }

    func baseScore(_ event: DiscoveryEvent, area: SearchArea, filter: CategoryFilter, now: Date, venue: Place?) -> Double {
        let hoursAway = max(0, event.start.timeIntervalSince(now) / 3600)
        // Happening now or within 2 days ranks highest; fades over ~3 weeks.
        let urgency = event.start <= now ? 1.0 : exp(-hoursAway / (24 * 9))
        let confidence: Double = event.confidence == .verified ? 1 : (event.confidence == .partial ? 0.65 : 0.35)
        var distance = 0.5
        if let c = event.coordinate {
            distance = exp(-GeoMath.distance(c, area.center) / max(250, 0.45 * area.radiusMeters))
        }
        let niche = venue?.score?.value ?? 0.55
        let relevance: Double = filter.isShowingAll ? 0.6 : (filter.selected.contains(.events) ? 1.0 : 0.7)
        return 0.30 * urgency + 0.15 * confidence + 0.20 * distance + 0.20 * niche + 0.15 * relevance
    }

    /// Filters and orders the whole feed.
    func rank(places: [Place], events: [DiscoveryEvent], area: SearchArea, filter: CategoryFilter, now: Date) -> [FeedEntry] {
        let venues = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var candidates: [(entry: FeedEntry, score: Double)] = []
        for place in places where filter.matches(place) && area.contains(place.coordinate) {
            candidates.append((.place(place), baseScore(place, area: area, filter: filter)))
        }
        for event in events where filter.matches(event) && event.isUpcoming(now: now) {
            if let c = event.coordinate, !area.contains(c) { continue }
            let venue = event.venuePlaceID.flatMap { venues[$0] }
            candidates.append((.event(event), baseScore(event, area: area, filter: filter, now: now, venue: venue)))
        }
        candidates.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.entry.id < rhs.entry.id
        }
        return diversify(candidates)
    }

    func diversify(_ sorted: [(entry: FeedEntry, score: Double)]) -> [FeedEntry] {
        var remaining = sorted
        var result: [FeedEntry] = []
        result.reserveCapacity(sorted.count)
        while !remaining.isEmpty {
            let poolSize = min(penalties.candidatePool, remaining.count)
            var bestIndex = 0
            var bestValue = -Double.infinity
            for i in 0..<poolSize {
                let candidate = remaining[i]
                let value = candidate.score - penalty(for: candidate.entry, after: result)
                if value > bestValue {
                    bestValue = value
                    bestIndex = i
                }
            }
            result.append(remaining.remove(at: bestIndex).entry)
        }
        return result
    }

    func penalty(for entry: FeedEntry, after previous: [FeedEntry]) -> Double {
        guard let last = previous.last else { return 0 }
        var p = 0.0
        if last.primaryCategory == entry.primaryCategory { p += penalties.sameCategoryAsPrevious }
        let window = previous.suffix(penalties.window)
        if window.contains(where: { $0.varietyKey == entry.varietyKey }) { p += penalties.sameTypeInWindow }
        if window.filter({ $0.primaryCategory == entry.primaryCategory }).count >= 2 { p += penalties.categoryCrowding }
        if let a = last.coordinate, let b = entry.coordinate, GeoMath.distance(a, b) < 80 { p += penalties.adjacentLocation }
        return p
    }
}
