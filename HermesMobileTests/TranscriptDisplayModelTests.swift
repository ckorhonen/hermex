import XCTest
import AVFoundation
import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers
@testable import HermesMobile

final class TranscriptMessageTests: XCTestCase {
    func testTranscriptMessagesHideToolRowsAndPreserveLoadedIndices() {
        let messages = [
            ChatMessage(role: "user", content: "Plan it", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Working on it", timestamp: 2, messageId: "a1"),
            ChatMessage(
                role: "tool",
                content: #"{"success":true,"diff":"..."}"#,
                timestamp: 3,
                messageId: "t1",
                toolCallId: "tool-1"
            ),
            ChatMessage(role: "assistant", content: "Done. Here's what changed.", timestamp: 4, messageId: "a2")
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(from: messages)

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 1, 3])
        XCTAssertEqual(transcriptMessages.map(\.message.id), ["u1", "a1", "a2"])
    }

    func testTranscriptMessagesCanHideActiveStreamingAssistantTurn() {
        let messages = [
            ChatMessage(role: "user", content: "Use tools", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: "stream-1"),
            ChatMessage(
                role: "tool",
                content: #"{"success":true}"#,
                timestamp: 3,
                messageId: "t1",
                toolCallId: "tool-1"
            ),
            ChatMessage(role: "assistant", content: "Older answer", timestamp: 4, messageId: "a2")
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(
            from: messages,
            hidingStreamingAssistantID: "stream-1"
        )

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 3])
        XCTAssertEqual(transcriptMessages.map(\.message.id), ["u1", "a2"])
    }

    func testTranscriptMessagesCanHideActiveStreamingAssistantFallbackAnchor() {
        let messages = [
            ChatMessage(role: "user", content: "Use tools", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: nil),
            ChatMessage(role: "assistant", content: "Older answer", timestamp: 3, messageId: nil)
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(
            from: messages,
            messageOffset: 20,
            hidingStreamingAssistantID: "raw:21"
        )

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 2])
        XCTAssertEqual(transcriptMessages.map(\.anchorID), ["raw:20", "raw:22"])
    }

    func testTranscriptMessagesKeepStreamingAssistantAnchorStableAcrossContentUpdates() {
        let initialMessages = [
            ChatMessage(role: "user", content: "Write a long answer", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: "stream-1")
        ]
        let updatedMessages = [
            ChatMessage(role: "user", content: "Write a long answer", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "First streamed token.", timestamp: 2, messageId: "stream-1")
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(from: initialMessages)
        let updatedTranscriptMessages = ChatViewModel.transcriptMessages(from: updatedMessages)

        XCTAssertEqual(initialTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(updatedTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(initialTranscriptMessages.map(\.id), updatedTranscriptMessages.map(\.id))
        XCTAssertEqual(initialTranscriptMessages.map(\.loadedIndex), updatedTranscriptMessages.map(\.loadedIndex))
    }

    func testTranscriptMessagesKeepRenderIDStableWhenServerReplacesStreamingAssistantID() {
        let streamingMessages = [
            ChatMessage(role: "user", content: "Finish the summary", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Working summary", timestamp: 2, messageId: "stream-1")
        ]
        let completedMessages = [
            ChatMessage(role: "user", content: "Finish the summary", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Final summary", timestamp: 2, messageId: "assistant-1")
        ]

        let streamingTranscriptMessages = ChatViewModel.transcriptMessages(from: streamingMessages)
        let completedTranscriptMessages = ChatViewModel.transcriptMessages(from: completedMessages)

        XCTAssertEqual(streamingTranscriptMessages.map(\.id), completedTranscriptMessages.map(\.id))
        XCTAssertEqual(streamingTranscriptMessages.map(\.anchorID), ["u1", "stream-1"])
        XCTAssertEqual(completedTranscriptMessages.map(\.anchorID), ["u1", "assistant-1"])
    }

    /// The bubble's `.id()` scopes the streaming fade/linger view state. If it
    /// changes when the server replaces the placeholder `stream-*` id with the
    /// final message id, the bubble remounts mid-animation and the text snaps.
    func testTranscriptMessagesKeepBubbleStateIDStableWhenServerReplacesStreamingAssistantID() {
        let streamingMessages = [
            ChatMessage(role: "user", content: "Finish the summary", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Working summary", timestamp: 2, messageId: "stream-1")
        ]
        let completedMessages = [
            ChatMessage(role: "user", content: "Finish the summary", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Final summary", timestamp: 2, messageId: "assistant-1")
        ]

        let streamingTranscriptMessages = ChatViewModel.transcriptMessages(from: streamingMessages)
        let completedTranscriptMessages = ChatViewModel.transcriptMessages(from: completedMessages)

        XCTAssertEqual(
            streamingTranscriptMessages.map(\.bubbleStateID),
            completedTranscriptMessages.map(\.bubbleStateID),
            "Bubble-local state identity must survive the streaming placeholder → final message swap"
        )
    }

    func testTranscriptMessagesUseRawAnchorForNilMessageIDsIndependentOfContent() {
        let initialMessages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "", timestamp: 2, messageId: nil)
        ]
        let updatedMessages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "A streamed response.", timestamp: 2, messageId: nil)
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(
            from: initialMessages,
            messageOffset: 10
        )
        let updatedTranscriptMessages = ChatViewModel.transcriptMessages(
            from: updatedMessages,
            messageOffset: 10
        )

        XCTAssertEqual(initialTranscriptMessages.map(\.anchorID), ["raw:10", "raw:11"])
        XCTAssertEqual(updatedTranscriptMessages.map(\.anchorID), ["raw:10", "raw:11"])
        XCTAssertEqual(initialTranscriptMessages.map(\.id), updatedTranscriptMessages.map(\.id))
    }

    func testTranscriptMessagesKeepRenderIDsStableWhenOlderMessagesPrepend() {
        let initialWindow = [
            ChatMessage(role: "assistant", content: "Earlier answer", timestamp: 1, messageId: "a1"),
            ChatMessage(role: "user", content: "Follow up", timestamp: 2, messageId: "u2"),
            ChatMessage(role: "assistant", content: "Latest answer", timestamp: 3, messageId: "a2")
        ]
        let expandedWindow = [
            ChatMessage(role: "user", content: "First question", timestamp: 0, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Earlier answer", timestamp: 1, messageId: "a1"),
            ChatMessage(role: "user", content: "Follow up", timestamp: 2, messageId: "u2"),
            ChatMessage(role: "assistant", content: "Latest answer", timestamp: 3, messageId: "a2")
        ]

        let initialTranscriptMessages = ChatViewModel.transcriptMessages(
            from: initialWindow,
            messageOffset: 1
        )
        let expandedTranscriptMessages = ChatViewModel.transcriptMessages(
            from: expandedWindow,
            messageOffset: 0
        )

        XCTAssertEqual(initialTranscriptMessages.map(\.id), ["transcript:1", "transcript:2", "transcript:3"])
        XCTAssertEqual(expandedTranscriptMessages.map(\.id), ["transcript:0", "transcript:1", "transcript:2", "transcript:3"])

        let initialRenderIDsByMessageID = Dictionary(
            uniqueKeysWithValues: initialTranscriptMessages.compactMap { transcriptMessage in
                transcriptMessage.message.messageId.map { ($0, transcriptMessage.id) }
            }
        )
        for expandedTranscriptMessage in expandedTranscriptMessages {
            guard let messageID = expandedTranscriptMessage.message.messageId,
                  let initialRenderID = initialRenderIDsByMessageID[messageID]
            else { continue }

            XCTAssertEqual(
                expandedTranscriptMessage.id,
                initialRenderID,
                "renderID should stay stable for message \(messageID)"
            )
        }
    }

    func testTranscriptMessagesPreserveMessagesWithNilMessageIDsWhenNoStreamingTurnHidden() {
        let messages = [
            ChatMessage(role: "user", content: "Hello", timestamp: 1, messageId: nil),
            ChatMessage(role: "assistant", content: "Hi", timestamp: 2, messageId: nil),
            ChatMessage(
                role: "tool",
                content: #"{"success":true}"#,
                timestamp: 3,
                messageId: nil,
                toolCallId: "tool-1"
            )
        ]

        let transcriptMessages = ChatViewModel.transcriptMessages(from: messages)

        XCTAssertEqual(transcriptMessages.map(\.loadedIndex), [0, 1])
        XCTAssertEqual(transcriptMessages.map(\.message.role), ["user", "assistant"])
    }
}

final class ChatTranscriptDisplaySettingsTests: XCTestCase {
    func testUserBubbleExpansionControlAppearsOnlyAfterCollapsedLineLimit() {
        let tenLineMessage = Array(repeating: "line", count: MessageBubbleView.collapsedUserBubbleLineLimit)
            .joined(separator: "\n")
        let elevenLineMessage = Array(repeating: "line", count: MessageBubbleView.collapsedUserBubbleLineLimit + 1)
            .joined(separator: "\n")

        XCTAssertFalse(MessageBubbleView.userBubbleNeedsExpansionControl(tenLineMessage))
        XCTAssertTrue(MessageBubbleView.userBubbleNeedsExpansionControl(elevenLineMessage))
    }

    func testUserBubbleExpansionControlAppearsForLongWrappedParagraphs() {
        let longParagraph = String(repeating: "word ", count: 160)

        XCTAssertTrue(MessageBubbleView.userBubbleNeedsExpansionControl(longParagraph))
    }

    func testTypingIndicatorStaysHiddenBehindVisibleThinkingAndToolCards() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: false,
            showsThinkingAndToolCards: true
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: true
        ))
    }

    func testTypingIndicatorShowsWhenHiddenCardsAreOnlyLiveActivity() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: false
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: true,
            liveReasoningText: "Inspecting files",
            hasLiveToolCalls: true,
            showsThinkingAndToolCards: false
        ))
    }

    func testTypingIndicatorHidesBehindPendingClarificationPrompt() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldShowAssistantTypingIndicator(
            hasActiveStream: true,
            isCancellingStream: false,
            hasStreamingAssistantMessage: false,
            hasPendingClarificationPrompt: true,
            liveReasoningText: "",
            hasLiveToolCalls: false,
            showsThinkingAndToolCards: false
        ))
    }

    func testStreamingBubbleRenderingRequiresAnActiveAssistantAnchor() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "user",
            messageAnchorID: nil,
            streamingAssistantMessageID: nil
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageAnchorID: nil,
            streamingAssistantMessageID: nil
        ))
    }

    func testStreamingBubbleRenderingMatchesActiveStreamingAssistant() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageAnchorID: "stream-1",
            streamingAssistantMessageID: "stream-1"
        ))

        XCTAssertTrue(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageAnchorID: "raw:42",
            streamingAssistantMessageID: "raw:42"
        ))

        XCTAssertFalse(ChatTranscriptDisplaySettings.shouldUseStreamingBubbleRendering(
            hasActiveStream: true,
            messageRole: "assistant",
            messageAnchorID: "assistant-1",
            streamingAssistantMessageID: "stream-1"
        ))
    }

    func testCardExpansionFollowsStartExpandedPreferenceUntilToggled() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: nil, startsExpanded: false))
        XCTAssertTrue(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: nil, startsExpanded: true))
    }

    func testCardExpansionTapOverrideWinsOverPreference() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: true, startsExpanded: false))
        XCTAssertFalse(ChatTranscriptDisplaySettings.isCardExpanded(userToggled: false, startsExpanded: true))
    }

    func testCardStartExpandedKeysAreStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey,
            "chatTranscript.thinkingCardsStartExpanded"
        )
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.toolCardsStartExpandedKey,
            "chatTranscript.toolCardsStartExpanded"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.thinkingCardsStartExpandedKey,
            ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey
        )
    }

    func testHidesAttachmentPathsKeyIsStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey,
            "chatTranscript.hidesAttachmentPaths"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey,
            ChatTranscriptDisplaySettings.showsThinkingAndToolCardsKey
        )
    }

    func testAssistantTurnTimestampsKeyIsStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey,
            "chatTranscript.showsAssistantTurnTimestamps"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey,
            ChatTranscriptDisplaySettings.hidesAttachmentPathsKey
        )
    }

    func testFontScaleKeyIsStableAndDistinct() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.fontScaleKey,
            "chatTranscript.fontScale"
        )
        XCTAssertNotEqual(
            ChatTranscriptDisplaySettings.fontScaleKey,
            ChatTranscriptDisplaySettings.showsAssistantTurnTimestampsKey
        )
    }

    func testFontScaleClampKeepsSliderAndShortcutsInSupportedRange() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.clampedFontScale(0.25),
            ChatTranscriptDisplaySettings.minimumFontScale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.clampedFontScale(2.0),
            ChatTranscriptDisplaySettings.maximumFontScale,
            accuracy: 0.001
        )
    }

    func testFormattedFontScaleUsesClampedPercentage() {
        XCTAssertEqual(ChatTranscriptDisplaySettings.formattedFontScale(1.0), "100%")
        XCTAssertEqual(ChatTranscriptDisplaySettings.formattedFontScale(1.2), "120%")
        XCTAssertEqual(ChatTranscriptDisplaySettings.formattedFontScale(2.0), "135%")
    }

    func testFontScaleShortcutAdjustmentsSnapAndClamp() {
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.increasedFontScale(from: 0.99),
            1.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.decreasedFontScale(from: 1.01),
            1.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.increasedFontScale(from: ChatTranscriptDisplaySettings.maximumFontScale),
            ChatTranscriptDisplaySettings.maximumFontScale,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ChatTranscriptDisplaySettings.decreasedFontScale(from: ChatTranscriptDisplaySettings.minimumFontScale),
            ChatTranscriptDisplaySettings.minimumFontScale,
            accuracy: 0.001
        )
    }

    func testAssistantTurnHeaderShowsForAssistantTextTurnWhenEnabled() {
        XCTAssertTrue(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: true
        ))
    }

    func testAssistantTurnHeaderHiddenWhenToggleOff() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: true,
            isEnabled: false
        ))
    }

    func testAssistantTurnHeaderHiddenForEmptyOrToolOnlyAssistantRow() {
        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: "assistant",
            hasTextContent: false,
            isEnabled: true
        ))
    }

    func testAssistantTurnHeaderHiddenForNonAssistantRoles() {
        for role in ["user", "system", "tool", "local_assistant", "local_notice"] {
            XCTAssertFalse(
                ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
                    role: role,
                    hasTextContent: true,
                    isEnabled: true
                ),
                "Header must not render for role \(role)"
            )
        }

        XCTAssertFalse(ChatTranscriptDisplaySettings.showsAssistantTurnHeader(
            role: nil,
            hasTextContent: true,
            isEnabled: true
        ))
    }

    func testContentWithoutAttachedFilesMarkerStripsTrailingMarker() {
        // Mirrors the exact format PendingAttachment.chatMessageText appends.
        let sent = "Analyze these files\n\n[Attached files: /tmp/workspace/sample.html, /tmp/workspace/image.jpg]"
        XCTAssertEqual(
            MessageAttachment.contentWithoutAttachedFilesMarker(in: sent),
            "Analyze these files"
        )
    }

    func testContentWithoutAttachedFilesMarkerReturnsEmptyForAttachmentOnlyMessage() {
        // No typed draft: the whole content is just the appended marker.
        let sent = "\n\n[Attached files: /tmp/workspace/image.jpg]"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: sent), "")
    }

    func testContentWithoutAttachedFilesMarkerPreservesInteriorNewlines() {
        let sent = "line one\nline two\n\n[Attached files: /tmp/a.png]"
        XCTAssertEqual(
            MessageAttachment.contentWithoutAttachedFilesMarker(in: sent),
            "line one\nline two"
        )
    }

    func testContentWithoutAttachedFilesMarkerLeavesPlainMessageUnchanged() {
        let plain = "Just a normal message with no attachments"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: plain), plain)
    }

    func testContentWithoutAttachedFilesMarkerIgnoresMarkerWithTrailingText() {
        // The parser only treats the marker as a suffix; trailing prose means it
        // is not a real attachment marker, so the content is left untouched.
        let content = "hello\n\n[Attached files: /tmp/a.png] and then more text"
        XCTAssertEqual(MessageAttachment.contentWithoutAttachedFilesMarker(in: content), content)
    }

    @MainActor
    func testReasoningDetailsUseMarkdownRenderer() {
        let view = ReasoningMarkdownDetailsView(
            text: "**Inspecting** `Markdown` inside thinking details."
        )

        XCTAssertTrue(
            String(describing: type(of: view.body)).contains("MarkdownRenderer"),
            "Thinking details must render through MarkdownRenderer instead of plain Text so Markdown syntax is formatted."
        )
    }
}

