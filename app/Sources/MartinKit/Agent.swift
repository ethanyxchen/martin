import Foundation

public struct RepositoryLookup: Codable, Hashable, Sendable {
    public let folder: URL?

    public init(folder: URL?) {
        self.folder = folder
    }
}

public enum Agent {
    public static let noteLimit = 5

    public struct Note: Encodable, Sendable {
        let title: String
        let path: String

        public init(title: String, file: URL) {
            self.title = title
            path = file.path(percentEncoded: false)
        }
    }

    struct Name: Encodable {
        let name: String
    }

    struct LookupJob: Encodable {
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

    public struct OverviewJob: Encodable, Sendable {
        public struct Note: Encodable, Sendable {
            public let id: Meeting.ID
            let title: String
            let date: Date
            public let changedAt: Date
            let path: String

            public init(id: Meeting.ID, title: String, date: Date, changedAt: Date, file: URL) {
                self.id = id
                self.title = title
                self.date = date
                self.changedAt = changedAt
                path = file.path(percentEncoded: false)
            }
        }

        struct Linked: Encodable, Sendable {
            let folder: String
            let slug: String
        }

        enum CodingKeys: CodingKey {
            case kind, provider, project, owner, cutoff, previous, notes, repository
        }

        let provider: Provider
        let project: Name
        let owner: Owner
        public let cutoff: Date
        let previous: Overview?
        public let notes: [Note]
        let repository: Linked?

        public init(provider: Provider, project: String, owner: Owner, cutoff: Date, previous: Overview?, notes: [Note], repository: Repository?) {
            self.provider = provider
            self.project = Name(name: project)
            self.owner = owner
            self.cutoff = cutoff
            self.previous = previous
            self.notes = notes
            self.repository = repository.map { Linked(folder: $0.folder.path(percentEncoded: false), slug: $0.slug) }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("overview", forKey: .kind)
            try container.encode(provider, forKey: .provider)
            try container.encode(project, forKey: .project)
            try container.encode(owner, forKey: .owner)
            try container.encode(cutoff, forKey: .cutoff)
            try container.encode(previous, forKey: .previous)
            try container.encode(notes, forKey: .notes)
            try container.encode(repository, forKey: .repository)
        }
    }

    struct Sections: Decodable {
        let now: [Overview.Item]
        let next: [Overview.Item]
        let shelved: [Overview.Item]
    }

    public static func overview(_ job: OverviewJob, using credential: Credential) async throws -> Overview {
        let sections: Sections = try await AgentClient().run(job, using: credential)
        return Overview(now: sections.now, next: sections.next, shelved: sections.shelved, readAt: job.cutoff)
    }

    struct Answer: Decodable, Equatable {
        let slugs: [String]
    }

    public static func match(_ project: Project, notes: [Note], among candidates: [Repository], using credential: Credential) async -> Set<String>? {
        guard !candidates.isEmpty else { return [] }
        let answer: Answer? = try? await AgentClient().run(LookupJob(for: project, notes: notes, among: candidates, provider: credential.provider), using: credential)
        return answer.map { Set($0.slugs) }
    }

    public static func pick(for project: Project, matches: Set<String>, among candidates: [Repository]) -> Repository? {
        candidates.first { matches.contains($0.slug.lowercased()) || names(project, $0) }
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
