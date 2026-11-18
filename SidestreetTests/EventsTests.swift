import XCTest
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

final class JSONLDEventTests: XCTestCase {
    let now = Fixture.referenceDate
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let page = URL(string: "https://venue.example/")!

    let html = """
    <html><head>
    <script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[
      {"@type":"MusicEvent","name":"Dub Techno Night","startDate":"2026-11-20T23:00:00+01:00",
       "endDate":"2026-11-21T06:00:00+01:00","url":"/events/dub",
       "location":{"@type":"Place","name":"Venue","address":{"@type":"PostalAddress","streetAddress":"Köpenicker Str. 70","addressLocality":"Berlin"}}},
      {"@type":"Event","name":"Cancelled Show","startDate":"2026-11-25T20:00","eventStatus":"https://schema.org/EventCancelled"},
      {"@type":"Event","name":"Last Year Party","startDate":"2025-11-25T20:00"},
      {"@type":"ExhibitionEvent","name":"Zine Fair &amp; Print Market","startDate":"2026-11-28","endDate":"2026-11-29",
       "location":{"@type":"Place","name":"Elsewhere Hall","geo":{"latitude":52.5,"longitude":13.42}}},
      {"@type":"Event","name":"Online Talk","startDate":"2026-11-30T19:00","location":{"@type":"VirtualLocation","url":"https://x"}},
      {"@type":"Organization","name":"Not an event"}
    ]}
    </script>
    <script type="application/ld+json">[{"@type":"Event","name":"Bad date","startDate":"soon"}]</script>
    </head></html>
    """

    func testExtractsOnlyValidUpcomingEvents() {
        let events = JSONLDEventExtractor.extract(html: html, pageURL: page, timeZone: berlin, now: now)
        XCTAssertEqual(events.map(\.name), ["Dub Techno Night", "Zine Fair & Print Market"])
        XCTAssertEqual(events[0].start, Fixture.date("2026-11-20 23:00"))
        XCTAssertEqual(events[0].url?.absoluteString, "https://venue.example/events/dub")
        XCTAssertEqual(events[0].addressText, "Köpenicker Str. 70, Berlin")
        XCTAssertTrue(events[1].isAllDay)
        XCTAssertEqual(events[1].coordinate, GeoCoordinate(latitude: 52.5, longitude: 13.42))
    }

    func testLocalTimesUseVenueTimeZone() {
        let (date, allDay) = JSONLDEventExtractor.parseDate("2026-11-21T20:00", timeZone: TimeZone(identifier: "Asia/Tokyo")!)!
        XCTAssertFalse(allDay)
        XCTAssertEqual(date, Fixture.date("2026-11-21 20:00", timeZone: "Asia/Tokyo"))
        XCTAssertNil(JSONLDEventExtractor.parseDate("21.11.2026", timeZone: berlin))
        XCTAssertNil(JSONLDEventExtractor.parseDate("2026-13-01", timeZone: berlin))
    }

    func testEventRequiresConfirmedLocation() {
        var venue = Fixture.place(id: "osm:node/1", name: "Venue", kind: .musicVenue)
        venue.website = page
        let extracted = JSONLDEventExtractor.extract(html: html, pageURL: page, timeZone: berlin, now: now)
        let area = Fixture.area(radius: 3_000)
        let atVenue = VenueEventsProvider.makeEvent(extracted[0], venue: venue, area: area, now: now)
        XCTAssertEqual(atVenue?.venuePlaceID, "osm:node/1", "event names the venue → placed at the venue")
        XCTAssertEqual(atVenue?.coordinate, venue.coordinate)
        XCTAssertEqual(atVenue?.kind, .music)

        let elsewhere = VenueEventsProvider.makeEvent(extracted[1], venue: venue, area: area, now: now)
        XCTAssertEqual(elsewhere?.coordinate, GeoCoordinate(latitude: 52.5, longitude: 13.42))
        XCTAssertNil(elsewhere?.venuePlaceID)

        var noLocation = extracted[1]
        noLocation.coordinate = nil
        noLocation.addressText = nil
        noLocation.locationName = "Some Other Club"
        XCTAssertNil(VenueEventsProvider.makeEvent(noLocation, venue: venue, area: area, now: now),
                     "events at an unknown other location are rejected")
    }

