import Foundation
import Testing
@testable import Martin

struct NotesPageTests {
    @Test func stampReadsLikeAChatList() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 15)))
        func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }
        #expect(ago(0).stamp(at: now) == ago(0).formatted(date: .omitted, time: .shortened))
        #expect(ago(1).stamp(at: now) == "Yesterday")
        #expect(ago(3).stamp(at: now) == ago(3).formatted(.dateTime.weekday(.wide)))
        #expect(ago(7).stamp(at: now) == ago(7).formatted(date: .numeric, time: .omitted))
    }

    @Test func settingsStaysInTheNavigationBarWhenEveryPageIsHidden() {
        #expect(HomePage.shown(hiding: Set(HomePage.allCases), on: .settings) == [.settings])
        #expect(HomePage.shown(hiding: [.upcoming], on: .notes) == [.notes, .projects, .settings])
    }

    @Test func aHiddenPageStaysInTheBarWhileItIsOpen() {
        #expect(HomePage.shown(hiding: [.upcoming], on: .upcoming) == HomePage.allCases)
    }
}
