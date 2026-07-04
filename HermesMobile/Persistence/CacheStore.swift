import Foundation
import SwiftData

enum CacheStore {
    @MainActor
    static func cachedSessions(
        serverURL: URL,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> [SessionSummary] {
        let serverURLString = serverURL.absoluteString
        let descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.serverURLString == serverURLString
            }
        )

        return try context.fetch(descriptor)
            .filter { $0.archived != true && $0.expiresAt > now }
            .map(SessionSummary.init(cachedSession:))
    }

    @MainActor
    static func cachedMessages(
        serverURL: URL,
        sessionID: String,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> [ChatMessage] {
        let serverURLString = serverURL.absoluteString
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { cachedMessage in
                cachedMessage.serverURLString == serverURLString
                    && cachedMessage.sessionID == sessionID
            }
        )

        return try context.fetch(descriptor)
            .filter { $0.expiresAt > now }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(ChatMessage.init(cachedMessage:))
    }

    @MainActor
    static func cacheSessions(
        _ sessions: [SessionSummary],
        serverURL: URL,
        in context: ModelContext,
        cachedAt: Date = Date()
    ) throws {
        let serverURLString = serverURL.absoluteString
        let cacheableSessions = sessions.filter { $0.archived != true && $0.sessionId != nil }
        let freshKeys = Set(cacheableSessions.compactMap { session -> String? in
            guard let sessionID = session.sessionId else { return nil }
            return CachedSession.cacheKey(serverURLString: serverURLString, sessionID: sessionID)
        })

        for session in cacheableSessions {
            guard let sessionID = session.sessionId else { continue }
            let cacheKey = CachedSession.cacheKey(serverURLString: serverURLString, sessionID: sessionID)
            if let cachedSession = try cachedSession(cacheKey: cacheKey, in: context) {
                cachedSession.apply(session, cachedAt: cachedAt)
            } else {
                context.insert(CachedSession(serverURLString: serverURLString, session: session, cachedAt: cachedAt))
            }
        }

        let descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.serverURLString == serverURLString
            }
        )
        let staleSessions = try context.fetch(descriptor).filter { !freshKeys.contains($0.cacheKey) }
        if !staleSessions.isEmpty {
            // Also drop the stale sessions' messages so they don't linger as
            // unreachable orphans squatting the message eviction budget.
            let staleSessionIDs = staleSessions.map(\.sessionID)
            let orphanDescriptor = FetchDescriptor<CachedMessage>(
                predicate: #Predicate { cachedMessage in
                    cachedMessage.serverURLString == serverURLString
                        && staleSessionIDs.contains(cachedMessage.sessionID)
                }
            )
            for orphanedMessage in try context.fetch(orphanDescriptor) {
                context.delete(orphanedMessage)
            }
        }
        for staleSession in staleSessions {
            context.delete(staleSession)
        }

        try performMaintenance(in: context, now: cachedAt)
        try context.save()
    }

    @MainActor
    static func cacheSession(
        _ session: SessionSummary,
        serverURL: URL,
        in context: ModelContext,
        cachedAt: Date = Date()
    ) throws {
        guard let sessionID = session.sessionId else { return }

        let serverURLString = serverURL.absoluteString
        let cacheKey = CachedSession.cacheKey(serverURLString: serverURLString, sessionID: sessionID)

        if session.archived == true {
            if let cachedSession = try cachedSession(cacheKey: cacheKey, in: context) {
                context.delete(cachedSession)
            }
        } else if let cachedSession = try cachedSession(cacheKey: cacheKey, in: context) {
            cachedSession.apply(session, cachedAt: cachedAt)
        } else {
            context.insert(CachedSession(serverURLString: serverURLString, session: session, cachedAt: cachedAt))
        }

        try performMaintenance(in: context, now: cachedAt)
        try context.save()
    }

    @MainActor
    static func cacheMessages(
        _ messages: [ChatMessage],
        serverURL: URL,
        sessionID: String,
        in context: ModelContext,
        cachedAt: Date = Date()
    ) throws {
        let serverURLString = serverURL.absoluteString
        let batchKeys = messageCacheKeys(for: messages, serverURLString: serverURLString, sessionID: sessionID)
        let freshKeys = Set(batchKeys)

        // One scoped fetch for the whole batch instead of one fetch per
        // message; upserts and stale-removal both work off this snapshot.
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { cachedMessage in
                cachedMessage.serverURLString == serverURLString
                    && cachedMessage.sessionID == sessionID
            }
        )
        let existingMessages = try context.fetch(descriptor)
        var messagesByKey = Dictionary(existingMessages.map { ($0.cacheKey, $0) }) { first, _ in first }

        for (offset, message) in messages.enumerated() {
            let cacheKey = batchKeys[offset]
            if let cachedMessage = messagesByKey[cacheKey] {
                cachedMessage.apply(message, sortIndex: offset, cachedAt: cachedAt)
            } else {
                let cachedMessage = CachedMessage(
                    serverURLString: serverURLString,
                    sessionID: sessionID,
                    message: message,
                    sortIndex: offset,
                    cacheKey: cacheKey,
                    cachedAt: cachedAt
                )
                context.insert(cachedMessage)
                messagesByKey[cacheKey] = cachedMessage
            }
        }

        for staleMessage in existingMessages where !freshKeys.contains(staleMessage.cacheKey) {
            context.delete(staleMessage)
        }

        try performMaintenance(in: context, now: cachedAt)
        try context.save()
    }

    @MainActor
    static func clearAll(in context: ModelContext) throws {
        for cachedSession in try context.fetch(FetchDescriptor<CachedSession>()) {
            context.delete(cachedSession)
        }

        for cachedMessage in try context.fetch(FetchDescriptor<CachedMessage>()) {
            context.delete(cachedMessage)
        }

        try context.save()
    }

    /// Deletes only the cached sessions and messages belonging to `serverURL`,
    /// leaving every other configured server's offline data intact (#18). Backs
    /// the Settings "Clear Offline Cache" action (active server) and the purge
    /// of a server's cache when it is removed, so a removed/reset server never
    /// leaves orphaned rows behind.
    @MainActor
    static func clearCache(for serverURL: URL, in context: ModelContext) throws {
        let serverURLString = serverURL.absoluteString

        let sessionDescriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.serverURLString == serverURLString
            }
        )
        for cachedSession in try context.fetch(sessionDescriptor) {
            context.delete(cachedSession)
        }

        let messageDescriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { cachedMessage in
                cachedMessage.serverURLString == serverURLString
            }
        )
        for cachedMessage in try context.fetch(messageDescriptor) {
            context.delete(cachedMessage)
        }

        try context.save()
    }

    /// Timestamp of the last completed maintenance pass. Housekeeping is
    /// debounced to at most one pass per `CachePolicy.maintenanceInterval`
    /// so expiry/eviction scans don't run on every cache write. Internal so
    /// tests can reset it to force the next write to run maintenance.
    @MainActor
    static var lastMaintenanceRun: Date?

    @MainActor
    private static func performMaintenance(in context: ModelContext, now: Date) throws {
        if let lastRun = lastMaintenanceRun,
           abs(now.timeIntervalSince(lastRun)) < CachePolicy.maintenanceInterval {
            return
        }
        lastMaintenanceRun = now

        // `fetchCount` only consults the persistent store, so flush pending
        // inserts/deletes first to keep the eviction math accurate.
        if context.hasChanges {
            try context.save()
        }

        try deleteExpiredSessions(in: context, now: now)
        try deleteExpiredMessages(in: context, now: now)
        try evictOldestMessagesIfNeeded(in: context)
    }

    @MainActor
    private static func deleteExpiredSessions(in context: ModelContext, now: Date) throws {
        let descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.expiresAt <= now
            }
        )
        for session in try context.fetch(descriptor) {
            context.delete(session)
        }
    }

    @MainActor
    private static func deleteExpiredMessages(in context: ModelContext, now: Date) throws {
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { cachedMessage in
                cachedMessage.expiresAt <= now
            }
        )
        for message in try context.fetch(descriptor) {
            context.delete(message)
        }
    }

    @MainActor
    private static func evictOldestMessagesIfNeeded(in context: ModelContext) throws {
        let overflowCount = try context.fetchCount(FetchDescriptor<CachedMessage>()) - CachePolicy.maxMessages
        guard overflowCount > 0 else { return }

        var descriptor = FetchDescriptor<CachedMessage>(
            sortBy: [
                SortDescriptor(\.cachedAt),
                SortDescriptor(\.timestamp),
                SortDescriptor(\.sortIndex)
            ]
        )
        descriptor.fetchLimit = overflowCount
        for message in try context.fetch(descriptor) {
            context.delete(message)
        }
    }

    @MainActor
    private static func cachedSession(cacheKey: String, in context: ModelContext) throws -> CachedSession? {
        var descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { cachedSession in
                cachedSession.cacheKey == cacheKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Computes the cache key for every message in a sync batch. Identical
    /// id-less messages (same role, timestamp, and content) would otherwise
    /// collide, so each repeat gets a deterministic per-batch occurrence
    /// index appended to its key.
    private static func messageCacheKeys(
        for messages: [ChatMessage],
        serverURLString: String,
        sessionID: String
    ) -> [String] {
        var occurrences: [String: Int] = [:]
        return messages.map { message in
            let baseKey = CachedMessage.cacheKey(
                serverURLString: serverURLString,
                sessionID: sessionID,
                message: message
            )
            let occurrence = occurrences[baseKey, default: 0]
            occurrences[baseKey] = occurrence + 1
            guard occurrence > 0, message.messageId == nil else { return baseKey }
            return CachedMessage.cacheKey(
                serverURLString: serverURLString,
                sessionID: sessionID,
                message: message,
                occurrence: occurrence
            )
        }
    }
}

private extension SessionSummary {
    init(cachedSession: CachedSession) {
        sessionId = cachedSession.sessionID
        title = cachedSession.title
        workspace = cachedSession.workspace
        model = cachedSession.model
        modelProvider = cachedSession.modelProvider
        messageCount = cachedSession.messageCount
        createdAt = cachedSession.createdAt
        updatedAt = cachedSession.updatedAt
        lastMessageAt = cachedSession.lastMessageAt
        pinned = cachedSession.pinned
        archived = cachedSession.archived
        projectId = cachedSession.projectId
        profile = cachedSession.profile
        inputTokens = cachedSession.inputTokens
        outputTokens = cachedSession.outputTokens
        estimatedCost = cachedSession.estimatedCost
        activeStreamId = cachedSession.activeStreamId
        isStreaming = cachedSession.isStreaming
        isCliSession = cachedSession.isCliSession
        sourceTag = cachedSession.sourceTag
        sessionSource = cachedSession.sessionSource
        sourceLabel = cachedSession.sourceLabel
        matchType = nil
    }
}

private extension ChatMessage {
    init(cachedMessage: CachedMessage) {
        let attachments: [MessageAttachment]?
        if let data = cachedMessage.attachmentsData {
            attachments = try? JSONDecoder().decode([MessageAttachment].self, from: data)
        } else {
            attachments = nil
        }
        self.init(
            role: cachedMessage.role,
            content: cachedMessage.content,
            timestamp: cachedMessage.timestamp,
            messageId: cachedMessage.messageId,
            name: cachedMessage.name,
            toolCallId: cachedMessage.toolCallId,
            reasoning: cachedMessage.reasoning,
            attachments: attachments
        )
    }
}
