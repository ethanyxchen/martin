import Foundation

public struct Connector: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, url: URL, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.enabled = enabled
    }

    public var secretKey: String { "connector.\(id.uuidString)" }

    public var isGitHub: Bool { url.host() == "api.githubcopilot.com" }

    public static let presets: [Connector] = [
        Connector(name: "GitHub", url: URL(string: "https://api.githubcopilot.com/mcp/")!),
        Connector(name: "Linear", url: URL(string: "https://mcp.linear.app/mcp")!),
        Connector(name: "Slack", url: URL(string: "https://mcp.slack.com/mcp")!),
    ]
}

public struct Settings: Codable, Hashable, Sendable {
    public var name: String
    public var aliases: [String]
    public var keyterms: [String]
    public var connectors: [Connector]

    public init(name: String = NSFullUserName(), aliases: [String] = [], keyterms: [String] = [], connectors: [Connector] = []) {
        self.name = name
        self.aliases = aliases
        self.keyterms = keyterms
        self.connectors = connectors
    }

    public static let url = MeetingLibrary.applicationSupport.appending(path: "settings.json")

    public static func load(from url: URL = url) -> Settings {
        (try? JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))) ?? Settings()
    }

    public func save(to url: URL = url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
