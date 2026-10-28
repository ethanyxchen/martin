import MartinKit
import Testing
@testable import Martin

struct ProjectPickerTests {
    let atlas = Project(id: "atlas", name: "Atlas Redesign")
    let hiring = Project(id: "hiring", name: "Hiring")

    @Test func anUnfiledNoteIsOfferedEveryProject() {
        #expect(ProjectOption.options(for: "", in: [atlas, hiring], current: nil) == ([.project(atlas), .project(hiring)], []))
    }

    @Test func aFiledNoteIsOfferedTheOtherProjectsAndUnassigned() {
        #expect(ProjectOption.options(for: "", in: [atlas, hiring], current: "atlas") == ([.project(hiring)], [.unassigned]))
    }

    @Test func typingNarrowsTheProjectsAndOffersANewOne() {
        #expect(ProjectOption.options(for: " re ", in: [atlas, hiring], current: nil) == ([.project(atlas)], [.new("re")]))
        #expect(ProjectOption.options(for: "Brand", in: [atlas, hiring], current: "atlas") == ([], [.new("Brand"), .unassigned]))
    }

    @Test func anExistingNameIsNotOfferedAsANewProject() {
        #expect(ProjectOption.options(for: "hiring", in: [atlas, hiring], current: nil) == ([.project(hiring)], []))
    }
}
