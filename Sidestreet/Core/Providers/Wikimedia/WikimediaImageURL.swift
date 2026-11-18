import Foundation

/// Builds Wikimedia Commons image URLs without an API request.
///
/// Commons stores files at `/<h>/<hh>/<Name>` where `hh` is the first two hex
/// digits of the MD5 of the underscore-normalised file name. Thumbnails are
/// served at standard widths only (non-standard widths are rejected), so the
/// app uses 500 px and 960 px.
enum WikimediaImageURL {
    static let standardWidths = [500, 960]

    /// Normalises "File:Foo bar.jpg", URLs and Special:FilePath links to "Foo_bar.jpg".
    static func normalizedFileName(from value: String) -> String? {
        var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return nil }
        for marker in ["Special:FilePath/", "/wiki/File:", "/wiki/Image:"] {
            if let range = name.range(of: marker) {
                name = String(name[range.upperBound...])
                break
            }
        }
        if let query = name.firstIndex(of: "?") { name = String(name[..<query]) }
        if let decoded = name.removingPercentEncoding { name = decoded }
        for prefix in ["File:", "file:", "Image:", "image:"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        name = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        guard !name.isEmpty, !name.hasPrefix("Category:"), name.contains(".") else { return nil }
        // Upper-case first letter (MediaWiki title normalisation).
        name = name.prefix(1).uppercased() + name.dropFirst()
        return name
    }

    static func isRasterImage(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "webp", "gif", "svg"].contains(ext)
    }

    /// Thumbnail URL at a standard width, or nil for unsupported files.
    static func thumbnail(fileName rawName: String, width: Int = 960) -> URL? {
        guard let name = normalizedFileName(from: rawName), isRasterImage(name) else { return nil }
        let hash = MD5.hex(name)
        let a = String(hash.prefix(1))
        let ab = String(hash.prefix(2))
        let ext = (name as NSString).pathExtension.lowercased()
        let thumbName = ext == "svg" ? "\(width)px-\(name).png" : "\(width)px-\(name)"
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedThumb = thumbName.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/\(a)/\(ab)/\(encodedName)/\(encodedThumb)")
    }

    /// The file's description page (license and author information).
    static func descriptionPage(fileName rawName: String) -> URL? {
        guard let name = normalizedFileName(from: rawName),
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://commons.wikimedia.org/wiki/File:\(encoded)")
    }
}
