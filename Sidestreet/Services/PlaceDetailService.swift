import Foundation
import MapKit

/// Lazy, per-profile lookups. Nothing here runs until the user opens a
/// place, and results are cached in memory for the session.
final class PlaceDetailService: Sendable {
    private let client: URLSessionHTTPClient
    private let summaries = ResponseCache<WikipediaSummaryService.Summary?>(ttl: 6 * 3600)
    private let photos = ResponseCache<[PlaceImage]>(ttl: 6 * 3600)
    private let videos = ResponseCache<[YouTubeService.Video]>(ttl: 12 * 3600)

    init(identity: ClientIdentity) {
        client = AppEnvironment.httpClient(identity: identity)
    }

    func wikipediaSummary(for place: Place) async -> WikipediaSummaryService.Summary? {
        guard let reference = place.wikipediaTitle else { return nil }
        if let cached = await summaries.value(for: reference) { return cached }
        do {
            let summary = try await WikipediaSummaryService(client: client).summary(reference: reference)
            await summaries.set(summary, for: reference) // cache found and not-found, but not errors
            return summary
        } catch {
            return nil
        }
    }

    /// Geotagged Commons photos taken within ~60 m (labelled "nearby").
    func nearbyPhotos(for place: Place, enabled: Bool = true) async -> [PlaceImage] {
        guard enabled else { return [] }
        let key = place.id
        if let cached = await photos.value(for: key) { return cached }
        let radius = place.kind.isPublicSpace ? 40 : 60
        let result = (try? await CommonsPhotoService(client: client).photos(near: place.coordinate, radius: radius, limit: 8)) ?? []
        let filtered = result.filter { image in !place.images.contains { $0.url == image.url } }
        await photos.set(filtered, for: key)
        return filtered
    }

    enum VideoResult {
        case notConfigured
        case videos([YouTubeService.Video])
        case failed(String)
    }

    func youtubeVideos(query: String, cacheKey: String) async -> VideoResult {
        guard let key = KeychainStore.youTubeAPIKey, !key.isEmpty else { return .notConfigured }
        if let cached = await videos.value(for: cacheKey) { return .videos(cached) }
        let service = YouTubeService(client: client, apiKey: key, bundleIdentifier: Bundle.main.bundleIdentifier)
        do {
            let result = try await service.search(query, maxResults: 6)
            await videos.set(result, for: cacheKey)
            return .videos(result)
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? "YouTube is unavailable.")
        }
    }

    /// Finds the matching Apple Maps item (for "Open in Maps" and Apple's
    /// own place card with hours, photos and price where Apple has them).
    @MainActor
    func appleMapItem(for place: Place) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place.isNameInferred ? place.kind.label : place.name
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
            latitudinalMeters: 600, longitudinalMeters: 600
        )
        guard !place.isNameInferred, let items = try? await MKLocalSearch(request: request).start().mapItems else { return nil }
        return items.first { item in
            let c = item.placemark.coordinate
            let distance = GeoMath.distance(GeoCoordinate(latitude: c.latitude, longitude: c.longitude), place.coordinate)
            return distance < 120 && TextMatching.nameSimilarity(item.name ?? "", place.name) >= 0.8
        }
    }

    /// A plain map item at the place's coordinate (always available).
    @MainActor
    static func coordinateMapItem(for place: Place) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)))
        item.name = place.name
        return item
    }
}
