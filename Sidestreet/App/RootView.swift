import SwiftUI

/// Bottom tab bar: Discover · Map · History · Settings.
struct RootView: View {
    enum Tab: Hashable { case discover, map, history, settings }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .discover

    var body: some View {
        TabView(selection: $tab) {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "square.stack.3d.up") }
                .tag(Tab.discover)
            DiscoveryMapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(Tab.map)
            HistoryView(onRestore: { tab = .discover })
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .toolbarBackground(Theme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(Theme.background)
        .task { await model.start() }
        .onChange(of: model.location.authorization) { _, _ in
            Task { await model.authorizationChanged() }
        }
    }
}
