import Foundation

public struct AgentClient: Sendable {
    public enum Failure: Error, Equatable {
        case unavailable
        case reported(String)
        case timedOut
        case broken

        public var message: String {
            switch self {
            case .unavailable: "Martin couldn't start its agent."
            case .reported(let message): message
            case .timedOut: "The agent took too long and was stopped."
            case .broken: "The agent stopped unexpectedly."
            }
        }
    }

    enum Event<Result: Decodable>: Decodable {
        case progress
        case result(Result)
        case error(String)

        enum CodingKeys: CodingKey {
            case type, result, message
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "progress": self = .progress
            case "result": self = .result(try container.decode(Result.self, forKey: .result))
            case "error": self = .error(try container.decode(String.self, forKey: .message))
            default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown event")
            }
        }

        var isProgress: Bool {
            if case .progress = self { true } else { false }
        }
    }

    let executable: URL?
    let timeout: TimeInterval

    public init(executable: URL? = Bundle.main.url(forAuxiliaryExecutable: "martin-agent"), timeout: TimeInterval = 300) {
        self.executable = executable
        self.timeout = timeout
    }

    public func run<Result: Decodable>(_ job: some Encodable, using credential: Credential) async throws -> Result {
        guard let executable else { throw Failure.unavailable }
        let input = String(decoding: try Self.encoder(in: .current).encode(job), as: UTF8.self)
        let outcome = await Command.run(executable.path(percentEncoded: false), [], input: input, environment: credential.environment, timeout: timeout)
        try Task.checkCancellation()
        return try Self.result(of: outcome)
    }

    static func encoder(in zone: TimeZone) -> JSONEncoder {
        let encoder = JSONEncoder()
        let style = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: zone)
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(style))
        }
        return encoder
    }

    static func result<Result: Decodable>(of outcome: Command.Outcome) throws(Failure) -> Result {
        switch outcome.ending {
        case .unlaunched: throw .unavailable
        case .stopped: throw .timedOut
        case .exited, .signalled: break
        }
        let decoder = JSONDecoder()
        guard let events = try? outcome.output.split(separator: "\n").map({ try decoder.decode(Event<Result>.self, from: Data($0.utf8)) }),
              let last = events.last, events.dropLast().allSatisfy(\.isProgress) else { throw .broken }
        switch (last, outcome.ending) {
        case (.result(let result), .exited(0)): return result
        case (.error(let message), .exited(let status)) where status != 0: throw .reported(message)
        default: throw .broken
        }
    }
}
