import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @FocusState private var isURLFieldFocused: Bool

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
        .onAppear {
            if model.records.isEmpty && model.environmentState == .ready {
                isURLFieldFocused = true
            }
        }
        .onChange(of: model.environmentState) { state in
            if state == .ready && model.records.isEmpty {
                isURLFieldFocused = true
            }
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
                List(selection: $model.selectedRecordID) {
                    ForEach(model.records) { record in
                        HistoryRow(record: record)
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
            inputBar
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

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField(
                    L10n.string(
                        "input.placeholder",
                        fallback: "Paste a YouTube URL, for example https://www.youtube.com/watch?v=…"
                    ),
                    text: $model.urlInput
                )
                .textFieldStyle(.plain)
                .focused($isURLFieldFocused)
                .onSubmit {
                    model.analyze()
                }

                Button {
                    model.analyze()
                } label: {
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
                .disabled(model.isAnalyzing || model.urlInput.nilIfBlank == nil)
            }

            if model.isAnalyzing || !model.statusMessage.isEmpty {
                HStack(spacing: 7) {
                    if model.isAnalyzing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.bar)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L10n.string("welcome.title", fallback: "YouTube Video Analysis"))
                .font(.title2.weight(.semibold))
            Text(L10n.string(
                "welcome.description",
                fallback: "Enter a video URL. The app uses available captions first, then downloads audio and transcribes it locally with Whisper when needed."
            ))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button(L10n.string("action.enterURL", fallback: "Enter URL")) {
                isURLFieldFocused = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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

private struct HistoryRow: View {
    let record: AnalysisRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.title)
                .font(.body.weight(.medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(record.analyzedAt, format: .dateTime.month().day().hour().minute())
                Text("·")
                Text(record.transcriptSource.localizedName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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

    private var renderedAnalysis: AttributedString {
        (try? AttributedString(
            markdown: record.analysis,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(record.analysis)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
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
                    Text(renderedAnalysis)
                        .textSelection(.enabled)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)

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

struct SettingsView: View {
    @AppStorage("codexModel") private var codexModel = "gpt-5.6-sol"
    @AppStorage("whisperModel") private var whisperModel =
        "mlx-community/whisper-large-v3-turbo"

    var body: some View {
        Form {
            Section(L10n.string("settings.analysisSection", fallback: "Analysis model")) {
                TextField(
                    L10n.string("settings.codexModel", fallback: "Codex model"),
                    text: $codexModel
                )
                Text(L10n.string(
                    "settings.codexDescription",
                    fallback: "Uses the Codex CLI already signed in on this Mac. Account credentials are not stored by the app."
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
        .frame(width: 520, height: 300)
    }
}
