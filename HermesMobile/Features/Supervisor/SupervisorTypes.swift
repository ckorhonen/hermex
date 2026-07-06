import Foundation

/// What the supervisor decided to do about a completed assistant response.
enum SupervisorAction: String, Equatable, Sendable {
    /// Response is fine; no follow-up needed.
    case none
    /// Send the drafted reply into the session on the owner's behalf.
    case reply
    /// Something needs the owner; never auto-send, surface a notification.
    case escalate
}

/// Tier-1 gate result: is this response worth a tier-2 look, and why.
struct SupervisorTriage: Equatable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        /// Agent said it would do something and stopped without doing it.
        case loopNotClosed = "loop_not_closed"
        /// Agent proposed a next step and is waiting for a go-ahead.
        case awaitingConfirmation = "awaiting_confirmation"
        /// Agent did partial work or hedged instead of finishing ("lazy").
        case incompleteWork = "incomplete_work"
        /// Agent asked something only the owner can answer.
        case needsOwner = "needs_owner"
        /// Nothing to do.
        case fine = "fine"
    }

    var needsAttention: Bool
    var category: Category
}

/// Tier-2 verdict: the concrete action plus the drafted reply text.
struct SupervisorVerdict: Equatable, Sendable {
    var action: SupervisorAction
    /// Reply text, without the transcript marker; required when action == .reply.
    var reply: String?
    /// One-line reason, kept for the local activity notice.
    var rationale: String
}

/// The slice of a session the supervisor is allowed to look at.
struct SupervisorContext: Equatable, Sendable {
    var sessionTitle: String?
    /// Most recent human-authored message (supervisor nudges excluded so the
    /// model never mistakes its own prior reply for an owner instruction).
    var lastUserMessage: String?
    /// The completed assistant response being triaged.
    var assistantResponse: String
    /// Server message ID of that response, used to dedupe stream replays.
    var assistantMessageID: String?
    /// Short older-history digest lines, oldest first (already truncated by
    /// caller); supervisor-sent turns appear with a "supervisor:" role label.
    var recentHistory: [String]

    init(
        sessionTitle: String? = nil,
        lastUserMessage: String? = nil,
        assistantResponse: String,
        assistantMessageID: String? = nil,
        recentHistory: [String] = []
    ) {
        self.sessionTitle = sessionTitle
        self.lastUserMessage = lastUserMessage
        self.assistantResponse = assistantResponse
        self.assistantMessageID = assistantMessageID
        self.recentHistory = recentHistory
    }
}

/// Why the supervisor is not allowed to send right now.
enum SupervisorSendDenial: Equatable, Sendable {
    case budgetExhausted(limit: Int)
    case coolingDown(remaining: TimeInterval)
}

/// Marker used to document supervisor-authored messages durably in the
/// server-side chat history. Any client sees the plain-text prefix; Hermex
/// renders it as a badge (see `SupervisorMessageMarker`).
enum SupervisorMessageMarker {
    static let prefix = "[Supervisor]"

    static func mark(_ reply: String) -> String {
        "\(prefix) \(reply)"
    }

    /// Splits a transcript message into (isSupervisor, displayText).
    static func unmark(_ text: String) -> (isSupervisor: Bool, body: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return (false, text) }
        let body = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return (true, body)
    }
}
