import Foundation
import Observation
import SwiftData
import SwiftUI

struct SessionListSection: Identifiable {
    enum Kind: String {
        case pinned
        case today
        case yesterday
        case earlier
    }

    let kind: Kind
    let title: String
    let sessions: [SessionSummary]

    var id: String { kind.rawValue }
}

enum ActiveSessionStateRefreshResult: Equatable {
    case unchanged
    case reloaded
    case failed
}

@MainActor
@Observable
final class SessionListViewModel {
    private(set) var sessions: [SessionSummary] = []
    private(set) var isLoading = false
    private(set) var isCreatingSession = false
    private(set) var isCreatingProject = false
    private(set) var isLoadingProjects = false
    private(set) var isDeletingProject = false
    private(set) var isRenamingSession = false
    private(set) var isRenamingProject = false
    private(set) var isMovingSession = false
    private(set) var isViewingCachedData = false
    private(set) var projects: [ProjectSummary] = []
    private(set) var errorMessage: String?
    private(set) var actionErrorMessage: String?
    private(set) var cacheErrorMessage: String?
    private(set) var searchErrorMessage: String?
    private(set) var isSearchingRemoteSessions = false
    private(set) var sessionLoadError: Error?
    private(set) var lastError: Error?
    private(set) var activeProfileName: String?
    private(set) var activeProfileDisplayName: String?
    private(set) var activeProfileModel: String?
    private(set) var activeProfileProvider: String?
    private(set) var profileOptions: [ProfileSummary] = []
    private(set) var isLoadingActiveProfile = false
    private(set) var isSwitchingActiveProfile = false
    private(set) var switchingActiveProfileName: String?
    private(set) var activeProfileErrorMessage: String?
    private(set) var mutatingSessionIDs: Set<String> = []
    private var trackedActiveSessionIDs: Set<String> = []
    private var recentlyCompletedSessionIDs: Set<String> = []

    private(set) var remoteContentSearchSessionIDs: [String] = []
    private var activeRemoteSearchQuery: String?

    private let client: APIClient
    private let sessionMutator: SessionMutator
    private let server: URL

    init(server: URL, client: APIClient? = nil) {
        self.server = server
        let resolvedClient = client ?? APIClient(baseURL: server)
        self.client = resolvedClient
        self.sessionMutator = SessionMutator(client: resolvedClient)
    }

    var sections: [SessionListSection] {
        let sortedSessions = sessions.sorted { left, right in
            timestamp(for: left) > timestamp(for: right)
        }
        let pinned = sortedSessions.filter { $0.pinned == true }
        let unpinned = sortedSessions.filter { $0.pinned != true }

        let calendar = Calendar.current
        let today = unpinned.filter { session in
            guard let date = date(for: session) else { return false }
            return calendar.isDateInToday(date)
        }
        let yesterday = unpinned.filter { session in
            guard let date = date(for: session) else { return false }
            return calendar.isDateInYesterday(date)
        }
        let earlier = unpinned.filter { session in
            guard let date = date(for: session) else { return true }
            return !calendar.isDateInToday(date) && !calendar.isDateInYesterday(date)
        }

        return [
            SessionListSection(kind: .pinned, title: String(localized: "Pinned"), sessions: pinned),
            SessionListSection(kind: .today, title: String(localized: "Today"), sessions: today),
            SessionListSection(kind: .yesterday, title: String(localized: "Yesterday"), sessions: yesterday),
            SessionListSection(kind: .earlier, title: String(localized: "Earlier"), sessions: earlier)
        ]
        .filter { !$0.sessions.isEmpty }
    }

