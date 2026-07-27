import Foundation

@main
struct SelfTest {
    static func main() throws {
        try testURLParsing()
        try testSubtitleParsing()
        try testPlainTextWhisperTranscript()
        try testGUIProcessPathNormalization()
        try testAnalysisLengthLimit()
        try testAnalysisPresentation()
        try testCodexModelSettings()
        try testYouTubeOAuthCredentialImport()
        try testYouTubePlaylistParsing()
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
        let result = AnalysisFormatter.capped(
            String(repeating: "字", count: 700),
            maxCharacters: 400
        )
        try expect(result.count == 400, "analysis should be capped at 400 characters")
        try expect(result.hasSuffix("…"), "truncated analysis should end with an ellipsis")
    }

    private static func testAnalysisPresentation() throws {
        let presentation = AnalysisPresentation.parse(
            """
            ## 总览
            这是一个通俗易懂的结论。

            ## 重点
            1. **背景** — 先理解问题
            2. **过程** — 输入 → 分析 → 结论
            """
        )
        try expect(
            presentation.overview == "这是一个通俗易懂的结论。",
            "analysis overview should be parsed"
        )
        try expect(presentation.points.count == 2, "analysis points should be parsed")
        try expect(
            presentation.points[0] == AnalysisPoint(title: "背景", detail: "先理解问题"),
            "analysis point labels should be parsed"
        )
    }

    private static func testCodexModelSettings() throws {
        try expect(
            PipelineSettings.resolvedCodexModel(
                selected: CodexModelOption.custom.rawValue,
                custom: "custom-model"
            ) == "custom-model",
            "custom Codex model should be resolved"
        )
        try expect(
            PipelineSettings.resolvedCodexModel(
                selected: CodexModelOption.custom.rawValue,
                custom: ""
            ) == CodexModelOption.sol.modelID,
            "blank custom model should fall back to Sol"
        )
        try expect(
            PipelineSettings.resolvedReasoningEffort("xhigh") == "xhigh",
            "supported reasoning effort should be preserved"
        )
        try expect(
            PipelineSettings.resolvedReasoningEffort("unsupported") == "medium",
            "unsupported reasoning effort should fall back to medium"
        )
    }

    private static func testYouTubeOAuthCredentialImport() throws {
        let data = """
        {
          "installed": {
            "client_id": "desktop-client.apps.googleusercontent.com",
            "client_secret": "test-secret"
          }
        }
        """.data(using: .utf8)!
        let configuration = try YouTubeOAuthConfiguration.imported(from: data)
        try expect(
            configuration.clientID == "desktop-client.apps.googleusercontent.com",
            "OAuth client ID should be imported"
        )
        try expect(
            configuration.clientSecret == "test-secret",
            "OAuth client secret should be imported"
        )
    }

    private static func testYouTubePlaylistParsing() throws {
        let data = """
        {
          "items": [{
            "snippet": {
              "title": "New video",
              "channelTitle": "Example channel",
              "publishedAt": "2026-07-27T01:00:00Z"
            },
            "contentDetails": {
              "videoId": "XYgm-dNNrR8",
              "videoPublishedAt": "2026-07-27T01:00:00Z"
            }
          }]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(
            PlaylistItemListResponse.self,
            from: data
        )
        let videos = YouTubeAPIParser.videos(
            from: response,
            fallbackChannelTitle: "Fallback"
        )
        try expect(videos.count == 1, "YouTube playlist item should be parsed")
        try expect(
            videos[0].videoID == "XYgm-dNNrR8",
            "YouTube video ID should be parsed"
        )
        try expect(
            videos[0].channelTitle == "Example channel",
            "YouTube channel title should be parsed"
        )
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
