import Foundation

enum SubtitleParser {
    static func parseJSON3(data: Data) throws -> String {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let events = object["events"] as? [[String: Any]]
        else {
            throw PipelineError.invalidCaptionFile
        }

        var output: [String] = []
        var previous = ""

        for event in events {
            guard let segments = event["segs"] as? [[String: Any]] else {
                continue
            }
            let text = segments
                .compactMap { $0["utf8"] as? String }
                .joined()
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty, text != previous else {
                continue
            }
            output.append(text)
            previous = text
        }

        return output.joined(separator: "\n")
    }
}
