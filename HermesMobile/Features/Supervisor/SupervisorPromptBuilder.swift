import Foundation

/// Builds the tier-1 and tier-2 prompts from a `SupervisorContext`, keeping
/// them inside the smallest model's context budget. Budgets are characters,
/// not tokens: the on-device model has a 4K-token window, and ~4 chars/token
/// keeps us safely under it without a tokenizer dependency.
enum SupervisorPromptBuilder {
    static let onDeviceBudget = 6_000
    static let pccBudget = 60_000

    static let gateInstructions = """
    You triage completed responses from a coding/ops agent on behalf of its owner. \
    Decide if the response needs any follow-up. Categories: \
    loop_not_closed (agent said it would do something and stopped without doing it), \
    awaiting_confirmation (agent proposed a next step and is waiting for a go-ahead), \
    incomplete_work (agent did partial work, hedged, or skipped verification it promised), \
    needs_owner (agent asked something only the owner can answer), \
    fine (nothing to do). Be conservative: when in doubt, answer fine.
    """

    static let verdictInstructions = """
    You supervise a coding/ops agent on behalf of its owner, who is away. \
    You have three choices for the completed response you are shown: \
    reply — send a short, direct follow-up message to the agent (confirm a proposed \
    step the owner would clearly approve, or push the agent to finish and verify work \
    it left incomplete); \
    escalate — the owner personally needs to see this (irreversible or risky actions, \
    real decisions, credentials, spending, anything destructive); \
    none — no follow-up needed. \
    Rules: never approve anything destructive or irreversible; never invent facts, \
    preferences, or credentials; keep replies under 3 sentences, imperative, and \
    specific about what the agent should do next. If the agent asked a question whose \
    answer you do not know, escalate.
    """

    static func gatePrompt(for context: SupervisorContext) -> String {
        prompt(for: context, budget: onDeviceBudget)
    }

    static func verdictPrompt(for context: SupervisorContext, budget: Int) -> String {
        prompt(for: context, budget: budget)
    }

    private static func prompt(for context: SupervisorContext, budget: Int) -> String {
        var sections: [String] = []
        if let title = context.sessionTitle, !title.isEmpty {
            sections.append("Session: \(title)")
        }
        if let last = context.lastUserMessage, !last.isEmpty {
            sections.append("Owner's last message:\n\(last)")
        }
        if !context.recentHistory.isEmpty {
            sections.append("Recent history:\n" + context.recentHistory.joined(separator: "\n"))
        }
        sections.append("Agent's completed response:\n\(context.assistantResponse)")

        // The response being judged is the highest-value text: when over budget,
        // drop history first, then truncate the middle of long fields.
        var text = sections.joined(separator: "\n\n")
        if text.count > budget {
            sections.removeAll { $0.hasPrefix("Recent history:") }
            text = sections.joined(separator: "\n\n")
        }
        if text.count > budget {
            text = truncatingMiddle(text, to: budget)
        }
        return text
    }

    static func truncatingMiddle(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 40 else { return text }
        let keep = (limit - 20) / 2
        let head = text.prefix(keep)
        let tail = text.suffix(keep)
        return "\(head)\n[…truncated…]\n\(tail)"
    }
}
