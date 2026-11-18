import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

/// Live integration tests against the real, free data sources.
///
/// Skipped by default. Run with `LIVE_SOURCES=1 swift test --filter LiveSourcesTests`
/// (the CI workflow does this on a schedule and on demand). They verify that
/// the integrations actually work and print a ranked discovery report so
/// result quality can be inspected.
final class LiveSourcesTests: XCTestCase {
    struct City {
        var name: String
        var center: GeoCoordinate
        var radius: Double
        var timeZone: String
    }

    static let cities: [City] = [
        City(name: "Berlin – Kreuzberg", center: GeoCoordinate(latitude: 52.4990, longitude: 13.4155), radius: 2_000, timeZone: "Europe/Berlin"),
        City(name: "London – Shoreditch", center: GeoCoordinate(latitude: 51.5246, longitude: -0.0786), radius: 2_000, timeZone: "Europe/London"),
        City(name: "Tokyo – Shimokitazawa", center: GeoCoordinate(latitude: 35.6616, longitude: 139.6680), radius: 1_500, timeZone: "Asia/Tokyo"),
        City(name: "Lisbon – Intendente", center: GeoCoordinate(latitude: 38.7223, longitude: -9.1360), radius: 2_000, timeZone: "Europe/Lisbon"),
    ]

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_SOURCES"] == "1", "Set LIVE_SOURCES=1 to run live tests")
    }

    var skipOverpass: Bool { ProcessInfo.processInfo.environment["LIVE_SKIP_OVERPASS"] == "1" }

    func makeClient() -> URLSessionHTTPClient {
        URLSessionHTTPClient(identity: ClientIdentity(appVersion: "1.0-ci", contact: "https://github.com/"))
    }

    func testLiveDiscoveryReport() async throws {
        let client = makeClient()
        for (index, city) in Self.cities.enumerated() {
            if ProcessInfo.processInfo.environment["LIVE_ALL_CITIES"] != "1" && index > 1 { break }
            let area = SearchArea(center: city.center, radiusMeters: city.radius, label: city.name, subtitle: nil,
                                  centerSource: .city, timeZoneIdentifier: city.timeZone, countryCode: nil)
            let engine = DiscoveryEngine(
                sources: .init(
                    overpass: skipOverpass ? nil : OverpassProvider(client: client),
                    wikidata: WikidataProvider(client: client),
                    supplementary: [],
                    venueEvents: VenueEventsProvider(client: client, maxVenues: 8)
                ),
                cache: DiscoveryCache(directory: nil)
            )
            let started = Date()
            var firstResultsAfter: TimeInterval?
            var final: DiscoverySnapshot?
            for await update in engine.discover(area: area, forceRefresh: true) {
                if firstResultsAfter == nil && !update.snapshot.places.isEmpty {
                    firstResultsAfter = Date().timeIntervalSince(started)
                }
                final = update.snapshot
            }
            let snapshot = try XCTUnwrap(final)
            let now = Date()
            let feed = FeedRanker().rank(places: snapshot.places, events: snapshot.events, area: area,
                                         filter: CategoryFilter(), now: now)

            print("\n==================== \(city.name) (r=\(Int(city.radius)) m) ====================")
            print("first results after: \(firstResultsAfter.map { String(format: "%.1fs", $0) } ?? "–"), complete after \(String(format: "%.1fs", Date().timeIntervalSince(started)))")
            for (provider, status) in snapshot.sourceStatuses.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                print("  source \(provider.displayName): \(status)")
            }
            let kinds = Dictionary(grouping: snapshot.places, by: \.kind).mapValues(\.count)
                .sorted { $0.value > $1.value }.prefix(18).map { "\($0.key.rawValue)=\($0.value)" }
            print("  places: \(snapshot.places.count), events: \(snapshot.events.count)")
            print("  kinds: \(kinds.joined(separator: ", "))")
            print("  confidence: " + [ConfidenceLevel.verified, .partial, .uncertain].map { level in
                "\(level.rawValue)=\(snapshot.places.filter { $0.confidence == level }.count)"
            }.joined(separator: " "))
            print("  with image: \(snapshot.places.filter { $0.primaryImage != nil }.count)")
            print("  --- top 30 of feed ---")
            for (rank, entry) in feed.prefix(30).enumerated() {
                switch entry {
                case .place(let p):
                    let d = Int(GeoMath.distance(p.coordinate, area.center))
                    let sources = p.providers.map(\.rawValue).sorted().joined(separator: "+")
                    print(String(format: "  %2d. [%3d] %@ — %@ · %dm · %@ · %@%@", rank + 1, p.score?.display ?? 0,
                                 p.name, p.kind.label, d, p.confidence.rawValue, sources, p.primaryImage != nil ? " · img" : ""))
                case .event(let e):
                    print("  \(rank + 1). [EVENT] \(e.title) — \(e.kind.label) · \(e.start) · \(e.source.provider.rawValue)")
                }
            }
            let chains = snapshot.places.filter { $0.kind == .fashionChain }
            if let worstChainRank = chains.compactMap({ chain in feed.firstIndex { $0.id == "p:" + chain.id } }).min() {
                print("  best-ranked chain store position: \(worstChainRank + 1) of \(feed.count)")
            }
            for event in snapshot.events.prefix(10) {
                print("  event: \(event.title) | \(event.start) | \(event.kind.label) | \(event.source.provider.rawValue) | \(event.venueName ?? "-")")
            }

            if !skipOverpass {
                XCTAssertFalse(snapshot.sourceStatuses[.openStreetMap]?.isFailure ?? true, "OSM failed for \(city.name)")
                XCTAssertGreaterThan(snapshot.places.count, 20, "too few places in \(city.name)")
                // Chains must not dominate the top of the feed.
                let topChains = feed.prefix(20).filter {
                    if case .place(let p) = $0 { return p.brand?.wikidataID != nil }
                    return false
                }
                XCTAssertLessThanOrEqual(topChains.count, 1, "chains in top 20 for \(city.name)")
            }
            // Pause between cities (Overpass etiquette).
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    /// Diagnostic: query each Overpass endpoint directly and report timing.
    func testOverpassEndpointsDirect() async throws {
        try XCTSkipIf(skipOverpass)
        let client = makeClient()
        let area = SearchArea(center: Self.cities[0].center, radiusMeters: 2_000, label: "Berlin", subtitle: nil,
                              centerSource: .city, timeZoneIdentifier: "Europe/Berlin", countryCode: nil)
        var anySucceeded = false
        for endpoint in OverpassProvider.defaultEndpoints {
            for kind in [OverpassQueryBuilder.Kind.niche, .everyday] {
                let started = Date()
                let provider = OverpassProvider(client: client, endpoints: [endpoint])
                do {
                    let response = try await provider.run(query: OverpassQueryBuilder.query(kind, area: area))
                    let places = OverpassProvider.places(from: response, area: area, now: Date())
                    anySucceeded = true
                    print(String(format: "overpass %@ %@: %.1fs, %d elements → %d places, remark: %@",
                                 endpoint.host ?? "?", kind.rawValue, Date().timeIntervalSince(started),
                                 response.elements.count, places.count, response.remark ?? "-"))
                } catch {
                    print(String(format: "overpass %@ %@: FAILED after %.1fs: %@", endpoint.host ?? "?", kind.rawValue,
                                 Date().timeIntervalSince(started), String(describing: error)))
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        XCTAssertTrue(anySucceeded, "no Overpass endpoint answered")
    }

    func testCommonsThumbnailsResolve() async throws {
        let client = makeClient()
        for file in ["Tresor - Berlin.jpg", "Berlin-kreuzberg anhalter-steg 20061018 219.jpg"] {
            let url = try XCTUnwrap(WikimediaImageURL.thumbnail(fileName: file))
            let response = try await client.send(HTTPRequest(url: url, timeout: 20))
            XCTAssertEqual(response.status, 200, "\(url)")
            XCTAssertTrue(response.header("Content-Type")?.contains("image") ?? false)
        }
    }

    func testCommonsNearbyAndWikipediaSummary() async throws {
        let client = makeClient()
        let photos = try await CommonsPhotoService(client: client).photos(near: GeoCoordinate(latitude: 52.51, longitude: 13.38277), radius: 100)
        print("commons nearby photos: \(photos.count) e.g. \(photos.first?.attribution ?? "-") \(photos.first?.license ?? "")")
        XCTAssertFalse(photos.isEmpty)
        do {
            let summary = try await WikipediaSummaryService(client: client).summary(reference: "en:Tresor (club)")
            print("wikipedia summary: \(summary?.extract.prefix(120) ?? "nil")")
            XCTAssertNotNil(summary)
        } catch NetworkError.httpStatus(429), NetworkError.rateLimited {
            // Shared CI/cloud IPs are sometimes rate limited by Wikimedia; the app handles this gracefully.
            throw XCTSkip("Wikipedia rate-limited this shared IP")
        }
    }
}