final class ChatActiveRunStatusPolicyTests: XCTestCase {
    func testStatusHidesWhenTranscriptBottomIsVisible() {
        XCTAssertNil(ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: true
        ))
    }

    func testStatusShowsActiveRunWhenScrolledAwayFromBottom() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .active)
        XCTAssertEqual(presentation?.label, "Hermes is working")
    }

    func testStatusShowsStartingBeforeStreamIDExists() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: true,
            hasActiveStream: false,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .starting)
    }

    func testStatusPrioritizesRecoveryStateOverGenericActiveRun() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: true,
            activeStreamRecoveryState: .reconnecting,
            isCancellingStream: false,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .reconnecting)
        XCTAssertEqual(presentation?.accessibilityLabel, "Hermes is reconnecting the response stream")
    }

    func testStatusPrioritizesCancellationOverOtherStates() {
        let presentation = ChatActiveRunStatusPolicy.presentation(
            isStartingChat: true,
            hasActiveStream: true,
            activeStreamRecoveryState: .checking,
            isCancellingStream: true,
            isScrolledNearBottom: false
        )

        XCTAssertEqual(presentation?.kind, .stopping)
    }

    func testStatusHidesWhenIdleAndNoRunIsStarting() {
        XCTAssertNil(ChatActiveRunStatusPolicy.presentation(
            isStartingChat: false,
            hasActiveStream: false,
            activeStreamRecoveryState: .idle,
            isCancellingStream: false,
            isScrolledNearBottom: false
        ))
    }
}

