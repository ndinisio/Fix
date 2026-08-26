import Foundation

extension String {
    /// Decodes the handful of HTML entities that video APIs return in titles
    /// and channel names.
    ///
    /// Deliberately not `NSAttributedString`: that parses full HTML, must run
    /// on the main thread, and is far too heavy for unescaping an ampersand in
    /// a list row.
    var htmlDecoded: String {
        guard contains("&") else { return self }
        var result = self
        let entities = [
            ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
            ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
            ("&#38;", "&")
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}

/// Turns an ISO 8601 duration such as `PT8M41S` into `8:41`.
enum ISO8601Duration {
    static func formatted(_ value: String) -> String? {
        guard value.hasPrefix("PT") else { return nil }
        var hours = 0, minutes = 0, seconds = 0
        var number = ""
        for character in value.dropFirst(2) {
            if character.isNumber {
                number.append(character)
                continue
            }
            guard let amount = Int(number) else { return nil }
            switch character {
            case "H": hours = amount
            case "M": minutes = amount
            case "S": seconds = amount
            default: return nil
            }
            number = ""
        }
        guard hours > 0 || minutes > 0 || seconds > 0 else { return nil }
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
