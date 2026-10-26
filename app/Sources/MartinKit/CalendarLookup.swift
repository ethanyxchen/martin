import EventKit
import Foundation

public struct CalendarEvent: Sendable, Hashable {
    public let occurrence: Occurrence
    public let title: String
    public let start: Date
    public let end: Date
    public let attendees: [String]

    init(occurrence: Occurrence, title: String, start: Date, end: Date, attendees: [String] = []) {
        self.occurrence = occurrence
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
    }

    init(_ event: EKEvent) {
        self.init(
            occurrence: Occurrence(series: event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier, start: event.occurrenceDate ?? event.startDate),
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            attendees: (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(CalendarLookup.name)
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

public enum CalendarLookup {
    public static func currentEvent(at date: Date = .now) async -> CalendarEvent? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return nil }
        return ongoing(at: date, in: store).map(CalendarEvent.init)
    }

    public static func events(from start: Date, to end: Date) -> AsyncStream<[CalendarEvent]> {
        AsyncStream { continuation in
            let task = Task {
                let store = EKEventStore()
                guard (try? await store.requestFullAccessToEvents()) == true else { return continuation.finish() }
                continuation.yield(events(from: start, to: end, in: store))
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                    continuation.yield(events(from: start, to: end, in: store))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func events(from start: Date, to end: Date, in store: EKEventStore) -> [CalendarEvent] {
        store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay }
            .map(CalendarEvent.init)
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

    static func ongoing(at date: Date, in store: EKEventStore) -> EKEvent? {
        let soon = date.addingTimeInterval(600)
        return store.events(matching: store.predicateForEvents(withStart: date, end: soon, calendars: nil))
            .filter { !$0.isAllDay && $0.startDate <= soon && $0.endDate > date }
            .max { ($0.hasAttendees ? 1 : 0, $0.startDate) < ($1.hasAttendees ? 1 : 0, $1.startDate) }
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
