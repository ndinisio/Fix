import Foundation

/// A single round of troubleshooting advice for one problem.
///
/// This is the shape FIX asks the model to return. Decoding is deliberately
/// forgiving: a model that omits an optional array, sends a lone string where a
/// list was expected, or invents an unfamiliar enum value should not cost the
/// user their diagnosis. Anything genuinely required — a summary and at least
/// one step — is still enforced, so an empty answer surfaces as an error rather
/// than an empty screen.
struct Diagnosis: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    /// One or two sentences naming the most likely problem.
    var summary: String
    var category: ProblemCategory
    var confidence: Confidence?
    var likelyCauses: [String]
    var steps: [TroubleshootingStep]
    var safetyWarnings: [SafetyWarning]
    /// Habits that keep this device working, and working for longer.
    var careTips: [CareTip]
    /// Search terms tuned for video search — not the raw user text.
    var videoSearchQuery: String?
    /// What to do when nothing here works: service, support, replacement.
    var escalation: String?
    /// Asked only when the model genuinely cannot proceed without an answer.
    var clarifyingQuestion: String?

    init(
        id: UUID = UUID(),
        summary: String,
        category: ProblemCategory = .other,
        confidence: Confidence? = nil,
        likelyCauses: [String] = [],
        steps: [TroubleshootingStep] = [],
        safetyWarnings: [SafetyWarning] = [],
        careTips: [CareTip] = [],
        videoSearchQuery: String? = nil,
        escalation: String? = nil,
        clarifyingQuestion: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.category = category
        self.confidence = confidence
        self.likelyCauses = likelyCauses
        self.steps = steps
        self.safetyWarnings = safetyWarnings
        self.careTips = careTips
        self.videoSearchQuery = videoSearchQuery
        self.escalation = escalation
        self.clarifyingQuestion = clarifyingQuestion
    }

    private enum CodingKeys: String, CodingKey {
        case id, summary, category, confidence, likelyCauses, steps
        case safetyWarnings, careTips, videoSearchQuery, escalation, clarifyingQuestion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let summary = container.trimmedString(forKey: .summary) ?? ""
        guard !summary.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .summary, in: container,
                debugDescription: "The diagnosis has no summary."
            )
        }
        self.id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.summary = summary
        self.category = (try? container.decodeIfPresent(ProblemCategory.self, forKey: .category)) ?? .other
        self.confidence = try? container.decodeIfPresent(Confidence.self, forKey: .confidence)
        self.likelyCauses = container.stringList(forKey: .likelyCauses)
        self.steps = (try? container.decodeIfPresent([TroubleshootingStep].self, forKey: .steps)) ?? []
        self.safetyWarnings = (try? container.decodeIfPresent([SafetyWarning].self, forKey: .safetyWarnings)) ?? []
        self.careTips = (try? container.decodeIfPresent([CareTip].self, forKey: .careTips)) ?? []
        self.videoSearchQuery = container.trimmedString(forKey: .videoSearchQuery)
        self.escalation = container.trimmedString(forKey: .escalation)
        self.clarifyingQuestion = container.trimmedString(forKey: .clarifyingQuestion)
    }

    /// A diagnosis with no steps and no question to ask is not useful, and is
    /// treated as a failed response rather than shown as an empty screen.
    var isActionable: Bool {
        !steps.isEmpty || clarifyingQuestion?.isEmpty == false
    }

    /// The most severe warning, used to decide how prominently safety is shown.
    var highestSeverity: SafetyWarning.Severity? {
        safetyWarnings.map(\.severity).max()
    }
}

// MARK: - Step

