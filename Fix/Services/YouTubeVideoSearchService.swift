import Foundation

/// ``VideoSearchService`` backed by the YouTube Data API.
///
/// As with the AI service, a relay keeps the credential off the device; a
/// direct key is for development only. Results are ranked by
/// ``VideoRelevanceRanker`` before they are returned, and anything that cannot
/// be turned into a real, playable result is dropped rather than shown with
/// invented data.
final class YouTubeVideoSearchService: VideoSearchService {
    private let transport: ServiceTransport
    private let client: APIClient

    private static let directBaseURL = URL(string: "https://www.googleapis.com/youtube/v3")!

    init(transport: ServiceTransport, client: APIClient = APIClient()) {
        self.transport = transport
        self.client = client
    }

    func searchVideos(query: String, limit: Int) async throws -> [VideoResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        // Ask for a few more than needed so ranking has something to choose
        // between, without paying for a large page.
        let fetchCount = min(max(limit * 2, limit + 2), 12)

        switch transport {
        case .relay(let baseURL):
            return try await relayResults(baseURL: baseURL, query: query, limit: fetchCount, cap: limit)
        case .direct(let apiKey):
            return try await directResults(apiKey: apiKey, query: query, limit: fetchCount, cap: limit)
        }
    }

    /// Checks that the key works. Uses `videos.list`, which costs a single unit
    /// of quota, rather than a search, which costs a hundred.
    func validateCredentials() async throws {
        switch transport {
        case .relay(let baseURL):
            guard var components = URLComponents(
                url: baseURL.appending(path: "videos"), resolvingAgainstBaseURL: false
            ) else { throw APIError.invalidResponse }
            components.queryItems = [
                URLQueryItem(name: "q", value: "test"),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let url = components.url else { throw APIError.invalidResponse }
            _ = try await client.data(for: URLRequest(url: url))
        case .direct(let apiKey):
            guard var components = URLComponents(
                url: Self.directBaseURL.appending(path: "videos"), resolvingAgainstBaseURL: false
            ) else { throw APIError.invalidResponse }
            components.queryItems = [
                URLQueryItem(name: "part", value: "id"),
                URLQueryItem(name: "chart", value: "mostPopular"),
                URLQueryItem(name: "maxResults", value: "1"),
                URLQueryItem(name: "key", value: apiKey)
            ]
            guard let url = components.url else { throw APIError.invalidResponse }
            _ = try await client.data(for: URLRequest(url: url))
        }
    }

    // MARK: - Relay

    private func relayResults(
        baseURL: URL,
        query: String,
        limit: Int,
        cap: Int
    ) async throws -> [VideoResult] {
        guard var components = URLComponents(url: baseURL.appending(path: "videos"), resolvingAgainstBaseURL: false)
        else { throw APIError.invalidResponse }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { throw APIError.invalidResponse }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response: RelayResponse = try await client.send(
            URLRequest(url: url), decoding: RelayResponse.self, decoder: decoder
        )
        return VideoRelevanceRanker.rank(response.videos, query: query, limit: cap)
    }

    // MARK: - Direct

    private func directResults(
        apiKey: String,
        query: String,
        limit: Int,
        cap: Int
    ) async throws -> [VideoResult] {
        guard var components = URLComponents(
            url: Self.directBaseURL.appending(path: "search"), resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidResponse }
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: String(limit)),
            URLQueryItem(name: "safeSearch", value: "moderate"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components.url else { throw APIError.invalidResponse }

        let response: SearchResponse = try await client.send(
            URLRequest(url: url), decoding: SearchResponse.self
        )
        let results = response.items.compactMap(Self.videoResult(from:))
        let ranked = VideoRelevanceRanker.rank(results, query: query, limit: cap)

        // One extra request adds durations for the results actually shown. It
        // costs a single unit of quota against search's hundred, and a failure
        // here only means the rows have no duration.
        guard !ranked.isEmpty,
              let durations = try? await durations(for: ranked.map(\.id), apiKey: apiKey)
        else { return ranked }

        return ranked.map { video in
            guard let duration = durations[video.id] else { return video }
            return VideoResult(
                id: video.id,
                title: video.title,
                channelName: video.channelName,
                thumbnailURL: video.thumbnailURL,
                videoURL: video.videoURL,
                duration: duration,
                publishedAt: video.publishedAt
            )
        }
    }

    private func durations(for ids: [String], apiKey: String) async throws -> [String: String] {
        guard var components = URLComponents(
            url: Self.directBaseURL.appending(path: "videos"), resolvingAgainstBaseURL: false
        ) else { return [:] }
        components.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components.url else { return [:] }

        let response: DetailsResponse = try await client.send(
            URLRequest(url: url), decoding: DetailsResponse.self
        )
        return response.items.reduce(into: [:]) { result, item in
            if let formatted = ISO8601Duration.formatted(item.contentDetails.duration) {
                result[item.id] = formatted
            }
        }
    }

    /// Builds a result, or `nil` when the item lacks something Fix would have
    /// to invent — an identifier, a title, or a usable URL.
    static func videoResult(from item: SearchResponse.Item) -> VideoResult? {
        guard let videoID = item.id.videoId?.trimmingCharacters(in: .whitespaces), !videoID.isEmpty,
              let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")
        else { return nil }
        let title = item.snippet.title.htmlDecoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return VideoResult(
            id: videoID,
            title: title,
            channelName: item.snippet.channelTitle.htmlDecoded,
            thumbnailURL: item.snippet.thumbnails?.best,
            videoURL: url,
            duration: nil,
            publishedAt: item.snippet.publishedAt
        )
    }

    // MARK: - Wire types

    private struct RelayResponse: Decodable {
        let videos: [VideoResult]
    }

    struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct Identifier: Decodable {
                let videoId: String?
            }

            struct Snippet: Decodable {
                struct Thumbnails: Decodable {
                    struct Thumbnail: Decodable {
                        let url: String
                    }
                    let medium: Thumbnail?
                    let high: Thumbnail?
                    let `default`: Thumbnail?

                    /// The largest thumbnail that is still list-row sized.
                    var best: URL? {
                        for candidate in [medium, high, self.default] {
                            if let string = candidate?.url, let url = URL(string: string) {
                                return url
                            }
                        }
                        return nil
                    }
                }

                let title: String
                let channelTitle: String
                let thumbnails: Thumbnails?
                let publishedAt: Date?

                private enum CodingKeys: String, CodingKey {
                    case title, channelTitle, thumbnails, publishedAt
                }

                init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    self.title = container.trimmedString(forKey: .title) ?? ""
                    self.channelTitle = container.trimmedString(forKey: .channelTitle) ?? ""
                    self.thumbnails = try? container.decodeIfPresent(Thumbnails.self, forKey: .thumbnails)
                    self.publishedAt = container.trimmedString(forKey: .publishedAt)
                        .flatMap { ISO8601DateFormatter().date(from: $0) }
                }
            }

            let id: Identifier
            let snippet: Snippet
        }

        let items: [Item]
    }

    private struct DetailsResponse: Decodable {
        struct Item: Decodable {
            struct ContentDetails: Decodable {
                let duration: String
            }
            let id: String
            let contentDetails: ContentDetails
        }

        let items: [Item]
    }
}
