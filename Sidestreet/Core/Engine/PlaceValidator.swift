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
        // Service companies (cleaning, caretaking, insurance …) are never shops,
        // cafés or venues, whatever a fuzzy search returned them for.
        if place.kind.isBusiness && looksLikeServiceBusiness(place.name) { return false }
        // Social-service offices (station missions, food banks, job centres)
        // aren't cultural or DIY spaces.
        if [.socialCentre, .communityCentre, .creativeHub, .hackerspace].contains(place.kind)
            && looksLikeSocialService(place.name) { return false }
        guard GeoMath.distance(place.coordinate, area.center) <= area.radiusMeters * 1.05 + 30 else { return false }
        guard !place.sources.isEmpty else { return false }
        return true
    }

    /// Distinctive (often compound) service-business words, matched anywhere
    /// in the folded name: "Hausmeisterservice", "Gebäudereinigung" …
    static let serviceCompoundFragments: [String] = [
        "hausmeister", "gartenpflege", "landschaftsbau", "gebaudereinigung", "glasreinigung", "entrumpelung",
        "versicherung", "immobilien", "hausverwaltung", "steuerberat", "rechtsanwalt", "zahnarzt", "arztpraxis",
        "physiotherap", "ergotherap", "fahrschule", "pflegedienst", "bestattung", "autohaus", "schlusseldienst",
        "schadlingsbekampf", "inkasso", "zeitarbeit", "personaldienst", "malerbetrieb", "dachdecker",
        "elektroinstall", "real estate", "estate agent", "law firm", "driving school", "car repair",
        "auto repair", "moving company", "pest control", "property management", "facility management", "lawn care",
    ]

    /// Short service words, matched only at the start of a word (so "Zebrastreifen"
    /// is not mistaken for a tyre shop).
    static let serviceWordPrefixes: [String] = [
        "reinigung", "umzug", "kanzlei", "notar", "kfz", "reifen", "sanitar", "heizung", "cleaning", "janitor",
        "gardening", "landscaping", "plumb", "locksmith", "insurance", "realty", "dentist", "dental", "attorney",
        "solicitor", "removals", "accountant", "staffing", "handyman", "nettoyage", "assurance", "immobilier",
        "notaire", "plombier", "serrurier", "demenagement", "limpieza", "seguros", "inmobiliaria", "pulizie",
        "assicurazion", "schoonmaak", "verzekering", "makelaar",
    ]

    static func looksLikeServiceBusiness(_ name: String) -> Bool {
        let tokens = TextMatching.tokens(name)
        let joined = tokens.joined(separator: " ")
        if serviceCompoundFragments.contains(where: { joined.contains($0) }) { return true }
        return tokens.contains { token in serviceWordPrefixes.contains { token.hasPrefix($0) } }
    }

    static let socialServiceFragments: [String] = [
        "bahnhofsmission", "caritas", "diakonie", "tafel", "jobcenter", "arbeitsagentur", "sozialamt", "jugendamt",
        "obdachlos", "wohnungslos", "suchtberatung", "drogenberatung", "schuldnerberatung", "seniorenheim", "altenheim",
        "pflegeheim", "kindergarten", "kita", "grundschule", "gymnasium", "realschule", "gemeindehaus", "pfarrheim",
        "pfarrzentrum", "kirchengemeinde", "food bank", "homeless", "job centre", "jobcentre", "care home",
        "nursing home", "kindergarten", "secours", "restos du coeur",
    ]

    static func looksLikeSocialService(_ name: String) -> Bool {
        let tokens = TextMatching.tokens(name)
        let joined = tokens.joined(separator: " ")
        return socialServiceFragments.contains { fragment in
            fragment.count >= 6 ? joined.contains(fragment) : tokens.contains { $0.hasPrefix(fragment) }
        }
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
