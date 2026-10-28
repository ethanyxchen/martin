import Foundation
import Testing
@testable import MartinKit

struct MeetingLibraryTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))

    @Test func createdMeetingKeepsCalendarDetails() throws {
        let occurrence = Occurrence(series: "standup@example.com", start: Date(timeIntervalSince1970: 1_750_000_000))
        let meeting = try library.create(startedAt: Date(timeIntervalSince1970: 1_749_999_000), occurrence: occurrence, title: "Standup")
        let reloaded = try #require(try library.meetings().first)
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

    @Test func meetingForEventIsDatedByTheEventAndFollowsItsReschedule() throws {
        let occurrence = Occurrence(series: "review@example.com")
        let event = CalendarEvent(occurrence: occurrence, title: "Review", start: Date(timeIntervalSince1970: 1_750_172_800), end: Date(timeIntervalSince1970: 1_750_176_400))
        let meeting = try library.meeting(for: event)
        #expect(meeting.date == event.start)
        #expect(meeting.title == "Review")
        let moved = CalendarEvent(occurrence: occurrence, title: "Review", start: Date(timeIntervalSince1970: 1_750_259_200), end: Date(timeIntervalSince1970: 1_750_262_800))
        #expect(try library.meeting(for: moved).id == meeting.id)
        #expect(try library.meetings().map(\.date) == [moved.start])
    }

    @Test func meetingForEventKeepsTheEventsAttendeesInStep() throws {
        let occurrence = Occurrence(series: "review@example.com")
        let ada = Person(email: "ada@example.com", name: "Ada Lovelace"), kim = Person(email: "kim.k@example.com")
        let start = Date(timeIntervalSince1970: 1_750_172_800), end = Date(timeIntervalSince1970: 1_750_176_400)
        let meeting = try library.meeting(for: CalendarEvent(occurrence: occurrence, title: "Review", start: start, end: end, attendees: [ada]))
        #expect(try library.meetings().map(\.attendees) == [[ada]])
        let invited = try library.meeting(for: CalendarEvent(occurrence: occurrence, title: "Review", start: start, end: end, attendees: [ada, kim]))
        #expect(invited.id == meeting.id)
        #expect(try library.meetings().map(\.attendees) == [[ada, kim]])
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

    @Test func meetingsAreOrderedByTheirMeetingDateNotWhenTheNoteWasStarted() throws {
        let earlyNote = try library.meeting(for: CalendarEvent(occurrence: Occurrence(series: "review@example.com"), title: "Review", start: Date(timeIntervalSince1970: 1_900_000_000), end: Date(timeIntervalSince1970: 1_900_003_600)))
        let adHoc = try library.create(startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try library.meetings().map(\.id) == [earlyNote.id, adHoc.id])
    }

    @Test func archivedMeetingStaysArchivedAfterReload() throws {
        var meeting = try library.create(startedAt: Date(timeIntervalSince1970: 1_750_000_000))
        meeting.archivedAt = Date(timeIntervalSince1970: 1_750_000_600)
        try library.save(meeting)
        #expect(try library.meetings().map(\.archivedAt) == [meeting.archivedAt])
    }

    @Test func deletedMeetingLeavesNothingBehind() throws {
        let kept = try library.create(startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let deleted = try library.create(startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try library.saveNote("# Gone", for: deleted)
        try library.delete(deleted)
        #expect(try library.meetings() == [kept])
        #expect(!FileManager.default.fileExists(atPath: library.folder(of: deleted).path))
    }

    @Test func meetingForEventBringsItsArchivedNoteBack() throws {
        let event = CalendarEvent(occurrence: Occurrence(series: "review@example.com"), title: "Review", start: Date(timeIntervalSince1970: 1_750_172_800), end: Date(timeIntervalSince1970: 1_750_176_400))
        var meeting = try library.meeting(for: event)
        meeting.archivedAt = Date(timeIntervalSince1970: 1_750_180_000)
        try library.save(meeting)
        #expect(try library.meeting(for: event).archivedAt == nil)
        #expect(try library.meetings().map(\.archivedAt) == [nil])
    }
}

struct ProjectFilingTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
    let sync = "sync@example.com"

    private func start(on day: Int) -> Date {
        Date(timeIntervalSince1970: 1_750_000_000 + Double(day) * 86_400)
    }

    private func syncNote(on day: Int) throws -> Meeting {
        try library.create(startedAt: start(on: day), occurrence: Occurrence(series: sync, start: start(on: day)), title: "Design Sync")
    }

    private func occurrence(on day: Int) -> CalendarEvent {
        CalendarEvent(occurrence: Occurrence(series: sync, start: start(on: day)), title: "Design Sync", start: start(on: day), end: start(on: day).addingTimeInterval(3_600))
    }

    @Test func createdProjectsAreKeptInOrder() throws {
        let atlas = try library.createProject(named: "Atlas")
        let hiring = try library.createProject(named: "Hiring")
        #expect(try library.projects() == [atlas, hiring])
    }

    @Test func filingARecurringNoteFilesItsLaterNotesButLeavesEarlierOnesAlone() throws {
        let atlas = try library.createProject(named: "Atlas")
        let earlier = try syncNote(on: 0)
        try library.file(syncNote(on: 1), in: atlas.id)
        #expect(try library.meeting(for: occurrence(on: 2)).project == atlas.id)
        #expect(try library.meetings().map(\.project) == [atlas.id, atlas.id, nil])
        #expect(try library.meetings().last?.id == earlier.id)
    }

    @Test func refilingARecurringNoteMovesItsSeriesAndUnassigningStopsIt() throws {
        let atlas = try library.createProject(named: "Atlas")
        let hiring = try library.createProject(named: "Hiring")
        let first = try syncNote(on: 0)
        try library.file(first, in: atlas.id)
        try library.file(first, in: hiring.id)
        #expect(try library.projects().map(\.series) == [[], [sync]])
        try library.file(first, in: nil)
        #expect(try library.projects().map(\.series) == [[], []])
        #expect(try library.meeting(for: occurrence(on: 1)).project == nil)
    }

    @Test func filingAOneOffNoteFollowsNothing() throws {
        let atlas = try library.createProject(named: "Atlas")
        try library.file(library.create(startedAt: start(on: 0), occurrence: Occurrence(series: "review@example.com"), title: "Review"), in: atlas.id)
        try library.file(library.create(startedAt: Date(timeIntervalSince1970: 1_700_000_000)), in: atlas.id)
        #expect(try library.projects().map(\.series) == [[]])
        #expect(try library.meetings().map(\.project) == [atlas.id, atlas.id])
    }
}

struct ProjectLifecycleTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))

    private func note(_ seconds: TimeInterval, in project: Project.ID?) throws -> Meeting {
        try library.create(startedAt: Date(timeIntervalSince1970: seconds), project: project)
    }

    @Test func renamingAProjectKeepsItsPlace() throws {
        var atlas = try library.createProject(named: "Atlas")
        let hiring = try library.createProject(named: "Hiring")
        atlas.name = "Atlas Redesign"
        try library.save(atlas)
        #expect(try library.projects().map(\.name) == ["Atlas Redesign", "Hiring"])
        #expect(try library.projects().first == atlas)
        #expect(try library.projects().last == hiring)
    }

    @Test func archivingAProjectArchivesItsNotesAndRestoringBringsBackOnlyThose() throws {
        let atlas = try library.createProject(named: "Atlas")
        var earlier = try note(1, in: atlas.id)
        earlier.archivedAt = Date(timeIntervalSince1970: 100)
        try library.save(earlier)
        let open = try note(2, in: atlas.id)
        let other = try note(3, in: nil)
        try library.archive(atlas, at: Date(timeIntervalSince1970: 200.7))
        let archived = try #require(try library.projects().first)
        #expect(archived.archivedAt == Date(timeIntervalSince1970: 200))
        #expect(try library.meetings().map(\.archivedAt) == [nil, Date(timeIntervalSince1970: 200), Date(timeIntervalSince1970: 100)])
        try library.restore(archived)
        #expect(try library.projects().first?.archivedAt == nil)
        #expect(try library.meetings().map(\.id) == [other.id, open.id, earlier.id])
        #expect(try library.meetings().map(\.archivedAt) == [nil, nil, Date(timeIntervalSince1970: 100)])
    }

    @Test func anArchivedProjectStopsFilingItsRecurringMeeting() throws {
        let atlas = try library.createProject(named: "Atlas")
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try library.file(library.create(startedAt: start, occurrence: Occurrence(series: "sync@example.com", start: start)), in: atlas.id)
        try library.archive(atlas)
        let next = start.addingTimeInterval(86_400)
        #expect(try library.meeting(for: CalendarEvent(occurrence: Occurrence(series: "sync@example.com", start: next), title: "Sync", start: next, end: next)).project == nil)
    }

    @Test func deletingAProjectDeletesEveryNoteInIt() throws {
        let atlas = try library.createProject(named: "Atlas")
        let hiring = try library.createProject(named: "Hiring")
        var archived = try note(1, in: atlas.id)
        archived.archivedAt = .now
        try library.save(archived)
        _ = try note(2, in: atlas.id)
        let kept = try note(3, in: hiring.id)
        try library.delete(atlas)
        #expect(try library.projects() == [hiring])
        #expect(try library.meetings() == [kept])
    }
}
