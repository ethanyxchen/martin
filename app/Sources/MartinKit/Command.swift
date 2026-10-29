import Foundation

enum Command {
    static func run(_ tool: String, _ arguments: [String], input: String? = nil, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let finish = Once { continuation.resume(returning: $0) }
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
                guard (try? process.run()) != nil else {
                    finish(nil)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if finish(nil), process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
                if let stdin, let input {
                    DispatchQueue.global().async {
                        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                        try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                        try? stdin.fileHandleForWriting.close()
                    }
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                finish(process.terminationReason == .exit && process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var body: ((String?) -> Void)?

    init(_ body: @escaping (String?) -> Void) {
        self.body = body
    }

    @discardableResult
    func callAsFunction(_ value: String?) -> Bool {
        let body = lock.withLock {
            defer { self.body = nil }
            return self.body
        }
        body?(value)
        return body != nil
    }
}
