import Foundation

final class HistoryStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let supportDirectory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.fileURL = supportDirectory
                .appendingPathComponent("YouTubeInsight", isDirectory: true)
                .appendingPathComponent("history.json")
        }
    }

    func load() -> [AnalysisRecord] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([AnalysisRecord].self, from: data))?
            .sorted { $0.analyzedAt > $1.analyzedAt } ?? []
    }

    func save(_ records: [AnalysisRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
