import Foundation

/// Data validation applied to every place and event before it can reach the
/// feed. Rejects broken records rather than repairing them with guesses.
enum PlaceValidator {
    private static let placeholderNames: Set<String> = [
        "unknown", "n/a", "na", "none", "null", "test", "fixme", "todo", "tbd", "noname", "no name", "?", "-",
    ]

    static func isValid(_ place: Place, area: SearchArea) -> Bool {
        guard !place.isSample else { return false } // sample data never mixes with real results
        guard place.coordinate.isValid else { return false }
        guard isValidName(place.name) else { return false }
        guard GeoMath.distance(place.coordinate, area.center) <= area.radiusMeters * 1.05 + 30 else { return false }
        guard !place.sources.isEmpty else { return false }
        return true
    }

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 160 else { return false }
        guard trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return false }
        return !placeholderNames.contains(trimmed.lowercased())
    }

    static func isValid(_ event: DiscoveryEvent, area: SearchArea, now: Date) -> Bool {
        guard !event.isSample else { return false }
        guard isValidName(event.title) else { return false }
        guard event.isUpcoming(now: now) else { return false }
        guard event.start <= now.addingTimeInterval(180 * 24 * 3600) else { return false }
        if let end = event.end, end < event.start { return false }
        if let coordinate = event.coordinate {
            guard coordinate.isValid, area.contains(coordinate) else { return false }
        } else {
            guard let address = event.addressText, !address.isEmpty else { return false }
        }
        return true
    }

    /// Cleans fields that are present but unusable.
    static func sanitize(_ place: Place) -> Place {
        var p = place
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let summary = p.summary {
            let cleaned = HTMLText.plain(summary)
            p.summary = cleaned.isEmpty || cleaned.lowercased() == p.name.lowercased() ? nil : String(cleaned.prefix(600))
        }
        if let website = p.website, let scheme = website.scheme?.lowercased(), scheme != "http" && scheme != "https" {
            p.website = nil
        }
        p.images = p.images.filter { $0.url.scheme?.lowercased() == "https" }
        return p
    }
}
