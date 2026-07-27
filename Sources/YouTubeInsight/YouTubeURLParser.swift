import Foundation

enum YouTubeURLParser {
    static func canonicalURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let host = url.host?.lowercased()
        else {
            return nil
        }

        let allowedHosts = [
            "youtube.com",
            "www.youtube.com",
            "m.youtube.com",
            "music.youtube.com",
            "youtu.be"
        ]
        guard allowedHosts.contains(host) else {
            return nil
        }

        let videoID: String?
        if host == "youtu.be" {
            videoID = url.pathComponents.dropFirst().first
        } else if url.path == "/watch" {
            videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value
        } else if url.path.hasPrefix("/shorts/") || url.path.hasPrefix("/live/") {
            videoID = url.pathComponents.dropFirst().dropFirst().first
        } else {
            videoID = nil
        }

        guard let videoID, isValidVideoID(videoID) else {
            return nil
        }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        guard value.count == 11 else {
            return false
        }
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
