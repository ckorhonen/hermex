import XCTest
@testable import HermesMobile

/// Deterministic model double: scripted gate/verdict results plus call counts.
private final class MockSupervisorModel: SupervisorModeling, @unchecked Sendable {
    let tierName = "Mock"
    var gateResult = SupervisorTriage(needsAttention: true, category: .awaitingConfirmation)
    var verdictResult = SupervisorVerdict(action: .reply, reply: "Proceed.", rationale: "agent asked to continue")
    var gateError: Error?
    private(set) var gateCalls = 0
    private(set) var verdictCalls = 0

    func gate(_ context: SupervisorContext) async throws -> SupervisorTriage {
        gateCalls += 1
        if let gateError { throw gateError }
        return gateResult
    }

    func verdict(_ context: SupervisorContext) async throws -> SupervisorVerdict {
        verdictCalls += 1
        return verdictResult
    }
}

@MainActor
final class ChatSupervisorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "chat-supervisor-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeContext(response: String = "Shall I proceed with the migration?") -> SupervisorContext {
        SupervisorContext(
            sessionTitle: "Test session",
            lastUserMessage: "Run the migration plan",
            assistantResponse: response,
            recentHistory: []
        )
    }

    private func makeSupervisor(
        model: MockSupervisorModel,
        policy: SupervisorPolicy = SupervisorPolicy(),
        now: @escaping () -> Date = Date.init
    ) -> ChatSupervisor {
        let supervisor = ChatSupervisor(
            sessionID: "session-\(UUID().uuidString)",
            model: model,
            policy: policy,
            now: now,
            defaults: defaults
        )
        supervisor.setEnabled(true)
        return supervisor
    }

    // MARK: - Pipeline

    func testReplyVerdictSendsMarkedMessageAndPostsNotice() async {
        let model = MockSupervisorModel()
        let supervisor = makeSupervisor(model: model)
        var sentTexts: [String] = []
        var notices: [String] = []
        supervisor.sendReply = { text in
            sentTexts.append(text)
            return true
        }
        supervisor.postLocalNotice = { notices.append($0) }

        supervisor.responseDidComplete(context: makeContext())
        await supervisor.waitForEvaluation()

        XCTAssertEqual(sentTexts, ["[Supervisor] Proceed."])
        XCTAssertEqual(supervisor.activity, .sentReply)
        XCTAssertTrue(notices.contains { $0.contains("Supervisor (Mock) replied") })
    }

    func testFineGateResultSendsNothing() async {
        let model = MockSupervisorModel()
        model.gateResult = SupervisorTriage(needsAttention: false, category: .fine)
        let supervisor = makeSupervisor(model: model)
        var didSend = false
        supervisor.sendReply = { _ in
            didSend = true
            return true
        }

        supervisor.responseDidComplete(context: makeContext())
        await supervisor.waitForEvaluation()

        XCTAssertFalse(didSend)
        XCTAssertEqual(model.verdictCalls, 0)
        XCTAssertEqual(supervisor.activity, .idle)
    }

    func testEscalationNotifiesWithoutSending() async {
        let model = MockSupervisorModel()
        model.verdictResult = SupervisorVerdict(action: .escalate, reply: nil, rationale: "needs credentials")
        let supervisor = makeSupervisor(model: model)
        var didSend = false
        var escalations: [String] = []
        supervisor.sendReply = { _ in
            didSend = true
            return true
        }
        supervisor.notifyEscalation = { escalations.append($0) }

        supervisor.responseDidComplete(context: makeContext())
        await supervisor.waitForEvaluation()

        XCTAssertFalse(didSend)
        XCTAssertEqual(escalations, ["needs credentials"])
        XCTAssertEqual(supervisor.activity, .escalated)
    }

    func testPendingApprovalBlocksEvaluation() async {
        let model = MockSupervisorModel()
        let supervisor = makeSupervisor(model: model)
        supervisor.hasPendingHumanPrompt = { true }
        var didSend = false
        supervisor.sendReply = { _ in
            didSend = true
            return true
        }

        supervisor.responseDidComplete(context: makeContext())
        await supervisor.waitForEvaluation()

        XCTAssertFalse(didSend)
        XCTAssertEqual(model.gateCalls, 0)
    }

    func testDisabledSupervisorDoesNothing() async {
        let model = MockSupervisorModel()
        let supervisor = makeSupervisor(model: model)
        supervisor.setEnabled(false)

        supervisor.responseDidComplete(context: makeContext())
        await supervisor.waitForEvaluation()

        XCTAssertEqual(model.gateCalls, 0)
    }

    func testSameResponseIsEvaluatedOnce() async {
        let model = MockSupervisorModel()
        model.gateResult = SupervisorTriage(needsAttention: false, category: .fine)
        let supervisor = makeSupervisor(model: model)

        let context = makeContext()
        supervisor.responseDidComplete(context: context)
        await supervisor.waitForEvaluation()
        supervisor.responseDidComplete(context: context)
        await supervisor.waitForEvaluation()

        XCTAssertEqual(model.gateCalls, 1)
    }

    func testBudgetExhaustionStopsAutoSendsUntilHumanMessage() async {
        let model = MockSupervisorModel()
        var clock = Date(timeIntervalSince1970: 1_000)
        let supervisor = makeSupervisor(
            model: model,
            policy: SupervisorPolicy(maxSendsPerHumanTurn: 1, cooldown: 0),
            now: { clock }
        )
        var sentTexts: [String] = []
        supervisor.sendReply = { text in
            sentTexts.append(text)
            return true
        }

        supervisor.responseDidComplete(context: makeContext(response: "First response"))
        await supervisor.waitForEvaluation()
        clock = clock.addingTimeInterval(60)
        supervisor.responseDidComplete(context: makeContext(response: "Second response"))
        await supervisor.waitForEvaluation()

        XCTAssertEqual(sentTexts.count, 1)

        supervisor.humanDidSend()
        clock = clock.addingTimeInterval(60)
        supervisor.responseDidComplete(context: makeContext(response: "Third response"))
        await supervisor.waitForEvaluation()

        XCTAssertEqual(sentTexts.count, 2)
    }

    func testCooldownBlocksBackToBackSends() async {
        let model = MockSupervisorModel()
        let fixedNow = Date(timeIntervalSince1970: 2_000)
        let supervisor = makeSupervisor(
            model: model,
            policy: SupervisorPolicy(maxSendsPerHumanTurn: 5, cooldown: 20),
            now: { fixedNow }
        )
        var sentTexts: [String] = []
        supervisor.sendReply = { text in
            sentTexts.append(text)
            return true
        }

        supervisor.responseDidComplete(context: makeContext(response: "First response"))
        await supervisor.waitForEvaluation()
        supervisor.responseDidComplete(context: makeContext(response: "Second response"))
        await supervisor.waitForEvaluation()

        XCTAssertEqual(sentTexts.count, 1)
    }

    func testModelErrorLeavesSkippedActivity() async {
        let model = MockSupervisorModel()
        model.gateError = SupervisorModelError.modelUnavailable
        let supervisor = makeSupervisor(model: model)

        supervisor.responseDidComplete(context: makeContext())
        await supervisor.waitForEvaluation()

        XCTAssertEqual(supervisor.activity, .skipped("model error"))
    }

    // MARK: - Persistence

    func testEnableStatePersistsPerSession() {
        let model = MockSupervisorModel()
        let sessionID = "persisted-session"
        let first = ChatSupervisor(sessionID: sessionID, model: model, defaults: defaults)
        XCTAssertFalse(first.isEnabled)
        first.setEnabled(true)

        let second = ChatSupervisor(sessionID: sessionID, model: model, defaults: defaults)
        XCTAssertTrue(second.isEnabled)

        let other = ChatSupervisor(sessionID: "different-session", model: model, defaults: defaults)
        XCTAssertFalse(other.isEnabled)
    }
}

