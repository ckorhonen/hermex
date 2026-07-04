import Foundation

/// Marker messages the agent emits around context compaction. The server sends
/// them as plain role-based messages with no structured flag, so — like the web
/// UI (`_isContextCompactionMessage` / `_isPreservedCompressionTaskListMessage`
/// in `ui.js`) — we detect them by content prefix.
enum ChatMarkerMessageKind: Equatable {
    case contextCompaction
    case preservedTaskList
    /// Synthesized "Context compaction · Reference only" anchor card built from
    /// session-level `compression_anchor_*` metadata — never produced by
    /// `classify`, which only sees literal marker messages.
    case compressionReference

    var title: String {
        switch self {
        case .contextCompaction, .compressionReference:
            return String(localized: "Context compaction")
        case .preservedTaskList:
            return String(localized: "Preserved task list")
        }
    }
}

struct PreservedTaskListItem: Equatable, Identifiable {
    enum State: Equatable {
        case active
        case checked
        case unchecked
    }

    let id: String
    let title: String
    let state: State
}

enum ChatMarkerMessageClassifier {
    private static let preservedTaskListPrefix = "[your active task list was preserved across context compression]"
    private static let contextCompactionPrefixes = [
        "[context compaction",
        "context compaction",
        "[prior context"
    ]

    static func classify(_ message: ChatMessage) -> ChatMarkerMessageKind? {
        guard let role = message.role, role != "tool" else { return nil }

        let text = trimmedContent(of: message)

        if hasCaseInsensitivePrefix(text, preservedTaskListPrefix) {
            return .preservedTaskList
        }

        if isContextCompactionText(text) {
            return .contextCompaction
        }

        return nil
    }

    /// Mirrors the web UI's `_isContextCompactionText`: true when the text is
    /// itself a literal compaction marker (used both for classification and to
    /// gate the synthesized reference card).
    static func isContextCompactionText(_ text: String?) -> Bool {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return contextCompactionPrefixes.contains { hasCaseInsensitivePrefix(trimmed, $0) }
    }

    /// The card body with the preserved-task-list marker line stripped, so the
    /// preview/expanded text starts at the actual task list (mirrors the web
    /// UI's `_preservedCompressionTaskListPreview`).
    static func cardBody(for kind: ChatMarkerMessageKind, content: String?) -> String {
        let text = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard kind == .preservedTaskList,
              let markerRange = text.range(
                of: preservedTaskListPrefix,
                options: [.caseInsensitive, .anchored]
              )
        else {
            return text
        }

        return String(text[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preservedTaskListItems(in content: String?) -> [PreservedTaskListItem] {
        let lines = (content ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        return lines.enumerated().compactMap { index, line in
            preservedTaskListItem(from: line, fallbackID: index)
        }
    }

    private static func trimmedContent(of message: ChatMessage) -> String {
        (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasCaseInsensitivePrefix(_ text: String, _ prefix: String) -> Bool {
        text.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
    }

    private static func preservedTaskListItem(from line: String, fallbackID: Int) -> PreservedTaskListItem? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let checkbox = markdownCheckboxState(in: text) {
            text = String(text[checkbox.remainingRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let id = stableTaskID(explicitID: leadingTaskID(in: text)?.id, title: text, fallbackID: fallbackID)
            return PreservedTaskListItem(id: id, title: text, state: checkbox.state)
        }

        let explicitID = leadingTaskID(in: text)
        if let explicitID {
            text = String(text[explicitID.remainingRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let status = trailingStatus(in: text) else { return nil }
        let title = String(text[..<status.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        return PreservedTaskListItem(
            id: stableTaskID(explicitID: explicitID?.id, title: title, fallbackID: fallbackID),
            title: title,
            state: state(forStatus: status.value)
        )
    }

    private static func markdownCheckboxState(in text: String) -> (state: PreservedTaskListItem.State, remainingRange: Range<String.Index>)? {
        guard text.hasPrefix("- [") || text.hasPrefix("* [") else { return nil }
        let markerIndex = text.index(text.startIndex, offsetBy: 3)
        let closingBracketIndex = text.index(text.startIndex, offsetBy: 4)
        let markerEnd = text.index(text.startIndex, offsetBy: 5)
        guard text.indices.contains(markerEnd),
              text[closingBracketIndex] == "]",
              text[markerEnd] == " "
        else { return nil }

        let marker = text[markerIndex]
        switch marker {
        case "x", "X":
            return (.checked, markerEnd..<text.endIndex)
        case " ":
            return (.unchecked, markerEnd..<text.endIndex)
        default:
            return nil
        }
    }

    private static func leadingTaskID(in text: String) -> (id: String, remainingRange: Range<String.Index>)? {
        guard let dotIndex = text.firstIndex(of: ".") else { return nil }
        let prefix = text[..<dotIndex]
        guard !prefix.isEmpty,
              prefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }

        let afterDot = text.index(after: dotIndex)
        guard afterDot < text.endIndex, text[afterDot].isWhitespace else { return nil }

        return (String(prefix), afterDot..<text.endIndex)
    }

    private static func trailingStatus(in text: String) -> (value: String, range: Range<String.Index>)? {
        guard text.hasSuffix(")"), let openIndex = text.lastIndex(of: "(") else { return nil }
        let statusStart = text.index(after: openIndex)
        let statusEnd = text.index(before: text.endIndex)
        guard statusStart < statusEnd else { return nil }
        return (String(text[statusStart..<statusEnd]), openIndex..<text.endIndex)
    }

    private static func state(forStatus status: String) -> PreservedTaskListItem.State {
        switch status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_") {
        case "complete", "completed", "done", "checked", "success":
            return .checked
        case "in_progress", "running", "active", "working":
            return .active
        default:
            return .unchecked
        }
    }

    private static func stableTaskID(explicitID: String?, title: String, fallbackID: Int) -> String {
        if let explicitID, !explicitID.isEmpty {
            return explicitID
        }

        let slug = title
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace || $0 == "-" || $0 == "_" }
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(6)
            .joined(separator: "-")
        return slug.isEmpty ? "task-\(fallbackID)" : slug
    }
}
