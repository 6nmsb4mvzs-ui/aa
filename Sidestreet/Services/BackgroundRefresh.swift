import BackgroundTasks
import Foundation

/// Periodic cache refresh using iOS background app refresh.
///
/// iOS decides when (and whether) to run this; there is no guaranteed
/// interval. The task re-fetches the *last searched area* so the feed opens
/// warm. It never uses location services in the background — the stored
/// centre is reused as-is.
enum BackgroundRefresh {
    static let taskIdentifier = "app.sidestreet.cache-refresh"

    static func schedule() {
        guard AppSettings.backgroundRefreshAllowed(), AppSettings.storedLastArea() != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    /// Runs inside the background task window (~30 s).
    static func perform() async {
        schedule() // keep the chain going
        guard AppSettings.backgroundRefreshAllowed(), let area = AppSettings.storedLastArea() else { return }
        let defaults = UserDefaults.standard
        let contact = defaults.string(forKey: "settings.userAgentContact")
        let identity = ClientIdentity(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                                      contact: (contact?.isEmpty ?? true) ? nil : contact)
        // Lightweight: OSM + Wikidata only (no third-party websites in the background).
        let engine = AppEnvironment.makeEngine(options: .init(
            appleMaps: false,
            wikidata: defaults.object(forKey: "settings.source.wikidata") as? Bool ?? true,
            venueEvents: false,
            identity: identity
        ))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await engine.refresh(area: area) }
            group.addTask { try? await Task.sleep(nanoseconds: 25_000_000_000) }
            // Whichever finishes first ends the window.
            await group.next()
            group.cancelAll()
        }
        await AppEnvironment.cache.purgeExpired()
    }
}
