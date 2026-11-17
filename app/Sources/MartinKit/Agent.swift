import Foundation

public struct RepositoryLookup: Codable, Hashable, Sendable {
    public let folder: URL?

    public init(folder: URL?) {
        self.folder = folder
    }
}

public enum Agent {
    public static let noteLimit = 5
    private static let timeout: TimeInterval = 120

    public struct Note: Encodable, Sendable {
        let title: String
        let path: String

        public init(title: String, file: URL) {
            self.title = title
            path = file.path(percentEncoded: false)
        }
    }

    struct LookupJob: Encodable {
        struct Name: Encodable {
            let name: String
        }

        struct Candidate: Encodable {
            let slug: String
            let summary: String?

            enum CodingKeys: CodingKey {
                case slug, summary
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(slug, forKey: .slug)
                try container.encode(summary, forKey: .summary)
            }
        }

        let kind = "repositoryLookup"
        let provider: Provider
        let project: Name
        let notes: [Note]
        let candidates: [Candidate]

        init(for project: Project, notes: [Note], among candidates: [Repository], provider: Provider) {
            self.provider = provider
            self.project = Name(name: project.name)
            self.notes = notes
            self.candidates = candidates.map { Candidate(slug: $0.slug, summary: $0.summary) }
        }
    }

    public static func match(_ project: Project, notes: [Note], among candidates: [Repository], using credential: Credential) async -> Set<String>? {
        guard !candidates.isEmpty else { return [] }
        guard let agent = Bundle.main.url(forAuxiliaryExecutable: "martin-agent"),
              let job = try? JSONEncoder().encode(LookupJob(for: project, notes: notes, among: candidates, provider: credential.provider)) else { return nil }
        let output = await Command.run(agent.path(percentEncoded: false), [], input: String(decoding: job, as: UTF8.self), environment: credential.environment, timeout: timeout)
        return output.flatMap(matches(in:))
    }

    public static func pick(for project: Project, matches: Set<String>, among candidates: [Repository]) -> Repository? {
        candidates.first { matches.contains($0.slug.lowercased()) || names(project, $0) }
    }

    static func matches(in output: String) -> Set<String>? {
        struct Event: Decodable {
            struct Answer: Decodable {
                let slugs: [String]
            }

            let type: String
            let result: Answer?
        }
        let events = output.split(whereSeparator: \.isNewline).compactMap { try? JSONDecoder().decode(Event.self, from: Data($0.utf8)) }
        return events.first { $0.type == "result" }?.result.map { Set($0.slugs) }
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
