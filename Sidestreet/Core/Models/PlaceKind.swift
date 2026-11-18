import Foundation

/// Fine-grained place type. Each kind carries the editorial knowledge the
/// scoring engine needs: which categories it belongs to, how intrinsically
/// "niche" it is, how strongly it relates to subcultures and what it usually
/// costs. These are transparent, hand-tuned priors — not data about a
/// specific place — and are documented in docs/SCORING.md.
enum PlaceKind: String, Codable, CaseIterable, Hashable, Sendable {
    // Fashion
    case thriftStore, charityShop, vintageStore, streetwearStore, skateShop
    case sneakerStore, designerBoutique, boutique, clothingStore, fashionChain
    // Markets
    case fleaMarket, market, antiques
    // Skate & street culture
    case skatepark, diySkatepark, skateSpot
    // Street art
    case mural, graffiti, streetArt
    // Architecture & urban exploration
    case brutalistBuilding, modernistBuilding, notableBuilding, industrialHeritage
    case waterTower, observationTower, bridge, staircase, creativeHub
    // Music & nightlife
    case recordStore, musicVenue, nightclub, bar, pub, brewery
    // Alternative culture
    case tattooStudio, gallery, comicStore, gameStore, cameraStore, bookstore
    case independentCinema, cinema, arcade, hackerspace, socialCentre, communityCentre
    case museum
    // Cafés
    case cafe, coffeeRoaster, bakery
    // Food
    case veganRestaurant, vegetarianRestaurant, localFood, streetFood, restaurant
    // Hidden gems
    case viewpoint, publicBookcase, communityGarden, artwork, giveBox
    // Nature
    case pond, lake, beach, waterfall, peak, garden

    var label: String {
        switch self {
        case .thriftStore: return "Thrift store"
        case .charityShop: return "Charity shop"
        case .vintageStore: return "Vintage store"
        case .streetwearStore: return "Streetwear"
        case .skateShop: return "Skate shop"
        case .sneakerStore: return "Sneaker store"
        case .designerBoutique: return "Designer / archive boutique"
        case .boutique: return "Independent boutique"
        case .clothingStore: return "Clothing store"
        case .fashionChain: return "Fashion chain"
        case .fleaMarket: return "Flea market"
        case .market: return "Market"
        case .antiques: return "Antiques & curiosities"
        case .skatepark: return "Skatepark"
        case .diySkatepark: return "DIY skatepark"
        case .skateSpot: return "Skate spot"
        case .mural: return "Mural"
        case .graffiti: return "Graffiti"
        case .streetArt: return "Street art"
        case .brutalistBuilding: return "Brutalist architecture"
        case .modernistBuilding: return "Modernist architecture"
        case .notableBuilding: return "Notable building"
        case .industrialHeritage: return "Industrial relic"
        case .waterTower: return "Water tower"
        case .observationTower: return "Observation tower"
        case .bridge: return "Bridge"
        case .staircase: return "Staircase"
        case .creativeHub: return "Creative space"
        case .recordStore: return "Record store"
        case .musicVenue: return "Live music venue"
        case .nightclub: return "Club"
        case .bar: return "Bar"
        case .pub: return "Pub"
        case .brewery: return "Craft brewery"
        case .tattooStudio: return "Tattoo studio"
        case .gallery: return "Gallery"
        case .comicStore: return "Comics & manga"
        case .gameStore: return "Games & retro gaming"
        case .cameraStore: return "Camera & analogue photo"
        case .bookstore: return "Independent bookstore"
        case .independentCinema: return "Independent cinema"
        case .cinema: return "Cinema"
        case .arcade: return "Arcade"
        case .hackerspace: return "Hackerspace"
        case .socialCentre: return "Social centre / DIY space"
        case .communityCentre: return "Community space"
        case .museum: return "Museum"
        case .cafe: return "Café"
        case .coffeeRoaster: return "Coffee roaster"
        case .bakery: return "Bakery"
        case .veganRestaurant: return "Vegan food"
        case .vegetarianRestaurant: return "Vegetarian food"
        case .localFood: return "Local specialty"
        case .streetFood: return "Cheap eats"
        case .restaurant: return "Restaurant"
        case .viewpoint: return "Viewpoint"
        case .publicBookcase: return "Public bookcase"
        case .communityGarden: return "Community garden"
        case .artwork: return "Public art"
        case .giveBox: return "Give box"
        case .pond: return "Pond"
        case .lake: return "Lake"
        case .beach: return "Urban beach"
        case .waterfall: return "Waterfall"
        case .peak: return "Hill / peak"
        case .garden: return "Garden"
        }
    }

