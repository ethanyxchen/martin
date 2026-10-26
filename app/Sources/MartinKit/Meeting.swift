import Foundation

public struct Meeting: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let startedAt: Date
    public let occurrence: Occurrence?
    public var title: String?

    public init(id: String, startedAt: Date, occurrence: Occurrence? = nil, title: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.occurrence = occurrence
        self.title = title
    }
}

public struct Occurrence: Codable, Hashable, Sendable {
    public let series: String
    public let start: Date?

    public init(series: String, start: Date? = nil) {
        self.series = series
        self.start = start
    }
}
