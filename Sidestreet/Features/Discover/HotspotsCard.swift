import SwiftUI

/// "Clusters worth a walk": streets with several independent fashion
/// stores, street-art hotspots and nightlife strips, derived from the
/// discovered places.
struct HotspotsCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var expanded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clusters worth a walk").eyebrow(Theme.accent)
                Text("Where the good stuff bunches up")
                    .font(.display(26))
                    .foregroundStyle(Theme.textPrimary)
            }
            ForEach(model.hotspots) { hotspot in
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            expanded = expanded == hotspot.id ? nil : hotspot.id
                        }
                    } label: {
                        row(hotspot)
                    }
                    .buttonStyle(.plain)
                    if expanded == hotspot.id {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(hotspot.memberIDs, id: \.self) { id in
                                if let place = model.place(withID: id) {
                                    Button {
                                        model.selectedEntry = .place(place)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: place.kind.symbolName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Theme.tint(for: place.primaryCategory))
                                                .frame(width: 18)
                                            Text(place.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(place.kind.label).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.leading, 40)
                    }
                }
                if hotspot.id != model.hotspots.last?.id {
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .padding(Theme.gutter)
        .cardSurface()
    }

    private func row(_ hotspot: Hotspot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hotspot.theme.category.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Theme.tint(for: hotspot.theme.category), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(hotspot.theme.label).eyebrow(Theme.tint(for: hotspot.theme.category))
                Text(hotspot.title).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text(subtitle(hotspot)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                if !hotspot.styles.isEmpty {
                    Text(hotspot.styles.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: expanded == hotspot.id ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 6)
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ hotspot: Hotspot) -> String {
        var text = "\(hotspot.count) \(hotspot.theme.memberNoun) within a short walk"
        if let area = model.area {
            text += " · " + Format.distance(GeoMath.distance(hotspot.center, area.center), metric: settings.useMetric) + " away"
        }
        return text
    }
}
