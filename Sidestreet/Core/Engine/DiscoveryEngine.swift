import Foundation

/// A progressive update from a discovery run.
struct DiscoveryUpdate: Sendable {
    enum Phase: String, Sendable {
        /// Served from the temporary cache.
        case cached
        /// First results (distinctive places) are in.
        case initial
        /// Everyday places and secondary sources merged.
        case expanded
        /// Enrichment and events added — the run is complete.
        case complete
    }

    var phase: Phase
    var snapshot: DiscoverySnapshot
    var isFinal: Bool { phase == .complete || phase == .cached }
}

/// Orchestrates providers → validation → de-duplication → scoring → events,
/// streaming progressively better snapshots so the feed fills quickly.
///
/// Network etiquette: the two Overpass queries run sequentially; other
/// sources run concurrently with the second one; nothing is fetched when a
/// fresh cached result covers the area.
final class DiscoveryEngine: Sendable {
    struct Sources: Sendable {
        var overpass: OverpassProvider?
        var wikidata: WikidataProvider?
        /// Additional searchable sources (Apple Maps in the app).
        var supplementary: [any PlaceSearchProvider] = []
        var venueEvents: VenueEventsProvider?
    }

    let sources: Sources
    let cache: DiscoveryCache
    private let clock: @Sendable () -> Date

    init(sources: Sources, cache: DiscoveryCache, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.sources = sources
        self.cache = cache
        self.clock = clock
    }

