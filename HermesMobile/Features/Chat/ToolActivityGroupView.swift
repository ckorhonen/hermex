import SwiftUI

struct ToolActivityGroupView: View {
    let group: ToolCallGroup
    /// Stable identity for the expand toggle in the session-scoped store; nil
    /// falls back to view-local state (previews, unkeyed call sites).
    var expansionKey: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.chatTranscriptFontScale) private var chatFontScale
    @Environment(\.transcriptCardExpansionStore) private var expansionStore
    // Dynamic Type first, then the chat font-size preference — mirrors the
    // message bubbles so the card chrome tracks the transcript text.
    @ScaledMetric(relativeTo: .caption) private var scaledCaptionPointSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var scaledIconPointSize: CGFloat = 14
    @AppStorage(ChatTranscriptDisplaySettings.toolCardsStartExpandedKey) private var startsExpanded = false
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


    private func cardFontSize(_ base: CGFloat) -> CGFloat {
        base * CGFloat(ChatTranscriptDisplaySettings.clampedFontScale(chatFontScale))
    }

    private var isExpanded: Bool {
        ChatTranscriptDisplaySettings.isCardExpanded(
            userToggled: userToggledExpansion,
            startsExpanded: startsExpanded
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
            Button {
                withAnimation(ChatMotion.disclosure(reduceMotion: reduceMotion)) {
                    setUserToggledExpansion(!isExpanded)
                }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityLabel(activityAccessibilityLabel)
            .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(group.toolCalls) { toolCall in
                        ToolCallCardView(toolCall: toolCall)
                    }
                }
                .transition(ChatMotion.disclosureTransition(reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .chatTimelineAccessorySurface()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var usesStackedHeader: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var header: some View {
        HStack(alignment: usesStackedHeader ? .top : .center, spacing: 8) {
            Image(systemName: activityIcon)
                .font(.system(size: cardFontSize(scaledIconPointSize), weight: .semibold))
                .foregroundStyle(activityColor)
                .frame(width: 18, height: 18)

            if usesStackedHeader {
                VStack(alignment: .leading, spacing: 3) {
                    titleText
                    summaryTextView(lineLimit: 2)
                    if let collapsedStateText {
                        TranscriptStatusPill(text: collapsedStateText, color: activityColor)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    titleText
                    summaryTextView(lineLimit: 1)
                    if let collapsedStateText {
                        TranscriptStatusPill(text: collapsedStateText, color: activityColor)
                    }
                }
            }

            Spacer(minLength: 6)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: cardFontSize(scaledCaptionPointSize), weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var titleText: some View {
        Text(group.activityTitle)
            .font(.system(size: cardFontSize(scaledCaptionPointSize), weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private func summaryTextView(lineLimit: Int) -> some View {
        Text(summaryText)
            .font(.system(size: cardFontSize(scaledCaptionPointSize)))
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
    }

    private var activityIcon: String {
        if group.hasFailedTool {
            return "exclamationmark.triangle.fill"
        }

        return group.isComplete ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill"
    }

    private var activityColor: Color {
        if group.hasFailedTool {
            return .red
        }

        return .secondary
    }

    private var collapsedStateText: String? {
        if group.hasFailedTool {
            return String(localized: "Failed")
        }

        return group.isComplete ? nil : String(localized: "Running")
    }

    private var activityAccessibilityLabel: String {
        "\(group.activityTitle), \(activityStateText), \(summaryText)"
    }

    private var activityStateText: String {
        if group.hasFailedTool {
            return String(localized: "Failed")
        }

        return group.isComplete ? String(localized: "Completed") : String(localized: "Running")
    }

    private var summaryText: String {
        let names = group.toolCalls.map(\.displayName)
        let uniqueNames = names.reduce(into: [String]()) { result, name in
            if !result.contains(name) {
                result.append(name)
            }
        }

        guard !uniqueNames.isEmpty else {
            return String(localized: "No tools")
        }

        let visibleNames = uniqueNames.prefix(3)
        let remainingCount = uniqueNames.count - visibleNames.count
        let visibleSummary = visibleNames.joined(separator: ", ")

        guard remainingCount > 0 else {
            return visibleSummary
        }

        return "\(visibleSummary), +\(remainingCount)"
    }
}
