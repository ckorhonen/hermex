import Foundation
import Observation

@MainActor
@Observable
final class ArchivedSessionsViewModel {
    private(set) var sessions: [SessionSummary] = []
    private(set) var isLoading = false
    private(set) var unarchivingSessionIDs: Set<String> = []
    private(set) var errorMessage: String?
    private(set) var actionErrorMessage: String?

    private let client: APIClient

    var isUnarchiving: Bool {
        !unarchivingSessionIDs.isEmpty
    }

    init(server: URL, client: APIClient? = nil) {
        self.client = client ?? APIClient.shared(for: server)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        actionErrorMessage = nil

        do {
            let response = try await client.sessions()
            sessions = (response.sessions ?? []).filter { $0.archived == true }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func unarchive(_ session: SessionSummary) async -> Bool {
        guard let sessionId = Self.nonEmpty(session.sessionId) else {
            actionErrorMessage = String(localized: "The server did not provide a session ID.")
            return false
        }
        guard !unarchivingSessionIDs.contains(sessionId) else {
            return false
        }

        guard let removedSession = removeSession(withID: sessionId) else {
            return false
        }

        unarchivingSessionIDs.insert(sessionId)
        actionErrorMessage = nil
        defer {
            unarchivingSessionIDs.remove(sessionId)
        }

        do {
            _ = try await client.archiveSession(id: sessionId, archived: false)
            return true
        } catch {
            restore(removedSession)
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    func isUnarchiving(_ session: SessionSummary) -> Bool {
        guard let sessionId = session.sessionId else { return false }
        return unarchivingSessionIDs.contains(sessionId)
    }

    func clearActionError() {
        actionErrorMessage = nil
    }

    private func removeSession(withID sessionId: String) -> (index: Int, session: SessionSummary)? {
        guard let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) else {
            return nil
        }

        let removed = sessions.remove(at: index)
        return (index, removed)
    }

    private func restore(_ removedSession: (index: Int, session: SessionSummary)) {
        guard removedSession.session.sessionId != nil,
              !sessions.contains(where: { $0.sessionId == removedSession.session.sessionId })
        else {
            return
        }

        sessions.insert(removedSession.session, at: min(removedSession.index, sessions.count))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
