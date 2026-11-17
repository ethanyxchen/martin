import Foundation

public struct Overview: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable {
        public let title: String
        public let caption: String
        public let updated: String?

        public init(title: String, caption: String, updated: String? = nil) {
            self.title = title
            self.caption = caption
            self.updated = updated
        }

        public func day(in calendar: Calendar) -> Date? {
            let style = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
            guard let updated, let day = try? Date(updated, strategy: style), day.formatted(style) == updated else { return nil }
            return day
        }
    }

    public enum Section: CaseIterable, Sendable {
        case now
        case next
        case shelved
    }

    public let now: [Item]
    public let next: [Item]
    public let shelved: [Item]
    public let readAt: Date

    public init(now: [Item], next: [Item], shelved: [Item], readAt: Date) {
        self.now = now
        self.next = next
        self.shelved = shelved
        self.readAt = readAt
    }

    public subscript(section: Section) -> [Item] {
        switch section {
        case .now: now
        case .next: next
        case .shelved: shelved
        }
    }
}
