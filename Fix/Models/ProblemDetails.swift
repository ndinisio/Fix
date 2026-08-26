import Foundation

/// Optional context the user can add before diagnosing.
///
/// Every field is optional on purpose: the primary flow is device plus problem,
/// and these live behind a collapsed section so they never stand between
/// someone and an answer.
struct ProblemDetails: Codable, Hashable, Sendable {
    var onset: Onset?
    var alreadyTried: String?
    var errorMessage: String?

    init(onset: Onset? = nil, alreadyTried: String? = nil, errorMessage: String? = nil) {
        self.onset = onset
        self.alreadyTried = alreadyTried?.nilIfBlank
        self.errorMessage = errorMessage?.nilIfBlank
    }

    var isEmpty: Bool {
        onset == nil && alreadyTried == nil && errorMessage == nil
    }

    /// When the problem started. Coarse buckets: people rarely know more, and
    /// asking for a date would be a worse experience for no extra accuracy.
    enum Onset: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
        case justNow
        case today
        case thisWeek
        case longerAgo
        case notSure

        var id: Self { self }

        var title: String {
            switch self {
            case .justNow: "Just now"
            case .today: "Today"
            case .thisWeek: "This week"
            case .longerAgo: "Longer ago"
            case .notSure: "Not sure"
            }
        }
    }
}

extension String {
    /// `nil` when the string is empty or only whitespace, trimmed otherwise.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
