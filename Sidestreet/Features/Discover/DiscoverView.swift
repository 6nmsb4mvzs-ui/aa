import SwiftUI

/// The main, image-led discovery feed.
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var showLocationPicker = false
    @State private var showRadius = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    LocationHeader(showLocationPicker: $showLocationPicker, showRadius: $showRadius)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 8)
                    if showRadius {
                        RadiusControl()
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                    Section {
                        if model.isDemo {
                            SampleDataBanner()
                                .padding(.horizontal, Theme.gutter)
                                .padding(.bottom, 14)
                        }
                        mainContent
                    } header: {
                        FilterBar()
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Theme.background.opacity(0.97))
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView()
                    .presentationDetents([.large])
                    .presentationBackground(Theme.surface)
            }
            .placeSheet()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch screenState {
        case .onboarding:
            OnboardingView(showLocationPicker: $showLocationPicker)
                .padding(.horizontal, Theme.gutter)
        case .needsCity(let reason):
            StateMessage(
                systemImage: "location.slash",
                title: "Where to?",
                message: reason == .locationUnavailable
                    ? "Your location couldn't be found. Search for a city to start discovering."
                    : "Location access is off, so Sidestreet can't centre on you. Search for a city instead, or allow location in the iOS Settings app."
            ) {
                VStack(spacing: 10) {
                    Button("Search a city") { showLocationPicker = true }.buttonStyle(PillButtonStyle())
                    if reason != .locationUnavailable, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button("Open iOS Settings") { UIApplication.shared.open(url) }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
            }
        case .loading(let message):
            LoadingCards(message: message)
                .padding(.horizontal, Theme.gutter)
        case .failed(let message):
            StateMessage(systemImage: "wifi.exclamationmark", title: "Couldn't load discoveries", message: message) {
                Button("Try again") { model.discover(force: true) }.buttonStyle(PillButtonStyle())
            }
        case .empty:
            StatusLine()
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
            EmptyFeedView()
        case .feed:
            StatusLine()
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
            ForEach(Array(model.visibleFeed.enumerated()), id: \.element.id) { item in
                FeedItem(index: item.offset, entry: item.element)
            }
            FeedTail()
                .padding(.horizontal, Theme.gutter)
        }
    }

    private enum ScreenState {
        case onboarding
        case needsCity(CenterResolution.FallbackReason)
        case loading(String)
        case failed(String)
        case empty
        case feed
    }

    private var screenState: ScreenState {
        if !model.isDemo {
            switch model.resolution {
            case .needsPermission where model.area == nil:
                return .onboarding
            case .needsCity(let reason):
                return .needsCity(reason)
            case .locating where model.feed.isEmpty:
                return .loading("Finding your location…")
            default:
                break
            }
        }
        if model.feed.isEmpty {
            switch model.loadState {
            case .idle, .loading, .refining:
                return .loading("Searching map data, encyclopaedias and local listings…")
            case .failed(let message):
                return .failed(message)
            case .loaded:
                return .empty
            }
        }
        return .feed
    }
}

/// A feed position: the card plus any interstitial card that follows it.
/// Kept as its own view so the feed's ViewBuilder stays cheap to type-check.
struct FeedItem: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let entry: FeedEntry

    private var lastIndex: Int { max(0, model.feed.count - 1) }
    private var showsHotspots: Bool { index == min(3, lastIndex) && !model.hotspots.isEmpty }
    private var showsCityCard: Bool { index == min(7, lastIndex) }

    var body: some View {
        VStack(spacing: 18) {
            FeedRow(entry: entry)
                .onAppear { model.entryAppeared(entry) }
            if showsHotspots {
                HotspotsCard()
            }
            if showsCityCard {
                CityExploreCard()
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 18)
    }
}

/// One card in the feed; tapping opens the compact preview sheet.
struct FeedRow: View {
    @Environment(AppModel.self) private var model
    var entry: FeedEntry

