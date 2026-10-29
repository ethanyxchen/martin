import Foundation

public struct RepositoryPick: Hashable, Sendable {
    public let repository: Repository
    public let reason: String
}

public enum Agent {
    static let model = "sonnet"
    static let excerpt = 1_500

    static let instructions = """
        You link projects in a meeting-notes app to the GitHub repository where each project's code lives. \
        Read the project's name and notes, then pick the one candidate repository that holds its code, judging by names, READMEs and what the notes discuss. \
        Answer with its slug exactly as listed, or null when no candidate clearly fits. \
        Give the reason as one plain sentence under 60 characters, shown as a caption under the repository's name, citing the evidence.
        """

    static let schema = """
        {"type":"object","properties":{"slug":{"type":["string","null"]},"reason":{"type":"string"}},"required":["slug","reason"],"additionalProperties":false}
        """

    public static func pickRepository(for project: Project, notes: [String], among candidates: [Repository]) async -> RepositoryPick? {
        guard !candidates.isEmpty else { return nil }
        let arguments = ["-p", "--model", model, "--tools", "", "--setting-sources", "", "--no-session-persistence",
                         "--system-prompt", instructions, "--output-format", "json", "--json-schema", schema]
        return await Command.run("claude", arguments, input: prompt(for: project, notes: notes, among: candidates))
            .flatMap { pick(from: $0, among: candidates) }
    }

    static func prompt(for project: Project, notes: [String], among candidates: [Repository]) -> String {
        let notes = notes.map { "<note>\n\($0.prefix(excerpt))\n</note>" }
        let repositories = candidates.map { "<repository slug=\"\($0.slug)\" folder=\"\($0.folder.lastPathComponent)\">\n\(($0.readme ?? "").prefix(excerpt))\n</repository>" }
        return """
            <project name="\(project.name)">
            \((notes.isEmpty ? ["No notes yet."] : notes).joined(separator: "\n"))
            </project>

            Candidate repositories cloned on this Mac, the ones the user worked on most recently first:
            \(repositories.joined(separator: "\n"))
            """
    }

    static func pick(from output: String, among candidates: [Repository]) -> RepositoryPick? {
        struct Envelope: Decodable {
            struct Answer: Decodable {
                let slug: String?
                let reason: String
            }
            let isError: Bool
            let structuredOutput: Answer?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let envelope = try? decoder.decode(Envelope.self, from: Data(output.utf8)), !envelope.isError,
              let answer = envelope.structuredOutput, let slug = answer.slug,
              let repository = candidates.first(where: { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }) else { return nil }
        return RepositoryPick(repository: repository, reason: answer.reason)
    }
}
