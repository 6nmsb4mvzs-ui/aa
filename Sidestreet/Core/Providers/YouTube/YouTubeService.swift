import Foundation

/// Optional YouTube Data API v3 integration.
///
/// Requires the user's own free API key (Google Cloud project, YouTube Data
/// API v3 enabled; default quota 10,000 units/day, one search = 100 units, so
/// roughly 100 searches per day). Without a key the app only offers outbound
/// YouTube search links.
struct YouTubeService: Sendable {
    struct Video: Hashable, Sendable, Identifiable, Codable {
        var id: String
        var title: String
        var channel: String
        var publishedAt: Date?
        var thumbnail: URL?

        var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
    }

    var client: HTTPClient
    var apiKey: String
    /// Sent so that keys restricted to this iOS app in Google Cloud work.
    var bundleIdentifier: String?

    private struct Response: Decodable {
        struct Item: Decodable {
            struct ID: Decodable { var videoId: String? }
            struct Snippet: Decodable {
                struct Thumbs: Decodable {
                    struct Thumb: Decodable { var url: String }
                    var medium: Thumb?
                    var high: Thumb?
                    var `default`: Thumb?
                }
                var title: String
                var channelTitle: String
                var publishedAt: String?
                var thumbnails: Thumbs?
            }
            var id: ID
            var snippet: Snippet
        }
        var items: [Item]
    }

    private struct ErrorResponse: Decodable {
        struct Inner: Decodable {
            struct Reason: Decodable { var reason: String? }
            var code: Int
            var errors: [Reason]?
        }
        var error: Inner
    }

    enum ServiceError: Error, Equatable, LocalizedError {
        case quotaExceeded
        case invalidKey

        var errorDescription: String? {
            switch self {
            case .quotaExceeded: return "Daily YouTube quota used up. It resets at midnight Pacific Time."
            case .invalidKey: return "The YouTube API key was rejected. Check it in Settings."
            }
        }
    }

    func request(query: String, maxResults: Int) -> HTTPRequest? {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            .init(name: "maxResults", value: String(max(1, min(maxResults, 25)))),
            .init(name: "q", value: query),
            .init(name: "safeSearch", value: "moderate"),
            .init(name: "key", value: apiKey),
        ]
        guard let url = components.url else { return nil }
        var headers = ["Accept": "application/json"]
        if let bundleIdentifier { headers["X-Ios-Bundle-Identifier"] = bundleIdentifier }
        return HTTPRequest(url: url, headers: headers, timeout: 15)
    }

    func search(_ query: String, maxResults: Int = 6) async throws -> [Video] {
        guard !apiKey.isEmpty else { throw NetworkError.notConfigured("YouTube API key") }
        guard let request = request(query: query, maxResults: maxResults) else { throw NetworkError.invalidResponse }
        let response = try await client.send(request)
        guard (200..<300).contains(response.status) else {
            if let error = try? JSONDecoder().decode(ErrorResponse.self, from: response.data) {
                let reasons = (error.error.errors ?? []).compactMap(\.reason)
                if reasons.contains(where: { $0.contains("quota") || $0 == "dailyLimitExceeded" }) { throw ServiceError.quotaExceeded }
                if reasons.contains(where: { $0.contains("keyInvalid") || $0 == "forbidden" || $0.contains("accessNotConfigured") }) || error.error.code == 400 {
                    throw ServiceError.invalidKey
                }
            }
            throw NetworkError.httpStatus(response.status)
        }
        return try Self.parse(response.data)
    }

    static func parse(_ data: Data) throws -> [Video] {
        let decoded: Response
        do { decoded = try JSONDecoder().decode(Response.self, from: data) } catch {
            throw NetworkError.decoding("YouTube")
        }
        let formatter = ISO8601DateFormatter()
        return decoded.items.compactMap { item in
            guard let id = item.id.videoId else { return nil }
            let thumbs = item.snippet.thumbnails
            let thumb = thumbs?.high?.url ?? thumbs?.medium?.url ?? thumbs?.default?.url
            return Video(id: id, title: HTMLText.decodeEntities(item.snippet.title),
                         channel: HTMLText.decodeEntities(item.snippet.channelTitle),
                         publishedAt: item.snippet.publishedAt.flatMap { formatter.date(from: $0) },
                         thumbnail: thumb.flatMap(URL.init(string:)))
        }
    }

    /// Number of videos whose titles mention the place name — used as a
    /// "local buzz" signal. Generic names are not counted.
    static func mentionCount(of placeName: String, in videos: [Video]) -> Int {
        let target = TextMatching.normalizedName(placeName)
        guard target.count >= 4 else { return 0 }
        return videos.filter { TextMatching.normalizedName($0.title).contains(target) }.count
    }
}
