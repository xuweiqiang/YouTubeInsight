import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var urlInput = ""
    @Published var records: [AnalysisRecord]
    @Published var selectedRecordID: UUID?
    @Published var isAnalyzing = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?

    private let store: HistoryStore
    private let pipeline: AnalysisPipeline

    init(
        store: HistoryStore = HistoryStore(),
        pipeline: AnalysisPipeline = AnalysisPipeline()
    ) {
        self.store = store
        self.pipeline = pipeline
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

    func analyze() {
        guard !isAnalyzing else {
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
