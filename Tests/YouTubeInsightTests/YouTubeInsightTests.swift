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
        XCTAssertEqual(
            YouTubeURLParser.thumbnailURL(
                from: "https://youtu.be/XYgm-dNNrR8"
            )?.absoluteString,
            "https://i.ytimg.com/vi/XYgm-dNNrR8/hqdefault.jpg"
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
        let thumbnailURL = URL(
            string: "https://i.ytimg.com/vi/XYgm-dNNrR8/maxresdefault.jpg"
        )!
        let record = AnalysisRecord(
            url: "https://www.youtube.com/watch?v=XYgm-dNNrR8",
            title: "测试视频",
            thumbnailURL: thumbnailURL,
            transcriptSource: .localWhisper,
            transcript: "转写",
            analysis: "分析"
        )
        try store.save([record])

        XCTAssertEqual(store.load(), [record])
        XCTAssertEqual(store.load().first?.thumbnailURL, thumbnailURL)
    }

    func testReadsPlainTextWhisperTranscript() throws {
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

        XCTAssertEqual(
            try WhisperTranscript.read(from: outputURL),
            "有效的转写文字"
        )
    }

    func testProcessRunnerAddsHomebrewToolsToMinimalGUIPath() throws {
        guard CommandLocator.locate("node") != nil else {
            throw XCTSkip("Node is not installed on this Mac")
        }
        let result = try ProcessRunner().run(
            executable: "/usr/bin/env",
            arguments: ["node", "--version"],
            environment: [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": "/usr/bin:/bin"
            ]
        )

        XCTAssertTrue(result.succeeded, result.standardError)
    }

    func testAnalysisFormatterEnforcesFourHundredCharacterLimit() {
        let result = AnalysisFormatter.capped(
            String(repeating: "字", count: 700),
            maxCharacters: 400
        )
        XCTAssertEqual(result.count, 400)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testAnalysisPresentationParsesOverviewAndLabeledPoints() {
        let presentation = AnalysisPresentation.parse(
            """
            ## Overview
            A short, clear conclusion.

            ## Key points
            1. **Problem** — The old result was too long.
            2. **Solution** — Summary → labels → visual cards.
            """
        )

        XCTAssertEqual(presentation.overview, "A short, clear conclusion.")
        XCTAssertEqual(
            presentation.points,
            [
                AnalysisPoint(title: "Problem", detail: "The old result was too long."),
                AnalysisPoint(title: "Solution", detail: "Summary → labels → visual cards.")
            ]
        )
    }

    func testImportsGoogleDesktopOAuthCredentialFile() throws {
        let data = """
        {
          "installed": {
            "client_id": "desktop-client.apps.googleusercontent.com",
            "client_secret": "test-secret"
          }
        }
        """.data(using: .utf8)!

        XCTAssertEqual(
            try YouTubeOAuthConfiguration.imported(from: data),
            YouTubeOAuthConfiguration(
                clientID: "desktop-client.apps.googleusercontent.com",
                clientSecret: "test-secret"
            )
        )
    }

    func testResolvesCodexModelAndReasoningSettings() {
        XCTAssertEqual(
            PipelineSettings.resolvedCodexModel(
                selected: CodexModelOption.custom.rawValue,
                custom: "custom-model"
            ),
            "custom-model"
        )
        XCTAssertEqual(
            PipelineSettings.resolvedCodexModel(
                selected: CodexModelOption.custom.rawValue,
                custom: nil
            ),
            CodexModelOption.sol.modelID
        )
        XCTAssertEqual(
            PipelineSettings.resolvedReasoningEffort("ultra"),
            "ultra"
        )
        XCTAssertEqual(
            PipelineSettings.resolvedReasoningEffort("unsupported"),
            "medium"
        )
    }

    func testParsesYouTubeUploadPlaylistItems() throws {
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

        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].videoID, "XYgm-dNNrR8")
        XCTAssertEqual(videos[0].channelTitle, "Example channel")
    }

    func testClassifiesOnlyUnavailableUploadPlaylistsAsSkippable() {
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

        XCTAssertEqual(details.reason, "playlistNotFound")
        XCTAssertTrue(
            YouTubeAPIError.requestFailed(
                404,
                reason: details.reason,
                details: details.message
            ).isUnavailableUploadPlaylist
        )
        XCTAssertFalse(
            YouTubeAPIError.requestFailed(
                403,
                reason: "quotaExceeded",
                details: "Quota exceeded"
            ).isUnavailableUploadPlaylist
        )
    }

    func testRecentVideoQueueOrdersNewestFirstAndDeduplicates() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let videos = [
            YouTubeRecentVideo(
                videoID: "oldest",
                title: "Oldest",
                channelTitle: "Channel",
                publishedAt: base
            ),
            YouTubeRecentVideo(
                videoID: "newest",
                title: "Newest",
                channelTitle: "Channel",
                publishedAt: base.addingTimeInterval(200)
            ),
            YouTubeRecentVideo(
                videoID: "middle",
                title: "Middle",
                channelTitle: "Channel",
                publishedAt: base.addingTimeInterval(100)
            )
        ]
        var queue = YouTubeRecentVideoQueue()
        queue.enqueue(contentsOf: videos + [videos[1]])

        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.dequeue()?.videoID, "newest")
        XCTAssertEqual(queue.dequeue()?.videoID, "middle")
        XCTAssertEqual(queue.dequeue()?.videoID, "oldest")
        XCTAssertTrue(queue.isEmpty)
    }
}
