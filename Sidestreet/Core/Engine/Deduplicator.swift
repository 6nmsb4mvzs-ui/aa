import Foundation

/// Merges records that describe the same physical place.
///
/// Matching uses, in order of reliability:
/// 1. Shared identifiers (same OSM element, same Wikidata item — OSM's
///    `wikidata` tag links the two databases).
/// 2. Geographic proximity *and* name similarity. Proximity alone never
///    merges (two shops in one building stay separate), and similar names
///    far apart never merge (chain branches stay separate).
enum Deduplicator {
    struct Thresholds: Sendable {
        /// Beyond this distance records are never merged.
        var maxDistance: Double = 120
        /// Strong name match required within `maxDistance`.
        var strongSimilarity: Double = 0.88
        /// Weaker name match accepted when very close.
        var closeDistance: Double = 30
        var closeSimilarity: Double = 0.72
        /// Two records from the *same* provider (e.g. an OSM node and an OSM
        /// building way for one shop) need a near-identical name.
        var sameProviderSimilarity: Double = 0.95
        var sameProviderDistance: Double = 80
        /// Apple Maps / Wikidata coordinates can sit further from the OSM
        /// point (building centroid vs. entrance); allow more distance for a
        /// near-identical name from a different source.
        var crossSourceExactDistance: Double = 220
        var crossSourceExactSimilarity: Double = 0.95
    }

    static func shouldMerge(_ a: Place, _ b: Place, thresholds: Thresholds = Thresholds()) -> Bool {
        if a.id == b.id { return true }
        if let wa = a.wikidataID, let wb = b.wikidataID { return wa == wb }
        let distance = GeoMath.distance(a.coordinate, b.coordinate)
        // Inferred names ("Untitled mural") carry no identity.
        guard !a.isNameInferred, !b.isNameInferred else { return false }
        let sameProvider = !a.providers.isDisjoint(with: b.providers)
        if !sameProvider && distance <= thresholds.crossSourceExactDistance && compatible(a.kind, b.kind) {
            if TextMatching.nameSimilarity(a.name, b.name) >= thresholds.crossSourceExactSimilarity { return true }
        }
        guard distance <= thresholds.maxDistance else { return false }
        let similarity = TextMatching.nameSimilarity(a.name, b.name)
        if sameProvider {
            return similarity >= thresholds.sameProviderSimilarity && distance <= thresholds.sameProviderDistance
                && compatible(a.kind, b.kind)
        }
        if similarity >= thresholds.strongSimilarity { return true }
        if distance <= thresholds.closeDistance && similarity >= thresholds.closeSimilarity { return compatible(a.kind, b.kind) }
        return false
    }

    /// Whether two kinds could plausibly describe the same place.
    static func compatible(_ a: PlaceKind, _ b: PlaceKind) -> Bool {
        if a == b { return true }
        let ca = Set(a.categories), cb = Set(b.categories)
        return !ca.isDisjoint(with: cb)
    }

