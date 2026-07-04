import XCTest
@testable import HermesMobile

final class StreamingMarkdownBlockSplitterTests: XCTestCase {
    func testShortTextStaysInActiveMarkdown() {
        let text = "Hello from Hermes."
        let segments = StreamingMarkdownBlockSplitter.split(text)

        XCTAssertTrue(segments.stableChunks.isEmpty)
        XCTAssertEqual(segments.activeMarkdown, text)
    }

    func testCompletedFenceSealsStableChunk() {
        let stableBody = String(repeating: "A", count: 6_100)
        let text = """
        \(stableBody)
        ```swift
        let answer = 42
        ```
        Still streaming
        """

        let segments = StreamingMarkdownBlockSplitter.split(text)

        XCTAssertEqual(segments.stableChunks.count, 1)
        XCTAssertTrue(segments.stableChunks[0].text.contains(stableBody))
        XCTAssertTrue(segments.activeMarkdown.contains("Still streaming"))
    }

    func testHeadingBoundaryCanSealWithoutFence() {
        let prose = String(repeating: "Line of prose.\n", count: 500)
        let text = prose + "## Next section\nMore text"

        let segments = StreamingMarkdownBlockSplitter.split(text)

        XCTAssertFalse(segments.stableChunks.isEmpty)
        XCTAssertTrue(segments.activeMarkdown.contains("More text"))
    }

    func testTabSeparatedHeadingCountsAsStableBoundary() {
        let prose = String(repeating: "Line of prose.\n", count: 500)
        let text = prose + "##\tTab heading\nMore text"

        let segments = StreamingMarkdownBlockSplitter.split(text)

        XCTAssertFalse(segments.stableChunks.isEmpty)
        XCTAssertTrue(segments.activeMarkdown.contains("More text"))
    }
}

/// The streaming renderer memoizes its full-content scans (block split, math
/// segmentation) per distinct content value. These tests prove the memo is
/// transparent: for representative streaming sequences it returns results
/// identical to a fresh computation, and it only recomputes on new content.
final class StreamingContentMemoTests: XCTestCase {
    func testMemoizedBlockSplitMatchesFreshComputationAcrossAppendOnlyStream() {
        // Capacity 2 mirrors the renderer's cache, which must serve both the
        // old and new content compared in advanceFadeWindow. The chunks walk
        // through paragraph growth, a heading boundary, list items, and a
        // fence opening then closing mid-stream.
        let memo = StreamingContentMemo(capacity: 2) { StreamingMarkdownBlockSplitter.split($0) }
        let chunks = [
            "Intro paragraph",
            " keeps growing.\n\n",
            "## Section heading\n",
            "- item one\n- item",
            " two\n\n```swift\nlet x",
            " = 1\n```\n",
            "Tail prose after the closed fence"
        ]

        var content = ""
        for chunk in chunks {
            content += chunk
            let fresh = StreamingMarkdownBlockSplitter.split(content)
            XCTAssertEqual(memo.value(for: content), fresh)
            // Repeated body-style evaluations of the same content stay
            // identical (served from cache, not recomputed differently).
            XCTAssertEqual(memo.value(for: content), fresh)
        }
    }

    func testMemoizedBlockSplitServesOldAndNewContentOfAFlush() {
        let memo = StreamingContentMemo(capacity: 2) { StreamingMarkdownBlockSplitter.split($0) }
        let old = "First paragraph.\n\nSecond paragraph still stre"
        let new = old + "aming\n\nThird begins"

        // Body pass for the old content, then an onChange comparing old/new,
        // then the body pass for the new content — the renderer's sequence.
        XCTAssertEqual(memo.value(for: old), StreamingMarkdownBlockSplitter.split(old))
        XCTAssertEqual(memo.value(for: old).activeMarkdown, StreamingMarkdownBlockSplitter.split(old).activeMarkdown)
        XCTAssertEqual(memo.value(for: new), StreamingMarkdownBlockSplitter.split(new))
        XCTAssertEqual(memo.value(for: old), StreamingMarkdownBlockSplitter.split(old))
        XCTAssertEqual(memo.value(for: new), StreamingMarkdownBlockSplitter.split(new))
    }

    func testMemoComputesOncePerDistinctContentAndEvictsBeyondCapacity() {
        var computeCount = 0
        let memo = StreamingContentMemo(capacity: 2) { (content: String) -> Int in
            computeCount += 1
            return content.count
        }

        XCTAssertEqual(memo.value(for: "a"), 1)
        XCTAssertEqual(memo.value(for: "a"), 1)
        XCTAssertEqual(computeCount, 1, "repeat lookups must not recompute")

        XCTAssertEqual(memo.value(for: "ab"), 2)
        XCTAssertEqual(memo.value(for: "a"), 1)
        XCTAssertEqual(computeCount, 2, "capacity 2 keeps both recent values")

        // A third distinct value evicts the least recently used ("ab").
        XCTAssertEqual(memo.value(for: "abc"), 3)
        XCTAssertEqual(computeCount, 3)
        XCTAssertEqual(memo.value(for: "ab"), 2)
        XCTAssertEqual(computeCount, 4, "evicted values are recomputed correctly")
    }

    func testMemoCapacityOneKeepsOnlyLatestValue() {
        var computeCount = 0
        let memo = StreamingContentMemo { (content: String) -> Int in
            computeCount += 1
            return content.count
        }

        XCTAssertEqual(memo.value(for: "x"), 1)
        XCTAssertEqual(memo.value(for: "x"), 1)
        XCTAssertEqual(computeCount, 1)
        XCTAssertEqual(memo.value(for: "xy"), 2)
        XCTAssertEqual(memo.value(for: "x"), 1)
        XCTAssertEqual(computeCount, 3, "capacity 1 recomputes after content changes")
    }
}

/// Width resolution for chat markdown table cells (issue #233). The layout
/// itself needs a render pass to verify; this covers the pure clamp that
/// decides the wrap width the cell height is measured at.
final class TableCellWidthCapTests: XCTestCase {
    private let minWidth: CGFloat = 96
    private let maxWidth: CGFloat = 260

    func testIdealWidthBelowMinClampsToMin() {
        let width = TableCellWidthCap.resolvedWidth(
            idealWidth: 40, proposedWidth: nil, minWidth: minWidth, maxWidth: maxWidth
        )
        XCTAssertEqual(width, minWidth)
    }

    func testIdealWidthWithinBoundsIsUsedAsIs() {
        let width = TableCellWidthCap.resolvedWidth(
            idealWidth: 150, proposedWidth: nil, minWidth: minWidth, maxWidth: maxWidth
        )
        XCTAssertEqual(width, 150)
    }

    func testIdealWidthAboveMaxClampsToMax() {
        let width = TableCellWidthCap.resolvedWidth(
            idealWidth: 1_200, proposedWidth: nil, minWidth: minWidth, maxWidth: maxWidth
        )
        XCTAssertEqual(width, maxWidth)
    }

    func testProposedColumnWidthOverridesIdealWidth() {
        let width = TableCellWidthCap.resolvedWidth(
            idealWidth: 40, proposedWidth: 200, minWidth: minWidth, maxWidth: maxWidth
        )
        XCTAssertEqual(width, 200)
    }

    func testProposedColumnWidthIsStillClamped() {
        let width = TableCellWidthCap.resolvedWidth(
            idealWidth: 40, proposedWidth: 999, minWidth: minWidth, maxWidth: maxWidth
        )
        XCTAssertEqual(width, maxWidth)
    }
}
