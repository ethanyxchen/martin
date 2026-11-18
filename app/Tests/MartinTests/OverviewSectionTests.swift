import Foundation
import MartinKit
import Testing
@testable import Martin

@MainActor
struct OverviewSectionTests {
    let calendar = Calendar(identifier: .gregorian)
    let task = Overview.Item(title: "Agent", caption: "Merged.")

    func date(_ month: Int, _ day: Int, year: Int = 2026, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func daysReadAsWordsThisWeekAndAsDatesBefore() {
        let now = date(11, 17, hour: 23)
        #expect(OverviewSection.stamp(date(11, 18, hour: 0), now: now, calendar: calendar) == "Today")
        #expect(OverviewSection.stamp(date(11, 17, hour: 0), now: now, calendar: calendar) == "Today")
        #expect(OverviewSection.stamp(date(11, 16, hour: 0), now: now, calendar: calendar) == "Yesterday")
        #expect(OverviewSection.stamp(date(11, 14, hour: 0), now: now, calendar: calendar) == date(11, 14, hour: 0).formatted(.dateTime.weekday(.wide)))
        #expect(OverviewSection.stamp(date(11, 3, hour: 0), now: now, calendar: calendar) == date(11, 3, hour: 0).formatted(.dateTime.month(.abbreviated).day()))
        #expect(OverviewSection.stamp(date(12, 2, year: 2025, hour: 0), now: now, calendar: calendar) == date(12, 2, year: 2025, hour: 0).formatted(.dateTime.month(.abbreviated).day().year()))
    }

    @Test func aDayIsWrittenInTheCalendarsTimeZone() {
        var auckland = calendar
        auckland.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let day = auckland.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let expected = day.formatted(Date.FormatStyle(timeZone: auckland.timeZone).month(.abbreviated).day())
        #expect(OverviewSection.stamp(day, now: day.addingTimeInterval(30 * 86_400), calendar: auckland) == expected)
    }

    @Test func shelvedFoldsAfterTwoUnlessOnlyOneWouldHide() {
        #expect(OverviewSection.shown(Array(repeating: task, count: 4), in: .shelved, unfolded: false).count == 2)
        #expect(OverviewSection.shown(Array(repeating: task, count: 3), in: .shelved, unfolded: false).count == 3)
        #expect(OverviewSection.shown(Array(repeating: task, count: 4), in: .shelved, unfolded: true).count == 4)
        #expect(OverviewSection.shown(Array(repeating: task, count: 6), in: .next, unfolded: false).count == 6)
        #expect(OverviewSection.folds(Array(repeating: task, count: 4), in: .shelved))
        #expect(!OverviewSection.folds(Array(repeating: task, count: 3), in: .shelved))
    }

    @Test func ageIsMeasuredFromTheGivenNowAndNeverInTheFuture() {
        let now = date(11, 17)
        #expect(OverviewSection.age(of: now.addingTimeInterval(-3600), now: now) == RelativeDateTimeFormatter().localizedString(for: now.addingTimeInterval(-3600), relativeTo: now))
        #expect(OverviewSection.age(of: now.addingTimeInterval(5), now: now) == RelativeDateTimeFormatter().localizedString(for: now, relativeTo: now))
    }

    @Test func aFailedRefreshOffersToTryAgainAndARunningOneOffersNothing() {
        #expect(OverviewStatus.ready.action == "Refresh")
        #expect(OverviewStatus.refreshing.action == nil)
        #expect(OverviewStatus.failed("Couldn't refresh.").action == "Try Again")
    }

    @Test func aRefreshKeepsTheAgeOfTheOverviewItReplaces() {
        let now = date(11, 17)
        let overview = Overview(now: [], next: [], shelved: [], readAt: now.addingTimeInterval(-7200))
        let updated = "Updated \(OverviewSection.age(of: overview.readAt, now: now))"
        #expect(OverviewSection.caption(overview, status: .ready, now: now) == updated)
        #expect(OverviewSection.caption(overview, status: .refreshing, now: now) == "\(updated) · refreshing")
        #expect(OverviewSection.caption(nil, status: .refreshing, now: now) == "Refreshing…")
        #expect(OverviewSection.caption(nil, status: .ready, now: now) == nil)
    }
}
