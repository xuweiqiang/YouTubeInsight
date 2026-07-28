import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @FocusState private var isURLFieldFocused: Bool
    @State private var renderedHistoryCount = 0

    var body: some View {
        ZStack {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
            } detail: {
                detail
            }
            .disabled(model.environmentState != .ready)

            if model.environmentState != .ready {
                EnvironmentPreparationView(
                    state: model.environmentState,
                    message: model.environmentMessage,
                    error: model.environmentError,
                    retryAction: model.retryEnvironmentPreparation
                )
            }
        }
        .alert(
            L10n.string("error.alertTitle", fallback: "Analysis could not be completed"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button(L10n.string("action.ok", fallback: "OK")) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusURLField)) { _ in
            isURLFieldFocused = true
        }
        .task {
            model.prepareEnvironmentIfNeeded()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("history.title", fallback: "History"))
                    .font(.headline)
                Spacer()
                Text("\(model.records.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if model.records.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(L10n.string("history.emptyTitle", fallback: "No analyses yet"))
                        .font(.headline)
                    Text(L10n.string(
                        "history.emptyDescription",
                        fallback: "Completed analyses are saved here automatically"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollViewReader { proxy in
                    List(selection: $model.selectedRecordID) {
                        ForEach(model.records) { record in
                            HistoryRow(record: record)
                                .id(record.id)
                                .tag(record.id)
                                .contextMenu {
                                    Button(L10n.string("action.copyAnalysis", fallback: "Copy analysis")) {
                                        model.copyAnalysis(record)
                                    }
                                    Button(L10n.string("action.openOriginal", fallback: "Open original video")) {
                                        model.openVideo(record)
                                    }
                                    Divider()
                                    Button(
                                        L10n.string("action.delete", fallback: "Delete"),
                                        role: .destructive
                                    ) {
                                        model.delete(record)
                                    }
                                }
                        }
                    }
                    .listStyle(.sidebar)
                    .onAppear {
                        renderedHistoryCount = model.records.count
                    }
                    .onChange(of: model.records.count) { newCount in
                        let target = HistoryListScrollPolicy.target(
                            previousCount: renderedHistoryCount,
                            currentCount: newCount,
                            firstRecordID: model.records.first?.id
                        )
                        renderedHistoryCount = newCount
                        guard let target else {
                            return
                        }
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }
                }
            }

            Divider()

            Text(AppVersion.localizedDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            subscriptionBar
            Divider()
            manualInputBar
            Divider()

            if let record = model.selectedRecord {
                AnalysisDetail(
                    record: record,
                    copyAction: { model.copyAnalysis(record) },
                    openAction: { model.openVideo(record) },
                    deleteAction: { model.delete(record) }
                )
            } else {
                welcome
            }
        }
    }

    private var subscriptionBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: youtubeAccountIcon)
                    .font(.title3)
                    .foregroundStyle(youtubeAccountColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(youtubeAccountTitle)
                        .font(.headline)
                    Text(youtubeAccountDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                switch model.youtubeConnectionState {
                case .connected:
                    Button(action: model.refreshSubscriptions) {
                        Label(
                            L10n.string("youtube.refresh", fallback: "Refresh now"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(
                        model.isRefreshingSubscriptions
                            || model.isAnalyzing
                    )
                case .connecting:
                    ProgressView()
                        .controlSize(.small)
                case .disconnected:
                    Button(action: model.bindYouTubeAccount) {
                        Label(
                            L10n.string("youtube.bind", fallback: "Bind account"),
                            systemImage: "person.crop.circle.badge.plus"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                case .notConfigured:
                    settingsControl
                    .buttonStyle(.borderedProminent)
                }
            }

            if model.isRefreshingSubscriptions
                || model.isAnalyzing
                || !model.statusMessage.isEmpty {
                HStack(spacing: 7) {
                    if model.isRefreshingSubscriptions || model.isAnalyzing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if model.pendingAutomaticAnalyses > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(L10n.format(
                            "youtube.pending",
                            fallback: "%d queued",
                            model.pendingAutomaticAnalyses
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.bar)
    }

    private var manualInputBar: some View {
        HStack(spacing: 10) {
            Label(
                L10n.string("manual.title", fallback: "Manual analysis"),
                systemImage: "link"
            )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(
                L10n.string(
                    "input.placeholder",
                    fallback: "Paste a YouTube URL, for example https://www.youtube.com/watch?v=…"
                ),
                text: $model.urlInput
            )
                .textFieldStyle(.roundedBorder)
                .focused($isURLFieldFocused)
                .onSubmit {
                    model.analyzeManualURL()
                }

            Button(action: model.analyzeManualURL) {
                if model.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Label(
                        L10n.string("action.analyze", fallback: "Analyze"),
                        systemImage: "sparkles"
                    )
                }
            }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.urlInput.nilIfBlank == nil
                        || model.isAnalyzing
                        || model.isRefreshingSubscriptions
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L10n.string("welcome.title", fallback: "YouTube Video Analysis"))
                .font(.title2.weight(.semibold))
            Text(L10n.string(
                "welcome.description",
                fallback: "Bind YouTube for automatic subscription analysis, or paste any YouTube link above for a one-time manual analysis."
            ))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            switch model.youtubeConnectionState {
            case .connected:
                Button(
                    L10n.string("youtube.refresh", fallback: "Refresh now"),
                    action: model.refreshSubscriptions
                )
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRefreshingSubscriptions)
            case .disconnected:
                Button(
                    L10n.string("youtube.bind", fallback: "Bind account"),
                    action: model.bindYouTubeAccount
                )
                    .buttonStyle(.borderedProminent)
            case .notConfigured:
                settingsControl
                    .buttonStyle(.borderedProminent)
            case .connecting:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var youtubeAccountTitle: String {
        switch model.youtubeConnectionState {
        case let .connected(name):
            return name
        case .connecting:
            return L10n.string(
                "youtube.connecting",
                fallback: "Connecting YouTube account…"
            )
        case .disconnected:
            return L10n.string(
                "youtube.notConnected",
                fallback: "YouTube account not connected"
            )
        case .notConfigured:
            return L10n.string(
                "youtube.notConfigured",
                fallback: "YouTube account setup required"
            )
        }
    }

    private var youtubeAccountDescription: String {
        if let lastRefresh = model.lastSubscriptionRefresh {
            return L10n.format(
                "youtube.lastRefresh",
                fallback: "Last checked: %@",
                DateFormatter.localizedString(
                    from: lastRefresh,
                    dateStyle: .short,
                    timeStyle: .short
                )
            )
        }
        return L10n.string(
            "youtube.monitorDescription",
            fallback: "Checks the last 24 hours now and every 15 minutes while the app is running"
        )
    }

    private var youtubeAccountIcon: String {
        switch model.youtubeConnectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "person.crop.circle.badge.clock"
        case .disconnected, .notConfigured:
            return "person.crop.circle.badge.exclamationmark"
        }
    }

    private var youtubeAccountColor: Color {
        switch model.youtubeConnectionState {
        case .connected:
            return .green
        case .connecting:
            return .accentColor
        case .disconnected, .notConfigured:
            return .orange
        }
    }

    @ViewBuilder
    private var settingsControl: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label(
                    L10n.string("youtube.configure", fallback: "Set up"),
                    systemImage: "gearshape"
                )
            }
        } else {
            Button(action: openLegacySettings) {
                Label(
                    L10n.string("youtube.configure", fallback: "Set up"),
                    systemImage: "gearshape"
                )
            }
        }
    }

    private func openLegacySettings() {
        let opened = NSApp.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
        if !opened {
            NSApp.sendAction(
                Selector(("showPreferencesWindow:")),
                to: nil,
                from: nil
            )
        }
    }
}

private struct EnvironmentPreparationView: View {
    let state: EnvironmentPreparationState
    let message: String
    let error: String?
    let retryAction: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if state == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.orange)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }

                Text(L10n.string(
                    "environment.title",
                    fallback: "Preparing YouTubeInsight"
                ))
                    .font(.title2.weight(.semibold))

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .frame(maxWidth: 540)

                    Button(
                        L10n.string("action.retry", fallback: "Retry"),
                        action: retryAction
                    )
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(32)
            .frame(maxWidth: 620)
        }
    }
}