    func visibleSessions(
        searchText rawSearchText: String,
        selectedProjectID: String?,
        automatedVisibility: AutomatedSessionVisibility = .showAll
    ) -> [SessionSummary] {
        let query = Self.normalizedSearchQuery(rawSearchText)
        let baseSessions = sessions.filter { automatedVisibility.shows($0) }
        let projectFilteredSessions = baseSessions.filter { session in
            guard let selectedProjectID else { return true }
            return session.projectId == selectedProjectID
        }
        let localMatches = projectFilteredSessions.filter { session in
            guard !query.isEmpty else { return true }
            return Self.searchableText(for: session).contains(query)
        }
        let sortedLocalMatches = Self.sortedSessions(localMatches)

        guard !query.isEmpty, activeRemoteSearchQuery == query else {
            return sortedLocalMatches
        }

        let localMatchIDs = Set(sortedLocalMatches.compactMap(\.sessionId))
        let sessionsByID = Dictionary(
            projectFilteredSessions.compactMap { session -> (String, SessionSummary)? in
                guard let sessionID = session.sessionId, !sessionID.isEmpty else { return nil }
                return (sessionID, session)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let remoteMatches = remoteContentSearchSessionIDs.compactMap { sessionID -> SessionSummary? in
            guard !localMatchIDs.contains(sessionID) else { return nil }
            return sessionsByID[sessionID]
        }

        return sortedLocalMatches + Self.sortedSessions(remoteMatches)
    }

    @discardableResult
    func load(modelContext: ModelContext? = nil, animation: Animation? = nil) async -> Bool {
        isLoading = true
        errorMessage = nil
        cacheErrorMessage = nil
        sessionLoadError = nil
        lastError = nil
        defer { isLoading = false }

        do {
            let response = try await client.sessions()
            let visibleSessions = (response.sessions ?? []).filter { $0.archived != true }
            applySessions(visibleSessions, animation: animation)
            isViewingCachedData = false

            if let modelContext {
                do {
                    try CacheStore.cacheSessions(visibleSessions, serverURL: server, in: modelContext)
                } catch {
                    cacheErrorMessage = error.localizedDescription
                }
            }

            return true
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            sessionLoadError = error
            if CacheFallbackPolicy.shouldUseCache(for: error), let modelContext {
                do {
                    let cachedSessions = try CacheStore.cachedSessions(serverURL: server, in: modelContext)
                    if !cachedSessions.isEmpty {
                        sessions = cachedSessions
                        isViewingCachedData = true
                        errorMessage = nil
                    } else {
                        isViewingCachedData = false
                        errorMessage = error.localizedDescription
                    }
                } catch {
                    cacheErrorMessage = error.localizedDescription
                    isViewingCachedData = false
                    errorMessage = lastError?.localizedDescription
                }
            } else {
                isViewingCachedData = false
                errorMessage = error.localizedDescription
            }

            return false
        }
    }

    func loadActiveProfile() async {
        guard !isLoadingActiveProfile else { return }

        isLoadingActiveProfile = true
        activeProfileErrorMessage = nil
        defer { isLoadingActiveProfile = false }

        do {
            let response = try await client.profiles()
            applyActiveProfile(response)
        } catch {
            guard !error.isCancellation else { return }

            activeProfileErrorMessage = error.localizedDescription
        }
    }

    func switchActiveProfile(_ profile: ProfileSummary) async -> Bool {
        guard !isViewingCachedData else {
            activeProfileErrorMessage = String(localized: "Reconnect to the server to change profiles.")
            return false
        }

        guard let profileName = Self.nonEmpty(profile.name) else {
            activeProfileErrorMessage = String(localized: "The server did not provide a profile name.")
            return false
        }

        guard profileName != activeProfileName else {
            return true
        }

        isSwitchingActiveProfile = true
        switchingActiveProfileName = profileName
        activeProfileErrorMessage = nil
        lastError = nil
        defer {
            isSwitchingActiveProfile = false
            switchingActiveProfileName = nil
        }

        do {
            let response = try await client.switchProfile(name: profileName)
            if let error = Self.nonEmpty(response.error) {
                activeProfileErrorMessage = error
                return false
            }

            let resolvedName = Self.nonEmpty(response.active) ?? profileName
            let profileResponse = ProfilesResponse(profiles: response.profiles ?? profileOptions, active: resolvedName)
            applyActiveProfile(
                profileResponse,
                fallbackProfile: profile,
                fallbackDefaultModel: response.defaultModel
            )
            return true
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            activeProfileErrorMessage = error.localizedDescription
            return false
        }
    }

    func searchSessions(
        query rawQuery: String,
        content: Bool = true,
        depth: Int = 5,
        debounceNanoseconds: UInt64 = 350_000_000
    ) async {
        let query = Self.normalizedSearchQuery(rawQuery)
        activeRemoteSearchQuery = query
        remoteContentSearchSessionIDs = []
        searchErrorMessage = nil

        guard !query.isEmpty, !isViewingCachedData else {
            isSearchingRemoteSessions = false
            return
        }

        do {
            if debounceNanoseconds > 0 {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            }

            guard !Task.isCancelled, activeRemoteSearchQuery == query else { return }

            isSearchingRemoteSessions = true
            let response = try await client.searchSessions(query: query, content: content, depth: depth)

            guard !Task.isCancelled, activeRemoteSearchQuery == query else { return }

            remoteContentSearchSessionIDs = contentMatchIDs(from: response.sessions ?? [])
            isSearchingRemoteSessions = false
        } catch {
            guard activeRemoteSearchQuery == query else { return }

            isSearchingRemoteSessions = false
            guard !error.isCancellation else { return }

            remoteContentSearchSessionIDs = []
            searchErrorMessage = error.localizedDescription
            lastError = error
        }
    }

    func clearSearchResults() {
        activeRemoteSearchQuery = nil
        remoteContentSearchSessionIDs = []
        searchErrorMessage = nil
        isSearchingRemoteSessions = false
    }

    private var loadFailureRefreshResult: ActiveSessionStateRefreshResult {
        lastError == nil ? .unchanged : .failed
    }

    /// True after the degenerate monitor state — rows flagged `is_streaming` with no
    /// `active_stream_id` to poll — has already triggered its one reload. Without this,
    /// the periodic active-row monitor would re-fetch the whole session list on every
    /// tick while such a session exists.
    private var didReloadForStreamlessActiveSessions = false

    @discardableResult
    func refreshActiveSessionStatesIfNeeded(
        streamIDs rawStreamIDs: [String],
        sessionIDs rawSessionIDs: [String] = [],
        modelContext: ModelContext? = nil
    ) async -> ActiveSessionStateRefreshResult {
        guard !isViewingCachedData, !isLoading else { return .unchanged }

        let streamIDs = Self.normalizedStreamIDs(rawStreamIDs)
        let monitoredSessionIDs = Set(rawSessionIDs.compactMap(Self.nonEmpty))

        if !monitoredSessionIDs.isEmpty {
            updateTrackedActiveSessions(monitoredSessionIDs: monitoredSessionIDs)
        }

        guard !streamIDs.isEmpty else {
            if !monitoredSessionIDs.isEmpty {
                return await refreshMonitoredSessionStatuses(
                    monitoredSessionIDs: monitoredSessionIDs,
                    reloadsInactiveStreamlessRows: Self.hasStreamlessActiveSession(
                        in: sessions,
                        matching: monitoredSessionIDs
                    ),
                    modelContext: modelContext
                )
            }

            // A session can report `is_streaming` without a stream ID to poll. Reload at
            // most once per transition into that state so a stale flag gets one chance to
            // clear, instead of a full list reload on every monitor tick.
            guard !didReloadForStreamlessActiveSessions else { return .unchanged }
            didReloadForStreamlessActiveSessions = true
            return await load(modelContext: modelContext) ? .reloaded : loadFailureRefreshResult
        }

        didReloadForStreamlessActiveSessions = false

        for streamID in streamIDs {
            do {
                let response = try await client.chatStreamStatus(streamID: streamID)
                guard response.active == false else { continue }
                return await reloadTrackedSessionStates(
                    monitoredSessionIDs: monitoredSessionIDs,
                    modelContext: modelContext
                )
            } catch {
                guard !error.isCancellation else { return .unchanged }
                if case APIError.unauthorized = error {
                    lastError = error
                    return .failed
                }
                continue
            }
        }

        return .unchanged
    }

    func consumeRecentlyCompletedSessionIDs() -> Set<String> {
        defer { recentlyCompletedSessionIDs.removeAll() }
        return recentlyCompletedSessionIDs
    }

    private func reloadTrackedSessionStates(
        monitoredSessionIDs: Set<String>,
        modelContext: ModelContext?
    ) async -> ActiveSessionStateRefreshResult {
        let didLoad = await load(modelContext: modelContext)
        guard didLoad else { return loadFailureRefreshResult }

        if !monitoredSessionIDs.isEmpty {
            updateTrackedActiveSessions(monitoredSessionIDs: monitoredSessionIDs)
        }

        return .reloaded
    }

    private func refreshMonitoredSessionStatuses(
        monitoredSessionIDs: Set<String>,
        reloadsInactiveStreamlessRows: Bool,
        modelContext: ModelContext?
    ) async -> ActiveSessionStateRefreshResult {
        for sessionID in monitoredSessionIDs.sorted() {
            do {
                let status = try await client.sessionStatus(id: sessionID)
                guard Self.isActiveStatus(status) else { continue }
                didReloadForStreamlessActiveSessions = false
                return await reloadTrackedSessionStates(
                    monitoredSessionIDs: monitoredSessionIDs,
                    modelContext: modelContext
                )
            } catch {
                guard !error.isCancellation else { return .unchanged }
                if case APIError.unauthorized = error {
                    lastError = error
                    return .failed
                }
                continue
            }
        }

        guard reloadsInactiveStreamlessRows else { return .unchanged }

        // A row can be locally marked `is_streaming` before the server exposes a
        // live stream ID. If direct status says none of the monitored sessions is
        // active, reload once per such transition to clear the stale local flag.
        guard !didReloadForStreamlessActiveSessions else { return .unchanged }
        didReloadForStreamlessActiveSessions = true
        return await reloadTrackedSessionStates(
            monitoredSessionIDs: monitoredSessionIDs,
            modelContext: modelContext
        )
    }

    private func updateTrackedActiveSessions(monitoredSessionIDs: Set<String>) {
        recentlyCompletedSessionIDs.removeAll()

        let currentActiveSessionIDs = Self.activeSessionIDs(in: sessions, matching: monitoredSessionIDs)
        let completedSessionIDs = trackedActiveSessionIDs
            .intersection(monitoredSessionIDs)
            .subtracting(currentActiveSessionIDs)

        recentlyCompletedSessionIDs.formUnion(completedSessionIDs)
        trackedActiveSessionIDs = trackedActiveSessionIDs
            .subtracting(monitoredSessionIDs)
            .union(currentActiveSessionIDs)
    }

    func loadSessionForDeepLink(id rawSessionID: String, modelContext: ModelContext? = nil) async -> SessionSummary? {
        let sessionID = rawSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty else { return nil }

        if let loadedSession = sessions.first(where: { $0.sessionId == sessionID }) {
            return loadedSession
        }

        actionErrorMessage = nil
        lastError = nil

        if let modelContext {
            do {
                if let cachedSession = try CacheStore.cachedSessions(serverURL: server, in: modelContext)
                    .first(where: { $0.sessionId == sessionID }) {
                    return cachedSession
                }
            } catch {
                cacheErrorMessage = error.localizedDescription
            }
        }

        do {
            let response = try await client.session(id: sessionID, includeMessages: false, messageLimit: nil)
            guard let sessionDetail = response.session else {
                actionErrorMessage = String(localized: "The server did not return the linked session.")
                return nil
            }

            let session = SessionSummary(from: sessionDetail)
            if session.archived != true, !sessions.contains(where: { $0.sessionId == session.sessionId }) {
                sessions.insert(session, at: 0)
            }

            if let modelContext {
                do {
                    try CacheStore.cacheSession(session, serverURL: server, in: modelContext)
                } catch {
                    cacheErrorMessage = error.localizedDescription
                }
            }

            return session
        } catch {
            lastError = error
            actionErrorMessage = error.localizedDescription
            return nil
        }
    }

    func setPinned(
        _ pinned: Bool,
        for session: SessionSummary,
        modelContext: ModelContext? = nil,
        animation: Animation? = nil
    ) async -> Bool {
        guard let sessionId = Self.nonEmpty(session.sessionId) else {
            actionErrorMessage = String(localized: "The server did not provide a session ID.")
            return false
        }

        guard beginSessionMutation(sessionId) else { return false }
        defer { endSessionMutation(sessionId) }

        return await mutate(modelContext: modelContext, animation: animation) {
            try await sessionMutator.setPinned(pinned, sessionID: sessionId)
        }
    }

    func archive(
        _ session: SessionSummary,
        modelContext: ModelContext? = nil,
        animation: Animation? = nil
    ) async -> Bool {
        guard let sessionId = Self.nonEmpty(session.sessionId) else {
            actionErrorMessage = String(localized: "The server did not provide a session ID.")
            return false
        }

        let archiveIDs = archiveCascadeIDs(forParentSessionID: sessionId)
        guard beginSessionMutations(archiveIDs) else { return false }
        defer { endSessionMutations(archiveIDs) }

        actionErrorMessage = nil
        lastError = nil

        do {
            var archivedIDs: [String] = []
            do {
                for archiveID in archiveIDs {
                    try await sessionMutator.archive(sessionID: archiveID)
                    archivedIDs.append(archiveID)
                }
            } catch {
                await rollbackArchiveCascade(for: archivedIDs)
                throw error
            }

            let didReload = await load(modelContext: modelContext, animation: animation)
            guard didReload else { return false }

            removeArchivedCascadeLocally(
                sessionIDs: Set(archiveIDs),
                modelContext: modelContext,
                animation: animation
            )
            return true
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    func delete(
        _ session: SessionSummary,
        modelContext: ModelContext? = nil,
        animation: Animation? = nil
    ) async -> Bool {
        guard let sessionId = Self.nonEmpty(session.sessionId) else {
            actionErrorMessage = String(localized: "The server did not provide a session ID.")
            return false
        }

        guard beginSessionMutation(sessionId) else { return false }
        defer { endSessionMutation(sessionId) }

        return await mutate(modelContext: modelContext, animation: animation) {
            try await sessionMutator.delete(sessionID: sessionId)
        }
    }

    func isMutating(_ session: SessionSummary) -> Bool {
        guard let sessionId = Self.nonEmpty(session.sessionId) else { return false }
        return mutatingSessionIDs.contains(sessionId)
    }

    @discardableResult
    func applyTitleUpdate(
        sessionID rawSessionID: String?,
        title rawTitle: String,
        modelContext: ModelContext? = nil
    ) -> Bool {
        guard let sessionID = Self.nonEmpty(rawSessionID),
              let title = Self.nonEmpty(rawTitle),
              let existingIndex = sessions.firstIndex(where: { $0.sessionId == sessionID })
        else {
            return false
        }

        let existingSession = sessions[existingIndex]
        guard Self.nonEmpty(existingSession.title) != title else { return false }

        let updatedSession = existingSession.replacingTitle(with: title)
        sessions[existingIndex] = updatedSession

        if let modelContext {
            do {
                try CacheStore.cacheSession(updatedSession, serverURL: server, in: modelContext)
            } catch {
                cacheErrorMessage = error.localizedDescription
            }
        }

        return true
    }

    /// Patches the matching row with live activity pushed from an open chat
    /// (stream started/ended, new messages) without any network request, then
    /// re-sorts the list so the active row surfaces by recency. Making the row's
    /// `activeStreamId`/`isStreaming` visible here is also what flips the view's
    /// active-row monitor eligibility so the 1 Hz poll starts.
    @discardableResult
    func applySessionActivityUpdate(
        _ update: SessionActivityUpdate,
        modelContext: ModelContext? = nil
    ) -> Bool {
        guard let sessionID = Self.nonEmpty(update.sessionID),
              let existingIndex = sessions.firstIndex(where: { $0.sessionId == sessionID })
        else {
            return false
        }

        let existingSession = sessions[existingIndex]
        let updatedSession = existingSession.replacingActivity(
            activeStreamId: Self.nonEmpty(update.activeStreamId),
            isStreaming: update.isStreaming,
            messageCount: update.messageCount,
            lastMessageAt: update.lastMessageAt
        )
        guard updatedSession != existingSession else { return false }

        sessions[existingIndex] = updatedSession
        sessions = Self.sortedSessions(sessions)

        if let modelContext {
            do {
                try CacheStore.cacheSession(updatedSession, serverURL: server, in: modelContext)
            } catch {
                cacheErrorMessage = error.localizedDescription
            }
        }

        return true
    }

    /// Inserts a session created outside this list (fork-from-message,
    /// profile-switch new session) so the sidebar learns about it without a
    /// reload. Mirrors `createSession`'s local insertion: dedupes by ID,
    /// replacing an existing row instead of inserting a duplicate.
    @discardableResult
    func applyCreatedSession(
        _ session: SessionSummary,
        modelContext: ModelContext? = nil
    ) -> Bool {
        guard let sessionID = Self.nonEmpty(session.sessionId) else { return false }

        if let existingIndex = sessions.firstIndex(where: { $0.sessionId == sessionID }) {
            guard sessions[existingIndex] != session else { return false }
            sessions[existingIndex] = session
        } else {
            sessions.insert(session, at: 0)
        }

        if let modelContext {
            do {
                try CacheStore.cacheSession(session, serverURL: server, in: modelContext)
            } catch {
                cacheErrorMessage = error.localizedDescription
            }
        }

        return true
    }

    func rename(_ session: SessionSummary, to rawTitle: String, modelContext: ModelContext? = nil) async -> Bool {
        guard !isViewingCachedData else {
            actionErrorMessage = String(localized: "Reconnect to the server to rename a session.")
            return false
        }

        guard let sessionId = Self.nonEmpty(session.sessionId) else {
            actionErrorMessage = String(localized: "The server did not provide a session ID.")
            return false
        }

        guard let title = Self.nonEmpty(rawTitle) else {
            actionErrorMessage = String(localized: "Enter a session title.")
            return false
        }

        isRenamingSession = true
        actionErrorMessage = nil
        lastError = nil
        defer { isRenamingSession = false }

        do {
            let response = try await sessionMutator.rename(sessionID: sessionId, title: title)
            if let error = Self.nonEmpty(response.error) {
                actionErrorMessage = error
                return false
            }

            let resolvedTitle = Self.nonEmpty(response.session?.title) ?? title
            let baseSession = sessions.first(where: { $0.sessionId == sessionId }) ?? session
            let updatedSession = baseSession.replacingTitle(with: resolvedTitle)
            if let existingIndex = sessions.firstIndex(where: { $0.sessionId == sessionId }) {
                sessions[existingIndex] = updatedSession
            }

            if let modelContext {
                do {
                    try CacheStore.cacheSession(updatedSession, serverURL: server, in: modelContext)
                } catch {
                    cacheErrorMessage = error.localizedDescription
                }
            }

            return true
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    func duplicate(_ session: SessionSummary, modelContext: ModelContext? = nil) async -> SessionSummary? {
        guard let sessionId = Self.nonEmpty(session.sessionId) else {
            actionErrorMessage = String(localized: "The server did not provide a session ID.")
            return nil
        }

        guard beginSessionMutation(sessionId) else { return nil }
        defer { endSessionMutation(sessionId) }

        actionErrorMessage = nil
        lastError = nil

        do {
            let result = try await sessionMutator.duplicate(
                sessionID: sessionId,
                title: duplicateTitle(for: session)
            )

            guard let duplicatedSession = result.session else {
                actionErrorMessage = result.errorMessage
                return nil
            }

            await load(modelContext: modelContext)
            if !sessions.contains(where: { $0.sessionId == duplicatedSession.sessionId }) {
                sessions.insert(duplicatedSession, at: 0)

                if let modelContext {
                    do {
                        try CacheStore.cacheSessions(sessions, serverURL: server, in: modelContext)
                    } catch {
                        cacheErrorMessage = error.localizedDescription
                    }
                }
            }
            return duplicatedSession
        } catch {
            lastError = error
            actionErrorMessage = error.localizedDescription
            return nil
        }
    }

    func loadProjects() async {
        isLoadingProjects = true
        actionErrorMessage = nil
        lastError = nil
        defer { isLoadingProjects = false }

        do {
            let response = try await client.projects()
            projects = response.projects ?? []
        } catch {
            guard !error.isCancellation else { return }

            lastError = error
            actionErrorMessage = error.localizedDescription
        }
    }

    func move(_ session: SessionSummary, to projectID: String?, modelContext: ModelContext? = nil) async {
        guard let sessionId = Self.nonEmpty(session.sessionId) else {
            actionErrorMessage = String(localized: "The server did not provide a session ID.")
            return
        }

        guard beginSessionMutation(sessionId) else { return }
        defer { endSessionMutation(sessionId) }

        isMovingSession = true
        defer { isMovingSession = false }

        _ = await mutate(modelContext: modelContext) {
            try await sessionMutator.move(sessionID: sessionId, to: projectID)
        }
    }

    func createProject(
        named rawName: String,
        color: String,
        moving session: SessionSummary,
        modelContext: ModelContext? = nil
    ) async -> Bool {
        actionErrorMessage = nil
        lastError = nil

        guard let sessionId = session.sessionId else {
            actionErrorMessage = String(localized: "The server did not provide a session ID.")
            return false
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            actionErrorMessage = String(localized: "Enter a project name.")
            return false
        }

        isCreatingProject = true
        isMovingSession = true
        defer {
            isCreatingProject = false
            isMovingSession = false
        }

        do {
            let createResponse = try await client.createProject(name: name, color: color)
            guard let project = createResponse.project else {
                actionErrorMessage = createResponse.error ?? String(localized: "The server did not return the new project.")
                return false
            }

            guard let projectID = project.projectId, !projectID.isEmpty else {
                actionErrorMessage = createResponse.error ?? String(localized: "The server did not return the new project ID.")
                return false
            }

            upsertProject(project)
            try await sessionMutator.move(sessionID: sessionId, to: projectID)
            await load(modelContext: modelContext)
            return true
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Creates a new project without moving any session into it.
    ///
    /// Mirrors ``createProject(named:color:moving:modelContext:)`` but skips the
    /// `sessionMutator.move(...)` step, so the Projects sidebar's standalone
    /// "Add project" button can make an empty, unassigned project.
    func createEmptyProject(
        named rawName: String,
        color: String,
        modelContext: ModelContext? = nil
    ) async -> Bool {
        actionErrorMessage = nil
        lastError = nil

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            actionErrorMessage = String(localized: "Enter a project name.")
            return false
        }

        isCreatingProject = true
        defer { isCreatingProject = false }

        do {
            let createResponse = try await client.createProject(name: name, color: color)
            guard let project = createResponse.project else {
                actionErrorMessage = createResponse.error ?? String(localized: "The server did not return the new project.")
                return false
            }

            guard let projectID = project.projectId, !projectID.isEmpty else {
                actionErrorMessage = createResponse.error ?? String(localized: "The server did not return the new project ID.")
                return false
            }

            upsertProject(project)
            await load(modelContext: modelContext)
            return true
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ project: ProjectSummary, modelContext: ModelContext? = nil) async -> Bool {
        guard let projectID = project.projectId, !projectID.isEmpty else {
            actionErrorMessage = String(localized: "The server did not provide a project ID.")
            return false
        }

        isDeletingProject = true
        actionErrorMessage = nil
        lastError = nil
        defer { isDeletingProject = false }

        do {
            _ = try await client.deleteProject(id: projectID)
            projects.removeAll { $0.projectId == projectID }
            await load(modelContext: modelContext)
            return true
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    func rename(_ project: ProjectSummary, named rawName: String, color: String?) async -> Bool {
        actionErrorMessage = nil
        lastError = nil

        guard let projectID = project.projectId, !projectID.isEmpty else {
            actionErrorMessage = String(localized: "The server did not provide a project ID.")
            return false
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            actionErrorMessage = String(localized: "Enter a project name.")
            return false
        }

        isRenamingProject = true
        defer { isRenamingProject = false }

        do {
            let response = try await client.renameProject(id: projectID, name: name, color: color)
            guard let renamedProject = response.project else {
                actionErrorMessage = response.error ?? String(localized: "The server did not return the renamed project.")
                return false
            }

            guard renamedProject.projectId?.isEmpty == false else {
                actionErrorMessage = response.error ?? String(localized: "The server did not return the renamed project ID.")
                return false
            }

            upsertProject(renamedProject)
            return true
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Creates a new session. `profile` pins it to a specific server profile (the "New Chat
    /// in <Profile>" App Intent, #339); `model`/`modelProvider` let deep links from Wiki
    /// Apps preselect a model for the new session. Nil keeps the legacy behavior of letting
    /// the server use its active/default configuration.
    func createSession(
        modelContext: ModelContext? = nil,
        profile: String? = nil,
        model: String? = nil,
        modelProvider: String? = nil
    ) async -> SessionSummary? {
        isCreatingSession = true
        actionErrorMessage = nil
        lastError = nil
        defer { isCreatingSession = false }

        do {
            let workspaces = try await client.workspaces()
            let workspace = workspaces.last ?? workspaces.workspaces?.compactMap(\.path).first
            let response = try await client.createSession(
                workspace: workspace,
                model: Self.nonEmpty(model),
                modelProvider: Self.nonEmpty(modelProvider),
                profile: Self.nonEmpty(profile)
            )

            guard let sessionDetail = response.session else {
                actionErrorMessage = String(localized: "The server did not return the new session.")
                return nil
            }

            let newSession = SessionSummary(from: sessionDetail)
            guard newSession.sessionId?.isEmpty == false else {
                actionErrorMessage = String(localized: "The server did not return the new session ID.")
                return nil
            }

            if let existingIndex = sessions.firstIndex(where: { $0.sessionId == newSession.sessionId }) {
                sessions[existingIndex] = newSession
            } else {
                sessions.insert(newSession, at: 0)
            }

            if let modelContext {
                do {
                    try CacheStore.cacheSession(newSession, serverURL: server, in: modelContext)
                } catch {
                    cacheErrorMessage = error.localizedDescription
                }
            }

            return newSession
        } catch {
            guard !error.isCancellation else { return nil }

            lastError = error
            actionErrorMessage = error.localizedDescription
            return nil
        }
    }

    func clearActionError() {
        actionErrorMessage = nil
    }

    private static func normalizedSearchQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func activeStreamIDs(in sessions: [SessionSummary]) -> [String] {
        normalizedStreamIDs(sessions.compactMap(\.activeStreamId))
    }

    static func monitorSessionIDs(in sessions: [SessionSummary]) -> [String] {
        Array(Set(sessions.map(\.id).compactMap(nonEmpty))).sorted()
    }

    private static func activeSessionIDs(
        in sessions: [SessionSummary],
        matching monitoredSessionIDs: Set<String>
    ) -> Set<String> {
        Set(sessions.compactMap { session in
            guard monitoredSessionIDs.contains(session.id), isActiveSession(session) else {
                return nil
            }

            return session.id
        })
    }

    private static func isActiveSession(_ session: SessionSummary) -> Bool {
        session.isStreaming == true || nonEmpty(session.activeStreamId) != nil
    }

    private static func hasStreamlessActiveSession(
        in sessions: [SessionSummary],
        matching monitoredSessionIDs: Set<String>
    ) -> Bool {
        sessions.contains { session in
            monitoredSessionIDs.contains(session.id)
                && session.isStreaming == true
                && nonEmpty(session.activeStreamId) == nil
        }
    }

    private static func isActiveStatus(_ status: SessionStatusResponse) -> Bool {
        status.agentRunning == true || nonEmpty(status.activeStreamId) != nil || status.isStreaming == true
    }

    private static func normalizedStreamIDs(_ rawStreamIDs: [String]) -> [String] {
        Array(Set(rawStreamIDs.compactMap(nonEmpty))).sorted()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sortedSessions(_ sessions: [SessionSummary]) -> [SessionSummary] {
        sessions.sorted { left, right in
            if (left.pinned == true) != (right.pinned == true) {
                return left.pinned == true
            }

            return timestamp(for: left) > timestamp(for: right)
        }
    }

    private static func timestamp(for session: SessionSummary) -> Double {
        session.lastMessageAt ?? session.updatedAt ?? session.createdAt ?? 0
    }

    private static func searchableText(for session: SessionSummary) -> String {
        [
            session.title,
            session.workspace,
            session.model,
            session.modelProvider,
            session.profile,
            session.sourceLabel
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private func applySessions(_ newSessions: [SessionSummary], animation: Animation?) {
        guard let animation else {
            sessions = newSessions
            return
        }

        withAnimation(animation) {
            sessions = newSessions
        }
    }

    private func archiveCascadeIDs(forParentSessionID parentSessionID: String) -> [String] {
        let childIDs = sessions.compactMap { session -> String? in
            guard session.normalizedParentSessionId == parentSessionID,
                  session.isSubagentListChildSession
            else { return nil }

            return Self.nonEmpty(session.sessionId)
        }

        var seenIDs = Set<String>()
        return ([parentSessionID] + childIDs).filter { seenIDs.insert($0).inserted }
    }

    private func removeArchivedCascadeLocally(
        sessionIDs: Set<String>,
        modelContext: ModelContext?,
        animation: Animation?
    ) {
        let filteredSessions = sessions.filter { session in
            guard let sessionID = Self.nonEmpty(session.sessionId) else { return true }
            return !sessionIDs.contains(sessionID)
        }

        if filteredSessions != sessions {
            applySessions(filteredSessions, animation: animation)
        }

        guard let modelContext else { return }
        do {
            try CacheStore.cacheSessions(filteredSessions, serverURL: server, in: modelContext)
        } catch {
            cacheErrorMessage = error.localizedDescription
        }
    }

    private func rollbackArchiveCascade(for archivedIDs: [String]) async {
        for archivedID in archivedIDs.reversed() {
            do {
                try await sessionMutator.unarchive(sessionID: archivedID)
            } catch {
                cacheErrorMessage = String(
                    localized: "Archive rollback failed for session \(archivedID): \(error.localizedDescription)"
                )
            }
        }
    }

    private func contentMatchIDs(from sessions: [SessionSummary]) -> [String] {
        let locallyVisibleSessionIDs = Set(self.sessions.compactMap { session -> String? in
            guard session.archived != true, let sessionID = session.sessionId, !sessionID.isEmpty else {
                return nil
            }

            return sessionID
        })
        var seenSessionIDs = Set<String>()

        return sessions.compactMap { session in
            guard session.matchType?.lowercased() == "content",
                  let sessionID = session.sessionId,
                  locallyVisibleSessionIDs.contains(sessionID),
                  !seenSessionIDs.contains(sessionID)
            else {
                return nil
            }

            seenSessionIDs.insert(sessionID)
            return sessionID
        }
    }

    private func timestamp(for session: SessionSummary) -> Double {
        Self.timestamp(for: session)
    }

    private func date(for session: SessionSummary) -> Date? {
        let value = timestamp(for: session)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private func duplicateTitle(for session: SessionSummary) -> String {
        let baseTitle = Self.nonEmpty(session.title) ?? String(localized: "Untitled Session")
        return String(localized: "\(baseTitle) (copy)")
    }

    private func beginSessionMutation(_ sessionId: String) -> Bool {
        mutatingSessionIDs.insert(sessionId).inserted
    }

    private func endSessionMutation(_ sessionId: String) {
        mutatingSessionIDs.remove(sessionId)
    }

    private func beginSessionMutations(_ sessionIDs: [String]) -> Bool {
        // SessionListViewModel is @MainActor, so this check and assignment are serialized
        // with the rest of the session mutation state.
        let requestedSessionIDs = Set(sessionIDs)
        let updatedSessionIDs = mutatingSessionIDs.union(requestedSessionIDs)
        guard updatedSessionIDs.count == mutatingSessionIDs.count + requestedSessionIDs.count else {
            return false
        }

        mutatingSessionIDs = updatedSessionIDs
        return true
    }

    private func endSessionMutations(_ sessionIDs: [String]) {
        sessionIDs.forEach { mutatingSessionIDs.remove($0) }
    }

    private func upsertProject(_ project: ProjectSummary) {
        guard let projectID = project.projectId, !projectID.isEmpty else { return }

        if let existingIndex = projects.firstIndex(where: { $0.projectId == projectID }) {
            projects[existingIndex] = project
        } else {
            projects.append(project)
        }
    }

    private func applyActiveProfile(
        _ response: ProfilesResponse,
        fallbackProfile: ProfileSummary? = nil,
        fallbackDefaultModel: String? = nil
    ) {
        profileOptions = response.profiles ?? profileOptions

        // Keep the App Intents profile cache fresh so the "New Chat in <Profile>" picker
        // (#339) stays populated when the Shortcuts app resolves it in the background, where
        // a live, authenticated fetch may not be possible, then nudge the system to (re-)index
        // the parameterized App Shortcut (iOS only indexes it once its suggested values exist).
        // A nil `profiles` (field absent/undecoded) is left untouched — tolerant decoding — but
        // an explicit empty list is forwarded so `save([])` can clear a stale picker if the
        // server ever reports none.
        if let profiles = response.profiles {
            let changed = ProfileEntityCache.shared.save(profiles)
            ProfileEntityProvider.refreshAppShortcuts(changed: changed)
        }

        let profileName = response.effectiveDefaultProfileName
        let profile = response.profile(matching: profileName) ?? fallbackProfile

        activeProfileName = profileName
        activeProfileDisplayName = response.displayName(for: profileName)
            ?? profile?.displayName
        activeProfileModel = Self.nonEmpty(profile?.model) ?? Self.nonEmpty(fallbackDefaultModel)
        activeProfileProvider = Self.nonEmpty(profile?.provider)
    }

    private func mutate(
        modelContext: ModelContext? = nil,
        animation: Animation? = nil,
        _ operation: () async throws -> Void
    ) async -> Bool {
        actionErrorMessage = nil
        lastError = nil

        do {
            try await operation()
            return await load(modelContext: modelContext, animation: animation)
        } catch {
            guard !error.isCancellation else { return false }

            lastError = error
            actionErrorMessage = error.localizedDescription
            return false
        }
    }

}
