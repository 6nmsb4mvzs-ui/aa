import SwiftUI
import UIKit

/// Loads, downsamples and caches remote images.
///
/// - De-duplicates concurrent requests for the same URL.
/// - Downsamples to display size to keep memory low while scrolling.
/// - Limits concurrent downloads (Wikimedia asks for ≤ 3 parallel requests).
/// - Memory cache only (plus the system URL cache); no permanent storage.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var failed: Set<URL> = []
    private var active = 0
    private let maxConcurrent = 3
    private let session: URLSession
    private var userAgent = ClientIdentity.default.userAgent

    init() {
        cache.countLimit = 150
        cache.totalCostLimit = 80 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 80 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
    }

    func setUserAgent(_ value: String) { userAgent = value }

    func cachedImage(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func image(for url: URL, maxPixelSize: CGFloat = 1100) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if failed.contains(url) { return nil }
        if let task = inFlight[url] { return await task.value }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.download(url, maxPixelSize: maxPixelSize)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            cache.setObject(result, forKey: url as NSURL, cost: Int(result.size.width * result.size.height * result.scale * result.scale * 4))
        } else {
            failed.insert(url)
        }
        return result
    }

    func clearMemory() {
        cache.removeAllObjects()
        failed.removeAll()
    }

    private func acquire() async {
        while active >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { return }
        }
        active += 1
    }

    private func release() { active = max(0, active - 1) }

    private func download(_ url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        await acquire()
        defer { release() }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 15_000_000 else {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            let longest = max(image.size.width, image.size.height) * image.scale
            if longest > maxPixelSize {
                let factor = maxPixelSize / longest
                let target = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
                return await image.byPreparingThumbnail(ofSize: target) ?? image
            }
            return await image.byPreparingForDisplay() ?? image
        } catch {
            return nil
        }
    }
}

/// Displays a remote image with a placeholder; never shows broken images.
struct RemoteImage<Placeholder: View>: View {
    var url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var loadedURL: URL?

    var body: some View {
        ZStack {
            if let image, loadedURL == url {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let cached = await ImagePipeline.shared.cachedImage(for: url) {
                image = cached
                loadedURL = url
                return
            }
            let loaded = await ImagePipeline.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
                loadedURL = loaded == nil ? nil : url
            }
        }
    }
}
