import Foundation

enum AnalysisFormatter {
    static func capped(_ input: String, maxCharacters: Int = 500) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard maxCharacters > 1, trimmed.count > maxCharacters else {
            return trimmed
        }

        let prefix = String(trimmed.prefix(maxCharacters - 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }
}
