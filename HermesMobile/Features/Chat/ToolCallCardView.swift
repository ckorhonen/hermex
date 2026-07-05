import SwiftUI

struct ToolCallCardView: View {
    let toolCall: ToolCall
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.chatTranscriptFontScale) private var chatFontScale
    @AppStorage(ChatTranscriptDisplaySettings.toolCardsStartExpandedKey) private var startsExpanded = false
    // Dynamic Type first, then the chat font-size preference — mirrors the
    // message bubbles so the card chrome tracks the transcript text.
    @ScaledMetric(relativeTo: .caption) private var scaledCaptionPointSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var scaledCaption2PointSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var scaledIconPointSize: CGFloat = 14
    @State private var userToggledExpansion: Bool?


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
        let statusDisplay = ToolCallStatusDisplay(toolCall: toolCall)

        VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
            Button {
                withAnimation(ChatMotion.disclosure(reduceMotion: reduceMotion)) {
                    userToggledExpansion = !isExpanded
                }
            } label: {
                header(statusDisplay: statusDisplay)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "\(toolCall.displayName), \(statusDisplay.detailText)"))
            .accessibilityHint(isExpanded ? "Double tap to collapse details." : "Double tap to expand details.")

            if isExpanded {
                expandedContent(statusDisplay: statusDisplay)
                    .transition(ChatMotion.disclosureTransition(reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, isExpanded ? 8 : 7)
        .chatTimelineAccessorySurface()
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tool-call bodies are commands, JSON, file paths, and results — code-like
        // content that must stay left-to-right inside an RTL message (#259). The
        // group's summary header above (ToolActivityGroupView) still mirrors.
        .forcedLeftToRight()
    }

    private func expandedContent(statusDisplay: ToolCallStatusDisplay) -> some View {
        let displayContent = ToolCallDisplayFormatter.content(for: toolCall)

        return VStack(alignment: .leading, spacing: 7) {
            if !displayContent.argumentRows.isEmpty {
                argumentsSection(displayContent.argumentRows)
            }

            if let result = displayContent.result {
                resultSection(result)
            }

            if shouldShowStatusDetail(displayContent: displayContent) {
                statusDetail(statusDisplay.detailText)
            }
        }
    }

    private var usesStackedHeader: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private func header(statusDisplay: ToolCallStatusDisplay) -> some View {
        HStack(alignment: usesStackedHeader ? .top : .center, spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: cardFontSize(scaledIconPointSize), weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 18, height: 18)

            if usesStackedHeader {
                VStack(alignment: .leading, spacing: 3) {
                    titleText
                    if let collapsedText = statusDisplay.collapsedText {
                        TranscriptStatusPill(text: collapsedText, color: statusColor)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    titleText
                    if let collapsedText = statusDisplay.collapsedText {
                        TranscriptStatusPill(text: collapsedText, color: statusColor)
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
        Text(toolCall.displayName)
            .font(.system(size: cardFontSize(scaledCaptionPointSize), weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var statusIcon: String {
        if toolCall.isError == true {
            return "exclamationmark.triangle.fill"
        }

        return toolCall.isCompleted ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill"
    }

    private var statusColor: Color {
        if toolCall.isError == true {
            return .red
        }

        return .secondary
    }

    private func shouldShowStatusDetail(displayContent: ToolCallDisplayContent) -> Bool {
        let hasPrimaryContent = !displayContent.argumentRows.isEmpty || displayContent.result != nil
        return !hasPrimaryContent || !toolCall.isCompleted || toolCall.isError == true || toolCall.duration != nil
    }

    private func statusDetail(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Status")
                .font(.system(size: cardFontSize(scaledCaption2PointSize), weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: cardFontSize(scaledCaptionPointSize)))
                .foregroundStyle(statusColor)
                .textSelection(.enabled)
        }
    }

    private func argumentsSection(_ rows: [ToolCallArgumentDisplay]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Arguments")
                .font(.system(size: cardFontSize(scaledCaption2PointSize), weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    argumentRow(row)
                }
            }
            .padding(7)
            .chatTimelineAccessoryInsetSurface()
        }
    }

    private func resultSection(_ result: ToolCallResultDisplay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.title)
                .font(.system(size: cardFontSize(scaledCaption2PointSize), weight: .semibold))
                .foregroundStyle(.secondary)

            Text(result.text)
                .font(result.isMonospaced ? AppFont.mono(size: cardFontSize(scaledCaptionPointSize)) : .system(size: cardFontSize(scaledCaptionPointSize)))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .chatTimelineAccessoryInsetSurface()
        }
    }

    @ViewBuilder
    private func argumentRow(_ row: ToolCallArgumentDisplay) -> some View {
        if usesStackedHeader {
            VStack(alignment: .leading, spacing: 2) {
                argumentKey(row.key)
                argumentValue(row.value)
            }
        } else {
            HStack(alignment: .top, spacing: 7) {
                argumentKey(row.key)
                    .frame(width: 78, alignment: .leading)

                argumentValue(row.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func argumentKey(_ value: String) -> some View {
        Text(value)
            .font(AppFont.mono(size: cardFontSize(scaledCaption2PointSize), weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func argumentValue(_ value: String) -> some View {
        Text(value)
            .font(AppFont.mono(size: cardFontSize(scaledCaptionPointSize)))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }
}

struct ToolCallStatusDisplay: Equatable {
    let collapsedText: String?
    let detailText: String

    init(toolCall: ToolCall) {
        if toolCall.isError == true {
            collapsedText = String(localized: "Failed")
            detailText = String(localized: "Failed")
            return
        }

        if toolCall.isCompleted {
            collapsedText = nil
            if let duration = toolCall.duration {
                detailText = "Completed in \(duration.formatted(.number.precision(.fractionLength(1))))s"
            } else {
                detailText = String(localized: "Completed")
            }
            return
        }

        collapsedText = String(localized: "Running")
        detailText = String(localized: "Running")
    }
}

struct TranscriptStatusPill: View {
    let text: String
    let color: Color

    @Environment(\.chatTranscriptFontScale) private var chatFontScale
    @ScaledMetric(relativeTo: .caption2) private var scaledCaption2PointSize: CGFloat = 11

    private func cardFontSize(_ base: CGFloat) -> CGFloat {
        base * CGFloat(ChatTranscriptDisplaySettings.clampedFontScale(chatFontScale))
    }

    var body: some View {
        Text(text)
            .font(.system(size: cardFontSize(scaledCaption2PointSize), weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
