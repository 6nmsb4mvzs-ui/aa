import XCTest
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

/// Realistic Overpass response (structure copied from the live API; values synthetic).
let overpassFixture = """
{
  "version": 0.6,
  "generator": "Overpass API",
  "elements": [
    {"type": "node", "id": 101, "lat": 52.4995, "lon": 13.4160,
     "tags": {"shop": "second_hand", "name": "Kilo Vintage Berlin", "clothes": "vintage;women;men",
              "opening_hours": "Mo-Sa 12:00-20:00", "addr:street": "Oranienstraße", "addr:housenumber": "12",
              "website": "kilovintage.example", "check_date": "2026-03-01"}},
    {"type": "way", "id": 202, "center": {"lat": 52.4980, "lon": 13.4150}, "nodes": [1,2,3],
     "tags": {"leisure": "skatepark", "name": "Bowl am Kanal", "diy": "yes"}},
    {"type": "node", "id": 303, "lat": 52.5001, "lon": 13.4170,
     "tags": {"tourism": "artwork", "artwork_type": "mural", "artist_name": "Blu"}},
    {"type": "node", "id": 404, "lat": 52.4990, "lon": 13.4140,
     "tags": {"shop": "clothes", "name": "H&M", "brand": "H&M", "brand:wikidata": "Q188326"}},
    {"type": "node", "id": 505, "lat": 52.4991, "lon": 13.4141,
     "tags": {"amenity": "cafe", "name": "Private Club Café", "access": "private"}},
    {"type": "node", "id": 606, "lat": 52.4992, "lon": 13.4142,
     "tags": {"amenity": "cafe"}},
    {"type": "way", "id": 707, "center": {"lat": 52.4970, "lon": 13.4180},
     "tags": {"building": "yes", "building:architecture": "brutalist", "name": "Wohnmaschine"}},
    {"type": "node", "id": 808, "lat": 52.4985, "lon": 13.4120,
     "tags": {"amenity": "marketplace", "name": "Flohmarkt am Maybachufer", "opening_hours": "Sa 10:00-16:00"}},
    {"type": "node", "id": 909, "lat": 52.6500, "lon": 13.4120,
     "tags": {"amenity": "cafe", "name": "Far Away Café"}},
    {"type": "node", "id": 1001, "lat": 52.4986, "lon": 13.4121,
     "tags": {"shop": "music", "name": "Hard Wax", "disused": "yes"}},
    {"type": "node", "id": 1101, "lat": 52.4987, "lon": 13.4122,
     "tags": {"amenity": "social_centre", "name": "Kollektiv Kiezraum", "operator:type": "community"}}
  ]
}
"""

final class OverpassParsingTests: XCTestCase {
    let now = Fixture.referenceDate

