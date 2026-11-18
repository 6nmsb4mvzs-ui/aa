import Foundation
import Observation

/// Central app state shared by all tabs.
///
/// Owns the discovery flow: resolve the centre (GPS or city) → build the
/// search area → stream results from the engine → rank off the main thread →
/// expose a paginated feed. Ranking, filtering and radius changes never block
/// the UI.
@MainActor
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case idle
        /// No results yet.
        case loading
        /// Some results shown, more sources still loading.
        case refining
        case loaded
        case failed(String)
    }

    let settings: AppSettings
    let location = LocationService()
    let citySearch = CitySearchService()
    let history = SearchHistoryStore(fileURL: SearchHistoryStore.defaultFileURL())
    @ObservationIgnored private(set) var engine: DiscoveryEngine
    @ObservationIgnored private(set) var details: PlaceDetailService
    @ObservationIgnored private var engineOptions: AppEnvironment.SourceOptions

    // Centre & area
    private(set) var selectedCity: CityChoice?
    private(set) var usesCurrentLocation: Bool
    private(set) var currentLocationInfo: CityChoice?
    private(set) var resolution: CenterResolution = .needsPermission
    private(set) var radiusMeters: Double
    private(set) var area: SearchArea?

    // Results
    private(set) var snapshot: DiscoverySnapshot?
    private(set) var loadState: LoadState = .idle
    private(set) var feed: [FeedEntry] = []
    private(set) var visibleCount = 20
    private(set) var filter: CategoryFilter
    private(set) var historyEntries: [SearchHistoryEntry] = []
    /// Clusters of independent shops / street art / nightlife in the current results.
    private(set) var hotspots: [Hotspot] = []

    /// The entry whose preview/profile sheet is open (feed or map).
    var selectedEntry: FeedEntry?

    static let pageSize = 20

    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var rankTask: Task<Void, Never>?
    @ObservationIgnored private var radiusTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isResolvingLocation = false
    @ObservationIgnored private var recordedHistoryForArea: SearchArea?

    init(settings: AppSettings) {
        self.settings = settings
        let options = Self.options(from: settings)
        engineOptions = options
        engine = AppEnvironment.makeEngine(options: options)
        details = PlaceDetailService(identity: settings.clientIdentity)
        usesCurrentLocation = settings.usesCurrentLocation
        selectedCity = settings.lastCity
        radiusMeters = settings.lastArea?.radiusMeters ?? settings.defaultRadiusMeters
        filter = CategoryFilter(selected: settings.lastFilters)
    }

    private static func options(from settings: AppSettings) -> AppEnvironment.SourceOptions {
        .init(appleMaps: settings.appleMapsEnabled, wikidata: settings.wikidataEnabled,
              venueEvents: settings.venueEventsEnabled, identity: settings.clientIdentity)
    }

    // MARK: - Derived state

    var visibleFeed: ArraySlice<FeedEntry> { feed.prefix(visibleCount) }
    var hasMoreToShow: Bool { visibleCount < feed.count }
    var isDemo: Bool { settings.demoMode }

    var timeZone: TimeZone { area?.timeZone ?? .current }

    var placeCount: Int { snapshot?.places.count ?? 0 }

    func place(withID id: String) -> Place? {
        snapshot?.places.first { $0.id == id }
    }
    var eventCount: Int { snapshot?.events.count ?? 0 }

    struct SourceFailure: Identifiable, Hashable {
        var provider: SourceProvider
        var message: String
        var id: SourceProvider { provider }
    }

    var failedSources: [SourceFailure] {
        (snapshot?.sourceStatuses ?? [:]).compactMap { provider, status in
            if case .failed(let message) = status { return SourceFailure(provider: provider, message: message) }
            return nil
        }.sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    var isLoadingSources: Bool {
        snapshot?.sourceStatuses.values.contains { $0 == .loading } ?? false
    }

    /// Places for the map: ranked order, current filter, capped for performance.
    var mapEntries: [FeedEntry] {
        Array(feed.filter { $0.coordinate != nil }.prefix(400))
    }

    var locationTitle: String {
        if isDemo { return "Sample City" }
        switch resolution {
        case .gps: return currentLocationInfo?.name ?? "Current location"
        case .city(let city, _): return city.name
        case .locating: return "Locating…"
        case .needsPermission, .needsCity: return "Choose a place"
        }
    }

    var locationSubtitle: String? {
        switch resolution {
        case .gps: return currentLocationInfo?.subtitle ?? "Near you"
        case .city(let city, let reason):
            if reason == .permissionDenied || reason == .permissionRestricted { return "City centre · location off" }
            if reason == .outsideCity { return "City centre" }
            return city.subtitle
        default: return nil
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await ImagePipeline.shared.setUserAgent(settings.clientIdentity.userAgent)
        await AppEnvironment.cache.purgeExpired()
        await refreshHistory()
        if isDemo {
            loadDemo()
            return
        }
        if usesCurrentLocation {
            if location.authorization == .notDetermined {
                recomputeResolution()
                if selectedCity != nil, resolution.coordinate != nil { discover() }
            } else {
                await locateAndDiscover()
            }
        } else if selectedCity != nil {
            await refreshResolutionForCity()
            discover()
        } else {
            recomputeResolution()
        }
    }

    /// Called when the location permission changes (e.g. after returning
    /// from the Settings app).
    func authorizationChanged() async {
        // A user-initiated location flow handles the change itself.
        guard hasStarted, !isDemo, !isResolvingLocation else { return }
        if usesCurrentLocation && location.authorization.allowsLocation {
            await locateAndDiscover()
        } else {
            let previous = area?.center
            recomputeResolution()
            if resolution.coordinate != previous { discover() }
        }
    }

    // MARK: - Centre selection

    func useCurrentLocation() async {
        usesCurrentLocation = true
        settings.usesCurrentLocation = true
        if isDemo { return }
        isResolvingLocation = true
        defer { isResolvingLocation = false }
        if location.authorization == .notDetermined {
            _ = await location.requestAuthorization()
        }
        await locateAndDiscover()
    }

    func selectCity(_ city: CityChoice) async {
        selectedCity = city
        usesCurrentLocation = false
        settings.lastCity = city
        settings.usesCurrentLocation = false
        if isDemo {
            loadDemo()
            return
        }
        await refreshResolutionForCity()
        discover()
    }

    func restore(_ entry: SearchHistoryEntry) async {
        let city = CityChoice(name: entry.label, subtitle: entry.subtitle, center: entry.center,
                              timeZoneIdentifier: entry.timeZoneIdentifier, countryCode: entry.countryCode)
        selectedCity = city
        usesCurrentLocation = false
        settings.lastCity = city
        settings.usesCurrentLocation = false
        radiusMeters = GeoMath.clampRadius(entry.radiusMeters)
        filter = CategoryFilter(selected: Set(entry.filters))
        settings.lastFilters = filter.selected
        if isDemo {
            loadDemo()
            return
        }
        // A history entry means "exactly this place": use its stored centre.
        resolution = .city(city, fallbackReason: nil)
        discover()
    }

    private func locateAndDiscover() async {
        if location.authorization.allowsLocation {
            if !LocationResolver.isUsable(location.lastFix, now: Date()) {
                resolution = .locating
            }
            if let fix = try? await location.currentLocation() {
                if currentLocationInfo == nil
                    || GeoMath.distance(currentLocationInfo!.center, fix.coordinate) > 1_500 {
                    currentLocationInfo = await location.describe(fix.coordinate)
                }
            }
        }
        recomputeResolution()
        discover()
    }

    private func refreshResolutionForCity() async {
        if settings.preferGPSInsideCity && location.authorization.allowsLocation
            && !LocationResolver.isUsable(location.lastFix, now: Date()) {
            _ = try? await location.currentLocation(timeout: 6)
        }
        recomputeResolution()
        if case .gps(let fix) = resolution,
           currentLocationInfo == nil || GeoMath.distance(currentLocationInfo!.center, fix.coordinate) > 1_500 {
            currentLocationInfo = await location.describe(fix.coordinate)
        }
    }

    private func recomputeResolution() {
        let preference: CenterPreference
        if usesCurrentLocation || selectedCity == nil {
            preference = .currentLocation
        } else {
            preference = .city(selectedCity!, preferGPSInside: settings.preferGPSInsideCity)
        }
        var result = LocationResolver.resolve(preference: preference, authorization: location.authorization,
                                              fix: location.lastFix, locationFailed: location.lastRequestFailed,
                                              now: Date())
        // GPS unavailable or denied: fall back to the last selected city.
        if case .needsCity(let reason) = result, let city = selectedCity {
            result = .city(city, fallbackReason: reason)
        }
        resolution = result
    }

    private func makeArea() -> SearchArea? {
        switch resolution {
        case .gps(let fix):
            return SearchArea(center: fix.coordinate, radiusMeters: radiusMeters,
                              label: currentLocationInfo?.name ?? "Current location",
                              subtitle: currentLocationInfo?.subtitle, centerSource: .gps,
                              timeZoneIdentifier: currentLocationInfo?.timeZoneIdentifier ?? TimeZone.current.identifier,
                              countryCode: currentLocationInfo?.countryCode)
        case .city(let city, _):
            return SearchArea(center: city.center, radiusMeters: radiusMeters, label: city.name, subtitle: city.subtitle,
                              centerSource: .city, timeZoneIdentifier: city.timeZoneIdentifier, countryCode: city.countryCode)
        default:
            return nil
        }
    }

    // MARK: - Radius & filters

    func setRadius(_ meters: Double) {
        radiusMeters = GeoMath.clampRadius(meters)
        radiusTask?.cancel()
        radiusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.isDemo {
                self.loadDemo()
            } else {
                // Smaller radius → served locally from the cache; larger → new request.
                self.discover()
            }
        }
    }

    func toggle(_ category: DiscoveryCategory) {
        filter.toggle(category)
        settings.lastFilters = filter.selected
        visibleCount = Self.pageSize
        scheduleRank()
    }

    func clearFilters() {
        filter = CategoryFilter()
        settings.lastFilters = []
        visibleCount = Self.pageSize
        scheduleRank()
    }

    // MARK: - Discovery

    func refresh() async {
        guard !isDemo else { return }
        if usesCurrentLocation, location.authorization.allowsLocation {
            _ = try? await location.currentLocation()
            recomputeResolution()
        }
        discover(force: true)
        // Keep the pull-to-refresh spinner until the run finishes.
        await discoveryTask?.value
    }

    func discover(force: Bool = false) {
        guard !isDemo else { return }
        guard let newArea = makeArea() else {
            discoveryTask?.cancel()
            loadState = .idle
            return
        }
        let sameCentre = area.map { GeoMath.distance($0.center, newArea.center) < 50 } ?? false
        area = newArea
        settings.lastArea = newArea
        discoveryTask?.cancel()
        if !sameCentre {
            snapshot = nil
            feed = []
            visibleCount = Self.pageSize
            selectedEntry = nil
        }
        loadState = feed.isEmpty ? .loading : .refining
        let engine = self.engine
        discoveryTask = Task { [weak self] in
            for await update in engine.discover(area: newArea, forceRefresh: force) {
                guard !Task.isCancelled else { return }
                self?.apply(update, area: newArea)
            }
        }
    }

    private func apply(_ update: DiscoveryUpdate, area requested: SearchArea) {
        guard let area, area == requested else { return }
        var snapshot = update.snapshot
        // Keep the label current (reverse geocoding may finish after the run starts).
        snapshot.area = area
        self.snapshot = snapshot
        switch update.phase {
        case .initial, .expanded:
            loadState = snapshot.places.isEmpty && snapshot.events.isEmpty ? .loading : .refining
        case .complete, .cached:
            let osmFailed = snapshot.sourceStatuses[.openStreetMap]?.isFailure ?? false
            if snapshot.places.isEmpty && snapshot.events.isEmpty && osmFailed {
                loadState = .failed(failedSources.first?.message ?? "Discovery sources are unreachable.")
            } else {
                loadState = .loaded
            }
            if update.phase == .cached, Date().timeIntervalSince(snapshot.generatedAt) > 6 * 3600 {
                // Stale-while-revalidate: show cached results, refresh quietly.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self?.discover(force: true)
                }
            }
            if loadState == .loaded { recordHistory(snapshot) }
        }
        scheduleRank()
    }

    private func scheduleRank() {
        rankTask?.cancel()
        guard let snapshot, let area else {
            feed = []
            hotspots = []
            return
        }
        let filter = self.filter
        rankTask = Task { [weak self] in
            let (ranked, hotspots) = await Task.detached(priority: .userInitiated) {
                let ranked = FeedRanker().rank(places: snapshot.places, events: snapshot.events, area: area, filter: filter, now: Date())
                let visible = snapshot.places.filter { filter.matches($0) && area.contains($0.coordinate) }
                let themes = Hotspot.Theme.allCases.filter { filter.isShowingAll || filter.selected.contains($0.category) }
                return (ranked, HotspotDetector.detect(places: visible, themes: themes, limit: 3))
            }.value
            guard !Task.isCancelled, let self else { return }
            self.feed = ranked
            self.hotspots = hotspots
            if self.visibleCount > ranked.count { self.visibleCount = max(Self.pageSize, min(self.visibleCount, ranked.count)) }
        }
    }

    /// Progressive loading: reveal the next page when the user nears the end.
    func entryAppeared(_ entry: FeedEntry) {
        guard let index = feed.firstIndex(of: entry) else { return }
        if index >= visibleCount - 5 && visibleCount < feed.count {
            visibleCount = min(feed.count, visibleCount + Self.pageSize)
        }
    }

    // MARK: - History

    private func recordHistory(_ snapshot: DiscoverySnapshot) {
        guard !isDemo, recordedHistoryForArea != snapshot.area else { return }
        recordedHistoryForArea = snapshot.area
        let count = snapshot.places.count + snapshot.events.count
        let filters = filter.selected
        Task { [weak self] in
            guard let self else { return }
            await self.history.record(snapshot.area, resultCount: count, filters: filters, date: Date())
            await self.refreshHistory()
        }
    }

    func refreshHistory() async {
        historyEntries = await history.all()
    }

    func deleteHistory(_ entry: SearchHistoryEntry) async {
        await history.remove(id: entry.id)
        await refreshHistory()
    }

    func clearHistory() async {
        await history.clear()
        await refreshHistory()
    }

    // MARK: - Settings changes

    /// Rebuilds the engine when data-source settings change.
    func sourcesChanged() {
        let options = Self.options(from: settings)
        guard options != engineOptions else { return }
        engineOptions = options
        engine = AppEnvironment.makeEngine(options: options)
        details = PlaceDetailService(identity: settings.clientIdentity)
        Task {
            await ImagePipeline.shared.setUserAgent(options.identity.userAgent)
            await AppEnvironment.cache.clear()
            self.discover(force: true)
        }
    }

    func demoModeChanged() async {
        discoveryTask?.cancel()
        snapshot = nil
        feed = []
        area = nil
        selectedEntry = nil
        visibleCount = Self.pageSize
        if isDemo {
            loadDemo()
        } else {
            hasStarted = false
            loadState = .idle
            await start()
        }
    }

    func clearCache() async {
        await AppEnvironment.cache.clear()
        await ImagePipeline.shared.clearMemory()
        URLCache.shared.removeAllCachedResponses()
    }

    /// Fills the model with sample data (SwiftUI previews only).
    func loadPreviewData() {
        loadDemo()
    }

    private func loadDemo() {
        let center = selectedCity?.center ?? location.lastFix?.coordinate ?? SampleData.center
        let demo = SampleData.snapshot(around: center, radius: radiusMeters)
        area = demo.area
        snapshot = demo
        loadState = .loaded
        resolution = .city(CityChoice(name: "Sample City", subtitle: "Fictional data", center: center,
                                      timeZoneIdentifier: nil, countryCode: nil), fallbackReason: nil)
        scheduleRank()
    }
}