private struct VideoThumbnail: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        placeholder
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "play.rectangle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct HistoryRow: View {
    let record: AnalysisRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VideoThumbnail(
                url: record.displayThumbnailURL,
                width: 88,
                height: 50,
                cornerRadius: 6
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(record.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                if let publishedAt = record.publishedAt {
                    Label(
                        L10n.format(
                            "history.publishedAt",
                            fallback: "Published %@",
                            DateFormatter.localizedString(
                                from: publishedAt,
                                dateStyle: .medium,
                                timeStyle: .short
                            )
                        ),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text(record.analyzedAt, format: .dateTime.month().day().hour().minute())
                    Text("·")
                    Text(record.transcriptSource.localizedName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AnalysisDetail: View {
    let record: AnalysisRecord
    let copyAction: () -> Void
    let openAction: () -> Void
    let deleteAction: () -> Void
    @State private var showsTranscript = false

    private var presentation: AnalysisPresentation {
        AnalysisPresentation.parse(record.analysis)
    }

    private var renderedAnalysis: AttributedString {
        (try? AttributedString(
            markdown: record.analysis,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(record.analysis)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VideoThumbnail(
                    url: record.displayThumbnailURL,
                    width: 168,
                    height: 95,
                    cornerRadius: 9
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(record.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Label(record.transcriptSource.localizedName, systemImage: "captions.bubble")
                        Text(record.analyzedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let publishedAt = record.publishedAt {
                        Label(
                            L10n.format(
                                "history.publishedAt",
                                fallback: "Published %@",
                                DateFormatter.localizedString(
                                    from: publishedAt,
                                    dateStyle: .long,
                                    timeStyle: .short
                                )
                            ),
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: openAction) {
                    Label(
                        L10n.string("action.originalVideo", fallback: "Original"),
                        systemImage: "arrow.up.right.square"
                    )
                }
                Button(action: copyAction) {
                    Label(
                        L10n.string("action.copy", fallback: "Copy"),
                        systemImage: "doc.on.doc"
                    )
                }
                Menu {
                    Button(showsTranscript
                        ? L10n.string("action.hideTranscript", fallback: "Hide transcript")
                        : L10n.string("action.showTranscript", fallback: "Show transcript")
                    ) {
                        showsTranscript.toggle()
                    }
                    Divider()
                    Button(
                        L10n.string("action.deleteRecord", fallback: "Delete record"),
                        role: .destructive,
                        action: deleteAction
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !presentation.overview.isEmpty || !presentation.points.isEmpty {
                        if !presentation.overview.isEmpty {
                            AnalysisOverviewCard(text: presentation.overview)
                        }

                        if !presentation.points.isEmpty {
                            Text(L10n.string(
                                "analysis.heading.points",
                                fallback: "Key points"
                            ))
                                .font(.title3.weight(.semibold))

                            VStack(spacing: 10) {
                                ForEach(
                                    Array(presentation.points.enumerated()),
                                    id: \.offset
                                ) { index, point in
                                    AnalysisPointRow(
                                        number: index + 1,
                                        point: point
                                    )
                                }
                            }
                        }
                    } else {
                        Text(renderedAnalysis)
                            .textSelection(.enabled)
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showsTranscript {
                        Divider()
                        Text(L10n.string("detail.transcript", fallback: "Transcript"))
                            .font(.title3.weight(.semibold))
                        Text(record.transcript)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineSpacing(3)
                    }
                }
                .frame(maxWidth: 850, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct AnalysisOverviewCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                L10n.string("analysis.heading.overview", fallback: "Overview"),
                systemImage: "lightbulb.fill"
            )
                .font(.headline)
                .foregroundStyle(.tint)

            Text(text)
                .font(.title3.weight(.medium))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.accentColor.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct AnalysisPointRow: View {
    let number: Int
    let point: AnalysisPoint

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                if let title = point.title {
                    Text(title)
                        .font(.headline)
                }
                Text(point.detail)
                    .font(.body)
                    .foregroundStyle(point.title == nil ? .primary : .secondary)
                    .lineSpacing(2)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("codexModel") private var codexModel = "gpt-5.6-sol"
    @AppStorage("codexCustomModel") private var codexCustomModel = ""
    @AppStorage("codexReasoningEffort")
    private var codexReasoningEffort = CodexReasoningEffort.medium.rawValue
    @AppStorage("whisperModel") private var whisperModel =
        "mlx-community/whisper-large-v3-turbo"
    @AppStorage(YouTubeOAuthConfiguration.clientIDKey)
    private var youtubeClientID = ""
    @AppStorage(YouTubeOAuthConfiguration.clientSecretKey)
    private var youtubeClientSecret = ""
    @State private var credentialMessage: String?
    @State private var credentialMessageIsError = false

    var body: some View {
        Form {
            Section(L10n.string(
                "youtube.oauthSection",
                fallback: "YouTube account"
            )) {
                TextField(
                    L10n.string("youtube.clientID", fallback: "OAuth client ID"),
                    text: $youtubeClientID
                )
                SecureField(
                    L10n.string(
                        "youtube.clientSecret",
                        fallback: "OAuth client secret (optional)"
                    ),
                    text: $youtubeClientSecret
                )

                HStack {
                    Button(
                        L10n.string(
                            "youtube.importJSON",
                            fallback: "Import OAuth JSON…"
                        ),
                        action: importOAuthCredentials
                    )

                    Spacer()

                    switch model.youtubeConnectionState {
                    case let .connected(name):
                        Label(name, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button(
                            L10n.string("youtube.disconnect", fallback: "Disconnect"),
                            role: .destructive,
                            action: model.disconnectYouTubeAccount
                        )
                    case .connecting:
                        ProgressView()
                            .controlSize(.small)
                    case .disconnected, .notConfigured:
                        Button(
                            L10n.string("youtube.bind", fallback: "Bind account"),
                            action: model.bindYouTubeAccount
                        )
                            .buttonStyle(.borderedProminent)
                            .disabled(youtubeClientID.nilIfBlank == nil)
                    }
                }

                if let credentialMessage {
                    Text(credentialMessage)
                        .font(.caption)
                        .foregroundStyle(
                            credentialMessageIsError ? Color.red : Color.green
                        )
                }

                Text(L10n.string(
                    "youtube.oauthDescription",
                    fallback: "Create a Desktop app OAuth client in Google Cloud, enable YouTube Data API v3, then import the downloaded JSON. Tokens are kept in macOS Keychain and only read-only YouTube access is requested."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(
                    L10n.string(
                        "youtube.openGoogleCloud",
                        fallback: "Open Google Cloud credentials"
                    ),
                    destination: URL(
                        string: "https://console.cloud.google.com/apis/credentials"
                    )!
                )
            }

            Section(L10n.string("settings.analysisSection", fallback: "Analysis model")) {
                Picker(
                    L10n.string("settings.codexModel", fallback: "Codex model"),
                    selection: codexModelSelection
                ) {
                    ForEach(CodexModelOption.allCases) { option in
                        Text(option.localizedName)
                            .tag(option)
                    }
                }

                if codexModelSelection.wrappedValue == .custom {
                    TextField(
                        L10n.string(
                            "settings.codexCustomModelID",
                            fallback: "Custom model ID"
                        ),
                        text: customCodexModelBinding
                    )
                }

                Picker(
                    L10n.string(
                        "settings.codexReasoningEffort",
                        fallback: "Reasoning effort"
                    ),
                    selection: $codexReasoningEffort
                ) {
                    ForEach(CodexReasoningEffort.allCases) { effort in
                        Text(effort.localizedName)
                            .tag(effort.rawValue)
                    }
                }

                Text(L10n.string(
                    "settings.codexDescription",
                    fallback: "Sol favors depth and polish, Terra balances speed and quality, and Luna suits repeatable summaries. Higher reasoning effort can improve difficult analyses but takes longer and may use more tokens. Availability depends on the signed-in Codex account."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.transcriptionSection", fallback: "Speech recognition")) {
                Picker(
                    L10n.string("settings.whisperModel", fallback: "Whisper model"),
                    selection: $whisperModel
                ) {
                    Text(L10n.string(
                        "settings.whisperHighQuality",
                        fallback: "High quality · large-v3-turbo"
                    ))
                        .tag("mlx-community/whisper-large-v3-turbo")
                    Text(L10n.string("settings.whisperFaster", fallback: "Faster · small"))
                        .tag("mlx-community/whisper-small-mlx")
                    Text(L10n.string("settings.whisperFastest", fallback: "Fastest · tiny"))
                        .tag("mlx-community/whisper-tiny-mlx")
                }
                Text(L10n.string(
                    "settings.whisperDescription",
                    fallback: "The selected model downloads the first time a video without captions is analyzed, then remains cached locally."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 640, height: 620)
    }

    private var codexModelSelection: Binding<CodexModelOption> {
        Binding(
            get: {
                CodexModelOption.selection(for: codexModel)
            },
            set: { option in
                codexModel = option.rawValue
            }
        )
    }

    private var customCodexModelBinding: Binding<String> {
        Binding(
            get: {
                if codexModel != CodexModelOption.custom.rawValue,
                   CodexModelOption(rawValue: codexModel) == nil {
                    return codexModel
                }
                return codexCustomModel
            },
            set: { value in
                codexCustomModel = value
                codexModel = CodexModelOption.custom.rawValue
            }
        )
    }

    private func importOAuthCredentials() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.string(
            "youtube.importPrompt",
            fallback: "Choose the OAuth desktop credential JSON downloaded from Google Cloud."
        )
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let configuration = try YouTubeOAuthConfiguration.imported(
                from: Data(contentsOf: url)
            )
            youtubeClientID = configuration.clientID
            youtubeClientSecret = configuration.clientSecret
            credentialMessageIsError = false
            credentialMessage = L10n.string(
                "youtube.importSuccess",
                fallback: "OAuth credentials imported. You can now bind the account."
            )
        } catch {
            credentialMessageIsError = true
            credentialMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
