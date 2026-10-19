import Foundation

enum GitHubCLI {
    static func token() async -> String? {
        await Task.detached {
            guard let executable = executable() else { return nil }
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return process.terminationStatus == 0 && !token.isEmpty ? token : nil
        }.value
    }

    private static func executable() -> URL? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(filePath: $0) }
    }
}
