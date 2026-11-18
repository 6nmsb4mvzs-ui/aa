import Foundation

/// Per-host politeness: limits concurrency, spaces out requests and honours
/// back-off after HTTP 429/503 — as requested by the Overpass ("no parallel
/// queries", pause after 429) and Wikimedia (≤ 3 concurrent requests,
/// respect Retry-After) usage policies.
actor HostRateLimiter {
    struct Policy: Sendable {
        var maxConcurrent: Int
        var minInterval: TimeInterval
    }

    private struct State {
        var inFlight = 0
        var nextAllowed = Date.distantPast
        var backoffUntil = Date.distantPast
    }

    private var states: [String: State] = [:]
    private let maxWait: TimeInterval

    init(maxWait: TimeInterval = 20) {
        self.maxWait = maxWait
    }

    static func policy(for host: String) -> Policy {
        let host = host.lowercased()
        if host.contains("overpass") { return Policy(maxConcurrent: 1, minInterval: 1.0) }
        if host == "query.wikidata.org" { return Policy(maxConcurrent: 1, minInterval: 1.0) }
        if host == "upload.wikimedia.org" { return Policy(maxConcurrent: 3, minInterval: 0.05) }
        if host.hasSuffix("wikipedia.org") || host.hasSuffix("wikimedia.org") || host.hasSuffix("wikidata.org") {
            return Policy(maxConcurrent: 2, minInterval: 0.4)
        }
        if host.hasSuffix("googleapis.com") { return Policy(maxConcurrent: 2, minInterval: 0.2) }
        if host == "api.panoramax.xyz" { return Policy(maxConcurrent: 2, minInterval: 0.3) }
        if host == "graph.mapillary.com" { return Policy(maxConcurrent: 3, minInterval: 0.1) }
        // Third-party venue websites: be gentle.
        return Policy(maxConcurrent: 1, minInterval: 1.0)
    }

    func acquire(host: String) async throws {
        let policy = Self.policy(for: host)
        let started = Date()
        while true {
            try Task.checkCancellation()
            var state = states[host] ?? State()
            let now = Date()
            if state.backoffUntil > now, state.backoffUntil.timeIntervalSince(now) > maxWait {
                throw NetworkError.rateLimited(retryAfter: state.backoffUntil.timeIntervalSince(now))
            }
            if state.inFlight < policy.maxConcurrent && now >= state.nextAllowed && now >= state.backoffUntil {
                state.inFlight += 1
                state.nextAllowed = now.addingTimeInterval(policy.minInterval)
                states[host] = state
                return
            }
            if now.timeIntervalSince(started) > maxWait * 2 {
                throw NetworkError.timedOut
            }
            let waitUntil = max(state.nextAllowed, state.backoffUntil)
            let delay = min(max(waitUntil.timeIntervalSince(now), 0.05), 0.5)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    func release(host: String) {
        guard var state = states[host] else { return }
        state.inFlight = max(0, state.inFlight - 1)
        states[host] = state
    }

    func backOff(host: String, seconds: TimeInterval) {
        var state = states[host] ?? State()
        state.backoffUntil = max(state.backoffUntil, Date().addingTimeInterval(min(seconds, 300)))
        states[host] = state
    }

    func isBackingOff(host: String) -> Bool {
        (states[host]?.backoffUntil ?? .distantPast) > Date()
    }
}
