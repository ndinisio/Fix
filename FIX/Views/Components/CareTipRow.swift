import SwiftUI

/// One piece of care advice. Used on the results screen and on a device's page,
/// so the two read identically.
struct CareTipRow: View {
    let tip: CareTip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(tip.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer(minLength: 8)
                if let cadence = tip.cadence {
                    Text(cadence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !tip.detail.isEmpty {
                Text(tip.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
