import Foundation

public struct Meeting: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let startedAt: Date
    public var endedAt: Date?
    public var title: String?
    public var attendees: [String]
    public var calendarNotes: String?

    public init(id: String, startedAt: Date, endedAt: Date? = nil, title: String? = nil, attendees: [String] = [], calendarNotes: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.attendees = attendees
        self.calendarNotes = calendarNotes
    }
}

public struct Segment: Codable, Hashable, Sendable {
    public let at: Double
    public let duration: Double
    public let text: String

    public init(at: Double, duration: Double, text: String) {
        self.at = at
        self.duration = duration
        self.text = text
    }
}
