import Foundation

/// Name normalisation and fuzzy matching used for duplicate detection.
enum TextMatching {
    /// Generic words that carry no identity ("Café X" == "X Café").
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "of", "le", "la", "les", "der", "die", "das", "el", "los", "las", "il",
        "cafe", "caffe", "coffee", "kaffee", "bar", "pub", "shop", "store", "laden", "boutique",
        "restaurant", "gmbh", "ltd", "llc", "inc", "co", "kg", "sarl", "srl", "bv", "ug", "e.v", "ev",
    ]

    /// Lower-cased, diacritic-free, punctuation-free token list.
    static func tokens(_ string: String) -> [String] {
        let folded = string
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "ß", with: "ss")
        var tokens: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Normalised name used as a matching key (stop words removed; if a name
    /// consists only of stop words, they are kept).
    static func normalizedName(_ string: String) -> String {
        let all = tokens(string)
        let significant = all.filter { !stopWords.contains($0) }
        return (significant.isEmpty ? all : significant).joined(separator: " ")
    }

    /// Jaro–Winkler similarity (0…1).
    static func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1), b = Array(s2)
        if a.isEmpty && b.isEmpty { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let matchDistance = max(0, max(a.count, b.count) / 2 - 1)
        var aMatches = [Bool](repeating: false, count: a.count)
        var bMatches = [Bool](repeating: false, count: b.count)
        var matches = 0
        for i in 0..<a.count {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, b.count)
            if start >= end { continue }
            for j in start..<end where !bMatches[j] && a[i] == b[j] {
                aMatches[i] = true
                bMatches[j] = true
                matches += 1
                break
            }
        }
        if matches == 0 { return 0 }
        var transpositions = 0
        var k = 0
        for i in 0..<a.count where aMatches[i] {
            while !bMatches[k] { k += 1 }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(a.count) + m / Double(b.count) + (m - Double(transpositions) / 2) / m) / 3
        var prefix = 0
        for i in 0..<min(4, min(a.count, b.count)) {
            if a[i] == b[i] { prefix += 1 } else { break }
        }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }

    /// Token-set similarity: |A∩B| / |A∪B| on significant tokens.
    static func tokenJaccard(_ s1: String, _ s2: String) -> Double {
        let a = Set(normalizedName(s1).split(separator: " "))
        let b = Set(normalizedName(s2).split(separator: " "))
        if a.isEmpty || b.isEmpty { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    /// Combined name similarity in 0…1, robust to word order and generic words.
    static func nameSimilarity(_ s1: String, _ s2: String) -> Double {
        let n1 = normalizedName(s1)
        let n2 = normalizedName(s2)
        if n1.isEmpty || n2.isEmpty { return 0 }
        if n1 == n2 { return 1 }
        let jw = jaroWinkler(n1, n2)
        let jaccard = tokenJaccard(s1, s2)
        // Containment ("Kaffee Burger" vs "Kaffee Burger Bar Berlin").
        let shorter = n1.count <= n2.count ? n1 : n2
        let longer = n1.count <= n2.count ? n2 : n1
        let containment: Double = (shorter.count >= 5 && longer.contains(shorter)) ? 0.9 : 0
        return max(jw * 0.9 + jaccard * 0.1, jaccard, containment)
    }

    /// Case- and diacritic-insensitive keyword search.
    static func containsAny(_ text: String, keywords: [String]) -> Int {
        let haystack = " " + tokens(text).joined(separator: " ") + " "
        var hits = 0
        for keyword in keywords {
            let needle = tokens(keyword).joined(separator: " ")
            guard !needle.isEmpty else { continue }
            if keyword.hasSuffix("*") {
                if haystack.contains(" " + needle) { hits += 1 }
            } else if haystack.contains(" " + needle + " ") {
                hits += 1
            }
        }
        return hits
    }
}

/// Keyword lists used to detect alternative / subculture relevance.
/// Multilingual where the words differ (thrift = Trödel = fripe = rastro …).
enum SubcultureLexicon {
    static let keywords: [String] = [
        "vintage", "thrift", "second hand", "secondhand", "preloved", "pre loved", "retro", "kilo*",
        "fripe*", "trodel*", "flohmarkt", "brocante", "rastro", "rastrillo", "mercatino", "loppis",
        "kirpputori", "vlooienmarkt", "swap", "upcycl*", "y2k", "archive",
        "skate*", "board shop", "boardshop", "bmx", "graffiti", "graff", "street art", "streetart", "mural",
        "spray", "zine*", "diy", "punk", "hardcore", "metal", "indie", "underground", "techno", "house music",
        "dub", "reggae", "hip hop", "hiphop", "rap", "vinyl", "records", "schallplatten", "disquaire", "plattenladen",
        "kollektiv", "collective", "cooperative", "genossenschaft", "co op", "squat", "autonom*",
        "queer", "lgbt*", "hackerspace", "makerspace", "fablab", "atelier", "studio", "analog*", "film lab",
        "comic*", "manga", "anime", "arcade", "retro gaming", "pinball", "flipper", "tattoo", "piercing",
        "third wave", "specialty coffee", "roaster*", "rosterei", "torrefacteur", "vegan", "kombucha",
        "brutalis*", "plattenbau", "modernis*", "neon", "rooftop", "warehouse", "industrial",
    ]

    /// Keywords indicating a local / community orientation.
    static let communityKeywords: [String] = [
        "kollektiv", "collective", "cooperative", "genossenschaft", "co op", "community", "kiez",
        "nachbarschaft", "neighbourhood", "neighborhood", "verein", "association", "asso", "social",
        "solidar*", "free shop", "umsonstladen", "repair cafe", "volunteer",
    ]

    /// Flea-market words in several languages, used to classify markets.
    static let fleaMarketKeywords: [String] = [
        "flea", "flohmarkt", "floh", "trodel*", "brocante", "puces", "vide grenier", "rastro", "rastrillo",
        "mercatino", "mercadillo", "vlooienmarkt", "rommelmarkt", "loppis", "kirpputori", "bazar", "car boot",
        "boot sale", "swap meet", "vintage", "antique*", "antik*", "second hand", "secondhand", "pchli",
        "blecha", "bolhapiac", "rommel", "kilo",
    ]
}
