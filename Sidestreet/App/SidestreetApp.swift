import SwiftUI

@main
struct SidestreetApp: App {
    @State private var settings: AppSettings
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: AppModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.perform()
        }
    }
}
