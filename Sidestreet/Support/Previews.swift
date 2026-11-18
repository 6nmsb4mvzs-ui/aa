import SwiftUI

#if DEBUG
/// SwiftUI previews backed by the clearly-labelled SampleData set
/// (fictional places; never mixed with real results).
@MainActor
enum PreviewSupport {
    static func environment() -> (AppModel, AppSettings) {
        let defaults = UserDefaults(suiteName: "sidestreet.previews") ?? .standard
        let settings = AppSettings(defaults: defaults)
        settings.demoMode = true
        let model = AppModel(settings: settings)
        model.loadPreviewData()
        return (model, settings)
    }
}

extension View {
    /// Injects a sample-data app model for previews.
    @MainActor
    func previewEnvironment() -> some View {
        let env = PreviewSupport.environment()
        return self
            .environment(env.0)
            .environment(env.1)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
    }
}

#Preview("App (sample data)") {
    RootView().previewEnvironment()
}

#Preview("Discovery cards") {
    ScrollView {
        VStack(spacing: 18) {
            ForEach(SampleData.places().prefix(3)) { place in
                DiscoveryCard(place: place, area: SampleData.area())
            }
        }
        .padding()
    }
    .background(Theme.background)
    .previewEnvironment()
}

#Preview("Event card") {
    EventCard(event: SampleData.events()[0], area: SampleData.area())
        .padding()
        .background(Theme.background)
        .previewEnvironment()
}

#Preview("Place profile") {
    PlaceProfileView(place: SampleData.places()[2], detent: .constant(.large))
        .background(Theme.surface)
        .previewEnvironment()
}
#endif
