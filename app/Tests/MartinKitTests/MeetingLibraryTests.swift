import Foundation
import Testing
@testable import MartinKit

struct MeetingLibraryTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))

    @Test func transcriptRoundTrips() throws {
        let meeting = try library.create(startedAt: Date(timeIntervalSince1970: 1_750_000_000), title: "Standup", attendees: ["Ada"])
        let segments = [Segment(at: 1, duration: 2, text: "hello"), Segment(at: 3.5, duration: 1, text: "ship it")]
        for segment in segments { try library.append(segment, to: meeting) }
        #expect(try library.transcript(of: meeting) == segments)
        #expect(try library.meetings() == [meeting])
    }

    @Test func savingNoteClearsError() throws {
        let meeting = try library.create()
        try library.saveAnalysisError("boom", for: meeting)
        #expect(library.analysisError(of: meeting) == "boom")
        try library.saveNote("# Note", for: meeting)
        #expect(library.note(of: meeting) == "# Note")
        #expect(library.analysisError(of: meeting) == nil)
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
