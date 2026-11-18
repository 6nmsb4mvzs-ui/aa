import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var cacheSize: Int?
    @State private var confirmClearHistory = false
    @State private var hasYouTubeKey = KeychainStore.youTubeAPIKey?.isEmpty == false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Discovery") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Default radius")
                            Spacer()
                            Text(Format.radius(settings.defaultRadiusMeters, metric: settings.useMetric))
                                .monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                        Slider(value: Binding(get: { sqrt(settings.defaultRadiusMeters) },
                                              set: { settings.defaultRadiusMeters = ($0 * $0).rounded() }),
                               in: sqrt(SearchRadius.minimumMeters)...sqrt(SearchRadius.maximumMeters))
                    }
                    Toggle("Metric units (km)", isOn: $settings.useMetric)
                    Toggle("Show niche score on cards", isOn: $settings.showNicheScore)
                    Toggle("Prefer my location inside a searched city", isOn: $settings.preferGPSInsideCity)
                    NavigationLink("How the niche score works") { ScoringExplainerView() }
                }

                Section {
                    Toggle("OpenStreetMap (always on)", isOn: .constant(true)).disabled(true)
                    Toggle("Wikidata & Wikipedia", isOn: $settings.wikidataEnabled)
                    Toggle("Apple Maps search", isOn: $settings.appleMapsEnabled)
                    Toggle("Venue websites (events)", isOn: $settings.venueEventsEnabled)
                    Toggle("Nearby photos (Wikimedia Commons)", isOn: $settings.nearbyPhotosEnabled)
                    Toggle("Look Around street imagery", isOn: $settings.lookAroundEnabled)
                    NavigationLink {
                        YouTubeKeyView(hasKey: $hasYouTubeKey)
                    } label: {
                        HStack {
                            Text("YouTube videos")
                            Spacer()
                            Text(hasYouTubeKey ? "Key added" : "Optional").foregroundStyle(Theme.textSecondary)
                        }
                    }
                    NavigationLink("Data sources & limitations") { DataSourcesView() }
                } header: {
                    Text("Data sources")
                } footer: {
                    Text("All sources are free. TikTok, Instagram, Pinterest and Reddit offer no API this app can use, so profiles link to their own search instead.")
                }

                Section {
                    Toggle("Background cache refresh", isOn: $settings.backgroundRefreshEnabled)
                    HStack {
                        Text("Temporary cache")
                        Spacer()
                        Text(cacheSize.map(Format.bytes) ?? "…").foregroundStyle(Theme.textSecondary)
                    }
                    Button("Clear cache") {
                        Task {
                            await model.clearCache()
                            cacheSize = await AppEnvironment.cache.diskSize()
                        }
                    }
                    Button("Clear search history", role: .destructive) { confirmClearHistory = true }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Results are cached for 24 hours to avoid repeat requests; iOS may clear the cache at any time. Background refresh re-fetches your last area when iOS allows it — no exact schedule is guaranteed and location is never used in the background.")
                }

                Section {
                    NavigationLink("Privacy & network") { PrivacyView() }
                    NavigationLink("Attribution & licences") { AttributionView() }
                    Toggle("Demo mode (sample data)", isOn: $settings.demoMode)
                } header: {
                    Text("About")
                } footer: {
                    Text("Demo mode shows clearly-labelled fictional places for trying the interface. It never mixes with real results.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .task { cacheSize = await AppEnvironment.cache.diskSize() }
            .onChange(of: settings.appleMapsEnabled) { _, _ in model.sourcesChanged() }
            .onChange(of: settings.wikidataEnabled) { _, _ in model.sourcesChanged() }
            .onChange(of: settings.venueEventsEnabled) { _, _ in model.sourcesChanged() }
            .onChange(of: settings.demoMode) { _, _ in Task { await model.demoModeChanged() } }
            .onChange(of: settings.backgroundRefreshEnabled) { _, enabled in
                if enabled { BackgroundRefresh.schedule() } else { BackgroundRefresh.cancel() }
            }
            .confirmationDialog("Clear all search history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { Task { await model.clearHistory() } }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Optional YouTube Data API key (stored in the Keychain).
struct YouTubeKeyView: View {
    @Binding var hasKey: Bool
    @State private var key = ""
    @State private var saved = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                SecureField("Paste your API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save key") {
                    KeychainStore.youTubeAPIKey = key
                    hasKey = !key.trimmingCharacters(in: .whitespaces).isEmpty
                    saved = true
                    key = ""
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasKey {
                    Button("Remove key", role: .destructive) {
                        KeychainStore.youTubeAPIKey = nil
                        hasKey = false
                    }
                }
                if saved { Text("Saved in the iPhone Keychain.").foregroundStyle(Theme.positive) }
            } footer: {
                Text("With a key, place profiles show related YouTube videos. Without one, the app opens YouTube search instead. The key is stored only in this iPhone's Keychain.")
            }
            Section("Get a free key (about 5 minutes)") {
                Text("1. Open console.cloud.google.com and sign in with a Google account.")
                Text("2. Create a project (any name).")
                Text("3. APIs & Services → Library → enable “YouTube Data API v3”.")
                Text("4. APIs & Services → Credentials → Create credentials → API key.")
                Text("5. Recommended: restrict the key to the YouTube Data API v3 (and optionally to this app’s bundle ID).")
                Text("Free quota: 10,000 units per day; each search costs 100 units (≈100 profile lookups/day). No billing account is needed for this API.")
                    .foregroundStyle(Theme.textSecondary)
                Button("Open Google Cloud Console") {
                    if let url = URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com") { openURL(url) }
                }
            }
            .font(.system(size: 14))
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("YouTube")
    }
}
