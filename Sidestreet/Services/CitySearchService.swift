import Foundation
import MapKit
import Observation

/// Worldwide city autocomplete using Apple's on-device `MKLocalSearchCompleter`
/// (free, no API key). Nominatim is deliberately not used here because its
/// usage policy forbids autocomplete.
@MainActor
@Observable
final class CitySearchService: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Hashable {
        var id: Int
        var title: String
        var subtitle: String
    }

    private(set) var suggestions: [Suggestion] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var completions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    /// Not observed itself (views bind their own text); setting it drives the completer.
    @ObservationIgnored var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                completer.cancel()
                suggestions = []
                completions = []
                isSearching = false
            } else {
                isSearching = true
                completer.queryFragment = trimmed
            }
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        let items = results.enumerated().map { index, completion in
            Suggestion(id: index, title: completion.title, subtitle: completion.subtitle)
        }
        MainActor.assumeIsolated {
            self.completions = results
            self.suggestions = items
            self.isSearching = false
            self.errorMessage = nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let message = (error as NSError).code == MKError.Code.placemarkNotFound.rawValue ? nil : "City search is unavailable right now."
        MainActor.assumeIsolated {
            self.isSearching = false
            self.errorMessage = message
            if message == nil { self.suggestions = [] }
        }
    }

    /// Resolves a suggestion to a city with coordinates and time zone.
    func resolve(_ suggestion: Suggestion) async -> CityChoice? {
        guard suggestion.id < completions.count else { return nil }
        let completion = completions[suggestion.id]
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        let center = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard center.isValid else { return nil }
        return CityChoice(
            name: suggestion.title.components(separatedBy: ",").first ?? suggestion.title,
            subtitle: suggestion.subtitle.isEmpty ? item.placemark.country : suggestion.subtitle,
            center: center,
            timeZoneIdentifier: item.timeZone?.identifier,
            countryCode: item.placemark.isoCountryCode
        )
    }
}
