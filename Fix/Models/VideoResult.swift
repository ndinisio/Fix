import Foundation

/// A repair or troubleshooting video returned by video search.
///
/// Every field comes from the search API. Fix never invents a title, channel,
/// thumbnail, or URL — a video that cannot be built from real data is dropped
/// rather than shown with placeholder text.
struct VideoResult: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let channelName: String
    /// Optional: the API occasionally omits thumbnails, and a missing image is
    /// not a reason to hide an otherwise relevant result.
    let thumbnailURL: URL?
    let videoURL: URL
    /// Human-readable length, e.g. "8:41". Absent when the enrichment request
    /// that provides it was skipped or failed.
    let duration: String?
    let publishedAt: Date?

    init(
        id: String,
        title: String,
        channelName: String,
        thumbnailURL: URL? = nil,
        videoURL: URL,
        duration: String? = nil,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.channelName = channelName
        self.thumbnailURL = thumbnailURL
        self.videoURL = videoURL
        self.duration = duration
        self.publishedAt = publishedAt
    }
}
