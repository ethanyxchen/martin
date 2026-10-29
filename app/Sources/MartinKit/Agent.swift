import CryptoKit
import Foundation

public struct RepositoryLookup: Codable, Hashable, Sendable {
    public let fingerprint: String
    public let matches: Set<String>

    public init(fingerprint: String, matches: Set<String>) {
        self.fingerprint = fingerprint
        self.matches = matches
    }
}

public enum Agent {
    public static let noteLimit = 5
    static let excerpt = 600
    static let summaryLimit = 600
    static let matchLimit = 3

    static let instructions = """
        List the GitHub repositories that hold this project's code: every one whose name or README names the project, or the product its notes discuss. \
        A repository that is merely about a similar topic does not count. \
        First quote the evidence, then list at most \(matchLimit) slugs exactly as written, or none when nothing names the project.
        """

    static let schema = """
        {"type":"object","properties":{"evidence":{"type":"string"},"slugs":{"type":"array","items":{"type":"string"}}},"required":["evidence","slugs"],"additionalProperties":false}
        """

    public static func match(_ project: Project, notes: [String], among candidates: [Repository], using assistant: Assistant) async -> Set<String>? {
        guard !candidates.isEmpty else { return [] }
        return await assistant.answer(prompt(for: project, notes: notes, among: candidates), instructions: instructions, schema: schema).flatMap(matches(in:))
    }

    public static func fingerprint(for project: Project, notes: [String], among candidates: [Repository], using assistant: Assistant) -> String {
        let inputs = [assistant.rawValue, instructions, schema, project.name, excerpts(of: notes)] + lines(for: candidates).sorted()
        return SHA256.hash(data: Data(inputs.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func pick(for project: Project, matches: Set<String>, among candidates: [Repository]) -> Repository? {
        candidates.first { matches.contains($0.slug.lowercased()) || names(project, $0) }
    }

    static func prompt(for project: Project, notes: [String], among candidates: [Repository]) -> String {
        """
        Project: \(project.name)

        Notes:
        \(excerpts(of: notes))

        Repositories:
        \(lines(for: candidates).joined(separator: "\n"))
        """
    }

    private static func excerpts(of notes: [String]) -> String {
        notes.isEmpty ? "No notes yet." : notes.map { String($0.prefix(excerpt)) }.joined(separator: "\n\n")
    }

    private static func lines(for candidates: [Repository]) -> [String] {
        candidates.map { [$0.slug, $0.summary.map { String($0.prefix(summaryLimit)) }].compactMap(\.self).joined(separator: ": ") }
    }

    static func matches(in answer: Data) -> Set<String>? {
        struct Answer: Decodable {
            let slugs: [String]
        }
        guard let slugs = (try? JSONDecoder().decode(Answer.self, from: answer))?.slugs else { return nil }
        return slugs.count <= matchLimit ? Set(slugs.map { $0.lowercased() }) : []
    }

    static func names(_ project: Project, _ repository: Repository) -> Bool {
        let name = project.name.words
        return name.joined().count >= 3 && "\(repository.slug) \(repository.summary ?? "")".words.contains(name)
    }
}

private extension String {
    var words: [Substring] {
        lowercased()[...].split { !$0.isLetter && !$0.isNumber }
    }
}
