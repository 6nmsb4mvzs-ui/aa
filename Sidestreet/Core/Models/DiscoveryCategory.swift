import Foundation

/// Top-level discovery categories, used for the on/off filter chips.
/// A place can belong to several categories (a graffiti wall is both
/// street art and a photo spot).
enum DiscoveryCategory: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case fashion
    case markets
    case skate
    case streetArt
    case architecture
    case photo
    case music
    case culture
    case cafes
    case food
    case hiddenGems
    case nature
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fashion: return "Fashion"
        case .markets: return "Flea & Markets"
        case .skate: return "Skate"
        case .streetArt: return "Street Art"
        case .architecture: return "Urban Explore"
        case .photo: return "Photo Spots"
        case .music: return "Music & Night"
        case .culture: return "Alt Culture"
        case .cafes: return "Cafés"
        case .food: return "Food"
        case .hiddenGems: return "Hidden Gems"
        case .nature: return "Nature"
        case .events: return "Events"
        }
    }

    /// SF Symbol name used by the app layer.
    var symbolName: String {
        switch self {
        case .fashion: return "tshirt"
        case .markets: return "tag"
        case .skate: return "figure.skateboarding"
        case .streetArt: return "paintbrush.pointed"
        case .architecture: return "building.2"
        case .photo: return "camera"
        case .music: return "opticaldisc"
        case .culture: return "theatermasks"
        case .cafes: return "cup.and.saucer"
        case .food: return "fork.knife"
        case .hiddenGems: return "sparkle.magnifyingglass"
        case .nature: return "leaf"
        case .events: return "calendar"
        }
    }

    /// Whether places of this category are usually commercial businesses.
    var isCommercial: Bool {
        switch self {
        case .fashion, .markets, .music, .culture, .cafes, .food: return true
        case .skate, .streetArt, .architecture, .photo, .hiddenGems, .nature, .events: return false
        }
    }
}