final class AssistantTurnTimestampFormatterTests: XCTestCase {
    // 2021-01-01 14:14:00 UTC
    private let fixedTimestamp: Double = 1_609_510_440
    private let utc = TimeZone(identifier: "UTC")!

    func testFormatsTwelveHourLocaleAsShortTime() {
        let result = AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: fixedTimestamp,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("2:14") == true, "Expected 12h time, got \(result ?? "nil")")
        XCTAssertTrue(result?.contains("PM") == true, "Expected PM marker, got \(result ?? "nil")")
    }

    func testFormatsTwentyFourHourLocaleAsShortTime() {
        let result = AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: fixedTimestamp,
            locale: Locale(identifier: "en_GB"),
            timeZone: utc
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("14:14") == true, "Expected 24h time, got \(result ?? "nil")")
        XCTAssertFalse(result?.contains("PM") == true, "24h time must not carry a PM marker")
    }

    func testReturnsNilForNilTimestamp() {
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: nil))
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(
            forUnixTimestamp: nil,
            locale: Locale(identifier: "en_US"),
            timeZone: utc
        ))
    }

    func testReturnsNilForNonFiniteTimestamp() {
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: .nan))
        XCTAssertNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: .infinity))
    }

    func testCurrentLocaleOverloadFormatsFiniteTimestamp() {
        XCTAssertNotNil(AssistantTurnTimestampFormatter.shortTime(forUnixTimestamp: fixedTimestamp))
    }
}