    /// Primary category first, then secondary categories.
    var categories: [DiscoveryCategory] {
        switch self {
        case .thriftStore, .charityShop, .vintageStore: return [.fashion]
        case .streetwearStore, .sneakerStore, .designerBoutique, .boutique, .clothingStore, .fashionChain: return [.fashion]
        case .skateShop: return [.skate, .fashion]
        case .fleaMarket: return [.markets, .fashion]
        case .market: return [.markets, .food]
        case .antiques: return [.markets]
        case .skatepark, .diySkatepark, .skateSpot: return [.skate, .photo]
        case .mural, .graffiti, .streetArt: return [.streetArt, .photo]
        case .brutalistBuilding, .modernistBuilding: return [.architecture, .photo]
        case .notableBuilding: return [.architecture]
        case .industrialHeritage: return [.architecture, .photo, .hiddenGems]
        case .waterTower: return [.architecture, .hiddenGems]
        case .observationTower: return [.architecture, .photo, .hiddenGems]
        case .bridge: return [.architecture, .photo]
        case .staircase: return [.architecture, .photo, .hiddenGems]
        case .creativeHub: return [.culture, .architecture]
        case .recordStore: return [.music, .culture]
        case .musicVenue, .nightclub: return [.music]
        case .bar, .pub, .brewery: return [.music]
        case .tattooStudio, .gallery, .comicStore, .gameStore, .cameraStore, .bookstore: return [.culture]
        case .independentCinema, .cinema, .arcade, .museum: return [.culture]
        case .hackerspace: return [.culture, .hiddenGems]
        case .socialCentre: return [.culture, .hiddenGems]
        case .communityCentre: return [.hiddenGems, .culture]
        case .cafe, .coffeeRoaster, .bakery: return [.cafes]
        case .veganRestaurant, .vegetarianRestaurant, .localFood, .streetFood, .restaurant: return [.food]
        case .viewpoint: return [.hiddenGems, .photo, .nature]
        case .publicBookcase, .giveBox: return [.hiddenGems]
        case .communityGarden: return [.hiddenGems, .nature]
        case .artwork: return [.hiddenGems, .streetArt]
        case .pond, .lake, .waterfall, .peak, .garden: return [.nature, .photo]
        case .beach: return [.nature, .hiddenGems]
        }
    }

    var primaryCategory: DiscoveryCategory { categories[0] }

    /// How unusual this type of place is, independent of the specific place
    /// (0 = completely generic, 1 = rare and distinctive).
    var intrinsicNiche: Double {
        switch self {
        case .diySkatepark, .socialCentre, .hackerspace: return 0.95
        case .graffiti, .skateSpot, .industrialHeritage, .staircase: return 0.85
        case .vintageStore, .recordStore, .brutalistBuilding, .giveBox, .publicBookcase: return 0.82
        case .thriftStore, .fleaMarket, .streetwearStore, .skateShop, .independentCinema: return 0.78
        case .mural, .streetArt, .musicVenue, .comicStore, .gameStore, .cameraStore, .waterTower: return 0.72
        case .charityShop, .tattooStudio, .arcade, .coffeeRoaster, .creativeHub, .communityGarden: return 0.68
        case .designerBoutique, .gallery, .nightclub, .modernistBuilding, .antiques: return 0.62
        case .skatepark, .bookstore, .viewpoint, .brewery, .veganRestaurant, .beach: return 0.6
        case .sneakerStore, .boutique, .localFood, .artwork, .pond, .waterfall: return 0.52
        case .observationTower, .bridge, .communityCentre, .vegetarianRestaurant: return 0.45
        case .notableBuilding, .market, .bar, .pub, .lake, .peak, .garden: return 0.38
        case .cafe, .bakery, .clothingStore, .museum: return 0.3
        case .restaurant, .cinema, .streetFood: return 0.2
        case .fashionChain: return 0.05
        }
    }

    /// Relevance to alternative / underground culture (skate, graffiti,
    /// DIY, vinyl, vintage, club culture).
    var subcultureAffinity: Double {
        switch self {
        case .diySkatepark, .socialCentre, .graffiti, .skateSpot, .recordStore: return 1.0
        case .skatepark, .skateShop, .streetwearStore, .vintageStore, .thriftStore, .hackerspace: return 0.85
        case .musicVenue, .nightclub, .streetArt, .tattooStudio, .fleaMarket, .comicStore: return 0.8
        case .mural, .gameStore, .arcade, .cameraStore, .charityShop, .independentCinema: return 0.65
        case .brutalistBuilding, .industrialHeritage, .creativeHub, .sneakerStore, .giveBox: return 0.6
        case .gallery, .coffeeRoaster, .bookstore, .staircase, .publicBookcase, .designerBoutique: return 0.45
        case .bar, .pub, .brewery, .veganRestaurant, .communityGarden, .antiques: return 0.4
        case .boutique, .modernistBuilding, .waterTower, .communityCentre, .vegetarianRestaurant: return 0.3
        case .cafe, .artwork, .bridge, .viewpoint, .observationTower, .beach: return 0.2
        case .clothingStore, .market, .bakery, .localFood, .notableBuilding, .museum, .cinema: return 0.15
        case .restaurant, .streetFood, .pond, .lake, .waterfall, .peak, .garden: return 0.1
        case .fashionChain: return 0.05
        }
    }