    func parsedPlaces() throws -> [String: Place] {
        let response = try JSONDecoder().decode(OverpassResponse.self, from: Data(overpassFixture.utf8))
        let places = OverpassProvider.places(from: response, area: Fixture.area(radius: 2_000), now: now)
        return Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    func testClassificationAndFields() throws {
        let places = try parsedPlaces()
        let vintage = try XCTUnwrap(places["osm:node/101"])
        XCTAssertEqual(vintage.kind, .vintageStore)
        XCTAssertEqual(vintage.address?.singleLine, "Oranienstraße 12")
        XCTAssertEqual(vintage.website?.absoluteString, "https://kilovintage.example")
        XCTAssertEqual(vintage.openingHoursRaw, "Mo-Sa 12:00-20:00")
        XCTAssertNotNil(vintage.signals.lastConfirmed)
        XCTAssertTrue(vintage.descriptors.contains("vintage"))
        XCTAssertEqual(vintage.price, .unknown, "vintage stores have no generic price estimate")

        XCTAssertEqual(places["osm:way/202"]?.kind, .diySkatepark)
        XCTAssertEqual(places["osm:way/707"]?.kind, .brutalistBuilding)
        XCTAssertEqual(places["osm:node/808"]?.kind, .fleaMarket)
        XCTAssertEqual(places["osm:node/1101"]?.kind, .socialCentre)
        XCTAssertEqual(places["osm:node/1101"]?.signals.communityOperated, true)

        let chain = try XCTUnwrap(places["osm:node/404"])
        XCTAssertEqual(chain.kind, .fashionChain)
        XCTAssertEqual(chain.brand?.wikidataID, "Q188326")
        XCTAssertEqual(chain.price, .estimated(.budget, reason: "high-street chain"))
    }

    func testUnnamedArtworkGetsLabelledInferredName() throws {
        let mural = try XCTUnwrap(try parsedPlaces()["osm:node/303"])
        XCTAssertEqual(mural.name, "Mural by Blu")
        XCTAssertTrue(mural.isNameInferred)
        XCTAssertEqual(mural.price, .estimated(.free, reason: "public space"))
    }

    func testRejectsPrivateDisusedUnnamedAndOutOfRadius() throws {
        let places = try parsedPlaces()
        XCTAssertNil(places["osm:node/505"], "private access is excluded")
        XCTAssertNil(places["osm:node/606"], "unnamed businesses are excluded")
        XCTAssertNil(places["osm:node/909"], "outside the radius")
        XCTAssertNil(places["osm:node/1001"], "disused places are excluded")
    }

    func testQueryContainsRadiusAndCentre() {
        let area = Fixture.area(radius: 3_000)
        let niche = OverpassQueryBuilder.query(.niche, area: area)
        XCTAssertTrue(niche.contains("(around:3000,52.499000,13.415500)"))
        XCTAssertTrue(niche.contains("[out:json]"))
        XCTAssertTrue(niche.contains("leisure\"=\"skatepark"))
        let everyday = OverpassQueryBuilder.query(.everyday, area: area)
        XCTAssertTrue(everyday.contains("[!\"brand\"]"), "chains are filtered server-side for dense categories")
        XCTAssertTrue(everyday.contains("out center 350"), "dense sets are capped")
    }

    func testClassifierEdgeCases() {
        XCTAssertEqual(OSMPlaceBuilder.classify(["shop": "clothes", "second_hand": "only"]), .thriftStore)
        XCTAssertEqual(OSMPlaceBuilder.classify(["shop": "clothes", "name": "Retro Kleidung"]), .vintageStore)
        XCTAssertEqual(OSMPlaceBuilder.classify(["shop": "sports", "sport": "skateboard"]), .skateShop)
        XCTAssertEqual(OSMPlaceBuilder.classify(["shop": "clothes", "name": "Sneaker Lab"]), .sneakerStore)
        XCTAssertEqual(OSMPlaceBuilder.classify(["shop": "clothes", "name": "Atelier Nord"]), .clothingStore)
        XCTAssertEqual(OSMPlaceBuilder.classify(["amenity": "marketplace", "name": "Marché aux Puces"]), .fleaMarket)
        XCTAssertEqual(OSMPlaceBuilder.classify(["amenity": "marketplace", "name": "Wochenmarkt"]), .market)
        XCTAssertEqual(OSMPlaceBuilder.classify(["amenity": "restaurant", "diet:vegan": "only"]), .veganRestaurant)
        XCTAssertEqual(OSMPlaceBuilder.classify(["amenity": "cinema", "name": "Kino Babylon"]), .independentCinema)
        XCTAssertEqual(OSMPlaceBuilder.classify(["amenity": "cinema", "brand": "CineStar"]), .cinema)
        XCTAssertEqual(OSMPlaceBuilder.classify(["tourism": "artwork", "artwork_type": "graffiti"]), .graffiti)
        XCTAssertEqual(OSMPlaceBuilder.classify(["natural": "water", "water": "pond", "name": "Teich"]), .pond)
        XCTAssertNil(OSMPlaceBuilder.classify(["shop": "supermarket"]))
        XCTAssertNil(OSMPlaceBuilder.classify(["shop": "sports", "name": "Decathlon"]))
    }

    func testExclusionRules() {
        XCTAssertTrue(OSMPlaceBuilder.isExcluded(["access": "private"]))
        XCTAssertTrue(OSMPlaceBuilder.isExcluded(["abandoned": "yes"]))
        XCTAssertTrue(OSMPlaceBuilder.isExcluded(["shop": "vacant"]))
        XCTAssertTrue(OSMPlaceBuilder.isExcluded(["opening_hours": "closed"]))
        XCTAssertTrue(OSMPlaceBuilder.isExcluded(["end_date": "2020-01-01"]))
        XCTAssertFalse(OSMPlaceBuilder.isExcluded(["access": "yes"]))
        XCTAssertFalse(OSMPlaceBuilder.isExcluded(["end_date": "2099-01-01"]))
    }

    func testImageTagsBecomeCommonsThumbnails() {
        let images = OSMPlaceBuilder.images(from: ["wikimedia_commons": "File:Tresor - Berlin.jpg"])
        XCTAssertEqual(images.first?.url.absoluteString,
                       "https://upload.wikimedia.org/wikipedia/commons/thumb/9/96/Tresor_-_Berlin.jpg/960px-Tresor_-_Berlin.jpg")
        XCTAssertEqual(images.first?.origin, .linked)
        XCTAssertTrue(OSMPlaceBuilder.images(from: ["image": "http://insecure.example/photo.jpg"]).isEmpty)
    }
}

final class WikimediaTests: XCTestCase {
    func testMD5MatchesKnownVectors() {
        XCTAssertEqual(MD5.hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(MD5.hex("The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
        XCTAssertEqual(MD5.hex(String(repeating: "a", count: 200)).count, 32)
    }

    func testThumbnailURLFromVariousForms() {
        let expected = "https://upload.wikimedia.org/wikipedia/commons/thumb/9/96/Tresor_-_Berlin.jpg/960px-Tresor_-_Berlin.jpg"
        XCTAssertEqual(WikimediaImageURL.thumbnail(fileName: "Tresor - Berlin.jpg")?.absoluteString, expected)
        XCTAssertEqual(WikimediaImageURL.thumbnail(fileName: "http://commons.wikimedia.org/wiki/Special:FilePath/Tresor%20-%20Berlin.jpg")?.absoluteString, expected)
        XCTAssertEqual(WikimediaImageURL.thumbnail(fileName: "https://commons.wikimedia.org/wiki/File:Tresor_-_Berlin.jpg")?.absoluteString, expected)
        XCTAssertNil(WikimediaImageURL.thumbnail(fileName: "Category:Murals in Berlin"))
        XCTAssertNil(WikimediaImageURL.thumbnail(fileName: "Document.pdf"))
        XCTAssertTrue(WikimediaImageURL.thumbnail(fileName: "Logo.svg")!.absoluteString.hasSuffix(".svg.png"))
    }

    func testWikidataResultsParsing() throws {
        let json = """
        {"head":{"vars":[]},"results":{"bindings":[
          {"item":{"type":"uri","value":"http://www.wikidata.org/entity/Q678186"},
           "itemLabel":{"type":"literal","value":"Tresor"},
           "itemDescription":{"type":"literal","value":"techno club in Berlin, Germany"},
           "coord":{"type":"literal","value":"Point(13.4185 52.5105)"},
           "image":{"type":"uri","value":"http://commons.wikimedia.org/wiki/Special:FilePath/Tresor%20-%20Berlin.jpg"},
           "sitelinks":{"type":"literal","value":"15"},
           "match":{"type":"uri","value":"http://www.wikidata.org/entity/Q622425"}},
          {"item":{"type":"uri","value":"http://www.wikidata.org/entity/Q47155387"},
           "itemLabel":{"type":"literal","value":"Kliems Festsäle"},
           "itemDescription":{"type":"literal","value":"former entertainment venue and cinema"},
           "coord":{"type":"literal","value":"Point(13.4213 52.4875)"},
           "sitelinks":{"type":"literal","value":"1"},
           "match":{"type":"uri","value":"http://www.wikidata.org/entity/Q8719053"}},
          {"item":{"type":"uri","value":"http://www.wikidata.org/entity/Q999"},
           "itemLabel":{"type":"literal","value":"Q999"},
           "coord":{"type":"literal","value":"Point(13.4213 52.4875)"},
           "sitelinks":{"type":"literal","value":"0"},
           "match":{"type":"uri","value":"http://www.wikidata.org/entity/Q219423"}}
        ]}}
        """
        let results = try JSONDecoder().decode(SPARQLResults.self, from: Data(json.utf8))
        let area = Fixture.area(center: GeoCoordinate(latitude: 52.50, longitude: 13.42), radius: 3_000)
        let places = WikidataProvider.places(from: results, area: area, now: Fixture.referenceDate)
        XCTAssertEqual(places.count, 1, "defunct venues and unlabeled items are dropped")
        let tresor = try XCTUnwrap(places.first)
        XCTAssertEqual(tresor.kind, .nightclub)
        XCTAssertEqual(tresor.signals.wikipediaSitelinks, 15)
        XCTAssertEqual(tresor.wikidataID, "Q678186")
        XCTAssertEqual(tresor.images.count, 1)
        XCTAssertEqual(tresor.summary, "Techno club in Berlin, Germany")
    }

    func testWikidataQueryUsesVerifiedEntityIDs() {
        let query = WikidataProvider.aroundQuery(Fixture.area(radius: 2_500), languages: "en")
        XCTAssertTrue(query.contains("wd:Q994776"), "brutalist architecture")
        XCTAssertTrue(query.contains("wd:Q909906"), "skatepark")
        XCTAssertTrue(query.contains("bd:serviceParam wikibase:radius \"2.50\""))
        XCTAssertTrue(query.contains("FILTER NOT EXISTS { ?item wdt:P576"), "demolished/dissolved items excluded")
    }

    func testCommonsParsing() throws {
        let json = """
        {"batchcomplete":true,"query":{"pages":[
          {"pageid":1,"ns":6,"title":"File:A.jpg","index":1,"imageinfo":[{"thumburl":"https://upload.wikimedia.org/a/960px-A.jpg",
            "descriptionurl":"https://commons.wikimedia.org/wiki/File:A.jpg","mime":"image/jpeg",
            "extmetadata":{"Artist":{"value":"<a href=\\"x\\">Jane &amp; Co</a>"},"LicenseShortName":{"value":"CC BY-SA 4.0"}}}]},
          {"pageid":2,"ns":6,"title":"File:B.pdf","index":0,"imageinfo":[{"thumburl":"https://upload.wikimedia.org/b.jpg","mime":"application/pdf"}]}
        ]}}
        """
        let images = try CommonsPhotoService.parse(Data(json.utf8))
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].attribution, "Jane & Co / Wikimedia Commons")
        XCTAssertEqual(images[0].license, "CC BY-SA 4.0")
        XCTAssertEqual(images[0].origin, .nearby)
    }

    func testWikipediaSummaryRequestAndParsing() throws {
        let request = WikipediaSummaryService.request(reference: "de:Tresor (Club)")
        XCTAssertEqual(request?.url.absoluteString, "https://de.wikipedia.org/api/rest_v1/page/summary/Tresor_(Club)")
        let json = """
        {"type":"standard","title":"Tresor","extract":"Tresor is a techno club.","content_urls":{"mobile":{"page":"https://en.m.wikipedia.org/wiki/Tresor"}}}
        """
        let summary = try XCTUnwrap(try WikipediaSummaryService.parse(Data(json.utf8)))
        XCTAssertEqual(summary.extract, "Tresor is a techno club.")
        let disambiguation = #"{"type":"disambiguation","title":"X","extract":"X may refer to"}"#
        XCTAssertNil(try WikipediaSummaryService.parse(Data(disambiguation.utf8)))
    }
}

final class APIFailureTests: XCTestCase {
    let now = Fixture.referenceDate

