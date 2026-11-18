import XCTest
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

final class GeoMathTests: XCTestCase {
    func testHaversineKnownDistance() {
        // Berlin Alexanderplatz → Brandenburger Tor ≈ 2.5 km
        let alex = GeoCoordinate(latitude: 52.521918, longitude: 13.413215)
        let gate = GeoCoordinate(latitude: 52.516275, longitude: 13.377704)
        XCTAssertEqual(GeoMath.distance(alex, gate), 2_485, accuracy: 60)
        // Paris → London ≈ 343.5 km
        let paris = GeoCoordinate(latitude: 48.8566, longitude: 2.3522)
        let london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278)
        XCTAssertEqual(GeoMath.distance(paris, london) / 1000, 343.5, accuracy: 2)
    }

    func testDistanceIsSymmetricAndZeroForSamePoint() {
        let a = Fixture.berlin
        let b = Fixture.offset(north: 1234)
        XCTAssertEqual(GeoMath.distance(a, b), GeoMath.distance(b, a), accuracy: 0.001)
        XCTAssertEqual(GeoMath.distance(a, a), 0, accuracy: 0.0001)
    }

    func testDestinationRoundTrip() {
        for bearing in stride(from: 0.0, to: 360, by: 45) {
            let target = GeoMath.destination(from: Fixture.berlin, distance: 5_000, bearing: bearing)
            XCTAssertEqual(GeoMath.distance(Fixture.berlin, target), 5_000, accuracy: 1)
        }
    }

    func testRadiusContainmentIsInclusiveAndPrecise() {
        let center = Fixture.berlin
        XCTAssertTrue(GeoMath.isWithin(Fixture.offset(north: 999), center: center, radius: 1_000))
        XCTAssertTrue(GeoMath.isWithin(Fixture.offset(east: 1_000 - 0.5), center: center, radius: 1_000))
        XCTAssertFalse(GeoMath.isWithin(Fixture.offset(north: 1_010), center: center, radius: 1_000))
        XCTAssertFalse(GeoMath.isWithin(Fixture.offset(north: 10), center: center, radius: -1))
    }

    func testAntimeridianDistance() {
        let a = GeoCoordinate(latitude: 0, longitude: 179.9)
        let b = GeoCoordinate(latitude: 0, longitude: -179.9)
        XCTAssertEqual(GeoMath.distance(a, b), 22_239, accuracy: 50)
    }

    func testCoordinateValidation() {
        XCTAssertTrue(GeoCoordinate(latitude: 52.5, longitude: 13.4).isValid)
        XCTAssertFalse(GeoCoordinate(latitude: 0, longitude: 0).isValid, "null island is treated as invalid data")
        XCTAssertFalse(GeoCoordinate(latitude: 91, longitude: 0).isValid)
        XCTAssertFalse(GeoCoordinate(latitude: 10, longitude: 181).isValid)
        XCTAssertFalse(GeoCoordinate(latitude: .nan, longitude: 10).isValid)
    }

    func testRadiusClamping() {
        XCTAssertEqual(GeoMath.clampRadius(10), SearchRadius.minimumMeters)
        XCTAssertEqual(GeoMath.clampRadius(1_000_000), SearchRadius.maximumMeters)
        XCTAssertEqual(GeoMath.clampRadius(3_210), 3_210)
    }

    func testBoundingBoxContainsCircle() {
        let box = GeoMath.boundingBox(center: Fixture.berlin, radius: 2_000)
        XCTAssertLessThan(box.south, Fixture.berlin.latitude)
        XCTAssertGreaterThan(box.north, Fixture.berlin.latitude)
        XCTAssertLessThan(box.west, Fixture.berlin.longitude)
        XCTAssertGreaterThan(box.east, Fixture.berlin.longitude)
    }

    func testSnapshotRestrictionToSmallerRadius() {
        let now = Fixture.referenceDate
        let near = Fixture.place(id: "near", at: Fixture.offset(north: 400))
        let far = Fixture.place(id: "far", at: Fixture.offset(north: 1_800))
        let snapshot = DiscoverySnapshot(area: Fixture.area(radius: 2_000), places: [near, far], events: [],
                                         sourceStatuses: [:], generatedAt: now)
        let restricted = snapshot.restricted(to: Fixture.area(radius: 1_000), now: now)
        XCTAssertEqual(restricted.places.map(\.id), ["near"])
    }
}

