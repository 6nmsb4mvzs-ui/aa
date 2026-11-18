import SwiftUI

/// City search with autocomplete, "use my location" and the radius slider.
struct LocationPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var resolvingID: Int?
    @State private var resolveFailed = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            dismiss()
                            await model.useCurrentLocation()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "location.fill").foregroundStyle(Theme.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use my current location").foregroundStyle(Theme.textPrimary)
                                Text(locationHint).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            if model.usesCurrentLocation, case .gps = model.resolution {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .disabled(model.location.authorization == .denied || model.location.authorization == .restricted)
                }
                .listRowBackground(Theme.surfaceRaised)

                Section {
                    RadiusControl()
                        .listRowInsets(EdgeInsets())
                }
                .listRowBackground(Color.clear)

                if !query.isEmpty {
                    Section("Cities & places") {
                        if model.citySearch.suggestions.isEmpty {
                            Text(model.citySearch.isSearching ? "Searching…" : (model.citySearch.errorMessage ?? "No matches"))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        ForEach(model.citySearch.suggestions) { suggestion in
                            Button {
                                Task { await choose(suggestion) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title).foregroundStyle(Theme.textPrimary)
                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    if resolvingID == suggestion.id { ProgressView() }
                                }
                            }
                        }
                        if resolveFailed {
                            Text("Couldn't open that place. Try another result.").foregroundStyle(Theme.warning)
                        }
                    }
                    .listRowBackground(Theme.surfaceRaised)
                } else if !model.historyEntries.isEmpty {
                    Section("Recent") {
                        ForEach(model.historyEntries.prefix(6)) { entry in
                            Button {
                                Task {
                                    dismiss()
                                    await model.restore(entry)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: entry.centerSource == .gps ? "location" : "clock")
                                        .foregroundStyle(Theme.textTertiary).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.label).foregroundStyle(Theme.textPrimary)
                                        if let subtitle = entry.subtitle {
                                            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.surfaceRaised)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search any city or neighbourhood")
            .onChange(of: query) { _, value in
                resolveFailed = false
                model.citySearch.query = value
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var locationHint: String {
        switch model.location.authorization {
        case .denied, .restricted: return "Location access is off — enable it in the iOS Settings app"
        case .notDetermined: return "Only while using the app; never in the background"
        case .authorizedWhenInUse: return "Centres the radius on you"
        }
    }

    private func choose(_ suggestion: CitySearchService.Suggestion) async {
        resolvingID = suggestion.id
        defer { resolvingID = nil }
        guard let city = await model.citySearch.resolve(suggestion) else {
            resolveFailed = true
            return
        }
        dismiss()
        await model.selectCity(city)
    }
}
