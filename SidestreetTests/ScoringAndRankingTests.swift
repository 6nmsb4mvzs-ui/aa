import XCTest
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

final class NicheScorerTests: XCTestCase {
    let now = Fixture.referenceDate
    var scorer: NicheScorer { NicheScorer(now: now) }

    func score(_ places: [Place]) -> [String: Place] {
        Dictionary(uniqueKeysWithValues: scorer.score(places).map { ($0.id, $0) })
    }

    func testIndependentVintageStoreBeatsGlobalChain() {
        let vintage = Fixture.place(id: "vintage", name: "Kilo Fripe Vintage", kind: .vintageStore)
        let chain = Fixture.place(id: "chain", name: "H&M", kind: .fashionChain,
                                  brand: BrandInfo(name: "H&M", wikidataID: "Q188326"))
        let scored = score([vintage, chain])
        XCTAssertGreaterThan(scored["vintage"]!.score!.value, scored["chain"]!.score!.value + 0.25)
        let independence = scored["chain"]!.score!.components.first { $0.kind == .independence }!
        XCTAssertLessThan(independence.value, 0.1)
    }

    func testFamousLandmarkScoresLowerOnObscurity() {
        let famous = Fixture.place(id: "famous", name: "Famous Tower", kind: .observationTower, sitelinks: 80)
        let hidden = Fixture.place(id: "hidden", name: "Quiet Tower", kind: .observationTower)
        let scored = score([famous, hidden])
        let obscurity = { (p: Place) in p.score!.components.first { $0.kind == .obscurity }!.value }
        XCTAssertLessThan(obscurity(scored["famous"]!), 0.05)
        XCTAssertEqual(obscurity(scored["hidden"]!), 1.0)
        XCTAssertGreaterThan(scored["hidden"]!.score!.value, scored["famous"]!.score!.value)
    }

    func testRepeatedNameInAreaReducesIndependence() {
        let branches = (0..<4).map { i in
            Fixture.place(id: "b\(i)", name: "Bean Republic", kind: .cafe, at: Fixture.offset(north: Double(i) * 500))
        }
        let solo = Fixture.place(id: "solo", name: "Café Unikat", kind: .cafe, at: Fixture.offset(east: 300))
        let scored = score(branches + [solo])
        let independence = { (p: Place) in p.score!.components.first { $0.kind == .independence }!.value }
        XCTAssertLessThan(independence(scored["b0"]!), 0.3)
        XCTAssertGreaterThan(independence(scored["solo"]!), 0.8)
    }

    func testLowConfidenceObscurePlaceDoesNotOutrankDocumentedGem() {
        // Same type and obscurity; one has rich, recently checked data from two sources.
        var documented = Fixture.place(id: "doc", name: "Second Life Thrift", kind: .thriftStore, tagRichness: 1.0,
                                       lastConfirmed: now.addingTimeInterval(-30 * 24 * 3600))
        documented.sources.append(SourceRecord(provider: .appleMaps, identifier: "x", url: nil, retrievedAt: now))
        documented.openingHoursRaw = "Mo-Sa 11:00-19:00"
        documented.address = PostalAddress(street: "Teststraße", houseNumber: "1", postcode: nil, city: nil, district: nil, country: nil, formatted: nil)
        let sketchy = Fixture.place(id: "sketchy", name: "Graffiti Wall", kind: .graffiti, tagRichness: 0.0, inferredName: true)
        let scored = score([documented, sketchy])
        XCTAssertGreaterThan(scored["doc"]!.score!.confidence, scored["sketchy"]!.score!.confidence)
        XCTAssertEqual(scored["doc"]!.confidence, .verified)
        XCTAssertEqual(scored["sketchy"]!.confidence, .uncertain)
        // The sketchy one has a niche-er type but must be damped by low confidence.
        XCTAssertLessThan(scored["sketchy"]!.score!.value, scored["sketchy"]!.score!.rawValue)
    }

