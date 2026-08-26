import Foundation
import Testing
@testable import Fix

/// The decisions the interface makes before any pixels are involved: when the
/// primary action is available, how history is grouped, and what the cache
/// hands back.
@Suite
struct InterfaceStateTests {
    @Test @MainActor func diagnoseIsAvailableOnlyWithEnoughToGoOn() {
        let model = DiagnoseViewModel()
        #expect(!model.canDiagnose, "An empty form has nothing to diagnose")

        model.device = "PS5"
        #expect(!model.canDiagnose)

        model.problem = "dead"
        #expect(!model.canDiagnose, "A single word is not a description")

        model.problem = "No display when I turn it on"
        #expect(model.canDiagnose)

        model.device = "   "
        #expect(!model.canDiagnose, "Whitespace is not a device")
    }

    @Test @MainActor func startingASessionKeepsTheDeviceAndClearsTheProblem() {
        let model = DiagnoseViewModel()
        model.device = "MacBook Air M3"
        model.problem = "It won't charge overnight"
        model.details.onset = .today
        model.isShowingDetails = true

        model.clearProblem()

        #expect(model.device == "MacBook Air M3")
        #expect(model.problem.isEmpty)
        #expect(model.details.isEmpty)
        #expect(!model.isShowingDetails)
    }

    @Test @MainActor func theRequestCarriesTheDetailsThatWereFilledIn() {
        let model = DiagnoseViewModel()
        model.device = "  Bambu Lab A1  "
        model.problem = "  Prints stop halfway  "
        model.details.errorMessage = "  HMS_0300 "
        model.details.alreadyTried = "   "

        let request = model.request()

        #expect(request.device == "Bambu Lab A1", "Trimmed before it is sent")
        #expect(request.problem == "Prints stop halfway")
        #expect(request.details.errorMessage == "HMS_0300")
        #expect(request.details.alreadyTried == nil, "Blank fields are not sent as empty strings")
        #expect(!request.isFollowUp)
    }

    @Test func historyGroupsByDayTheWayTheSystemDoes() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        #expect(HistoryView.groupTitle(for: now, calendar: calendar, now: now) == "Today")
        #expect(
            HistoryView.groupTitle(
                for: calendar.date(byAdding: .day, value: -1, to: now)!,
                calendar: calendar, now: now
            ) == "Yesterday"
        )
        let lastMonth = calendar.date(byAdding: .month, value: -2, to: now)!
        let title = HistoryView.groupTitle(for: lastMonth, calendar: calendar, now: now)
        #expect(title != "Today" && title != "Yesterday")
    }

    @Test func theCacheForgetsWhatHasExpired() async {
        let clock = MutableClock()
        let cache = ResponseCache<String>(ttl: 60, limit: 10, now: { clock.now })

        await cache.insert("answer", forKey: "key")
        #expect(await cache.value(forKey: "key") == "answer")

        clock.advance(by: 61)
        #expect(await cache.value(forKey: "key") == nil, "An expired answer is not served")
    }

    @Test func theCacheStaysWithinItsLimit() async {
        let clock = MutableClock()
        let cache = ResponseCache<String>(ttl: 600, limit: 2, now: { clock.now })

        await cache.insert("first", forKey: "a")
        clock.advance(by: 1)
        await cache.insert("second", forKey: "b")
        clock.advance(by: 1)
        await cache.insert("third", forKey: "c")

        #expect(await cache.value(forKey: "a") == nil, "The oldest entry is evicted")
        #expect(await cache.value(forKey: "c") == "third")
    }

    @Test func clearingTheCacheEmptiesIt() async {
        let cache = ResponseCache<String>()
        await cache.insert("value", forKey: "key")
        await cache.removeAll()

        #expect(await cache.value(forKey: "key") == nil)
    }

    @Test func everyErrorHasSomethingToShow() {
        let errors: [APIError] = [
            .offline, .notConfigured, .timedOut, .rateLimited(retryAfter: nil),
            .server(statusCode: 500), .unauthorized, .invalidResponse, .cancelled,
            .underlying(description: "Something went wrong.")
        ]

        for error in errors {
            #expect(!error.title.isEmpty)
            #expect(!error.guidance.isEmpty)
            #expect(!error.symbolName.isEmpty)
        }
    }

    @Test func everyCategoryHasATitleAndASymbol() {
        for category in ProblemCategory.allCases {
            #expect(!category.title.isEmpty)
            #expect(!category.symbolName.isEmpty)
        }
    }
}

/// A clock the cache tests can move forward without waiting.
private final class MutableClock: @unchecked Sendable {
    private var offset: TimeInterval = 0
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    var now: Date { start.addingTimeInterval(offset) }

    func advance(by seconds: TimeInterval) {
        offset += seconds
    }
}