    func testOverpassFailsOverToSecondEndpoint() async throws {
        let client = MockHTTPClient { request in
            if request.url.host == "overpass-api.de" { return MockHTTPClient.status(504) }
            return MockHTTPClient.ok(overpassFixture)
        }
        let provider = OverpassProvider(client: client)
        let places = try await provider.fetch(.niche, area: Fixture.area(), now: now)
        XCTAssertFalse(places.isEmpty)
        XCTAssertEqual(client.requests.map { $0.url.host }, ["overpass-api.de", "overpass.private.coffee"])
        XCTAssertTrue(client.requests[0].decodedFormBody.hasPrefix("data=[out:json]"))
    }

    func testOverpassRateLimitOnAllEndpointsThrows() async {
        let client = MockHTTPClient { _ in MockHTTPClient.status(429, headers: ["Retry-After": "30"]) }
        do {
            _ = try await OverpassProvider(client: client).fetch(.niche, area: Fixture.area(), now: now)
            XCTFail("expected error")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 30))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testOverpassHTMLErrorPageIsADecodingFailure() async {
        let client = MockHTTPClient { _ in MockHTTPClient.ok("<html><body>runtime error: Query timed out</body></html>") }
        do {
            _ = try await OverpassProvider(client: client).fetch(.niche, area: Fixture.area(), now: now)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .decoding("Overpass"))
            XCTAssertEqual(client.requests.count, 2, "tried the fallback endpoint too")
        }
    }

