import Foundation

/// Fetches places from OpenStreetMap via the public Overpass API.
///
/// - Free, no API key. Data © OpenStreetMap contributors (ODbL).
/// - Usage policy: identify the app (User-Agent), no parallel queries, cache
///   results, pause after HTTP 429. Queries are serialised by
///   `HostRateLimiter` and results are cached by `DiscoveryCache`.
/// - The main instance is often overloaded, so further instances are asked
///   when it fails or is slow (hedged requests, one query per server).
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

    /// Remembers which endpoint answered last (tried first next time, also
    /// across app launches for a few hours) and which failed or were slow
    /// (tried last for 5 minutes), so follow-up queries don't wait on servers
    /// that are down.
    actor EndpointHealth {
        static let shared = EndpointHealth(persistenceKey: "overpass.preferredEndpoint")

        private var coolingDownUntil: [URL: Date] = [:]
        private var preferred: (url: URL, since: Date)?
        private let persistenceKey: String?
        private static let preferenceLifetime: TimeInterval = 6 * 3600

        init(persistenceKey: String? = nil) {
            self.persistenceKey = persistenceKey
            if let key = persistenceKey,
               let string = UserDefaults.standard.string(forKey: key), let url = URL(string: string) {
                let since = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: key + ".date"))
                preferred = (url, since)
            }
        }

        func order(_ endpoints: [URL], now: Date = Date()) -> [URL] {
            var list = endpoints
            if let preferred, now.timeIntervalSince(preferred.since) < Self.preferenceLifetime,
               let index = list.firstIndex(of: preferred.url) {
                list.remove(at: index)
                list.insert(preferred.url, at: 0)
            }
            let healthy = list.filter { (coolingDownUntil[$0] ?? .distantPast) <= now }
            let cooling = list.filter { (coolingDownUntil[$0] ?? .distantPast) > now }
            return healthy + cooling
        }

        func markFailed(_ endpoint: URL, now: Date = Date()) {
            coolingDownUntil[endpoint] = now.addingTimeInterval(5 * 60)
            if preferred?.url == endpoint { preferred = nil }
        }

        /// `slower` are endpoints that were still working when `endpoint` answered.
        func markSucceeded(_ endpoint: URL, slower: [URL] = [], now: Date = Date()) {
            coolingDownUntil[endpoint] = nil
            for url in slower where url != endpoint {
                coolingDownUntil[url] = now.addingTimeInterval(5 * 60)
            }
            preferred = (endpoint, now)
            if let key = persistenceKey {
                UserDefaults.standard.set(endpoint.absoluteString, forKey: key)
                UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key + ".date")
            }
        }
    }

    var health: EndpointHealth? = EndpointHealth.shared

    /// Delay before also asking the next endpoint while the current one is
    /// still working ("hedged" request). Different endpoints are different
    /// servers, so this never runs parallel queries against one server.
    var hedgeDelay: TimeInterval = 8
    /// Per-request timeout. Public Overpass servers can queue requests for
    /// 30–45 s when busy, so this is generous; other sources fill the feed meanwhile.
    var requestTimeout: TimeInterval = 60

    func run(query: String, endpoints: [URL]? = nil) async throws -> OverpassResponse {
        var candidates = endpoints ?? self.endpoints ?? Self.defaultEndpoints
        if let health { candidates = await health.order(candidates) }
        guard !candidates.isEmpty else { throw NetworkError.invalidResponse }

        enum Event: Sendable {
            case result(URL, Result<OverpassResponse, NetworkError>)
            case hedge
        }

        return try await withThrowingTaskGroup(of: Event.self) { group in
            var nextIndex = 0
            var running = 0
            var lastError: NetworkError = .invalidResponse
            var inFlight: [URL] = []

            func startNext() {
                guard nextIndex < candidates.count else { return }
                let endpoint = candidates[nextIndex]
                nextIndex += 1
                running += 1
                inFlight.append(endpoint)
                group.addTask {
                    do {
                        return .result(endpoint, .success(try await fetchOnce(query: query, endpoint: endpoint)))
                    } catch let error as NetworkError {
                        return .result(endpoint, .failure(error))
                    } catch is CancellationError {
                        return .result(endpoint, .failure(.cancelled))
                    } catch {
                        return .result(endpoint, .failure(.transport(error.localizedDescription)))
                    }
                }
                if nextIndex < candidates.count {
                    let delay = hedgeDelay
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        return .hedge
                    }
                }
            }

            startNext()
            while let event = try await group.next() {
                switch event {
                case .hedge:
                    startNext()
                case let .result(endpoint, .success(response)):
                    await health?.markSucceeded(endpoint, slower: inFlight.filter { $0 != endpoint })
                    group.cancelAll()
                    return response
                case let .result(endpoint, .failure(error)):
                    running -= 1
                    inFlight.removeAll { $0 == endpoint }
                    if error == .cancelled {
                        if Task.isCancelled { throw error }
                        continue
                    }
                    lastError = error
                    // Non-transient errors (e.g. HTTP 400 = bad query) won't improve elsewhere.
                    guard error.isTransient || error == .decoding("Overpass") else {
                        group.cancelAll()
                        throw error
                    }
                    await health?.markFailed(endpoint)
                    if nextIndex < candidates.count {
                        startNext()
                    } else if running == 0 {
                        group.cancelAll()
                        throw lastError
                    }
                }
            }
            throw lastError
        }
    }

    private func fetchOnce(query: String, endpoint: URL) async throws -> OverpassResponse {
        try Task.checkCancellation()
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        let request = HTTPRequest(
            url: endpoint,
            method: .post,
            headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
                      "Accept": "application/json"],
            body: Data(body.utf8),
            timeout: requestTimeout,
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
