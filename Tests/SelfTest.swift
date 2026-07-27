import Foundation

@main
struct SelfTest {
    static func main() throws {
        try testURLParsing()
        try testSubtitleParsing()
        try testPlainTextWhisperTranscript()
        try testGUIProcessPathNormalization()
        try testAnalysisLengthLimit()
        try testHistoryRoundTrip()
        print("All YouTubeInsight self-tests passed.")
    }

    private static func testURLParsing() throws {
        let shortURL = YouTubeURLParser.canonicalURL(
            from: "https://youtu.be/XYgm-dNNrR8?si=test"
        )
        try expect(
            shortURL?.absoluteString == "https://www.youtube.com/watch?v=XYgm-dNNrR8",
            "youtu.be URL canonicalization failed"
        )
        try expect(
            YouTubeURLParser.canonicalURL(from: "https://example.com/watch?v=XYgm-dNNrR8") == nil,
            "non-YouTube URL should be rejected"
        )
    }

    private static func testSubtitleParsing() throws {
        let data = """
        {
          "events": [
            {"segs": [{"utf8": "第一句"}]},
            {"segs": [{"utf8": "第一句"}]},
            {"segs": [{"utf8": "第二"}, {"utf8": "句\\n"}]}
          ]
        }
        """.data(using: .utf8)!
        let parsed = try SubtitleParser.parseJSON3(data: data)
        try expect(parsed == "第一句\n第二句", "JSON3 caption parsing failed")
    }

    private static func testHistoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YouTubeInsightSelfTest-\(UUID().uuidString)")
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
        try expect(store.load() == [record], "history persistence round trip failed")
    }

    private static func testPlainTextWhisperTranscript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YouTubeInsightTranscriptTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let outputURL = directory.appendingPathComponent("transcript.txt")
        try "  有效的转写文字  \n".write(
            to: outputURL,
            atomically: true,
            encoding: .utf8
        )
        let transcript = try WhisperTranscript.read(from: outputURL)
        try expect(
            transcript == "有效的转写文字",
            "plain-text Whisper transcript parsing failed"
        )
    }

    private static func testGUIProcessPathNormalization() throws {
        guard CommandLocator.locate("node") != nil else {
            return
        }
        let result = try ProcessRunner().run(
            executable: "/usr/bin/env",
            arguments: ["node", "--version"],
            environment: [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": "/usr/bin:/bin"
            ]
        )
        try expect(
            result.succeeded,
            "GUI process PATH should include the Homebrew Node directory"
        )
    }

    private static func testAnalysisLengthLimit() throws {
        let result = AnalysisFormatter.capped(String(repeating: "字", count: 700))
        try expect(result.count == 500, "analysis should be capped at 500 characters")
        try expect(result.hasSuffix("…"), "truncated analysis should end with an ellipsis")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw SelfTestError(message: message)
        }
    }
}

private struct SelfTestError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