    func testNonTransientErrorDoesNotRetry() async {
        let client = MockHTTPClient { _ in MockHTTPClient.status(400) }
        do {
            _ = try await OverpassProvider(client: client).fetch(.niche, area: Fixture.area(), now: now)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? NetworkError, .httpStatus(400))
            XCTAssertEqual(client.requests.count, 1)
        }
    }

    func testEngineDegradesGracefullyWhenSourcesFail() async {
        let client = MockHTTPClient { request in
            if request.url.host == "query.wikidata.org" { throw NetworkError.offline }
            if request.bodyString.contains("cafes") { return MockHTTPClient.status(503) }
            return MockHTTPClient.ok(overpassFixture)
        }
        let engine = DiscoveryEngine(
            sources: .init(overpass: OverpassProvider(client: client), wikidata: WikidataProvider(client: client)),
            cache: DiscoveryCache(directory: nil),
            clock: { Fixture.referenceDate }
        )
        var updates: [DiscoveryUpdate] = []
        for await update in engine.discover(area: Fixture.area()) { updates.append(update) }
        let final = try! XCTUnwrap(updates.last)
        XCTAssertEqual(final.phase, .complete)
        XCTAssertFalse(final.snapshot.places.isEmpty, "OSM niche results still arrive")
        XCTAssertEqual(final.snapshot.sourceStatuses[.wikidata], .failed(message: NetworkError.offline.errorDescription!))
        if case .loaded? = final.snapshot.sourceStatuses[.openStreetMap] {} else {
            XCTFail("OSM should report loaded despite the everyday query failing")
        }
        XCTAssertTrue(updates.contains { $0.phase == .initial && !$0.snapshot.places.isEmpty }, "progressive first results")
    }

