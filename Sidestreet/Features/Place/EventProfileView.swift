import MapKit
import SwiftUI

/// Preview + profile for a dated event. Dates come verbatim from the source.
struct EventProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    var event: DiscoveryEvent
    @Binding var detent: PresentationDetent
    @Binding var selection: FeedEntry?

    private var timeZone: TimeZone {
        event.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? model.area?.timeZone ?? .current
    }

    private var venue: Place? {
        guard let id = event.venuePlaceID else { return nil }
        return model.snapshot?.places.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    DateBlock(date: event.start, timeZone: timeZone)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.kind.label).eyebrow(Theme.tint(for: .events))
                        Text(event.title)
                            .font(.display(30))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(detent == .large ? 4 : 2)
                    }
                }
                if event.isSample { SampleDataBanner() }
                HStack(spacing: 10) {
                    Text(Format.eventDate(event, timeZone: timeZone)).font(.metaMono).foregroundStyle(Theme.textPrimary)
                    if let area = model.area, let coordinate = event.coordinate {
                        Text(Format.distance(GeoMath.distance(coordinate, area.center), metric: settings.useMetric))
                            .font(.metaMono).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    ConfidenceBadge(level: event.confidence)
                }
                HStack(spacing: 10) {
                    if let url = event.url {
                        Button { openURL(url) } label: {
                            Label("Event page", systemImage: "safari").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                    if let coordinate = event.coordinate {
                        Button {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                                latitude: coordinate.latitude, longitude: coordinate.longitude)))
                            item.name = event.venueName ?? event.title
                            _ = item.openInMaps(launchOptions: nil)
                        } label: {
                            Label("Maps", systemImage: "map").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle(prominent: event.url == nil))
                    }
                }
                if detent != .large {
                    Button {
                        withAnimation { detent = .large }
                    } label: {
                        Label("Details", systemImage: "chevron.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(prominent: false))
                } else {
                    details
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var details: some View {
        if let image = event.imageURL {
            RemoteImage(url: image) { Rectangle().fill(Theme.surfaceHigh) }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        if let summary = event.summary {
            ProfileSection(title: "About") {
                Text(summary).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
            }
        }
        ProfileSection(title: "When & where") {
            InfoRow(symbol: "calendar", title: "Date", value: Format.eventDate(event, timeZone: timeZone))
            if let recurrence = event.recurrence {
                InfoRow(symbol: "repeat", title: "Recurring schedule", value: recurrence.scheduleDescription)
            }
            if let venueName = event.venueName {
                InfoRow(symbol: "building.2", title: "Venue", value: venueName)
            }
            if let address = event.addressText {
                InfoRow(symbol: "mappin.and.ellipse", title: "Address", value: address)
            }
            if timeZone.identifier != TimeZone.current.identifier {
                Text("Times shown in local time (\(timeZone.identifier)).").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        ProfileSection(title: "Source") {
            Text(sourceExplanation).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            if let url = event.source.url {
                Link(destination: url) {
                    InfoRow(symbol: "link", title: event.source.provider.displayName, value: url.host ?? url.absoluteString, isLink: true)
                }
            }
            Text(event.confidence.explanation).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
        }
        if let venue {
            Button {
                selection = nil
                Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    selection = .place(venue)
                }
            } label: {
                InfoRow(symbol: venue.kind.symbolName, title: "Venue profile", value: venue.name, isLink: true)
            }
            .buttonStyle(.plain)
            .padding(16)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var sourceExplanation: String {
        switch event.source.provider {
        case .venueWebsite:
            return "Date and details as published in machine-readable form (schema.org) on the venue's own website."
        case .openStreetMap:
            return "Next date calculated from the recurring schedule recorded in OpenStreetMap. Check the organiser's channels before going — markets can pause or move."
        case .sample:
            return "Fictional sample event."
        default:
            return "Published by \(event.source.provider.displayName)."
        }
    }
}
