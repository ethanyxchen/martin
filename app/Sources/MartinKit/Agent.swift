import Foundation

public enum Agent {
    public static let noteLimit = 5
    static let excerpt = 600
    static let summaryLimit = 600

    static let instructions = """
        Pick the GitHub repository that holds this project's code, judging by the project's name and notes and each repository's README. \
        First quote the evidence that ties the project to a repository, then answer with that repository's slug exactly as listed, or null unless the evidence clearly matches one.
        """

    static let schema = """
        {"type":"object","properties":{"evidence":{"type":"string"},"slug":{"type":["string","null"]}},"required":["evidence","slug"],"additionalProperties":false}
        """

    public static func pickRepository(for project: Project, notes: [String], among candidates: [Repository], using assistant: Assistant) async -> Repository? {
        guard !candidates.isEmpty else { return nil }
        return await assistant.answer(prompt(for: project, notes: notes, among: candidates), instructions: instructions, schema: schema)
            .flatMap { pick(from: $0, among: candidates) }
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

    static func pick(from answer: Data, among candidates: [Repository]) -> Repository? {
        struct Answer: Decodable {
            let slug: String?
        }
        guard let slug = (try? JSONDecoder().decode(Answer.self, from: answer))?.slug else { return nil }
        return candidates.first { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }
    }
}
