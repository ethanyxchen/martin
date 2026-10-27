import Foundation
import Testing
@testable import MartinKit

struct CalendarLookupTests {
    @Test func emailComesFromMailtoURLs() {
        #expect(CalendarLookup.email(URL(string: "mailto:ada%2Blabs@example.com")!) == "ada+labs@example.com")
        #expect(CalendarLookup.email(URL(string: "https://example.com/ada")!) == nil)
    }

    private static let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private static func event(_ title: String, _ start: Date, _ end: Date) -> CalendarEvent {
        CalendarEvent(occurrence: Occurrence(series: title, start: start), title: title, start: start, end: end)
    }

    private static func agenda(_ events: [CalendarEvent], at now: Date) -> [[String]] {
        CalendarLookup.agenda(of: events, days: 4, at: now, calendar: calendar).map { $0.events.map(\.title) }
    }

    @Test func agendaCoversTodayAndTheNextThreeDays() {
        let days = CalendarLookup.agenda(of: [], days: 4, at: Self.at(20, 15), calendar: Self.calendar)
        #expect(days.map(\.start) == [Self.at(20, 0), Self.at(21, 0), Self.at(22, 0), Self.at(23, 0)])
        #expect(days.map(\.end) == [Self.at(21, 0), Self.at(22, 0), Self.at(23, 0), Self.at(24, 0)])
        #expect(days.allSatisfy { $0.events.isEmpty })
    }

    @Test func agendaGroupsEventsByDayInOrder() {
        let events = [
            Self.event("Retro", Self.at(22, 16), Self.at(22, 17)),
            Self.event("Planning", Self.at(21, 14), Self.at(21, 15)),
            Self.event("Standup", Self.at(21, 9, 30), Self.at(21, 9, 45)),
            Self.event("Next week", Self.at(24, 9), Self.at(24, 10)),
        ]
        #expect(Self.agenda(events, at: Self.at(20, 8)) == [[], ["Standup", "Planning"], ["Retro"], []])
    }

    @Test func agendaDropsEventsThatHaveEndedAndKeepsTheOneUnderway() {
        let events = [
            Self.event("Standup", Self.at(20, 9), Self.at(20, 9, 15)),
            Self.event("Design review", Self.at(20, 10), Self.at(20, 11)),
            Self.event("One on one", Self.at(20, 14), Self.at(20, 14, 30)),
        ]
        #expect(Self.agenda(events, at: Self.at(20, 10, 30))[0] == [events[1], events[2]].map(\.title))
    }

    @Test func agendaShowsEventsOnEveryDayTheySpan() {
        let events = [
            Self.event("Hackathon", Self.at(21, 13), Self.at(22, 13)),
            Self.event("Release night", Self.at(20, 22), Self.at(21, 2)),
        ]
        #expect(Self.agenda(events, at: Self.at(20, 12)) == [["Release night"], ["Release night", "Hackathon"], ["Hackathon"], []])
    }

    @Test func eventIsUnderwayFromStartUntilEnd() {
        let standup = Self.event("Standup", Self.at(20, 9), Self.at(20, 9, 15))
        #expect(!standup.isUnderway(at: Self.at(20, 8, 59)))
        #expect(standup.isUnderway(at: Self.at(20, 9)))
        #expect(!standup.isUnderway(at: Self.at(20, 9, 15)))
    }

}
