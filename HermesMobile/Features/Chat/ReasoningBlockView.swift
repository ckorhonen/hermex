import SwiftUI

struct ReasoningBlockView: View {
    let text: String
    /// Stable identity for the expand toggle in the session-scoped store; nil
    /// falls back to view-local state (previews, unkeyed call sites).
    var expansionKey: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.transcriptCardExpansionStore) private var expansionStore
    @AppStorage(ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey) private var startsExpanded = false
    @State private var localUserToggledExpansion: Bool?

    private var userToggledExpansion: Bool? {
        if let expansionKey, let expansionStore {
            return expansionStore.userToggledExpansion(forKey: expansionKey)
        }
        return localUserToggledExpansion
    }

    private func setUserToggledExpansion(_ value: Bool) {
        if let expansionKey, let expansionStore {
            expansionStore.setUserToggledExpansion(value, forKey: expansionKey)
        } else {
            localUserToggledExpansion = value
        }
    }

    private var isExpanded: Bool {
        ChatTranscriptDisplaySettings.isCardExpanded(
            userToggled: userToggledExpansion,
            startsExpanded: startsExpanded
        )
    }

    var body: some View {
        if let trimmedText {
            let summary = summary(for: trimmedText)

            VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
                Button {
                    withAnimation(ChatMotion.disclosure(reduceMotion: reduceMotion)) {
                        setUserToggledExpansion(!isExpanded)
                    }
                } label: {
                    header(summary: summary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Thinking, \(summary)"))
                .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")

                if isExpanded {
                    ReasoningMarkdownDetailsView(text: trimmedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(ChatMotion.disclosureTransition(reduceMotion: reduceMotion))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .chatTimelineAccessorySurface()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var usesStackedHeader: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private func header(summary: String) -> some View {
        HStack(alignment: usesStackedHeader ? .top : .center, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            if usesStackedHeader {
                VStack(alignment: .leading, spacing: 1) {
                    titleText
                    summaryText(summary, lineLimit: 2)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    titleText
                    summaryText(summary, lineLimit: 1)
                }
            }

            Spacer(minLength: 6)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var titleText: some View {
        Text("Thinking")
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private func summaryText(_ value: String, lineLimit: Int) -> some View {
        Text(value)
            .font(AppFont.caption())
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
    }

    private var trimmedText: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func summary(for value: String) -> String {
        let oneLine = markdownStrippedPreviewText(from: value)

        if oneLine.count <= 80 {
            return oneLine
        }

        return "\(oneLine.prefix(80))..."
    }

    /// The expanded thinking card can render markdown, but the collapsed header
    /// is a compact one-line preview. Render markdown to plain text there so the
    /// snippet reads like prose instead of showing raw markers such as `**`.
    private func markdownStrippedPreviewText(from value: String) -> String {
        let plainText = (try? AttributedString(markdown: value)).map { String($0.characters) } ?? value

        return plainText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ReasoningMarkdownDetailsView: View {
    let text: String

    var body: some View {
        MarkdownRenderer(content: text, isStreaming: false)
    }
}
