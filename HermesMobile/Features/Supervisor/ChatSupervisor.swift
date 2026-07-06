import Foundation

/// Per-session babysitter (spec §13a). Owns the enable state, guardrail
/// policy, and the evaluate → send/escalate pipeline for one chat session.
/// All effects (sending, notices, notifications) are injected closures so the
/// type is fully testable without a view model or network.
@MainActor
@Observable
final class ChatSupervisor {
    enum Activity: Equatable {
        case idle
        case evaluating
        case sentReply
        case escalated
        case skipped(String)
    }

    /// What happened on the last completed evaluation, for UI/debugging.
    private(set) var activity: Activity = .idle
    private(set) var isEnabled: Bool

    private let sessionID: String
    private let model: any SupervisorModeling
    private var policy: SupervisorPolicy
    private let now: () -> Date
    private let defaults: UserDefaults
    /// Avoids re-judging the same response on stream replays/reconnects.
    private var lastEvaluatedFingerprint: String?
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?

    /// Sends the (already marker-prefixed) reply into the session. Returns
    /// true when the send actually started.
    var sendReply: ((String) async -> Bool)?
    /// Posts a local, in-transcript notice documenting supervisor activity.
    var postLocalNotice: ((String) -> Void)?
    /// Raises an owner-facing escalation (local notification + notice).
    var notifyEscalation: ((String) -> Void)?
    /// Whether a human-only prompt (approval/clarification) is pending.
    var hasPendingHumanPrompt: (() -> Bool)?

    init(
        sessionID: String,
        model: any SupervisorModeling,
        policy: SupervisorPolicy = SupervisorPolicy(),
        now: @escaping () -> Date = Date.init,
        defaults: UserDefaults = .standard
    ) {
        self.sessionID = sessionID
        self.model = model
        self.policy = policy
        self.now = now
        self.defaults = defaults
        isEnabled = SupervisorSessionStore.isSupervised(sessionID: sessionID, defaults: defaults)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        SupervisorSessionStore.setSupervised(enabled, sessionID: sessionID, defaults: defaults)
        if !enabled {
            evaluationTask?.cancel()
            activity = .idle
        }
        postLocalNotice?(
            enabled
                ? String(localized: "Supervisor on (\(model.tierName)) — it may reply for you in this chat.")
                : String(localized: "Supervisor off.")
        )
    }

    /// A human-authored send resets the auto-send budget and supersedes any
    /// in-flight evaluation.
    func humanDidSend() {
        policy.recordHumanMessage()
        evaluationTask?.cancel()
        activity = .idle
    }

    /// Entry point, called when an assistant response completes.
    func responseDidComplete(context: SupervisorContext) {
        guard isEnabled else { return }
        // Dedupe stream replays/reconnects by the assistant message's stable
        // server ID; hash the text only for messages that don't carry one.
        // Distinct IDs with identical text still evaluate (a looping agent
        // repeating itself verbatim is exactly a case worth judging).
        let fingerprint = context.assistantMessageID ?? "hash:\(context.assistantResponse.hashValue)"
        guard fingerprint != lastEvaluatedFingerprint else { return }
        lastEvaluatedFingerprint = fingerprint

        evaluationTask?.cancel()
        evaluationTask = Task { [weak self] in
            await self?.evaluate(context)
        }
    }

    /// Awaitable for tests and for the background keeper, which needs to know
    /// when the supervisor has settled before ending its task.
    func waitForEvaluation() async {
        await evaluationTask?.value
    }

    private func evaluate(_ context: SupervisorContext) async {
        if hasPendingHumanPrompt?() == true {
            activity = .skipped(String(localized: "waiting on you"))
            return
        }
        // Deliberately NOT gated on the send budget/cooldown here: those only
        // limit auto-replies (checked at send time in apply). Escalations must
        // reach the owner even after the reply budget is spent — that is
        // precisely when a risky response most needs a human.

        activity = .evaluating
        do {
            let triage = try await model.gate(context)
            guard !Task.isCancelled else { return }
            guard triage.needsAttention, triage.category != .fine else {
                activity = .idle
                return
            }

            let verdict = try await model.verdict(context)
            guard !Task.isCancelled else { return }
            try await apply(verdict)
        } catch is CancellationError {
            // Superseded by a human send or toggle-off; say nothing.
        } catch {
            activity = .skipped(String(localized: "model error"))
        }
    }

    private func apply(_ verdict: SupervisorVerdict) async throws {
        switch verdict.action {
        case .none:
            activity = .idle

        case .reply:
            guard let reply = verdict.reply, !reply.isEmpty else {
                activity = .idle
                return
            }
            // Guardrails are checked at send time (after the slow model call):
            // a pending prompt may have arrived meanwhile, and the reply
            // budget/cooldown applies only to this branch, never to escalate.
            if hasPendingHumanPrompt?() == true {
                activity = .skipped(String(localized: "waiting on you"))
                return
            }
            if let denial = policy.sendDenial(at: now()) {
                switch denial {
                case .budgetExhausted(let limit):
                    activity = .skipped(String(localized: "auto-reply limit (\(limit)) reached"))
                    postLocalNotice?(String(localized: "Supervisor paused: \(limit) auto-replies sent since your last message."))
                case .coolingDown:
                    activity = .skipped(String(localized: "cooling down"))
                }
                return
            }
            let sent = await sendReply?(SupervisorMessageMarker.mark(reply)) ?? false
            if sent {
                policy.recordSupervisorSend(at: now())
                activity = .sentReply
                postLocalNotice?(String(localized: "Supervisor (\(model.tierName)) replied: \(verdict.rationale)"))
            } else {
                activity = .skipped(String(localized: "send failed"))
            }

        case .escalate:
            activity = .escalated
            let reason = verdict.rationale.isEmpty
                ? String(localized: "The agent needs your attention.")
                : verdict.rationale
            notifyEscalation?(reason)
            postLocalNotice?(String(localized: "Supervisor escalated to you: \(reason)"))
        }
    }
}

/// Local persistence for which sessions have supervision switched on. Session
/// IDs are server-scoped, so this is a plain bounded set in UserDefaults —
/// deliberately not a server field (spec §13a).
enum SupervisorSessionStore {
    static let defaultsKey = "chatSupervisor.supervisedSessionIDs"
    private static let capacity = 200

    static func isSupervised(sessionID: String, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: defaultsKey) ?? []).contains(sessionID)
    }

    static func setSupervised(_ supervised: Bool, sessionID: String, defaults: UserDefaults = .standard) {
        var ids = defaults.stringArray(forKey: defaultsKey) ?? []
        ids.removeAll { $0 == sessionID }
        if supervised {
            ids.append(sessionID)
            if ids.count > capacity {
                ids.removeFirst(ids.count - capacity)
            }
        }
        defaults.set(ids, forKey: defaultsKey)
    }
}