    func testEventsPageLinkDetection() {
        let page = #"<nav><a href="/about">About</a><a class="x" href="/programm/">Programm</a></nav>"#
        XCTAssertEqual(VenueEventsProvider.eventsPageLink(in: page, base: URL(string: "https://club.example/")!)?.absoluteString,
                       "https://club.example/programm/")
    }

    func testVenueEventsRespectRobotsTxt() async throws {
        var venue = Fixture.place(id: "v", name: "Venue", kind: .musicVenue)
        venue.website = URL(string: "https://blocked.example/")!
        let html = self.html
        let client = MockHTTPClient { request in
            if request.url.path == "/robots.txt" { return MockHTTPClient.ok("User-agent: *\nDisallow: /") }
            return MockHTTPClient.ok(html, headers: ["Content-Type": "text/html"])
        }
        let provider = VenueEventsProvider(client: client)
        let events = await provider.events(for: [venue], area: Fixture.area(radius: 3_000), now: now)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(client.requests.map(\.url.path), ["/robots.txt"], "page is never fetched when disallowed")
    }

    func testVenueEventsFetchWhenAllowed() async {
        var venue = Fixture.place(id: "v", name: "Venue", kind: .musicVenue)
        venue.website = URL(string: "https://open.example/")!
        let html = self.html
        let client = MockHTTPClient { request in
            if request.url.path == "/robots.txt" { return MockHTTPClient.status(404) }
            return MockHTTPClient.ok(html, headers: ["Content-Type": "text/html; charset=utf-8"])
        }
        let events = await VenueEventsProvider(client: client).events(for: [venue], area: Fixture.area(radius: 3_000), now: now)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.source.provider == .venueWebsite })
    }

    func testRecurringMarketEventsUseVerifiedSchedule() {
        var market = Fixture.place(id: "m", name: "Flohmarkt am Kanal", kind: .fleaMarket)
        market.openingHoursRaw = "Sa 10:00-16:00"
        var daily = Fixture.place(id: "d", name: "Daily Market", kind: .market)
        daily.openingHoursRaw = "Mo-Su 08:00-20:00"
        var unparseable = Fixture.place(id: "u", name: "Sometimes Market", kind: .fleaMarket)
        unparseable.openingHoursRaw = "irregular, see website"
        var shop = Fixture.place(id: "s", name: "Shop", kind: .thriftStore)
        shop.openingHoursRaw = "Sa 10:00-16:00"
        let events = RecurringMarketEvents.events(from: [market, daily, unparseable, shop], area: Fixture.area(), now: now)
        XCTAssertEqual(Set(events.map(\.venuePlaceID)), ["m"], "only weekly-ish markets with parseable schedules")
        XCTAssertEqual(events.first?.start, Fixture.date("2026-11-21 10:00"))
        XCTAssertEqual(events.first?.recurrence?.rule, "Sa 10:00-16:00")
        XCTAssertEqual(events.first?.confidence, .partial, "no recent survey date → partially verified")
    }
}

final class RobotsTxtTests: XCTestCase {
    func testGroupsAndLongestMatch() {
        let robots = RobotsTxt("""
        # comment
        User-agent: BadBot
        Disallow: /

        User-agent: *
        Disallow: /private
        Allow: /private/events
        Disallow: /*.pdf$
        """)
        XCTAssertTrue(robots.isAllowed(path: "/", agentToken: "Sidestreet"))
        XCTAssertFalse(robots.isAllowed(path: "/private/admin", agentToken: "Sidestreet"))
        XCTAssertTrue(robots.isAllowed(path: "/private/events", agentToken: "Sidestreet"))
        XCTAssertFalse(robots.isAllowed(path: "/files/menu.pdf", agentToken: "Sidestreet"))
        XCTAssertTrue(robots.isAllowed(path: "/files/menu.pdf.html", agentToken: "Sidestreet"))
        XCTAssertFalse(robots.isAllowed(path: "/", agentToken: "BadBot/1.0"))
    }

    func testEmptyDisallowAllowsEverything() {
        XCTAssertTrue(RobotsTxt("User-agent: *\nDisallow:").isAllowed(path: "/anything", agentToken: "Sidestreet"))
        XCTAssertTrue(RobotsTxt("").isAllowed(path: "/", agentToken: "Sidestreet"))
    }

    func testSpecificAgentGroup() {
        let robots = RobotsTxt("User-agent: *\nDisallow: /\n\nUser-agent: Sidestreet\nAllow: /")
        XCTAssertTrue(robots.isAllowed(path: "/events", agentToken: "Sidestreet"))
    }
}
