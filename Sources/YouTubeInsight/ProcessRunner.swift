import Foundation

struct ProcessResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool {
        exitCode == 0
    }
}

struct ProcessRunner {
    private let fileManager = FileManager.default

    func run(
        executable: String,
        arguments: [String],
        input: String? = nil,
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment ?? ProcessInfo.processInfo.environment

        let scratchDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("YouTubeInsight-Process-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: scratchDirectory)
        }

        let outputURL = scratchDirectory.appendingPathComponent("stdout")
        let errorURL = scratchDirectory.appendingPathComponent("stderr")
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        fileManager.createFile(atPath: errorURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        var inputPipe: Pipe?
        if input != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inputPipe = pipe
        }

        do {
            try process.run()
        } catch {
            try? outputHandle.close()
            try? errorHandle.close()
            throw PipelineError.processLaunchFailed(executable, error.localizedDescription)
        }

        if let input, let data = input.data(using: .utf8) {
            inputPipe?.fileHandleForWriting.write(data)
            try? inputPipe?.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        try? outputHandle.close()
        try? errorHandle.close()

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let error = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: output,
            standardError: error
        )
    }
}

enum CommandLocator {
    static func locate(_ command: String) -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        let directories = pathEntries + [
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        for directory in Array(NSOrderedSet(array: directories)) as? [String] ?? directories {
            let path = URL(fileURLWithPath: directory)
                .appendingPathComponent(command)
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
