import MapKit
import SwiftUI

extension View {
    /// Presents the compact preview → full profile sheet for a feed entry.
    func placeSheet(item: Binding<FeedEntry?>, interactiveBackground: Bool = false) -> some View {
        modifier(PlaceSheetModifier(item: item, interactiveBackground: interactiveBackground))
    }

    /// Sheet bound to the Discover feed's selection.
    func placeSheet() -> some View {
        modifier(ModelPlaceSheetModifier())
    }
}

private struct ModelPlaceSheetModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content.placeSheet(item: $model.selectedEntry)
    }
}

private struct PlaceSheetModifier: ViewModifier {
    @Binding var item: FeedEntry?
    var interactiveBackground: Bool

    func body(content: Content) -> some View {
        content.sheet(item: $item) { entry in
            EntrySheet(entry: entry, selection: $item, interactiveBackground: interactiveBackground)
        }
    }
}

/// Height of the compact preview detent.
let compactSheetHeight: CGFloat = 340

private struct EntrySheet: View {
    var entry: FeedEntry
    @Binding var selection: FeedEntry?
    var interactiveBackground: Bool
    @State private var detent: PresentationDetent = .height(compactSheetHeight)

    var body: some View {
        Group {
            switch entry {
            case .place(let place):
                PlaceProfileView(place: place, detent: $detent)
            case .event(let event):
                EventProfileView(event: event, detent: $detent, selection: $selection)
            }
        }
        .presentationDetents([.height(compactSheetHeight), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
        .presentationCornerRadius(24)
        .presentationBackgroundInteraction(interactiveBackground ? .enabled(upThrough: .height(compactSheetHeight)) : .disabled)
    }
}

/// Shows Apple's own place card (hours, photos, ratings where Apple has
/// them) on iOS 18+. On older systems the button opens Apple Maps instead.
struct AppleMapsCardModifier: ViewModifier {
    @Binding var item: MKMapItem?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.mapItemDetailSheet(item: $item)
        } else {
            content
        }
    }
}