    /// Typical cost. Only used as a clearly-labelled *estimate* when the data
    /// sources do not provide real price information.
    var typicalAffordability: AffordabilityTier? {
        switch self {
        case .thriftStore, .charityShop, .fleaMarket, .streetFood, .giveBox, .publicBookcase: return .budget
        case .designerBoutique: return .premium
        case .skatepark, .diySkatepark, .skateSpot, .mural, .graffiti, .streetArt, .artwork,
             .viewpoint, .bridge, .staircase, .communityGarden, .pond, .lake, .beach, .waterfall, .peak:
            return .free
        default: return nil
        }
    }

    /// Whether the place is normally a business with opening hours.
    var isBusiness: Bool { primaryCategory.isCommercial || self == .skateShop }

    /// Whether this kind is a publicly accessible space rather than a venue.
    var isPublicSpace: Bool { typicalAffordability == .free }

    /// Kinds whose venues often publish event calendars on their websites.
    var publishesEvents: Bool {
        switch self {
        case .musicVenue, .nightclub, .gallery, .creativeHub, .socialCentre, .independentCinema,
             .recordStore, .fleaMarket, .market, .skatepark, .diySkatepark, .skateShop, .communityCentre,
             .hackerspace, .bookstore, .brewery, .bar, .pub, .comicStore, .gameStore, .museum:
            return true
        default:
            return false
        }
    }

    /// Kinds that are photogenic by nature.
    var isPhotogenic: Bool { categories.contains(.photo) }

    var symbolName: String {
        switch self {
        case .thriftStore, .charityShop, .vintageStore, .streetwearStore, .boutique, .clothingStore, .fashionChain, .designerBoutique:
            return "tshirt"
        case .sneakerStore: return "shoe"
        case .skateShop, .skatepark, .diySkatepark, .skateSpot: return "figure.skateboarding"
        case .fleaMarket, .market, .antiques: return "tag"
        case .mural, .streetArt, .graffiti: return "paintbrush.pointed"
        case .brutalistBuilding, .modernistBuilding, .notableBuilding: return "building.2"
        case .industrialHeritage: return "gearshape.2"
        case .waterTower, .observationTower: return "building.columns"
        case .bridge: return "road.lanes"
        case .staircase: return "stairs"
        case .creativeHub: return "paintpalette"
        case .recordStore: return "opticaldisc"
        case .musicVenue: return "music.mic"
        case .nightclub: return "headphones"
        case .bar, .pub: return "wineglass"
        case .brewery: return "mug"
        case .tattooStudio: return "pencil.and.scribble"
        case .gallery, .museum: return "photo.artframe"
        case .comicStore, .bookstore, .publicBookcase: return "books.vertical"
        case .gameStore, .arcade: return "gamecontroller"
        case .cameraStore: return "camera"
        case .independentCinema, .cinema: return "film"
        case .hackerspace: return "cpu"
        case .socialCentre, .communityCentre: return "person.3"
        case .cafe, .coffeeRoaster: return "cup.and.saucer"
        case .bakery: return "birthday.cake"
        case .veganRestaurant, .vegetarianRestaurant: return "carrot"
        case .localFood, .streetFood, .restaurant: return "fork.knife"
        case .viewpoint: return "binoculars"
        case .communityGarden, .garden: return "leaf"
        case .artwork: return "cube"
        case .giveBox: return "shippingbox"
        case .pond, .lake: return "drop"
        case .beach: return "beach.umbrella"
        case .waterfall: return "water.waves"
        case .peak: return "mountain.2"
        }
    }
}

/// Coarse affordability tiers.
enum AffordabilityTier: String, Codable, Hashable, Sendable, Comparable {
    case free, budget, moderate, premium

    var label: String {
        switch self {
        case .free: return "Free"
        case .budget: return "Budget"
        case .moderate: return "Mid-range"
        case .premium: return "Premium"
        }
    }

    /// Normalised affordability (1 = cheapest).
    var affordabilityScore: Double {
        switch self {
        case .free: return 1.0
        case .budget: return 0.85
        case .moderate: return 0.5
        case .premium: return 0.2
        }
    }

    private var order: Int {
        switch self {
        case .free: return 0
        case .budget: return 1
        case .moderate: return 2
        case .premium: return 3
        }
    }

    static func < (lhs: AffordabilityTier, rhs: AffordabilityTier) -> Bool { lhs.order < rhs.order }
}
