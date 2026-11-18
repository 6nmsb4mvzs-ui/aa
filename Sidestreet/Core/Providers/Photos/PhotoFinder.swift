import Foundation

/// Extracts a web page's own preview image (Open Graph / Twitter card /
/// `image_src`) — the picture a business chose to represent itself, the
/// same one shown in link previews in messaging apps.
enum WebPreviewImage {
    private static let metaKeys = ["og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src"]

    static func imageURL(in html: String, pageURL: URL) -> URL? {
        let head = String(html.prefix(300_000))
        var found: [String: String] = [:]
        for tag in tags(named: "meta", in: head) {
            let attributes = attributes(of: tag)
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  metaKeys.contains(key), let content = attributes["content"], !content.isEmpty else { continue }
            if found[key] == nil { found[key] = content }
        }
        var candidates = metaKeys.compactMap { found[$0] }
        for tag in tags(named: "link", in: head) {
            let attributes = attributes(of: tag)
            if attributes["rel"]?.lowercased() == "image_src", let href = attributes["href"] { candidates.append(href) }
        }
        candidates += jsonLDImages(in: head)
        for candidate in candidates {
            if let url = usableImageURL(HTMLText.decodeEntities(candidate), base: pageURL) { return url }
        }
        // Many small-business sites have no preview tags: use the first real photo on the page.
        for tag in tags(named: "img", in: String(html.prefix(600_000))) {
            let attributes = attributes(of: tag)
            guard let src = attributes["src"] ?? attributes["data-src"] ?? attributes["data-lazy-src"] else { continue }
            let lower = src.lowercased()
            guard lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".webp") else { continue }
            if let width = attributes["width"].flatMap({ Int($0) }), width < 300 { continue }
            if let height = attributes["height"].flatMap({ Int($0) }), height < 200 { continue }
            if let url = usableImageURL(HTMLText.decodeEntities(src), base: pageURL) { return url }
        }
        return nil
    }

    /// `image` values of schema.org business/organisation JSON-LD blocks.
    static func jsonLDImages(in html: String) -> [String] {
        var images: [String] = []
        for block in JSONLDEventExtractor.jsonLDBlocks(in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            var stack: [Any] = [json]
            while let item = stack.popLast(), images.count < 3 {
                if let array = item as? [Any] { stack += array; continue }
                guard let object = item as? [String: Any] else { continue }
                if let graph = object["@graph"] { stack.append(graph) }
                if let image = object["image"] as? String { images.append(image) }
                if let image = object["image"] as? [String: Any], let url = image["url"] as? String { images.append(url) }
                if let list = object["image"] as? [Any] {
                    for entry in list.prefix(2) {
                        if let url = entry as? String { images.append(url) }
                        if let o = entry as? [String: Any], let url = o["url"] as? String { images.append(url) }
                    }
                }
            }
        }
        return images
    }

    /// Absolute https URL of a raster image (http is upgraded; icons are skipped).
    static func usableImageURL(_ raw: String, base: URL) -> URL? {
        guard var url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL else {
            return nil
        }
        if url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https" // iOS blocks plain-http image loads
            if let upgraded = components.url { url = upgraded }
        }
        guard url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        let lower = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        let host = url.host?.lowercased() ?? ""
        let blockedHosts = ["gravatar.com", "secure.gravatar.com", "ui-avatars.com", "facebook.com", "fbcdn.net", "googleusercontent.com"]
        if blockedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return nil }
        let iconWords = ["favicon", "logo", "icon", "sprite", "avatar", "badge", "placeholder", "spacer", "pixel", "payment",
                         "cookie", "emoji", "flag"]
        if iconWords.contains(where: { path.contains($0) }) || lower.contains("favicon")
            || path.hasSuffix(".svg") || path.hasSuffix(".ico") || path.hasSuffix(".gif") {
            return nil
        }
        return url
    }

    private static func tags(named name: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func attributes(of tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')") else {
            return [:]
        }
        let ns = tag as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let valueRange = match.range(at: 3).location != NSNotFound ? match.range(at: 3) : match.range(at: 4)
            guard valueRange.location != NSNotFound else { continue }
            result[key] = ns.substring(with: valueRange)
        }
        return result
    }
}