final class ChatTranscriptViewPerformanceGuardTests: XCTestCase {
    func testTranscriptUsesLazyStackForLongConversationScrollPerformance() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HermesMobile/Features/Chat/ChatTranscriptView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let sourceLines = source.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        XCTAssertTrue(
            sourceLines.contains("LazyVStack(spacing: transcriptMessageSpacing) {"),
            "The chat transcript should lazily realize message rows so long conversations do not lay out every bubble while scrolling."
        )
        XCTAssertFalse(
            sourceLines.contains("VStack(spacing: transcriptMessageSpacing) {"),
            "A plain VStack eagerly builds every transcript row and regresses long-chat scroll performance."
        )
    }

    /// The follow-scroll cooldown deadline is rewritten on every scroll-metrics
    /// delivery while a drag or deceleration is in flight. Holding it in
    /// `@State Date?` invalidated the whole ChatView body once per scrolled
    /// frame; it must stay in the non-invalidating reference box (it is only
    /// read imperatively, never rendered).
    func testScrollCooldownDeadlineIsNotViewInvalidatingState() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HermesMobile/Features/Chat/ChatView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertNil(
            source.range(
                of: #"@State\s+private\s+var\s+\w*[Cc]ooldown\w*\s*:\s*Date\??"#,
                options: .regularExpression
            ),
            "A per-frame-changing cooldown Date in @State invalidates the whole ChatView body on every scrolled frame."
        )
        XCTAssertTrue(
            source.contains("= ChatScrollCooldownBox()"),
            "The cooldown deadline should live in the ChatScrollCooldownBox reference box so writes during a scroll gesture do not invalidate the body."
        )
    }
}

