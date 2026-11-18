import Foundation

/// A past search, stored locally on the device only.
struct SearchHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var label: String
    var subtitle: String?
    var center: GeoCoordinate
    var radiusMeters: Double
    var centerSource: CenterSource
    var timeZoneIdentifier: String?
    var countryCode: String?
    var date: Date
    var resultCount: Int
    var filters: [DiscoveryCategory]

    var area: SearchArea {
        SearchArea(center: center, radiusMeters: radiusMeters, label: label, subtitle: subtitle,
                   centerSource: centerSource, timeZoneIdentifier: timeZoneIdentifier, countryCode: countryCode)
    }
}

/// Persists search history as a small JSON file in Application Support.
/// Never leaves the device.
actor SearchHistoryStore {
    private let fileURL: URL?
    private let maxEntries: Int
    private var entries: [SearchHistoryEntry]?

    init(fileURL: URL?, maxEntries: Int = 100) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
    }

    static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SearchHistory.json")
    }

    private func load() -> [SearchHistoryEntry] {
        if let entries { return entries }
        var loaded: [SearchHistoryEntry] = []
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            loaded = (try? decoder.decode([SearchHistoryEntry].self, from: data)) ?? []
        }
        entries = loaded
        return loaded
    }

    func all() -> [SearchHistoryEntry] {
        load().sorted { $0.date > $1.date }
    }

    /// Records a search. A repeated search of the same place (same label and
    /// centre within 1 km) updates the existing entry instead of duplicating.
    @discardableResult
    func record(_ area: SearchArea, resultCount: Int, filters: Set<DiscoveryCategory>, date: Date) -> SearchHistoryEntry {
        var list = load()
        let entry: SearchHistoryEntry
        if let index = list.firstIndex(where: {
            $0.label == area.label && GeoMath.distance($0.center, area.center) < 1_000
        }) {
            list[index].date = date
            list[index].radiusMeters = area.radiusMeters
            list[index].resultCount = resultCount
            list[index].filters = filters.sorted { $0.rawValue < $1.rawValue }
            list[index].center = area.center
            entry = list[index]
        } else {
            entry = SearchHistoryEntry(
                id: UUID(), label: area.label, subtitle: area.subtitle, center: area.center,
                radiusMeters: area.radiusMeters, centerSource: area.centerSource,
                timeZoneIdentifier: area.timeZoneIdentifier, countryCode: area.countryCode,
                date: date, resultCount: resultCount, filters: filters.sorted { $0.rawValue < $1.rawValue }
            )
            list.append(entry)
        }
        list.sort { $0.date > $1.date }
        if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
        save(list)
        return entry
    }

    func remove(id: UUID) {
        save(load().filter { $0.id != id })
    }

    func clear() {
        save([])
    }

    private func save(_ list: [SearchHistoryEntry]) {
        entries = list
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(list).write(to: fileURL, options: [.atomic])
            #if os(iOS)
            // Keep history strictly on this device (not in iCloud backups).
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = fileURL
            try? url.setResourceValues(values)
            #endif
        } catch {
            // History persistence is best-effort; in-memory state stays correct.
        }
    }
}
