import Foundation

struct AnalysisPoint: Equatable {
    let title: String?
    let detail: String
}

struct AnalysisPresentation: Equatable {
    let overview: String
    let points: [AnalysisPoint]

    static func parse(_ input: String) -> AnalysisPresentation {
        let lines = input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var overviewLines: [String] = []
        var pointLines: [String] = []
        var hasReachedPoints = false

        for line in lines {
            if line.hasPrefix("#") {
                continue
            }
            if let item = listItem(from: line) {
                hasReachedPoints = true
                pointLines.append(item)
            } else if !hasReachedPoints {
                overviewLines.append(cleanMarkdown(line))
            }
        }

        let points = pointLines
            .prefix(5)
            .map(makePoint)
        let overview = overviewLines
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AnalysisPresentation(
            overview: overview,
            points: points
        )
    }

    private static func listItem(from line: String) -> String? {
        let numberedPattern = #"^\s*\d+[\.\)]\s+"#
        if let range = line.range(
            of: numberedPattern,
            options: .regularExpression
        ) {
            return cleanMarkdown(String(line[range.upperBound...]))
        }

        for prefix in ["- ", "• ", "* "] where line.hasPrefix(prefix) {
            return cleanMarkdown(String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func makePoint(_ input: String) -> AnalysisPoint {
        for separator in [" — ", " – ", "：", ": "] {
            let parts = input.components(separatedBy: separator)
            guard parts.count > 1 else {
                continue
            }
            let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = parts.dropFirst()
                .joined(separator: separator)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !detail.isEmpty {
                return AnalysisPoint(title: title, detail: detail)
            }
        }
        return AnalysisPoint(title: nil, detail: input)
    }

    private static func cleanMarkdown(_ input: String) -> String {
        input
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
