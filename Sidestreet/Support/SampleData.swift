import Foundation

/// FICTIONAL sample data for SwiftUI previews and the optional Demo mode.
///
/// Every record is flagged `isSample = true`, uses the `.sample` source,
/// carries a "Sample ·" name prefix and is rejected by `PlaceValidator`, so
/// it can never be mixed into real discovery results. The UI shows a
/// "SAMPLE DATA" banner whenever these records are displayed.
enum SampleData {
    static let center = GeoCoordinate(latitude: 52.4990, longitude: 13.4155)

    static func area(center: GeoCoordinate = center, radius: Double = 2_500) -> SearchArea {
        SearchArea(center: center, radiusMeters: radius, label: "Sample City", subtitle: "Fictional data",
                   centerSource: .city, timeZoneIdentifier: TimeZone.current.identifier, countryCode: nil)
    }

    private static func make(_ index: Int, _ name: String, _ kind: PlaceKind, north: Double, east: Double,
                             hours: String? = nil, descriptors: [String] = [], summary: String? = nil,
                             around origin: GeoCoordinate) -> Place {
        let point = GeoMath.destination(from: GeoMath.destination(from: origin, distance: north, bearing: 0), distance: east, bearing: 90)
        var place = Place(id: "sample:\(index)", name: "Sample · " + name, coordinate: point, kind: kind,
                          categories: Set(kind.categories), descriptors: descriptors)
        place.openingHoursRaw = hours
        place.summary = summary ?? "Fictional example used to preview the interface. Not a real place."
        place.address = PostalAddress(street: "Example Street", houseNumber: "\(index + 1)", postcode: nil,
                                      city: "Sample City", district: nil, country: nil, formatted: nil)
        place.price = OSMPlaceBuilder.price(from: [:], kind: kind, brand: nil)
        place.sources = [SourceRecord(provider: .sample, identifier: "sample-\(index)", url: nil, retrievedAt: Date())]
        place.signals.tagRichness = 0.6
        place.isSample = true
        return place
    }

    static func places(around origin: GeoCoordinate = center) -> [Place] {
        let list: [Place] = [
            make(0, "Second Skin Vintage", .vintageStore, north: 220, east: -140, hours: "Mo-Sa 11:00-19:00",
                 descriptors: ["vintage", "y2k", "second-hand"], around: origin),
            make(1, "Concrete Bowl DIY", .diySkatepark, north: -480, east: 610, descriptors: ["diy", "bowl"], around: origin),
            make(2, "Night Owl Records", .recordStore, north: 650, east: 300, hours: "Tu-Sa 12:00-20:00",
                 descriptors: ["vinyl", "techno", "dub"], around: origin),
            make(3, "Grey Block Estate", .brutalistBuilding, north: -900, east: -400, descriptors: ["brutalist"], around: origin),
            make(4, "Canal Side Mural", .mural, north: 120, east: 820, around: origin),
            make(5, "Slow Pour Roasters", .coffeeRoaster, north: 380, east: -700, hours: "Mo-Su 08:00-18:00",
                 descriptors: ["specialty coffee", "outdoor seating"], around: origin),
            make(6, "Kollektiv Space", .socialCentre, north: -150, east: -1100, descriptors: ["diy", "community"], around: origin),
            make(7, "Water Tower Hill", .viewpoint, north: 1300, east: 900, around: origin),
            make(8, "Thrift Depot", .thriftStore, north: -1300, east: 200, hours: "Mo-Fr 10:00-19:00; Sa 10:00-16:00",
                 descriptors: ["second-hand", "kilo sale"], around: origin),
            make(9, "Green Plate", .veganRestaurant, north: 800, east: -1200, hours: "Mo-Su 12:00-23:30",
                 descriptors: ["100% vegan", "late-night"], around: origin),
            make(10, "Ink Department", .tattooStudio, north: -700, east: 1300, around: origin),
            make(11, "Reed Pond", .pond, north: 1800, east: -600, around: origin),
            make(12, "Big Chain Fashion", .fashionChain, north: 60, east: 60, hours: "Mo-Sa 10:00-20:00", around: origin),
            make(13, "Arcade 2000", .arcade, north: -1700, east: -900, descriptors: ["retro gaming", "pinball"], around: origin),
        ]
        var scored = NicheScorer(now: Date()).score(list)
        for index in scored.indices { scored[index].isSample = true }
        return scored
    }

    static func events(around origin: GeoCoordinate = center, now: Date = Date()) -> [DiscoveryEvent] {
        let calendar = Calendar.current
        let saturday = calendar.nextDate(after: now, matching: DateComponents(hour: 10, minute: 0, weekday: 7),
                                         matchingPolicy: .nextTime) ?? now.addingTimeInterval(3 * 86_400)
        let friday = calendar.nextDate(after: now, matching: DateComponents(hour: 23, minute: 0, weekday: 6),
                                       matchingPolicy: .nextTime) ?? now.addingTimeInterval(2 * 86_400)
        let source = SourceRecord(provider: .sample, identifier: "sample-event", url: nil, retrievedAt: now)
        return [
            DiscoveryEvent(id: "sample-event-0", title: "Sample · Canal Flea Market", kind: .fleaMarket, start: saturday,
                           end: saturday.addingTimeInterval(6 * 3600), isAllDay: false,
                           recurrence: .init(scheduleDescription: "Sat 10:00–16:00", rule: "Sa 10:00-16:00"),
                           venueName: "Sample City Canal", venuePlaceID: nil,
                           coordinate: GeoMath.destination(from: origin, distance: 500, bearing: 200), addressText: nil,
                           url: nil, imageURL: nil, summary: "Fictional event used to preview the interface.",
                           source: source, confidence: .partial, timeZoneIdentifier: nil, isSample: true),
            DiscoveryEvent(id: "sample-event-1", title: "Sample · Basement Dub Night", kind: .music, start: friday,
                           end: friday.addingTimeInterval(6 * 3600), isAllDay: false, recurrence: nil,
                           venueName: "Sample · Night Owl Records", venuePlaceID: "sample:2",
                           coordinate: GeoMath.destination(from: origin, distance: 720, bearing: 25), addressText: nil,
                           url: nil, imageURL: nil, summary: "Fictional event used to preview the interface.",
                           source: source, confidence: .verified, timeZoneIdentifier: nil, isSample: true),
        ]
    }

    static func snapshot(around origin: GeoCoordinate = center, radius: Double = 2_500) -> DiscoverySnapshot {
        DiscoverySnapshot(area: area(center: origin, radius: radius), places: places(around: origin),
                          events: events(around: origin), sourceStatuses: [.sample: .loaded(count: 14)],
                          generatedAt: Date())
    }
}
