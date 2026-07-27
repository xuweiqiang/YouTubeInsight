import Foundation

enum WhisperTranscript {
    static func read(from url: URL) throws -> String {
        guard
            let text = try? String(contentsOf: url, encoding: .utf8),
            let transcript = text.nilIfBlank
        else {
            throw PipelineError.emptyTranscript
        }
        return transcript
    }
}
