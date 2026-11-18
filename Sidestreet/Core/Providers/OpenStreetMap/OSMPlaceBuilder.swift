import Foundation

/// Raw Overpass JSON.
struct OverpassResponse: Decodable, Sendable {
    struct Element: Decodable, Sendable {
        struct Center: Decodable, Sendable {
            var lat: Double
            var lon: Double
        }

        var type: String
        var id: Int64
        var lat: Double?
        var lon: Double?
        var center: Center?
        var tags: [String: String]?

        var coordinate: GeoCoordinate? {
            if let lat, let lon { return GeoCoordinate(latitude: lat, longitude: lon) }
            if let center { return GeoCoordinate(latitude: center.lat, longitude: center.lon) }
            return nil
        }
    }

    var elements: [Element]
    var remark: String?
}

/// Turns OpenStreetMap tags into `Place` values. Classification rules are
/// ordered from most to least specific. Features that are private,
/// disused, abandoned or permanently closed are rejected — the app never
/// points people at places they cannot legally enter.
enum OSMPlaceBuilder {
    static func place(from element: OverpassResponse.Element, retrievedAt: Date) -> Place? {
        guard let tags = element.tags, let coordinate = element.coordinate, coordinate.isValid else { return nil }
        guard !isExcluded(tags) else { return nil }
        guard let kind = classify(tags) else { return nil }

        let rawName = (tags["name"] ?? tags["name:en"] ?? tags["brand"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        var name: String
        var inferred = false
        if let rawName, !rawName.isEmpty {
            name = rawName
        } else if let inferredName = inferredName(for: kind, tags: tags) {
            name = inferredName
            inferred = true
        } else {
            return nil // Unnamed businesses are too unreliable to show.
        }
        if name.count > 120 { name = String(name.prefix(120)) }

        let osmType = element.type
        let identifier = "\(osmType)/\(element.id)"
        let source = SourceRecord(
            provider: .openStreetMap,
            identifier: identifier,
            url: URL(string: "https://www.openstreetmap.org/\(identifier)"),
            retrievedAt: retrievedAt
        )

        var categories = Set(kind.categories)
        let descriptors = descriptors(for: tags, kind: kind)
        if descriptors.contains("late-night") && (kind.primaryCategory == .food || kind.primaryCategory == .cafes) {
            categories.insert(.food)
        }

        var place = Place(
            id: "osm:\(identifier)",
            name: name,
            isNameInferred: inferred,
            coordinate: coordinate,
            kind: kind,
            categories: categories,
            descriptors: descriptors
        )
        place.address = address(from: tags)
        place.openingHoursRaw = tags["opening_hours"].flatMap { $0.isEmpty ? nil : $0 }
        place.website = website(from: tags)
        place.phone = tags["phone"] ?? tags["contact:phone"]
        place.summary = tags["description"] ?? tags["description:en"]
        place.images = images(from: tags)
        place.brand = brand(from: tags)
        place.wikidataID = tags["wikidata"].flatMap { $0.hasPrefix("Q") ? $0 : nil }
        place.wikipediaTitle = tags["wikipedia"]
        place.price = price(from: tags, kind: kind, brand: place.brand)
        place.sources = [source]

        var signals = PlaceSignals()
        signals.isTouristAttraction = tags["tourism"] == "attraction" || tags["tourism"] == "museum" && tags["wikidata"] != nil
        signals.hasWikipediaArticle = tags["wikipedia"] != nil
        signals.tagRichness = tagRichness(tags)
        signals.lastConfirmed = lastConfirmed(tags)
        signals.communityOperated = isCommunityOperated(tags)
        let keywordText = [name, tags["description"], tags["clothes"], tags["music"], tags["music:genre"],
                           tags["cuisine"], tags["artwork_type"], tags["operator"], tags["shop"], tags["second_hand"]]
            .compactMap { $0 }.joined(separator: " ")
        signals.subcultureKeywordHits = TextMatching.containsAny(keywordText, keywords: SubcultureLexicon.keywords)
        place.signals = signals
        return place
    }

    // MARK: Exclusion

    static func isExcluded(_ tags: [String: String]) -> Bool {
        let access = tags["access"]?.lowercased()
        if access == "private" || access == "no" { return true }
        if tags["disused"] == "yes" || tags["abandoned"] == "yes" || tags["demolished"] == "yes" { return true }
        if tags["shop"] == "vacant" { return true }
        let hours = tags["opening_hours"]?.lowercased().trimmingCharacters(in: .whitespaces)
        if hours == "closed" || hours == "off" { return true }
        if let end = tags["end_date"], let endDate = parseDate(end), endDate < Date() {
            return true
        }
        if tags["historic"] != nil && (tags["ruins"] == "yes" || tags["historic"] == "ruins") && access != "yes" { return true }
        return false
    }

    // MARK: Classification

    private static func matches(_ value: String?, _ pattern: String) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func classify(_ tags: [String: String]) -> PlaceKind? {
        let shop = tags["shop"]
        let amenity = tags["amenity"]
        let leisure = tags["leisure"]
        let tourism = tags["tourism"]
        let name = tags["name"] ?? ""
        let sport = tags["sport"]
        let clothes = tags["clothes"]
        let secondHand = tags["second_hand"]
        let isSecondHand = secondHand == "yes" || secondHand == "only"
        let vintagePattern = "vintage|retro|y2k|archive|antik"
        let thriftPattern = "thrift|second ?hand|secondhand|pre-?loved|resale|kilo|fripe|tr[oö]del|brocante|charity|op ?shop"

        // Skate
        if leisure == "skatepark" {
            let diy = tags["diy"] == "yes" || matches(name, "\\bdiy\\b") || tags["skatepark:type"] == "diy"
                || tags["operator:type"] == "community"
            return diy ? .diySkatepark : .skatepark
        }
        if matches(sport, "skateboard"), let leisure, ["pitch", "track", "sports_centre"].contains(leisure) {
            return .skateSpot
        }

        // Fashion & shops
        if let shop {
            switch shop {
            case "sports" where matches(sport, "skateboard") || matches(name, "skate"),
                 "skate":
                return .skateShop
            case "second_hand":
                return matches(clothes, "vintage") || matches(name, vintagePattern) ? .vintageStore : .thriftStore
            case "charity":
                return .charityShop
            case "clothes", "shoes", "fashion_accessories", "bag", "sports":
                if matches(name, "skate|board ?shop") { return .skateShop }
                if isSecondHand || matches(clothes, "second_hand") {
                    return matches(clothes, "vintage") || matches(name, vintagePattern) ? .vintageStore : .thriftStore
                }
                if matches(clothes, "vintage") || matches(name, vintagePattern) { return .vintageStore }
                if matches(name, thriftPattern) { return .thriftStore }
                if matches(clothes, "streetwear|skate|subculture|alternative") || matches(name, "street ?wear|streetwear") { return .streetwearStore }
                if matches(tags["shoes"], "sneaker") || matches(name, "sneaker") { return .sneakerStore }
                if matches(clothes, "designer") || matches(name, "archive|designer") { return .designerBoutique }
                if tags["brand"] != nil || tags["brand:wikidata"] != nil { return .fashionChain }
                if shop == "sports" { return nil }
                return .clothingStore
            case "boutique":
                return tags["brand"] != nil ? .fashionChain : .boutique
            case "antiques", "collector":
                return .antiques
            case "music":
                return .recordStore
            case "tattoo":
                return .tattooStudio
            case "art":
                return .gallery
            case "games", "video_games":
                return .gameStore
            case "anime", "comics":
                return .comicStore
            case "photo":
                return .cameraStore
            case "books":
                return .bookstore
            case "coffee":
                return .coffeeRoaster
            case "bakery":
                return .bakery
            default:
                break
            }
        }

        // Markets
        if amenity == "marketplace" {
            let text = [name, tags["description"], tags["market"], tags["marketplace"]].compactMap { $0 }.joined(separator: " ")
            if isSecondHand || TextMatching.containsAny(text, keywords: SubcultureLexicon.fleaMarketKeywords) > 0 {
                return .fleaMarket
            }
            return .market
        }

        // Street art & public art
        if tourism == "artwork" {
            let type = tags["artwork_type"]?.lowercased() ?? ""
            if type.contains("graffiti") { return .graffiti }
            if type.contains("mural") { return .mural }
            if type.contains("street_art") || type.contains("street art") { return .streetArt }
            return .artwork
        }

        // Architecture
        let style = (tags["building:architecture"] ?? tags["architecture"] ?? "").lowercased()
        if style.contains("brutalis") { return .brutalistBuilding }
        if !style.isEmpty, matches(style, "modern|constructivis|expressionis|postmodern|deconstructivis|soviet|socialist|bauhaus|international|metabolis|high-tech") {
            return .modernistBuilding
        }

        // Infrastructure
        switch tags["man_made"] {
        case "water_tower": return .waterTower
        case "observation_tower", "lighthouse": return .observationTower
        case "gasometer", "crane", "kiln": return .industrialHeritage
        case "bridge": return .bridge
        default: break
        }
        if tags["tower:type"] == "observation" { return .observationTower }
        if let historic = tags["historic"],
           ["industrial", "locomotive", "aircraft", "ship", "tram", "railway_car", "mine", "kiln", "technical_monument", "crane"].contains(historic) {
            return .industrialHeritage
        }

        // Culture & nightlife
        switch amenity {
        case "music_venue": return .musicVenue
        case "nightclub": return .nightclub
        case "events_venue":
            return tags["live_music"] == "yes" || tags["music"] != nil ? .musicVenue : nil
        case "arts_centre": return .creativeHub
        case "social_centre": return .socialCentre
        case "community_centre": return .communityCentre
        case "cinema": return tags["brand"] != nil || tags["brand:wikidata"] != nil ? .cinema : .independentCinema
        case "public_bookcase": return .publicBookcase
        case "give_box": return .giveBox
        default: break
        }
        if leisure == "hackerspace" { return .hackerspace }
        if leisure == "amusement_arcade" { return .arcade }
        if tourism == "gallery" { return .gallery }
        if tourism == "museum" { return .museum }
        if tourism == "viewpoint" { return .viewpoint }

        // Craft
        if let craft = tags["craft"] {
            if craft == "roaster" || craft == "coffee_roaster" { return .coffeeRoaster }
            if craft == "brewery" { return .brewery }
        }

        // Nature & public space
        if leisure == "garden", tags["garden:type"] == "community" { return .communityGarden }
        if tags["highway"] == "steps" { return .staircase }
        if tags["natural"] == "water" {
            return tags["water"] == "pond" ? .pond : .lake
        }
        if tags["natural"] == "beach" || leisure == "beach_resort" { return .beach }
        if tags["natural"] == "peak" || tags["natural"] == "hill" { return .peak }
        if tags["waterway"] == "waterfall" { return .waterfall }

        // Cafés, bars, food
        switch amenity {
        case "cafe":
            return .cafe
        case "bar", "biergarten": return .bar
        case "pub": return .pub
        case "restaurant", "fast_food", "food_court":
            if tags["diet:vegan"] == "only" || tags["diet:vegan"] == "yes" { return .veganRestaurant }
            if tags["diet:vegetarian"] == "only" { return .vegetarianRestaurant }
            if matches(tags["cuisine"], "regional|local|traditional") { return .localFood }
            if amenity == "fast_food" || amenity == "food_court" { return .streetFood }
            return .restaurant
        default:
            return nil
        }
    }

    static func inferredName(for kind: PlaceKind, tags: [String: String]) -> String? {
        switch kind {
        case .mural: return tags["artist_name"].map { "Mural by \($0)" } ?? "Untitled mural"
        case .graffiti: return tags["artist_name"].map { "Graffiti by \($0)" } ?? "Graffiti wall"
        case .streetArt: return tags["artist_name"].map { "Street art by \($0)" } ?? "Street art"
        case .artwork:
            if let artist = tags["artist_name"] { return "Artwork by \(artist)" }
            if let type = tags["artwork_type"], !type.isEmpty { return type.replacingOccurrences(of: "_", with: " ").capitalized }
            return "Public artwork"
        case .skatepark: return "Skatepark"
        case .diySkatepark: return "DIY skatepark"
        case .skateSpot: return "Skate spot"
        case .viewpoint: return "Viewpoint"
        case .publicBookcase: return "Public bookcase"
        case .giveBox: return "Give box"
        case .waterfall: return "Waterfall"
        case .waterTower: return "Water tower"
        case .observationTower: return "Observation tower"
        case .communityGarden: return "Community garden"
        case .industrialHeritage: return tags["historic"].map { "Industrial relic (\($0.replacingOccurrences(of: "_", with: " ")))" }
        default: return nil
        }
    }

    // MARK: Attributes

    static func descriptors(for tags: [String: String], kind: PlaceKind) -> [String] {
        var result: [String] = []
        func add(_ value: String) {
            let v = value.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces).lowercased()
            if !v.isEmpty, v != "yes", v != "no", !result.contains(v) { result.append(v) }
        }
        if tags["second_hand"] == "only" || tags["second_hand"] == "yes" { add("second-hand") }
        tags["clothes"]?.split(separator: ";").prefix(4).forEach { add(String($0)) }
        if let cuisine = tags["cuisine"] {
            cuisine.split(separator: ";").prefix(3).forEach { add(String($0)) }
        }
        if tags["diet:vegan"] == "only" { add("100% vegan") } else if tags["diet:vegan"] == "yes" { add("vegan options") }
        if tags["diet:vegetarian"] == "only" { add("vegetarian") }
        tags["music"]?.split(separator: ";").prefix(3).forEach { add(String($0)) }
        tags["music:genre"]?.split(separator: ";").prefix(3).forEach { add(String($0)) }
        if tags["live_music"] == "yes" { add("live music") }
        if tags["outdoor_seating"] == "yes" { add("outdoor seating") }
        if let style = tags["building:architecture"] ?? tags["architecture"] { add(style) }
        if let artist = tags["artist_name"] { add("by " + artist) }
        if let type = tags["artwork_type"], kind == .artwork { add(type) }
        if tags["lgbtq"] == "primary" || tags["lgbtq"] == "welcome" { add("lgbtq+ friendly") }
        if tags["cafe"] == "book" || matches(tags["name"], "book ?caf|buchcaf|caf[eé] librairie") { add("book café") }
        if tags["cafe"] == "board_game" || matches(tags["name"], "board ?game|spielecaf") { add("board games") }
        if tags["building"] != nil && tags["architect"] != nil { add("architect: " + tags["architect"]!) }
        if let hours = tags["opening_hours"], let parsed = OpeningHours.parse(hours), parsed.isLateNight,
           [.cafes, .food].contains(kind.primaryCategory) {
            add("late-night")
        }
        if tags["fee"] == "no" && kind.isPublicSpace { add("free entry") }
        return result
    }

    static func address(from tags: [String: String]) -> PostalAddress? {
        let address = PostalAddress(
            street: tags["addr:street"] ?? tags["addr:place"],
            houseNumber: tags["addr:housenumber"],
            postcode: tags["addr:postcode"],
            city: tags["addr:city"],
            district: tags["addr:suburb"] ?? tags["addr:district"],
            country: tags["addr:country"],
            formatted: tags["addr:full"]
        )
        return address.isEmpty && address.district == nil ? nil : address
    }

    static func website(from tags: [String: String]) -> URL? {
        guard var value = (tags["website"] ?? tags["contact:website"] ?? tags["url"])?
            .trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let semicolon = value.firstIndex(of: ";") { value = String(value[..<semicolon]) }
        if !value.lowercased().hasPrefix("http") { value = "https://" + value }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    static func images(from tags: [String: String]) -> [PlaceImage] {
        var result: [PlaceImage] = []
        var seen = Set<URL>()
        func addCommons(_ value: String) {
            guard let url = WikimediaImageURL.thumbnail(fileName: value), !seen.contains(url) else { return }
            seen.insert(url)
            result.append(PlaceImage(url: url, pageURL: WikimediaImageURL.descriptionPage(fileName: value),
                                     attribution: "Wikimedia Commons", license: nil,
                                     provider: .wikimediaCommons, origin: .linked))
        }
        if let commons = tags["wikimedia_commons"], commons.hasPrefix("File:") { addCommons(commons) }
        if let image = tags["image"]?.trimmingCharacters(in: .whitespaces), !image.isEmpty {
            if image.contains("wikimedia.org") || image.contains("wikipedia.org") || image.hasPrefix("File:") {
                addCommons(image)
            } else if let url = URL(string: image), url.scheme?.lowercased() == "https",
                      ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased()), !seen.contains(url) {
                seen.insert(url)
                result.append(PlaceImage(url: url, pageURL: url, attribution: url.host, license: nil,
                                         provider: .openStreetMap, origin: .linked))
            }
        }
        return result
    }

    static func brand(from tags: [String: String]) -> BrandInfo? {
        if let brand = tags["brand"], !brand.isEmpty {
            return BrandInfo(name: brand, wikidataID: tags["brand:wikidata"])
        }
        if let wikidata = tags["brand:wikidata"] {
            return BrandInfo(name: tags["name"] ?? wikidata, wikidataID: wikidata)
        }
        return nil
    }

    /// Fast-fashion chains whose price positioning is widely known. Used only
    /// for a clearly-labelled estimate.
    private static let budgetChains = ["h&m", "primark", "zara", "bershka", "pull&bear", "pull & bear", "uniqlo",
                                       "c&a", "new yorker", "kik", "takko", "stradivarius", "reserved", "pepco",
                                       "shein", "forever 21", "monki", "weekday", "mango"]

    static func price(from tags: [String: String], kind: PlaceKind, brand: BrandInfo?) -> PriceInfo {
        if tags["fee"] == "no" { return .free(source: .openStreetMap) }
        if let brand, kind == .fashionChain, budgetChains.contains(brand.name.lowercased()) {
            return .estimated(.budget, reason: "high-street chain")
        }
        if let tier = kind.typicalAffordability {
            switch tier {
            case .free: return .estimated(.free, reason: "public space")
            case .budget: return .estimated(.budget, reason: "typical for a \(kind.label.lowercased())")
            case .premium: return .estimated(.premium, reason: "typical for a \(kind.label.lowercased())")
            case .moderate: return .estimated(.moderate, reason: "typical for a \(kind.label.lowercased())")
            }
        }
        return .unknown
    }

    static func tagRichness(_ tags: [String: String]) -> Double {
        let informative: [[String]] = [
            ["name"], ["opening_hours"], ["website", "contact:website", "url"], ["addr:street"], ["addr:housenumber"],
            ["phone", "contact:phone"], ["description"], ["image", "wikimedia_commons", "wikidata"],
            ["check_date", "survey:date", "check_date:opening_hours"], ["contact:instagram", "contact:facebook"],
        ]
        let present = informative.filter { keys in keys.contains { tags[$0]?.isEmpty == false } }.count
        return min(1, Double(present) / 7.0)
    }

    static func lastConfirmed(_ tags: [String: String]) -> Date? {
        let candidates = ["check_date", "survey:date", "check_date:opening_hours", "survey_date"].compactMap { tags[$0] }
        let dates = candidates.compactMap(parseDate)
        return dates.max()
    }

    static func parseDate(_ value: String) -> Date? {
        let parts = value.trimmingCharacters(in: .whitespaces).prefix(10).split(separator: "-").compactMap { Int($0) }
        guard let year = parts.first, (1990...2100).contains(year) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = parts.count > 1 ? parts[1] : 1
        comps.day = parts.count > 2 ? parts[2] : 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: comps)
    }

    static func isCommunityOperated(_ tags: [String: String]) -> Bool {
        if let type = tags["operator:type"]?.lowercased(),
           ["community", "cooperative", "ngo", "charitable", "non_profit", "association", "religious"].contains(type) {
            return type != "religious"
        }
        if tags["cooperative"] != nil { return true }
        if tags["amenity"] == "social_centre" || tags["leisure"] == "hackerspace" { return true }
        let text = [tags["name"], tags["operator"]].compactMap { $0 }.joined(separator: " ")
        return TextMatching.containsAny(text, keywords: SubcultureLexicon.communityKeywords) > 0
    }
}
