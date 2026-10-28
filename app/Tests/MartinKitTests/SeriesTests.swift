import Foundation
import Testing
@testable import MartinKit

struct SeriesTests {
    private func meeting(_ id: String, _ occurrence: Occurrence? = nil) -> Meeting {
        Meeting(id: id, startedAt: Date(timeIntervalSince1970: 1_750_000_000), occurrence: occurrence)
    }

    @Test func recurringMeetingsAreGroupedBySeriesAndEverythingElseComesLast() {
        let standup = "standup@example.com", retro = "retro@example.com"
        let meetings = [
            meeting("adhoc"),
            meeting("standup-2", Occurrence(series: standup, start: Date(timeIntervalSince1970: 2))),
            meeting("review", Occurrence(series: "review@example.com")),
            meeting("retro-1", Occurrence(series: retro, start: Date(timeIntervalSince1970: 1))),
            meeting("standup-1", Occurrence(series: standup, start: Date(timeIntervalSince1970: 1))),
        ]
        #expect(meetings.series.map(\.id) == [.recurring(standup), .recurring(retro), .other])
        #expect(meetings.series.map { $0.meetings.map(\.id) } == [["standup-2", "standup-1"], ["retro-1"], ["adhoc", "review"]])
    }

    @Test func noMeetingsMakeNoSeries() {
        #expect([Meeting]().series.isEmpty)
    }
}
