import Foundation

/// Reads event listings that venues publish on their own public websites
/// (schema.org JSON-LD). Respects robots.txt, reads at most a few pages per
/// discovery run, and follows at most one same-site "events/programme" link.
struct VenueEventsProvider: Sendable {
    static let agentToken = "Sidestreet"

    var client: HTTPClient
    var maxVenues = 10
    var maxConcurrent = 3

    private static let eventLinkPattern =
        "<a[^>]+href\\s*=\\s*[\"']([^\"'#]+)[\"'][^>]*>\\s*(?:<[^>]+>\\s*)*(events?|programm?e?|program|agenda|calendar|kalender|termine|veranstaltungen|concerts?|konzerte|shows|line-?up|exhibitions?|ausstellungen|what'?s on)\\b"

    /// Chooses which venues to check: event-prone kinds with a website, best score first.
    static func candidates(from places: [Place], limit: Int) -> [Place] {
        places
            .filter { $0.website != nil && $0.kind.publishesEvents && !$0.isSample }
            .sorted { ($0.score?.value ?? 0) > ($1.score?.value ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    func events(for venues: [Place], area: SearchArea, now: Date) async -> [DiscoveryEvent] {
        let selected = Array(venues.prefix(maxVenues))
        var results: [DiscoveryEvent] = []
        var index = 0
        while index < selected.count {
            let batch = selected[index..<min(index + maxConcurrent, selected.count)]
            index += maxConcurrent
            await withTaskGroup(of: [DiscoveryEvent].self) { group in
                for venue in batch {
                    group.addTask { (try? await self.events(for: venue, area: area, now: now)) ?? [] }
                }
                for await events in group { results += events }
            }
            if Task.isCancelled { break }
        }
        return results
    }

    func events(for venue: Place, area: SearchArea, now: Date) async throws -> [DiscoveryEvent] {
        guard let website = venue.website, let host = website.host else { return [] }
        guard try await isAllowed(url: website) else { throw NetworkError.blockedByRobots }
        let page = try await fetchHTML(website)
        var extracted = JSONLDEventExtractor.extract(html: page, pageURL: website, timeZone: area.timeZone, now: now)
        if extracted.isEmpty, let eventsURL = Self.eventsPageLink(in: page, base: website), eventsURL.host == host,
           eventsURL != website, try await isAllowed(url: eventsURL) {
            let eventsPage = try await fetchHTML(eventsURL)
            extracted = JSONLDEventExtractor.extract(html: eventsPage, pageURL: eventsURL, timeZone: area.timeZone, now: now)
        }
        return extracted.prefix(12).compactMap { Self.makeEvent($0, venue: venue, area: area, now: now) }
    }

    static func makeEvent(_ event: JSONLDEventExtractor.ExtractedEvent, venue: Place, area: SearchArea, now: Date) -> DiscoveryEvent? {
        // Location: explicit coordinates, else the venue itself when the event
        // names no other location or names the venue.
        var coordinate = event.coordinate
        var venueName: String? = event.locationName
        var placeID: String?
        let namesVenue = event.locationName.map { TextMatching.nameSimilarity($0, venue.name) >= 0.75 } ?? true
        if coordinate == nil && namesVenue {
            coordinate = venue.coordinate
            venueName = venue.name
            placeID = venue.id
        } else if let c = coordinate, GeoMath.distance(c, venue.coordinate) < 150 {
            placeID = venue.id
            venueName = venueName ?? venue.name
        }
        // Require a confirmed location: coordinates or a stated address.
        guard coordinate != nil || event.addressText != nil else { return nil }
        if let c = coordinate, !area.contains(c) { return nil }
        let kind = JSONLDEventExtractor.kind(for: event, venueKind: venue.kind)
        let identifier = (event.url?.absoluteString ?? event.name) + "@" + String(Int(event.start.timeIntervalSince1970))
        return DiscoveryEvent(
            id: "web:" + MD5.hex(identifier),
            title: event.name,
            kind: kind,
            start: event.start,
            end: event.end,
            isAllDay: event.isAllDay,
            recurrence: nil,
            venueName: venueName,
            venuePlaceID: placeID,
            coordinate: coordinate,
            addressText: event.addressText ?? (placeID != nil ? venue.address?.singleLine : nil),
            url: event.url ?? venue.website,
            imageURL: event.imageURL,
            summary: event.description,
            source: SourceRecord(provider: .venueWebsite, identifier: venue.website?.host ?? venue.id,
                                 url: event.url ?? venue.website, retrievedAt: now),
            confidence: .verified,
            timeZoneIdentifier: area.timeZoneIdentifier
        )
    }

    static func eventsPageLink(in html: String, base: URL) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: eventLinkPattern, options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: min(ns.length, 400_000))),
              match.numberOfRanges > 1 else { return nil }
        let href = ns.substring(with: match.range(at: 1))
        guard let url = URL(string: href, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private func fetchHTML(_ url: URL) async throws -> String {
        let request = HTTPRequest(url: url, headers: ["Accept": "text/html,application/xhtml+xml"], timeout: 12,
                                  maxBytes: 3 * 1024 * 1024)
        let response = try await client.sendChecked(request)
        if let type = response.header("Content-Type")?.lowercased(), !type.contains("html") { return "" }
        return String(decoding: response.data, as: UTF8.self)
    }

    private func isAllowed(url: URL) async throws -> Bool {
        guard let scheme = url.scheme, let host = url.host else { return false }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/robots.txt"
        guard let robotsURL = components.url else { return false }
        do {
            let response = try await client.send(HTTPRequest(url: robotsURL, timeout: 8, maxBytes: 512 * 1024))
            switch response.status {
            case 200..<300:
                let robots = RobotsTxt(String(decoding: response.data, as: UTF8.self))
                let path = url.path.isEmpty ? "/" : url.path
                return robots.isAllowed(path: path, agentToken: Self.agentToken)
            case 400..<500:
                return true // No robots.txt: crawling is permitted (RFC 9309).
            default:
                return false // Server error: be conservative.
            }
        } catch {
            return false
        }
    }
}

/// Turns recurring markets with a machine-readable OSM schedule into dated
/// upcoming events. Only schedules the `OpeningHours` parser fully
/// understands are used; nothing is inferred.
enum RecurringMarketEvents {
    static func events(from places: [Place], area: SearchArea, now: Date, days: Int = 31) -> [DiscoveryEvent] {
        var events: [DiscoveryEvent] = []
        for place in places where place.kind == .fleaMarket || place.kind == .market {
            guard let raw = place.openingHoursRaw, let hours = OpeningHours.parse(raw), !hours.isAlwaysOpen else { continue }
            // Daily markets are places, not events.
            let intervals = hours.upcomingIntervals(from: now, timeZone: area.timeZone, days: days)
            guard !intervals.isEmpty, intervals.count <= 10 else { continue }
            let recent = place.signals.lastConfirmed.map { now.timeIntervalSince($0) < 2 * 365 * 24 * 3600 } ?? false
            // Only the next date per market (the profile shows the full schedule).
            for interval in intervals.prefix(1) {
                let identifier = place.id + "@" + String(Int(interval.start.timeIntervalSince1970))
                events.append(DiscoveryEvent(
                    id: "osm-recurring:" + MD5.hex(identifier),
                    title: place.name,
                    kind: place.kind == .fleaMarket ? .fleaMarket : .market,
                    start: interval.start,
                    end: interval.end,
                    isAllDay: false,
                    recurrence: DiscoveryEvent.Recurrence(scheduleDescription: describe(hours, timeZone: area.timeZone, now: now), rule: raw),
                    venueName: place.name,
                    venuePlaceID: place.id,
                    coordinate: place.coordinate,
                    addressText: place.address?.singleLine,
                    url: place.website,
                    imageURL: place.primaryImage?.url,
                    summary: place.summary,
                    source: place.osmSource ?? SourceRecord(provider: .openStreetMap, identifier: place.id, url: nil, retrievedAt: now),
                    confidence: recent ? .verified : .partial,
                    timeZoneIdentifier: area.timeZoneIdentifier
                ))
            }
        }
        return events
    }

    static func describe(_ hours: OpeningHours, timeZone: TimeZone, now: Date) -> String {
        hours.weeklySchedule(containing: now, timeZone: timeZone)
            .filter { $0.text != "Closed" }
            .map { "\(OpeningHours.weekdayName($0.weekday)) \($0.text)" }
            .joined(separator: " · ")
    }
}
