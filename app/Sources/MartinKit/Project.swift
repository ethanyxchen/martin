import Foundation

public struct Project: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var series: [String]
    public var archivedAt: Date?
    public var repository: URL?

    public init(id: String = UUID().uuidString, name: String, series: [String] = [], repository: URL? = nil) {
        self.id = id
        self.name = name
        self.series = series
        self.repository = repository
    }
}

public struct Shelf: Identifiable, Hashable, Sendable {
    public enum ID: Hashable, Sendable {
        case project(Project.ID)
        case unassigned
    }

    public let project: Project?
    public let meetings: [Meeting]

    public var id: ID { project.map { .project($0.id) } ?? .unassigned }
}

public extension [Meeting] {
    func shelved(in projects: [Project]) -> [Shelf] {
        let known = Set(projects.map(\.id))
        let filed = Dictionary(grouping: self) { $0.project.flatMap { known.contains($0) ? $0 : nil } }
        let shelves = projects.map { Shelf(project: $0, meetings: filed[$0.id] ?? []) }
            .sorted { ($0.meetings.first?.date ?? .distantPast) > ($1.meetings.first?.date ?? .distantPast) }
        return shelves + (filed[nil].map { [Shelf(project: nil, meetings: $0)] } ?? [])
    }
}

public extension [Project] {
    func suggestions(for query: String) -> [Project] {
        filter { query.isEmpty || !$0.name.wordMatches(of: query).isEmpty }
    }
}
