import Foundation
import Testing
@testable import FIX

@Suite(.serialized)
struct VideoSearchTests {
    private func service(
        transport: ServiceTransport = .direct(apiKey: "key")
    ) -> YouTubeVideoSearchService {
        YouTubeVideoSearchService(transport: transport, client: StubURLProtocol.makeClient())
    }

    private let searchJSON = """
    { "items": [
      { "id": { "videoId": "aaa" },
        "snippet": { "title": "How to fix a MacBook that won&#39;t charge",
                     "channelTitle": "Repair &amp; Restore",
                     "publishedAt": "2024-03-01T10:00:00Z",
                     "thumbnails": { "medium": { "url": "https://example.com/a.jpg" } } } },
      { "id": { "videoId": "bbb" },
        "snippet": { "title": "MacBook Air unboxing and review",
                     "channelTitle": "Gadget Channel",
                     "thumbnails": { "medium": { "url": "https://example.com/b.jpg" } } } }
    ] }
    """

    @Test func mapsAndRanksResults() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: searchJSON)

        let videos = try await service().searchVideos(query: "MacBook charge fix", limit: 2)

        #expect(videos.count == 2)
        #expect(videos[0].id == "aaa", "A repair video outranks an unboxing")
        #expect(videos[0].title == "How to fix a MacBook that won't charge", "Entities are decoded")
        #expect(videos[0].channelName == "Repair & Restore")
        #expect(videos[0].videoURL.absoluteString == "https://www.youtube.com/watch?v=aaa")
        #expect(videos[0].thumbnailURL?.absoluteString == "https://example.com/a.jpg")
    }

    @Test func emptyResultsAreNotAnError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: #"{"items":[]}"#)

        #expect(try await service().searchVideos(query: "nothing", limit: 5).isEmpty)
    }

    @Test func apiFailurePropagates() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 403)

        await #expect(throws: APIError.unauthorized) {
            _ = try await service().searchVideos(query: "anything", limit: 5)
        }
    }

    @Test func dropsResultsThatWouldHaveToBeInvented() throws {
        let response = try JSONDecoder().decode(
            YouTubeVideoSearchService.SearchResponse.self,
            from: Data(#"{"items":[{"id":{},"snippet":{"title":"T","channelTitle":"C"}}]}"#.utf8)
        )
        let item = try #require(response.items.first)

        #expect(YouTubeVideoSearchService.videoResult(from: item) == nil)
    }

    @Test func missingThumbnailStillYieldsAResult() throws {
        let response = try JSONDecoder().decode(
            YouTubeVideoSearchService.SearchResponse.self,
            from: Data(#"{"items":[{"id":{"videoId":"z"},"snippet":{"title":"T","channelTitle":"C"}}]}"#.utf8)
        )
        let video = try #require(YouTubeVideoSearchService.videoResult(from: response.items[0]))

        #expect(video.thumbnailURL == nil)
        #expect(video.id == "z")
    }

    @Test func emptyQueryMakesNoRequest() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: searchJSON)

        #expect(try await service().searchVideos(query: "   ", limit: 5).isEmpty)
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    @Test func relayRequestsCarryNoKey() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: #"{"videos":[]}"#)
        let relay = try #require(URL(string: "https://relay.example.com/v1"))

        _ = try await service(transport: .relay(baseURL: relay)).searchVideos(query: "test", limit: 3)

        let url = try #require(StubURLProtocol.recordedRequests.first?.url?.absoluteString)
        #expect(url.contains("relay.example.com/v1/videos"))
        #expect(!url.contains("key="))
    }

    @Test func rankingPrefersRepairOverPromotion() {
        let query = "bambu lab a1 print stops halfway"
        let repair = VideoResult(
            id: "1", title: "Bambu Lab A1 print stops halfway — how to fix",
            channelName: "Print Repair", videoURL: URL(string: "https://y.com/1")!
        )
        let promo = VideoResult(
            id: "2", title: "Bambu Lab A1 review — best printer of the year?",
            channelName: "Gadgets", videoURL: URL(string: "https://y.com/2")!
        )

        let ranked = VideoRelevanceRanker.rank([promo, repair], query: query, limit: 2)
        #expect(ranked.first?.id == "1")
    }

    @Test func rankingKeepsAPIOrderForTies() {
        let a = VideoResult(id: "a", title: "Zzz", channelName: "X", videoURL: URL(string: "https://y.com/a")!)
        let b = VideoResult(id: "b", title: "Zzz", channelName: "X", videoURL: URL(string: "https://y.com/b")!)

        #expect(VideoRelevanceRanker.rank([a, b], query: "unrelated", limit: 2).map(\.id) == ["a", "b"])
    }

    @Test func rankingRespectsTheLimit() {
        let videos = (0..<10).map {
            VideoResult(id: "\($0)", title: "Fix it \($0)", channelName: "C",
                        videoURL: URL(string: "https://y.com/\($0)")!)
        }
        #expect(VideoRelevanceRanker.rank(videos, query: "fix", limit: 3).count == 3)
    }

    @Test func formatsDurations() {
        #expect(ISO8601Duration.formatted("PT8M41S") == "8:41")
        #expect(ISO8601Duration.formatted("PT1H2M3S") == "1:02:03")
        #expect(ISO8601Duration.formatted("PT45S") == "0:45")
        #expect(ISO8601Duration.formatted("P1D") == nil)
        #expect(ISO8601Duration.formatted("nonsense") == nil)
    }

    @Test func decodesHTMLEntities() {
        #expect("Fix &amp; repair".htmlDecoded == "Fix & repair")
        #expect("won&#39;t charge".htmlDecoded == "won't charge")
        #expect("plain title".htmlDecoded == "plain title")
    }
}
