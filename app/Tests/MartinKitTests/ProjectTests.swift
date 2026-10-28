import Foundation
import Testing
@testable import MartinKit

struct ProjectTests {
    private func meeting(_ id: String, at seconds: TimeInterval, in project: Project.ID? = nil) -> Meeting {
        Meeting(id: id, startedAt: Date(timeIntervalSince1970: seconds), project: project)
    }

    @Test func notesAreShelvedByProjectWithTheLatestFirstAndUnassignedLast() {
        let atlas = Project(id: "atlas", name: "Atlas"), hiring = Project(id: "hiring", name: "Hiring"), empty = Project(id: "empty", name: "Empty")
        let meetings = [
            meeting("debrief", at: 4, in: "hiring"),
            meeting("quick", at: 3),
            meeting("sync", at: 2, in: "atlas"),
            meeting("orphan", at: 1, in: "deleted"),
            meeting("standup", at: 0, in: "atlas"),
        ]
        let shelves = meetings.shelved(in: [atlas, empty, hiring])
        #expect(shelves.map(\.id) == [.project("hiring"), .project("atlas"), .project("empty"), .unassigned])
        #expect(shelves.map { $0.meetings.map(\.id) } == [["debrief"], ["sync", "standup"], [], ["quick", "orphan"]])
    }

    @Test func thereIsNoUnassignedShelfWhenEveryNoteHasAProject() {
        let atlas = Project(id: "atlas", name: "Atlas")
        #expect([meeting("sync", at: 0, in: "atlas")].shelved(in: [atlas]).map(\.id) == [.project("atlas")])
        #expect([Meeting]().shelved(in: []).isEmpty)
    }

    @Test func suggestionsMatchTheStartOfAnyWordInTheName() {
        let atlas = Project(name: "Atlas Redesign"), planning = Project(name: "Q4 Planning")
        #expect([atlas, planning].suggestions(for: "") == [atlas, planning])
        #expect([atlas, planning].suggestions(for: "re") == [atlas])
        #expect([atlas, planning].suggestions(for: "PLAN") == [planning])
        #expect([atlas, planning].suggestions(for: "sign").isEmpty)
    }
}