/// The expand/collapse toggle on reasoning/tool cards must survive the
/// live → archived view transition at turn completion; view-local @State
/// cannot (the live and archived cards are different views), so the toggles
/// live in a session-scoped store keyed by the owning row's stable renderID.
@MainActor
final class TranscriptCardExpansionStoreTests: XCTestCase {
    func testStoreRemembersTogglesPerKey() {
        let store = TranscriptCardExpansionStore()

        XCTAssertNil(store.userToggledExpansion(forKey: "reasoning:transcript:1:0"))

        store.setUserToggledExpansion(true, forKey: "reasoning:transcript:1:0")
        store.setUserToggledExpansion(false, forKey: "tools:transcript:1:0")

        XCTAssertEqual(store.userToggledExpansion(forKey: "reasoning:transcript:1:0"), true)
        XCTAssertEqual(store.userToggledExpansion(forKey: "tools:transcript:1:0"), false)
        XCTAssertNil(store.userToggledExpansion(forKey: "reasoning:transcript:2:0"))
    }

    /// A live card is keyed with the index it will occupy once archived
    /// (archived-count at render time), and the owning row's renderID is
    /// stable across the streaming placeholder → final message swap — so a
    /// mid-stream toggle is found again by the archived card after finalize.
    func testLiveCardKeySurvivesFinalizeSwap() {
        let streamingMessages = [
            ChatMessage(role: "user", content: "Think hard", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Working", timestamp: 2, messageId: "stream-1")
        ]
        let completedMessages = [
            ChatMessage(role: "user", content: "Think hard", timestamp: 1, messageId: "u1"),
            ChatMessage(role: "assistant", content: "Done", timestamp: 2, messageId: "assistant-1")
        ]

        let liveRow = ChatViewModel.transcriptMessages(from: streamingMessages)[1]
        let archivedRow = ChatViewModel.transcriptMessages(from: completedMessages)[1]

        let store = TranscriptCardExpansionStore()
        // Mid-stream: no archived reasoning groups yet, so the live card's index is 0.
        store.setUserToggledExpansion(true, forKey: "reasoning:\(liveRow.renderID):0")

        // After finalize the archived card is the first (index 0) group of the same row.
        XCTAssertEqual(
            store.userToggledExpansion(forKey: "reasoning:\(archivedRow.renderID):0"),
            true,
            "The archived card must find the toggle recorded while the card was live"
        )
    }
}

extension TranscriptCardExpansionStoreTests {
    /// Truncate-and-regrow flows (edit/regenerate//undo//retry) reset the
    /// store so positional keys can't misattribute old toggles to new content.
    func testResetClearsAllToggles() {
        let store = TranscriptCardExpansionStore()
        store.setUserToggledExpansion(true, forKey: "reasoning:transcript:8:0")
        store.setUserToggledExpansion(false, forKey: "tools:loose:0")

        store.reset()

        XCTAssertNil(store.userToggledExpansion(forKey: "reasoning:transcript:8:0"))
        XCTAssertNil(store.userToggledExpansion(forKey: "tools:loose:0"))
    }

