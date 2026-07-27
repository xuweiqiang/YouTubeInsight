import AppKit
import Foundation

enum EnvironmentPreparationState: Equatable {
    case idle
    case preparing
    case ready
    case failed
}

@MainActor
final class AppModel: ObservableObject {
    @Published var urlInput = ""
    @Published var records: [AnalysisRecord]
    @Published var selectedRecordID: UUID?
    @Published var isAnalyzing = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published private(set) var environmentState: EnvironmentPreparationState = .idle
    @Published private(set) var environmentMessage = ""
    @Published private(set) var environmentError: String?

    private let store: HistoryStore
    private let pipeline: AnalysisPipeline
    private let runtimeEnvironment: RuntimeEnvironment

    init(
        store: HistoryStore = HistoryStore(),
        pipeline: AnalysisPipeline = AnalysisPipeline(),
        runtimeEnvironment: RuntimeEnvironment = RuntimeEnvironment()
    ) {
        self.store = store
        self.pipeline = pipeline
        self.runtimeEnvironment = runtimeEnvironment
        let loaded = store.load()
        records = loaded
        selectedRecordID = loaded.first?.id
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

    func analyze() {
        guard !isAnalyzing else {
            return
        }
        guard environmentState == .ready else {
            errorMessage = environmentError ?? L10n.string(
                "environment.notReady",
                fallback: "The runtime environment is not ready. Retry the startup check."
            )
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
        statusMessage = L10n.string("status.preparing", fallback: "Preparing analysis…")
        errorMessage = nil
        let settings = PipelineSettings.current

        Task {
            do {
                let output = try await pipeline.analyze(
                    url: url,
                    settings: settings
                ) { [weak self] message in
                    DispatchQueue.main.async {
                        self?.statusMessage = message
                    }
                }

                let record = AnalysisRecord(
                    url: url.absoluteString,
                    title: output.title,
                    transcriptSource: output.transcriptSource,
                    transcript: output.transcript,
                    analysis: output.analysis
                )
                records.insert(record, at: 0)
                selectedRecordID = record.id
                urlInput = ""
                try store.save(records)
                statusMessage = L10n.string(
                    "status.completeSaved",
                    fallback: "Analysis complete and saved"
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                statusMessage = L10n.string("status.failed", fallback: "Analysis failed")
            }
            isAnalyzing = false
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
                try await runtimeEnvironment.prepare { [weak self] message in
                    DispatchQueue.main.async {
                        self?.environmentMessage = message
                    }
                }
                environmentMessage = L10n.string(
                    "environment.ready",
                    fallback: "Runtime environment is ready"
                )
                environmentState = .ready
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
