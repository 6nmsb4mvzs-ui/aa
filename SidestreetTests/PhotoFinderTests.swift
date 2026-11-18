import XCTest
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

final class PhotoFinderTests: XCTestCase {
    let page = URL(string: "https://bar.example/")!

    func testOpenGraphImageIsFoundInAnyAttributeOrder() {
        let html = """
        <html><head>
        <link rel="icon" href="/favicon.ico">
        <meta content="https://bar.example/img/interior.jpg" property="og:image" />
        <meta name="twitter:image" content="https://bar.example/img/other.jpg">
        </head><body></body></html>
        """
        XCTAssertEqual(WebPreviewImage.imageURL(in: html, pageURL: page)?.absoluteString, "https://bar.example/img/interior.jpg")
    }

    func testRelativeAndHttpImagesAreNormalisedAndIconsSkipped() {
        let relative = #"<meta property="og:image" content="/media/front.jpg">"#
        XCTAssertEqual(WebPreviewImage.imageURL(in: relative, pageURL: page)?.absoluteString, "https://bar.example/media/front.jpg")
        let http = #"<meta property='og:image' content='http://cdn.example/a.jpg'>"#
        XCTAssertEqual(WebPreviewImage.imageURL(in: http, pageURL: page)?.absoluteString, "https://cdn.example/a.jpg")
        let icon = #"<meta property="og:image" content="https://bar.example/favicon-196.png">"#
        XCTAssertNil(WebPreviewImage.imageURL(in: icon, pageURL: page))
        let avatar = #"<meta property="og:image" content="https://secure.gravatar.com/avatar/abc?s=512">"#
        XCTAssertNil(WebPreviewImage.imageURL(in: avatar, pageURL: page))
        let logoFolder = #"<meta property="og:image" content="https://hotel.example/assets/Images/Logos/glocke.png">"#
        XCTAssertNil(WebPreviewImage.imageURL(in: logoFolder, pageURL: page))
        let svg = #"<meta property="og:image" content="https://bar.example/logo.svg">"#
        XCTAssertNil(WebPreviewImage.imageURL(in: svg, pageURL: page))
        XCTAssertNil(WebPreviewImage.imageURL(in: "<html><head><title>x</title></head></html>", pageURL: page))
    }

