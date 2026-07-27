import Foundation

struct YouTubeRecentVideo: Equatable, Hashable {
    let videoID: String
    let title: String
    let channelTitle: String
    let publishedAt: Date

    var url: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }
}

enum YouTubeAPIError: LocalizedError {
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return L10n.string(
                "youtube.error.invalidResponse",
                fallback: "YouTube returned an unreadable response."
            )
        case let .requestFailed(status, details):
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

    private let oauthManager: YouTubeOAuthManager
    private let session: URLSession
    private let decoder = JSONDecoder()

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

    func recentUploads(
        configuration: YouTubeOAuthConfiguration,
        since cutoff: Date,
        progress: @escaping ProgressHandler
    ) async throws -> [YouTubeRecentVideo] {
        progress(L10n.string(
            "youtube.status.fetchingSubscriptions",
            fallback: "Reading subscribed channels…"
        ))
        let subscriptions = try await fetchSubscriptions(
            configuration: configuration
        )
        guard !subscriptions.isEmpty else {
            return []
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

        var videos: [YouTubeRecentVideo] = []
        for (index, channel) in channels.enumerated() {
            progress(L10n.format(
                "youtube.status.scanningChannel",
                fallback: "Checking recent uploads %d/%d: %@",
                index + 1,
                channels.count,
                channel.title
            ))
            videos += try await fetchRecentVideos(
                channel: channel,
                cutoff: cutoff,
                configuration: configuration
            )
        }

        var unique: [String: YouTubeRecentVideo] = [:]
        for video in videos {
            unique[video.videoID] = video
        }
        return unique.values.sorted { $0.publishedAt < $1.publishedAt }
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

        return videos
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
            throw YouTubeAPIError.requestFailed(
                http.statusCode,
                YouTubeAPIParser.errorMessage(from: data)
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

private struct UploadChannel {
    let channelID: String
    let title: String
    let uploadsPlaylistID: String
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

    static func errorMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable {
                let message: String?
            }

            let error: APIError?
        }
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = envelope.error?.message?.nilIfBlank {
            return message
        }
        return String(data: data, encoding: .utf8)?.nilIfBlank
            ?? L10n.string("youtube.error.unknown", fallback: "Unknown YouTube API error")
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
