import Foundation

/// Temporary cache for discovery results, to avoid repeating network requests.
///
/// - Entries expire (default 24 h for places; events are re-validated on read
///   so expired events are never served as upcoming).
/// - A cached area can answer a request for a *smaller or equal* radius
///   around (almost) the same centre by filtering locally.
/// - Stored in the Caches directory, which iOS may purge; size is bounded.
///   This is deliberately not an offline library.
actor DiscoveryCache {
    struct Entry: Codable, Sendable {
        var snapshot: DiscoverySnapshot
        var storedAt: Date
    }

    private let directory: URL?
    private let clock: @Sendable () -> Date
    private let timeToLive: TimeInterval
    private let maxEntries: Int
    /// A cached centre within this distance counts as the same centre.
    let centerTolerance: Double
    private var memory: [String: Entry] = [:]
    private var loadedIndex = false

    init(directory: URL?, timeToLive: TimeInterval = 24 * 3600, maxEntries: Int = 12,
         centerTolerance: Double = 250, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.timeToLive = timeToLive
        self.maxEntries = maxEntries
        self.centerTolerance = centerTolerance
        self.clock = clock
    }

    /// Default on-disk location inside the app's Caches directory.
    static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DiscoveryCache", isDirectory: true)
    }

    static func key(for area: SearchArea) -> String {
        // Round to ~100 m so tiny GPS jitter maps to the same file.
        let lat = (area.center.latitude * 1000).rounded() / 1000
        let lon = (area.center.longitude * 1000).rounded() / 1000
        return String(format: "%.3f_%.3f_%05d", lat, lon, Int(area.radiusMeters.rounded()))
    }

    private func loadIndexIfNeeded() {
        guard !loadedIndex else { return }
        loadedIndex = true
        guard let directory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(Entry.self, from: data) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            memory[file.deletingPathExtension().lastPathComponent] = entry
        }
    }

    /// A fresh cached snapshot that covers `area`, restricted to it.
    func lookup(_ area: SearchArea) -> DiscoverySnapshot? {
        loadIndexIfNeeded()
        let now = clock()
        var best: (key: String, entry: Entry)?
        for (key, entry) in memory {
            guard now.timeIntervalSince(entry.storedAt) < timeToLive else { continue }
            let cachedArea = entry.snapshot.area
            let offset = GeoMath.distance(cachedArea.center, area.center)
            guard offset <= centerTolerance, cachedArea.radiusMeters >= area.radiusMeters + offset else { continue }
            if best == nil || entry.storedAt > best!.entry.storedAt { best = (key, entry) }
        }
        guard let best else { return nil }
        var snapshot = best.entry.snapshot.restricted(to: area, now: now)
        snapshot.isFromCache = true
        snapshot.generatedAt = best.entry.storedAt
        return snapshot
    }

    /// Age of the newest entry covering the area (nil if none).
    func age(of area: SearchArea) -> TimeInterval? {
        guard let snapshot = lookup(area) else { return nil }
        return clock().timeIntervalSince(snapshot.generatedAt)
    }

    func store(_ snapshot: DiscoverySnapshot) {
        loadIndexIfNeeded()
        let key = Self.key(for: snapshot.area)
        var stored = snapshot
        stored.isFromCache = false
        let entry = Entry(snapshot: stored, storedAt: clock())
        memory[key] = entry
        persist(entry, key: key)
        enforceLimits()
    }

    func purgeExpired() {
        loadIndexIfNeeded()
        let now = clock()
        for (key, entry) in memory where now.timeIntervalSince(entry.storedAt) >= timeToLive {
            remove(key)
        }
    }

    func clear() {
        memory.removeAll()
        loadedIndex = true
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    var entryCount: Int {
        loadIndexIfNeeded()
        return memory.count
    }

    func diskSize() -> Int {
        guard let directory else { return 0 }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { total, file in
            total + ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func enforceLimits() {
        guard memory.count > maxEntries else { return }
        let sorted = memory.sorted { $0.value.storedAt < $1.value.storedAt }
        for (key, _) in sorted.prefix(memory.count - maxEntries) { remove(key) }
    }

    private func remove(_ key: String) {
        memory.removeValue(forKey: key)
        if let directory { try? FileManager.default.removeItem(at: directory.appendingPathComponent(key + ".json")) }
    }

    private func persist(_ entry: Entry, key: String) {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: directory.appendingPathComponent(key + ".json"), options: .atomic)
        } catch {
            // Cache writes are best-effort.
        }
    }
}

/// Small time-limited key/value cache for profile lookups (Wikipedia
/// summaries, nearby photos, YouTube results). Memory only.
actor ResponseCache<Value: Sendable> {
    private var storage: [String: (value: Value, expires: Date)] = [:]
    private let ttl: TimeInterval
    private let maxCount: Int
    private let clock: @Sendable () -> Date

    init(ttl: TimeInterval, maxCount: Int = 200, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl
        self.maxCount = maxCount
        self.clock = clock
    }

    func value(for key: String) -> Value? {
        guard let entry = storage[key] else { return nil }
        if entry.expires < clock() {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func set(_ value: Value, for key: String) {
        if storage.count >= maxCount, let oldest = storage.min(by: { $0.value.expires < $1.value.expires })?.key {
            storage.removeValue(forKey: oldest)
        }
        storage[key] = (value, clock().addingTimeInterval(ttl))
    }

    func removeAll() { storage.removeAll() }
}
