import XCTest
@testable import HermesMobile

final class ChatMarkerMessageClassifierTests: XCTestCase {
    // MARK: - Context compaction

    func testBracketedCompactionPrefixMatches() {
        let message = makeMessage(role: "user", content: "[Context compaction] Summary of earlier conversation…")
        XCTAssertEqual(ChatMarkerMessageClassifier.classify(message), .contextCompaction)
    }

    func testUnbracketedCompactionPrefixMatches() {
        let message = makeMessage(role: "assistant", content: "Context compaction: the prior history was summarized.")
        XCTAssertEqual(ChatMarkerMessageClassifier.classify(message), .contextCompaction)
    }

    func testCompactionPrefixIsCaseInsensitive() {
        let message = makeMessage(role: "user", content: "[CONTEXT COMPACTION] details")
        XCTAssertEqual(ChatMarkerMessageClassifier.classify(message), .contextCompaction)
    }

    func testCompactionPrefixToleratesLeadingWhitespace() {
        let message = makeMessage(role: "user", content: "  \n\t[context compaction] details")
        XCTAssertEqual(ChatMarkerMessageClassifier.classify(message), .contextCompaction)
    }

    func testPriorContextReferencePrefixMatches() {
        let message = makeMessage(
            role: "assistant",
            content: "[PRIOR CONTEXT — for reference only; not a new message]\nEarlier work summary"
        )
        XCTAssertEqual(ChatMarkerMessageClassifier.classify(message), .contextCompaction)
    }

    func testToolRoleNeverMatches() {
        let message = makeMessage(role: "tool", content: "[context compaction] details")
        XCTAssertNil(ChatMarkerMessageClassifier.classify(message))
    }

    func testMissingRoleNeverMatches() {
        let message = makeMessage(role: nil, content: "[context compaction] details")
        XCTAssertNil(ChatMarkerMessageClassifier.classify(message))
    }

    func testNonMarkerTextStartingWithContextDoesNotMatch() {
        let message = makeMessage(role: "user", content: "Context windows are interesting — explain compaction.")
        XCTAssertNil(ChatMarkerMessageClassifier.classify(message))
    }

    // MARK: - Preserved task list

    func testPreservedTaskListPrefixMatchesForUserRole() {
        let message = makeMessage(
            role: "user",
            content: "[Your active task list was preserved across context compression]\n1. Do the thing"
        )
        XCTAssertEqual(ChatMarkerMessageClassifier.classify(message), .preservedTaskList)
    }

    func testPreservedTaskListPrefixIsCaseInsensitiveAndToleratesWhitespace() {
        let message = makeMessage(
            role: "user",
            content: "   [YOUR ACTIVE TASK LIST WAS PRESERVED ACROSS CONTEXT COMPRESSION] tasks"
        )
        XCTAssertEqual(ChatMarkerMessageClassifier.classify(message), .preservedTaskList)
    }

    func testPreservedTaskListPrefixMatchesForAssistantRole() {
        let message = makeMessage(
            role: "assistant",
            content: "[Your active task list was preserved across context compression] tasks"
        )
        XCTAssertEqual(ChatMarkerMessageClassifier.classify(message), .preservedTaskList)
    }

    func testPreservedTaskListPrefixDoesNotMatchToolRole() {
        let message = makeMessage(
            role: "tool",
            content: "[Your active task list was preserved across context compression] tasks"
        )
        XCTAssertNil(ChatMarkerMessageClassifier.classify(message))
    }

    // MARK: - Plain messages

    func testNormalUserMessageDoesNotMatch() {
        let message = makeMessage(role: "user", content: "Hey, can you check the build?")
        XCTAssertNil(ChatMarkerMessageClassifier.classify(message))
    }

    func testEmptyContentDoesNotMatch() {
        let message = makeMessage(role: "user", content: nil)
        XCTAssertNil(ChatMarkerMessageClassifier.classify(message))
    }

    // MARK: - Card body

    func testCardBodyStripsPreservedTaskListMarker() {
        let body = ChatMarkerMessageClassifier.cardBody(
            for: .preservedTaskList,
            content: "[Your active task list was preserved across context compression]\n1. First task\n2. Second task"
        )
        XCTAssertEqual(body, "1. First task\n2. Second task")
    }

    func testCardBodyKeepsCompactionTextIntact() {
        let body = ChatMarkerMessageClassifier.cardBody(
            for: .contextCompaction,
            content: "  [Context compaction] Summary text  "
        )
        XCTAssertEqual(body, "[Context compaction] Summary text")
    }

    func testPreservedTaskListItemsParseStatusSuffixRows() {
        let items = ChatMarkerMessageClassifier.preservedTaskListItems(in: """
        state. Verify live Hermex git state and isolate unrelated work (in_progress)
        review. Run autoreview/security scan on the response notification copy diff (pending)
        done. Upload build to TestFlight (completed)
        """)

        XCTAssertEqual(items, [
            PreservedTaskListItem(
                id: "state",
                title: "Verify live Hermex git state and isolate unrelated work",
                state: .active
            ),
            PreservedTaskListItem(
                id: "review",
                title: "Run autoreview/security scan on the response notification copy diff",
                state: .unchecked
            ),
            PreservedTaskListItem(
                id: "done",
                title: "Upload build to TestFlight",
                state: .checked
            )
        ])
    }

    func testPreservedTaskListItemsParseMarkdownCheckboxRows() {
        let items = ChatMarkerMessageClassifier.preservedTaskListItems(in: """
        - [x] Completed task
        - [ ] Pending task
        """)

        XCTAssertEqual(items.map(\.title), ["Completed task", "Pending task"])
        XCTAssertEqual(items.map(\.state), [.checked, .unchecked])
    }

    func testPreservedTaskListItemsIgnorePlainLines() {
        let items = ChatMarkerMessageClassifier.preservedTaskListItems(in: "Just a normal note")

        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Helpers

    private func makeMessage(role: String?, content: String?) -> ChatMessage {
        ChatMessage(role: role, content: content, timestamp: nil, messageId: "test-id")
    }
}
