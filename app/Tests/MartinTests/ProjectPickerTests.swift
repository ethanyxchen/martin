import MartinKit
import Testing
@testable import Martin

struct ProjectPickerTests {
    let atlas = Project(id: "atlas", name: "Atlas Redesign")
    let hiring = Project(id: "hiring", name: "Hiring")

    @Test func theFullListOpensWithUnassignedLast() {
        #expect(ProjectOption.options(for: "", in: [atlas, hiring]) == ([.project(atlas), .project(hiring)], [.unassigned]))
    }

    @Test func typingNarrowsTheListAndOffersToCreateTheName() {
        #expect(ProjectOption.options(for: " re ", in: [atlas, hiring]) == ([.project(atlas)], [.new("re")]))
        #expect(ProjectOption.options(for: "Goodmeet", in: [atlas, hiring]) == ([], [.new("Goodmeet")]))
    }

    @Test func anExistingNameIsNotOfferedAsANewProject() {
        #expect(ProjectOption.options(for: "hiring", in: [atlas, hiring]) == ([.project(hiring)], []))
    }

    @Test func theCreateRowNamesTheProject() {
        #expect(ProjectOption.new("Goodmeet").title == "Create “Goodmeet”")
    }
}