    func testScoresAreNormalisedAndWeightsSumToOne() {
        let places = PlaceKind.allCases.enumerated().map { i, kind in
            Fixture.place(id: "k\(i)", name: "Place \(i)", kind: kind, at: Fixture.offset(north: Double(i) * 20))
        }
        for place in scorer.score(places) {
            let score = place.score!
            XCTAssertTrue((0...1).contains(score.value), "\(place.kind) out of range")
            XCTAssertTrue((0...1).contains(score.confidence))
            XCTAssertEqual(score.components.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.0001)
            for c in score.components { XCTAssertTrue((0...1).contains(c.value), "\(c.kind) out of range") }
        }
    }

    func testSocialSignalOnlyCountsWhenAvailable() {
        var place = Fixture.place(id: "a", name: "Record Bunker", kind: .recordStore)
        XCTAssertFalse(scorer.score([place])[0].score!.components.contains { $0.kind == .socialSignal })
        place.signals.socialMentions = 3
        let withSocial = scorer.score([place])[0].score!
        XCTAssertEqual(withSocial.components.first { $0.kind == .socialSignal }?.value, 0.9)
    }

    func testBusinessKnownOnlyFromWikidataStaysUnverified() {
        // Wikidata often lacks closure dates for clubs that shut years ago.
        let wikidataOnly = Fixture.place(id: "wd:Q1", name: "Old Club", kind: .nightclub, provider: .wikidata, sitelinks: 3)
        var confirmed = wikidataOnly
        confirmed.id = "wd:Q2"
        confirmed.sources.append(SourceRecord(provider: .openStreetMap, identifier: "node/1", url: nil, retrievedAt: now))
        let scored = score([wikidataOnly, confirmed])
        XCTAssertEqual(scored["wd:Q1"]!.confidence, .uncertain)
        XCTAssertGreaterThan(scored["wd:Q2"]!.score!.value, scored["wd:Q1"]!.score!.value)
        // Public art from Wikidata alone is fine.
        let mural = Fixture.place(id: "wd:Q3", name: "Big Mural", kind: .mural, provider: .wikidata)
        XCTAssertNotEqual(scorer.score([mural])[0].confidence, .uncertain)
    }

    func testCommunitySpaceGetsCommunityCredit() {
        var squat = Fixture.place(id: "s", name: "Kollektiv Raum", kind: .socialCentre)
        squat.signals.communityOperated = true
        let result = scorer.score([squat])[0].score!
        XCTAssertEqual(result.components.first { $0.kind == .community }?.value, 1.0)
        XCTAssertEqual(result.components.first { $0.kind == .independence }?.value, 1.0)
    }
}

final class DeduplicatorTests: XCTestCase {
    func testMergesSamePlaceFromDifferentSources() {
        let osm = Fixture.place(id: "osm:node/1", name: "Café Botanico", kind: .cafe, provider: .openStreetMap)
        let apple = Fixture.place(id: "apple:1", name: "Cafe Botanico", kind: .cafe,
                                  at: Fixture.offset(north: 25), provider: .appleMaps)
        let merged = Deduplicator.merge([osm, apple])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(Set(merged[0].providers), [.openStreetMap, .appleMaps])
        XCTAssertEqual(merged[0].id, "osm:node/1", "OSM record is the base for structured data")
    }

    func testDoesNotMergeDifferentShopsInSameBuilding() {
        let a = Fixture.place(id: "a", name: "Vinyl Vault", kind: .recordStore, provider: .openStreetMap)
        let b = Fixture.place(id: "b", name: "Ink & Needle Tattoo", kind: .tattooStudio,
                              at: Fixture.offset(north: 5), provider: .appleMaps)
        XCTAssertEqual(Deduplicator.merge([a, b]).count, 2)
    }

    func testDoesNotMergeChainBranchesFarApart() {
        let a = Fixture.place(id: "a", name: "Humana Second Hand", kind: .thriftStore, provider: .openStreetMap)
        let b = Fixture.place(id: "b", name: "Humana Second Hand", kind: .thriftStore,
                              at: Fixture.offset(north: 600), provider: .appleMaps)
        XCTAssertEqual(Deduplicator.merge([a, b]).count, 2)
    }

