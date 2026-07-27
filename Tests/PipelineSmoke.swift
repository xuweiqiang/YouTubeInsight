import Foundation

@main
struct PipelineSmoke {
    static func main() async {
        let input = CommandLine.arguments.dropFirst().first
            ?? "https://www.youtube.com/watch?v=XYgm-dNNrR8"
        guard let url = YouTubeURLParser.canonicalURL(from: input) else {
            fputs("Invalid YouTube URL.\n", stderr)
            Foundation.exit(2)
        }

        do {
            let output = try await AnalysisPipeline().analyze(
                url: url,
                settings: .current
            ) { message in
                print("[progress] \(message)")
            }
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
