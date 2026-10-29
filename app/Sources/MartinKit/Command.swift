import Foundation

enum Command {
    static func run(_ tool: String, _ arguments: [String], input: String? = nil) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(filePath: "/usr/bin/env")
                process.arguments = [tool] + arguments
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = [environment["PATH"], "/opt/homebrew/bin", "/usr/local/bin", URL.homeDirectory.appending(path: ".local/bin").path(percentEncoded: false)]
                    .compactMap(\.self).joined(separator: ":")
                process.environment = environment
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                let stdin = input.map { _ in Pipe() }
                process.standardInput = stdin ?? FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }
                if let stdin, let input {
                    DispatchQueue.global().async {
                        stdin.fileHandleForWriting.write(Data(input.utf8))
                        try? stdin.fileHandleForWriting.close()
                    }
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }
}
