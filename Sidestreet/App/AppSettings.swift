import Foundation
import Observation

/// User preferences, stored locally in UserDefaults. Nothing is synced.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let defaultRadius = "settings.defaultRadius"
        static let useMetric = "settings.useMetric"
        static let showNicheScore = "settings.showNicheScore"
        static let appleMaps = "settings.source.appleMaps"
        static let wikidata = "settings.source.wikidata"
        static let venueEvents = "settings.source.venueEvents"
        static let nearbyPhotos = "settings.source.nearbyPhotos"
        static let lookAround = "settings.lookAround"
        static let backgroundRefresh = "settings.backgroundRefresh"
        static let preferGPSInsideCity = "settings.preferGPSInsideCity"
        static let demoMode = "settings.demoMode"
        static let contact = "settings.userAgentContact"
        static let lastArea = "state.lastArea"
        static let lastCity = "state.lastCity"
        static let usesCurrentLocation = "state.usesCurrentLocation"
        static let filters = "state.filters"
    }

    private let defaults: UserDefaults

    // Each setting persists on change. The explicit observation calls make
    // SwiftUI update when a setting changes.
    @ObservationIgnored private var _defaultRadiusMeters: Double
    var defaultRadiusMeters: Double {
        get { access(keyPath: \.defaultRadiusMeters); return _defaultRadiusMeters }
        set {
            withMutation(keyPath: \.defaultRadiusMeters) { _defaultRadiusMeters = newValue }
            defaults.set(newValue, forKey: Key.defaultRadius)
        }
    }

    @ObservationIgnored private var _useMetric: Bool
    var useMetric: Bool {
        get { access(keyPath: \.useMetric); return _useMetric }
        set {
            withMutation(keyPath: \.useMetric) { _useMetric = newValue }
            defaults.set(newValue, forKey: Key.useMetric)
        }
    }

    @ObservationIgnored private var _showNicheScore: Bool
    var showNicheScore: Bool {
        get { access(keyPath: \.showNicheScore); return _showNicheScore }
        set {
            withMutation(keyPath: \.showNicheScore) { _showNicheScore = newValue }
            defaults.set(newValue, forKey: Key.showNicheScore)
        }
    }

    @ObservationIgnored private var _appleMapsEnabled: Bool
    var appleMapsEnabled: Bool {
        get { access(keyPath: \.appleMapsEnabled); return _appleMapsEnabled }
        set {
            withMutation(keyPath: \.appleMapsEnabled) { _appleMapsEnabled = newValue }
            defaults.set(newValue, forKey: Key.appleMaps)
        }
    }

    @ObservationIgnored private var _wikidataEnabled: Bool
    var wikidataEnabled: Bool {
        get { access(keyPath: \.wikidataEnabled); return _wikidataEnabled }
        set {
            withMutation(keyPath: \.wikidataEnabled) { _wikidataEnabled = newValue }
            defaults.set(newValue, forKey: Key.wikidata)
        }
    }

    @ObservationIgnored private var _venueEventsEnabled: Bool
    var venueEventsEnabled: Bool {
        get { access(keyPath: \.venueEventsEnabled); return _venueEventsEnabled }
        set {
            withMutation(keyPath: \.venueEventsEnabled) { _venueEventsEnabled = newValue }
            defaults.set(newValue, forKey: Key.venueEvents)
        }
    }

    @ObservationIgnored private var _nearbyPhotosEnabled: Bool
    var nearbyPhotosEnabled: Bool {
        get { access(keyPath: \.nearbyPhotosEnabled); return _nearbyPhotosEnabled }
        set {
            withMutation(keyPath: \.nearbyPhotosEnabled) { _nearbyPhotosEnabled = newValue }
            defaults.set(newValue, forKey: Key.nearbyPhotos)
        }
    }

    @ObservationIgnored private var _lookAroundEnabled: Bool
    var lookAroundEnabled: Bool {
        get { access(keyPath: \.lookAroundEnabled); return _lookAroundEnabled }
        set {
            withMutation(keyPath: \.lookAroundEnabled) { _lookAroundEnabled = newValue }
            defaults.set(newValue, forKey: Key.lookAround)
        }
    }

    @ObservationIgnored private var _backgroundRefreshEnabled: Bool
    var backgroundRefreshEnabled: Bool {
        get { access(keyPath: \.backgroundRefreshEnabled); return _backgroundRefreshEnabled }
        set {
            withMutation(keyPath: \.backgroundRefreshEnabled) { _backgroundRefreshEnabled = newValue }
            defaults.set(newValue, forKey: Key.backgroundRefresh)
        }
    }

    @ObservationIgnored private var _preferGPSInsideCity: Bool
    var preferGPSInsideCity: Bool {
        get { access(keyPath: \.preferGPSInsideCity); return _preferGPSInsideCity }
        set {
            withMutation(keyPath: \.preferGPSInsideCity) { _preferGPSInsideCity = newValue }
            defaults.set(newValue, forKey: Key.preferGPSInsideCity)
        }
    }

    @ObservationIgnored private var _demoMode: Bool
    var demoMode: Bool {
        get { access(keyPath: \.demoMode); return _demoMode }
        set {
            withMutation(keyPath: \.demoMode) { _demoMode = newValue }
            defaults.set(newValue, forKey: Key.demoMode)
        }
    }

    @ObservationIgnored private var _userAgentContact: String
    var userAgentContact: String {
        get { access(keyPath: \.userAgentContact); return _userAgentContact }
        set {
            withMutation(keyPath: \.userAgentContact) { _userAgentContact = newValue }
            defaults.set(newValue, forKey: Key.contact)
        }
    }


    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.defaultRadius: SearchRadius.defaultMeters,
            Key.useMetric: Locale.current.measurementSystem != .us,
            Key.showNicheScore: true,
            Key.appleMaps: true,
            Key.wikidata: true,
            Key.venueEvents: true,
            Key.nearbyPhotos: true,
            Key.lookAround: true,
            Key.backgroundRefresh: true,
            Key.preferGPSInsideCity: true,
            Key.demoMode: false,
            Key.usesCurrentLocation: true,
        ])
        _defaultRadiusMeters = GeoMath.clampRadius(defaults.double(forKey: Key.defaultRadius))
        _useMetric = defaults.bool(forKey: Key.useMetric)
        _showNicheScore = defaults.bool(forKey: Key.showNicheScore)
        _appleMapsEnabled = defaults.bool(forKey: Key.appleMaps)
        _wikidataEnabled = defaults.bool(forKey: Key.wikidata)
        _venueEventsEnabled = defaults.bool(forKey: Key.venueEvents)
        _nearbyPhotosEnabled = defaults.bool(forKey: Key.nearbyPhotos)
        _lookAroundEnabled = defaults.bool(forKey: Key.lookAround)
        _backgroundRefreshEnabled = defaults.bool(forKey: Key.backgroundRefresh)
        _preferGPSInsideCity = defaults.bool(forKey: Key.preferGPSInsideCity)
        _demoMode = defaults.bool(forKey: Key.demoMode)
        _userAgentContact = defaults.string(forKey: Key.contact) ?? ""
    }

    var clientIdentity: ClientIdentity {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return ClientIdentity(appVersion: version, contact: userAgentContact.isEmpty ? nil : userAgentContact)
    }

    // MARK: Session state (last search, for restore and background refresh)

    var usesCurrentLocation: Bool {
        get { defaults.bool(forKey: Key.usesCurrentLocation) }
        set { defaults.set(newValue, forKey: Key.usesCurrentLocation) }
    }

    var lastCity: CityChoice? {
        get { decode(CityChoice.self, key: Key.lastCity) }
        set { encode(newValue, key: Key.lastCity) }
    }

    var lastFilters: Set<DiscoveryCategory> {
        get { Set(decode([DiscoveryCategory].self, key: Key.filters) ?? []) }
        set { encode(Array(newValue), key: Key.filters) }
    }

    /// The last searched area (centre + radius). Read by background refresh.
    nonisolated static func storedLastArea(defaults: UserDefaults = .standard) -> SearchArea? {
        guard let data = defaults.data(forKey: Key.lastArea) else { return nil }
        return try? JSONDecoder().decode(SearchArea.self, from: data)
    }

    nonisolated static func backgroundRefreshAllowed(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.backgroundRefresh) as? Bool ?? true
    }

    var lastArea: SearchArea? {
        get { decode(SearchArea.self, key: Key.lastArea) }
        set { encode(newValue, key: Key.lastArea) }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func resetSessionState() {
        defaults.removeObject(forKey: Key.lastArea)
        defaults.removeObject(forKey: Key.lastCity)
        defaults.removeObject(forKey: Key.filters)
    }
}
