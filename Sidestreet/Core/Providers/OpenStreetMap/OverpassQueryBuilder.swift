import Foundation

/// Builds Overpass QL queries for discovery.
///
/// Discovery uses two queries, run one after another (never in parallel, per
/// the Overpass usage policy). Both use a global bounding box (`[bbox:…]`):
///
/// 1. **Niche query** — sparse, distinctive features (thrift and vintage
///    shops, skateparks, street art, brutalist buildings, record stores,
///    social centres, viewpoints …). Returned completely within the radius.
/// 2. **Everyday query** — dense categories (cafés, bars, food, clothing).
///    Branded chains are filtered server-side where appropriate and each set
///    is capped, so large radii stay fast and light on mobile data.
enum OverpassQueryBuilder {
    enum Kind: String, Sendable {
        case niche, everyday
    }

    /// Global bounding box of the search circle. A `[bbox:…]` setting lets
    /// Overpass use its spatial index for every statement, which is far
    /// faster than per-statement `around` filters. Results are then cut to
    /// the exact circle client-side.
    static func bbox(_ area: SearchArea) -> String {
        let box = GeoMath.boundingBox(center: area.center, radius: GeoMath.clampRadius(area.radiusMeters))
        return "[bbox:\(format(box.south)),\(format(box.west)),\(format(box.north)),\(format(box.east))]"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    /// Case-insensitive name patterns for independent shops that lack
    /// detailed tags (multilingual).
    static let indieFashionNamePattern =
        "vintage|thrift|second ?hand|secondhand|pre-?loved|retro|kilo|fripe|friperie|brocante|tr[oö]del|"
        + "resale|archive|sneaker|skate|streetwear|upcycl|y2k|rework"

    static func query(_ kind: Kind, area: SearchArea) -> String {
        let header = "[out:json][timeout:25]" + bbox(area) + ";"
        switch kind {
        case .niche:
            return header + """

            (
              nwr["shop"~"^(second_hand|charity|music|tattoo|art|games|video_games|anime|photo|antiques|boutique|comics|skate|collector)$"];
              nwr["shop"~"^(clothes|shoes|fashion_accessories|bag)$"]["second_hand"~"^(yes|only)$"];
              nwr["shop"~"^(clothes|shoes)$"]["clothes"~"vintage|streetwear|skate|designer|second_hand|subculture|alternative",i];
              nwr["shop"~"^(clothes|shoes|sports|fashion_accessories)$"]["name"~"\(indieFashionNamePattern)",i];
              nwr["shop"="sports"]["sport"~"skateboard"];
              nwr["shop"="books"][!"brand"];
              nwr["leisure"="skatepark"];
              nwr["sport"~"skateboard"]["leisure"~"^(pitch|sports_centre|track)$"];
              nwr["tourism"="artwork"]["artwork_type"!~"^(statue|bust|stone|relief|plaque|memorial)$"];
              nwr["building:architecture"~"brutalis|modern|constructivis|expressionis|postmodern|deconstructivis|soviet|socialist|bauhaus|international|metabolis|high-tech",i];
              nwr["architecture"~"brutalis|modern|constructivis|expressionis|postmodern|deconstructivis|soviet|socialist|bauhaus|international|metabolis|high-tech",i];
              nwr["man_made"~"^(water_tower|gasometer|lighthouse|observation_tower|crane|kiln)$"];
              nwr["tower:type"="observation"];
              nwr["historic"~"^(industrial|locomotive|aircraft|ship|tram|railway_car|mine|kiln|technical_monument|crane)$"];
              nwr["amenity"~"^(nightclub|music_venue|arts_centre|social_centre|community_centre|cinema|public_bookcase|give_box|marketplace|events_venue)$"];
              nwr["leisure"~"^(hackerspace|amusement_arcade)$"];
              nwr["tourism"~"^(gallery|viewpoint|museum)$"];
              nwr["craft"~"^(roaster|coffee_roaster|brewery)$"];
              nwr["shop"="coffee"][!"brand"];
              nwr["leisure"="garden"]["garden:type"="community"];
              nwr["highway"="steps"]["name"];
              nwr["man_made"="bridge"]["name"];
              nwr["natural"="water"]["water"~"^(pond|lake|reservoir|lagoon)$"]["name"];
              nwr["natural"~"^(peak|beach|hill)$"]["name"];
              nwr["waterway"="waterfall"];
              nwr["leisure"="beach_resort"];
            );
            out center 2500;
            """
        case .everyday:
            return header + """

            nwr["amenity"="cafe"][!"brand"]->.cafes;
            nwr["amenity"~"^(bar|pub|biergarten)$"][!"brand"]->.bars;
            nwr["amenity"~"^(restaurant|fast_food|food_court)$"]["diet:vegan"~"^(yes|only)$"]->.vegan;
            nwr["amenity"~"^(restaurant|fast_food|cafe)$"]["diet:vegetarian"="only"]->.vegetarian;
            nwr["amenity"~"^(restaurant|fast_food)$"]["cuisine"~"regional|local|traditional",i][!"brand"]->.regional;
            nwr["amenity"="fast_food"][!"brand"]->.cheap;
            nwr["shop"~"^(clothes|shoes)$"]->.fashion;
            nwr["shop"="bakery"][!"brand"]["craft"]->.bakery;
            .cafes out center 350;
            .bars out center 300;
            .vegan out center 200;
            .vegetarian out center 100;
            .regional out center 120;
            .cheap out center 200;
            .fashion out center 350;
            .bakery out center 80;
            """
        }
    }
}
