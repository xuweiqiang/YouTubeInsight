import XCTest
@testable import YouTubeInsight

final class YouTubeInsightTests: XCTestCase {
    func testCanonicalizesSupportedYouTubeURLs() {
        XCTAssertEqual(
            YouTubeURLParser.canonicalURL(
                from: "https://youtu.be/XYgm-dNNrR8?si=test"
            )?.absoluteString,
            "https://www.youtube.com/watch?v=XYgm-dNNrR8"
        )
        XCTAssertEqual(
            YouTubeURLParser.canonicalURL(
                from: "https://www.youtube.com/shorts/XYgm-dNNrR8"
            )?.absoluteString,
            "https://www.youtube.com/watch?v=XYgm-dNNrR8"
        )
    }

    func testRejectsNonYouTubeAndInvalidVideoIDs() {
        XCTAssertNil(YouTubeURLParser.canonicalURL(from: "https://example.com/watch?v=XYgm-dNNrR8"))
        XCTAssertNil(YouTubeURLParser.canonicalURL(from: "https://youtube.com/watch?v=short"))
        XCTAssertNil(YouTubeURLParser.canonicalURL(from: "not a url"))
    }

    func testParsesAndDeduplicatesJSON3Captions() throws {
        let data = """
        {
          "events": [
            {"segs": [{"utf8": "第一句"}]},
            {"segs": [{"utf8": "第一句"}]},
            {"segs": [{"utf8": "第二"}, {"utf8": "句\\n"}]}
          ]
        }
        """.data(using: .utf8)!

        XCTAssertEqual(
            try SubtitleParser.parseJSON3(data: data),
            "第一句\n第二句"
        )
    }

    func testHistoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YouTubeInsightTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = HistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        let record = AnalysisRecord(
            url: "https://www.youtube.com/watch?v=XYgm-dNNrR8",
            title: "测试视频",
            transcriptSource: .localWhisper,
            transcript: "转写",
            analysis: "分析"
        )
        try store.save([record])

        XCTAssertEqual(store.load(), [record])
    }

    func testAnalysisFormatterEnforcesFiveHundredCharacterLimit() {
        let result = AnalysisFormatter.capped(String(repeating: "字", count: 700))
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("…"))
    }
}
