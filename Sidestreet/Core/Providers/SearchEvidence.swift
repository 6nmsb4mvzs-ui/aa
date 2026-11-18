import Foundation

/// Evidence a fuzzy map-search result must show before it is trusted as a
/// given kind of place. Apple Maps happily returns a cleaning company for
/// "thrift store"; requiring the right category and/or tell-tale words in the
/// name keeps such results out.
struct SearchEvidence: Sendable, Hashable {
    enum Mode: Sendable, Hashable {
        /// The result's POI category must be one of `categories`.
        case category
        /// The name must contain one of `nameFragments`.
        case name
        /// Either is enough.
        case nameOrCategory
    }

    var mode: Mode
    var categories: Set<String> = []
    var nameFragments: [String] = []

    func accepts(name: String, category: String?) -> Bool {
        let categoryOK = category.map { categories.contains($0) } ?? false
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
        let nameOK = nameFragments.contains { folded.contains($0) }
        switch mode {
        case .category: return categoryOK
        case .name: return nameOK
        case .nameOrCategory: return nameOK || categoryOK
        }
    }

    // Shared fragment lists (folded, lower-case, matched as substrings so
    // German compounds like "Plattenladen" or "Secondhandladen" count).
    static let thrift = ["second", "2nd", "secondhand", "thrift", "vintage", "trodel", "kilo", "fripe", "friperie", "charity",
                         "oxfam", "humana", "preloved", "pre-loved", "resale", "retro", "gebraucht", "flohmarkt",
                         "sozialkaufhaus", "kleiderkammer", "brocante", "rastro", "upcycl", "wiederverkauf", "zweite hand",
                         "2. hand", "zweiter hand", "2ten", "2te hand", "zweiten blick", "2. blick", "used",
                         "kleiderkreisel", "kleidertausch"]
    static let vintage = ["vintage", "retro", "second", "kilo", "archive", "fripe", "70s", "80s", "90s", "y2k", "secondhand"]
    static let skate = ["skate", "board"]
    static let records = ["record", "vinyl", "platten", "schallplatte", "disc", "disque", "music", "musik", "sound", "groove"]
    static let flea = ["floh", "flea", "trodel", "brocante", "puces", "rastro", "mercadillo", "mercatino", "bazar", "markt",
                       "market", "marche", "swap"]
    static let tattoo = ["tattoo", "tatau", "tatow", "ink", "piercing"]
    static let gallery = ["galerie", "gallery", "galleria", "galeria", "kunst", "art", "atelier", "studio"]
    static let roaster = ["roast", "rosterei", "rostrei", "torrefa", "tostad", "coffee", "kaffee", "espresso", "cafe"]
    static let vegan = ["vegan", "vegetar", "veggie", "plant"]
    static let comics = ["comic", "manga", "anime", "geek", "nerd"]
    static let music = ["club", "live", "music", "musik", "venue", "keller", "buhne", "stage", "halle", "konzert", "concert", "jazz"]
}
