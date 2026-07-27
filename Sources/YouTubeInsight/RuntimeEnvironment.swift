import Foundation

enum RuntimeEnvironmentError: LocalizedError {
    case repairFailed(String, String)
    case manualActionRequired(String)

    var errorDescription: String? {
        switch self {
        case let .repairFailed(component, details):
            return L10n.format(
                "environment.repairFailed",
                fallback: "Could not prepare %@: %@",
                component,
                details
            )
        case let .manualActionRequired(details):
            return details
        }
    }
}

final class RuntimeEnvironment: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (String) -> Void

    private let runner: ProcessRunner
    private let fileManager: FileManager

    init(
        runner: ProcessRunner = ProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.fileManager = fileManager
    }

    func prepare(progress: @escaping ProgressHandler) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.prepareSynchronously(progress: progress)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func whisperEnvironment(
        repairProgress: ProgressHandler? = nil
    ) throws -> [String: String] {
        repairProgress?(checking("ffmpeg"))

        if let ffmpeg = CommandLocator.locate("ffmpeg"),
           isHealthy(executable: ffmpeg, arguments: ["-version"]) {
            return environment(
                prepending: URL(fileURLWithPath: ffmpeg).deletingLastPathComponent()
            )
        }

        let toolDirectory = applicationToolDirectory
        let linkURL = toolDirectory.appendingPathComponent("ffmpeg")
        if fileManager.isExecutableFile(atPath: linkURL.path),
           isHealthy(executable: linkURL.path, arguments: ["-version"]) {
            return environment(prepending: toolDirectory)
        }

        repairProgress?(repairing("ffmpeg"))
        guard let uv = CommandLocator.locate("uv"),
              isHealthy(executable: uv, arguments: ["--version"]) else {
            throw RuntimeEnvironmentError.repairFailed(
                "ffmpeg",
                L10n.string(
                    "guidance.installUV",
                    fallback: "Run: brew install uv"
                )
            )
        }

        let result = try runner.run(
            executable: uv,
            arguments: [
                "run",
                "--with", "imageio-ffmpeg",
                "python",
                "-c",
                "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"
            ]
        )
        guard
            result.succeeded,
            let staticPath = result.standardOutput
                .split(separator: "\n")
                .map(String.init)
                .last?
                .nilIfBlank
        else {
            throw RuntimeEnvironmentError.repairFailed(
                "ffmpeg",
                errorDetails(from: result)
            )
        }

        try fileManager.createDirectory(
            at: toolDirectory,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: linkURL.path) {
            try fileManager.removeItem(at: linkURL)
        }
        try fileManager.createSymbolicLink(
            at: linkURL,
            withDestinationURL: URL(fileURLWithPath: staticPath)
        )

        guard isHealthy(executable: linkURL.path, arguments: ["-version"]) else {
            throw RuntimeEnvironmentError.repairFailed(
                "ffmpeg",
                L10n.string("error.unknown", fallback: "Unknown error")
            )
        }
        return environment(prepending: toolDirectory)
    }

    private func prepareSynchronously(
        progress: @escaping ProgressHandler
    ) throws {
        try ensureBrewFormula(
            command: "uv",
            formula: "uv",
            arguments: ["--version"],
            progress: progress
        )
        try ensureBrewFormula(
            command: "uvx",
            formula: "uv",
            arguments: ["--version"],
            progress: progress
        )
        try ensureBrewFormula(
            command: "node",
            formula: "node",
            arguments: ["--version"],
            progress: progress
        )
        try ensureCodex(progress: progress)
        _ = try whisperEnvironment(repairProgress: progress)
        try ensureUVTool(
            name: "yt-dlp",
            package: "yt-dlp",
            arguments: ["--from", "yt-dlp", "yt-dlp", "--version"],
            progress: progress
        )
        try ensureUVTool(
            name: "MLX Whisper",
            package: "mlx-whisper",
            arguments: ["--from", "mlx-whisper", "mlx_whisper", "--help"],
            progress: progress
        )
    }

    private func ensureBrewFormula(
        command: String,
        formula: String,
        arguments: [String],
        progress: ProgressHandler
    ) throws {
        progress(checking(command))
        if let executable = CommandLocator.locate(command),
           isHealthy(executable: executable, arguments: arguments) {
            return
        }

        progress(repairing(command))
        guard let brew = CommandLocator.locate("brew"),
              isHealthy(executable: brew, arguments: ["--version"]) else {
            throw RuntimeEnvironmentError.repairFailed(
                command,
                L10n.string(
                    "environment.homebrewRequired",
                    fallback: "Install Homebrew, then retry."
                )
            )
        }

        let installed = try runner.run(
            executable: brew,
            arguments: ["list", "--formula", formula]
        ).succeeded
        let result = try runner.run(
            executable: brew,
            arguments: [installed ? "reinstall" : "install", formula]
        )
        guard
            let executable = CommandLocator.locate(command),
            isHealthy(executable: executable, arguments: arguments)
        else {
            throw RuntimeEnvironmentError.repairFailed(
                command,
                errorDetails(from: result)
            )
        }
    }

    private func ensureCodex(progress: ProgressHandler) throws {
        progress(checking("Codex CLI"))
        var codex = CommandLocator.locate("codex")
        let codexIsHealthy = codex.map {
            isHealthy(executable: $0, arguments: ["--version"])
        } ?? false
        if !codexIsHealthy {
            progress(repairing("Codex CLI"))
            try ensureBrewFormula(
                command: "npm",
                formula: "node",
                arguments: ["--version"],
                progress: progress
            )
            guard let npm = CommandLocator.locate("npm"),
                  isHealthy(executable: npm, arguments: ["--version"]) else {
                throw RuntimeEnvironmentError.repairFailed(
                    "Codex CLI",
                    L10n.string(
                        "environment.npmRequired",
                        fallback: "Node.js and npm are required to install Codex CLI."
                    )
                )
            }
            let result = try runner.run(
                executable: npm,
                arguments: ["install", "-g", "@openai/codex@latest"]
            )
            codex = CommandLocator.locate("codex")
            guard result.succeeded,
                  let codex,
                  isHealthy(executable: codex, arguments: ["--version"]) else {
                throw RuntimeEnvironmentError.repairFailed(
                    "Codex CLI",
                    errorDetails(from: result)
                )
            }
        }

        guard let codex else {
            throw RuntimeEnvironmentError.repairFailed(
                "Codex CLI",
                L10n.string("error.unknown", fallback: "Unknown error")
            )
        }
        let loginStatus = try runner.run(
            executable: codex,
            arguments: ["login", "status"]
        )
        guard loginStatus.succeeded else {
            throw RuntimeEnvironmentError.manualActionRequired(
                L10n.string(
                    "environment.codexLoginRequired",
                    fallback: "Codex CLI is installed but not signed in. Run codex login in Terminal, then retry."
                )
            )
        }
    }

    private func ensureUVTool(
        name: String,
        package: String,
        arguments: [String],
        progress: ProgressHandler
    ) throws {
        progress(checking(name))
        guard let uvx = CommandLocator.locate("uvx") else {
            throw RuntimeEnvironmentError.repairFailed(
                name,
                L10n.string("guidance.installUV", fallback: "Run: brew install uv")
            )
        }

        if isHealthy(executable: uvx, arguments: arguments) {
            return
        }

        progress(repairing(name))
        let repairArguments = ["--refresh-package", package] + arguments
        let result = try runner.run(
            executable: uvx,
            arguments: repairArguments
        )
        guard result.succeeded else {
            throw RuntimeEnvironmentError.repairFailed(
                name,
                errorDetails(from: result)
            )
        }
    }

    private func isHealthy(
        executable: String,
        arguments: [String]
    ) -> Bool {
        guard let result = try? runner.run(
            executable: executable,
            arguments: arguments
        ) else {
            return false
        }
        return result.succeeded
    }

    private var applicationToolDirectory: URL {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return supportDirectory
            .appendingPathComponent("YouTubeInsight", isDirectory: true)
            .appendingPathComponent("tools", isDirectory: true)
    }

    private func environment(prepending directory: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existing = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "\(directory.path):\(existing)"
        return environment
    }

    private func checking(_ component: String) -> String {
        L10n.format(
            "environment.checkingComponent",
            fallback: "Checking %@…",
            component
        )
    }

    private func repairing(_ component: String) -> String {
        L10n.format(
            "environment.repairingComponent",
            fallback: "Repairing %@…",
            component
        )
    }

    private func errorDetails(from result: ProcessResult) -> String {
        let error = result.standardError.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let output = result.standardOutput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let details = [error, output]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !details.isEmpty else {
            return L10n.string("error.unknown", fallback: "Unknown error")
        }
        return String(details.suffix(2_000))
    }
}
