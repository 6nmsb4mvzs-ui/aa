import XCTest
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

/// Thread-safe mutable clock for cache tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}

final class DiscoveryCacheTests: XCTestCase {
    var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cache-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func snapshot(radius: Double, now: Date, places: [Place]? = nil) -> DiscoverySnapshot {
        DiscoverySnapshot(area: Fixture.area(radius: radius),
                          places: places ?? [Fixture.place(id: "a", at: Fixture.offset(north: 300)),
                                             Fixture.place(id: "b", at: Fixture.offset(north: 2_500))],
                          events: [], sourceStatuses: [.openStreetMap: .loaded(count: 2)], generatedAt: now)
    }

    func testHitForSameOrSmallerRadiusAndMissForLarger() async {
        let clock = TestClock(Fixture.referenceDate)
        let cache = DiscoveryCache(directory: directory, clock: { clock.now })
        await cache.store(snapshot(radius: 3_000, now: clock.now))

        let same = await cache.lookup(Fixture.area(radius: 3_000))
        XCTAssertEqual(same?.places.count, 2)
        XCTAssertEqual(same?.isFromCache, true)

        let smaller = await cache.lookup(Fixture.area(radius: 1_000))
        XCTAssertEqual(smaller?.places.map(\.id), ["a"], "filtered locally to the smaller radius")

        let larger = await cache.lookup(Fixture.area(radius: 5_000))
        XCTAssertNil(larger, "a larger radius needs new data")
    }

    func testMissWhenCentreMovesTooFar() async {
        let cache = DiscoveryCache(directory: nil, clock: { Fixture.referenceDate })
        await cache.store(snapshot(radius: 3_000, now: Fixture.referenceDate))
        let moved = Fixture.area(center: Fixture.offset(north: 1_000), radius: 1_000)
        let nearby = Fixture.area(center: Fixture.offset(north: 100), radius: 1_000)
        let movedResult = await cache.lookup(moved)
        let nearbyResult = await cache.lookup(nearby)
        XCTAssertNil(movedResult)
        XCTAssertNotNil(nearbyResult)
    }

    func testEntriesExpire() async {
        let clock = TestClock(Fixture.referenceDate)
        let cache = DiscoveryCache(directory: directory, timeToLive: 3_600, clock: { clock.now })
        await cache.store(snapshot(radius: 2_000, now: clock.now))
        clock.advance(3_599)
        let fresh = await cache.lookup(Fixture.area(radius: 2_000))
        XCTAssertNotNil(fresh)
        clock.advance(2)
        let expired = await cache.lookup(Fixture.area(radius: 2_000))
        XCTAssertNil(expired)
        await cache.purgeExpired()
        let count = await cache.entryCount
        XCTAssertEqual(count, 0)
    }