/// Panoramax: open, community street-level imagery (free, no key).
/// Searches for a picture *looking at* the place.
struct PanoramaxService: Sendable {
    var client: HTTPClient

    static func request(lookingAt coordinate: GeoCoordinate) -> HTTPRequest {
        var components = URLComponents(string: "https://api.panoramax.xyz/api/search")!
        components.queryItems = [
            .init(name: "place_position", value: String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude)),
            .init(name: "place_distance", value: "2-25"),
            .init(name: "limit", value: "1"),
        ]
        return HTTPRequest(url: components.url!, headers: ["Accept": "application/geo+json, application/json"], timeout: 15)
    }

    private struct Response: Decodable {
        struct Feature: Decodable {
            struct Asset: Decodable { var href: String }
            struct Provider: Decodable { var name: String?; var roles: [String]? }
            var id: String
            var assets: [String: Asset]?
            var providers: [Provider]?
            var properties: [String: JSONValue]?
        }
        var features: [Feature]
    }

    /// Minimal JSON value to read optional string properties.
    enum JSONValue: Decodable {
        case string(String), other
        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) { self = .string(value) } else { self = .other }
        }
        var string: String? { if case .string(let s) = self { return s }; return nil }
    }

    func picture(lookingAt coordinate: GeoCoordinate) async throws -> PlaceImage? {
        let response = try await client.sendChecked(Self.request(lookingAt: coordinate))
        return Self.parse(response.data)
    }

    static func parse(_ data: Data) -> PlaceImage? {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data), let feature = decoded.features.first,
              let href = feature.assets?["sd"]?.href ?? feature.assets?["thumb"]?.href,
              let url = URL(string: href), url.scheme == "https" else { return nil }
        let author = feature.providers?.last(where: { $0.roles?.contains("producer") ?? false })?.name
        let license = feature.properties?["license"]?.string
        return PlaceImage(url: url, pageURL: URL(string: "https://api.panoramax.xyz/#focus=pic&pic=\(feature.id)"),
                          attribution: author.map { "\($0) / Panoramax" } ?? "Panoramax",
                          license: license, provider: .panoramax, origin: .streetLevel)
    }
}

/// Caches robots.txt per host so repeated page reads stay polite and cheap.
actor RobotsCache {
    private var entries: [String: RobotsTxt?] = [:]

    func robots(for url: URL, client: HTTPClient) async -> RobotsTxt? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let key = scheme + "://" + host
        if let cached = entries[key] { return cached }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/robots.txt"
        var result: RobotsTxt?
        if let robotsURL = components.url,
           let response = try? await client.send(HTTPRequest(url: robotsURL, timeout: 8, maxBytes: 512 * 1024)) {
            switch response.status {
            case 200..<300: result = RobotsTxt(String(decoding: response.data, as: UTF8.self))
            case 400..<500: result = RobotsTxt("") // no robots.txt: allowed (RFC 9309)
            default: result = nil // server error: be conservative
            }
        }
        entries[key] = .some(result)
        return result
    }
}

/// Reads public web pages politely: robots.txt is respected, size is capped.
struct WebPageFetcher: Sendable {
    static let agentToken = "Sidestreet"
    static let sharedRobots = RobotsCache()

    var client: HTTPClient
    var robots: RobotsCache = WebPageFetcher.sharedRobots

    func isAllowed(_ url: URL) async -> Bool {
        guard let robots = await robots.robots(for: url, client: client) else { return false }
        return robots.isAllowed(path: url.path.isEmpty ? "/" : url.path, agentToken: Self.agentToken)
    }

    func html(at url: URL, maxBytes: Int = 3 * 1024 * 1024) async throws -> String {
        guard await isAllowed(url) else { throw NetworkError.blockedByRobots }
        let request = HTTPRequest(url: url, headers: ["Accept": "text/html,application/xhtml+xml"], timeout: 12, maxBytes: maxBytes)
        let response = try await client.sendChecked(request)
        if let type = response.header("Content-Type")?.lowercased(), !type.contains("html") { return "" }
        return String(decoding: response.data, as: UTF8.self)
    }
}

