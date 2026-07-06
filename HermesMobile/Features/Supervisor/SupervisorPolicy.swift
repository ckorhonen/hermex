import Foundation

/// Pure guardrail state machine for one supervised session.
///
/// Hard rules (spec §13a): a bounded number of auto-sends between human
/// messages, a minimum cooldown between sends, and no action at all while an
/// approval or clarification prompt is pending. The clock is injected so tests
/// can drive time.
struct SupervisorPolicy: Equatable, Sendable {
    var maxSendsPerHumanTurn: Int
    var cooldown: TimeInterval

    private(set) var sendsSinceHumanMessage = 0
    private(set) var lastSendAt: Date?

    init(maxSendsPerHumanTurn: Int = 5, cooldown: TimeInterval = 20) {
        self.maxSendsPerHumanTurn = maxSendsPerHumanTurn
        self.cooldown = cooldown
    }

    /// A human-authored message resets the send budget.
    mutating func recordHumanMessage() {
        sendsSinceHumanMessage = 0
    }

    mutating func recordSupervisorSend(at date: Date) {
        sendsSinceHumanMessage += 1
        lastSendAt = date
    }

    /// nil means sending is allowed right now.
    func sendDenial(at now: Date) -> SupervisorSendDenial? {
        if sendsSinceHumanMessage >= maxSendsPerHumanTurn {
            return .budgetExhausted(limit: maxSendsPerHumanTurn)
        }
        if let lastSendAt {
            let elapsed = now.timeIntervalSince(lastSendAt)
            if elapsed < cooldown {
                return .coolingDown(remaining: cooldown - elapsed)
            }
        }
        return nil
    }
}
