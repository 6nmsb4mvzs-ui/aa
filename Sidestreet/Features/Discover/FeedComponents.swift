import SwiftUI

/// Location title, radius pill and refresh — the top of the Discover feed.
struct LocationHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Binding var showLocationPicker: Bool
    @Binding var showRadius: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                showLocationPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: centerSymbol).font(.system(size: 11, weight: .bold))
                        Text(model.locationSubtitle ?? "Discover").lineLimit(1)
                    }
                    .eyebrow(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.locationTitle.uppercased())
                            .font(.display(38))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location: \(model.locationTitle). Change location")
            Spacer(minLength: 8)
            Button {
                withAnimation(.snappy(duration: 0.25)) { showRadius.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "scope").font(.system(size: 12, weight: .semibold))
                    Text(Format.radius(model.radiusMeters, metric: settings.useMetric))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(showRadius ? Color.black : Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(showRadius ? Theme.accent : Theme.surfaceHigh, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search radius \(Format.radius(model.radiusMeters, metric: settings.useMetric))")
            .padding(.bottom, 6)
        }
    }

    private var centerSymbol: String {
        switch model.resolution {
        case .gps: return "location.fill"
        case .city: return "building.2"
        default: return "location.slash"
        }
    }
}

/// Continuous radius slider; changes apply after a short debounce without restarting anything.
struct RadiusControl: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var draft: Double = SearchRadius.defaultMeters
    @State private var isEditing = false

    // Slider works on a square-root scale so small radii get more precision.
    private var sliderValue: Binding<Double> {
        Binding(
            get: { sqrt(draft) },
            set: { draft = ($0 * $0).rounded() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Search radius").eyebrow()
                Spacer()
                Text(Format.radius(draft, metric: settings.useMetric))
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            Slider(value: sliderValue, in: sqrt(SearchRadius.minimumMeters)...sqrt(SearchRadius.maximumMeters)) { editing in
                isEditing = editing
                if !editing { model.setRadius(draft) }
            }
            .tint(Theme.accent)
            HStack {
                Text(Format.radius(SearchRadius.minimumMeters, metric: settings.useMetric))
                Spacer()
                Text(model.area?.centerSource == .gps ? "centred on you" : "centred on the city")
                Spacer()
                Text(Format.radius(SearchRadius.maximumMeters, metric: settings.useMetric))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { draft = model.radiusMeters }
        .onChange(of: model.radiusMeters) { _, newValue in
            if !isEditing { draft = newValue }
        }
    }
}

/// Horizontal on/off category chips. "All" clears the selection.
struct FilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(title: "All", symbol: "square.grid.2x2", isOn: model.filter.isShowingAll, tint: Theme.accent) {
                    model.clearFilters()
                }
                ForEach(DiscoveryCategory.allCases) { category in
                    chip(title: category.title, symbol: category.symbolName,
                         isOn: model.filter.selected.contains(category), tint: Theme.tint(for: category)) {
                        model.toggle(category)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, symbol: String, isOn: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color.black : Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn ? tint : Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
