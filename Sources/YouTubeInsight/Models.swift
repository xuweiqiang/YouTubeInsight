import Foundation

struct AnalysisRecord: Identifiable, Codable, Hashable {
    enum TranscriptSource: String, Codable {
        case youtubeCaptions = "YouTube 字幕"
        case localWhisper = "本地 Whisper"

        var localizedName: String {
            switch self {
            case .youtubeCaptions:
                return L10n.string(
                    "source.youtubeCaptions",
                    fallback: "YouTube captions"
                )
            case .localWhisper:
                return L10n.string(
                    "source.localWhisper",
                    fallback: "Local Whisper"
                )
            }
        }
    }

    let id: UUID
    let url: String
    let title: String
    let analyzedAt: Date
    let transcriptSource: TranscriptSource
    let transcript: String
    let analysis: String

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        analyzedAt: Date = Date(),
        transcriptSource: TranscriptSource,
        transcript: String,
        analysis: String
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.analyzedAt = analyzedAt
        self.transcriptSource = transcriptSource
        self.transcript = transcript
        self.analysis = analysis
    }
}

struct AnalysisOutput {
    let title: String
    let transcript: String
    let transcriptSource: AnalysisRecord.TranscriptSource
    let analysis: String
}

struct PipelineSettings {
    let codexModel: String
    let whisperModel: String

    static var current: PipelineSettings {
        let defaults = UserDefaults.standard
        return PipelineSettings(
            codexModel: defaults.string(forKey: "codexModel")?.nilIfBlank ?? "gpt-5.6-sol",
            whisperModel: defaults.string(forKey: "whisperModel")?.nilIfBlank
                ?? "mlx-community/whisper-large-v3-turbo"
        )
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
