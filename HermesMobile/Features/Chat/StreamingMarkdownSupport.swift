import Foundation

/// Memoizes the most recent results of a pure `(String) -> Value` computation.
///
/// The streaming renderer's SwiftUI bodies re-evaluate far more often than
/// their content changes (fade-clock frames, unrelated state churn), and
/// helpers like `StreamingMarkdownBlockSplitter.split` or
/// `MarkdownMathSegmenter.segments` re-scan the entire accumulated message on
/// every call. Holding one of these boxes in `@State` (the reference is the
/// state; its contents are just a cache) makes repeated evaluations for the
/// same content cost a string comparison instead of a full re-scan, without
/// changing any result: a miss always runs the exact same computation.
///
/// Not thread-safe — intended for a single view's body/update path on the
/// main actor.
final class StreamingContentMemo<Value> {
    private let capacity: Int
    private let compute: (String) -> Value
    /// Most recently used first.
    private var entries: [(content: String, value: Value)] = []

    /// `capacity` is how many distinct content values stay cached; use 2 when
    /// an `onChange(of:)` needs the old and new value of the same computation
    /// (e.g. `advanceFadeWindow`).
    init(capacity: Int = 1, _ compute: @escaping (String) -> Value) {
        self.capacity = max(1, capacity)
        self.compute = compute
    }

    func value(for content: String) -> Value {
        if let index = entries.firstIndex(where: { $0.content == content }) {
            let hit = entries.remove(at: index)
            entries.insert(hit, at: 0)
            return hit.value
        }

        let value = compute(content)
        entries.insert((content, value), at: 0)
        if entries.count > capacity {
            entries.removeLast()
        }
        return value
    }
}

struct StreamingMarkdownChunk: Identifiable, Equatable {
    let id: Int
    let text: String
}

struct StreamingMarkdownBlockSegments: Equatable {
    let stableChunks: [StreamingMarkdownChunk]
    let activeMarkdown: String
}

enum StreamingMarkdownBlockSplitter {
    static let stableChunkTargetCharacterCount = 6_000

    static func split(_ text: String) -> StreamingMarkdownBlockSegments {
        var lineStart = text.startIndex
        var chunkStart = text.startIndex
        var isInsideFence = false
        var stableChunks: [StreamingMarkdownChunk] = []

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let nextLineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            let hasLineBreak = lineEnd < text.endIndex
            let trimmedLine = String(text[lineStart..<lineEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var stableBoundary: String.Index?
            if isFenceDelimiter(trimmedLine) {
                isInsideFence.toggle()
                if !isInsideFence {
                    stableBoundary = nextLineStart
                }
            } else if !isInsideFence, hasLineBreak {
                if trimmedLine.isEmpty || isStableSingleLineBlock(trimmedLine) {
                    stableBoundary = nextLineStart
                }
            }

            if let stableBoundary,
               shouldSealChunk(in: text, from: chunkStart, to: stableBoundary) {
                appendChunk(in: text, from: chunkStart, to: stableBoundary, into: &stableChunks)
                chunkStart = stableBoundary
            }

            lineStart = nextLineStart
        }

        return StreamingMarkdownBlockSegments(
            stableChunks: stableChunks,
            activeMarkdown: String(text[chunkStart...])
        )
    }

    private static func shouldSealChunk(
        in text: String,
        from start: String.Index,
        to boundary: String.Index
    ) -> Bool {
        guard boundary < text.endIndex else { return false }
        return text.distance(from: start, to: boundary) >= stableChunkTargetCharacterCount
    }

    private static func appendChunk(
        in text: String,
        from start: String.Index,
        to end: String.Index,
        into chunks: inout [StreamingMarkdownChunk]
    ) {
        guard start < end else { return }
        let chunkText = String(text[start..<end])
        guard !chunkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chunks.append(
            StreamingMarkdownChunk(
                id: chunks.count,
                text: chunkText
            )
        )
    }

    private static func isFenceDelimiter(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("```") || trimmedLine.hasPrefix("~~~")
    }

    private static func isStableSingleLineBlock(_ trimmedLine: String) -> Bool {
        let headingMarkerCount = trimmedLine.prefix(while: { $0 == "#" }).count
        let isHeading = (1...6).contains(headingMarkerCount)
            && trimmedLine.dropFirst(headingMarkerCount).first?.isWhitespace == true
        return isHeading || trimmedLine == "---" || trimmedLine == "***"
    }
}
