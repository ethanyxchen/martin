import Foundation

public enum Agent {
    static let excerpt = 1_500

    static let instructions = """
        You link projects in a meeting-notes app to the GitHub repository where each project's code lives. \
        Read the project's name and notes, then pick the one candidate repository that holds its code, judging by names, READMEs and what the notes discuss. \
        Answer with its slug exactly as listed, or null when no candidate clearly fits.
        """

    static let schema = """
        {"type":"object","properties":{"slug":{"type":["string","null"]}},"required":["slug"],"additionalProperties":false}
        """

    public static func pickRepository(for project: Project, notes: [String], among candidates: [Repository], using assistant: Assistant) async -> Repository? {
        guard !candidates.isEmpty else { return nil }
        return await assistant.answer(prompt(for: project, notes: notes, among: candidates), instructions: instructions, schema: schema)
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

    static func pick(from answer: Data, among candidates: [Repository]) -> Repository? {
        struct Answer: Decodable {
            let slug: String?
        }
        guard let slug = (try? JSONDecoder().decode(Answer.self, from: answer))?.slug else { return nil }
        return candidates.first { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }
    }
}
