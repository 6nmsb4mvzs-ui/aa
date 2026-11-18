import SwiftUI

/// Interstitial feed card: explore the city on platforms the app can't
/// search directly (outbound links), plus YouTube city guides when the user
/// added a YouTube API key.
struct CityExploreCard: View {
    @Environment(AppModel.self) private var model
    @State private var videos: [YouTubeService.Video] = []
    @State private var loadedFor: String?

    private var cityName: String { model.area?.label ?? model.locationTitle }
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ExternalLinkBuilder.cityLinks(cityName: cityName)) { link in
                    CityLinkTile(link: link)
                }
            }
            if !videos.isEmpty {
                Text("City guides on YouTube").eyebrow()
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(videos) { video in
                            CityVideoTile(video: video)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Theme.gutter)
        .cardSurface()
        .task(id: cityName) { await loadVideos() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Beyond the map").eyebrow(Theme.accent)
            Text("Explore \(cityName) elsewhere")
                .font(.display(26))
                .foregroundStyle(Theme.textPrimary)
            Text("Local videos, posts and threads live on platforms without a public API. These open their own search — Sidestreet doesn't read them.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func loadVideos() async {
        guard !model.isDemo, loadedFor != cityName else { return }
        loadedFor = cityName
        let query = "\(cityName) alternative city guide hidden gems"
        let result = await model.details.youtubeVideos(query: query, cacheKey: "city:" + cityName.lowercased())
        if case .videos(let list) = result { videos = list }
    }
}

private struct CityLinkTile: View {
    let link: ExternalLink

    var body: some View {
        Link(destination: link.url) {
            HStack(spacing: 8) {
                Image(systemName: link.platform.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.platform.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(link.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct CityVideoTile: View {
    let video: YouTubeService.Video

    var body: some View {
        if let url = video.watchURL {
            Link(destination: url) {
                VStack(alignment: .leading, spacing: 6) {
                    RemoteImage(url: video.thumbnail) { Rectangle().fill(Theme.surfaceHigh) }
                        .frame(width: 200, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(video.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .frame(width: 200, alignment: .leading)
                }
            }
        }
    }
}
