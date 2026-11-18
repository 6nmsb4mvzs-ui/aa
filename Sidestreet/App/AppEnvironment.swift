import Foundation

/// Builds the discovery engine and services from the current settings.
enum AppEnvironment {
    /// Shared rate limiter so politeness limits hold across engine rebuilds.
    static let rateLimiter = HostRateLimiter()

    static let cache = DiscoveryCache(directory: DiscoveryCache.defaultDirectory())

    /// Finds photos for places without one (website preview, Commons, street level).
    static let photoFinder = PhotoFinder(client: httpClient(identity: .default), cacheFile: PhotoFinder.defaultCacheFile())

    static func httpClient(identity: ClientIdentity) -> URLSessionHTTPClient {
        URLSessionHTTPClient(identity: identity, limiter: rateLimiter)
    }

    struct SourceOptions: Sendable, Hashable {
        var appleMaps: Bool
        var wikidata: Bool
        var venueEvents: Bool
        var identity: ClientIdentity
    }

    static func makeEngine(options: SourceOptions) -> DiscoveryEngine {
        let client = httpClient(identity: options.identity)
        var supplementary: [any PlaceSearchProvider] = []
        if options.appleMaps { supplementary.append(AppleMapsProvider()) }
        return DiscoveryEngine(
            sources: .init(
                overpass: OverpassProvider(client: client),
                wikidata: options.wikidata ? WikidataProvider(client: client) : nil,
                supplementary: supplementary,
                venueEvents: options.venueEvents ? VenueEventsProvider(client: client) : nil
            ),
            cache: cache
        )
    }
}
