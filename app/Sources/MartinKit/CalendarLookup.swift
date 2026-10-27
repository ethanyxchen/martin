import EventKit
import Foundation

public struct CalendarEvent: Sendable, Hashable {
    public let occurrence: Occurrence
    public let title: String
    public let start: Date
    public let end: Date
    public let attendees: [Person]

    init(occurrence: Occurrence, title: String, start: Date, end: Date, attendees: [Person] = []) {
        self.occurrence = occurrence
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
    }

    init(_ event: EKEvent) {
        let recurring = event.hasRecurrenceRules || event.isDetached
        self.init(
            occurrence: Occurrence(series: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier, start: recurring ? event.occurrenceDate : nil),
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            attendees: (event.attendees ?? []).filter { !$0.isCurrentUser && ![.room, .resource].contains($0.participantType) }.compactMap(CalendarLookup.person)
        )
    }

    public func isUnderway(at date: Date) -> Bool {
        start <= date && date < end
    }
}

public struct AgendaDay: Sendable, Hashable {
    public let start: Date
    public let events: [CalendarEvent]
}

public struct EventCalendar: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let account: String
    public let color: CGColor

    init(id: String, title: String, account: String, color: CGColor) {
        self.id = id
        self.title = title
        self.account = account
        self.color = color
    }

    init(_ calendar: EKCalendar) {
        self.init(id: calendar.calendarIdentifier, title: calendar.title, account: calendar.source?.title ?? "", color: calendar.cgColor)
    }
}

public struct CalendarAccount: Sendable, Hashable {
    public let title: String
    public let calendars: [EventCalendar]
}

public enum CalendarLookup {
    public static func currentEvent(at date: Date = .now, hiding hidden: Set<EventCalendar.ID>) async -> CalendarEvent? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return nil }
        return ongoing(at: date, hiding: hidden, in: store).map(CalendarEvent.init)
    }

    public static func events(from start: Date, to end: Date, hiding hidden: Set<EventCalendar.ID>) -> AsyncStream<[CalendarEvent]> {
        watch { store in
            events(from: start, to: end, hiding: hidden, in: store)
                .filter { !$0.isAllDay }
                .map(CalendarEvent.init)
        }
    }

    public static func accounts() -> AsyncStream<[CalendarAccount]> {
        watch { store in accounts(of: store.calendars(for: .event).map(EventCalendar.init)) }
    }

    static func accounts(of calendars: [EventCalendar]) -> [CalendarAccount] {
        Dictionary(grouping: calendars, by: \.account)
            .map { CalendarAccount(title: $0.key, calendars: $0.value.sorted { ($0.title, $0.id) < ($1.title, $1.id) }) }
            .sorted { $0.title < $1.title }
    }

    private static func watch<Value: Sendable>(_ read: @escaping @Sendable (EKEventStore) -> Value) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let task = Task {
                let store = EKEventStore()
                guard (try? await store.requestFullAccessToEvents()) == true else { return continuation.finish() }
                continuation.yield(read(store))
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                    continuation.yield(read(store))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func events(from start: Date, to end: Date, hiding hidden: Set<EventCalendar.ID>, in store: EKEventStore) -> [EKEvent] {
        store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !hidden.contains($0.calendar.calendarIdentifier) }
    }

    public static func agenda(of events: [CalendarEvent], days: Int, at now: Date, calendar: Calendar = .current) -> [AgendaDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).map { offset in
            let start = calendar.date(byAdding: .day, value: offset, to: today)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return AgendaDay(
                start: start,
                events: events
                    .filter { $0.start < end && $0.end > max(start, now) }
                    .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            )
        }
    }

    static func ongoing(at date: Date, hiding hidden: Set<EventCalendar.ID>, in store: EKEventStore) -> EKEvent? {
        let soon = date.addingTimeInterval(600)
        return events(from: date, to: soon, hiding: hidden, in: store)
            .filter { !$0.isAllDay && $0.startDate <= soon && $0.endDate > date }
            .max { ($0.hasAttendees ? 1 : 0, $0.startDate) < ($1.hasAttendees ? 1 : 0, $1.startDate) }
    }

    static func person(of participant: EKParticipant) -> Person? {
        email(participant.url).map { Person(email: $0, name: participant.name) }
    }

    static func email(_ url: URL) -> String? {
        guard url.scheme == "mailto" else { return nil }
        return String(url.absoluteString.dropFirst("mailto:".count)).removingPercentEncoding
    }
}
