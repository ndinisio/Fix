import Foundation
import Testing
@testable import Fix

@Suite
struct DiagnosisDecodingTests {
    private func decode(_ json: String) throws -> Diagnosis {
        try JSONDecoder().decode(Diagnosis.self, from: Data(json.utf8))
    }

    @Test func decodesACompleteResponse() throws {
        let diagnosis = try decode(TestFixtures.diagnosisJSON)

        #expect(diagnosis.category == .charging)
        #expect(diagnosis.confidence == .medium)
        #expect(diagnosis.likelyCauses.count == 2)
        #expect(diagnosis.steps.count == 1)
        #expect(diagnosis.steps[0].expectedOutcome == "A charging indicator appears.")
        #expect(diagnosis.safetyWarnings.first?.severity == .caution)
        #expect(diagnosis.careTips.first?.cadence == "Monthly")
        #expect(diagnosis.videoSearchQuery == "MacBook Air not charging troubleshooting")
        #expect(diagnosis.isActionable)
    }

    @Test func toleratesMissingOptionalFields() throws {
        let diagnosis = try decode("""
        { "summary": "Probably the cable.",
          "steps": [{ "title": "Swap the cable", "detail": "Try another one." }] }
        """)

        #expect(diagnosis.category == .other)
        #expect(diagnosis.confidence == nil)
        #expect(diagnosis.likelyCauses.isEmpty)
        #expect(diagnosis.safetyWarnings.isEmpty)
        #expect(diagnosis.steps[0].difficulty == .easy)
        #expect(diagnosis.steps[0].risk == .low)
        #expect(!diagnosis.steps[0].id.isEmpty)
    }

    @Test func ignoresUnexpectedFields() throws {
        let diagnosis = try decode("""
        { "summary": "Fine.", "somethingNew": 42, "nested": { "a": [1, 2] },
          "steps": [{ "title": "Do this", "detail": "Then that.", "extra": true }] }
        """)

        #expect(diagnosis.summary == "Fine.")
        #expect(diagnosis.steps.count == 1)
    }

    @Test func acceptsUnknownEnumValues() throws {
        let diagnosis = try decode("""
        { "summary": "Odd values.", "category": "quantum", "confidence": "certain",
          "steps": [{ "title": "Do this", "detail": "…", "difficulty": "hard", "risk": "extreme" }] }
        """)

        #expect(diagnosis.category == .other)
        #expect(diagnosis.confidence == nil)
        #expect(diagnosis.steps[0].difficulty == .easy)
        #expect(diagnosis.steps[0].risk == .low)
    }

    @Test func acceptsAStringWhereAListWasExpected() throws {
        let diagnosis = try decode("""
        { "summary": "One cause.", "likelyCauses": "A worn cable",
          "steps": [{ "title": "Check it", "detail": "Look closely." }] }
        """)

        #expect(diagnosis.likelyCauses == ["A worn cable"])
    }

    @Test func acceptsBareStringWarningsAndTips() throws {
        let diagnosis = try decode("""
        { "summary": "Careful.", "safetyWarnings": ["Unplug it first"],
          "careTips": ["Keep it dry"],
          "steps": [{ "title": "Check it", "detail": "Look closely." }] }
        """)

        #expect(diagnosis.safetyWarnings.first?.text == "Unplug it first")
        #expect(diagnosis.safetyWarnings.first?.severity == .caution)
        #expect(diagnosis.careTips.first?.title == "Keep it dry")
    }

    @Test func acceptsNumericConfidence() throws {
        #expect(try decode(#"{"summary":"x","confidence":0.9,"steps":[]}"#).confidence == .high)
        #expect(try decode(#"{"summary":"x","confidence":0.5,"steps":[]}"#).confidence == .medium)
        #expect(try decode(#"{"summary":"x","confidence":0.1,"steps":[]}"#).confidence == .low)
    }

    @Test func requiresASummary() {
        #expect(throws: (any Error).self) {
            try decode(#"{"steps":[{"title":"Do this","detail":"…"}]}"#)
        }
        #expect(throws: (any Error).self) {
            try decode(#"{"summary":"   ","steps":[]}"#)
        }
    }

    @Test func dropsStepsWithoutATitle() throws {
        // The array itself fails to decode, and the lenient container leaves it
        // empty rather than losing the whole diagnosis.
        let diagnosis = try decode("""
        { "summary": "Still useful.", "steps": [{ "detail": "No title here." }],
          "clarifyingQuestion": "Does it show any light at all?" }
        """)

        #expect(diagnosis.steps.isEmpty)
        #expect(diagnosis.isActionable, "A clarifying question is still something to act on")
    }

    @Test func emptyAnswerIsNotActionable() throws {
        #expect(try !decode(#"{"summary":"No idea.","steps":[]}"#).isActionable)
    }

    @Test func severityOrdersDangerHighest() throws {
        let diagnosis = try decode("""
        { "summary": "Danger.", "steps": [{"title":"Stop","detail":"Now."}],
          "safetyWarnings": [
            { "text": "Mild", "severity": "caution" },
            { "text": "Serious", "severity": "danger" } ] }
        """)

        #expect(diagnosis.highestSeverity == .danger)
    }

    @Test func roundTripsThroughStorage() throws {
        let original = try decode(TestFixtures.diagnosisJSON)
        let data = try JSONEncoder.fix.encode(original)
        let restored = try JSONDecoder.fix.decode(Diagnosis.self, from: data)

        #expect(restored.id == original.id, "Identity must survive being saved")
        #expect(restored == original)
    }

    @Test func decodesACarePlan() throws {
        let plan = try JSONDecoder().decode(CarePlan.self, from: Data("""
        { "summary": "Heat is the enemy.",
          "tips": [{ "title": "Dust the vents", "detail": "Use compressed air." }],
          "signsToWatch": ["Fans always running"] }
        """.utf8))

        #expect(plan.tips.count == 1)
        #expect(plan.signsToWatch == ["Fans always running"])
        #expect(plan.isActionable)
    }
}
