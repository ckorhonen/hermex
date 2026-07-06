import Foundation

// Compiled only when the project is built against an iOS 27+ SDK (see the
// SDK-conditional HERMEX_PCC flags in Config/Shared.xcconfig). This file
// cannot be compile-checked on Xcode 26 toolchains; it follows the WWDC26
// "Build with the new Apple Foundation Model on Private Cloud Compute" API
// (session 319) and must be re-verified the first time it is built with
// Xcode 27.
#if HERMEX_PCC && canImport(FoundationModels)
import FoundationModels

/// Tier-2 verdicts on Apple's Private Cloud Compute server model (32K
/// context); the cheap tier-1 gate stays on-device to preserve the user's
/// per-day PCC quota.
@available(iOS 27.0, *)
final class PCCSupervisorModel: SupervisorModeling {
    let tierName = "Private Cloud Compute"

    private let onDevice: OnDeviceSupervisorModel

    private init(onDevice: OnDeviceSupervisorModel) {
        self.onDevice = onDevice
    }

    static func ifAvailable() -> PCCSupervisorModel? {
        guard PrivateCloudComputeLanguageModel().isAvailable,
              let onDevice = OnDeviceSupervisorModel.ifAvailable()
        else { return nil }
        return PCCSupervisorModel(onDevice: onDevice)
    }

    func gate(_ context: SupervisorContext) async throws -> SupervisorTriage {
        try await onDevice.gate(context)
    }

    func verdict(_ context: SupervisorContext) async throws -> SupervisorVerdict {
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable, !model.quotaUsage.isLimitReached else {
            // Out of PCC quota (per-user daily limit) → judge on-device instead.
            return try await onDevice.verdict(context)
        }
        let session = LanguageModelSession(
            model: model,
            instructions: SupervisorPromptBuilder.verdictInstructions
        )
        let response = try await session.respond(
            to: SupervisorPromptBuilder.verdictPrompt(
                for: context,
                budget: SupervisorPromptBuilder.pccBudget
            ),
            generating: VerdictOutput.self
        )
        return try response.content.asVerdict()
    }
}
#endif