final class SupervisorPolicyTests: XCTestCase {
    func testDenialTransitions() {
        var policy = SupervisorPolicy(maxSendsPerHumanTurn: 2, cooldown: 20)
        let t0 = Date(timeIntervalSince1970: 0)

        XCTAssertNil(policy.sendDenial(at: t0))

        policy.recordSupervisorSend(at: t0)
        XCTAssertEqual(policy.sendDenial(at: t0.addingTimeInterval(5)), .coolingDown(remaining: 15))
        XCTAssertNil(policy.sendDenial(at: t0.addingTimeInterval(25)))

        policy.recordSupervisorSend(at: t0.addingTimeInterval(25))
        XCTAssertEqual(policy.sendDenial(at: t0.addingTimeInterval(100)), .budgetExhausted(limit: 2))

        policy.recordHumanMessage()
        XCTAssertNil(policy.sendDenial(at: t0.addingTimeInterval(100)))
    }
}

final class SupervisorMessageMarkerTests: XCTestCase {
    func testMarkAndUnmarkRoundTrip() {
        let marked = SupervisorMessageMarker.mark("Finish the tests.")
        XCTAssertEqual(marked, "[Supervisor] Finish the tests.")

        let unmarked = SupervisorMessageMarker.unmark(marked)
        XCTAssertTrue(unmarked.isSupervisor)
        XCTAssertEqual(unmarked.body, "Finish the tests.")
    }

    func testUnmarkedTextPassesThrough() {
        let result = SupervisorMessageMarker.unmark("Just a normal message")
        XCTAssertFalse(result.isSupervisor)
        XCTAssertEqual(result.body, "Just a normal message")
    }

    func testMarkerMentionedMidTextIsNotAttribution() {
        let result = SupervisorMessageMarker.unmark("The [Supervisor] tag is used for attribution")
        XCTAssertFalse(result.isSupervisor)
    }
}

final class SupervisorPromptBuilderTests: XCTestCase {
    func testHistoryIsDroppedBeforeResponseIsTruncated() {
        let context = SupervisorContext(
            sessionTitle: "Big session",
            lastUserMessage: "short",
            assistantResponse: String(repeating: "r", count: 4_000),
            recentHistory: (0..<50).map { _ in String(repeating: "h", count: 100) }
        )

        let prompt = SupervisorPromptBuilder.gatePrompt(for: context)

        XCTAssertLessThanOrEqual(prompt.count, SupervisorPromptBuilder.onDeviceBudget)
        XCTAssertFalse(prompt.contains("Recent history:"))
        XCTAssertTrue(prompt.contains("Agent's completed response:"))
    }

    func testMiddleTruncationKeepsHeadAndTail() {
        let text = "HEAD" + String(repeating: "x", count: 10_000) + "TAIL"
        let truncated = SupervisorPromptBuilder.truncatingMiddle(text, to: 500)

        XCTAssertLessThanOrEqual(truncated.count, 520)
        XCTAssertTrue(truncated.hasPrefix("HEAD"))
        XCTAssertTrue(truncated.hasSuffix("TAIL"))
        XCTAssertTrue(truncated.contains("[…truncated…]"))
    }
}
