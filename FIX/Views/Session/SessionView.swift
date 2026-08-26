import SwiftUI

/// The answer.
///
/// A plain grouped `List`: the content here is a sequence of related sections,
/// which is exactly what lists are for. No cards, no floating panels — the
/// hierarchy comes from section headers, type styles and order, with the most
/// urgent thing (safety) first and the least urgent (escalation) last.
struct SessionView: View {
    @State private var model: SessionViewModel

    @Environment(ServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: SessionViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        content
            .navigationTitle(model.device)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .ready = model.state {
                    ToolbarItem(placement: .topBarTrailing) { actionsMenu }
                }
            }
            .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading(let phase):
            DiagnosisProgressView(phase: phase, includesVideos: services.settings.includeVideos)
        case .failed(let error):
            ErrorStateView(error: error, retry: { await model.retry() })
        case .ready:
            results
        }
    }

    // MARK: - Results

    private var results: some View {
        List {
            if model.session.isSolved { solvedSection }
            diagnosisHeader
            stepsSection
            if model.session.canContinue { continueSection }
            if !causes.isEmpty { causesSection }
            if !model.session.careTips.isEmpty { careSection }
            videosSection
            if let escalation = diagnosis?.escalation { escalationSection(escalation) }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            if model.session.isSolved {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
        }
        .sensoryFeedback(.success, trigger: model.session.isSolved)
    }

    /// Safety first when it is serious, then the diagnosis, then the milder
    /// cautions. Grouped so the ordering rule lives in one place.
    @ViewBuilder
    private var diagnosisHeader: some View {
        if hasDangerWarning { safetySection }
        summarySection
        if !hasDangerWarning, !warnings.isEmpty { safetySection }
    }

    private var solvedSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: reduceMotion ? false : model.session.isSolved)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Problem solved")
                        .font(.headline)
                    Text("Glad we got it working.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.problem)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(diagnosis?.summary ?? "")
                    .font(.body)
                if let confidence = diagnosis?.confidence, confidence != .high {
                    // Only shown when it is worth a caveat. Announcing "high
                    // confidence" on every answer would train people to ignore it.
                    Text(confidence.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            if let question = diagnosis?.clarifyingQuestion {
                Label(question, systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label(category.title, systemImage: category.symbolName)
        }
    }

    private var safetySection: some View {
        Section {
            ForEach(warnings) { warning in
                Label {
                    Text(warning.text)
                        .font(.subheadline)
                } icon: {
                    Image(systemName: warning.severity == .danger
                          ? "exclamationmark.octagon.fill"
                          : "exclamationmark.triangle.fill")
                    .foregroundStyle(warning.severity == .danger ? .red : .orange)
                }
            }
        } header: {
            Text(hasDangerWarning ? "Stop and read this first" : "Before you start")
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                StepRow(
                    step: step,
                    index: index + 1,
                    total: steps.count,
                    outcome: model.outcome(for: step),
                    isExpanded: model.expandedStepIDs.contains(step.id),
                    onToggleExpanded: { model.toggleExpansion(for: step) },
                    onOutcome: { model.setOutcome($0, for: step) }
                )
            }
        } header: {
            Text(model.session.rounds.count > 1 ? "What to try next" : "What to try")
        } footer: {
            if !steps.isEmpty {
                Text("Work down the list. Tell FIX what happened and it will keep going.")
            }
        }
    }

    private var continueSection: some View {
        Section {
            Button {
                Task { await model.continueTroubleshooting() }
            } label: {
                HStack {
                    Text("Keep troubleshooting")
                    Spacer()
                    if model.isContinuing {
                        ProgressView()
                    }
                }
            }
            .disabled(model.isContinuing)

            if let error = model.continueError {
                Label(error.guidance, systemImage: error.symbolName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Still not fixed?")
        } footer: {
            Text("FIX will suggest what to try next, using what didn't work.")
        }
    }

    private var causesSection: some View {
        Section("Possible causes") {
            ForEach(causes, id: \.self) { cause in
                Label(cause, systemImage: "circle.fill")
                    .labelStyle(.bullet)
                    .font(.subheadline)
            }
        }
    }

    private var careSection: some View {
        Section {
            ForEach(model.session.careTips) { tip in
                CareTipRow(tip: tip)
            }
        } header: {
            Text("Keep it healthy")
        } footer: {
            Text("Habits that make this less likely to come back.")
        }
    }

    @ViewBuilder
    private var videosSection: some View {
        if !model.session.videos.isEmpty {
            Section {
                ForEach(model.session.videos) { video in
                    Link(destination: video.videoURL) {
                        VideoRow(video: video)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Videos")
            } footer: {
                Text("Search results, ordered by how relevant they look. FIX can't verify who made them.")
            }
        } else if model.session.videoSearchDidFail {
            Section {
                Label("Video search wasn't available", systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Videos")
            }
        }
    }

    private func escalationSection(_ text: String) -> some View {
        Section("If this doesn't fix it") {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Toolbar

    private var actionsMenu: some View {
        Menu {
            if !model.isSaved {
                Button("Save Device", systemImage: "plus.circle") {
                    model.saveDevice()
                }
            }
            ShareLink(item: model.shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - Convenience

    private var diagnosis: Diagnosis? { model.session.latestRound?.diagnosis }
    private var steps: [TroubleshootingStep] { diagnosis?.steps ?? [] }
    private var causes: [String] { diagnosis?.likelyCauses ?? [] }
    private var warnings: [SafetyWarning] { diagnosis?.safetyWarnings ?? [] }
    private var category: ProblemCategory { model.session.category }
    private var hasDangerWarning: Bool { diagnosis?.highestSeverity == .danger }
}

#Preview {
    NavigationStack {
        SessionView(
            model: SessionViewModel(
                session: PreviewData.session,
                services: PreviewSupport.services,
                library: PreviewSupport.library
            )
        )
    }
    .environment(PreviewSupport.services)
}
