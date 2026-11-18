import Foundation

/// Extracts schema.org `Event` objects published as JSON-LD on a web page.
///
/// Many venues (clubs, galleries, cinemas, markets) embed machine-readable
/// event data for search engines. Only events with an explicit `startDate`
/// are accepted, and dates are taken verbatim from the page — never guessed.
enum JSONLDEventExtractor {
    struct ExtractedEvent: Hashable, Sendable {
        var name: String
        var start: Date
        var end: Date?
        var isAllDay: Bool
        var url: URL?
        var imageURL: URL?
        var locationName: String?
        var addressText: String?
        var coordinate: GeoCoordinate?
        var description: String?
        var typeName: String
    }

    static func extract(html: String, pageURL: URL, timeZone: TimeZone, now: Date,
                        horizon: TimeInterval = 120 * 24 * 3600) -> [ExtractedEvent] {
        var events: [ExtractedEvent] = []
        for block in jsonLDBlocks(in: html) {
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            for object in eventObjects(in: json) {
                guard let event = parseEvent(object, pageURL: pageURL, timeZone: timeZone) else { continue }
                let effectiveEnd = event.end ?? (event.isAllDay ? event.start.addingTimeInterval(24 * 3600) : event.start.addingTimeInterval(3 * 3600))
                guard effectiveEnd >= now, event.start <= now.addingTimeInterval(horizon) else { continue }
                events.append(event)
            }
        }
        // De-duplicate (pages often repeat the same event in several blocks).
        var seen = Set<String>()
        return events.filter { seen.insert($0.name.lowercased() + "|" + String(Int($0.start.timeIntervalSince1970))).inserted }
            .sorted { $0.start < $1.start }
    }

