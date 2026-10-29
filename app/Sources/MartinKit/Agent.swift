import Foundation

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

    public static func pickRepository(for project: Project, notes: [String], among candidates: [Repository], using assistant: Assistant) async -> Repository? {
        guard !candidates.isEmpty else { return nil }
        let answer = await assistant.answer(prompt(for: project, notes: notes, among: candidates), instructions: instructions, schema: schema)
        return pick(for: project, from: answer, among: candidates)
    }

    static func prompt(for project: Project, notes: [String], among candidates: [Repository]) -> String {
        let notes = notes.isEmpty ? "No notes yet." : notes.map { String($0.prefix(excerpt)) }.joined(separator: "\n\n")
        let repositories = candidates.map { [$0.slug, $0.summary.map { String($0.prefix(summaryLimit)) }].compactMap(\.self).joined(separator: ": ") }
        return """
            Project: \(project.name)

            Notes:
            \(notes)

            Repositories:
            \(repositories.joined(separator: "\n"))
            """
    }

    static func pick(for project: Project, from answer: Data?, among candidates: [Repository]) -> Repository? {
        let named = slugs(in: answer)
        return candidates.first { named.contains($0.slug.lowercased()) || names(project, $0) }
    }

    private static func slugs(in answer: Data?) -> Set<String> {
        struct Answer: Decodable {
            let slugs: [String]
        }
        guard let slugs = answer.flatMap({ try? JSONDecoder().decode(Answer.self, from: $0) })?.slugs, slugs.count <= matchLimit else { return [] }
        return Set(slugs.map { $0.lowercased() })
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
