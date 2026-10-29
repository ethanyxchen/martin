import Foundation

public struct Overview: Codable, Hashable, Sendable {
    public struct Task: Codable, Hashable, Sendable {
        public var title: String
        public var caption: String
        public var updatedAt: Date?

        public init(title: String, caption: String, updatedAt: Date? = nil) {
            self.title = title
            self.caption = caption
            self.updatedAt = updatedAt
        }
    }

    public var now: [Task]
    public var next: [Task]
    public var shelved: [Task]
    public var readAt: Date

    public init(now: [Task] = [], next: [Task] = [], shelved: [Task] = [], readAt: Date) {
        self.now = now
        self.next = next
        self.shelved = shelved
        self.readAt = readAt
    }
}
