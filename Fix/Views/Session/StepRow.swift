import SwiftUI

/// One step, in three states: untried, done, or tried without success.
///
/// The circle is a control of its own, the way Reminders works — tapping it
/// records that the step was done. Tapping the text opens the step. Both are
/// reachable by VoiceOver, and the outcome buttons are also exposed as
/// accessibility actions so they do not require expanding the row first.
struct StepRow: View {
    let step: TroubleshootingStep
    let index: Int
    let total: Int
    let outcome: StepOutcome
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onOutcome: (StepOutcome) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button {
                    onOutcome(outcome == .untried ? .completed : .untried)
                } label: {
                    Image(systemName: statusSymbol)
                        .font(.title3)
                        .foregroundStyle(statusColor)
                        .symbolEffect(.bounce, value: reduceMotion ? false : outcome == .fixedIt)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(outcome == .untried ? "Mark as done" : "Mark as not done")

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.headline)
                        .foregroundStyle(outcome == .didNotWork ? .secondary : .primary)
                    if !isExpanded {
                        Text(step.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
            .onTapGesture(perform: onToggleExpanded)

            if isExpanded {
                expandedContent
            }
        }
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(index) of \(total): \(step.title)")
        .accessibilityValue(outcomeDescription)
        .accessibilityActions {
            Button("This fixed it") { onOutcome(.fixedIt) }
            Button("Didn't work") { onOutcome(.didNotWork) }
            Button(isExpanded ? "Collapse" : "Expand", action: onToggleExpanded)
        }
    }

    // MARK: - Expanded

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.detail)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let caution = step.caution {
                Label(caution, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let expected = step.expectedOutcome {
                detailBlock(title: "You should see", text: expected)
            }
            if let ifItFails = step.ifItFails {
                detailBlock(title: "If nothing changes", text: ifItFails)
            }
            if step.isNoteworthy {
                Text("\(step.difficulty.title) · \(step.risk.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("This fixed it") { onOutcome(.fixedIt) }
                    .buttonStyle(.borderedProminent)
                Button("Didn't work") { onOutcome(.didNotWork) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
            .padding(.top, 2)
            .accessibilityHidden(true)
        }
        .padding(.leading, 34)
        .transition(.opacity)
    }

    private func detailBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status

    private var statusSymbol: String {
        switch outcome {
        case .untried: "circle"
        case .completed: "checkmark.circle.fill"
        case .didNotWork: "xmark.circle.fill"
        case .fixedIt: "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch outcome {
        case .untried: .secondary
        case .completed: .accentColor
        case .didNotWork: .secondary
        case .fixedIt: .green
        }
    }

    private var outcomeDescription: String {
        switch outcome {
        case .untried: "Not tried"
        case .completed: "Done"
        case .didNotWork: "Didn't work"
        case .fixedIt: "This fixed it"
        }
    }
}

#Preview {
    List {
        StepRow(
            step: PreviewData.diagnosis.steps[0],
            index: 1,
            total: 3,
            outcome: .untried,
            isExpanded: true,
            onToggleExpanded: {},
            onOutcome: { _ in }
        )
        StepRow(
            step: PreviewData.diagnosis.steps[1],
            index: 2,
            total: 3,
            outcome: .didNotWork,
            isExpanded: false,
            onToggleExpanded: {},
            onOutcome: { _ in }
        )
    }
}
