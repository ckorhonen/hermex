import Foundation

struct SessionDuplicateResult {
    let session: SessionSummary?
    let errorMessage: String?
}

struct SessionMutator {
    let client: APIClient

    func setPinned(_ pinned: Bool, sessionID: String) async throws {
        _ = try await client.pinSession(id: sessionID, pinned: pinned)
    }

    func archive(sessionID: String) async throws {
        try await setArchived(true, sessionID: sessionID)
    }

    func unarchive(sessionID: String) async throws {
        try await setArchived(false, sessionID: sessionID)
    }

    private func setArchived(_ archived: Bool, sessionID: String) async throws {
        _ = try await client.archiveSession(id: sessionID, archived: archived)
    }

    func delete(sessionID: String) async throws {
        _ = try await client.deleteSession(id: sessionID)
    }

    func rename(sessionID: String, title: String) async throws -> SessionMutationResponse {
        try await client.renameSession(id: sessionID, title: title)
    }

    func move(sessionID: String, to projectID: String?) async throws {
        _ = try await client.moveSession(id: sessionID, projectID: projectID)
    }

    func duplicate(sessionID: String, title: String) async throws -> SessionDuplicateResult {
        let response = try await client.branchSession(id: sessionID, title: title)

        guard let duplicatedSessionID = response.sessionId else {
            return SessionDuplicateResult(
                session: nil,
                errorMessage: response.error ?? String(localized: "The server did not return the duplicated session ID.")
            )
        }

        let duplicatedResponse = try await client.session(
            id: duplicatedSessionID,
            includeMessages: false,
            messageLimit: nil
        )

        guard let duplicatedSessionDetail = duplicatedResponse.session else {
            return SessionDuplicateResult(
                session: nil,
                errorMessage: String(localized: "The server did not return the duplicated session.")
            )
        }

        return SessionDuplicateResult(
            session: SessionSummary(from: duplicatedSessionDetail),
            errorMessage: nil
        )
    }
}
