import SwiftUI

/// A small round bullet, sized to sit on the baseline of the text beside it.
///
/// A `Label` with a custom style rather than a literal "•" in the string: the
/// bullet stays out of the accessibility label, and the text wraps with a hanging
/// indent instead of running back under the marker.
struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

extension LabelStyle where Self == BulletLabelStyle {
    static var bullet: BulletLabelStyle { BulletLabelStyle() }
}
