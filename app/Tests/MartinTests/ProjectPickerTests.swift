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

@MainActor
struct ProjectFieldTests {
    @Test func aNewProjectIsOfferedUnderTheTypedName() {
        #expect(ProjectOption.new("Brand").choice == Dropdown.Choice(badge: "+", title: "Brand", detail: "New project"))
    }

    @Test func theFieldInvitesANewProjectWhenThereAreNone() {
        #expect(ProjectField.prompt(for: []) == "Name a new project")
        #expect(ProjectField.prompt(for: [Project(name: "Atlas")]) == "Find or create a project")
    }

    @Test func theFieldGrowsWithTheNameUpToAWidestWidth() {
        let field = FocusedField()
        field.font = .systemFont(ofSize: 11.5, weight: .medium)
        field.stringValue = "Atlas"
        let short = field.intrinsicContentSize.width
        field.stringValue = "Atlas Redesign"
        #expect(field.intrinsicContentSize.width > short)
        field.stringValue = String(repeating: "Atlas Redesign ", count: 20)
        #expect(field.intrinsicContentSize.width == FocusedField.widest)
    }
}
