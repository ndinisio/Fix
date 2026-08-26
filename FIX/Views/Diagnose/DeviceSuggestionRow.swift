import SwiftUI

/// A tappable device suggestion under the device field.
///
/// Styled as content rather than as a link: these behave like the system's own
/// autofill suggestions, which fill the field instead of navigating anywhere.
struct DeviceSuggestionRow: View {
    let suggestion: DeviceSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: suggestion.family.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(suggestion.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .accessibilityHint("Uses this device")
    }
}
