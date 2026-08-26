import SwiftUI

/// The wait after tapping Diagnose.
///
/// Each row is a stage that is really happening: the first appears while the
/// model is being asked, the second while videos are being searched for. If
/// video search is switched off, that row is not shown — the app does not
/// perform progress it is not making.
struct DiagnosisProgressView: View {
    let phase: DiagnosisPhase
    let includesVideos: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stages: [DiagnosisPhase] {
        includesVideos ? [.analyzing, .findingVideos] : [.analyzing]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(stages, id: \.self) { stage in
                stageRow(stage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(phase.title)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func stageRow(_ stage: DiagnosisPhase) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: stage)
                .frame(width: 22, height: 22)
            Text(stage.title)
                .font(.body)
                .foregroundStyle(state(of: stage) == .pending ? .secondary : .primary)
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .default, value: phase)
    }

    @ViewBuilder
    private func statusIcon(for stage: DiagnosisPhase) -> some View {
        switch state(of: stage) {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .imageScale(.large)
        case .active:
            ProgressView()
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .imageScale(.large)
        }
    }

    private enum StageState {
        case done, active, pending
    }

    private func state(of stage: DiagnosisPhase) -> StageState {
        // `.finished` is not in `stages`, so it lands past the end and every
        // row reads as done.
        let current = stages.firstIndex(of: phase) ?? stages.count
        guard let index = stages.firstIndex(of: stage) else { return .pending }
        if index < current { return .done }
        return index == current ? .active : .pending
    }
}

#Preview("Analyzing") {
    DiagnosisProgressView(phase: .analyzing, includesVideos: true)
}

#Preview("Finding videos") {
    DiagnosisProgressView(phase: .findingVideos, includesVideos: true)
}
