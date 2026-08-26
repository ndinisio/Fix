import Foundation

/// Everything the AI layer needs to produce one round of advice.
///
/// Nothing here is collected implicitly. The device and problem are typed by
/// the user, the details are optional, and the history is the list of steps
/// they already reported on. No identifiers, no device telemetry, no location.
struct DiagnosisRequest: Hashable, Sendable {
    var device: String
    var problem: String
    var details: ProblemDetails
    /// Steps already tried, for a follow-up round. Empty on a first diagnosis.
    var history: [AttemptedStep]

    init(
        device: String,
        problem: String,
        details: ProblemDetails = ProblemDetails(),
        history: [AttemptedStep] = []
    ) {
        self.device = device.trimmingCharacters(in: .whitespacesAndNewlines)
        self.problem = problem.trimmingCharacters(in: .whitespacesAndNewlines)
        // Re-run the details through their own initialiser: whatever route the
        // values arrived by, what gets sent is trimmed, and a field left blank
        // is absent rather than an empty string.
        self.details = ProblemDetails(
            onset: details.onset,
            alreadyTried: details.alreadyTried,
            errorMessage: details.errorMessage
        )
        self.history = history
    }

    var isFollowUp: Bool { !history.isEmpty }

    /// Stable key for the response cache. Follow-up rounds include the number
    /// of attempts so a second round is never served from the first round's
    /// cache entry.
    var cacheKey: String {
        var parts = [
            device.lowercased(),
            problem.lowercased(),
            details.onset?.rawValue ?? "",
            details.alreadyTried?.lowercased() ?? "",
            details.errorMessage?.lowercased() ?? ""
        ]
        parts.append(contentsOf: history.map { "\($0.title.lowercased())|\($0.outcome.rawValue)" })
        return parts.joined(separator: "\u{1F}")
    }
}
