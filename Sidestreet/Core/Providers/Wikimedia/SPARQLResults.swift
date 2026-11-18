import Foundation

/// SPARQL 1.1 JSON results format (Wikidata Query Service).
struct SPARQLResults: Decodable, Sendable {
    struct Value: Decodable, Sendable {
        var type: String
        var value: String
    }

    struct Results: Decodable, Sendable {
        var bindings: [[String: Value]]
    }

    var results: Results
}

extension Dictionary where Key == String, Value == SPARQLResults.Value {
    func string(_ key: String) -> String? { self[key]?.value }

    /// "http://www.wikidata.org/entity/Q42" → "Q42"
    func entityID(_ key: String) -> String? {
        guard let value = self[key]?.value, let last = value.split(separator: "/").last else { return nil }
        let id = String(last)
        return id.hasPrefix("Q") ? id : nil
    }

    /// WKT "Point(lon lat)".
    func point(_ key: String) -> GeoCoordinate? {
        guard let value = self[key]?.value,
              let open = value.firstIndex(of: "("), let close = value.firstIndex(of: ")") else { return nil }
        let parts = value[value.index(after: open)..<close].split(separator: " ").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let coordinate = GeoCoordinate(latitude: parts[1], longitude: parts[0])
        return coordinate.isValid ? coordinate : nil
    }

    func int(_ key: String) -> Int? { self[key].flatMap { Int($0.value) } }
}