    func discover(area: SearchArea, forceRefresh: Bool = false) -> AsyncStream<DiscoveryUpdate> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                await self.run(area: area, forceRefresh: forceRefresh) { update in
                    continuation.yield(update)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs a complete discovery and stores it in the cache (used by
    /// background refresh). Returns the final snapshot.
    @discardableResult
    func refresh(area: SearchArea) async -> DiscoverySnapshot? {
        var last: DiscoverySnapshot?
        for await update in discover(area: area, forceRefresh: true) {
            last = update.snapshot
        }
        return last
    }

    private func run(area: SearchArea, forceRefresh: Bool, emit: @Sendable (DiscoveryUpdate) -> Void) async {
        let now = clock()
        if !forceRefresh, let cached = await cache.lookup(area) {
            emit(DiscoveryUpdate(phase: .cached, snapshot: cached))
            return
        }

        var statuses: [SourceProvider: SourceStatus] = [:]
        var collected: [Place] = []
        var events: [DiscoveryEvent] = []

        func snapshot() -> DiscoverySnapshot {
            assemble(places: collected, events: events, area: area, statuses: statuses, now: now)
        }

        // Stage 1 — distinctive places (fast, sparse query).
        if let overpass = sources.overpass {
            statuses[.openStreetMap] = .loading
            emit(DiscoveryUpdate(phase: .initial, snapshot: snapshot()))
            do {
                let niche = try await overpass.fetch(.niche, area: area, now: now)
                collected += niche
                statuses[.openStreetMap] = .loaded(count: niche.count)
            } catch {
                statuses[.openStreetMap] = .failed(message: Self.describe(error))
            }
        } else {
            statuses[.openStreetMap] = .skipped(reason: "Disabled")
        }
        if Task.isCancelled { return }
        let initial = snapshot()
        emit(DiscoveryUpdate(phase: .initial, snapshot: initial))

        // Stage 2 — everyday places + secondary sources, concurrently.
        enum StageResult: Sendable {
            case places(SourceProvider, [Place], isEveryday: Bool)
            case failure(SourceProvider, String, isEveryday: Bool)
        }
        let osmNicheFailed = statuses[.openStreetMap]?.isFailure ?? false
        if sources.wikidata != nil { statuses[.wikidata] = .loading }
        for provider in sources.supplementary { statuses[provider.provider] = .loading }
        await withTaskGroup(of: StageResult.self) { group in
            if let overpass = sources.overpass {
                group.addTask {
                    do {
                        return .places(.openStreetMap, try await overpass.fetch(.everyday, area: area, now: now), isEveryday: true)
                    } catch {
                        return .failure(.openStreetMap, Self.describe(error), isEveryday: true)
                    }
                }
            }
            if let wikidata = sources.wikidata {
                group.addTask {
                    do {
                        return .places(.wikidata, try await wikidata.searchPlaces(in: area, now: now), isEveryday: false)
                    } catch {
                        return .failure(.wikidata, Self.describe(error), isEveryday: false)
                    }
                }
            }
            for provider in sources.supplementary {
                group.addTask {
                    do {
                        return .places(provider.provider, try await provider.searchPlaces(in: area, now: now), isEveryday: false)
                    } catch {
                        return .failure(provider.provider, Self.describe(error), isEveryday: false)
                    }
                }
            }
            for await result in group {
                switch result {
                case let .places(provider, places, isEveryday):
                    collected += places
                    if provider == .openStreetMap && isEveryday {
                        let previous: Int
                        if case .loaded(let count)? = statuses[.openStreetMap] { previous = count } else { previous = 0 }
                        statuses[.openStreetMap] = .loaded(count: previous + places.count)
                    } else {
                        statuses[provider] = .loaded(count: places.count)
                    }
                case let .failure(provider, message, isEveryday):
                    if provider == .openStreetMap && isEveryday {
                        if osmNicheFailed { statuses[.openStreetMap] = .failed(message: message) }
                    } else {
                        statuses[provider] = .failed(message: message)
                    }
                }
                if Task.isCancelled { break }
                emit(DiscoveryUpdate(phase: .expanded, snapshot: snapshot()))
            }
        }
        if Task.isCancelled { return }

        // Stage 3 — enrichment and events.
        var current = snapshot()
        if let wikidata = sources.wikidata {
            let ids = current.places.filter { $0.wikidataID != nil && $0.signals.wikipediaSitelinks == nil }.compactMap(\.wikidataID)
            if !ids.isEmpty, let enrichment = try? await wikidata.enrichment(for: ids) {
                collected = collected.map { Self.apply(enrichment, to: $0) }
            }
        }
        if Task.isCancelled { return }
        current = snapshot()
        events = RecurringMarketEvents.events(from: current.places, area: area, now: now)
        if let venueEvents = sources.venueEvents {
            statuses[.venueWebsite] = .loading
            emit(DiscoveryUpdate(phase: .expanded, snapshot: snapshot()))
            let candidates = VenueEventsProvider.candidates(from: current.places, limit: venueEvents.maxVenues)
            let webEvents = await venueEvents.events(for: candidates, area: area, now: now)
            events += webEvents
            statuses[.venueWebsite] = candidates.isEmpty
                ? .skipped(reason: "No venue websites in this area")
                : .loaded(count: webEvents.count)
        }
        if Task.isCancelled { return }
        let final = snapshot()
        let usable = !final.places.isEmpty || !(statuses[.openStreetMap]?.isFailure ?? true)
        if usable { await cache.store(final) }
        emit(DiscoveryUpdate(phase: .complete, snapshot: final))
    }

    /// Validation → sanitising → de-duplication → scoring.
    func assemble(places: [Place], events: [DiscoveryEvent], area: SearchArea,
                  statuses: [SourceProvider: SourceStatus], now: Date) -> DiscoverySnapshot {
        let valid = places.filter { PlaceValidator.isValid($0, area: area) }.map(PlaceValidator.sanitize)
        let merged = Deduplicator.merge(valid)
        let scored = NicheScorer(now: now).score(merged)
        var seenEvents = Set<String>()
        let validEvents = events
            .filter { PlaceValidator.isValid($0, area: area, now: now) }
            .filter { seenEvents.insert($0.title.lowercased() + "|" + String(Int($0.start.timeIntervalSince1970 / 3600))).inserted }
            .sorted { $0.start < $1.start }
        return DiscoverySnapshot(area: area, places: scored, events: validEvents, sourceStatuses: statuses, generatedAt: now)
    }

    static func apply(_ enrichment: [String: WikidataProvider.Enrichment], to place: Place) -> Place {
        guard let id = place.wikidataID, let info = enrichment[id] else { return place }
        var p = place
        p.signals.wikipediaSitelinks = max(p.signals.wikipediaSitelinks ?? 0, info.sitelinks)
        if info.englishWikipedia != nil || info.sitelinks > 0 { p.signals.hasWikipediaArticle = true }
        if let image = info.image, !p.images.contains(where: { $0.url == image }) {
            p.images.insert(PlaceImage(url: image, pageURL: info.imagePage, attribution: "Wikimedia Commons", license: nil,
                                       provider: .wikimediaCommons, origin: .linked), at: 0)
        }
        if p.summary == nil, let description = info.description {
            p.summary = description.prefix(1).uppercased() + description.dropFirst()
        }
        if !p.sources.contains(where: { $0.provider == .wikidata }) {
            p.sources.append(SourceRecord(provider: .wikidata, identifier: id,
                                          url: URL(string: "https://www.wikidata.org/wiki/\(id)"), retrievedAt: Date()))
        }
        return p
    }

    static func describe(_ error: Error) -> String {
        if let network = error as? NetworkError { return network.errorDescription ?? "Network error" }
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
        return "Unavailable"
    }
}
