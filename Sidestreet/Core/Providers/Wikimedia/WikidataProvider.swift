import Foundation

/// Wikidata Query Service (free, no key, CC0 data).
///
/// Two uses:
/// 1. `searchPlaces` — items near the centre that are brutalist/modernist
///    architecture, street art, skateparks, music venues, record shops,
///    arthouse cinemas, social centres, viewpoints, public bookcases …
///    (entity IDs verified against Wikidata, see docs/DATA_SOURCES.md).
/// 2. `enrichment` — for places that OSM links to Wikidata: number of
///    Wikipedia language editions (a fame signal for the niche score), an
///    image and a short description.
struct WikidataProvider: PlaceSearchProvider {
    static let endpoint = URL(string: "https://query.wikidata.org/sparql")!

    var client: HTTPClient
    var languages = "en,mul,de,fr,es,it,nl,pt,pl,sv,da,cs,ja,ko,zh"

    var provider: SourceProvider { .wikidata }

    /// Architectural styles (P149).
    static let styleKinds: [String: PlaceKind] = [
        "Q994776": .brutalistBuilding,   // brutalist architecture
        "Q245188": .modernistBuilding,   // modern architecture
        "Q841977": .modernistBuilding,   // constructivist architecture
        "Q595448": .modernistBuilding,   // postmodern architecture
        "Q1148060": .modernistBuilding,  // expressionist architecture
        "Q162324": .modernistBuilding,   // International Style
        "Q1503425": .modernistBuilding,  // Metabolism
        "Q238255": .modernistBuilding,   // deconstructivism
        "Q11784483": .modernistBuilding, // Neues Bauen
        "Q845318": .modernistBuilding,   // high-tech architecture
        "Q1134824": .modernistBuilding,  // Stalinist architecture
    ]

    /// Instance-of classes (P31).
    static let classKinds: [String: PlaceKind] = [
        "Q909906": .skatepark,
        "Q219423": .mural,
        "Q17514": .graffiti,
        "Q17516": .streetArt,
        "Q8719053": .musicVenue,
        "Q622425": .nightclub,
        "Q2243978": .recordStore,
        "Q27921531": .independentCinema,
        "Q8536775": .socialCentre,
        "Q385870": .fleaMarket,
        "Q274153": .waterTower,
        "Q1440300": .observationTower,
        "Q6017969": .viewpoint,
        "Q294297": .publicBookcase,
        "Q251958": .communityGarden,
        "Q260676": .arcade,
        "Q16590780": .comicStore,
        "Q4034417": .creativeHub,
        "Q7900097": .beach,
        "Q1068842": .bridge,
    ]

    /// Venue-like kinds that are dropped when Wikidata says the item no longer operates.
    private static let operatingKinds: Set<PlaceKind> = [
        .musicVenue, .nightclub, .recordStore, .independentCinema, .socialCentre, .fleaMarket, .arcade,
        .comicStore, .creativeHub,
    ]

    static func aroundQuery(_ area: SearchArea, languages: String) -> String {
        let radiusKm = String(format: "%.2f", min(GeoMath.clampRadius(area.radiusMeters), 25_000) / 1000)
        let center = String(format: "Point(%.6f %.6f)", area.center.longitude, area.center.latitude)
        let styles = styleKinds.keys.sorted().map { "wd:\($0)" }.joined(separator: " ")
        let classes = classKinds.keys.sorted().map { "wd:\($0)" }.joined(separator: " ")
        return """
        SELECT ?item ?itemLabel ?itemDescription ?coord ?image ?sitelinks ?match ?website ?commonsCat WHERE {
          SERVICE wikibase:around {
            ?item wdt:P625 ?coord .
            bd:serviceParam wikibase:center "\(center)"^^geo:wktLiteral .
            bd:serviceParam wikibase:radius "\(radiusKm)" .
          }
          { VALUES ?match { \(styles) } ?item wdt:P149 ?match . }
          UNION
          { VALUES ?match { \(classes) } ?item wdt:P31 ?match . }
          FILTER NOT EXISTS { ?item wdt:P576 ?dissolved . }
          FILTER NOT EXISTS { ?item wdt:P3999 ?closed . }
          ?item wikibase:sitelinks ?sitelinks .
          OPTIONAL { ?item wdt:P18 ?image . }
          OPTIONAL { ?item wdt:P856 ?website . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "\(languages)". }
        } LIMIT 600
        """
    }

    static func enrichmentQuery(ids: [String]) -> String {
        let values = ids.map { "wd:\($0)" }.joined(separator: " ")
        return """
        SELECT ?item ?sitelinks ?image ?desc ?enwiki WHERE {
          VALUES ?item { \(values) }
          ?item wikibase:sitelinks ?sitelinks .
          OPTIONAL { ?item wdt:P18 ?image . }
          OPTIONAL { ?item schema:description ?desc . FILTER(lang(?desc) = "en") }
          OPTIONAL { ?enwiki schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> . }
        }
        """
    }

