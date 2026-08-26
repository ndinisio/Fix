import Foundation

/// Video discovery, kept behind a protocol for the same reason as ``AIService``:
/// the source should be replaceable without touching the app.
protocol VideoSearchService: Sendable {
    /// Results for a query the model wrote, ordered most useful first.
    /// Returning an empty array is a valid answer; throwing means the search
    /// itself failed.
    func searchVideos(query: String, limit: Int) async throws -> [VideoResult]
}

extension VideoSearchService {
    func searchVideos(query: String) async throws -> [VideoResult] {
        try await searchVideos(query: query, limit: 5)
    }
}
