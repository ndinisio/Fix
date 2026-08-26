import Foundation

/// Orders video results so the most plausibly useful ones come first.
///
/// This ranks; it does not certify. Fix has no way to verify that a channel is
/// who it claims to be, so nothing here is ever surfaced as an "official" or
/// "authoritative" badge — the only thing that changes is the order.
enum VideoRelevanceRanker {
    /// Words that suggest a video actually walks through a fix.
    private static let repairTerms: Set<String> = [
        "fix", "fixed", "repair", "troubleshoot", "troubleshooting", "solve",
        "solution", "how", "guide", "tutorial", "won't", "wont", "not",
        "problem", "issue", "error", "diy", "replace", "clean", "calibrate"
    ]

    /// Words that suggest a video is about buying or reacting to a device
    /// rather than repairing one.
    private static let offTopicTerms: Set<String> = [
        "unboxing", "review", "vs", "versus", "giveaway", "asmr", "reaction",
        "trailer", "haul", "shorts", "prank", "ranked", "worst", "best",
        "top", "buy", "deal", "sale"
    ]

    static func rank(_ videos: [VideoResult], query: String, limit: Int) -> [VideoResult] {
        guard !videos.isEmpty else { return [] }
        let queryTokens = tokens(in: query)
        let scored = videos.enumerated().map { index, video in
            // The API's own ordering is a real relevance signal; the index
            // breaks ties instead of letting equal scores shuffle.
            (video: video, score: score(video, queryTokens: queryTokens), index: index)
        }
        return scored
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.video)
    }

    static func score(_ video: VideoResult, queryTokens: Set<String>) -> Double {
        let titleTokens = tokens(in: video.title)
        var score = 0.0

        if !queryTokens.isEmpty {
            let overlap = Double(titleTokens.intersection(queryTokens).count)
            score += 2.5 * (overlap / Double(queryTokens.count))
        }
        if !titleTokens.isDisjoint(with: repairTerms) { score += 1.0 }
        if !titleTokens.isDisjoint(with: offTopicTerms) { score -= 1.5 }

        // A channel named after the device's maker is usually more relevant.
        // It is not proof of anything, so the weight stays small.
        let channelTokens = tokens(in: video.channelName)
        if !channelTokens.isDisjoint(with: queryTokens) { score += 0.6 }

        if let publishedAt = video.publishedAt {
            let years = Date.now.timeIntervalSince(publishedAt) / (365 * 24 * 60 * 60)
            if years < 2 { score += 0.3 } else if years < 4 { score += 0.15 }
        }
        return score
    }

    /// Lowercased words of three or more characters, punctuation removed.
    /// Short words carry no signal here and only add noise to the overlap.
    static func tokens(in text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(
            text.lowercased()
                .components(separatedBy: separators)
                .filter { $0.count >= 3 }
        )
    }
}