/// Finds a photo for places that have none, trying (in order):
/// 1. the place's own website preview image,
/// 2. a geotagged Wikimedia Commons photo (public art, architecture,
///    viewpoints — where a nearby photo usually shows the place itself),
/// 3. a Panoramax street-level picture looking at the place.
/// Results (including "nothing found") are cached on disk for a week.
actor PhotoFinder {
    struct Options: Sendable, Hashable {
        var website = true
        var commons = true
        var streetLevel = true
        /// Optional personal Mapillary access token (street-level photos).
        var mapillaryToken: String? = nil
    }

    private struct CacheEntry: Codable {
        var image: PlaceImage?
        var date: Date
    }

    private let client: HTTPClient
    private let fetcher: WebPageFetcher
    private let cacheFile: URL?
    private let clock: @Sendable () -> Date
    private var cache: [String: CacheEntry] = [:]
    private var loaded = false
    private var inFlight: [String: Task<PlaceImage?, Never>] = [:]
    private var active = 0
    private let maxConcurrent = 3
    private var dirty = 0

    init(client: HTTPClient, cacheFile: URL?, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.fetcher = WebPageFetcher(client: client)
        self.cacheFile = cacheFile
        self.clock = clock
    }

    static func defaultCacheFile() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("PhotoFinder.json")
    }

    /// Kinds where a photo geotagged a few metres away usually shows the place.
    static func nearbyPhotosDepictPlace(_ kind: PlaceKind) -> Bool {
        switch kind.primaryCategory {
        case .streetArt, .architecture, .photo, .nature, .hiddenGems, .skate: return true
        default: return kind == .museum || kind == .market || kind == .fleaMarket
        }
    }

    func cachedPhoto(for place: Place) -> PlaceImage?? {
        loadIfNeeded()
        guard let entry = cache[place.id], !isExpired(entry) else { return nil }
        return .some(entry.image)
    }

    func photo(for place: Place, options: Options) async -> PlaceImage? {
        if let linked = place.primaryImage { return linked }
        if let cached = cachedPhoto(for: place) { return cached }
        if let task = inFlight[place.id] { return await task.value }
        let task = Task<PlaceImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.lookup(place, options: options)
        }
        inFlight[place.id] = task
        let image = await task.value
        inFlight[place.id] = nil
        if !Task.isCancelled {
            cache[place.id] = CacheEntry(image: image, date: clock())
            dirty += 1
            if dirty >= 5 { save() }
        }
        return image
    }

    func flush() { if dirty > 0 { save() } }

    func clear() {
        cache.removeAll()
        if let cacheFile { try? FileManager.default.removeItem(at: cacheFile) }
    }

    private func isExpired(_ entry: CacheEntry) -> Bool {
        let ttl: TimeInterval = entry.image == nil ? 2 * 86_400 : 7 * 86_400
        return clock().timeIntervalSince(entry.date) > ttl
    }

    private func lookup(_ place: Place, options: Options) async -> PlaceImage? {
        await acquire()
        defer { release() }
        if Task.isCancelled { return nil }
        if options.website, let website = place.website, place.kind.isBusiness || place.kind.publishesEvents {
            if let image = await websiteImage(website) { return image }
        }
        if options.commons && Self.nearbyPhotosDepictPlace(place.kind) {
            if let image = try? await CommonsPhotoService(client: client).photos(near: place.coordinate, radius: 35, limit: 3).first {
                return image
            }
        }
        if options.streetLevel {
            if let token = options.mapillaryToken, !token.isEmpty,
               let image = try? await MapillaryService(client: client, token: token).picture(lookingAt: place.coordinate) {
                return image
            }
            if let image = try? await PanoramaxService(client: client).picture(lookingAt: place.coordinate) {
                return image
            }
        }
        return nil
    }

    func websiteImage(_ website: URL) async -> PlaceImage? {
        guard let html = try? await fetcher.html(at: website, maxBytes: 2 * 1024 * 1024), !html.isEmpty,
              let url = WebPreviewImage.imageURL(in: html, pageURL: website) else { return nil }
        return PlaceImage(url: url, pageURL: website, attribution: website.host.map { "Image: \($0)" },
                          license: nil, provider: .venueWebsite, origin: .linked)
    }

    private func acquire() async {
        while active >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        active += 1
    }

    private func release() { active = max(0, active - 1) }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let cacheFile, let data = try? Data(contentsOf: cacheFile),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else { return }
        cache = decoded.filter { !isExpired($0.value) }
    }

    private func save() {
        dirty = 0
        guard let cacheFile else { return }
        if cache.count > 3_000 {
            let newest = cache.sorted { $0.value.date > $1.value.date }.prefix(2_000)
            cache = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFile, options: .atomic)
        }
    }
}

