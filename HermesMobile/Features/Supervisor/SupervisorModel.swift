import Foundation

/// Abstracts the Apple Intelligence models behind the supervisor so the
/// pipeline is testable and the PCC tier can be compiled in or out per SDK.
protocol SupervisorModeling: Sendable {
    /// Human-readable tier name, shown in the local activity notice ("On-device", "Private Cloud Compute").
    var tierName: String { get }
    func gate(_ context: SupervisorContext) async throws -> SupervisorTriage
    func verdict(_ context: SupervisorContext) async throws -> SupervisorVerdict
}

enum SupervisorModelError: Error {
    case modelUnavailable
    case malformedOutput
}

/// Picks the best available model stack at runtime:
/// PCC (iOS 27+, compiled under `HERMEX_PCC`) → on-device (iOS 26+) → nil.
/// A nil result means the feature is hidden entirely.
enum SupervisorModelFactory {
    /// Model availability is fixed for the process lifetime; resolve once
    /// instead of re-probing FoundationModels on every chat open.
    private static let cachedDefault: (any SupervisorModeling)? = resolveDefault()

    static func makeDefault() -> (any SupervisorModeling)? {
        cachedDefault
    }

    private static func resolveDefault() -> (any SupervisorModeling)? {
        #if HERMEX_PCC
        if #available(iOS 27.0, *), let pcc = PCCSupervisorModel.ifAvailable() {
            return pcc
        }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let onDevice = OnDeviceSupervisorModel.ifAvailable() {
            return onDevice
        }
        #endif
        return nil
    }
}
