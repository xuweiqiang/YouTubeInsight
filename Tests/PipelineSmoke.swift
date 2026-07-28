import Foundation

@main
struct PipelineSmoke {
    static func main() async {
        let input = CommandLine.arguments.dropFirst().first
            ?? "https://www.youtube.com/watch?v=XYgm-dNNrR8"
        if input == "--environment-only" {
            do {
                try await RuntimeEnvironment().prepare { message in
                    print("[environment] \(message)")
                }
                print("[environment] ready")
            } catch {
                fputs("Environment preparation failed: \(error.localizedDescription)\n", stderr)
                Foundation.exit(1)
            }
            return
        }

        guard let url = YouTubeURLParser.canonicalURL(from: input) else {
            fputs("Invalid YouTube URL.\n", stderr)
            Foundation.exit(2)
        }

        do {
            let startedAt = ProcessInfo.processInfo.systemUptime
            let currentSettings = PipelineSettings.current
            let settings = PipelineSettings(
                codexModel: currentSettings.codexModel,
                codexReasoningEffort: currentSettings.codexReasoningEffort,
                whisperModel: ProcessInfo.processInfo.environment[
                    "YOUTUBEINSIGHT_SMOKE_WHISPER_MODEL"
                ]?.nilIfBlank ?? currentSettings.whisperModel
            )
            let output = try await AnalysisPipeline().analyze(
                url: url,
                settings: settings
            ) { message in
                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                print(String(format: "[progress +%.3fs] %@", elapsed, message))
            }
            let total = ProcessInfo.processInfo.systemUptime - startedAt
            print(String(format: "[total] %.3fs", total))
            print("[title] \(output.title)")
            print("[source] \(output.transcriptSource.rawValue)")
            print("[transcript characters] \(output.transcript.count)")
            print("[analysis characters] \(output.analysis.count)")
            print(output.analysis)
        } catch {
            fputs("Pipeline failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}
