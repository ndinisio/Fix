import SwiftUI

extension Binding where Value == String? {
    /// Bridges an optional string to a text field, which needs a non-optional
    /// binding. Blank input reads back as `nil`, so an emptied field is stored
    /// as "not provided" rather than as an empty string.
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.nilIfBlank }
        )
    }
}
