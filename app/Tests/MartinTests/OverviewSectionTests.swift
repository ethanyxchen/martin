import Foundation
import MartinKit
import Testing
@testable import Martin

@MainActor
struct OverviewSectionTests {
    let calendar = Calendar(identifier: .gregorian)
    let task = Overview.Task(title: "Agent", caption: "Merged.")

    func date(_ month: Int, _ day: Int, year: Int = 2026, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func recentDaysReadAsWordsAndOlderOnesAsDates() {
        let now = date(11, 17, hour: 23)
        #expect(OverviewSection.stamp(date(11, 17, hour: 0), now: now, calendar: calendar) == "Today")
        #expect(OverviewSection.stamp(date(11, 16, hour: 0), now: now, calendar: calendar) == "Yesterday")
        #expect(OverviewSection.stamp(date(11, 14, hour: 0), now: now, calendar: calendar) == date(11, 14, hour: 0).formatted(.dateTime.month(.abbreviated).day()))
        #expect(OverviewSection.stamp(date(12, 2, year: 2025, hour: 0), now: now, calendar: calendar) == date(12, 2, year: 2025, hour: 0).formatted(.dateTime.month(.abbreviated).day().year()))
    }

    @Test func shelvedFoldsAfterTwoUnlessOnlyOneWouldHide() {
        #expect(OverviewSection.shown(Array(repeating: task, count: 4), in: .shelved, unfolded: false).count == 2)
        #expect(OverviewSection.shown(Array(repeating: task, count: 3), in: .shelved, unfolded: false).count == 3)
        #expect(OverviewSection.shown(Array(repeating: task, count: 4), in: .shelved, unfolded: true).count == 4)
        #expect(OverviewSection.shown(Array(repeating: task, count: 6), in: .next, unfolded: false).count == 6)
    }

    @Test func aFailedRefreshOffersToTryAgain() {
        #expect(OverviewStatus.ready.action == "Refresh")
        #expect(OverviewStatus.refreshing.action == "Refresh")
        #expect(OverviewStatus.failed("Couldn't refresh.").action == "Try Again")
    }
}
