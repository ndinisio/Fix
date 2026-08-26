import Foundation
import Observation

/// Owns one troubleshooting session from first request to resolution.
///
/// Also the single place that decides when a session is written to history:
/// once a diagnosis exists, and again whenever the user records progress.
@MainActor
@Observable
final class SessionViewModel: Identifiable, Hashable {
    enum LoadState: Equatable {
        case loading(DiagnosisPhase)
        case ready
        case failed(APIError)
    }

    let id = UUID()
    private(set) var session: TroubleshootingSession
    private(set) var state: LoadState
    /// A follow-up round is in flight.
    private(set) var isContinuing = false
    /// A failed follow-up is shown in place, so the answer already on screen is
    /// never thrown away because the next round failed.
    private(set) var continueError: APIError?
    /// Steps the user has opened. The first unfinished step starts open so the
    /// screen arrives with something to read rather than a list of headings.
    var expandedStepIDs: Set<String> = []

    private let request: DiagnosisRequest
    private let services: ServiceContainer
    private let library: Library
    private var hasStarted = false

    /// Starts a new session for a request.
    init(request: DiagnosisRequest, services: ServiceContainer, library: Library) {
        self.request = request
        self.services = services
        self.library = library
        self.session = TroubleshootingSession(
            device: request.device,
            problem: request.problem,
            details: request.details
        )
        self.state = .loading(.analyzing)
    }

    /// Reopens a session from history. No network involved.
    init(session: TroubleshootingSession, services: ServiceContainer, library: Library) {
        self.request = DiagnosisRequest(
            device: session.device, problem: session.problem, details: session.details
        )
        self.services = services
        self.library = library
        self.session = session
        self.state = .ready
        self.hasStarted = true
        self.expandedStepIDs = Self.initialExpansion(for: session)
    }

    var device: String { session.device }
    var problem: String { session.problem }

    var isSaved: Bool { library.device(named: session.device) != nil }

    // MARK: - Loading

    /// Runs the first diagnosis. Safe to call again — it does nothing once a
    /// diagnosis exists or one is already in flight.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await load()
    }

    func retry() async {
        state = .loading(.analyzing)
        await load()
    }

    private func load() async {
        do {
            let outcome = try await services.troubleshooting.diagnose(
                request,
                includeVideos: services.settings.includeVideos,
                onPhase: { [weak self] phase in
                    await MainActor.run {
                        guard let self, case .loading = self.state else { return }
                        self.state = .loading(phase)
                    }
                }
            )
            session.append(outcome.diagnosis)
            session.videos = outcome.videos
            session.videoSearchDidFail = outcome.videoSearchDidFail
            expandedStepIDs = Self.initialExpansion(for: session)
            state = .ready
            library.markDeviceUsed(session.device)
            library.save(session)
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.underlying(description: "The connection failed. Try again."))
        }
    }

    // MARK: - Progress

    func outcome(for step: TroubleshootingStep) -> StepOutcome {
        session.outcome(for: step)
    }

    func setOutcome(_ outcome: StepOutcome, for step: TroubleshootingStep) {
        session.setOutcome(outcome, forStepID: step.id)
        if outcome == .didNotWork {
            // Move the user on rather than leaving a failed step open.
            expandedStepIDs.remove(step.id)
            if let next = nextUntriedStep() {
                expandedStepIDs.insert(next.id)
            }
        }
        library.save(session)
    }

    func toggleExpansion(for step: TroubleshootingStep) {
        if expandedStepIDs.contains(step.id) {
            expandedStepIDs.remove(step.id)
        } else {
            expandedStepIDs.insert(step.id)
        }
    }

    func nextUntriedStep() -> TroubleshootingStep? {
        session.latestRound?.diagnosis.steps.first { session.outcome(for: $0) == .untried }
    }

    /// Asks for another round, telling the model what has already failed.
    func continueTroubleshooting() async {
        guard !isContinuing else { return }
        isContinuing = true
        continueError = nil
        defer { isContinuing = false }

        let followUp = DiagnosisRequest(
            device: session.device,
            problem: session.problem,
            details: session.details,
            history: session.attemptHistory
        )
        do {
            // Videos already on screen came from the same problem; a second
            // search would cost a request to say the same thing.
            let outcome = try await services.troubleshooting.diagnose(followUp, includeVideos: false)
            session.append(outcome.diagnosis)
            if let next = session.latestRound?.diagnosis.steps.first {
                expandedStepIDs.insert(next.id)
            }
            library.save(session)
        } catch let error as APIError {
            continueError = error
        } catch {
            continueError = .underlying(description: "The connection failed. Try again.")
        }
    }

    func saveDevice() {
        library.addDevice(named: session.device)
    }

    /// Plain text for the share sheet — the diagnosis and the steps, in the
    /// order they appear on screen, so a shared copy is still readable.
    var shareText: String {
        var lines = ["\(session.device) — \(session.problem)"]
        if let diagnosis = session.latestRound?.diagnosis {
            lines.append("")
            lines.append(diagnosis.summary)
            if !diagnosis.steps.isEmpty {
                lines.append("")
                lines.append("What to try:")
                for (index, step) in diagnosis.steps.enumerated() {
                    lines.append("\(index + 1). \(step.title) — \(step.detail)")
                }
            }
            for warning in diagnosis.safetyWarnings {
                lines.append("")
                lines.append("Safety: \(warning.text)")
            }
        }
        lines.append("")
        lines.append("Shared from Fix")
        return lines.joined(separator: "\n")
    }

    // Identity-based conformance so the session can be used as navigation
    // state: `navigationDestination(item:)` needs a Hashable value.
    nonisolated static func == (lhs: SessionViewModel, rhs: SessionViewModel) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    /// Opens the first step that has not been tried yet.
    private static func initialExpansion(for session: TroubleshootingSession) -> Set<String> {
        guard let step = session.latestRound?.diagnosis.steps
            .first(where: { session.outcome(for: $0) == .untried })
        else { return [] }
        return [step.id]
    }
}