    var body: some View {
        Button {
            model.selectedEntry = entry
        } label: {
            switch entry {
            case .place(let place):
                DiscoveryCard(place: place, area: model.area)
            case .event(let event):
                EventCard(event: event, area: model.area)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FeedTail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.hasMoreToShow {
            ProgressView().tint(Theme.textSecondary).frame(maxWidth: .infinity).padding()
        } else if model.loadState == .refining {
            HStack(spacing: 8) {
                ProgressView().tint(Theme.textSecondary)
                Text("Checking more sources…").font(.meta).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
            FeedFooter()
        }
    }
}

struct LoadingCards: View {
    var message: String

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ProgressView().tint(Theme.textSecondary)
                Text(message).font(.meta).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            SkeletonCard()
            SkeletonCard()
        }
    }
}

struct EmptyFeedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        StateMessage(
            systemImage: "binoculars",
            title: "Nothing here yet",
            message: model.filter.isShowingAll
                ? "No discoveries in this radius. Try a larger radius or another area."
                : "No matches for these filters. Clear the filters or widen the radius."
        ) {
            HStack {
                if !model.filter.isShowingAll {
                    Button("Clear filters") { model.clearFilters() }.buttonStyle(PillButtonStyle(prominent: false))
                }
                Button("Widen radius") {
                    model.setRadius(min(SearchRadius.maximumMeters, model.radiusMeters * 2))
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }
}

/// Counts, freshness and source warnings above the feed.
struct StatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(model.feed.count) results")
                if model.eventCount > 0 { Text("· \(model.eventCount) events") }
                if let snapshot = model.snapshot, !model.isDemo {
                    Text("· " + (snapshot.isFromCache ? "cached " : "updated ") + Format.relative(snapshot.generatedAt))
                }
                Spacer()
                if model.loadState == .refining || model.isLoadingSources {
                    ProgressView().controlSize(.mini).tint(Theme.textTertiary)
                }
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.textTertiary)
            if !model.isDemo {
                SourceStatusRow()
            }
            if model.isMapDataLoading {
                Label("Loading shops, cafés and spots from OpenStreetMap — busy public map servers can take up to a minute. Results appear as they arrive.",
                      systemImage: "hourglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(model.failedSources) { failure in
                Label("\(failure.provider.displayName) unavailable — \(failure.message)", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .lineLimit(2)
            }
            if model.mapDataFailed {
                Button("Retry map data") { model.discover(force: true) }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
    }
}

/// One small chip per data source: loading, count, or failed.
struct SourceStatusRow: View {
    @Environment(AppModel.self) private var model

    private let order: [SourceProvider] = [.openStreetMap, .appleMaps, .wikidata, .venueWebsite]

    var body: some View {
        let statuses = model.snapshot?.sourceStatuses ?? [:]
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(order.filter { statuses[$0] != nil }) { provider in
                    SourceChip(name: shortName(provider), status: statuses[provider] ?? .idle)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func shortName(_ provider: SourceProvider) -> String {
        switch provider {
        case .openStreetMap: return "OSM"
        case .appleMaps: return "Apple Maps"
        case .wikidata: return "Wikidata"
        case .venueWebsite: return "Events"
        default: return provider.displayName
        }
    }
}

private struct SourceChip: View {
    let name: String
    let status: SourceStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .loading:
                ProgressView().controlSize(.mini).tint(Theme.textSecondary)
            case .loaded(let count), .cached(let count):
                Text("\(count)").monospacedDigit()
            case .failed:
                Image(systemName: "xmark")
            case .skipped, .idle:
                Image(systemName: "minus")
            }
            Text(name)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(status.isFailure ? Theme.warning : Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surfaceRaised, in: Capsule())
    }
}

struct FeedFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Theme.textTertiary)
            Text("That's everything in this radius.")
                .font(.meta).foregroundStyle(Theme.textSecondary)
            Text("Map data © OpenStreetMap contributors · Wikidata · Wikimedia Commons")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// First-launch screen: explains the location choice before iOS asks.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Binding var showLocationPicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("FIND THE\nOTHER CITY")
                .font(.display(52))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 28)
            Text("Thrift and vintage, skate spots, street art, brutalist blocks, record stores, DIY spaces and quiet viewpoints — the places standard guides skip.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await model.useCurrentLocation() }
                } label: {
                    Label("Use my location", systemImage: "location.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                Button {
                    showLocationPicker = true
                } label: {
                    Label("Search a city", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            }
            .padding(.top, 8)
            Text("Location is used only while the app is open and only to centre your search. The search area is sent to the data sources listed in Settings → Privacy & network; nothing else leaves your phone.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 12)
    }
}
