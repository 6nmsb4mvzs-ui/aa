import Foundation

/// Builds Overpass QL queries for discovery.
///
/// Discovery uses two queries, run one after another (never in parallel, per
/// the Overpass usage policy):
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

    static func around(_ area: SearchArea) -> String {
        let r = Int(GeoMath.clampRadius(area.radiusMeters).rounded())
        return "(around:\(r),\(format(area.center.latitude)),\(format(area.center.longitude)))"
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
        let a = around(area)
        switch kind {
        case .niche:
            return """
            [out:json][timeout:25];
            (
              nwr["shop"~"^(second_hand|charity|music|tattoo|art|games|video_games|anime|photo|antiques|boutique|comics|skate|frame|collector)$"]\(a);
              nwr["shop"~"^(clothes|shoes|fashion_accessories|bag)$"]["second_hand"~"^(yes|only)$"]\(a);
              nwr["shop"~"^(clothes|shoes)$"]["clothes"~"vintage|streetwear|skate|designer|second_hand|subculture|alternative",i]\(a);
              nwr["shop"~"^(clothes|shoes|sports|fashion_accessories)$"]["name"~"\(indieFashionNamePattern)",i]\(a);
              nwr["shop"="sports"]["sport"~"skateboard"]\(a);
              nwr["shop"="books"][!"brand"]\(a);
              nwr["leisure"="skatepark"]\(a);
              nwr["sport"~"skateboard"]["leisure"~"^(pitch|sports_centre|track)$"]\(a);
              nwr["tourism"="artwork"]["artwork_type"!~"^(statue|bust|stone|relief|plaque|memorial)$"]\(a);
              nwr["building:architecture"~"brutalis|modern|constructivis|expressionis|postmodern|deconstructivis|soviet|socialist|bauhaus|international|metabolis|high-tech",i]\(a);
              nwr["architecture"~"brutalis|modern|constructivis|expressionis|postmodern|deconstructivis|soviet|socialist|bauhaus|international|metabolis|high-tech",i]\(a);
              nwr["man_made"~"^(water_tower|gasometer|lighthouse|observation_tower|crane|kiln)$"]\(a);
              nwr["tower:type"="observation"]\(a);
              nwr["historic"~"^(industrial|locomotive|aircraft|ship|tram|railway_car|mine|kiln|technical_monument|crane)$"]\(a);
              nwr["amenity"~"^(nightclub|music_venue|arts_centre|social_centre|community_centre|cinema|public_bookcase|give_box|marketplace|events_venue)$"]\(a);
              nwr["leisure"~"^(hackerspace|amusement_arcade)$"]\(a);
              nwr["tourism"~"^(gallery|viewpoint|museum)$"]\(a);
              nwr["craft"~"^(roaster|coffee_roaster|brewery)$"]\(a);
              nwr["shop"="coffee"][!"brand"]\(a);
              nwr["leisure"="garden"]["garden:type"="community"]\(a);
              nwr["highway"="steps"]["name"]\(a);
              nwr["man_made"="bridge"]["name"]\(a);
              nwr["natural"="water"]["water"~"^(pond|lake|reservoir|lagoon)$"]["name"]\(a);
              nwr["natural"~"^(peak|beach|hill)$"]["name"]\(a);
              nwr["waterway"="waterfall"]\(a);
              nwr["leisure"="beach_resort"]\(a);
            );
            out center 2500;
            """
        case .everyday:
            return """
            [out:json][timeout:25];
            nwr["amenity"="cafe"][!"brand"]\(a)->.cafes;
            nwr["amenity"~"^(bar|pub|biergarten)$"][!"brand"]\(a)->.bars;
            nwr["amenity"~"^(restaurant|fast_food|food_court)$"]["diet:vegan"~"^(yes|only)$"]\(a)->.vegan;
            nwr["amenity"~"^(restaurant|fast_food|cafe)$"]["diet:vegetarian"="only"]\(a)->.vegetarian;
            nwr["amenity"~"^(restaurant|fast_food)$"]["cuisine"~"regional|local|traditional",i][!"brand"]\(a)->.regional;
            nwr["amenity"="fast_food"][!"brand"]\(a)->.cheap;
            nwr["shop"~"^(clothes|shoes)$"]\(a)->.fashion;
            nwr["shop"="bakery"][!"brand"]["craft"]\(a)->.bakery;
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