    func testPanoramaxParsing() {
        let json = """
        {"type":"FeatureCollection","features":[{"id":"abc","type":"Feature",
          "assets":{"sd":{"href":"https://panoramax.example/derivates/abc/sd.jpg"},"thumb":{"href":"https://panoramax.example/derivates/abc/thumb.jpg"}},
          "providers":[{"name":"instance","roles":["producer"]},{"name":"jane","roles":["producer"]}],
          "properties":{"license":"CC-BY-SA-4.0","datetime":"2024-05-01T10:00:00Z"}}]}
        """
        let image = PanoramaxService.parse(Data(json.utf8))
        XCTAssertEqual(image?.url.absoluteString, "https://panoramax.example/derivates/abc/sd.jpg")
        XCTAssertEqual(image?.attribution, "jane / Panoramax")
        XCTAssertEqual(image?.license, "CC-BY-SA-4.0")
        XCTAssertEqual(image?.origin, .streetLevel)
        XCTAssertNil(PanoramaxService.parse(Data(#"{"features":[]}"#.utf8)))
    }

    func testFinderPrefersWebsiteThenStreetLevelAndCachesMisses() async {
        let client = MockHTTPClient { request in
            switch request.url.host {
            case "bar.example":
                if request.url.path == "/robots.txt" { return MockHTTPClient.status(404) }
                return MockHTTPClient.ok(#"<meta property="og:image" content="https://bar.example/room.jpg">"#,
                                         headers: ["Content-Type": "text/html"])
            case "api.panoramax.xyz":
                return MockHTTPClient.ok(#"{"features":[{"id":"p1","assets":{"sd":{"href":"https://pano.example/p1.jpg"}}}]}"#)
            default:
                return MockHTTPClient.status(404)
            }
        }
        let finder = PhotoFinder(client: client, cacheFile: nil)
        var bar = Fixture.place(id: "bar", name: "Ziegenbock.Bar", kind: .pub)
        bar.website = page
        let barImage = await finder.photo(for: bar, options: .init())
        XCTAssertEqual(barImage?.url.absoluteString, "https://bar.example/room.jpg")
        XCTAssertEqual(barImage?.provider, .venueWebsite)

        let shopWithoutSite = Fixture.place(id: "shop", name: "Sadri", kind: .thriftStore)
        let streetLevel = await finder.photo(for: shopWithoutSite, options: .init())
        XCTAssertEqual(streetLevel?.provider, .panoramax)

        let before = client.requests.count
        _ = await finder.photo(for: shopWithoutSite, options: .init())
        XCTAssertEqual(client.requests.count, before, "cached: no second lookup")

        var off = PhotoFinder.Options()
        off.streetLevel = false
        let nothing = await finder.photo(for: Fixture.place(id: "none", name: "Plain Shop", kind: .clothingStore), options: off)
        XCTAssertNil(nothing)
    }

    func testLinkedPhotoIsUsedWithoutAnyRequest() async {
        let client = MockHTTPClient { _ in MockHTTPClient.status(500) }
        var place = Fixture.place(name: "Tresor", kind: .nightclub)
        place.images = [PlaceImage(url: URL(string: "https://upload.wikimedia.org/x.jpg")!, pageURL: nil, attribution: nil,
                                   license: nil, provider: .wikimediaCommons, origin: .linked)]
        let image = await PhotoFinder(client: client, cacheFile: nil).photo(for: place, options: .init())
        XCTAssertEqual(image?.url.absoluteString, "https://upload.wikimedia.org/x.jpg")
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testLogosAreSkippedAndPagePhotoIsUsedAsFallback() {
        let html = """
        <meta property="og:image" content="https://shop.example/img/logo.png">
        <body><img src="/img/header-icon.jpg" width="40"><img src="/uploads/storefront.jpg" width="1200" height="800"></body>
        """
        XCTAssertEqual(WebPreviewImage.imageURL(in: html, pageURL: page)?.absoluteString, "https://bar.example/uploads/storefront.jpg")
    }

    func testJSONLDBusinessImage() {
        let html = #"<script type="application/ld+json">{"@type":"BarOrPub","name":"Bar","image":["https://bar.example/photos/bar.jpg"]}</script>"#
        XCTAssertEqual(WebPreviewImage.imageURL(in: html, pageURL: page)?.absoluteString, "https://bar.example/photos/bar.jpg")
    }

    func testMapillaryPicksPictureFacingThePlace() {
        let target = Fixture.berlin
        let south = GeoMath.destination(from: target, distance: 20, bearing: 180) // 20 m south of the place
        func candidate(_ id: String, at c: GeoCoordinate, heading: Double, pano: Bool = false) -> MapillaryService.Candidate {
            MapillaryService.Candidate(id: id, thumb_1024_url: "https://img.example/\(id).jpg", computed_compass_angle: heading,
                                       compass_angle: nil, computed_geometry: .init(coordinates: [c.longitude, c.latitude]),
                                       geometry: nil, captured_at: Date().timeIntervalSince1970 * 1000, is_pano: pano,
                                       creator: .init(username: "mapper"))
        }
        let facingAway = candidate("away", at: south, heading: 180)
        let facing = candidate("facing", at: south, heading: 5)
        let pano = candidate("pano", at: south, heading: 0, pano: true)
        let image = MapillaryService.best([facingAway, pano, facing], target: target)
        XCTAssertEqual(image?.url.absoluteString, "https://img.example/facing.jpg")
        XCTAssertEqual(image?.attribution, "mapper / Mapillary")
        XCTAssertNil(MapillaryService.best([facingAway], target: target), "a camera pointing away never counts")
    }

    func testPanoramaxTagBecomesLinkedPhoto() {
        let images = OSMPlaceBuilder.images(from: ["panoramax": "9cc38bf6-6a40-4adf-b2be-4447eb361202"])
        XCTAssertEqual(images.first?.url.absoluteString,
                       "https://api.panoramax.xyz/api/pictures/9cc38bf6-6a40-4adf-b2be-4447eb361202/sd.jpg")
        XCTAssertEqual(images.first?.origin, .linked)
    }
}
