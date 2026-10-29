import Foundation

public struct Repository: Hashable, Sendable {
    public static let roots = ["Developer", "Code", "Projects", "src", "GitHub", "dev", "repos", "Documents/GitHub"]
        .map { URL.homeDirectory.appending(path: $0, directoryHint: .isDirectory) }

    static let activityWindow: TimeInterval = 30 * 24 * 60 * 60

    public let folder: URL
    public let slug: String
    public internal(set) var lastWorkedOn: Date?
    private let gitDirectory: URL

    public init?(at folder: URL) {
        guard let gitDirectory = Self.gitDirectory(of: folder) else { return nil }
        let common = Self.commonDirectory(of: gitDirectory)
        guard let config = try? String(contentsOf: common.appending(path: "config"), encoding: .utf8),
              let slug = Self.slug(inConfig: config) else { return nil }
        self.folder = folder
        self.slug = slug
        self.gitDirectory = gitDirectory
        lastWorkedOn = Self.lastWorkedOn(in: common)
    }

    public var name: String { String(slug.split(separator: "/").last ?? "") }

    public var web: URL { URL(string: "https://github.com/\(slug)")! }

    public var summary: String? {
        guard let readme = ["README.md", "readme.md", "README"].lazy
            .compactMap({ try? String(contentsOf: self.folder.appending(path: $0), encoding: .utf8) }).first else { return nil }
        var code = false
        let prose = readme.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { line in
            if line.hasPrefix("```") { code.toggle(); return false }
            return !code && !line.isEmpty && !line.contains("</") && !["<", "![", "[![", "|", "---"].contains(where: line.hasPrefix)
        }
        return prose.isEmpty ? nil : prose.joined(separator: " ")
    }

    public var branch: String? {
        (try? String(contentsOf: gitDirectory.appending(path: "HEAD"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .firstMatch(of: /^ref: refs\/heads\/(.+)$/).map { String($0.1) }
    }

    public func activity(since date: Date?) async -> String? {
        let since = (date ?? .now.addingTimeInterval(-Self.activityWindow)).formatted(.iso8601.year().month().day())
        let commits = await Command.run("git", ["-C", folder.path(percentEncoded: false), "log", "--all", "--since", since, "--date=short", "--pretty=format:%ad %s", "-n", "40"], timeout: 30)
        let pulls = await Command.run("gh", ["pr", "list", "--repo", slug, "--state", "all", "--limit", "15", "--search", "updated:>=\(since)", "--json", "title,state,updatedAt",
                                             "--jq", #".[] | "\(.updatedAt[:10]) pull request \(.state): \(.title)""#], timeout: 30)
        let lines = [commits, pulls].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public static func clones(in roots: [URL]) -> [Repository] {
        roots.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .filter { isDirectory($0.appending(path: ".git")) }
            .compactMap(Repository.init(at:))
    }

    public static func nearby(_ folders: [URL]) async -> [Repository] {
        async let activity = GitHub.recentActivity()
        return clones(in: roots + folders).ranked(by: await activity)
    }

    private static func lastWorkedOn(in common: URL) -> Date? {
        let worktrees = (try? FileManager.default.contentsOfDirectory(at: common.appending(path: "worktrees"), includingPropertiesForKeys: nil)) ?? []
        return ([common] + worktrees)
            .compactMap { try? $0.appending(path: "logs/HEAD").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
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
    func ranked(by activity: [String: Date]) -> [Repository] {
        var seen: Set<String> = []
        let order = { (repository: Repository) in
            (-(repository.lastWorkedOn ?? .distantPast).timeIntervalSinceReferenceDate, repository.folder.lastPathComponent == repository.name ? 0 : 1, repository.folder.path)
        }
        return map { repository in
            var worked = repository
            worked.lastWorkedOn = [repository.lastWorkedOn, activity[repository.slug.lowercased()]].compactMap(\.self).max()
            return worked
        }
        .sorted { order($0) < order($1) }
        .filter { seen.insert($0.slug.lowercased()).inserted }
    }
}

enum GitHub {
    static func recentActivity() async -> [String: Date] {
        guard let login = await gh(["api", "user", "--jq", ".login"]).first else { return [:] }
        let events = await gh(["api", "--paginate", "users/\(login)/events?per_page=100", "--jq", ".[] | \"\\(.repo.name) \\(.created_at)\""])
        return activity(in: events)
    }

    static func activity(in events: [String]) -> [String: Date] {
        Dictionary(events.compactMap { event in
            let fields = event.split(separator: " ")
            guard fields.count == 2, let date = try? Date(String(fields[1]), strategy: .iso8601) else { return nil }
            return (fields[0].lowercased(), date)
        }, uniquingKeysWith: max)
    }

    private static func gh(_ arguments: [String]) async -> [String] {
        (await Command.run("gh", arguments, timeout: 30) ?? "").split(whereSeparator: \.isNewline).map(String.init)
    }
}
