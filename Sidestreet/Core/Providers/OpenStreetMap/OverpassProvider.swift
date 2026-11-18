import Foundation

/// Fetches places from OpenStreetMap via the public Overpass API.
///
/// - Free, no API key. Data © OpenStreetMap contributors (ODbL).
/// - Usage policy: identify the app (User-Agent), no parallel queries, cache
///   results, pause after HTTP 429. Queries are serialised by
///   `HostRateLimiter` and results are cached by `DiscoveryCache`.
/// - The main instance is often overloaded, so a second public instance is
///   used as a fallback on timeouts, 429 and 5xx responses.
struct OverpassProvider: Sendable {
    static let defaultEndpoints: [URL] = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.private.coffee/api/interpreter")!,
    ]

    var client: HTTPClient
    var endpoints: [URL] = OverpassProvider.defaultEndpoints

    func fetch(_ kind: OverpassQueryBuilder.Kind, area: SearchArea, now: Date) async throws -> [Place] {
        let query = OverpassQueryBuilder.query(kind, area: area)
        let response = try await run(query: query)
        return Self.places(from: response, area: area, now: now)
    }

    func run(query: String) async throws -> OverpassResponse {
        var lastError: Error = NetworkError.invalidResponse
        for endpoint in endpoints {
            try Task.checkCancellation()
            do {
                var allowed = CharacterSet.alphanumerics
                allowed.insert(charactersIn: "-._~")
                let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
                let request = HTTPRequest(
                    url: endpoint,
                    method: .post,
                    headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
                              "Accept": "application/json"],
                    body: Data(body.utf8),
                    timeout: 35,
                    maxBytes: 20 * 1024 * 1024
                )
                let response = try await client.sendChecked(request)
                let decoded: OverpassResponse
                do {
                    decoded = try JSONDecoder().decode(OverpassResponse.self, from: response.data)
                } catch {
                    // Overpass returns HTML/XML error pages with status 200 on some failures.
                    throw NetworkError.decoding("Overpass")
                }
                if decoded.elements.isEmpty, let remark = decoded.remark, remark.lowercased().contains("error") {
                    throw NetworkError.httpStatus(504)
                }
                return decoded
            } catch let error as NetworkError {
                lastError = error
                if error == .cancelled { throw error }
                guard error.isTransient || error == .decoding("Overpass") else { throw error }
                continue
            }
        }
        throw lastError
    }

    static func places(from response: OverpassResponse, area: SearchArea, now: Date) -> [Place] {
        // Allow a small tolerance: way centres can sit just outside the circle.
        let tolerance = area.radiusMeters * 1.05 + 30
        var seen = Set<String>()
        var result: [Place] = []
        for element in response.elements {
            guard let place = OSMPlaceBuilder.place(from: element, retrievedAt: now) else { continue }
            guard GeoMath.distance(place.coordinate, area.center) <= tolerance else { continue }
            guard seen.insert(place.id).inserted else { continue }
            result.append(place)
        }
        return result
    }
}