    func testEngineReportsTotalFailure() async {
        let client = MockHTTPClient { _ in throw NetworkError.offline }
        let engine = DiscoveryEngine(sources: .init(overpass: OverpassProvider(client: client)),
                                     cache: DiscoveryCache(directory: nil), clock: { Fixture.referenceDate })
        var last: DiscoveryUpdate?
        for await update in engine.discover(area: Fixture.area()) { last = update }
        XCTAssertEqual(last?.snapshot.places.count, 0)
        XCTAssertEqual(last?.snapshot.sourceStatuses[.openStreetMap]?.isFailure, true)
    }

    func testYouTubeQuotaAndKeyErrors() async {
        let quota = """
        {"error":{"code":403,"message":"quota","errors":[{"reason":"quotaExceeded"}]}}
        """
        let service = YouTubeService(client: MockHTTPClient { _ in MockHTTPClient.status(403, body: quota) }, apiKey: "k", bundleIdentifier: "app")
        do {
            _ = try await service.search("x")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? YouTubeService.ServiceError, .quotaExceeded)
        }
        let invalid = #"{"error":{"code":400,"message":"API key not valid","errors":[{"reason":"badRequest"}]}}"#
        let badKey = YouTubeService(client: MockHTTPClient { _ in MockHTTPClient.status(400, body: invalid) }, apiKey: "k", bundleIdentifier: nil)
        do {
            _ = try await badKey.search("x")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? YouTubeService.ServiceError, .invalidKey)
        }
        let noKey = YouTubeService(client: MockHTTPClient { _ in MockHTTPClient.ok("{}") }, apiKey: "", bundleIdentifier: nil)
        do {
            _ = try await noKey.search("x")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? NetworkError, .notConfigured("YouTube API key"))
        }
    }

    func testYouTubeParsingAndMentions() throws {
        let json = """
        {"items":[
          {"id":{"kind":"youtube#video","videoId":"abc"},"snippet":{"title":"Kilo Vintage Berlin haul &amp; tour","channelTitle":"Thrift Diaries","publishedAt":"2026-05-01T10:00:00Z","thumbnails":{"high":{"url":"https://i.ytimg.com/vi/abc/hqdefault.jpg"}}}},
          {"id":{"kind":"youtube#channel","channelId":"c"},"snippet":{"title":"Channel","channelTitle":"C"}}
        ]}
        """
        let videos = try YouTubeService.parse(Data(json.utf8))
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].title, "Kilo Vintage Berlin haul & tour")
        XCTAssertEqual(YouTubeService.mentionCount(of: "Kilo Vintage", in: videos), 1)
        XCTAssertEqual(YouTubeService.mentionCount(of: "Bar", in: videos), 0, "generic names are not counted")
    }
}
