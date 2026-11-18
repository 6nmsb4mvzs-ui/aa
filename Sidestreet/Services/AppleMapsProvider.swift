import Foundation
import MapKit

/// Apple Maps local search (MapKit, on-device, free, no key).
///
/// Adds independent businesses that OpenStreetMap may be missing and
/// cross-confirms OSM records (raising their confidence). Apple throttles
/// apps that search too often, so a single run issues a small, fixed set of
/// queries sequentially. Places returned for a *generic* query ("coffee")
/// are flagged as prominent in mainstream search, which lowers obscurity.
struct AppleMapsProvider: PlaceSearchProvider {
    struct Query: Sendable {
        var text: String
        var kind: PlaceKind
        var isGeneric: Bool
        /// Apple POI categories accepted for this query (nil = any).
        var allowed: Set<String>?
    }

    var provider: SourceProvider { .appleMaps }

    static let queries: [Query] = [
        Query(text: "coffee", kind: .cafe, isGeneric: true, allowed: ["MKPOICategoryCafe", "MKPOICategoryBakery"]),
        Query(text: "thrift store", kind: .thriftStore, isGeneric: false, allowed: ["MKPOICategoryStore"]),
        Query(text: "vintage clothing", kind: .vintageStore, isGeneric: false, allowed: ["MKPOICategoryStore"]),
        Query(text: "skate shop", kind: .skateShop, isGeneric: false, allowed: ["MKPOICategoryStore"]),
        Query(text: "record store", kind: .recordStore, isGeneric: false, allowed: ["MKPOICategoryStore"]),
        Query(text: "flea market", kind: .fleaMarket, isGeneric: false, allowed: nil),
        Query(text: "tattoo studio", kind: .tattooStudio, isGeneric: false, allowed: nil),
        Query(text: "art gallery", kind: .gallery, isGeneric: false, allowed: ["MKPOICategoryMuseum", "MKPOICategoryStore"]),
        Query(text: "specialty coffee roaster", kind: .coffeeRoaster, isGeneric: false, allowed: ["MKPOICategoryCafe", "MKPOICategoryStore"]),
        Query(text: "vegan restaurant", kind: .veganRestaurant, isGeneric: false, allowed: ["MKPOICategoryRestaurant", "MKPOICategoryCafe", "MKPOICategoryFoodMarket"]),
        Query(text: "comic store", kind: .comicStore, isGeneric: false, allowed: ["MKPOICategoryStore"]),
        Query(text: "live music venue", kind: .musicVenue, isGeneric: false, allowed: ["MKPOICategoryNightlife", "MKPOICategoryTheater", "MKPOICategoryMusicVenue"]),
    ]

    func searchPlaces(in area: SearchArea, now: Date) async throws -> [Place] {
        var results: [Place] = []
        var failures = 0
        var throttled = false
        // Three searches at a time: fast enough to arrive within seconds,
        // gentle enough to stay under Apple's search throttling.
        let batches = stride(from: 0, to: Self.queries.count, by: 3).map {
            Array(Self.queries[$0..<min($0 + 3, Self.queries.count)])
        }
        for batch in batches {
            try Task.checkCancellation()
            if throttled { break }
            await withTaskGroup(of: Result<[Place], Error>.self) { group in
                for query in batch {
                    group.addTask {
                        do { return .success(try await search(query, area: area, now: now)) } catch { return .failure(error) }
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let places):
                        results += places
                    case .failure(let error):
                        failures += 1
                        if (error as NSError).code == MKError.Code.loadingThrottled.rawValue { throttled = true }
                    }
                }
            }
        }
        if results.isEmpty && failures > 0 { throw NetworkError.transport("Apple Maps search unavailable") }
        return results
    }

    /// Runs one query and converts results on the main actor (MapKit objects
    /// never leave it).
    @MainActor
    private func search(_ query: Query, area: SearchArea, now: Date) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.text
        request.resultTypes = .pointOfInterest
        let span = min(area.radiusMeters, 20_000) * 2
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: area.center.latitude, longitude: area.center.longitude),
            latitudinalMeters: span, longitudinalMeters: span
        )
        let items = try await MKLocalSearch(request: request).start().mapItems
        return items.compactMap { Self.place(from: $0, query: query, area: area, now: now) }
    }

    @MainActor
    static func place(from item: MKMapItem, query: Query, area: SearchArea, now: Date) -> Place? {
        guard let name = item.name?.trimmingCharacters(in: .whitespaces), PlaceValidator.isValidName(name) else { return nil }
        let c = item.placemark.coordinate
        let coordinate = GeoCoordinate(latitude: c.latitude, longitude: c.longitude)
        guard coordinate.isValid, area.contains(coordinate) else { return nil }
        if let allowed = query.allowed, let category = item.pointOfInterestCategory?.rawValue, !allowed.contains(category) {
            return nil
        }
        var kind = query.kind
        if query.kind == .cafe, name.lowercased().contains("roast") { kind = .coffeeRoaster }
        // Re-use the OSM name heuristics for fashion results ("Vintage …", "Thrift …").
        if kind.primaryCategory == .fashion, let refined = OSMPlaceBuilder.classify(["shop": "clothes", "name": name]),
           refined != .clothingStore {
            kind = refined
        }
        let key = String(format: "%@|%.4f|%.4f", name.lowercased(), coordinate.latitude, coordinate.longitude)
        var place = Place(id: "apple:" + MD5.hex(key), name: name, coordinate: coordinate, kind: kind,
                          categories: Set(kind.categories))
        let placemark = item.placemark
        place.address = PostalAddress(street: placemark.thoroughfare, houseNumber: placemark.subThoroughfare,
                                      postcode: placemark.postalCode, city: placemark.locality,
                                      district: placemark.subLocality, country: placemark.country, formatted: nil)
        place.phone = item.phoneNumber
        if let url = item.url, url.scheme?.hasPrefix("http") == true { place.website = url }
        var mapsURL = URLComponents(string: "https://maps.apple.com/")!
        mapsURL.queryItems = [.init(name: "q", value: name), .init(name: "ll", value: "\(c.latitude),\(c.longitude)")]
        place.sources = [SourceRecord(provider: .appleMaps, identifier: key, url: mapsURL.url, retrievedAt: now)]
        place.signals.appleGenericVisibility = query.isGeneric
        place.signals.tagRichness = [place.address?.isEmpty == false, item.phoneNumber != nil, item.url != nil]
            .filter { $0 }.count > 1 ? 0.45 : 0.3
        place.signals.subcultureKeywordHits = TextMatching.containsAny(name, keywords: SubcultureLexicon.keywords)
        place.price = OSMPlaceBuilder.price(from: [:], kind: kind, brand: nil)
        return place
    }
}
