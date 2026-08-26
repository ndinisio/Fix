import Foundation

/// What the user did with one suggested step.
enum StepOutcome: String, Codable, Hashable, Sendable {
    /// Not attempted yet.
    case untried
    /// Done, but the user has not said whether it helped.
    case completed
    /// Tried, and the problem is unchanged.
    case didNotWork
    /// This is the step that solved it.
    case fixedIt

    var isAttempted: Bool { self != .untried }
}

/// One diagnosis and the user's progress through its steps.
///
/// Troubleshooting is iterative, so a session holds an ordered list of rounds
/// rather than a single answer. When the user works through everything without
/// success, Fix asks the model for another round with the failures included —
/// it never starts the diagnosis over from scratch.
struct TroubleshootingRound: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var diagnosis: Diagnosis
    var outcomes: [String: StepOutcome]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        diagnosis: Diagnosis,
        outcomes: [String: StepOutcome] = [:],
        createdAt: Date = .now
    ) {
        self.id = id
        self.diagnosis = diagnosis
        self.outcomes = outcomes
        self.createdAt = createdAt
    }

    func outcome(for step: TroubleshootingStep) -> StepOutcome {
        outcomes[step.id] ?? .untried
    }

    /// True once every step has been tried and none of them worked.
    var isExhausted: Bool {
        !diagnosis.steps.isEmpty && diagnosis.steps.allSatisfy { outcome(for: $0) == .didNotWork }
    }
}

/// A complete troubleshooting session: the problem, every round of advice, and
/// how it ended. This is the unit that is saved to history.
struct TroubleshootingSession: Codable, Hashable, Sendable, Identifiable {
    enum Resolution: String, Codable, Hashable, Sendable {
        case inProgress
        case solved
        /// Closed without a fix — the user stopped, or escalated to a repair.
        case unresolved
    }

    var id: UUID
    var device: String
    var problem: String
    var details: ProblemDetails
    var rounds: [TroubleshootingRound]
    var videos: [VideoResult]
    /// Recorded so the UI can say video search was unavailable instead of
    /// implying that no relevant videos exist.
    var videoSearchDidFail: Bool
    var resolution: Resolution
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        device: String,
        problem: String,
        details: ProblemDetails = ProblemDetails(),
        rounds: [TroubleshootingRound] = [],
        videos: [VideoResult] = [],
        videoSearchDidFail: Bool = false,
        resolution: Resolution = .inProgress,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.device = device
        self.problem = problem
        self.details = details
        self.rounds = rounds
        self.videos = videos
        self.videoSearchDidFail = videoSearchDidFail
        self.resolution = resolution
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Derived state

    var latestRound: TroubleshootingRound? { rounds.last }

    var isSolved: Bool { resolution == .solved }

    /// Every step across every round, oldest first.
    var allSteps: [TroubleshootingStep] { rounds.flatMap(\.diagnosis.steps) }

    func outcome(for step: TroubleshootingStep) -> StepOutcome {
        for round in rounds.reversed() where round.outcomes[step.id] != nil {
            return round.outcomes[step.id] ?? .untried
        }
        return .untried
    }

    /// The step the user reported as the fix, if there is one.
    var fixedStep: TroubleshootingStep? {
        allSteps.first { outcome(for: $0) == .fixedIt }
    }

    /// Care advice from every round, de-duplicated by title. Later rounds win,
    /// which keeps the most recent phrasing without repeating a tip.
    var careTips: [CareTip] {
        var seen = Set<String>()
        var tips: [CareTip] = []
        for tip in rounds.flatMap(\.diagnosis.careTips).reversed() {
            let key = tip.title.lowercased()
            if seen.insert(key).inserted { tips.append(tip) }
        }
        return tips.reversed()
    }

    /// True when the newest round has been fully tried without success, which
    /// is the moment to offer another round of troubleshooting.
    var canContinue: Bool {
        resolution == .inProgress && (latestRound?.isExhausted ?? false)
    }

    var category: ProblemCategory { latestRound?.diagnosis.category ?? .other }

    // MARK: - Mutation

    mutating func setOutcome(_ outcome: StepOutcome, forStepID stepID: String) {
        guard let index = rounds.lastIndex(where: { $0.diagnosis.steps.contains { $0.id == stepID } })
        else { return }
        rounds[index].outcomes[stepID] = outcome
        if outcome == .fixedIt {
            resolution = .solved
        } else if resolution == .solved, fixedStep == nil {
            // The user took the fix back.
            resolution = .inProgress
        }
        updatedAt = .now
    }

    mutating func append(_ diagnosis: Diagnosis) {
        rounds.append(TroubleshootingRound(diagnosis: diagnosis))
        updatedAt = .now
    }

    /// Everything the user has tried, for the follow-up request. Only titles
    /// and outcomes are sent — enough for the model to avoid repeating itself,
    /// and no more than that.
    var attemptHistory: [AttemptedStep] {
        allSteps.compactMap { step in
            let result = outcome(for: step)
            guard result.isAttempted else { return nil }
            return AttemptedStep(title: step.title, outcome: result)
        }
    }
}

/// A step the user has already tried, as sent back to the model.
struct AttemptedStep: Codable, Hashable, Sendable {
    var title: String
    var outcome: StepOutcome
}
