import XCTest
@testable import HermesMobile

/// Covers the tolerant-decoding hard rule for numeric fields: values the
/// server could plausibly send — including numbers outside `Int`'s
/// representable range — must decode to `nil` instead of trapping.
final class LossyNumericDecodingTests: XCTestCase {

    // MARK: - decodeLossyIntIfPresent probe

    private struct IntProbe: Decodable {
        let value: Int?

        private enum CodingKeys: String, CodingKey {
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = container.decodeLossyIntIfPresent(forKey: .value)
        }
    }

    private func decodeProbe(_ json: String) throws -> IntProbe {
        try JSONDecoder().decode(IntProbe.self, from: Data(json.utf8))
    }

    func testLossyIntDecodesInRangeValues() throws {
        XCTAssertEqual(try decodeProbe(#"{"value": 42}"#).value, 42)
        XCTAssertEqual(try decodeProbe(#"{"value": 5.7}"#).value, 5)
        XCTAssertEqual(try decodeProbe(#"{"value": -3.2}"#).value, -3)
        XCTAssertEqual(try decodeProbe(#"{"value": "17"}"#).value, 17)
        XCTAssertEqual(try decodeProbe(#"{"value": "3.9"}"#).value, 3)
        XCTAssertNil(try decodeProbe(#"{"value": null}"#).value)
        XCTAssertNil(try decodeProbe(#"{}"#).value)
    }

    func testLossyIntReturnsNilForOutOfRangeNumbers() throws {
        XCTAssertNil(try decodeProbe(#"{"value": 1e20}"#).value)
        XCTAssertNil(try decodeProbe(#"{"value": -1e20}"#).value)
        XCTAssertNil(try decodeProbe(#"{"value": 9223372036854775808}"#).value)
    }

    func testLossyIntReturnsNilForOutOfRangeNumericStrings() throws {
        XCTAssertNil(try decodeProbe(#"{"value": "1e20"}"#).value)
        XCTAssertNil(try decodeProbe(#"{"value": "-1e20"}"#).value)
    }

    // MARK: - Real model round-trips

    func testSessionSummaryToleratesOversizedMessageCount() throws {
        let payloads = [
            #"{"session_id": "s1"}"#,
            #"{"session_id": "s1", "message_count": 1e20}"#,
            #"{"session_id": "s1", "input_tokens": 9223372036854775808}"#,
            #"{"session_id": "s1", "message_count": 1e20, "input_tokens": 9223372036854775808}"#,
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        for json in payloads {
            do {
                let summary = try decoder.decode(SessionSummary.self, from: Data(json.utf8))
                XCTAssertEqual(summary.sessionId, "s1", "payload: \(json)")
                XCTAssertNil(summary.messageCount, "payload: \(json)")
                XCTAssertNil(summary.inputTokens, "payload: \(json)")
            } catch {
                XCTFail("payload \(json) threw: \(error)")
            }
        }
    }

    func testToolCallResultToleratesOversizedExitCode() {
        let display = ToolCallDisplayFormatter.resultDisplay(
            preview: #"{"output":"done\n","exit_code":1e20,"error":null}"#,
            toolName: "terminal"
        )

        XCTAssertEqual(display?.text, "done")
    }

    /// `SessionSummary` previously relied on synthesized decoding, so one
    /// drifted field — a fractional `message_count`, a numeric `title` — threw
    /// and dropped the entire sessions payload.
    func testSessionSummaryToleratesDriftedFieldShapes() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let json = #"""
        {
            "session_id": "s1",
            "title": 42,
            "message_count": 1.5,
            "created_at": 1751234567.123,
            "pinned": "true",
            "estimated_cost": "0.05"
        }
        """#
        let summary = try decoder.decode(SessionSummary.self, from: Data(json.utf8))

        XCTAssertEqual(summary.sessionId, "s1")
        XCTAssertEqual(summary.title, "42")
        XCTAssertEqual(summary.messageCount, 1)
        XCTAssertEqual(summary.createdAt ?? 0, 1751234567.123, accuracy: 0.001)
        XCTAssertEqual(summary.pinned, true)
        XCTAssertEqual(summary.estimatedCost, 0.05)
    }

    // MARK: - Duration formatting from server-supplied seconds

    func testClarificationDurationTextToleratesOversizedTimeout() {
        XCTAssertEqual(ClarificationRequestCard.durationText(Double(Int.max)), "0s")
        XCTAssertEqual(ClarificationRequestCard.durationText(1e20), "0s")
        XCTAssertEqual(ClarificationRequestCard.durationText(90), "1m 30s")
    }
}
