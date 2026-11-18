import Foundation

/// A cluster of related independent places — e.g. a street with several
/// vintage and thrift stores, or a graffiti hotspot. Derived only from the
/// discovered places themselves (no external data, nothing invented).
struct Hotspot: Identifiable, Hashable, Sendable {
    enum Theme: String, CaseIterable, Sendable {
        case fashion, streetArt, nightlife

        var label: String {
            switch self {
            case .fashion: return "Shopping district"
            case .streetArt: return "Street-art hotspot"
            case .nightlife: return "Nightlife strip"
            }
        }

        var memberNoun: String {
            switch self {
            case .fashion: return "independent fashion stores"
            case .streetArt: return "street-art pieces"
            case .nightlife: return "bars, clubs & venues"
            }
        }

        var category: DiscoveryCategory {
            switch self {
            case .fashion: return .fashion
            case .streetArt: return .streetArt
            case .nightlife: return .music
            }
        }

        var kinds: Set<PlaceKind> {
            switch self {
            case .fashion:
                return [.thriftStore, .charityShop, .vintageStore, .streetwearStore, .skateShop, .sneakerStore,
                        .designerBoutique, .boutique, .clothingStore]
            case .streetArt:
                return [.mural, .graffiti, .streetArt]
            case .nightlife:
                return [.bar, .pub, .nightclub, .musicVenue, .brewery]
            }
        }
    }

    var id: String
    var theme: Theme
    var title: String
    var center: GeoCoordinate
    var memberIDs: [String]
    /// Most common descriptors among members (e.g. "vintage", "second-hand").
    var styles: [String]

    var count: Int { memberIDs.count }
}

enum HotspotDetector {
    /// Places within `linkDistance` of a seed form a cluster; clusters need `minMembers`.
    static func detect(places: [Place], themes: [Hotspot.Theme] = Hotspot.Theme.allCases,
                       linkDistance: Double = 220, minMembers: Int = 4, limit: Int = 4) -> [Hotspot] {
        var result: [Hotspot] = []
        for theme in themes {
            let members = places.filter { place in
                theme.kinds.contains(place.kind) && place.brand == nil && !place.isSample
                    && place.signals.sameNameCount < 2
            }
            guard members.count >= minMembers else { continue }
            var unassigned = Set(members.indices)
            // Neighbour counts → densest seeds first.
            let neighbours: [[Int]] = members.indices.map { i in
                members.indices.filter { j in j != i && GeoMath.distance(members[i].coordinate, members[j].coordinate) <= linkDistance }
            }
            let seeds = members.indices.sorted { neighbours[$0].count > neighbours[$1].count || (neighbours[$0].count == neighbours[$1].count && members[$0].id < members[$1].id) }
            for seed in seeds where unassigned.contains(seed) {
                let cluster = [seed] + neighbours[seed].filter { unassigned.contains($0) }
                guard cluster.count >= minMembers else { continue }
                cluster.forEach { unassigned.remove($0) }
                let clusterPlaces = cluster.map { members[$0] }
                result.append(makeHotspot(theme: theme, places: clusterPlaces))
            }
        }
        return Array(result.sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }.prefix(limit))
    }

    static func makeHotspot(theme: Hotspot.Theme, places: [Place]) -> Hotspot {
        let lat = places.map(\.coordinate.latitude).reduce(0, +) / Double(places.count)
        let lon = places.map(\.coordinate.longitude).reduce(0, +) / Double(places.count)
        let center = GeoCoordinate(latitude: lat, longitude: lon)
        func mostCommon(_ values: [String]) -> (String, Int)? {
            let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
            return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }.map { ($0.key, $0.value) }
        }
        let title: String
        if let (street, count) = mostCommon(places.compactMap { $0.address?.street }), count >= 2 {
            title = street
        } else if let (district, _) = mostCommon(places.compactMap { $0.address?.district }) {
            title = district
        } else {
            let nearest = places.min { GeoMath.distance($0.coordinate, center) < GeoMath.distance($1.coordinate, center) }
            title = "Around " + (nearest?.name ?? "here")
        }
        let styleCounts = Dictionary(grouping: places.flatMap { $0.descriptors.prefix(4) }, by: { $0 }).mapValues(\.count)
        let styles = styleCounts.filter { $0.value >= 2 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(4).map(\.key)
        let ids = places.map(\.id).sorted()
        return Hotspot(id: theme.rawValue + ":" + MD5.hex(ids.joined(separator: ",")), theme: theme, title: title,
                       center: center, memberIDs: ids, styles: styles)
    }
}