/// One thing to try, written so the user knows what to do, what they should
/// see afterwards, and what to do if it does not work.
struct TroubleshootingStep: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var detail: String
    /// What the user should observe once they have done this.
    var expectedOutcome: String?
    /// Where to go next if this step changes nothing.
    var ifItFails: String?
    var difficulty: Difficulty
    var risk: RiskLevel
    /// A caution specific to this step, such as a data-loss warning.
    var caution: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        detail: String,
        expectedOutcome: String? = nil,
        ifItFails: String? = nil,
        difficulty: Difficulty = .easy,
        risk: RiskLevel = .low,
        caution: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.expectedOutcome = expectedOutcome
        self.ifItFails = ifItFails
        self.difficulty = difficulty
        self.risk = risk
        self.caution = caution
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, expectedOutcome, ifItFails, difficulty, risk, caution
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = container.trimmedString(forKey: .title) ?? ""
        guard !title.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .title, in: container,
                debugDescription: "A step has no title."
            )
        }
        self.id = container.trimmedString(forKey: .id) ?? UUID().uuidString
        self.title = title
        self.detail = container.trimmedString(forKey: .detail) ?? ""
        self.expectedOutcome = container.trimmedString(forKey: .expectedOutcome)
        self.ifItFails = container.trimmedString(forKey: .ifItFails)
        self.difficulty = (try? container.decodeIfPresent(Difficulty.self, forKey: .difficulty)) ?? .easy
        self.risk = (try? container.decodeIfPresent(RiskLevel.self, forKey: .risk)) ?? .low
        self.caution = container.trimmedString(forKey: .caution)
    }

    /// Difficulty and risk are only worth showing when they are not routine —
    /// labelling every step "Easy · Low risk" is noise.
    var isNoteworthy: Bool {
        difficulty != .easy || risk != .low || caution != nil
    }
}

enum Difficulty: String, Codable, Hashable, Sendable, Comparable {
    case easy, moderate, advanced

    var title: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .advanced: "Advanced"
        }
    }

    private var order: Int {
        switch self {
        case .easy: 0
        case .moderate: 1
        case .advanced: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Difficulty(rawValue: raw.lowercased()) ?? .easy
    }
}

enum RiskLevel: String, Codable, Hashable, Sendable, Comparable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: "Low risk"
        case .medium: "Some risk"
        case .high: "High risk"
        }
    }

    private var order: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RiskLevel(rawValue: raw.lowercased()) ?? .low
    }
}

enum Confidence: String, Codable, Hashable, Sendable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: "Low confidence"
        case .medium: "Moderate confidence"
        case .high: "High confidence"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self),
           let value = Confidence(rawValue: raw.lowercased()) {
            self = value
            return
        }
        // Some models answer with a number despite being asked for a word.
        let number = try container.decode(Double.self)
        self = switch number {
        case ..<0.4: .low
        case ..<0.75: .medium
        default: .high
        }
    }
}

// MARK: - Safety

/// A hazard the user should know about before trying anything.
struct SafetyWarning: Codable, Hashable, Sendable, Identifiable {
    enum Severity: String, Codable, Hashable, Sendable, Comparable {
        /// Worth reading before continuing.
        case caution
        /// Stop and make the device safe first.
        case danger

        private var order: Int { self == .caution ? 0 : 1 }
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Severity(rawValue: raw.lowercased()) ?? .caution
        }
    }

    var id: String
    var text: String
    var severity: Severity

    init(id: String = UUID().uuidString, text: String, severity: Severity = .caution) {
        self.id = id
        self.text = text
        self.severity = severity
    }

    private enum CodingKeys: String, CodingKey { case id, text, severity }

    init(from decoder: any Decoder) throws {
        // Accept a bare string as well as an object: models drift between the
        // two when a list is described as "warnings".
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            let trimmed = single.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Empty warning.")
                )
            }
            self.init(text: trimmed)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = container.trimmedString(forKey: .text) ?? ""
        guard !text.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .text, in: container, debugDescription: "Empty warning."
            )
        }
        self.id = container.trimmedString(forKey: .id) ?? UUID().uuidString
        self.text = text
        self.severity = (try? container.decodeIfPresent(Severity.self, forKey: .severity)) ?? .caution
    }
}

// MARK: - Care

/// Advice that keeps a device healthy rather than fixing something broken —
/// the difference between a repair app and one that helps things last.
struct CareTip: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var detail: String
    /// How often this is worth doing, e.g. "Monthly". Free text: cadence
    /// varies far too much by device to be worth an enum.
    var cadence: String?

    init(id: String = UUID().uuidString, title: String, detail: String, cadence: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.cadence = cadence
    }

    private enum CodingKeys: String, CodingKey { case id, title, detail, cadence }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            let trimmed = single.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Empty care tip.")
                )
            }
            self.init(title: trimmed, detail: "")
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = container.trimmedString(forKey: .title) ?? ""
        guard !title.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .title, in: container, debugDescription: "Empty care tip."
            )
        }
        self.id = container.trimmedString(forKey: .id) ?? UUID().uuidString
        self.title = title
        self.detail = container.trimmedString(forKey: .detail) ?? ""
        self.cadence = container.trimmedString(forKey: .cadence)
    }
}
