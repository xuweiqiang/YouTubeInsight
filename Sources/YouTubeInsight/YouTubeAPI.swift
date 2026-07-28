import Foundation

struct YouTubeRecentVideo: Equatable, Hashable, Sendable {
    let videoID: String
    let title: String
    let channelTitle: String
    let publishedAt: Date

    var url: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }
}

struct YouTubeRecentVideoQueue {
    private var videos: [YouTubeRecentVideo] = []
    private var videoIDs = Set<String>()

    var count: Int {
        videos.count
    }

    var isEmpty: Bool {
        videos.isEmpty
    }

    mutating func enqueue(contentsOf additions: [YouTubeRecentVideo]) {
        for video in additions where videoIDs.insert(video.videoID).inserted {
            videos.append(video)
        }
        videos.sort {
            if $0.publishedAt == $1.publishedAt {
                return $0.videoID < $1.videoID
            }
            return $0.publishedAt > $1.publishedAt
        }
    }

    mutating func dequeue() -> YouTubeRecentVideo? {
        guard !videos.isEmpty else {
            return nil
        }
        let video = videos.removeFirst()
        videoIDs.remove(video.videoID)
        return video
    }

    mutating func removeAll() {
        videos.removeAll(keepingCapacity: true)
        videoIDs.removeAll(keepingCapacity: true)
    }
}

enum YouTubeAPIError: LocalizedError {
    case invalidResponse
    case requestFailed(Int, reason: String?, details: String)

    var isUnavailableUploadPlaylist: Bool {
        switch self {
        case let .requestFailed(status, reason, _):
            return status == 404
                || (status == 403 && reason == "playlistItemsNotAccessible")
        case .invalidResponse:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return L10n.string(
                "youtube.error.invalidResponse",
                fallback: "YouTube returned an unreadable response."
            )
        case let .requestFailed(status, _, details):
            return L10n.format(
                "youtube.error.api",
                fallback: "YouTube API request failed (%d): %@",
                status,
                details
            )
        }
    }
}