    func testPersistsAcrossInstancesAndClears() async {
        let clock = TestClock(Fixture.referenceDate)
        let first = DiscoveryCache(directory: directory, clock: { clock.now })
        await first.store(snapshot(radius: 2_000, now: clock.now))
        let second = DiscoveryCache(directory: directory, clock: { clock.now })
        let restored = await second.lookup(Fixture.area(radius: 2_000))
        XCTAssertEqual(restored?.places.count, 1)
        let size = await second.diskSize()
        XCTAssertGreaterThan(size, 0)
        await second.clear()
        let afterClear = await second.lookup(Fixture.area(radius: 2_000))
        XCTAssertNil(afterClear)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testSizeLimitEvictsOldest() async {
        let clock = TestClock(Fixture.referenceDate)
        let cache = DiscoveryCache(directory: nil, maxEntries: 2, clock: { clock.now })
        for i in 0..<3 {
            var s = snapshot(radius: 1_000, now: clock.now)
            s.area.center = Fixture.offset(east: Double(i) * 5_000)
            await cache.store(s)
            clock.advance(10)
        }
        let count = await cache.entryCount
        XCTAssertEqual(count, 2)
        let oldest = await cache.lookup(Fixture.area(center: Fixture.offset(east: 0), radius: 1_000))
        XCTAssertNil(oldest)
    }

    func testExpiredEventsAreNotServedFromCache() async {
        let clock = TestClock(Fixture.referenceDate)
        let cache = DiscoveryCache(directory: nil, clock: { clock.now })
        let event = DiscoveryEvent(id: "e", title: "Market", kind: .fleaMarket, start: clock.now.addingTimeInterval(3_600),
                                   end: clock.now.addingTimeInterval(7_200), isAllDay: false, recurrence: nil, venueName: nil,
                                   venuePlaceID: nil, coordinate: Fixture.berlin, addressText: nil, url: nil, imageURL: nil,
                                   summary: nil, source: SourceRecord(provider: .openStreetMap, identifier: "x", url: nil, retrievedAt: clock.now),
                                   confidence: .partial, timeZoneIdentifier: nil)
        var s = snapshot(radius: 2_000, now: clock.now)
        s.events = [event]
        await cache.store(s)
        let before = await cache.lookup(Fixture.area(radius: 2_000))
        XCTAssertEqual(before?.events.count, 1)
        clock.advance(3 * 3_600)
        let after = await cache.lookup(Fixture.area(radius: 2_000))
        XCTAssertEqual(after?.events.count, 0)
    }

    func testEngineUsesCacheInsteadOfNetwork() async {
        let client = MockHTTPClient { _ in MockHTTPClient.ok(overpassFixture) }
        let cache = DiscoveryCache(directory: nil, clock: { Fixture.referenceDate })
        let engine = DiscoveryEngine(sources: .init(overpass: OverpassProvider(client: client, health: nil)), cache: cache,
                                     clock: { Fixture.referenceDate })
        for await _ in engine.discover(area: Fixture.area()) {}
        let requestsAfterFirst = client.requests.count
        XCTAssertEqual(requestsAfterFirst, 2, "niche + everyday query")
        var phases: [DiscoveryUpdate.Phase] = []
        for await update in engine.discover(area: Fixture.area(radius: 1_000)) { phases.append(update.phase) }
        XCTAssertEqual(phases, [.cached])
        XCTAssertEqual(client.requests.count, requestsAfterFirst, "no new requests for a cached, smaller area")
        for await _ in engine.discover(area: Fixture.area(), forceRefresh: true) {}
        XCTAssertEqual(client.requests.count, requestsAfterFirst + 2, "pull-to-refresh bypasses the cache")
    }

    func testResponseCacheExpiry() async {
        let clock = TestClock(Fixture.referenceDate)
        let cache = ResponseCache<String>(ttl: 60, clock: { clock.now })
        await cache.set("v", for: "k")
        let hit = await cache.value(for: "k")
        XCTAssertEqual(hit, "v")
        clock.advance(61)
        let miss = await cache.value(for: "k")
        XCTAssertNil(miss)
    }
}

final class SearchHistoryTests: XCTestCase {
    func testRecordDeduplicatesAndOrders() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SearchHistoryStore(fileURL: file)
        let berlin = Fixture.area(radius: 2_000)
        var paris = Fixture.area(center: GeoCoordinate(latitude: 48.8566, longitude: 2.3522), radius: 3_000)
        paris.label = "Paris"
        await store.record(berlin, resultCount: 10, filters: [], date: Fixture.referenceDate)
        await store.record(paris, resultCount: 5, filters: [.fashion], date: Fixture.referenceDate.addingTimeInterval(60))
        await store.record(berlin, resultCount: 12, filters: [.skate], date: Fixture.referenceDate.addingTimeInterval(120))
        let all = await store.all()
        XCTAssertEqual(all.map(\.label), ["Test City", "Paris"])
        XCTAssertEqual(all[0].resultCount, 12)
        XCTAssertEqual(all[0].filters, [.skate])

        let reloaded = await SearchHistoryStore(fileURL: file).all()
        XCTAssertEqual(reloaded.count, 2, "persisted locally")
        await store.remove(id: all[1].id)
        let afterRemove = await store.all()
        XCTAssertEqual(afterRemove.count, 1)
        await store.clear()
        let afterClear = await store.all()
        XCTAssertTrue(afterClear.isEmpty)
    }

    func testMaxEntries() async {
        let store = SearchHistoryStore(fileURL: nil, maxEntries: 3)
        for i in 0..<5 {
            var area = Fixture.area(center: Fixture.offset(east: Double(i) * 10_000))
            area.label = "City \(i)"
            await store.record(area, resultCount: i, filters: [], date: Fixture.referenceDate.addingTimeInterval(Double(i)))
        }
        let all = await store.all()
        XCTAssertEqual(all.map(\.label), ["City 4", "City 3", "City 2"])
    }
}

final class ValidationTests: XCTestCase {
    let now = Fixture.referenceDate

