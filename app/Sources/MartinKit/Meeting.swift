import Foundation

public struct Meeting: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let startedAt: Date
    public var scheduledAt: Date?
    public let occurrence: Occurrence?
    public var title: String?
    public var attendees: [Person]
    public var archivedAt: Date?
    public var project: Project.ID?

    public init(id: String, startedAt: Date, scheduledAt: Date? = nil, occurrence: Occurrence? = nil, title: String? = nil, attendees: [Person] = [], project: Project.ID? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.scheduledAt = scheduledAt
        self.occurrence = occurrence
        self.title = title
        self.attendees = attendees
        self.project = project
    }

    public var date: Date { scheduledAt ?? startedAt }
}

public struct Occurrence: Codable, Hashable, Sendable {
    public let series: String
    public let start: Date?

    public init(series: String, start: Date? = nil) {
        self.series = series
        self.start = start
    }

    public var recurringSeries: String? {
        start == nil ? nil : series
    }
}
