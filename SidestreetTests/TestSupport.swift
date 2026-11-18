import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

/// Test fixtures. These are synthetic records used only by unit tests; they
/// are never shown in the app.
enum Fixture {
    static let berlin = GeoCoordinate(latitude: 52.4990, longitude: 13.4155)

    static func area(center: GeoCoordinate = berlin, radius: Double = 2_000, timeZone: String = "Europe/Berlin") -> SearchArea {
        SearchArea(center: center, radiusMeters: radius, label: "Test City", subtitle: nil,
                   centerSource: .city, timeZoneIdentifier: timeZone, countryCode: "DE")
    }

    static func place(
        id: String = UUID().uuidString,
        name: String = "Test Place",
        kind: PlaceKind = .thriftStore,
        at coordinate: GeoCoordinate = berlin,
        provider: SourceProvider = .openStreetMap,
        brand: BrandInfo? = nil,
        wikidataID: String? = nil,
        sitelinks: Int? = nil,
        tagRichness: Double = 0.6,
        lastConfirmed: Date? = nil,
        inferredName: Bool = false
    ) -> Place {
        var place = Place(id: id, name: name, isNameInferred: inferredName, coordinate: coordinate, kind: kind,
                          categories: Set(kind.categories))
        place.sources = [SourceRecord(provider: provider, identifier: id, url: nil, retrievedAt: Date(timeIntervalSince1970: 0))]
        place.brand = brand
        place.wikidataID = wikidataID
        place.signals.wikipediaSitelinks = sitelinks
        place.signals.tagRichness = tagRichness
        place.signals.lastConfirmed = lastConfirmed
        return place
    }

    /// A coordinate `meters` north of `origin`.
    static func offset(_ origin: GeoCoordinate = berlin, north meters: Double) -> GeoCoordinate {
        GeoMath.destination(from: origin, distance: meters, bearing: 0)
    }

    static func offset(_ origin: GeoCoordinate = berlin, east meters: Double) -> GeoCoordinate {
        GeoMath.destination(from: origin, distance: meters, bearing: 90)
    }

    /// Fixed reference date: Wednesday 18 Nov 2026, 12:00 Berlin time.
    static var referenceDate: Date {
        date("2026-11-18 12:00", timeZone: "Europe/Berlin")
    }

    static func date(_ string: String, timeZone: String = "Europe/Berlin") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }
}

/// Scripted HTTP client: maps requests to canned responses or errors.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async throws -> HTTPResponse
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    private func record(_ request: HTTPRequest) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        record(request)
        return try await handler(request)
    }

    static func ok(_ body: String, url: URL = URL(string: "https://example.org")!, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: 200, headers: headers, data: Data(body.utf8), url: url)
    }

    static func status(_ code: Int, body: String = "", headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: code, headers: headers, data: Data(body.utf8), url: URL(string: "https://example.org")!)
    }
}

extension HTTPRequest {
    var bodyString: String { body.map { String(decoding: $0, as: UTF8.self) } ?? "" }
    var decodedFormBody: String { bodyString.removingPercentEncoding ?? bodyString }
}
