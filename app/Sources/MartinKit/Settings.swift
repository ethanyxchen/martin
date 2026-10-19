import Foundation

public struct Settings: Codable, Hashable, Sendable {
    public var name: String
    public var aliases: [String]
    public var keyterms: [String]

    public init(name: String = NSFullUserName(), aliases: [String] = [], keyterms: [String] = []) {
        self.name = name
        self.aliases = aliases
        self.keyterms = keyterms
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
