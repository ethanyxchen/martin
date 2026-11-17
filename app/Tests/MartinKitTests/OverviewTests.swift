import Foundation
import Testing
@testable import MartinKit

struct OverviewTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        return calendar
    }()

    @Test func aTasksDayIsMidnightOfThatDayInTheGivenCalendar() throws {
        let day = try #require(Overview.Task(title: "Agent", caption: "Merged.", updated: "2026-11-17").day(in: calendar))
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: day) == DateComponents(year: 2026, month: 11, day: 17, hour: 0))
    }

    @Test func aTaskWithoutAReadableDayHasNone() {
        #expect(Overview.Task(title: "Agent", caption: "Merged.").day(in: calendar) == nil)
        #expect(Overview.Task(title: "Agent", caption: "Merged.", updated: "last week").day(in: calendar) == nil)
    }

    @Test func sectionsReadTheirTasks() {
        let task = Overview.Task(title: "Agent", caption: "Merged.")
        let overview = Overview(now: [task], next: [], shelved: [task, task], readAt: .now)
        #expect(Overview.Section.allCases.map { overview[$0].count } == [1, 0, 2])
    }
}