/// Optional Mapillary street-level photos (free personal access token).
/// Picks a recent, non-panoramic picture taken 4–45 m away whose camera
/// faces the place. Imagery © Mapillary contributors, CC BY-SA 4.0.
struct MapillaryService: Sendable {
    var client: HTTPClient
    var token: String

    struct Candidate: Decodable, Sendable {
        struct Geometry: Decodable, Sendable { var coordinates: [Double] }
        struct Creator: Decodable, Sendable { var username: String? }
        var id: String
        var thumb_1024_url: String?
        var computed_compass_angle: Double?
        var compass_angle: Double?
        var computed_geometry: Geometry?
        var geometry: Geometry?
        var captured_at: Double?
        var is_pano: Bool?
        var creator: Creator?
    }

    private struct Response: Decodable { var data: [Candidate] }

    func request(near coordinate: GeoCoordinate) -> HTTPRequest {
        var components = URLComponents(string: "https://graph.mapillary.com/images")!
        components.queryItems = [
            .init(name: "fields", value: "id,thumb_1024_url,computed_compass_angle,compass_angle,computed_geometry,geometry,captured_at,is_pano,creator"),
            .init(name: "lat", value: String(format: "%.6f", coordinate.latitude)),
            .init(name: "lng", value: String(format: "%.6f", coordinate.longitude)),
            .init(name: "radius", value: "45"),
            .init(name: "limit", value: "30"),
        ]
        return HTTPRequest(url: components.url!, headers: ["Authorization": "OAuth \(token)", "Accept": "application/json"], timeout: 15)
    }

    func picture(lookingAt coordinate: GeoCoordinate) async throws -> PlaceImage? {
        guard !token.isEmpty else { throw NetworkError.notConfigured("Mapillary token") }
        let response = try await client.sendChecked(request(near: coordinate))
        guard let decoded = try? JSONDecoder().decode(Response.self, from: response.data) else { throw NetworkError.decoding("Mapillary") }
        return Self.best(decoded.data, target: coordinate)
    }

    /// Initial bearing (degrees) from `a` to `b`.
    static func bearing(from a: GeoCoordinate, to b: GeoCoordinate) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func best(_ candidates: [Candidate], target: GeoCoordinate) -> PlaceImage? {
        var bestScore = -Double.infinity
        var best: (Candidate, URL)?
        for candidate in candidates where candidate.is_pano != true {
            guard let urlString = candidate.thumb_1024_url, let url = URL(string: urlString), url.scheme == "https",
                  let coords = (candidate.computed_geometry ?? candidate.geometry)?.coordinates, coords.count == 2,
                  let heading = candidate.computed_compass_angle ?? candidate.compass_angle else { continue }
            let position = GeoCoordinate(latitude: coords[1], longitude: coords[0])
            let distance = GeoMath.distance(position, target)
            guard distance >= 4, distance <= 45 else { continue }
            var difference = abs(bearing(from: position, to: target) - heading).truncatingRemainder(dividingBy: 360)
            if difference > 180 { difference = 360 - difference }
            guard difference <= 50 else { continue } // camera must face the place
            let ageYears = candidate.captured_at.map { (Date().timeIntervalSince1970 - $0 / 1000) / (365 * 86_400) } ?? 5
            let score = -difference / 50 - distance / 45 - min(ageYears, 10) / 10
            if score > bestScore {
                bestScore = score
                best = (candidate, url)
            }
        }
        guard let (candidate, url) = best else { return nil }
        let author = candidate.creator?.username
        return PlaceImage(url: url, pageURL: URL(string: "https://www.mapillary.com/app/?pKey=\(candidate.id)"),
                          attribution: author.map { "\($0) / Mapillary" } ?? "Mapillary", license: "CC BY-SA 4.0",
                          provider: .mapillary, origin: .streetLevel)
    }
}
