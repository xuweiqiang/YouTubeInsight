import AppKit
import Foundation

enum EnvironmentPreparationState: Equatable {
    case idle
    case preparing
    case ready
    case failed
}

enum YouTubeConnectionState: Equatable {
    case notConfigured
    case disconnected
    case connecting
    case connected(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var urlInput = ""
    @Published var records: [AnalysisRecord]
    @Published var selectedRecordID: UUID?
    @Published var isAnalyzing = false
    @Published private(set) var isRefreshingSubscriptions = false
    @Published private(set) var pendingAutomaticAnalyses = 0
    @Published private(set) var lastSubscriptionRefresh: Date?
    @Published private(set) var youtubeConnectionState: YouTubeConnectionState
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published private(set) var environmentState: EnvironmentPreparationState = .idle
    @Published private(set) var environmentMessage = ""
    @Published private(set) var environmentError: String?

    private let store: HistoryStore
    private let pipeline: AnalysisPipeline
    private let runtimeEnvironment: RuntimeEnvironment
    private let youtubeService: YouTubeSubscriptionService
    private var subscriptionMonitorTask: Task<Void, Never>?
    private var attemptedVideoIDs = Set<String>()
    private var automaticVideoQueue = YouTubeRecentVideoQueue()
    private var automaticDiscoveryFinished = true
    private var automaticDiscoveredCount = 0
    private let subscriptionChannelCountKey = "youtubeSubscriptionChannelCount"
    private let quotaRetryAfterKey = "youtubeQuotaRetryAfter"

    private var monitorInterval: UInt64 {
        let channelCount = UserDefaults.standard.integer(
            forKey: subscriptionChannelCountKey
        )
        return UInt64(
            YouTubeQuotaPolicy.scanInterval(channelCount: channelCount)
                * 1_000_000_000
        )
    }

    init(
        store: HistoryStore = HistoryStore(),
        pipeline: AnalysisPipeline = AnalysisPipeline(),
        runtimeEnvironment: RuntimeEnvironment = RuntimeEnvironment(),
        youtubeService: YouTubeSubscriptionService = YouTubeSubscriptionService()
    ) {
        self.store = store
        self.pipeline = pipeline
        self.runtimeEnvironment = runtimeEnvironment
        self.youtubeService = youtubeService
        let loaded = store.load()
        records = loaded
        selectedRecordID = loaded.first?.id
        lastSubscriptionRefresh = UserDefaults.standard.object(
            forKey: "youtubeLastSubscriptionRefresh"
        ) as? Date
        if YouTubeOAuthConfiguration.current == nil {
            youtubeConnectionState = .notConfigured
        } else {
            youtubeConnectionState = .disconnected
        }
    }

    var selectedRecord: AnalysisRecord? {
        guard let selectedRecordID else {
            return nil
        }
        return records.first(where: { $0.id == selectedRecordID })
    }

    func prepareEnvironmentIfNeeded() {
        guard environmentState == .idle else {
            return
        }
        prepareEnvironment()
    }

    func retryEnvironmentPreparation() {
        guard environmentState != .preparing else {
            return
        }
        prepareEnvironment()
    }

    func bindYouTubeAccount() {
        guard youtubeConnectionState != .connecting else {
            return
        }
        guard let configuration = YouTubeOAuthConfiguration.current else {
            youtubeConnectionState = .notConfigured
            errorMessage = YouTubeOAuthError.missingConfiguration.localizedDescription
            return
        }
        youtubeConnectionState = .connecting
        statusMessage = L10n.string(
            "youtube.status.binding",
            fallback: "Waiting for YouTube authorization in the browser…"
        )
        errorMessage = nil

        Task {
            do {
                let accountName = try await youtubeService.authorize(
                    configuration: configuration
                )
                UserDefaults.standard.set(
                    accountName,
                    forKey: "youtubeAccountDisplayName"
                )
                youtubeConnectionState = .connected(accountName)
                statusMessage = L10n.string(
                    "youtube.status.bound",
                    fallback: "YouTube account connected"
                )
                beginYouTubeMonitoringIfNeeded()
                await refreshSubscriptionsNow(force: true)
            } catch {
                youtubeConnectionState = .disconnected
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                statusMessage = L10n.string(
                    "youtube.status.bindFailed",
                    fallback: "YouTube account connection failed"
                )
            }
        }
    }

    func disconnectYouTubeAccount() {
        let configuration = YouTubeOAuthConfiguration.current
        Task {
            do {
                try await youtubeService.disconnect(configuration: configuration)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            UserDefaults.standard.removeObject(forKey: "youtubeAccountDisplayName")
            youtubeConnectionState = configuration == nil ? .notConfigured : .disconnected
            pendingAutomaticAnalyses = 0
            attemptedVideoIDs.removeAll()
            statusMessage = L10n.string(
                "youtube.status.disconnected",
                fallback: "YouTube account disconnected"
            )
        }
    }

    func refreshSubscriptions() {
        Task {
            await refreshSubscriptionsNow(force: true)
        }
    }

    func analyzeManualURL() {
        guard environmentState == .ready else {
            errorMessage = environmentError ?? L10n.string(
                "environment.notReady",
                fallback: "The runtime environment is not ready. Retry the startup check."
            )
            return
        }
        guard !isAnalyzing, !isRefreshingSubscriptions else {
            return
        }
        guard let url = YouTubeURLParser.canonicalURL(from: urlInput) else {
            errorMessage = L10n.string(
                "error.invalidURL",
                fallback: "Enter a valid YouTube video URL."
            )
            return
        }

        isAnalyzing = true
        errorMessage = nil
        statusMessage = L10n.string(
            "status.preparing",
            fallback: "Preparing analysis…"
        )

        Task {
            defer {
                isAnalyzing = false
            }
            do {
                try await analyzeAndSave(url: url)
                urlInput = ""
                statusMessage = L10n.string(
                    "status.completeSaved",
                    fallback: "Analysis complete and saved"
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                statusMessage = L10n.string(
                    "status.failed",
                    fallback: "Analysis failed"
                )
            }
        }
    }

    private func prepareEnvironment() {
        environmentState = .preparing
        environmentError = nil
        environmentMessage = L10n.string(
            "environment.starting",
            fallback: "Checking runtime environment…"
        )

        Task {
            do {
                try await runtimeEnvironment.prepare { [self] message in
                    DispatchQueue.main.async { [self] in
                        environmentMessage = message
                    }
                }
                environmentMessage = L10n.string(
                    "environment.ready",
                    fallback: "Runtime environment is ready"
                )
                environmentState = .ready
                beginYouTubeMonitoringIfNeeded()
            } catch {
                environmentError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                environmentMessage = L10n.string(
                    "environment.failed",
                    fallback: "Runtime environment check failed"
                )
                environmentState = .failed
            }
        }
    }

    private func beginYouTubeMonitoringIfNeeded() {
        guard environmentState == .ready,
              subscriptionMonitorTask == nil else {
            return
        }
        subscriptionMonitorTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.restoreYouTubeConnection()
            await self.refreshSubscriptionsNow()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.monitorInterval)
                guard !Task.isCancelled else {
                    return
                }
                await self.refreshSubscriptionsNow()
            }
        }
    }

