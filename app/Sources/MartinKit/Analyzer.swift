import Foundation

public enum Analyzer {
    struct Input: Encodable {
        struct Owner: Encodable { let name: String; let aliases: [String] }
        struct MeetingInfo: Encodable { let title: String?; let startedAt: Date; let attendees: [String]; let notes: String? }
        struct Line: Encodable { let at: Double; let text: String }
        struct Source: Encodable { let name: String; let url: URL; let token: String? }
        let owner: Owner
        let meeting: MeetingInfo
        let transcript: [Line]
        let connectors: [Source]
    }

    public struct ConnectorStatus: Decodable, Sendable, Hashable {
        public let name: String
        public let ok: Bool
        public let tools: Int
        public let error: String?
    }

    public struct Failure: LocalizedError {
        public let errorDescription: String?
    }

    public static func note(for meeting: Meeting, transcript: [Segment], settings: Settings) async throws -> String {
        let input = Input(
            owner: .init(name: settings.name, aliases: settings.aliases),
            meeting: .init(title: meeting.title, startedAt: meeting.startedAt, attendees: meeting.attendees, notes: meeting.calendarNotes),
            transcript: transcript.map { .init(at: $0.at, text: $0.text) },
            connectors: await sources(settings.connectors.filter(\.enabled))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try await run(arguments: [], input: encoder.encode(input))
    }

    public static func check(_ connectors: [Connector]) async throws -> [ConnectorStatus] {
        let output = try await run(arguments: ["check"], input: JSONEncoder().encode(["connectors": await sources(connectors)]))
        return try JSONDecoder().decode([ConnectorStatus].self, from: Data(output.utf8))
    }

    static func sources(_ connectors: [Connector]) async -> [Input.Source] {
        var sources: [Input.Source] = []
        for connector in connectors {
            var token = Secrets.get(connector.secretKey)
            if token == nil, connector.isGitHub { token = await GitHubCLI.token() }
            sources.append(.init(name: connector.name, url: connector.url, token: token))
        }
        return sources
    }

    static var executable: URL {
        if let path = ProcessInfo.processInfo.environment["MARTIN_ANALYZER"] { return URL(filePath: path) }
        return Bundle.main.url(forResource: "martin-analyzer", withExtension: nil) ?? URL(filePath: "/usr/bin/false")
    }

    static func run(arguments: [String], input: Data) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["ANTHROPIC_API_KEY"] = Secrets.get(Secrets.anthropic)
        process.environment = environment
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
