import Foundation

public struct Repository: Hashable, Sendable {
    public static let roots = ["Developer", "Code", "Projects", "src", "GitHub", "dev", "repos", "Documents/GitHub"]
        .map { URL.homeDirectory.appending(path: $0, directoryHint: .isDirectory) }

    public let folder: URL
    public let slug: String
    private let gitDirectory: URL

    public init?(at folder: URL) {
        guard let gitDirectory = Self.gitDirectory(of: folder),
              let config = try? String(contentsOf: Self.commonDirectory(of: gitDirectory).appending(path: "config"), encoding: .utf8),
              let slug = Self.slug(inConfig: config) else { return nil }
        self.folder = folder
        self.slug = slug
        self.gitDirectory = gitDirectory
    }

    public var name: String { String(slug.split(separator: "/").last ?? "") }

    public var web: URL { URL(string: "https://github.com/\(slug)")! }

    public var branch: String? {
        (try? String(contentsOf: gitDirectory.appending(path: "HEAD"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .firstMatch(of: /^ref: refs\/heads\/(.+)$/).map { String($0.1) }
    }

    public static func clones(in roots: [URL]) -> [Repository] {
        roots.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .filter { isDirectory($0.appending(path: ".git")) }
            .compactMap(Repository.init(at:))
    }

    public static func nearby(_ folders: [URL]) async -> [Repository] {
        async let activity = GitHub.recentRepositories()
        return clones(in: roots + folders).ranked(by: await activity)
    }

    static func slug(of remote: String) -> String? {
        remote.firstMatch(of: /github\.com[:\/]([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/).map { "\($0.1)/\($0.2)" }
    }

    private static func slug(inConfig config: String) -> String? {
        var origin = false
        for line in config.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") {
                origin = line == "[remote \"origin\"]"
            } else if origin, let url = line.firstMatch(of: /^url\s*=\s*(.+)$/) {
                return slug(of: String(url.1))
            }
        }
        return nil
    }

    private static func gitDirectory(of folder: URL) -> URL? {
        let git = folder.appending(path: ".git")
        if isDirectory(git) { return git }
        guard let pointer = try? String(contentsOf: git, encoding: .utf8).firstMatch(of: /^gitdir:\s*(.+)$/.anchorsMatchLineEndings()) else { return nil }
        return URL(filePath: String(pointer.1).trimmingCharacters(in: .whitespaces), directoryHint: .isDirectory, relativeTo: folder).standardizedFileURL
    }

    private static func commonDirectory(of gitDirectory: URL) -> URL {
        guard let common = try? String(contentsOf: gitDirectory.appending(path: "commondir"), encoding: .utf8) else { return gitDirectory }
        return URL(filePath: common.trimmingCharacters(in: .whitespacesAndNewlines), directoryHint: .isDirectory, relativeTo: gitDirectory).standardizedFileURL
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
}

public extension [Repository] {
    func ranked(by activity: [String]) -> [Repository] {
        let recency = Dictionary(activity.enumerated().map { ($1.lowercased(), $0) }) { first, _ in first }
        var seen: Set<String> = []
        let order = { (repository: Repository) in
            (recency[repository.slug.lowercased()] ?? .max, repository.folder.lastPathComponent == repository.name ? 0 : 1, repository.folder.path)
        }
        return sorted { order($0) < order($1) }
            .filter { seen.insert($0.slug.lowercased()).inserted }
    }

    func suggestion(for project: Project) -> Repository? {
        let words = project.name.words
        return first { !words.isDisjoint(with: $0.name.words) }
    }
}

enum GitHub {
    static func recentRepositories() async -> [String] {
        guard let login = await gh(["api", "user", "--jq", ".login"]).first else { return [] }
        return await gh(["api", "--paginate", "users/\(login)/events?per_page=100", "--jq", ".[].repo.name"])
    }

    private static func gh(_ arguments: [String]) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(filePath: "/usr/bin/env")
                process.arguments = ["gh"] + arguments
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = [environment["PATH"], "/opt/homebrew/bin", "/usr/local/bin"].compactMap(\.self).joined(separator: ":")
                process.environment = environment
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: []) }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init) : [])
            }
        }
    }
}

private extension String {
    var words: Set<String> {
        Set(lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count >= 3 }.map(String.init))
    }
}
