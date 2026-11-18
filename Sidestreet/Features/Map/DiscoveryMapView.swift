import MapKit
import SwiftUI

/// Simple MapKit view: your location, the search radius and discovered pins.
/// Tapping a pin opens the same compact preview as the feed.
struct DiscoveryMapView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedID: String?
    @State private var sheetEntry: FeedEntry?
    @State private var lastFramedArea: SearchArea?

    var body: some View {
        let entries = model.mapEntries
        let markers = entries.compactMap { entry in
            entry.coordinate.map { MapMarkerItem(id: entry.id, coordinate: $0.clLocation, entry: entry, title: title(for: entry)) }
        }
        ZStack(alignment: .top) {
            Map(position: $position, selection: $selectedID) {
                UserAnnotation()
                if let area = model.area {
                    MapCircle(center: area.center.clLocation, radius: area.radiusMeters)
                        .foregroundStyle(Theme.accent.opacity(0.06))
                        .stroke(Theme.accent.opacity(0.55), lineWidth: 1.2)
                    if area.centerSource == .city {
                        Annotation("Centre", coordinate: area.center.clLocation, anchor: .center) {
                            Circle().fill(Theme.accent).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(.black, lineWidth: 2))
                        }
                        .annotationTitles(.hidden)
                    }
                }
                ForEach(markers) { marker in
                    Annotation(marker.title, coordinate: marker.coordinate, anchor: .bottom) {
                        MapPin(entry: marker.entry, isSelected: selectedID == marker.id)
                    }
                    .annotationTitles(.hidden)
                    .tag(marker.id)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                sheetEntry = entries.first { $0.id == id }
            }
            .onChange(of: sheetEntry) { _, entry in
                if entry == nil { selectedID = nil }
            }
            .onChange(of: model.area) { _, area in frame(area) }
            .onAppear { frame(model.area) }

            MapHeader(count: entries.count)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
        }
        .placeSheet(item: $sheetEntry, interactiveBackground: true)
    }

    private func frame(_ area: SearchArea?) {
        guard let area, area != lastFramedArea else { return }
        lastFramedArea = area
        let span = area.radiusMeters * 2.3
        withAnimation(.easeInOut(duration: 0.4)) {
            position = .region(MKCoordinateRegion(center: area.center.clLocation, latitudinalMeters: span, longitudinalMeters: span))
        }
    }

    private func title(for entry: FeedEntry) -> String {
        switch entry {
        case .place(let place): return place.name
        case .event(let event): return event.title
        }
    }
}

private struct MapMarkerItem: Identifiable {
    var id: String
    var coordinate: CLLocationCoordinate2D
    var entry: FeedEntry
    var title: String
}

private struct MapPin: View {
    var entry: FeedEntry
    var isSelected: Bool

    private var symbol: String {
        switch entry {
        case .place(let place): return place.kind.symbolName
        case .event(let event): return event.kind.symbolName
        }
    }

    private var tint: Color { Theme.tint(for: entry.primaryCategory) }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: isSelected ? 15 : 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: isSelected ? 36 : 26, height: isSelected ? 36 : 26)
                .background(tint, in: Circle())
                .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1.5))
            Triangle()
                .fill(tint)
                .frame(width: 8, height: 5)
        }
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MapHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    var count: Int

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.locationTitle.uppercased())
                    .font(.display(22))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(count) on map · \(Format.radius(model.radiusMeters, metric: settings.useMetric)) radius" + (model.filter.isShowingAll ? "" : " · filtered"))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if model.loadState == .loading || model.loadState == .refining {
                ProgressView().tint(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

extension GeoCoordinate {
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