    func testMergesByWikidataIDRegardlessOfName() {
        let osm = Fixture.place(id: "osm:way/9", name: "Tresor Club", kind: .nightclub, wikidataID: "Q678186")
        let wd = Fixture.place(id: "wd:Q678186", name: "Tresor", kind: .nightclub, at: Fixture.offset(north: 90),
                               provider: .wikidata, wikidataID: "Q678186", sitelinks: 15)
        let merged = Deduplicator.merge([osm, wd])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].signals.wikipediaSitelinks, 15)
    }

    func testDifferentWikidataIDsNeverMerge() {
        let a = Fixture.place(id: "a", name: "Water Tower", kind: .waterTower, wikidataID: "Q1")
        let b = Fixture.place(id: "b", name: "Water Tower", kind: .waterTower, at: Fixture.offset(north: 10),
                              provider: .wikidata, wikidataID: "Q2")
        XCTAssertEqual(Deduplicator.merge([a, b]).count, 2)
    }

    func testInferredNamesNeverMergeByName() {
        let a = Fixture.place(id: "a", name: "Untitled mural", kind: .mural, inferredName: true)
        let b = Fixture.place(id: "b", name: "Untitled mural", kind: .mural, at: Fixture.offset(north: 15),
                              provider: .wikidata, inferredName: true)
        XCTAssertEqual(Deduplicator.merge([a, b]).count, 2)
    }

    func testSameProviderRequiresNearIdenticalName() {
        // Node + building way of the same shop in OSM.
        let node = Fixture.place(id: "osm:node/5", name: "Mauerpark Flohmarkt", kind: .fleaMarket)
        let way = Fixture.place(id: "osm:way/6", name: "Mauerpark Flohmarkt", kind: .fleaMarket, at: Fixture.offset(north: 20))
        XCTAssertEqual(Deduplicator.merge([node, way]).count, 1)
        let other = Fixture.place(id: "osm:node/7", name: "Mauerpark Café", kind: .cafe, at: Fixture.offset(north: 15))
        XCTAssertEqual(Deduplicator.merge([node, other]).count, 2)
    }

    func testMergeCombinesFieldsAndImages() {
        var osm = Fixture.place(id: "osm:node/1", name: "Kino Moviemento", kind: .independentCinema)
        osm.openingHoursRaw = "Mo-Su 14:00-23:00"
        var wd = Fixture.place(id: "wd:Q5", name: "Moviemento", kind: .independentCinema, at: Fixture.offset(north: 30),
                               provider: .wikidata, wikidataID: "Q5")
        wd.summary = "Oldest cinema in Berlin"
        wd.images = [PlaceImage(url: URL(string: "https://upload.wikimedia.org/x.jpg")!, pageURL: nil, attribution: nil,
                                license: nil, provider: .wikimediaCommons, origin: .linked)]
        let merged = Deduplicator.merge([osm, wd])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].openingHoursRaw, "Mo-Su 14:00-23:00")
        XCTAssertEqual(merged[0].summary, "Oldest cinema in Berlin")
        XCTAssertEqual(merged[0].images.count, 1)
        XCTAssertEqual(merged[0].wikidataID, "Q5")
    }

    func testNameSimilarity() {
        XCTAssertEqual(TextMatching.nameSimilarity("Café Botanico", "Cafe Botanico"), 1, accuracy: 0.001)
        XCTAssertGreaterThan(TextMatching.nameSimilarity("The Record Loft", "Record Loft"), 0.9)
        XCTAssertLessThan(TextMatching.nameSimilarity("Vinyl Vault", "Ink & Needle"), 0.6)
        XCTAssertGreaterThan(TextMatching.nameSimilarity("Kaffee Burger", "Kaffee Burger Bar Berlin"), 0.85)
    }
}