    func testRejectsInvalidPlaces() {
        let area = Fixture.area()
        XCTAssertTrue(PlaceValidator.isValid(Fixture.place(name: "Good Place"), area: area))
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "?"), area: area))
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "1234"), area: area))
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "unknown"), area: area))
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "Far", at: Fixture.offset(north: 5_000)), area: area))
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "Null Island", at: GeoCoordinate(latitude: 0, longitude: 0)), area: area))
        var noSource = Fixture.place(name: "No Source")
        noSource.sources = []
        XCTAssertFalse(PlaceValidator.isValid(noSource, area: area))
    }

    func testServiceBusinessesAreNeverShops() {
        let area = Fixture.area()
        let gardener = Fixture.place(name: "Gartenpflege Hausmeisterservice und Gebäudereinigung Trier", kind: .thriftStore,
                                     provider: .appleMaps)
        XCTAssertFalse(PlaceValidator.isValid(gardener, area: area))
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "City Cleaning Services", kind: .vintageStore), area: area))
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "Allianz Versicherung", kind: .cafe), area: area))
        // Real shops survive.
        XCTAssertTrue(PlaceValidator.isValid(Fixture.place(name: "Liebe auf den 2ten Blick", kind: .thriftStore), area: area))
        XCTAssertTrue(PlaceValidator.isValid(Fixture.place(name: "Ziegenbock.Bar", kind: .pub), area: area))
        XCTAssertTrue(PlaceValidator.isValid(Fixture.place(name: "Zebrastreifen", kind: .bar), area: area), "'reifen' only matches at word start")
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "Reifen Müller", kind: .clothingStore), area: area))
        // Public art named after a cleaning company isn't a business — not filtered.
        XCTAssertTrue(PlaceValidator.isValid(Fixture.place(name: "Mural Reinigungsfirma Wall", kind: .mural), area: area))
    }

    func testSocialServicesAreNotCultureSpaces() {
        let area = Fixture.area()
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "Bahnhofsmission", kind: .socialCentre), area: area))
        XCTAssertFalse(PlaceValidator.isValid(Fixture.place(name: "Trierer Tafel e.V.", kind: .communityCentre), area: area))
        XCTAssertTrue(PlaceValidator.isValid(Fixture.place(name: "Tufa", kind: .communityCentre), area: area))
        XCTAssertTrue(PlaceValidator.isValid(Fixture.place(name: "KULTURSPEKTRUM", kind: .creativeHub), area: area))
    }

    func testSampleDataNeverPassesValidation() {
        var sample = Fixture.place(name: "Sample Place")
        sample.isSample = true
        XCTAssertFalse(PlaceValidator.isValid(sample, area: Fixture.area()))
    }

    func testSanitizeStripsHTMLAndUnsafeURLs() {
        var place = Fixture.place(name: "Shop")
        place.summary = "<p>Great <b>vintage</b> &amp; records</p>"
        place.website = URL(string: "javascript:alert(1)")
        place.images = [PlaceImage(url: URL(string: "http://insecure.example/a.jpg")!, pageURL: nil, attribution: nil,
                                   license: nil, provider: .openStreetMap, origin: .linked)]
        let clean = PlaceValidator.sanitize(place)
        XCTAssertEqual(clean.summary, "Great vintage & records")
        XCTAssertNil(clean.website)
        XCTAssertTrue(clean.images.isEmpty)
    }

    func testEventValidation() {
        let area = Fixture.area()
        let source = SourceRecord(provider: .venueWebsite, identifier: "x", url: nil, retrievedAt: now)
        let good = DiscoveryEvent(id: "e", title: "Skate Jam", kind: .skate, start: now.addingTimeInterval(86_400), end: nil,
                                  isAllDay: false, recurrence: nil, venueName: nil, venuePlaceID: nil,
                                  coordinate: Fixture.offset(north: 200), addressText: nil, url: nil, imageURL: nil,
                                  summary: nil, source: source, confidence: .verified, timeZoneIdentifier: nil)
        XCTAssertTrue(PlaceValidator.isValid(good, area: area, now: now))
        var past = good
        past.start = now.addingTimeInterval(-86_400 * 2)
        XCTAssertFalse(PlaceValidator.isValid(past, area: area, now: now), "expired events are never shown as upcoming")
        var noLocation = good
        noLocation.coordinate = nil
        XCTAssertFalse(PlaceValidator.isValid(noLocation, area: area, now: now))
        noLocation.addressText = "Somewhere Str. 1"
        XCTAssertTrue(PlaceValidator.isValid(noLocation, area: area, now: now))
        var outside = good
        outside.coordinate = Fixture.offset(north: 10_000)
        XCTAssertFalse(PlaceValidator.isValid(outside, area: area, now: now))
        var backwards = good
        backwards.end = good.start.addingTimeInterval(-60)
        XCTAssertFalse(PlaceValidator.isValid(backwards, area: area, now: now))
    }

    func testEngineAssemblesValidScoredDeduplicatedSnapshot() {
        let engine = DiscoveryEngine(sources: .init(), cache: DiscoveryCache(directory: nil))
        let a = Fixture.place(id: "osm:1", name: "Kilo Shop", kind: .thriftStore)
        let b = Fixture.place(id: "apple:1", name: "Kilo Shop", kind: .thriftStore, at: Fixture.offset(north: 20), provider: .appleMaps)
        let invalid = Fixture.place(id: "bad", name: "?", kind: .cafe)
        let snapshot = engine.assemble(places: [a, b, invalid], events: [], area: Fixture.area(), statuses: [:], now: now)
        XCTAssertEqual(snapshot.places.count, 1)
        XCTAssertNotNil(snapshot.places[0].score)
        XCTAssertEqual(snapshot.places[0].providers, [.openStreetMap, .appleMaps])
    }
}
