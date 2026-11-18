import Foundation

/// Photos from Wikimedia Commons taken near a coordinate (free, no key).
/// Used lazily on place profiles. Results are labelled "nearby" because a
/// geotagged photo may show the surroundings rather than the place itself.
struct CommonsPhotoService: Sendable {
    var client: HTTPClient

    static func request(near coordinate: GeoCoordinate, radius: Int, limit: Int) -> HTTPRequest {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "format", value: "json"),
            .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "geosearch"),
            .init(name: "ggscoord", value: String(format: "%.6f|%.6f", coordinate.latitude, coordinate.longitude)),
            .init(name: "ggsradius", value: String(max(10, min(radius, 10_000)))),
            .init(name: "ggslimit", value: String(max(1, min(limit, 20)))),
            .init(name: "ggsnamespace", value: "6"),
            .init(name: "prop", value: "imageinfo"),
            .init(name: "iiprop", value: "url|extmetadata|mime"),
            .init(name: "iiurlwidth", value: "960"),
            .init(name: "iiextmetadatafilter", value: "Artist|LicenseShortName|ObjectName"),
        ]
        return HTTPRequest(url: components.url!, headers: ["Accept": "application/json"], timeout: 20)
    }

    private struct Response: Decodable {
        struct Query: Decodable { var pages: [Page]? }
        struct Page: Decodable {
            var title: String
            var index: Int?
            var imageinfo: [ImageInfo]?
        }
        struct ImageInfo: Decodable {
            var thumburl: String?
            var descriptionurl: String?
            var mime: String?
            var extmetadata: [String: Meta]?
        }
        struct Meta: Decodable { var value: String? }
        var query: Query?
    }

    func photos(near coordinate: GeoCoordinate, radius: Int = 60, limit: Int = 8) async throws -> [PlaceImage] {
        let response = try await client.sendChecked(Self.request(near: coordinate, radius: radius, limit: limit))
        return try Self.parse(response.data)
    }

    static func parse(_ data: Data) throws -> [PlaceImage] {
        let decoded: Response
        do { decoded = try JSONDecoder().decode(Response.self, from: data) } catch {
            throw NetworkError.decoding("Commons")
        }
        let pages = (decoded.query?.pages ?? []).sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        return pages.compactMap { page -> PlaceImage? in
            guard let info = page.imageinfo?.first, let thumb = info.thumburl, let url = URL(string: thumb),
                  let mime = info.mime, mime.hasPrefix("image/"), mime != "image/svg+xml" else { return nil }
            let artist = info.extmetadata?["Artist"]?.value.map(HTMLText.plain)
            let license = info.extmetadata?["LicenseShortName"]?.value
            return PlaceImage(url: url, pageURL: info.descriptionurl.flatMap(URL.init(string:)),
                              attribution: artist.map { "\($0) / Wikimedia Commons" } ?? "Wikimedia Commons",
                              license: license, provider: .wikimediaCommons, origin: .nearby)
        }
    }
}

/// Short article summaries from Wikipedia's REST API (free, no key).
struct WikipediaSummaryService: Sendable {
    var client: HTTPClient

    struct Summary: Sendable, Hashable {
        var title: String
        var extract: String
        var pageURL: URL?
        var thumbnail: URL?
    }

    private struct Response: Decodable {
        struct Thumb: Decodable { var source: String }
        struct URLs: Decodable { struct Page: Decodable { var page: String }; var mobile: Page? ; var desktop: Page? }
        var title: String
        var extract: String?
        var type: String?
        var thumbnail: Thumb?
        var content_urls: URLs?
    }

    /// `reference` is an OSM-style "lang:Title" (default language: en).
    static func request(reference: String) -> HTTPRequest? {
        var language = "en"
        var title = reference
        if let colon = reference.firstIndex(of: ":"), reference.distance(from: reference.startIndex, to: colon) <= 3 {
            language = String(reference[..<colon]).lowercased()
            title = String(reference[reference.index(after: colon)...])
        }
        guard language.allSatisfy({ $0.isLetter || $0 == "-" }), !title.isEmpty else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let encoded = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { return nil }
        return HTTPRequest(url: url, headers: ["Accept": "application/json"], timeout: 15)
    }

    func summary(reference: String) async throws -> Summary? {
        guard let request = Self.request(reference: reference) else { return nil }
        let response = try await client.send(request)
        if response.status == 404 { return nil }
        guard (200..<300).contains(response.status) else { throw NetworkError.httpStatus(response.status) }
        return try Self.parse(response.data)
    }

    static func parse(_ data: Data) throws -> Summary? {
        let decoded: Response
        do { decoded = try JSONDecoder().decode(Response.self, from: data) } catch {
            throw NetworkError.decoding("Wikipedia")
        }
        guard decoded.type != "disambiguation", let extract = decoded.extract, !extract.isEmpty else { return nil }
        return Summary(title: decoded.title, extract: extract,
                       pageURL: (decoded.content_urls?.mobile?.page ?? decoded.content_urls?.desktop?.page).flatMap(URL.init(string:)),
                       thumbnail: decoded.thumbnail.flatMap { URL(string: $0.source) })
    }
}

/// Tiny HTML-to-text helper (strips tags, decodes common entities).
enum HTMLText {
    static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = string
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
                     "&ldquo;": "“", "&rdquo;": "”", "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&szlig;": "ß",
                     "&eacute;": "é", "&egrave;": "è", "&agrave;": "à", "&ccedil;": "ç"]
        for (entity, replacement) in named { result = result.replacingOccurrences(of: entity, with: replacement) }
        // Numeric entities.
        let pattern = "&#(x?[0-9a-fA-F]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = result as NSString
        var output = ""
        var last = 0
        for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let body = ns.substring(with: match.range(at: 1))
            let value = body.hasPrefix("x") || body.hasPrefix("X") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            if let value, let scalar = Unicode.Scalar(value) {
                output.unicodeScalars.append(scalar)
            } else {
                output += ns.substring(with: match.range)
            }
            last = match.range.location + match.range.length
        }
        output += ns.substring(from: last)
        return output
    }
}
