import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device model (FoundationModels, iOS 26+). Serves as the tier-1
/// gate always, and as the tier-2 verdict model when PCC is not compiled in or
/// not available on this device.
@available(iOS 26.0, *)
final class OnDeviceSupervisorModel: SupervisorModeling {
    let tierName = "On-device"

    static func ifAvailable() -> OnDeviceSupervisorModel? {
        SystemLanguageModel.default.isAvailable ? OnDeviceSupervisorModel() : nil
    }

    func gate(_ context: SupervisorContext) async throws -> SupervisorTriage {
        let session = LanguageModelSession(instructions: SupervisorPromptBuilder.gateInstructions)
        let response = try await session.respond(
            to: SupervisorPromptBuilder.gatePrompt(for: context),
            generating: GateOutput.self
        )
        return response.content.asTriage
    }

    func verdict(_ context: SupervisorContext) async throws -> SupervisorVerdict {
        let session = LanguageModelSession(instructions: SupervisorPromptBuilder.verdictInstructions)
        let response = try await session.respond(
            to: SupervisorPromptBuilder.verdictPrompt(
                for: context,
                budget: SupervisorPromptBuilder.onDeviceBudget
            ),
            generating: VerdictOutput.self
        )
        return try response.content.asVerdict()
    }
}

/// Guided-generation DTOs shared by the on-device and PCC adapters.
@available(iOS 26.0, *)
@Generable
struct GateOutput {
    @Guide(description: "Whether this response needs any follow-up at all.")
    var needsAttention: Bool

    @Guide(
        description: "Why: loop_not_closed, awaiting_confirmation, incomplete_work, needs_owner, or fine.",
        .anyOf(SupervisorTriage.Category.allCases.map(\.rawValue))
    )
    var category: String

    var asTriage: SupervisorTriage {
        SupervisorTriage(
            needsAttention: needsAttention,
            category: SupervisorTriage.Category(rawValue: category) ?? .fine
        )
    }
}

@available(iOS 26.0, *)
@Generable
struct VerdictOutput {
    @Guide(
        description: "reply to send the follow-up, escalate to alert the owner, none to do nothing.",
        .anyOf(["reply", "escalate", "none"])
    )
    var action: String

    @Guide(description: "The follow-up message to send to the agent. Empty unless action is reply.")
    var reply: String

    @Guide(description: "One short sentence explaining the decision.")
    var rationale: String

    func asVerdict() throws -> SupervisorVerdict {
        guard let action = SupervisorAction(rawValue: action) else {
            throw SupervisorModelError.malformedOutput
        }
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if action == .reply, trimmed.isEmpty {
            throw SupervisorModelError.malformedOutput
        }
        return SupervisorVerdict(
            action: action,
            reply: action == .reply ? trimmed : nil,
            rationale: rationale
        )
    }
}
#endif
