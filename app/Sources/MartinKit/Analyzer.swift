import Foundation

public enum Analyzer {
    struct Input: Encodable {
        struct Owner: Encodable { let name: String; let aliases: [String] }
        struct MeetingInfo: Encodable { let title: String?; let startedAt: Date; let attendees: [String]; let notes: String? }
        struct Line: Encodable { let at: Double; let text: String }
        let owner: Owner
        let meeting: MeetingInfo
        let transcript: [Line]
    }

    public struct Source: Decodable, Sendable, Hashable, Identifiable {
        public let name: String
        public let status: String
        public let detail: String?

        public var id: String { name }
        public var connected: Bool { status == "connected" }
    }

    public struct Failure: LocalizedError {
        public let errorDescription: String?
    }

    public static func note(for meeting: Meeting, transcript: [Segment], settings: Settings) async throws -> String {
        let input = Input(
            owner: .init(name: settings.name, aliases: settings.aliases),
            meeting: .init(title: meeting.title, startedAt: meeting.startedAt, attendees: meeting.attendees, notes: meeting.calendarNotes),
            transcript: transcript.map { .init(at: $0.at, text: $0.text) }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try await run(arguments: [], input: encoder.encode(input))
    }

    public static func sources() async throws -> [Source] {
        try JSONDecoder().decode([Source].self, from: Data(await run(arguments: ["sources"], input: Data()).utf8))
    }

    static var executable: URL {
        if let path = ProcessInfo.processInfo.environment["MARTIN_ANALYZER"] { return URL(filePath: path) }
        return Bundle.main.url(forResource: "martin-analyzer", withExtension: nil) ?? URL(filePath: "/usr/bin/false")
    }

    static func run(arguments: [String], input: Data) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: input)
        try stdin.fileHandleForWriting.close()
        async let output = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
        async let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value
        let (out, err) = await (output, errors)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(errorDescription: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: out, as: UTF8.self)
    }
}
