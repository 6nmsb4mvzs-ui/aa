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

    /// Free regional instances (listed on the OSM wiki; no key, ≤ 4 parallel
    /// queries per IP, daily-updated extracts). Used only as a last resort
    /// for areas they cover.
    static let europeEndpoint = URL(string: "https://ovp.dresel.systems/api/interpreter")!
    static let northAmericaEndpoint = URL(string: "https://ovp.dresel.systems/api-na/interpreter")!

    /// Endpoints to try, in order, for an area.
    static func endpoints(for area: SearchArea) -> [URL] {
        var list = defaultEndpoints
        let c = area.center
        if (34...72).contains(c.latitude) && (-25...45).contains(c.longitude) {
            list.append(europeEndpoint)
        } else if (14...84).contains(c.latitude) && (-170 ... -50).contains(c.longitude) {
            list.append(northAmericaEndpoint)
        }
        return list
    }

    var client: HTTPClient
    /// Fixed endpoint list (tests/diagnostics). When nil, `endpoints(for:)` decides.
    var endpoints: [URL]? = nil

    func fetch(_ kind: OverpassQueryBuilder.Kind, area: SearchArea, now: Date) async throws -> [Place] {
        let query = OverpassQueryBuilder.query(kind, area: area)
        let response = try await run(query: query, endpoints: endpoints ?? Self.endpoints(for: area))
        return Self.places(from: response, area: area, now: now)
    }

    /// Remembers endpoints that recently failed so the next query (e.g. the
    /// "everyday" query right after the "niche" one) doesn't wait on them again.
    actor EndpointHealth {
        static let shared = EndpointHealth()
        private var coolingDownUntil: [URL: Date] = [:]

        func order(_ endpoints: [URL], now: Date = Date()) -> [URL] {
            let healthy = endpoints.filter { (coolingDownUntil[$0] ?? .distantPast) <= now }
            let cooling = endpoints.filter { (coolingDownUntil[$0] ?? .distantPast) > now }
            return healthy + cooling
        }

        func markFailed(_ endpoint: URL, now: Date = Date()) {
            coolingDownUntil[endpoint] = now.addingTimeInterval(5 * 60)
        }

        func markSucceeded(_ endpoint: URL) {
            coolingDownUntil[endpoint] = nil
        }
    }

    var health: EndpointHealth? = EndpointHealth.shared

    func run(query: String, endpoints: [URL]? = nil) async throws -> OverpassResponse {
        var lastError: Error = NetworkError.invalidResponse
        var candidates = endpoints ?? self.endpoints ?? Self.defaultEndpoints
        if let health { candidates = await health.order(candidates) }
        for endpoint in candidates {
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
                    timeout: 30,
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
                await health?.markSucceeded(endpoint)
                return decoded
            } catch let error as NetworkError {
                lastError = error
                if error == .cancelled { throw error }
                guard error.isTransient || error == .decoding("Overpass") else { throw error }
                await health?.markFailed(endpoint)
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
