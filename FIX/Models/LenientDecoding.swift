import Foundation

/// Small decoding conveniences shared by the model types.
///
/// Language models are consistent but not perfectly consistent: a field
/// described as a list of strings occasionally arrives as one string, optional
/// fields arrive as `null` or as `""`, and whitespace is unpredictable. These
/// helpers absorb that variation in one place so the models themselves stay
/// readable, and so the app never discards an otherwise good answer over
/// formatting.
extension KeyedDecodingContainer {
    /// A trimmed string, or `nil` when the key is absent, null, or blank.
    func trimmedString(forKey key: Key) -> String? {
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A list of non-empty trimmed strings. Accepts a single string in place of
    /// a one-element list, and never throws.
    func stringList(forKey key: Key) -> [String] {
        func cleaned(_ values: [String]) -> [String] {
            values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let array = try? decodeIfPresent([String].self, forKey: key) {
            return cleaned(array)
        }
        if let single = trimmedString(forKey: key) {
            return [single]
        }
        return []
    }
}
