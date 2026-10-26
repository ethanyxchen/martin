import Foundation
import Testing
@testable import MartinKit

struct MeetingLibraryTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))

    @Test func createdMeetingKeepsCalendarDetails() throws {
        let occurrence = Occurrence(series: "standup@example.com", start: Date(timeIntervalSince1970: 1_750_000_000))
        let meeting = try library.create(startedAt: Date(timeIntervalSince1970: 1_749_999_000), scheduledAt: Date(timeIntervalSince1970: 1_750_000_300), occurrence: occurrence, title: "Standup")
        let reloaded = try #require(try library.meetings().first)
        #expect(reloaded.date == Date(timeIntervalSince1970: 1_750_000_300))
        #expect(reloaded.occurrence == occurrence)
        #expect(reloaded.title == "Standup")
        #expect(library.note(of: meeting) == nil)
    }

    @Test func meetingForOccurrenceFindsOnlyThatOccurrence() throws {
        let monday = Occurrence(series: "standup@example.com", start: Date(timeIntervalSince1970: 1_750_000_000))
        let tuesday = Occurrence(series: "standup@example.com", start: Date(timeIntervalSince1970: 1_750_086_400))
        let review = Occurrence(series: "review@example.com")
        let mondayMeeting = try library.create(startedAt: Date(timeIntervalSince1970: 1_750_000_000), occurrence: monday)
        let reviewMeeting = try library.create(startedAt: Date(timeIntervalSince1970: 1_750_000_100), occurrence: review)
        #expect(try library.meeting(for: monday) == mondayMeeting)
        #expect(try library.meeting(for: review) == reviewMeeting)
        #expect(try library.meeting(for: tuesday) == nil)
    }

    @Test func meetingsStartedInTheSameSecondDoNotOverwriteEachOther() throws {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let first = try library.create(startedAt: startedAt, title: "Standup")
        #expect(throws: (any Error).self) { try library.create(startedAt: startedAt.addingTimeInterval(0.5), title: "Retro") }
        #expect(try library.meetings() == [first])
    }

    @Test func meetingWithoutScheduleIsDatedWhenStarted() throws {
        let meeting = try library.create(startedAt: Date(timeIntervalSince1970: 1_750_000_000))
        #expect(meeting.date == meeting.startedAt)
    }

    @Test func noteRoundTripsByteForByte() throws {
        let meeting = try library.create()
        let note = "# Café ☕️ 会议\r\n\n- [x] **done** \t\n```\n  indented `code`\n```\n> “quoted” — 👩🏽‍💻"
        try library.saveNote(note, for: meeting)
        #expect(try Data(contentsOf: library.folder(of: meeting).appending(path: "note.md")) == Data(note.utf8))
        #expect(library.note(of: meeting) == note)
    }

    @Test func createdMeetingEqualsReloadedMeeting() throws {
        let meeting = try library.create(startedAt: Date(timeIntervalSince1970: 1_750_000_000.75))
        #expect(try library.meetings() == [meeting])
    }

    @Test func meetingsAreNewestFirst() throws {
        let older = try library.create(startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = try library.create(startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try library.meetings().map(\.id) == [newer.id, older.id])
    }
}
