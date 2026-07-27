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
    let codexReasoningEffort: String
    let whisperModel: String

    static var current: PipelineSettings {
        let defaults = UserDefaults.standard
        let selectedModel = defaults.string(forKey: "codexModel")?.nilIfBlank
            ?? "gpt-5.6-sol"
        let customModel = defaults.string(forKey: "codexCustomModel")?.nilIfBlank
        return PipelineSettings(
            codexModel: resolvedCodexModel(
                selected: selectedModel,
                custom: customModel
            ),
            codexReasoningEffort: resolvedReasoningEffort(
                defaults.string(forKey: "codexReasoningEffort")
            ),
            whisperModel: defaults.string(forKey: "whisperModel")?.nilIfBlank
                ?? "mlx-community/whisper-large-v3-turbo"
        )
    }

    static func resolvedCodexModel(
        selected: String,
        custom: String?
    ) -> String {
        if selected == CodexModelOption.custom.rawValue {
            return custom?.nilIfBlank ?? CodexModelOption.sol.modelID
        }
        return selected.nilIfBlank ?? CodexModelOption.sol.modelID
    }

    static func resolvedReasoningEffort(_ value: String?) -> String {
        CodexReasoningEffort(rawValue: value ?? "")?.rawValue
            ?? CodexReasoningEffort.medium.rawValue
    }
}

enum CodexModelOption: String, CaseIterable, Identifiable {
    case sol = "gpt-5.6-sol"
    case terra = "gpt-5.6-terra"
    case luna = "gpt-5.6-luna"
    case custom

    var id: String { rawValue }

    var modelID: String {
        switch self {
        case .sol: return "gpt-5.6-sol"
        case .terra: return "gpt-5.6-terra"
        case .luna: return "gpt-5.6-luna"
        case .custom: return "custom"
        }
    }

    var localizedName: String {
        switch self {
        case .sol:
            return L10n.string(
                "settings.codexModelSol",
                fallback: "Sol · Deep analysis and polish"
            )
        case .terra:
            return L10n.string(
                "settings.codexModelTerra",
                fallback: "Terra · Balanced and faster"
            )
        case .luna:
            return L10n.string(
                "settings.codexModelLuna",
                fallback: "Luna · Efficient structured summaries"
            )
        case .custom:
            return L10n.string(
                "settings.codexModelCustom",
                fallback: "Custom model"
            )
        }
    }

    static func selection(for storedModel: String) -> CodexModelOption {
        CodexModelOption(rawValue: storedModel) ?? .custom
    }
}

enum CodexReasoningEffort: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .low:
            return L10n.string("settings.effort.low", fallback: "Low · Fastest")
        case .medium:
            return L10n.string("settings.effort.medium", fallback: "Medium · Balanced")
        case .high:
            return L10n.string("settings.effort.high", fallback: "High · Deeper")
        case .xhigh:
            return L10n.string("settings.effort.xhigh", fallback: "Extra High")
        case .max:
            return L10n.string("settings.effort.max", fallback: "Max")
        case .ultra:
            return L10n.string("settings.effort.ultra", fallback: "Ultra")
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
