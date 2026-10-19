import EventKit
import Foundation

public struct CalendarEvent: Sendable, Hashable {
    public let title: String
    public let attendees: [String]
    public let notes: String?
}

public enum CalendarLookup {
    public static func currentEvent(at date: Date = .now) async -> CalendarEvent? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return nil }
        let soon = date.addingTimeInterval(600)
        let event = store.events(matching: store.predicateForEvents(withStart: date, end: soon, calendars: nil))
            .filter { !$0.isAllDay && $0.startDate <= soon && $0.endDate > date }
            .max { ($0.hasAttendees ? 1 : 0, $0.startDate) < ($1.hasAttendees ? 1 : 0, $1.startDate) }
        return event.map { event in
            CalendarEvent(
                title: event.title ?? "",
                attendees: (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(name),
                notes: event.notes
            )
        }
    }

    static func name(of participant: EKParticipant) -> String? {
        if let name = participant.name, !name.isEmpty { return name }
        return emailName(participant.url)
    }

    static func emailName(_ url: URL) -> String? {
        guard url.scheme == "mailto", let local = url.absoluteString.dropFirst("mailto:".count).split(separator: "@").first else { return nil }
        return local.removingPercentEncoding
    }
}