final class CategoryFilterTests: XCTestCase {
    func testEmptyFilterShowsEverything() {
        let filter = CategoryFilter()
        XCTAssertTrue(filter.matches(Fixture.place(kind: .cafe)))
        XCTAssertTrue(filter.matches(Fixture.place(kind: .graffiti)))
    }

    func testSingleAndCombinedFilters() {
        var filter = CategoryFilter()
        filter.toggle(.skate)
        XCTAssertTrue(filter.matches(Fixture.place(kind: .skatepark)))
        XCTAssertTrue(filter.matches(Fixture.place(kind: .skateShop)), "skate shops are in skate and fashion")
        XCTAssertFalse(filter.matches(Fixture.place(kind: .cafe)))
        filter.toggle(.cafes)
        XCTAssertTrue(filter.matches(Fixture.place(kind: .cafe)))
        filter.toggle(.skate)
        XCTAssertFalse(filter.matches(Fixture.place(kind: .skatepark)))
    }

    func testSecondaryCategoriesMatch() {
        var filter = CategoryFilter()
        filter.toggle(.photo)
        XCTAssertTrue(filter.matches(Fixture.place(kind: .mural)), "murals are photo spots too")
        XCTAssertTrue(filter.matches(Fixture.place(kind: .brutalistBuilding)))
        XCTAssertFalse(filter.matches(Fixture.place(kind: .thriftStore)))
    }

    func testRelevanceWeighting() {
        var filter = CategoryFilter()
        filter.toggle(.photo)
        XCTAssertEqual(filter.relevance(of: Fixture.place(kind: .mural)), 0.7)
        filter.toggle(.streetArt)
        XCTAssertEqual(filter.relevance(of: Fixture.place(kind: .mural)), 1.0)
    }

    func testEventFiltering() {
        let event = DiscoveryEvent(id: "e", title: "Flea", kind: .fleaMarket, start: Fixture.referenceDate, end: nil,
                                   isAllDay: false, recurrence: nil, venueName: nil, venuePlaceID: nil,
                                   coordinate: Fixture.berlin, addressText: nil, url: nil, imageURL: nil, summary: nil,
                                   source: SourceRecord(provider: .openStreetMap, identifier: "x", url: nil, retrievedAt: Fixture.referenceDate),
                                   confidence: .partial, timeZoneIdentifier: nil)
        var filter = CategoryFilter()
        filter.toggle(.events)
        XCTAssertTrue(filter.matches(event))
        filter = CategoryFilter(selected: [.fashion])
        XCTAssertTrue(filter.matches(event), "flea markets show under fashion")
        filter = CategoryFilter(selected: [.food])
        XCTAssertFalse(filter.matches(event))
    }
}

final class FeedRankerTests: XCTestCase {
    let now = Fixture.referenceDate

    func scored(_ places: [Place]) -> [Place] { NicheScorer(now: now).score(places) }

    func testNicheBeatsMainstreamAtEqualDistance() {
        let places = scored([
            Fixture.place(id: "chain", name: "Zara", kind: .fashionChain, at: Fixture.offset(north: 200),
                          brand: BrandInfo(name: "Zara", wikidataID: "Q147662")),
            Fixture.place(id: "diy", name: "Beton Bowl DIY", kind: .diySkatepark, at: Fixture.offset(north: 200)),
        ])
        let feed = FeedRanker().rank(places: places, events: [], area: Fixture.area(), filter: CategoryFilter(), now: now)
        XCTAssertEqual(feed.first?.id, "p:diy")
    }

    func testDistanceMattersForEqualPlaces() {
        let places = scored([
            Fixture.place(id: "far", name: "Far Vintage", kind: .vintageStore, at: Fixture.offset(north: 1_900)),
            Fixture.place(id: "near", name: "Near Vintage", kind: .vintageStore, at: Fixture.offset(north: 100)),
        ])
        let feed = FeedRanker().rank(places: places, events: [], area: Fixture.area(), filter: CategoryFilter(), now: now)
        XCTAssertEqual(feed.map(\.id), ["p:near", "p:far"])
    }

