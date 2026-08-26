#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Fixtures for Xcode previews only.
///
/// Compiled out of release builds. The sample service exists so previews can
/// render a finished screen without a network or an API key — it never stands
/// in for a provider in the shipping app, which reports ``APIError/notConfigured``
/// instead of inventing an answer.
@MainActor
enum PreviewSupport {
    static let container: ModelContainer = {
        let schema = Schema([SavedDevice.self, StoredSession.self])
        // Previews are the one place a failure here is not worth handling: it
        // would mean the schema is broken, which the app's own tests catch.
        return try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }()

    static var library: Library { Library(context: container.mainContext) }

    static var services: ServiceContainer {
        ServiceContainer(
            configuration: AppConfiguration(ai: nil, video: nil, groqModel: "preview"),
            settings: AppSettings(defaults: UserDefaults(suiteName: "preview") ?? .standard),
            networkMonitor: NetworkMonitor(),
            troubleshooting: SampleTroubleshootingService()
        )
    }

}

/// Sample data, deliberately outside the main-actor helper so services can
/// read it from any context.
enum PreviewData {
    static let diagnosis = Diagnosis(
        summary: "The charger or the cable is the most likely cause, not the Mac itself.",
        category: .charging,
        confidence: .medium,
        likelyCauses: [
            "Faulty or underpowered charger",
            "Damaged USB-C cable",
            "Debris in the charging port"
        ],
        steps: [
            TroubleshootingStep(
                id: "step-1",
                title: "Try a different outlet",
                detail: "Plug the charger into a wall socket you know works, not an extension lead.",
                expectedOutcome: "A charging indicator appears within a minute.",
                ifItFails: "The outlet isn't the problem — move on to the cable."
            ),
            TroubleshootingStep(
                id: "step-2",
                title: "Swap the cable",
                detail: "Use another USB-C cable rated for charging, ideally the one that came with the Mac.",
                expectedOutcome: "The battery symbol shows charging.",
                ifItFails: "The cable is probably fine.",
                difficulty: .easy,
                risk: .low
            ),
            TroubleshootingStep(
                id: "step-3",
                title: "Reset the SMC",
                detail: "Hold the power button for ten seconds, release, then press it again.",
                expectedOutcome: "The Mac starts up normally.",
                ifItFails: "This points to a hardware fault rather than software.",
                difficulty: .moderate,
                risk: .medium,
                caution: "Any unsaved work will be lost."
            )
        ],
        safetyWarnings: [
            SafetyWarning(
                text: "If the charger is hot, discoloured or smells burnt, stop using it.",
                severity: .caution
            )
        ],
        careTips: [
            CareTip(
                title: "Keep the port clear",
                detail: "Check for lint with a torch before assuming the cable has failed.",
                cadence: "Every few months"
            )
        ],
        videoSearchQuery: "MacBook Air not charging troubleshooting",
        escalation: "If none of this works, an Apple Store or authorised service provider can test the port."
    )

    static var session: TroubleshootingSession {
        var session = TroubleshootingSession(
            device: "MacBook Air M3",
            problem: "It stopped charging overnight and the light doesn't come on."
        )
        session.append(diagnosis)
        return session
    }
}

/// Returns fixed sample data so previews render instantly and offline.
struct SampleTroubleshootingService: TroubleshootingServicing {
    func diagnose(
        _ request: DiagnosisRequest,
        includeVideos: Bool,
        onPhase: @Sendable (DiagnosisPhase) async -> Void
    ) async throws -> DiagnosisOutcome {
        await onPhase(.analyzing)
        return DiagnosisOutcome(
            diagnosis: PreviewData.diagnosis,
            videos: [],
            videoSearchDidFail: false
        )
    }

    func carePlan(for device: String) async throws -> CarePlan {
        CarePlan(
            device: device,
            summary: "Heat and deep discharges shorten this device's life more than anything else.",
            tips: [
                CareTip(title: "Avoid full discharges", detail: "Top up before it drops below 20%."),
                CareTip(title: "Keep vents clear", detail: "Dust the fans.", cadence: "Twice a year")
            ],
            signsToWatch: ["Fans running constantly", "Battery health below 80%"]
        )
    }
}
#endif