    static func merge(_ places: [Place], thresholds: Thresholds = Thresholds()) -> [Place] {
        guard places.count > 1 else { return places }
        var parent = Array(0..<places.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        // 1. Identifier matches.
        var byID: [String: Int] = [:]
        var byWikidata: [String: Int] = [:]
        for (index, place) in places.enumerated() {
            if let existing = byID[place.id] { union(existing, index) } else { byID[place.id] = index }
            if let qid = place.wikidataID {
                if let existing = byWikidata[qid] { union(existing, index) } else { byWikidata[qid] = index }
            }
        }

        // 2. Spatial grid (≈ 250 m cells) to compare only nearby candidates.
        let cellSize = 0.0023
        var grid: [String: [Int]] = [:]
        func cell(_ c: GeoCoordinate) -> (Int, Int) {
            let lonScale = max(0.2, cos(c.latitude * .pi / 180))
            return (Int(floor(c.latitude / cellSize)), Int(floor(c.longitude * lonScale / cellSize)))
        }
        for (index, place) in places.enumerated() {
            let (x, y) = cell(place.coordinate)
            grid["\(x):\(y)", default: []].append(index)
        }
        for (index, place) in places.enumerated() {
            let (x, y) = cell(place.coordinate)
            for dx in -1...1 {
                for dy in -1...1 {
                    for other in grid["\(x + dx):\(y + dy)"] ?? [] where other > index {
                        if find(index) == find(other) { continue }
                        // Conflicting Wikidata IDs mean distinct items.
                        if let wa = place.wikidataID, let wb = places[other].wikidataID, wa != wb { continue }
                        if shouldMerge(place, places[other], thresholds: thresholds) { union(index, other) }
                    }
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        var order: [Int] = []
        for index in places.indices {
            let root = find(index)
            if groups[root] == nil { order.append(root) }
            groups[root, default: []].append(index)
        }
        return order.map { root in
            let members = groups[root]!.map { places[$0] }
            return members.count == 1 ? members[0] : combine(members)
        }
    }

    /// Provider priority for structured fields (hours, address).
    private static func priority(_ provider: SourceProvider) -> Int {
        switch provider {
        case .openStreetMap: return 0
        case .appleMaps: return 1
        case .wikidata: return 2
        default: return 3
        }
    }

    static func combine(_ members: [Place]) -> Place {
        let sorted = members.sorted {
            let pa = $0.sources.map { priority($0.provider) }.min() ?? 9
            let pb = $1.sources.map { priority($0.provider) }.min() ?? 9
            if pa != pb { return pa < pb }
            return $0.signals.tagRichness > $1.signals.tagRichness
        }
        var base = sorted[0]
        for other in sorted.dropFirst() {
            if base.isNameInferred && !other.isNameInferred {
                base.name = other.name
                base.isNameInferred = false
            }
            // Keep the more specific kind (e.g. "Record store" over "Shop").
            if other.kind.intrinsicNiche > base.kind.intrinsicNiche && compatible(other.kind, base.kind) && base.kind != .fashionChain {
                base.kind = other.kind
            }
            base.categories.formUnion(other.categories)
            for descriptor in other.descriptors where !base.descriptors.contains(descriptor) {
                base.descriptors.append(descriptor)
            }
            if base.address == nil || base.address?.isEmpty == true { base.address = other.address }
            base.openingHoursRaw = base.openingHoursRaw ?? other.openingHoursRaw
            base.website = base.website ?? other.website
            base.phone = base.phone ?? other.phone
            if base.summary == nil || (other.summary?.count ?? 0) > (base.summary?.count ?? 0) * 2 {
                base.summary = other.summary ?? base.summary
            }
            for image in other.images where !base.images.contains(where: { $0.url == image.url }) {
                base.images.append(image)
            }
            if case .unknown = base.price { base.price = other.price }
            if case .estimated = base.price, case .level = other.price { base.price = other.price }
            base.brand = base.brand ?? other.brand
            base.wikidataID = base.wikidataID ?? other.wikidataID
            base.wikipediaTitle = base.wikipediaTitle ?? other.wikipediaTitle
            for source in other.sources where !base.sources.contains(where: { $0.provider == source.provider && $0.identifier == source.identifier }) {
                base.sources.append(source)
            }
            base.signals = mergeSignals(base.signals, other.signals)
        }
        base.images.sort { ($0.origin == .linked ? 0 : 1) < ($1.origin == .linked ? 0 : 1) }
        var aliases = Set(base.aliasIDs ?? [])
        for member in sorted.dropFirst() { aliases.formUnion(member.allIDs) }
        aliases.remove(base.id)
        base.aliasIDs = aliases.isEmpty ? nil : aliases.sorted()
        return base
    }

    static func mergeSignals(_ a: PlaceSignals, _ b: PlaceSignals) -> PlaceSignals {
        var s = a
        s.wikipediaSitelinks = [a.wikipediaSitelinks, b.wikipediaSitelinks].compactMap { $0 }.max()
        s.hasWikipediaArticle = a.hasWikipediaArticle || b.hasWikipediaArticle
        s.isTouristAttraction = a.isTouristAttraction || b.isTouristAttraction
        s.appleGenericVisibility = a.appleGenericVisibility || b.appleGenericVisibility
        s.subcultureKeywordHits = max(a.subcultureKeywordHits, b.subcultureKeywordHits)
        s.communityOperated = a.communityOperated || b.communityOperated
        s.tagRichness = max(a.tagRichness, b.tagRichness)
        s.lastConfirmed = [a.lastConfirmed, b.lastConfirmed].compactMap { $0 }.max()
        s.socialMentions = [a.socialMentions, b.socialMentions].compactMap { $0 }.max()
        return s
    }
}