    private func restoreYouTubeConnection() async {
        guard let configuration = YouTubeOAuthConfiguration.current else {
            youtubeConnectionState = .notConfigured
            return
        }
        let hasAuthorization = await youtubeService.hasStoredAuthorization(
            configuration: configuration
        )
        guard hasAuthorization else {
            youtubeConnectionState = .disconnected
            return
        }
        let savedName = UserDefaults.standard.string(
            forKey: "youtubeAccountDisplayName"
        )?.nilIfBlank
        youtubeConnectionState = .connected(
            savedName ?? L10n.string(
                "youtube.accountUnknown",
                fallback: "YouTube account"
            )
        )
    }

    private func refreshSubscriptionsNow(force: Bool = false) async {
        guard environmentState == .ready,
              !isRefreshingSubscriptions,
              !isAnalyzing,
              case .connected = youtubeConnectionState,
              let configuration = YouTubeOAuthConfiguration.current else {
            return
        }

        let now = Date()
        if let retryAfter = UserDefaults.standard.object(
            forKey: quotaRetryAfterKey
        ) as? Date {
            if retryAfter > now {
                errorMessage = YouTubeQuotaPolicy.quotaExceededMessage
                statusMessage = YouTubeQuotaPolicy.quotaExceededMessage
                return
            }
            UserDefaults.standard.removeObject(forKey: quotaRetryAfterKey)
        }

        let knownChannelCount = UserDefaults.standard.integer(
            forKey: subscriptionChannelCountKey
        )
        guard force || YouTubeQuotaPolicy.shouldScan(
            lastRefresh: lastSubscriptionRefresh,
            channelCount: knownChannelCount,
            now: now
        ) else {
            return
        }

        isRefreshingSubscriptions = true
        errorMessage = nil
        defer {
            isRefreshingSubscriptions = false
            pendingAutomaticAnalyses = 0
            isAnalyzing = false
            automaticVideoQueue.removeAll()
            automaticDiscoveryFinished = true
        }

        do {
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            automaticVideoQueue.removeAll()
            automaticDiscoveryFinished = false
            automaticDiscoveredCount = 0

            async let discovery: Int = discoverAutomaticVideos(
                configuration: configuration,
                cutoff: cutoff
            )

            var succeeded = 0
            var failed = 0
            var deferred = 0
            while !automaticDiscoveryFinished || !automaticVideoQueue.isEmpty {
                guard !Task.isCancelled else {
                    return
                }

                guard let video = automaticVideoQueue.dequeue() else {
                    do {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    } catch {
                        return
                    }
                    continue
                }

                isAnalyzing = true
                pendingAutomaticAnalyses = automaticVideoQueue.count + 1
                statusMessage = L10n.format(
                    "youtube.status.analyzingVideo",
                    fallback: "Analyzing %d/%d: %@",
                    succeeded + failed + deferred + 1,
                    automaticDiscoveredCount,
                    video.title
                )
                do {
                    try await analyzeAutomatically(video)
                    succeeded += 1
                } catch let pipelineError as PipelineError
                    where pipelineError.isUpcomingLiveEvent {
                    deferred += 1
                    attemptedVideoIDs.remove(video.videoID)
                } catch {
                    failed += 1
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
                isAnalyzing = false
                pendingAutomaticAnalyses = automaticVideoQueue.count
            }
            let channelCount = try await discovery
            UserDefaults.standard.set(
                channelCount,
                forKey: subscriptionChannelCountKey
            )

            guard succeeded + failed + deferred > 0 else {
                completeSubscriptionRefresh(
                    status: L10n.string(
                        "youtube.status.noNewVideos",
                        fallback: "No new subscription videos in the last 24 hours"
                    )
                )
                return
            }

            let status = succeeded == 0 && failed == 0 && deferred > 0
                ? PipelineError.upcomingLiveEvent.localizedDescription
                : failed == 0
                ? L10n.format(
                    "youtube.status.refreshComplete",
                    fallback: "%d new videos analyzed and saved",
                    succeeded
                )
                : L10n.format(
                    "youtube.status.refreshPartial",
                    fallback: "%d analyzed, %d failed",
                    succeeded,
                    failed
                )
            completeSubscriptionRefresh(status: status)
        } catch let error as YouTubeAPIError where error.isQuotaExceeded {
            let retryAfter = YouTubeQuotaPolicy.quotaRetryDate()
            UserDefaults.standard.set(retryAfter, forKey: quotaRetryAfterKey)
            errorMessage = error.localizedDescription
            statusMessage = YouTubeQuotaPolicy.quotaExceededMessage
        } catch YouTubeOAuthError.authorizationRequired {
            youtubeConnectionState = .disconnected
            UserDefaults.standard.removeObject(forKey: "youtubeAccountDisplayName")
            errorMessage = YouTubeOAuthError.authorizationRequired.localizedDescription
            statusMessage = L10n.string(
                "youtube.status.reconnect",
                fallback: "Reconnect the YouTube account"
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            statusMessage = L10n.string(
                "youtube.status.refreshFailed",
                fallback: "Could not refresh YouTube subscriptions"
            )
        }
    }

    private func discoverAutomaticVideos(
        configuration: YouTubeOAuthConfiguration,
        cutoff: Date
    ) async throws -> Int {
        defer {
            automaticDiscoveryFinished = true
        }
        return try await youtubeService.discoverRecentUploads(
            configuration: configuration,
            since: cutoff
        ) { [weak self] message in
            DispatchQueue.main.async { [weak self] in
                guard let self, !isAnalyzing else {
                    return
                }
                statusMessage = message
            }
        } discovered: { [weak self] videos in
            await self?.enqueueAutomaticVideos(videos)
        }
    }

    private func enqueueAutomaticVideos(_ videos: [YouTubeRecentVideo]) {
        let savedURLs = Set(records.map(\.url))
        let unseen = videos.filter {
            !savedURLs.contains($0.url.absoluteString)
                && !attemptedVideoIDs.contains($0.videoID)
        }
        guard !unseen.isEmpty else {
            return
        }

        attemptedVideoIDs.formUnion(unseen.map(\.videoID))
        automaticVideoQueue.enqueue(contentsOf: unseen)
        automaticDiscoveredCount += unseen.count
        pendingAutomaticAnalyses = automaticVideoQueue.count
            + (isAnalyzing ? 1 : 0)
    }

    private func analyzeAutomatically(_ video: YouTubeRecentVideo) async throws {
        try await analyzeAndSave(url: video.url)
    }

    private func analyzeAndSave(url: URL) async throws {
        let output = try await pipeline.analyze(
            url: url,
            settings: PipelineSettings.current
        ) { [self] message in
            DispatchQueue.main.async { [self] in
                statusMessage = message
            }
        }
        let record = AnalysisRecord(
            url: url.absoluteString,
            title: output.title,
            publishedAt: output.publishedAt,
            thumbnailURL: output.thumbnailURL,
            transcriptSource: output.transcriptSource,
            transcript: output.transcript,
            analysis: output.analysis
        )
        records.insert(record, at: 0)
        selectedRecordID = record.id
        try store.save(records)
    }

    private func completeSubscriptionRefresh(status: String) {
        let now = Date()
        lastSubscriptionRefresh = now
        UserDefaults.standard.set(now, forKey: "youtubeLastSubscriptionRefresh")
        statusMessage = status
    }

    func delete(_ record: AnalysisRecord) {
        records.removeAll(where: { $0.id == record.id })
        if selectedRecordID == record.id {
            selectedRecordID = records.first?.id
        }
        do {
            try store.save(records)
        } catch {
            errorMessage = L10n.format(
                "error.saveAfterDelete",
                fallback: "Could not save history after deletion: %@",
                error.localizedDescription
            )
        }
    }

    func copyAnalysis(_ record: AnalysisRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.analysis, forType: .string)
        statusMessage = L10n.string("status.copied", fallback: "Analysis copied")
    }

    func openVideo(_ record: AnalysisRecord) {
        guard let url = URL(string: record.url) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
