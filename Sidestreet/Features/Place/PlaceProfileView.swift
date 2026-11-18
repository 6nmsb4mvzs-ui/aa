import MapKit
import SwiftUI

/// Compact preview (first ~340 pt) that expands into the full profile.
/// Shows only information a source actually provided; gaps are stated.
struct PlaceProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    var place: Place
    @Binding var detent: PresentationDetent

    @State private var summary: WikipediaSummaryService.Summary?
    @State private var nearbyPhotos: [PlaceImage] = []
    @State private var foundPhoto: PlaceImage?
    @State private var videos: PlaceDetailService.VideoResult?
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var appleItem: MKMapItem?
    @State private var appleCardItem: MKMapItem?
    @State private var isOpeningMaps = false
    @State private var didLoadDetails = false

    private var area: SearchArea? { model.area }
    private var tint: Color { Theme.tint(for: place.primaryCategory) }
    private var isExpanded: Bool { detent == .large }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                preview
                if isExpanded {
                    fullProfile
                } else {
                    Button {
                        withAnimation { detent = .large }
                    } label: {
                        Label("Full profile", systemImage: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .modifier(AppleMapsCardModifier(item: $appleCardItem))
        .task(id: isExpanded) {
            guard isExpanded, !didLoadDetails, !place.isSample else { return }
            didLoadDetails = true
            await loadDetails()
        }
    }

    // MARK: Compact preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.kind.label).eyebrow(tint)
                    Text(place.name)
                        .font(.display(34))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(isExpanded ? 4 : 2)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
            }
            if place.isSample { SampleDataBanner() }
            MetaRow(place: place, area: area)
            HStack(spacing: 8) {
                ConfidenceBadge(level: place.confidence)
                if place.isNameInferred { Tag(text: "Untitled", systemImage: "textformat", color: Theme.textSecondary) }
                ForEach(place.descriptors.prefix(3), id: \.self) { Tag(text: $0) }
            }
            .lineLimit(1)
            actionRow
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await openInMaps() }
            } label: {
                Label(isOpeningMaps ? "Opening…" : "Maps", systemImage: "map").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            if let website = place.website {
                Button { openURL(website) } label: {
                    Label("Website", systemImage: "safari").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
            ShareLink(item: shareURL, subject: Text(place.name), message: Text("\(place.name) — \(place.kind.label)")) {
                Image(systemName: "square.and.arrow.up").frame(width: 22)
            }
            .buttonStyle(PillButtonStyle(prominent: false))
        }
    }

    private var shareURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            .init(name: "q", value: place.name),
            .init(name: "ll", value: String(format: "%.6f,%.6f", place.coordinate.latitude, place.coordinate.longitude)),
        ]
        return components.url!
    }

    // MARK: Full profile

    @ViewBuilder
    private var fullProfile: some View {
        photosSection
        if let text = summary?.extract ?? place.summary {
            ProfileSection(title: "About") {
                Text(text).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                if summary != nil, let url = summary?.pageURL {
                    Link("Read on Wikipedia", destination: url).font(.system(size: 13, weight: .semibold))
                }
            }
        }
        detailsSection
        hoursSection
        priceSection
        scoreSection
        sourcesSection
        exploreSection
        videosSection
    }

    /// Linked photos, then the found photo, then nearby photos (no duplicates).
    private var allPhotos: [PlaceImage] {
        var result: [PlaceImage] = place.images
        if let foundPhoto, !result.contains(where: { $0.url == foundPhoto.url }) {
            result.append(foundPhoto)
        }
        for photo in nearbyPhotos where !result.contains(where: { $0.url == photo.url }) {
            result.append(photo)
        }
        return result
    }

    @ViewBuilder
    private var photosSection: some View {
        let all: [PlaceImage] = allPhotos
        ProfileSection(title: "Photos & visual references") {
            if all.isEmpty && lookAroundScene == nil {
                Text(didLoadDetails ? "No photos found in open image sources for this place." : "Looking for photos…")
                    .font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            }
            if !all.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(all, id: \.url) { image in
                            PhotoTile(image: image)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                if !nearbyPhotos.isEmpty || foundPhoto?.origin == .streetLevel {
                    Text("“Nearby” photos are geotagged within about 60 m; street-level views look towards the place. Both may show the surroundings.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            if let scene = lookAroundScene {
                LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: false)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Street-level imagery: Apple Look Around").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var detailsSection: some View {
        ProfileSection(title: "Details") {
            InfoRow(symbol: "mappin.and.ellipse", title: "Address",
                    value: place.address?.singleLine ?? "Not listed in our sources")
            if let area {
                InfoRow(symbol: "location.north.line", title: area.centerSource == .gps ? "Distance from you" : "Distance from centre",
                        value: Format.distance(place.distance(from: area.center), metric: settings.useMetric))
            }
            if let phone = place.phone {
                let digits = phone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "tel:\(digits)") {
                    Link(destination: url) { InfoRow(symbol: "phone", title: "Phone", value: phone, isLink: true) }
                }
            }
            if let website = place.website {
                Link(destination: website) { InfoRow(symbol: "safari", title: "Website", value: website.host ?? website.absoluteString, isLink: true) }
            }
            Button {
                Task {
                    if appleItem == nil { appleItem = await model.details.appleMapItem(for: place) }
                    if let appleItem { appleCardItem = appleItem } else { await openInMaps() }
                }
            } label: {
                InfoRow(symbol: "apple.logo", title: "Apple Maps place card",
                        value: "Hours, photos and price where Apple has them", isLink: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var hoursSection: some View {
        let timeZone = area?.timeZone ?? .current
        ProfileSection(title: "Opening hours") {
            if let raw = place.openingHoursRaw {
                if let hours = OpeningHours.parse(raw) {
                    if let status = Format.openStatus(place, timeZone: timeZone) {
                        Text(status.text)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(status.isOpen ? Theme.positive : Theme.textSecondary)
                    }
                    if hours.isAlwaysOpen {
                        Text("Open 24/7").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    } else {
                        let rows = hours.weeklySchedule(containing: Date(), timeZone: timeZone)
                        VStack(spacing: 6) {
                            ForEach(rows, id: \.weekday) { row in
                                HStack {
                                    Text(OpeningHours.weekdayName(row.weekday)).frame(width: 44, alignment: .leading)
                                    Text(row.text)
                                    Spacer()
                                }
                                .font(.system(size: 14).monospacedDigit())
                                .foregroundStyle(row.text == "Closed" ? Theme.textTertiary : Theme.textPrimary)
                            }
                        }
                    }
                    if hours.hasHolidayRules {
                        Text("Hours may differ on public holidays.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                    if timeZone.identifier != TimeZone.current.identifier {
                        Text("Times shown in local time (\(timeZone.identifier)).").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                } else {
                    Text(raw).font(.system(size: 14).monospaced()).foregroundStyle(Theme.textSecondary)
                    Text("This schedule format can't be evaluated automatically, so no open/closed status is shown.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
                Text("Source: OpenStreetMap community data — check before visiting.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            } else if place.kind.isBusiness {
                Text("Not available from our sources. Try the Apple Maps place card or Google Maps below.")
                    .font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            } else {
                Text("Public space — no opening hours recorded.").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var priceSection: some View {
        ProfileSection(title: "Price & affordability") {
            switch place.price {
            case .unknown:
                Text("Price level not available from free sources.").font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
            case .level(let level, let source):
                Text("Price level \(level) of 4").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Source: \(source.displayName)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            case .free(let source):
                Text("Free entry").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Source: \(source.displayName) (fee = no)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            case .estimated(let tier, let reason):
                Text("\(tier.label) (estimate)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Estimated from the type of place (\(reason)), not from actual prices.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var scoreSection: some View {
        if let score = place.score {
            ProfileSection(title: "Why it's here") {
                ForEach(score.components.sorted { $0.weight > $1.weight }) { component in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(component.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(Int((component.value * 100).rounded()))").font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surfaceHigh)
                                Capsule().fill(Theme.accent.opacity(0.85))
                                    .frame(width: max(4, proxy.size.width * component.value))
                            }
                        }
                        .frame(height: 5)
                        Text(component.explanation).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
                Text(String(format: "Data confidence %d%% — the score is damped when data is sparse.", Int((score.confidence * 100).rounded())))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var sourcesSection: some View {
        ProfileSection(title: "Sources & confidence") {
            HStack(spacing: 8) {
                ConfidenceBadge(level: place.confidence)
                Spacer()
            }
            Text(place.confidence.explanation).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            if let confirmed = place.signals.lastConfirmed {
                Text("Last confirmed by a mapper: \(confirmed.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(place.sources, id: \.identifier) { source in
                if let url = source.url {
                    Link(destination: url) { InfoRow(symbol: "link", title: source.provider.displayName, value: source.identifier, isLink: true) }
                } else {
                    InfoRow(symbol: "link", title: source.provider.displayName, value: source.identifier)
                }
            }
            if place.providers.contains(.openStreetMap) {
                Text("Map data © OpenStreetMap contributors (ODbL). Spotted an error? Fix it on openstreetmap.org.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var exploreSection: some View {
        ProfileSection(title: "Find more") {
            Text("Opens each platform's own search. Sidestreet doesn't read or analyse these platforms.")
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            ForEach(ExternalLinkBuilder.links(for: place, cityName: area?.label)) { link in
                Link(destination: link.url) {
                    InfoRow(symbol: link.platform.symbolName, title: link.platform.title, value: link.subtitle, isLink: true)
                }
            }
        }
    }

    @ViewBuilder
    private var videosSection: some View {
        switch videos {
        case .videos(let list)? where !list.isEmpty:
            ProfileSection(title: "On YouTube") {
                ForEach(list) { video in
                    if let url = video.watchURL {
                        Link(destination: url) { VideoRow(video: video) }
                    }
                }
                Text("Results from the YouTube Data API using your key.").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        case .failed(let message)?:
            ProfileSection(title: "On YouTube") {
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            }
        default:
            EmptyView()
        }
    }

    // MARK: Actions

    private func loadDetails() async {
        let details = model.details
        let place = self.place
        let photosEnabled = settings.nearbyPhotosEnabled
        async let summaryResult = details.wikipediaSummary(for: place)
        async let photosResult = details.nearbyPhotos(for: place, enabled: photosEnabled)
        if place.primaryImage == nil {
            foundPhoto = await AppEnvironment.photoFinder.photo(for: place, options: model.photoOptions)
        }
        if settings.lookAroundEnabled {
            lookAroundScene = await LookAroundService.shared.scene(at: place.coordinate)
        }
        summary = await summaryResult
        nearbyPhotos = await photosResult
        if !place.isNameInferred {
            let query = "\(place.name) \(area?.label ?? "")"
            let result = await details.youtubeVideos(query: query, cacheKey: place.id)
            videos = result
        }
    }

    private func openInMaps() async {
        isOpeningMaps = true
        defer { isOpeningMaps = false }
        if appleItem == nil { appleItem = await model.details.appleMapItem(for: place) }
        let item = appleItem ?? PlaceDetailService.coordinateMapItem(for: place)
        _ = item.openInMaps(launchOptions: nil)
    }
}

// MARK: - Building blocks

struct ProfileSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).eyebrow()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct InfoRow: View {
    var symbol: String
    var title: String
    var value: String
    var isLink = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textTertiary)
                Text(value).font(.system(size: 15)).foregroundStyle(isLink ? Theme.accent : Theme.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if isLink {
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct PhotoTile: View {
    var image: PlaceImage
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RemoteImage(url: image.url) {
                Rectangle().fill(Theme.surfaceHigh)
            }
            .frame(width: 220, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                if image.origin == .nearby {
                    Tag(text: "Nearby", color: Theme.textPrimary).padding(8)
                } else if image.origin == .streetLevel {
                    Tag(text: "Street view", color: Theme.textPrimary).padding(8)
                } else if image.provider == .venueWebsite {
                    Tag(text: "Website", color: Theme.textPrimary).padding(8)
                }
            }
            Text([image.attribution, image.license].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
        }
        .onTapGesture {
            if let page = image.pageURL { openURL(page) }
        }
    }
}

struct VideoRow: View {
    var video: YouTubeService.Video

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: video.thumbnail) { Rectangle().fill(Theme.surfaceHigh) }
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Text(video.channel).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
