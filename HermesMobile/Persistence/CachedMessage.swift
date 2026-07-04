import CryptoKit
import Foundation
import SwiftData

@Model
final class CachedMessage {
    @Attribute(.unique) var cacheKey: String
    var serverURLString: String
    var sessionID: String
    /// Position within the cached transcript window. Deliberately *not* part
    /// of `cacheKey`: when a message merely shifts position (e.g. one message
    /// is inserted above it), `apply` updates this column in place instead of
    /// the whole tail being deleted and reinserted.
    var sortIndex: Int
    var role: String?
    var content: String?
    var timestamp: Double?
    var messageId: String?
    var name: String?
    var toolCallId: String?
    var reasoning: String?
    var attachmentsData: Data?
    var cachedAt: Date
    var expiresAt: Date

    init(
        serverURLString: String,
        sessionID: String,
        message: ChatMessage,
        sortIndex: Int,
        cacheKey: String? = nil,
        cachedAt: Date = Date()
    ) {
        self.cacheKey = cacheKey ?? Self.cacheKey(
            serverURLString: serverURLString,
            sessionID: sessionID,
            message: message
        )
        self.serverURLString = serverURLString
        self.sessionID = sessionID
        self.sortIndex = sortIndex
        self.cachedAt = cachedAt
        self.expiresAt = cachedAt.addingTimeInterval(CachePolicy.ttl)
        apply(message, sortIndex: sortIndex, cachedAt: cachedAt)
    }

    /// Builds the unique key for a cached message. Messages with a server
    /// `messageId` key on it directly. Id-less messages key on stable content
    /// identity — role, timestamp, and a SHA-256 digest of the content — plus
    /// an `occurrence` index that disambiguates identical duplicates within
    /// one sync batch, so a pure position shift never rewrites the tail of
    /// the transcript. (Rows written under the old sortIndex-based fallback
    /// keys simply miss once and are rewritten on the next sync.)
    static func cacheKey(
        serverURLString: String,
        sessionID: String,
        message: ChatMessage,
        occurrence: Int = 0
    ) -> String {
        let messagePart: String
        if let messageId = message.messageId {
            messagePart = messageId
        } else {
            let digest = SHA256.hash(data: Data((message.content ?? "").utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            messagePart = "content|\(message.role ?? "")|\(message.timestamp ?? 0)|\(digest)|\(occurrence)"
        }
        return "\(serverURLString)|session|\(sessionID)|message|\(messagePart)"
    }

    func apply(_ message: ChatMessage, sortIndex: Int, cachedAt: Date = Date()) {
        self.sortIndex = sortIndex
        role = message.role
        content = message.content
        timestamp = message.timestamp
        messageId = message.messageId
        name = message.name
        toolCallId = message.toolCallId
        reasoning = message.reasoning
        if let attachments = message.attachments, !attachments.isEmpty {
            attachmentsData = try? JSONEncoder().encode(attachments)
        } else {
            attachmentsData = nil
        }
        self.cachedAt = cachedAt
        expiresAt = cachedAt.addingTimeInterval(CachePolicy.ttl)
    }
}
