import Foundation
import Testing
@testable import Fix

/// The state machine behind the results screen: what the user has tried, what
/// that means, and when Fix should offer to keep going.
@Suite
struct SessionStateTests {
    private func session() -> TroubleshootingSession {
        var session = TroubleshootingSession(device: "PS5", problem: "No display")
        session.append(TestFixtures.diagnosis())
        return session
    }

    @Test func startsWithEverythingUntried() {
        let session = session()

        #expect(session.rounds.count == 1)
        #expect(session.resolution == .inProgress)
        #expect(session.allSteps.allSatisfy { session.outcome(for: $0) == .untried })
        #expect(!session.canContinue)
        #expect(session.fixedStep == nil)
    }

    @Test func recordsWhatHappenedToEachStep() {
        var session = session()
        let steps = session.allSteps

        session.setOutcome(.didNotWork, forStepID: steps[0].id)

        #expect(session.outcome(for: steps[0]) == .didNotWork)
        #expect(session.outcome(for: steps[1]) == .untried)
    }

    @Test func offersToContinueOnlyWhenEverythingHasFailed() {
        var session = session()
        let steps = session.allSteps

        session.setOutcome(.didNotWork, forStepID: steps[0].id)
        #expect(!session.canContinue, "One failure is not the end of the list")

        session.setOutcome(.didNotWork, forStepID: steps[1].id)
        #expect(session.canContinue)
    }

    @Test func aFixResolvesTheSession() {
        var session = session()
        let steps = session.allSteps

        session.setOutcome(.fixedIt, forStepID: steps[1].id)

        #expect(session.isSolved)
        #expect(session.fixedStep?.id == steps[1].id)
        #expect(!session.canContinue, "A solved session is not asking for more steps")
    }

    @Test func takingBackAFixReopensTheSession() {
        var session = session()
        let steps = session.allSteps

        session.setOutcome(.fixedIt, forStepID: steps[0].id)
        session.setOutcome(.untried, forStepID: steps[0].id)

        #expect(!session.isSolved)
        #expect(session.resolution == .inProgress)
    }

    @Test func aFollowUpRoundAppendsRatherThanReplaces() {
        var session = session()
        session.setOutcome(.didNotWork, forStepID: session.allSteps[0].id)

        session.append(TestFixtures.diagnosis(
            summary: "Then it is probably the port.",
            steps: [TroubleshootingStep(id: "step-3", title: "Inspect the port", detail: "Look inside.")]
        ))

        #expect(session.rounds.count == 2)
        #expect(session.allSteps.count == 3, "Earlier rounds stay on screen")
        #expect(session.outcome(for: session.allSteps[0]) == .didNotWork, "And keep their outcomes")
        #expect(session.latestRound?.diagnosis.steps.first?.id == "step-3")
        #expect(!session.canContinue, "The new round has not been tried yet")
    }

    @Test func attemptHistoryCarriesOnlyWhatWasTried() {
        var session = session()
        session.setOutcome(.didNotWork, forStepID: session.allSteps[0].id)

        let history = session.attemptHistory

        #expect(history.count == 1)
        #expect(history[0].title == "Try another outlet")
        #expect(history[0].outcome == .didNotWork)
    }

    @Test func careTipsAreCollectedWithoutRepeating() {
        var session = session()
        let tip = CareTip(title: "Keep the vents clear", detail: "Dust them.")
        session.rounds[0].diagnosis.careTips = [tip]
        session.append(TestFixtures.diagnosis(summary: "Second round."))
        session.rounds[1].diagnosis.careTips = [
            CareTip(title: "keep the vents clear", detail: "Dust them properly."),
            CareTip(title: "Leave space behind it", detail: "Airflow matters.")
        ]

        let tips = session.careTips

        #expect(tips.count == 2)
        #expect(tips.contains { $0.detail == "Dust them properly." }, "The newest wording wins")
    }

    @Test func unknownStepIDsAreIgnored() {
        var session = session()
        session.setOutcome(.fixedIt, forStepID: "not-a-real-step")

        #expect(!session.isSolved)
    }

    @Test func survivesBeingSavedAndReopened() throws {
        var original = session()
        original.setOutcome(.didNotWork, forStepID: original.allSteps[0].id)
        original.videos = [TestFixtures.video]

        let stored = StoredSession(session: original)
        let restored = try #require(stored.session)

        #expect(restored.id == original.id)
        #expect(restored.outcome(for: restored.allSteps[0]) == .didNotWork)
        #expect(restored.videos.count == 1)
        #expect(stored.device == "PS5")
        #expect(stored.isSolved == false)
        #expect(stored.category == .charging)
    }

    @Test func storedColumnsFollowTheSession() {
        var session = session()
        let stored = StoredSession(session: session)

        session.setOutcome(.fixedIt, forStepID: session.allSteps[0].id)
        stored.apply(session)

        #expect(stored.isSolved)
        #expect(stored.updatedAt == session.updatedAt)
    }
}