    static func jsonLDBlocks(in html: String) -> [String] {
        let pattern = "<script[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            var body = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix("<!--") { body = String(body.dropFirst(4)) }
            if body.hasSuffix("-->") { body = String(body.dropLast(3)) }
            if body.hasPrefix("//<![CDATA[") { body = String(body.dropFirst(11)) }
            if body.hasSuffix("//]]>") { body = String(body.dropLast(5)) }
            return body
        }
    }

    private static let eventTypes: Set<String> = [
        "event", "musicevent", "exhibitionevent", "festival", "socialevent", "saleevent", "screeningevent",
        "theaterevent", "danceevent", "comedyevent", "visualartsevent", "literaryevent", "sportsevent",
        "childrensevent", "educationevent", "foodevent", "businessevent", "publicationevent",
    ]

    static func typeNames(_ object: [String: Any]) -> [String] {
        if let type = object["@type"] as? String { return [type] }
        if let types = object["@type"] as? [String] { return types }
        return []
    }

    static func eventObjects(in json: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 6 else { return [] }
        if let array = json as? [Any] {
            return array.flatMap { eventObjects(in: $0, depth: depth + 1) }
        }
        guard let object = json as? [String: Any] else { return [] }
        var found: [[String: Any]] = []
        if typeNames(object).contains(where: { eventTypes.contains($0.lowercased()) }) {
            found.append(object)
        }
        for key in ["@graph", "event", "events", "subEvent", "itemListElement", "item", "mainEntity"] {
            if let nested = object[key] { found += eventObjects(in: nested, depth: depth + 1) }
        }
        return found
    }

    static func parseEvent(_ object: [String: Any], pageURL: URL, timeZone: TimeZone) -> ExtractedEvent? {
        guard let rawName = (object["name"] as? String) ?? (object["headline"] as? String) else { return nil }
        let name = HTMLText.plain(rawName)
        guard !name.isEmpty, name.count < 200 else { return nil }
        if let status = object["eventStatus"] as? String {
            let lower = status.lowercased()
            if lower.contains("cancel") || lower.contains("postpon") || lower.contains("movedonline") { return nil }
        }
        guard let startString = object["startDate"] as? String,
              let (start, startAllDay) = parseDate(startString, timeZone: timeZone) else { return nil }
        var end: Date?
        var endAllDay = startAllDay
        if let endString = object["endDate"] as? String, let (parsedEnd, allDay) = parseDate(endString, timeZone: timeZone) {
            // A date-only end date means "until the end of that day".
            end = allDay ? parsedEnd.addingTimeInterval(24 * 3600 - 1) : parsedEnd
            endAllDay = allDay
            if let e = end, e < start { end = nil }
        }
        var url: URL?
        if let urlString = object["url"] as? String {
            url = URL(string: urlString, relativeTo: pageURL)?.absoluteURL
        }
        if let scheme = url?.scheme?.lowercased(), scheme != "https" && scheme != "http" { url = nil }
        var imageURL: URL?
        if let image = object["image"] as? String {
            imageURL = URL(string: image, relativeTo: pageURL)?.absoluteURL
        } else if let images = object["image"] as? [Any], let first = images.first {
            if let s = first as? String { imageURL = URL(string: s, relativeTo: pageURL)?.absoluteURL }
            if let o = first as? [String: Any], let s = o["url"] as? String { imageURL = URL(string: s, relativeTo: pageURL)?.absoluteURL }
        } else if let image = object["image"] as? [String: Any], let s = image["url"] as? String {
            imageURL = URL(string: s, relativeTo: pageURL)?.absoluteURL
        }
        if imageURL?.scheme?.lowercased() != "https" { imageURL = nil }

        var locationName: String?
        var addressText: String?
        var coordinate: GeoCoordinate?
        let location: [String: Any]? = (object["location"] as? [String: Any]) ?? ((object["location"] as? [Any])?.first as? [String: Any])
        if let location {
            if typeNames(location).contains(where: { $0.lowercased() == "virtuallocation" }) { return nil }
            locationName = (location["name"] as? String).map(HTMLText.plain)
            if let address = location["address"] as? String {
                addressText = HTMLText.plain(address)
            } else if let address = location["address"] as? [String: Any] {
                let parts = ["streetAddress", "postalCode", "addressLocality"].compactMap { address[$0] as? String }
                addressText = parts.isEmpty ? nil : parts.map(HTMLText.plain).joined(separator: ", ")
            }
            if let geo = location["geo"] as? [String: Any],
               let lat = number(geo["latitude"]), let lon = number(geo["longitude"]) {
                let c = GeoCoordinate(latitude: lat, longitude: lon)
                if c.isValid { coordinate = c }
            }
        } else if let locationString = object["location"] as? String {
            locationName = HTMLText.plain(locationString)
        }
        let description = (object["description"] as? String).map(HTMLText.plain).map { String($0.prefix(400)) }
        let typeName = typeNames(object).first ?? "Event"
        return ExtractedEvent(name: name, start: start, end: end, isAllDay: startAllDay && endAllDay, url: url,
                              imageURL: imageURL, locationName: locationName, addressText: addressText,
                              coordinate: coordinate, description: description, typeName: typeName)
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// Parses ISO 8601 dates as used in schema.org: date-only, local
    /// date-time (interpreted in the venue's time zone) or with offset.
    static func parseDate(_ value: String, timeZone: TimeZone) -> (Date, Bool)? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 10 else { return nil }
        let withOffset = ISO8601DateFormatter()
        withOffset.formatOptions = [.withInternetDateTime]
        if let date = withOffset.date(from: trimmed) { return (date, false) }
        withOffset.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withOffset.date(from: trimmed) { return (date, false) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let datePart = String(trimmed.prefix(10))
        let ymd = datePart.split(separator: "-").compactMap { Int($0) }
        guard ymd.count == 3, (2000...2100).contains(ymd[0]), (1...12).contains(ymd[1]), (1...31).contains(ymd[2]) else { return nil }
        var comps = DateComponents(year: ymd[0], month: ymd[1], day: ymd[2])
        if trimmed.count == 10 {
            guard let date = calendar.date(from: comps) else { return nil }
            return (date, true)
        }
        // Local time without offset: "2026-11-21T20:00" or "2026-11-21 20:00:00".
        let timePart = trimmed.dropFirst(11).prefix(8)
        let hms = timePart.split(separator: ":").compactMap { Int($0) }
        guard hms.count >= 2, (0...23).contains(hms[0]), (0...59).contains(hms[1]) else { return nil }
        comps.hour = hms[0]
        comps.minute = hms[1]
        comps.second = hms.count > 2 ? hms[2] : 0
        guard let date = calendar.date(from: comps) else { return nil }
        return (date, false)
    }

    /// Maps a schema.org type and text to an event kind.
    static func kind(for event: ExtractedEvent, venueKind: PlaceKind?) -> DiscoveryEvent.Kind {
        let type = event.typeName.lowercased()
        let text = [event.name, event.description ?? ""].joined(separator: " ")
        if TextMatching.containsAny(text, keywords: SubcultureLexicon.fleaMarketKeywords) > 0 && TextMatching.containsAny(text, keywords: ["market", "markt", "marche", "mercado", "fair", "flea", "swap", "sale"]) > 0 {
            return .fleaMarket
        }
        if TextMatching.containsAny(text, keywords: ["skate*", "bowl jam", "best trick"]) > 0 { return .skate }
        if TextMatching.containsAny(text, keywords: ["pop up", "popup", "pop-up", "sample sale"]) > 0 { return .popUp }
        if type.contains("music") || type.contains("dance") || type == "festival" { return .music }
        if type.contains("exhibition") || type.contains("visualarts") { return .exhibition }
        if type.contains("sale") { return .popUp }
        switch venueKind {
        case .musicVenue?, .nightclub?, .recordStore?: return .music
        case .gallery?, .creativeHub?, .museum?: return .exhibition
        case .fleaMarket?: return .fleaMarket
        case .market?: return .market
        case .skatepark?, .diySkatepark?, .skateShop?: return .skate
        default: return .cultural
        }
    }
}