final class YouTubeSubscriptionService: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (String) -> Void
    typealias DiscoveryHandler = @Sendable ([YouTubeRecentVideo]) async -> Void

    private let oauthManager: YouTubeOAuthManager
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let maximumConcurrentChannelRequests = 6

    init(
        oauthManager: YouTubeOAuthManager = YouTubeOAuthManager(),
        session: URLSession = .shared
    ) {
        self.oauthManager = oauthManager
        self.session = session
    }

    func hasStoredAuthorization(
        configuration: YouTubeOAuthConfiguration
    ) async -> Bool {
        await oauthManager.hasStoredAuthorization(for: configuration)
    }

    func authorize(configuration: YouTubeOAuthConfiguration) async throws -> String {
        try await oauthManager.authorize(configuration: configuration)
        return try await accountName(configuration: configuration)
    }

    func disconnect(configuration: YouTubeOAuthConfiguration?) async throws {
        try await oauthManager.revoke(configuration: configuration)
    }

    func accountName(
        configuration: YouTubeOAuthConfiguration
    ) async throws -> String {
        let response: ChannelListResponse = try await request(
            path: "channels",
            queryItems: [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "mine", value: "true"),
                URLQueryItem(name: "maxResults", value: "1")
            ],
            configuration: configuration
        )
        return response.items.first?.snippet?.title
            ?? L10n.string("youtube.accountUnknown", fallback: "YouTube account")
    }

    func discoverRecentUploads(
        configuration: YouTubeOAuthConfiguration,
        since cutoff: Date,
        progress: @escaping ProgressHandler,
        discovered: @escaping DiscoveryHandler
    ) async throws {
        progress(L10n.string(
            "youtube.status.fetchingSubscriptions",
            fallback: "Reading subscribed channels…"
        ))
        let subscriptions = try await fetchSubscriptions(
            configuration: configuration
        )
        guard !subscriptions.isEmpty else {
            return
        }

        progress(L10n.format(
            "youtube.status.fetchingChannels",
            fallback: "Preparing %d subscribed channels…",
            subscriptions.count
        ))
        let channels = try await fetchChannelDetails(
            subscriptions: subscriptions,
            configuration: configuration
        )
        guard !channels.isEmpty else {
            return
        }

        try await withThrowingTaskGroup(
            of: ChannelScanResult.self
        ) { group in
            let initialCount = min(
                maximumConcurrentChannelRequests,
                channels.count
            )
            for channel in channels.prefix(initialCount) {
                group.addTask { [self] in
                    try await scanChannel(
                        channel,
                        cutoff: cutoff,
                        configuration: configuration
                    )
                }
            }

            var nextIndex = initialCount
            var completedCount = 0
            while let result = try await group.next() {
                completedCount += 1
                progress(L10n.format(
                    "youtube.status.scanningChannel",
                    fallback: "Checking recent uploads %d/%d: %@",
                    completedCount,
                    channels.count,
                    result.channel.title
                ))
                if !result.videos.isEmpty {
                    await discovered(result.videos)
                }

                if nextIndex < channels.count {
                    let channel = channels[nextIndex]
                    nextIndex += 1
                    group.addTask { [self] in
                        try await scanChannel(
                            channel,
                            cutoff: cutoff,
                            configuration: configuration
                        )
                    }
                }
            }
        }
    }

    private func scanChannel(
        _ channel: UploadChannel,
        cutoff: Date,
        configuration: YouTubeOAuthConfiguration
    ) async throws -> ChannelScanResult {
        do {
            let videos = try await fetchRecentVideos(
                channel: channel,
                cutoff: cutoff,
                configuration: configuration
            )
            return ChannelScanResult(channel: channel, videos: videos)
        } catch let error as YouTubeAPIError
            where error.isUnavailableUploadPlaylist {
            return ChannelScanResult(channel: channel, videos: [])
        }
    }

    private func fetchSubscriptions(
        configuration: YouTubeOAuthConfiguration
    ) async throws -> [SubscribedChannel] {
        var result: [SubscribedChannel] = []
        var pageToken: String?

        repeat {
            var items = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "mine", value: "true"),
                URLQueryItem(name: "maxResults", value: "50"),
                URLQueryItem(name: "order", value: "alphabetical")
            ]
            if let pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let response: SubscriptionListResponse = try await request(
                path: "subscriptions",
                queryItems: items,
                configuration: configuration
            )
            result += response.items.compactMap { item in
                guard let channelID = item.snippet?.resourceID?.channelID?.nilIfBlank else {
                    return nil
                }
                return SubscribedChannel(
                    channelID: channelID,
                    title: item.snippet?.title?.nilIfBlank ?? channelID
                )
            }
            pageToken = response.nextPageToken
        } while pageToken != nil

        return result
    }

    private func fetchChannelDetails(
        subscriptions: [SubscribedChannel],
        configuration: YouTubeOAuthConfiguration
    ) async throws -> [UploadChannel] {
        var channels: [UploadChannel] = []
        let lookup = Dictionary(
            uniqueKeysWithValues: subscriptions.map { ($0.channelID, $0.title) }
        )

        for start in stride(from: 0, to: subscriptions.count, by: 50) {
            let end = min(start + 50, subscriptions.count)
            let ids = subscriptions[start..<end]
                .map(\.channelID)
                .joined(separator: ",")
            let response: ChannelListResponse = try await request(
                path: "channels",
                queryItems: [
                    URLQueryItem(name: "part", value: "snippet,contentDetails"),
                    URLQueryItem(name: "id", value: ids),
                    URLQueryItem(name: "maxResults", value: "50")
                ],
                configuration: configuration
            )
            channels += response.items.compactMap { item in
                guard let playlistID = item.contentDetails?
                    .relatedPlaylists?
                    .uploads?
                    .nilIfBlank else {
                    return nil
                }
                return UploadChannel(
                    channelID: item.id,
                    title: item.snippet?.title?.nilIfBlank
                        ?? lookup[item.id]
                        ?? item.id,
                    uploadsPlaylistID: playlistID
                )
            }
        }
        return channels.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func fetchRecentVideos(
        channel: UploadChannel,
        cutoff: Date,
        configuration: YouTubeOAuthConfiguration
    ) async throws -> [YouTubeRecentVideo] {
        var videos: [YouTubeRecentVideo] = []
        var pageToken: String?
        let now = Date().addingTimeInterval(300)

        repeat {
            var items = [
                URLQueryItem(name: "part", value: "snippet,contentDetails"),
                URLQueryItem(name: "playlistId", value: channel.uploadsPlaylistID),
                URLQueryItem(name: "maxResults", value: "50")
            ]
            if let pageToken {
                items.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let response: PlaylistItemListResponse = try await request(
                path: "playlistItems",
                queryItems: items,
                configuration: configuration
            )
            let parsed = YouTubeAPIParser.videos(
                from: response,
                fallbackChannelTitle: channel.title
            )
            videos += parsed.filter {
                $0.publishedAt >= cutoff && $0.publishedAt <= now
            }

            let oldest = parsed.map(\.publishedAt).min()
            if let oldest, oldest < cutoff {
                pageToken = nil
            } else {
                pageToken = response.nextPageToken
            }
        } while pageToken != nil

        return videos.sorted {
            if $0.publishedAt == $1.publishedAt {
                return $0.videoID < $1.videoID
            }
            return $0.publishedAt > $1.publishedAt
        }
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        configuration: YouTubeOAuthConfiguration,
        retryingAfterUnauthorized: Bool = false
    ) async throws -> Response {
        let token = try await oauthManager.validAccessToken(
            configuration: configuration,
            forceRefresh: retryingAfterUnauthorized
        )
        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/\(path)"
        )!
        components.queryItems = queryItems
        guard let url = components.url else {
            throw YouTubeAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.invalidResponse
        }
        if http.statusCode == 401, !retryingAfterUnauthorized {
            return try await self.request(
                path: path,
                queryItems: queryItems,
                configuration: configuration,
                retryingAfterUnauthorized: true
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            let details = YouTubeAPIParser.errorDetails(from: data)
            throw YouTubeAPIError.requestFailed(
                http.statusCode,
                reason: details.reason,
                details: details.message
            )
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw YouTubeAPIError.invalidResponse
        }
    }
}

private struct SubscribedChannel {
    let channelID: String
    let title: String
}

private struct UploadChannel: Sendable {
    let channelID: String
    let title: String
    let uploadsPlaylistID: String
}

private struct ChannelScanResult: Sendable {
    let channel: UploadChannel
    let videos: [YouTubeRecentVideo]
}

struct SubscriptionListResponse: Decodable {
    struct Item: Decodable {
        struct Snippet: Decodable {
            struct ResourceID: Decodable {
                let channelID: String?

                enum CodingKeys: String, CodingKey {
                    case channelID = "channelId"
                }
            }

            let title: String?
            let resourceID: ResourceID?

            enum CodingKeys: String, CodingKey {
                case title
                case resourceID = "resourceId"
            }
        }

        let snippet: Snippet?
    }

    let nextPageToken: String?
    let items: [Item]
}

struct ChannelListResponse: Decodable {
    struct Item: Decodable {
        struct Snippet: Decodable {
            let title: String?
        }

        struct ContentDetails: Decodable {
            struct RelatedPlaylists: Decodable {
                let uploads: String?
            }

            let relatedPlaylists: RelatedPlaylists?
        }

        let id: String
        let snippet: Snippet?
        let contentDetails: ContentDetails?
    }

    let items: [Item]
}

struct PlaylistItemListResponse: Decodable {
    struct Item: Decodable {
        struct Snippet: Decodable {
            let title: String?
            let channelTitle: String?
            let videoOwnerChannelTitle: String?
            let publishedAt: String?
        }

        struct ContentDetails: Decodable {
            let videoID: String?
            let videoPublishedAt: String?

            enum CodingKeys: String, CodingKey {
                case videoID = "videoId"
                case videoPublishedAt
            }
        }

        let snippet: Snippet?
        let contentDetails: ContentDetails?
    }

    let nextPageToken: String?
    let items: [Item]
}

enum YouTubeAPIParser {
    static func videos(
        from response: PlaylistItemListResponse,
        fallbackChannelTitle: String
    ) -> [YouTubeRecentVideo] {
        response.items.compactMap { item in
            guard let videoID = item.contentDetails?.videoID?.nilIfBlank,
                  let title = item.snippet?.title?.nilIfBlank,
                  let dateString = item.contentDetails?.videoPublishedAt
                    ?? item.snippet?.publishedAt,
                  let publishedAt = parseDate(dateString) else {
                return nil
            }
            return YouTubeRecentVideo(
                videoID: videoID,
                title: title,
                channelTitle: item.snippet?.videoOwnerChannelTitle?.nilIfBlank
                    ?? item.snippet?.channelTitle?.nilIfBlank
                    ?? fallbackChannelTitle,
                publishedAt: publishedAt
            )
        }
    }

    static func errorDetails(from data: Data) -> YouTubeAPIErrorDetails {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable {
                struct Detail: Decodable {
                    let message: String?
                    let reason: String?
                }

                let message: String?
                let errors: [Detail]?
            }

            let error: APIError?
        }
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let apiError = envelope.error {
            return YouTubeAPIErrorDetails(
                reason: apiError.errors?.first?.reason?.nilIfBlank,
                message: apiError.message?.nilIfBlank
                    ?? apiError.errors?.first?.message?.nilIfBlank
                    ?? L10n.string(
                        "youtube.error.unknown",
                        fallback: "Unknown YouTube API error"
                    )
            )
        }
        return YouTubeAPIErrorDetails(
            reason: nil,
            message: String(data: data, encoding: .utf8)?.nilIfBlank
                ?? L10n.string(
                    "youtube.error.unknown",
                    fallback: "Unknown YouTube API error"
                )
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct YouTubeAPIErrorDetails: Equatable {
    let reason: String?
    let message: String
}
