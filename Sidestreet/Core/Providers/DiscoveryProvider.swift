import Foundation

/// A source that can search for places in an area. The Apple Maps provider
/// (app layer, MapKit) conforms to this protocol, as do the OSM stages.
protocol PlaceSearchProvider: Sendable {
    var provider: SourceProvider { get }
    func searchPlaces(in area: SearchArea, now: Date) async throws -> [Place]
}

/// Adapts one Overpass query kind to `PlaceSearchProvider`.
struct OverpassStage: PlaceSearchProvider {
    var overpass: OverpassProvider
    var kind: OverpassQueryBuilder.Kind

    var provider: SourceProvider { .openStreetMap }

    func searchPlaces(in area: SearchArea, now: Date) async throws -> [Place] {
        try await overpass.fetch(kind, area: area, now: now)
    }
}
