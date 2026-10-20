import Foundation

public enum Analyzer {
    struct Input: Encodable {
        struct Owner: Encodable { let name: String; let aliases: [String]; let interests: [String] }
        struct MeetingInfo: Encodable { let title: String?; let attendees: [String]; let notes: String? }
        let owner: Owner
        let meeting: MeetingInfo
        let work: [PullRequest]
        let transcript: [String]
        let bullets: [Bullet]
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

    public static func work(since: Date) async throws -> [PullRequest] {
        try decoder.decode([PullRequest].self, from: await run(arguments: ["work", since.formatted(.iso8601)], input: Data()))
    }

    public static func listen(meeting: Meeting, work: [PullRequest], transcript: [Segment], bullets: [Bullet], settings: Settings) async throws -> [Bullet] {
        let input = Input(
            owner: .init(name: settings.name, aliases: settings.aliases, interests: settings.keyterms),
            meeting: .init(title: meeting.title, attendees: meeting.attendees, notes: meeting.calendarNotes),
            work: work,
            transcript: transcript.map(\.text),
            bullets: bullets
        )
        return try decoder.decode([Bullet].self, from: await run(arguments: ["listen"], input: encoder.encode(input)))
    }

    public static func sources() async throws -> [Source] {
        try decoder.decode([Source].self, from: await run(arguments: ["sources"], input: Data()))
    }

    static var executable: URL {
        if let path = ProcessInfo.processInfo.environment["MARTIN_ANALYZER"] { return URL(filePath: path) }
        return Bundle.main.url(forResource: "martin-analyzer", withExtension: nil) ?? URL(filePath: "/usr/bin/false")
    }

    static func run(arguments: [String], input: Data) async throws -> Data {
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
        return out
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
