import Foundation

public struct Meeting: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let startedAt: Date
    public var title: String?
    public var attendees: [String]

    public init(id: String, startedAt: Date, title: String? = nil, attendees: [String] = []) {
        self.id = id
        self.startedAt = startedAt
        self.title = title
        self.attendees = attendees
    }
}
