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
        try testYouTubeUnavailablePlaylistErrorHandling()
        try testYouTubeRecentVideoQueue()
        try testYTDLPForbiddenRecovery()
        try testHistoryScrollPolicy()
        try testVideoPublicationDateParsing()
        try testLeanCodexSummaryInvocation()
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
            YouTubeURLParser.thumbnailURL(
                from: "https://www.youtube.com/shorts/XYgm-dNNrR8"
            )?.absoluteString == "https://i.ytimg.com/vi/XYgm-dNNrR8/hqdefault.jpg",
            "YouTube thumbnail URL generation failed"
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
        let publishedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let thumbnailURL = URL(
            string: "https://i.ytimg.com/vi/XYgm-dNNrR8/maxresdefault.jpg"
        )!
        let record = AnalysisRecord(
            url: "https://www.youtube.com/watch?v=XYgm-dNNrR8",
            title: "测试视频",
            publishedAt: publishedAt,
            thumbnailURL: thumbnailURL,
            transcriptSource: .localWhisper,
            transcript: "转写",
            analysis: "分析"
        )
        try store.save([record])
        try expect(store.load() == [record], "history persistence round trip failed")
        try expect(
            store.load().first?.publishedAt == publishedAt,
            "video publication time should persist in history"
        )
        try expect(
            store.load().first?.thumbnailURL == thumbnailURL,
            "video thumbnail URL should persist in history"
        )
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

    private static func testYouTubeUnavailablePlaylistErrorHandling() throws {
        let data = """
        {
          "error": {
            "code": 404,
            "message": "The playlist cannot be found.",
            "errors": [{
              "message": "The playlist cannot be found.",
              "reason": "playlistNotFound"
            }]
          }
        }
        """.data(using: .utf8)!
        let details = YouTubeAPIParser.errorDetails(from: data)
        try expect(
            details.reason == "playlistNotFound",
            "YouTube API error reason should be parsed"
        )
        try expect(
            YouTubeAPIError.requestFailed(
                404,
                reason: details.reason,
                details: details.message
            ).isUnavailableUploadPlaylist,
            "a missing upload playlist should be skipped"
        )
        try expect(
            !YouTubeAPIError.requestFailed(
                403,
                reason: "quotaExceeded",
                details: "Quota exceeded"
            ).isUnavailableUploadPlaylist,
            "global API failures must not be skipped"
        )
    }

    private static func testYTDLPForbiddenRecovery() throws {
        let attempts = YTDLPRecovery.audioDownloadAttempts(
            template: "/tmp/source.%(ext)s",
            videoURL: "https://www.youtube.com/watch?v=XYgm-dNNrR8",
            metadataPath: "/tmp/metadata.json"
        )
        try expect(attempts.count == 2, "audio download should have one bounded recovery attempt")
        try expect(
            attempts[0].arguments.contains("--retries")
                && attempts[0].arguments.contains("--load-info-json")
                && attempts[0].arguments.contains("/tmp/metadata.json"),
            "the initial audio download should reuse metadata and retry transient failures"
        )
        try expect(
            attempts[1].refreshPackage
                && attempts[1].arguments.contains("--force-ipv4")
                && attempts[1].arguments.contains("--no-continue"),
            "the 403 recovery should refresh yt-dlp and request a fresh IPv4 download"
        )
        try expect(
            YTDLPRecovery.shouldRetryAfterForbidden(
                ProcessResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "HTTP Error 403: Forbidden"
                )
            ),
            "HTTP 403 should trigger the recovery attempt"
        )
        try expect(
            !YTDLPRecovery.shouldRetryAfterForbidden(
                ProcessResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "Video unavailable"
                )
            ),
            "non-403 failures should not be retried as forbidden responses"
        )
    }

    private static func testHistoryScrollPolicy() throws {
        let firstID = UUID()
        try expect(
            HistoryListScrollPolicy.target(
                previousCount: 4,
                currentCount: 5,
                firstRecordID: firstID
            ) == firstID,
            "adding a history record should scroll to the new first row"
        )
        try expect(
            HistoryListScrollPolicy.target(
                previousCount: 5,
                currentCount: 4,
                firstRecordID: firstID
            ) == nil,
            "deleting a history record should not force a scroll"
        )
    }

    private static func testVideoPublicationDateParsing() throws {
        let timestamp = 1_700_000_000.0
        try expect(
            VideoPublicationDate.parse(
                from: [
                    "release_timestamp": timestamp,
                    "timestamp": timestamp - 60
                ]
            ) == Date(timeIntervalSince1970: timestamp),
            "release timestamp should be preferred for video publication time"
        )

        let uploadDate = VideoPublicationDate.parse(
            from: ["upload_date": "20260728"]
        )
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        try expect(
            uploadDate.map { utcCalendar.component(.year, from: $0) } == 2026,
            "compact upload date should be parsed when timestamps are unavailable"
        )

        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "url": "https://www.youtube.com/watch?v=XYgm-dNNrR8",
          "title": "Legacy",
          "analyzedAt": 0,
          "transcriptSource": "本地 Whisper",
          "transcript": "text",
          "analysis": "analysis"
        }
        """.data(using: .utf8)!
        let legacyRecord = try JSONDecoder().decode(
            AnalysisRecord.self,
            from: legacyJSON
        )
        try expect(
            legacyRecord.publishedAt == nil,
            "history saved before publication dates were added should still load"
        )
        try expect(
            legacyRecord.displayThumbnailURL?.absoluteString
                == "https://i.ytimg.com/vi/XYgm-dNNrR8/hqdefault.jpg",
            "legacy history should derive a thumbnail from its YouTube URL"
        )
    }

    private static func testLeanCodexSummaryInvocation() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/analysis.md")
        let builtIn = CodexSummaryInvocation.arguments(
            outputURL: outputURL,
            model: CodexModelOption.sol.modelID,
            reasoningEffort: "medium"
        )
        try expect(
            builtIn.contains("--ephemeral")
                && builtIn.contains("--ignore-rules")
                && builtIn.contains("--ignore-user-config")
                && builtIn.contains("never"),
            "built-in Codex summaries should skip unrelated startup and session work"
        )

        let custom = CodexSummaryInvocation.arguments(
            outputURL: outputURL,
            model: "custom-provider-model",
            reasoningEffort: "low"
        )
        try expect(
            !custom.contains("--ignore-user-config"),
            "custom Codex models should retain user provider configuration"
        )
    }

    private static func testYouTubeRecentVideoQueue() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let oldest = YouTubeRecentVideo(
            videoID: "oldest",
            title: "Oldest",
            channelTitle: "Channel",
            publishedAt: base
        )
        let newest = YouTubeRecentVideo(
            videoID: "newest",
            title: "Newest",
            channelTitle: "Channel",
            publishedAt: base.addingTimeInterval(200)
        )
        let middle = YouTubeRecentVideo(
            videoID: "middle",
            title: "Middle",
            channelTitle: "Channel",
            publishedAt: base.addingTimeInterval(100)
        )

        var queue = YouTubeRecentVideoQueue()
        queue.enqueue(contentsOf: [oldest, newest, middle, newest])

        try expect(queue.count == 3, "recent video queue should deduplicate videos")
        try expect(
            queue.dequeue()?.videoID == "newest",
            "newest discovered video should be analyzed first"
        )
        try expect(
            queue.dequeue()?.videoID == "middle",
            "middle video should be analyzed second"
        )
        try expect(
            queue.dequeue()?.videoID == "oldest",
            "oldest video should be analyzed last"
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
