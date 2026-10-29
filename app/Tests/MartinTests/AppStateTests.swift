import Foundation
import MartinKit
import Testing
@testable import Martin

@MainActor
final class AppStateTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
    let suite = UUID().uuidString
    lazy var defaults = UserDefaults(suiteName: suite)!

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: library.root)
    }

    @Test func pageAndHiddenPagesAreRememberedAcrossLaunches() {
        let app = AppState(library: library, defaults: defaults)
        app.page = .projects
        app.hiddenPages = [.upcoming]
        let relaunched = AppState(library: library, defaults: defaults)
        #expect(relaunched.page == .projects)
        #expect(relaunched.hiddenPages == [.upcoming])
    }

    @Test func pageShortcutsNumberTheShownPagesAndStayPutOnAHiddenPage() {
        let app = AppState(library: library, defaults: defaults)
        app.hiddenPages = [.notes]
        app.page = .notes
        #expect(HomePage.allCases.map(app.shortcut(of:)) == [nil, 1, 2, 3])
    }

    @Test func savingANoteUpdatesItsPreview() throws {
        let meeting = try library.create(title: "Standup")
        try library.saveNote("# Before", for: meeting)
        let app = AppState(library: library, defaults: defaults)
        #expect(app.previews[meeting.id] == "Before")
        app.save("- shipped **icons**", for: meeting)
        #expect(app.previews[meeting.id] == "shipped icons")
        #expect(library.note(of: meeting) == "- shipped **icons**")
    }

    @Test func archivingMovesANoteToTheArchiveAndRestoringBringsItBack() throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults)
        app.archive(meeting)
        #expect(app.notes.isEmpty)
        #expect(app.archive.map(\.id) == [meeting.id])
        #expect(AppState(library: library, defaults: defaults).archive.map(\.id) == [meeting.id])
        app.restore(try #require(app.meeting(meeting.id)))
        #expect(app.notes.map(\.id) == [meeting.id])
        #expect(app.archive.isEmpty)
    }

    @Test func deletingANoteRemovesItForGood() throws {
        let meeting = try library.create(title: "Standup")
        try library.saveNote("# Secret", for: meeting)
        let app = AppState(library: library, defaults: defaults)
        app.delete(meeting)
        #expect(app.meetings.isEmpty)
        #expect(app.previews[meeting.id] == nil)
        #expect(try library.meetings().isEmpty)
    }

    @Test func archivingKeepsARenameMadeAfterTheNoteWasPickedUp() throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults)
        app.rename(meeting, to: "Retro")
        app.archive(meeting)
        #expect(app.archive.map(\.title) == ["Retro"])
    }

    @Test func filingANoteIntoANewProjectShelvesItThere() throws {
        let meeting = try library.create(title: "Kickoff")
        let app = AppState(library: library, defaults: defaults)
        app.file(meeting, inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        #expect(atlas.name == "Atlas")
        #expect(app.project(of: try #require(app.meeting(meeting.id))) == atlas)
        #expect(app.notes.shelved(in: app.projects).map(\.id) == [.project(atlas.id)])
        app.file(meeting, in: nil)
        #expect(app.notes.shelved(in: app.projects).map(\.id) == [.project(atlas.id), .unassigned])
    }

    @Test func aNoteIsLabelledWithItsProjectEvenOnceTheProjectIsArchived() throws {
        let app = AppState(library: library, defaults: defaults)
        let meeting = try library.create(title: "Kickoff")
        app.reload()
        #expect(app.projectName(of: meeting) == "Unassigned")
        app.file(meeting, inNewProjectNamed: "Atlas")
        let filed = try #require(app.meeting(meeting.id))
        #expect(app.projectName(of: filed) == "Atlas")
        app.archive(try #require(app.projects.first))
        #expect(app.projectName(of: filed) == "Atlas")
    }

    @Test func pinnedNotesComeFirstUntilUnpinnedAndSkipTheArchive() throws {
        let older = try library.create(startedAt: .now.addingTimeInterval(-60), title: "Older")
        let newer = try library.create(title: "Newer")
        let app = AppState(library: library, defaults: defaults)
        #expect(app.pinned.isEmpty)
        app.pin(older, true)
        #expect(app.pinned.map(\.id) == [older.id])
        #expect(app.unpinned.map(\.id) == [newer.id])
        app.archive(try #require(app.meeting(older.id)))
        #expect(app.pinned.isEmpty)
        app.restore(try #require(app.meeting(older.id)))
        #expect(app.pinned.map(\.id) == [older.id])
        app.pin(try #require(app.meeting(older.id)), false)
        #expect(app.pinned.isEmpty)
        #expect(app.unpinned.map(\.id) == [newer.id, older.id])
    }

    @Test func aNoteWithoutAMeetingIsAQuickNote() throws {
        #expect(try library.create().displayTitle == "Quick note")
        #expect(try library.create(startedAt: .distantPast, occurrence: Occurrence(series: "review@example.com")).displayTitle == "Meeting")
    }

    @Test func theTabsRunFromAllNotesThroughProjectsAndUpcomingToSettings() {
        #expect(HomePage.allCases == [.notes, .projects, .upcoming, .settings])
    }

    @Test func archivingAProjectMovesItAndItsNotesToTheArchive() throws {
        let app = AppState(library: library, defaults: defaults)
        let meeting = try library.create(title: "Kickoff")
        app.file(meeting, inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        app.archive(atlas)
        #expect(app.projects.isEmpty)
        #expect(app.archivedProjects.map(\.id) == [atlas.id])
        #expect(app.notes.isEmpty)
        app.restore(try #require(app.archivedProjects.first))
        #expect(app.projects.map(\.id) == [atlas.id])
        #expect(app.notes.map(\.id) == [meeting.id])
    }

    @Test func renamingAProjectIgnoresABlankName() throws {
        let app = AppState(library: library, defaults: defaults)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        app.rename(try #require(app.projects.first), to: "  Atlas Redesign ")
        #expect(app.projects.map(\.name) == ["Atlas Redesign"])
        app.rename(try #require(app.projects.first), to: "   ")
        #expect(app.projects.map(\.name) == ["Atlas Redesign"])
    }

    @Test func renamingAProjectArchivedSinceKeepsItArchived() throws {
        let app = AppState(library: library, defaults: defaults)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        app.archive(atlas)
        app.rename(atlas, to: "Atlas Redesign")
        #expect(app.projects.isEmpty)
        #expect(app.archivedProjects.map(\.name) == ["Atlas Redesign"])
    }

    @Test func deletingAProjectDeletesItsNotes() throws {
        let app = AppState(library: library, defaults: defaults)
        let kept = try library.create(startedAt: .distantPast)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        app.delete(try #require(app.projects.first))
        #expect(app.allProjects.isEmpty)
        #expect(app.meetings.map(\.id) == [kept.id])
    }

    @Test func aRepositoryIsTurnedOnThenLinkedAndRememberedUntilRemoved() throws {
        let app = AppState(library: library, defaults: defaults)
        app.file(try library.create(), inNewProjectNamed: "Martin")
        #expect(app.projects.map(\.repository) == [nil])
        app.link(try #require(app.projects.first), to: .unset)
        #expect(AppState(library: library, defaults: defaults).projects.map(\.repository) == [.unset])
        let folder = URL(filePath: "/Users/ada/Developer/martin", directoryHint: .isDirectory)
        app.link(try #require(app.projects.first), to: .folder(folder))
        #expect(AppState(library: library, defaults: defaults).projects.map(\.repository) == [.folder(folder)])
        app.link(try #require(app.projects.first), to: nil)
        #expect(AppState(library: library, defaults: defaults).projects.map(\.repository) == [nil])
    }

    @Test func linkingAProjectArchivedSinceKeepsItArchived() throws {
        let app = AppState(library: library, defaults: defaults)
        app.file(try library.create(), inNewProjectNamed: "Martin")
        let martin = try #require(app.projects.first)
        app.archive(martin)
        app.link(martin, to: .folder(URL(filePath: "/Users/ada/Developer/martin", directoryHint: .isDirectory)))
        #expect(app.projects.isEmpty)
        #expect(app.archivedProjects.map(\.repository?.folder?.lastPathComponent) == ["martin"])
    }

    @Test func theChosenAssistantIsRememberedAcrossLaunches() {
        let app = AppState(library: library, defaults: defaults, finder: finding(nil))
        #expect(app.assistant == nil)
        app.use(.codex)
        #expect(AppState(library: library, defaults: defaults).assistant == .codex)
        app.assistant = nil
        #expect(AppState(library: library, defaults: defaults).assistant == nil)
    }

    @Test func noRepositoryIsSoughtWithoutAnAssistantOrForALinkedProject() async throws {
        let app = AppState(library: library, defaults: defaults, finder: finding(nil))
        app.file(try library.create(), inNewProjectNamed: "Martin")
        await app.suggestRepositories()
        #expect(app.suggestions.isEmpty)
        app.link(try #require(app.projects.first), to: .folder(URL(filePath: "/Users/ada/Developer/martin", directoryHint: .isDirectory)))
        app.assistant = .claude
        await app.suggestRepositories()
        #expect(app.suggestions.isEmpty)
    }

    private func clone(_ name: String) throws -> Repository {
        let folder = library.root.appending(path: "clones/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: ".git"), withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = git@github.com:ethanyxchen/\(name).git\n".write(to: folder.appending(path: ".git/config"), atomically: true, encoding: .utf8)
        return try #require(Repository(at: folder))
    }

    private func finding(_ repository: Repository?) -> RepositoryFinder {
        RepositoryFinder(nearby: { _ in [] }, pick: { _, _, _, _ in repository })
    }

    @Test func aRepositoryFoundInTheBackgroundIsLinkedTheMomentItIsTurnedOn() async throws {
        let martin = try clone("martin")
        let app = AppState(library: library, defaults: defaults, finder: finding(martin))
        app.file(try library.create(), inNewProjectNamed: "Martin")
        app.assistant = .claude
        await app.suggestRepositories()
        #expect(app.projects.map(\.repository) == [nil])
        app.addRepository(to: try #require(app.projects.first))
        #expect(app.projects.map(\.repository) == [.folder(martin.folder)])
    }

    @Test func aRepositoryTurnedOnBeforeItIsFoundIsLinkedOnceItIs() async throws {
        let martin = try clone("martin")
        let app = AppState(library: library, defaults: defaults, finder: finding(martin))
        app.file(try library.create(), inNewProjectNamed: "Martin")
        app.assistant = .claude
        app.addRepository(to: try #require(app.projects.first))
        #expect(app.projects.map(\.repository) == [.unset])
        await app.suggestRepository(for: try #require(app.projects.first))
        #expect(app.projects.map(\.repository) == [.folder(martin.folder)])
    }

    @Test func withNothingFoundTurningItOnLeavesTheRepositoryToChoose() async throws {
        let app = AppState(library: library, defaults: defaults, finder: finding(nil))
        app.file(try library.create(), inNewProjectNamed: "Interviews")
        app.assistant = .claude
        await app.suggestRepositories()
        app.addRepository(to: try #require(app.projects.first))
        #expect(app.projects.map(\.repository) == [.unset])
    }
}
