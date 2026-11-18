import Foundation

/// Outbound links to platforms that offer no usable public API for this app.
///
/// TikTok (Research API: academic researchers only), Instagram (no public
/// search; Basic Display API shut down Dec 2024), Pinterest (no public pin
/// search for unapproved apps) and Reddit (self-service API access closed
/// Nov 2025) are therefore *not* queried. Instead, the app opens their own
/// search pages so the user can browse real, original content there.
struct ExternalLink: Identifiable, Hashable, Sendable {
    enum Platform: String, Hashable, Sendable, CaseIterable {
        case tiktok, instagram, reddit, youtube, pinterest, googleMaps, appleMaps, web, atlasObscura, openStreetMap, wikipedia, wikidata

        var title: String {
            switch self {
            case .tiktok: return "TikTok"
            case .instagram: return "Instagram"
            case .reddit: return "Reddit"
            case .youtube: return "YouTube"
            case .pinterest: return "Pinterest"
            case .googleMaps: return "Google Maps"
            case .appleMaps: return "Apple Maps"
            case .web: return "Web search"
            case .atlasObscura: return "Atlas Obscura"
            case .openStreetMap: return "OpenStreetMap"
            case .wikipedia: return "Wikipedia"
            case .wikidata: return "Wikidata"
            }
        }

        var symbolName: String {
            switch self {
            case .tiktok: return "music.note"
            case .instagram: return "camera"
            case .reddit: return "bubble.left.and.bubble.right"
            case .youtube: return "play.rectangle"
            case .pinterest: return "pin"
            case .googleMaps, .appleMaps: return "map"
            case .web: return "magnifyingglass"
            case .atlasObscura: return "globe.europe.africa"
            case .openStreetMap: return "map.circle"
            case .wikipedia: return "book"
            case .wikidata: return "barcode"
            }
        }
    }

    var platform: Platform
    var url: URL
    var subtitle: String

    var id: String { platform.rawValue + url.absoluteString }
}

enum ExternalLinkBuilder {
    private static func url(_ base: String, _ items: [String: String]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    /// Search links for a specific place.
    static func links(for place: Place, cityName: String?) -> [ExternalLink] {
        let city = cityName ?? place.address?.city ?? ""
        let query = [place.isNameInferred ? place.kind.label : place.name, city]
            .filter { !$0.isEmpty }.joined(separator: " ")
        var links: [ExternalLink] = []
        func add(_ platform: ExternalLink.Platform, _ url: URL?, _ subtitle: String) {
            if let url { links.append(ExternalLink(platform: platform, url: url, subtitle: subtitle)) }
        }
        add(.tiktok, url("https://www.tiktok.com/search", ["q": query]), "Videos about this place")
        add(.instagram, url("https://www.instagram.com/explore/search/keyword/", ["q": query]), "Posts (may require login)")
        add(.reddit, url("https://www.reddit.com/search/", ["q": query]), "Local discussions")
        add(.youtube, url("https://www.youtube.com/results", ["search_query": query]), "Video tours & reviews")
        add(.pinterest, url("https://www.pinterest.com/search/pins/", ["q": query]), "Aesthetic references")
        add(.googleMaps, url("https://www.google.com/maps/search/", [
            "api": "1",
            "query": place.isNameInferred
                ? String(format: "%.6f,%.6f", place.coordinate.latitude, place.coordinate.longitude)
                : "\(place.name) \(place.address?.singleLine ?? city)",
        ]), "Reviews, photos and current hours")
        add(.web, url("https://duckduckgo.com/", ["q": query + " blog"]), "Blogs and local magazines")
        if let osm = place.osmSource?.url {
            links.append(ExternalLink(platform: .openStreetMap, url: osm, subtitle: "View or correct the map data"))
        }
        if let wikidata = place.wikidataID, let url = URL(string: "https://www.wikidata.org/wiki/\(wikidata)") {
            links.append(ExternalLink(platform: .wikidata, url: url, subtitle: "Structured data"))
        }
        return links
    }

    /// City-level exploration links (hashtags and "hidden gems" searches).
    static func cityLinks(cityName: String) -> [ExternalLink] {
        let tag = TextMatching.tokens(cityName).joined()
        var links: [ExternalLink] = []
        func add(_ platform: ExternalLink.Platform, _ url: URL?, _ subtitle: String) {
            if let url { links.append(ExternalLink(platform: platform, url: url, subtitle: subtitle)) }
        }
        add(.tiktok, url("https://www.tiktok.com/search", ["q": "\(cityName) hidden gems"]), "Hidden gems in \(cityName)")
        if let tagURL = URL(string: "https://www.instagram.com/explore/tags/\(tag)vintage/") {
            add(.instagram, tagURL, "#\(tag)vintage")
        }
        add(.reddit, url("https://www.reddit.com/search/", ["q": "\(cityName) underground OR hidden OR thrift OR skate"]), "Local recommendations")
        add(.youtube, url("https://www.youtube.com/results", ["search_query": "\(cityName) alternative city guide"]), "Alternative city guides")
        add(.pinterest, url("https://www.pinterest.com/search/pins/", ["q": "\(cityName) aesthetic street photography"]), "Visual inspiration")
        add(.atlasObscura, url("https://www.atlasobscura.com/search", ["q": cityName]), "Curious places")
        return links
    }
}