    /// A loose (unanchored) live card predicts the index it will occupy once
    /// archived — index 0 when nothing is archived yet — so its key matches
    /// the archived card's "reasoning:loose:0", not a dead "live" literal.
    func testLooseLiveCardKeyMatchesFirstArchivedLooseKey() {
        let store = TranscriptCardExpansionStore()
        store.setUserToggledExpansion(true, forKey: "reasoning:loose:0")

        XCTAssertEqual(store.userToggledExpansion(forKey: "reasoning:loose:0"), true)
        XCTAssertNil(store.userToggledExpansion(forKey: "reasoning:loose:live"))
    }
}

/// Wall-clock measurements for the transcript data hot path (issue #32).
///
/// During streaming, every paced word-drain tick mutates `messages`, which
/// rebuilds `displayedTranscriptMessages` and `displayedReasoningGroups` over
/// the full loaded conversation. These measure blocks quantify one rebuild
/// over a 1,000-message conversation so per-tick cost regressions show up as
/// numbers instead of scroll-feel anecdotes.
final class TranscriptDataHotPathPerformanceTests: XCTestCase {
    private static let thousandMessageConversation: [ChatMessage] = makeConversation(turnCount: 250)

    /// 250 turns × 4 messages (user, assistant+reasoning, tool result, assistant)
    /// = 1,000 loaded messages with realistic content lengths.
    private static func makeConversation(turnCount: Int) -> [ChatMessage] {
        let userText = String(repeating: "Please refactor the session list so it stays in sync. ", count: 4)
        let assistantText = String(repeating: "Here is the plan: extract the sync seam, add tests, then wire the sidebar. ", count: 8)
        let reasoningText = String(repeating: "The sidebar drifts because renames bypass the store. ", count: 6)

        var messages: [ChatMessage] = []
        messages.reserveCapacity(turnCount * 4)
        for turn in 0..<turnCount {
            let base = turn * 4
            messages.append(ChatMessage(
                role: "user", content: userText, timestamp: Double(base), messageId: "user-\(turn)"
            ))
            messages.append(ChatMessage(
                role: "assistant", content: assistantText, timestamp: Double(base + 1),
                messageId: "assistant-\(turn)-a", reasoning: reasoningText
            ))
            messages.append(ChatMessage(
                role: "tool", content: #"{"success":true,"diff":"..."}"#, timestamp: Double(base + 2),
                messageId: "tool-\(turn)", toolCallId: "call-\(turn)"
            ))
            messages.append(ChatMessage(
                role: "assistant", content: assistantText, timestamp: Double(base + 3),
                messageId: "assistant-\(turn)-b"
            ))
        }
        return messages
    }

    func testMeasureTranscriptMessagesRebuildOverThousandMessages() {
        let messages = Self.thousandMessageConversation

        measure {
            for _ in 0..<10 {
                _ = ChatViewModel.transcriptMessages(from: messages, messageOffset: 40)
            }
        }
    }

    func testMeasureReasoningDisplayGroupsRebuildOverThousandMessages() {
        let messages = Self.thousandMessageConversation
        let archived = (0..<50).map { index in
            ReasoningGroup(
                id: "archived-\(index)",
                anchorMessageID: "assistant-\(index)-a",
                text: String(repeating: "Archived reasoning kept across reloads. ", count: 6)
            )
        }

        measure {
            for _ in 0..<10 {
                _ = ChatViewModel.reasoningDisplayGroups(
                    messages: messages,
                    messageOffset: 40,
                    archivedGroups: archived
                )
            }
        }
    }
}
