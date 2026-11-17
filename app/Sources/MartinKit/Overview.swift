import Foundation

public struct Overview: Codable, Hashable, Sendable {
    public struct Task: Codable, Hashable, Sendable {
        public let title: String
        public let caption: String
        public let updated: String?

        public init(title: String, caption: String, updated: String? = nil) {
            self.title = title
            self.caption = caption
            self.updated = updated
        }

        public func day(in calendar: Calendar) -> Date? {
            let parts = updated?.split(separator: "-").compactMap { Int($0) } ?? []
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
    }

    public enum Section: CaseIterable, Sendable {
        case now
        case next
        case shelved
    }

    public let now: [Task]
    public let next: [Task]
    public let shelved: [Task]
    public let readAt: Date

    public init(now: [Task], next: [Task], shelved: [Task], readAt: Date) {
        self.now = now
        self.next = next
        self.shelved = shelved
        self.readAt = readAt
    }

    public subscript(section: Section) -> [Task] {
        switch section {
        case .now: now
        case .next: next
        case .shelved: shelved
        }
    }
}
