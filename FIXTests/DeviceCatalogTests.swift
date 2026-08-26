import Foundation
import Testing
@testable import FIX

@Suite
struct DeviceCatalogTests {
    @Test func prefixMatchesComeFirst() {
        let names = DeviceCatalog.suggestions(matching: "mac").map(\.name)

        #expect(names.contains("MacBook Air"))
        #expect(names.first?.lowercased().hasPrefix("mac") == true)
    }

    @Test func recentDevicesOutrankTheCatalog() {
        let names = DeviceCatalog.suggestions(
            matching: "ip", recents: ["iPhone 15 Pro"]
        ).map(\.name)

        #expect(names.first == "iPhone 15 Pro")
    }

    @Test func doesNotSuggestWhatIsAlreadyTyped() {
        let names = DeviceCatalog.suggestions(matching: "iPad").map(\.name)

        #expect(!names.contains("iPad"), "Suggesting the exact text back is noise")
    }

    @Test func anEmptyQueryStillOffersSomething() {
        #expect(!DeviceCatalog.suggestions(matching: "").isEmpty)
        #expect(DeviceCatalog.suggestions(matching: "", limit: 3).count == 3)
    }

    @Test func doesNotRepeatARecentThatIsAlsoInTheCatalog() {
        let names = DeviceCatalog.suggestions(matching: "", recents: ["iPhone"]).map(\.name)

        #expect(names.filter { $0 == "iPhone" }.count == 1)
    }

    @Test func picksASymbolForFreeText() {
        #expect(DeviceCatalog.family(for: "iPhone 15 Pro") == .phone)
        #expect(DeviceCatalog.family(for: "my PS5") == .console)
        #expect(DeviceCatalog.family(for: "Bambu Lab A1") == .printer3D)
        #expect(DeviceCatalog.family(for: "Brother laser printer") == .printer)
        #expect(DeviceCatalog.family(for: "Apple TV 4K") == .tv, "Longer keywords win over shorter ones")
        #expect(DeviceCatalog.family(for: "something unheard of") == .other)
    }

    @Test func nothingIsUnmatchable() {
        // Every catalog entry should resolve to the family it was filed under,
        // so a saved device and a suggested one look the same.
        for suggestion in DeviceCatalog.common where suggestion.family != .other {
            #expect(
                DeviceCatalog.family(for: suggestion.name) != .other,
                "\(suggestion.name) has no keyword"
            )
        }
    }
}

@Suite
struct AppConfigurationTests {
    @Test func environmentWinsOverTheBuildSetting() {
        let configuration = AppConfiguration.resolve(
            environment: ["FIX_GROQ_API_KEY": "from-scheme"],
            infoDictionary: ["GroqAPIKey": "from-xcconfig"]
        )

        #expect(configuration.ai == .direct(apiKey: "from-scheme"))
    }

    @Test func aRelayAlwaysWinsOverAnOnDeviceKey() {
        let configuration = AppConfiguration.resolve(
            environment: [:],
            infoDictionary: [
                "RelayBaseURL": "relay.example.com/v1",
                "GroqAPIKey": "should-not-be-used",
                "YouTubeAPIKey": "also-not-used"
            ]
        )

        #expect(configuration.ai == .relay(baseURL: URL(string: "https://relay.example.com/v1")!))
        #expect(configuration.video?.isRelay == true)
    }

    @Test func missingConfigurationIsAState() {
        let configuration = AppConfiguration.resolve(environment: [:], infoDictionary: nil)

        #expect(configuration.ai == nil)
        #expect(!configuration.isAIConfigured)
        #expect(!configuration.isVideoSearchConfigured)
        #expect(configuration.groqModel == AppConfiguration.groqDefaultModel)
    }

    @Test func blankValuesCountAsMissing() {
        let configuration = AppConfiguration.resolve(
            environment: ["FIX_GROQ_API_KEY": "   "],
            infoDictionary: ["YouTubeAPIKey": ""]
        )

        #expect(configuration.ai == nil)
        #expect(configuration.video == nil)
    }

    @Test func acceptsAHostOrAFullURL() {
        #expect(
            AppConfiguration.normalizedURL("relay.example.com")?.absoluteString
                == "https://relay.example.com"
        )
        #expect(
            AppConfiguration.normalizedURL("https://relay.example.com/v1")?.absoluteString
                == "https://relay.example.com/v1"
        )
        #expect(AppConfiguration.normalizedURL("  ") == nil)
        #expect(AppConfiguration.normalizedURL("///") == nil)
    }
}