    private func execute(_ query: String) async throws -> SPARQLResults {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = "query=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        let request = HTTPRequest(
            url: Self.endpoint,
            method: .post,
            headers: ["Accept": "application/sparql-results+json",
                      "Content-Type": "application/x-www-form-urlencoded; charset=utf-8"],
            body: Data(body.utf8),
            timeout: 40
        )
        let response = try await client.sendChecked(request)
        do {
            return try JSONDecoder().decode(SPARQLResults.self, from: response.data)
        } catch {
            throw NetworkError.decoding("Wikidata")
        }
    }

    func searchPlaces(in area: SearchArea, now: Date) async throws -> [Place] {
        let results = try await execute(Self.aroundQuery(area, languages: languages))
        return Self.places(from: results, area: area, now: now)
    }

    static func places(from results: SPARQLResults, area: SearchArea, now: Date) -> [Place] {
        var byID: [String: Place] = [:]
        var order: [String] = []
        for row in results.results.bindings {
            guard let id = row.entityID("item"), let coordinate = row.point("coord"),
                  let match = row.entityID("match") else { continue }
            guard let label = row.string("itemLabel"), !label.isEmpty, label != id else { continue }
            let isStyle = styleKinds[match] != nil
            guard let matchedKind = styleKinds[match] ?? classKinds[match] else { continue }
            let description = row.string("itemDescription")
            if operatingKinds.contains(matchedKind), let description, isDefunct(description) { continue }

            if var existing = byID[id] {
                // Prefer the more specific/niche classification.
                if matchedKind.intrinsicNiche > existing.kind.intrinsicNiche && !(isStyle && existing.kind.primaryCategory != .architecture) {
                    existing.kind = matchedKind
                    existing.categories.formUnion(matchedKind.categories)
                }
                if let image = row.string("image"), existing.images.count < 3 {
                    appendImage(image, to: &existing)
                }
                byID[id] = existing
                continue
            }
            guard GeoMath.distance(coordinate, area.center) <= area.radiusMeters * 1.05 + 30 else { continue }

            var place = Place(
                id: "wd:\(id)",
                name: label,
                coordinate: coordinate,
                kind: matchedKind,
                categories: Set(matchedKind.categories)
            )
            place.wikidataID = id
            place.summary = description.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            if let website = row.string("website"), let url = URL(string: website),
               url.scheme?.hasPrefix("http") == true {
                place.website = url
            }
            if let image = row.string("image") { appendImage(image, to: &place) }
            place.sources = [SourceRecord(provider: .wikidata, identifier: id,
                                          url: URL(string: "https://www.wikidata.org/wiki/\(id)"), retrievedAt: now)]
            place.signals.wikipediaSitelinks = row.int("sitelinks")
            place.signals.hasWikipediaArticle = (row.int("sitelinks") ?? 0) > 0
            place.signals.tagRichness = 0.4
            place.price = OSMPlaceBuilder.price(from: [:], kind: matchedKind, brand: nil)
            let keywordText = [label, description ?? ""].joined(separator: " ")
            place.signals.subcultureKeywordHits = TextMatching.containsAny(keywordText, keywords: SubcultureLexicon.keywords)
            byID[id] = place
            order.append(id)
        }
        return order.compactMap { byID[$0] }
    }

    static func isDefunct(_ description: String) -> Bool {
        let lower = description.lowercased()
        return ["former", "defunct", "closed", "demolished", "ehemalig", "nicht erhalten", "ancien", "antiguo", "ex-"]
            .contains { lower.hasPrefix($0) || lower.contains(" \($0) ") }
    }

    private static func appendImage(_ value: String, to place: inout Place) {
        guard let url = WikimediaImageURL.thumbnail(fileName: value),
              !place.images.contains(where: { $0.url == url }) else { return }
        place.images.append(PlaceImage(url: url, pageURL: WikimediaImageURL.descriptionPage(fileName: value),
                                       attribution: "Wikimedia Commons", license: nil,
                                       provider: .wikimediaCommons, origin: .linked))
    }

    struct Enrichment: Sendable, Hashable {
        var sitelinks: Int
        var image: URL?
        var imagePage: URL?
        var description: String?
        var englishWikipedia: URL?
    }

    /// Fetches fame signals and images for Wikidata IDs (batched).
    func enrichment(for ids: [String]) async throws -> [String: Enrichment] {
        let unique = Array(Set(ids)).sorted()
        guard !unique.isEmpty else { return [:] }
        var result: [String: Enrichment] = [:]
        for batchStart in stride(from: 0, to: min(unique.count, 400), by: 150) {
            let batch = Array(unique[batchStart..<min(batchStart + 150, unique.count)])
            let results = try await execute(Self.enrichmentQuery(ids: batch))
            for row in results.results.bindings {
                guard let id = row.entityID("item") else { continue }
                var entry = result[id] ?? Enrichment(sitelinks: row.int("sitelinks") ?? 0)
                if entry.image == nil, let image = row.string("image") {
                    entry.image = WikimediaImageURL.thumbnail(fileName: image)
                    entry.imagePage = WikimediaImageURL.descriptionPage(fileName: image)
                }
                if entry.description == nil { entry.description = row.string("desc") }
                if entry.englishWikipedia == nil, let wiki = row.string("enwiki") { entry.englishWikipedia = URL(string: wiki) }
                result[id] = entry
            }
        }
        return result
    }
}