    func testExcludesPlacesOutsideRadius() {
        let places = scored([Fixture.place(id: "out", name: "Outside", kind: .vintageStore, at: Fixture.offset(north: 2_500))])
        XCTAssertTrue(FeedRanker().rank(places: places, events: [], area: Fixture.area(radius: 2_000),
                                        filter: CategoryFilter(), now: now).isEmpty)
    }

    func testVarietyAvoidsLongRunsOfSameCategory() {
        var places: [Place] = []
        for i in 0..<8 {
            places.append(Fixture.place(id: "cafe\(i)", name: "Café \(i)", kind: .cafe, at: Fixture.offset(north: Double(i) * 50 + 10)))
        }
        for i in 0..<4 {
            places.append(Fixture.place(id: "art\(i)", name: "Mural \(i)", kind: .mural, at: Fixture.offset(east: Double(i) * 400 + 600)))
        }
        let feed = FeedRanker().rank(places: scored(places), events: [], area: Fixture.area(), filter: CategoryFilter(), now: now)
        XCTAssertEqual(feed.count, 12)
        // While both categories are available (first 8 cards: 4 murals + 4 cafés),
        // the ranker must interleave them. Once murals run out, cafés necessarily follow.
        let head = Array(feed.prefix(8))
        var longestRun = 1, run = 1
        for i in 1..<head.count {
            run = head[i].primaryCategory == head[i - 1].primaryCategory ? run + 1 : 1
            longestRun = max(longestRun, run)
        }
        XCTAssertLessThanOrEqual(longestRun, 2, "feed should interleave categories: \(head.map(\.id))")
        XCTAssertEqual(head.filter { $0.primaryCategory == .streetArt }.count, 4)
    }

    func testFilterRestrictsFeed() {
        let places = scored([
            Fixture.place(id: "cafe", name: "Café", kind: .cafe),
            Fixture.place(id: "skate", name: "Park", kind: .skatepark, at: Fixture.offset(north: 300)),
        ])
        let feed = FeedRanker().rank(places: places, events: [], area: Fixture.area(),
                                     filter: CategoryFilter(selected: [.skate]), now: now)
        XCTAssertEqual(feed.map(\.id), ["p:skate"])
    }

    func testEventsAppearInFeedAndExpiredOnesDoNot() {
        let source = SourceRecord(provider: .venueWebsite, identifier: "x", url: nil, retrievedAt: now)
        let upcoming = DiscoveryEvent(id: "soon", title: "Vintage Fair", kind: .fleaMarket, start: now.addingTimeInterval(3_600 * 20),
                                      end: nil, isAllDay: false, recurrence: nil, venueName: nil, venuePlaceID: nil,
                                      coordinate: Fixture.offset(north: 300), addressText: nil, url: nil, imageURL: nil,
                                      summary: nil, source: source, confidence: .verified, timeZoneIdentifier: nil)
        var expired = upcoming
        expired.id = "past"
        expired.start = now.addingTimeInterval(-3_600 * 30)
        expired.end = now.addingTimeInterval(-3_600 * 26)
        let feed = FeedRanker().rank(places: scored([Fixture.place(id: "p", name: "Shop", kind: .thriftStore)]),
                                     events: [upcoming, expired], area: Fixture.area(), filter: CategoryFilter(), now: now)
        XCTAssertTrue(feed.contains { $0.id == "e:soon" })
        XCTAssertFalse(feed.contains { $0.id == "e:past" })
    }

    func testRankingIsDeterministic() {
        let places = scored((0..<30).map { i in
            Fixture.place(id: "p\(i)", name: "Place \(i)", kind: PlaceKind.allCases[i % PlaceKind.allCases.count],
                          at: Fixture.offset(north: Double(i * 37 % 1_900)))
        })
        let a = FeedRanker().rank(places: places, events: [], area: Fixture.area(), filter: CategoryFilter(), now: now)
        let b = FeedRanker().rank(places: places.reversed(), events: [], area: Fixture.area(), filter: CategoryFilter(), now: now)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }
}
