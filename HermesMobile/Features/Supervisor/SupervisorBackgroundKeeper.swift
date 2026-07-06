import Foundation
import BackgroundTasks

/// Keeps a supervised run alive after the app is backgrounded (spec §13a).
///
/// The existing `beginBackgroundTask` window in ChatView grants ~30s; when a
/// session is being supervised we additionally submit a
/// `BGContinuedProcessingTask` (iOS 26+) so the SSE stream and the supervisor
/// keep running with a system-visible progress card. iOS may still expire the
/// task on system pressure — the stream's existing suspend/replay recovery
/// then takes over on next foreground.
@MainActor
final class SupervisorBackgroundKeeper {
    static let shared = SupervisorBackgroundKeeper()

    /// Registered wildcard; concrete submissions append a unique suffix.
    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    nonisolated static var wildcardIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "app").supervisor.*"
    }

    private(set) var isActive = false
    private var hasRegistered = false
    /// Polled by the run loop below; set by the owning view via `extend`.
    private var shouldContinue: () -> Bool = { false }
    private var completeActiveTask: (() -> Void)?

    private init() {}

    /// Must be called exactly once, at app launch, before any submission.
    func registerLaunchHandlerIfNeeded() {
        guard #available(iOS 26.0, *), !hasRegistered else { return }
        hasRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.wildcardIdentifier,
            using: .main
        ) { [weak self] task in
            guard let self, let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated {
                self.run(task)
            }
        }
    }

    /// Ask the system to continue the supervised run. Call when the scene
    /// backgrounds with supervision on and a stream active. `shouldContinue`
    /// is re-evaluated every few seconds; the task completes when it returns
    /// false (run finished and supervisor settled) or the system expires it.
    func extend(sessionTitle: String, shouldContinue: @escaping () -> Bool) {
        guard #available(iOS 26.0, *), hasRegistered, !isActive else { return }
        self.shouldContinue = shouldContinue

        let uniqueID = Self.wildcardIdentifier.replacingOccurrences(of: "*", with: UUID().uuidString)
        let request = BGContinuedProcessingTaskRequest(
            identifier: uniqueID,
            title: String(localized: "Supervising agent run"),
            subtitle: sessionTitle
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Rejected (system load, unsupported, too many tasks): the run
            // falls back to the plain 30s background window. Nothing to do.
        }
    }

    /// Ends the active task, if any — call when the scene becomes active.
    func endActiveTask() {
        completeActiveTask?()
    }

    @available(iOS 26.0, *)
    private func run(_ task: BGContinuedProcessingTask) {
        isActive = true
        // The scheduler expires tasks that look stalled, so tick determinate
        // progress in a slow loop while the stream does the real work.
        task.progress.totalUnitCount = 100

        let monitor = Task { @MainActor [weak self] in
            var ticks: Int64 = 0
            while !Task.isCancelled {
                guard let self, self.shouldContinue() else { break }
                ticks += 1
                task.progress.completedUnitCount = min(99, ticks)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }

        let finish: (Bool) -> Void = { [weak self] success in
            guard let self, self.isActive else { return }
            self.isActive = false
            self.completeActiveTask = nil
            monitor.cancel()
            task.progress.completedUnitCount = 100
            task.setTaskCompleted(success: success)
        }

        completeActiveTask = { finish(true) }
        task.expirationHandler = { Task { @MainActor in finish(false) } }

        Task { @MainActor in
            _ = await monitor.value
            finish(true)
        }
    }
}
