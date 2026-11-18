import SwiftUI

/// Large visual card for a place.
struct DiscoveryCard: View {
    @Environment(AppSettings.self) private var settings
    var place: Place
    var area: SearchArea?

    private var tint: Color { Theme.tint(for: place.primaryCategory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                CardImage(place: place)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.kind.label).eyebrow(tint)
                    Text(place.name)
                        .font(.display(30))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                }
                .padding(Theme.gutter)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    if place.isSample { Tag(text: "Sample", color: Theme.accent, filled: true) }
                    if place.confidence == .uncertain { Tag(text: "Unverified", systemImage: "questionmark", color: Theme.warning, filled: true) }
                }
                .padding(12)
            }
            MetaRow(place: place, area: area)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
        }
        .cardSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens a preview")
    }
}

/// Distance · open status · price · neighbourhood.
struct MetaRow: View {
    @Environment(AppSettings.self) private var settings
    var place: Place
    var area: SearchArea?

    var body: some View {
        HStack(spacing: 10) {
            if let area {
                Label(Format.distance(place.distance(from: area.center), metric: settings.useMetric), systemImage: "location.north.line")
                    .font(.metaMono)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let status = Format.openStatus(place, timeZone: area?.timeZone ?? .current) {
                Text(status.isOpen ? "Open" : "Closed")
                    .font(.meta)
                    .foregroundStyle(status.isOpen ? Theme.positive : Theme.textTertiary)
            }
            if let price = place.price.shortLabel {
                Text(price + (place.price.isEstimate ? "*" : ""))
                    .font(.meta)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let hint = place.address?.shortHint ?? place.descriptors.first {
                Text(hint)
                    .font(.meta)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            ConfidenceBadge(level: place.confidence, compact: true)
        }
        .labelStyle(.titleAndIcon)
    }
}

/// Card image: linked photo → photo search (venue website, Commons,
/// street-level) → Apple Look Around → placeholder art. Non-linked sources
/// are labelled in the corner.
struct CardImage: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    var place: Place
    @State private var found: PlaceImage?
    @State private var lookAround: UIImage?

    private var image: PlaceImage? { place.primaryImage ?? found }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if let image {
                    RemoteImage(url: image.url) { fallback }
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else if let lookAround {
                    Image(uiImage: lookAround)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    fallback.frame(width: size.width, height: size.height)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let label = sourceLabel {
                    Text(label)
                        .font(.system(size: 8, weight: .bold).width(.expanded))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(12)
                }
            }
            .task(id: place.id) {
                await loadPhoto(size: size)
            }
        }
    }

    private var sourceLabel: String? {
        if let image {
            switch (image.provider, image.origin) {
            case (.venueWebsite, _): return "WEBSITE"
            case (_, .streetLevel): return "STREET VIEW · \(image.provider.displayName.uppercased())"
            case (_, .nearby): return "NEARBY PHOTO"
            default: return nil
            }
        }
        return lookAround != nil ? "LOOK AROUND" : nil
    }

    private func loadPhoto(size: CGSize) async {
        guard place.primaryImage == nil, !place.isSample else { return }
        let finder = AppEnvironment.photoFinder
        var needsSearch = true
        if let cached = await finder.cachedPhoto(for: place) {
            found = cached
            needsSearch = false
            if cached != nil { return }
        }
        // Short delay so fast scrolling doesn't trigger lookups for every card.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        if needsSearch {
            found = await finder.photo(for: place, options: model.photoOptions)
            if found != nil || Task.isCancelled { return }
        }
        guard settings.lookAroundEnabled else { return }
        if let cached = LookAroundService.shared.cachedSnapshot(at: place.coordinate) {
            lookAround = cached
            return
        }
        let target = CGSize(width: max(size.width, 300), height: max(size.height, 225))
        lookAround = await LookAroundService.shared.snapshot(at: place.coordinate, size: target)
    }

    private var fallback: some View {
        PlaceholderArtwork(symbol: place.kind.symbolName, tint: Theme.tint(for: place.primaryCategory))
    }
}

/// Card for a dated event.
struct EventCard: View {
    @Environment(AppSettings.self) private var settings
    var event: DiscoveryEvent
    var area: SearchArea?

    private var timeZone: TimeZone {
        event.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? area?.timeZone ?? .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = event.imageURL {
                        RemoteImage(url: url) { placeholder }
                    } else {
                        placeholder
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                HStack(alignment: .bottom, spacing: 14) {
                    DateBlock(date: event.start, timeZone: timeZone)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.recurrence == nil ? event.kind.label : "\(event.kind.label) · recurring")
                            .eyebrow(Theme.tint(for: .events))
                        Text(event.title)
                            .font(.display(26))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(Theme.gutter)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Tag(text: "Event", systemImage: "calendar", color: Theme.tint(for: .events), filled: true)
                    if event.isSample { Tag(text: "Sample", color: Theme.accent, filled: true) }
                }
                .padding(12)
            }
            HStack(spacing: 10) {
                Text(Format.eventDate(event, timeZone: timeZone))
                    .font(.metaMono)
                    .foregroundStyle(Theme.textPrimary)
                if let area, let coordinate = event.coordinate {
                    Text(Format.distance(GeoMath.distance(coordinate, area.center), metric: settings.useMetric))
                        .font(.metaMono)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let venue = event.venueName {
                    Text(venue).font(.meta).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                ConfidenceBadge(level: event.confidence, compact: true)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
        }
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private var placeholder: some View {
        PlaceholderArtwork(symbol: event.kind.symbolName, tint: Theme.tint(for: .events))
    }
}

/// "SAT / 21 / NOV" date stack.
struct DateBlock: View {
    var date: Date
    var timeZone: TimeZone

    private func string(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(string("EEE").uppercased()).font(.system(size: 10, weight: .bold).width(.expanded))
            Text(string("d")).font(.system(size: 26, weight: .heavy).monospacedDigit())
            Text(string("MMM").uppercased()).font(.system(size: 10, weight: .bold).width(.expanded))
        }
        .foregroundStyle(.black)
        .frame(width: 54, height: 64)
        .background(Theme.tint(for: .events), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
