import Foundation

public struct CalendarEvent: Sendable, Hashable {
    public let title: String
    public let attendees: [String]
    public let notes: String?
}

public enum CalendarLookup {
    public static func currentEvent(at date: Date = .now) async -> CalendarEvent? { nil }
}
