import MapKit
import UIKit

/// Apple Look Around (street-level imagery, on-device MapKit, free).
/// Used as a clearly-labelled visual reference when a place has no photo.
/// Coverage depends on the city; missing coverage simply shows nothing.
@MainActor
final class LookAroundService {
    static let shared = LookAroundService()

    private var scenes: [String: MKLookAroundScene] = [:]
    private var missing: Set<String> = []
    private let snapshots = NSCache<NSString, UIImage>()
    private var activeSnapshots = 0

    private init() {
        snapshots.countLimit = 60
    }

    private func key(_ coordinate: GeoCoordinate) -> String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    func scene(at coordinate: GeoCoordinate) async -> MKLookAroundScene? {
        let k = key(coordinate)
        if let scene = scenes[k] { return scene }
        if missing.contains(k) { return nil }
        let request = MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                                                  longitude: coordinate.longitude))
        do {
            if let scene = try await request.scene {
                scenes[k] = scene
                return scene
            }
        } catch {}
        missing.insert(k)
        return nil
    }

    func cachedSnapshot(at coordinate: GeoCoordinate) -> UIImage? {
        snapshots.object(forKey: key(coordinate) as NSString)
    }

    /// A static Look Around image for feed cards (limited concurrency).
    func snapshot(at coordinate: GeoCoordinate, size: CGSize) async -> UIImage? {
        let k = key(coordinate) as NSString
        if let cached = snapshots.object(forKey: k) { return cached }
        while activeSnapshots >= 2 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return nil }
        }
        activeSnapshots += 1
        defer { activeSnapshots -= 1 }
        guard let scene = await scene(at: coordinate) else { return nil }
        let options = MKLookAroundSnapshotter.Options()
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot else { return nil }
        snapshots.setObject(snapshot.image, forKey: k)
        return snapshot.image
    }
}