final class LocationResolverTests: XCTestCase {
    let now = Fixture.referenceDate
    var city: CityChoice {
        CityChoice(name: "Berlin", subtitle: "Germany", center: GeoCoordinate(latitude: 52.52, longitude: 13.405),
                   timeZoneIdentifier: "Europe/Berlin", countryCode: "DE")
    }

    func fix(_ coordinate: GeoCoordinate, accuracy: Double = 20, age: TimeInterval = 5) -> LocationFix {
        LocationFix(coordinate: coordinate, horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(-age))
    }

    func testCurrentLocationNotDeterminedAsksForPermission() {
        let result = LocationResolver.resolve(preference: .currentLocation, authorization: .notDetermined,
                                              fix: nil, locationFailed: false, now: now)
        XCTAssertEqual(result, .needsPermission)
    }

    func testCurrentLocationDeniedRequiresCity() {
        let result = LocationResolver.resolve(preference: .currentLocation, authorization: .denied,
                                              fix: nil, locationFailed: false, now: now)
        XCTAssertEqual(result, .needsCity(.permissionDenied))
        let restricted = LocationResolver.resolve(preference: .currentLocation, authorization: .restricted,
                                                  fix: nil, locationFailed: false, now: now)
        XCTAssertEqual(restricted, .needsCity(.permissionRestricted))
    }

    func testCurrentLocationAuthorizedUsesFreshFix() {
        let f = fix(Fixture.berlin)
        let result = LocationResolver.resolve(preference: .currentLocation, authorization: .authorizedWhenInUse,
                                              fix: f, locationFailed: false, now: now)
        XCTAssertEqual(result, .gps(f))
        XCTAssertEqual(result.coordinate, Fixture.berlin)
    }

    func testStaleOrInaccurateFixIsIgnored() {
        let stale = fix(Fixture.berlin, age: 60 * 60)
        XCTAssertEqual(LocationResolver.resolve(preference: .currentLocation, authorization: .authorizedWhenInUse,
                                                fix: stale, locationFailed: false, now: now), .locating)
        let inaccurate = fix(Fixture.berlin, accuracy: 5_000)
        XCTAssertEqual(LocationResolver.resolve(preference: .currentLocation, authorization: .authorizedWhenInUse,
                                                fix: inaccurate, locationFailed: true, now: now),
                       .needsCity(.locationUnavailable))
    }

    func testCityPreferenceFallsBackToCityWhenDenied() {
        let result = LocationResolver.resolve(preference: .city(city, preferGPSInside: true), authorization: .denied,
                                              fix: nil, locationFailed: false, now: now)
        XCTAssertEqual(result, .city(city, fallbackReason: .permissionDenied))
        XCTAssertEqual(result.coordinate, city.center)
    }

    func testCityPreferenceUsesGPSWhenInsideCity() {
        let inside = fix(Fixture.berlin) // ~2.5 km from the city centre
        let result = LocationResolver.resolve(preference: .city(city, preferGPSInside: true),
                                              authorization: .authorizedWhenInUse, fix: inside, locationFailed: false, now: now)
        XCTAssertEqual(result, .gps(inside))
    }

    func testCityPreferenceUsesCityCentreWhenFarAway() {
        let paris = fix(GeoCoordinate(latitude: 48.8566, longitude: 2.3522))
        let result = LocationResolver.resolve(preference: .city(city, preferGPSInside: true),
                                              authorization: .authorizedWhenInUse, fix: paris, locationFailed: false, now: now)
        XCTAssertEqual(result, .city(city, fallbackReason: .outsideCity))
    }

    func testExplicitCityCentreIgnoresGPS() {
        let inside = fix(Fixture.berlin)
        let result = LocationResolver.resolve(preference: .city(city, preferGPSInside: false),
                                              authorization: .authorizedWhenInUse, fix: inside, locationFailed: false, now: now)
        XCTAssertEqual(result, .city(city, fallbackReason: nil))
    }
}
