import Foundation
import MartinKit
import Testing
@testable import Martin

@MainActor
final class AppStateTests: Sandbox {
    @Test func pageAndHiddenPagesAreRememberedAcrossLaunches() {
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.page = .projects
        app.hiddenPages = [.upcoming]
        let relaunched = AppState(library: library, defaults: defaults, credentials: credentials)
        #expect(relaunched.page == .projects)
        #expect(relaunched.hiddenPages == [.upcoming])
    }

    @Test func usageIsSharedUntilTurnedOffAndStaysOffAcrossLaunches() {
        var shared: [Bool] = []
        let app = AppState(library: library, defaults: defaults, credentials: credentials, share: { shared.append($0) })
        #expect(app.sharesUsage)
        app.sharesUsage = false
        let relaunched = AppState(library: library, defaults: defaults, credentials: credentials, share: { shared.append($0) })
        #expect(!relaunched.sharesUsage)
        #expect(shared == [true, false, false])
    }

    @Test func pageShortcutsNumberTheShownPagesAndStayPutOnAHiddenPage() {
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.hiddenPages = [.notes]
        app.page = .notes
        #expect(HomePage.allCases.map(app.shortcut(of:)) == [nil, 1, 2, 3])
    }

    @Test func savingANoteUpdatesItsPreview() throws {
        let meeting = try library.create(title: "Standup")
        try library.saveNote("# Before", for: meeting)
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        #expect(app.previews[meeting.id] == "Before")
        app.save("- shipped **icons**", for: meeting)
        #expect(app.previews[meeting.id] == "shipped icons")
        #expect(library.note(of: meeting) == "- shipped **icons**")
    }

    @Test func archivingMovesANoteToTheArchiveAndRestoringBringsItBack() throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.archive(meeting)
        #expect(app.notes.isEmpty)
        #expect(app.archive.map(\.id) == [meeting.id])
        #expect(AppState(library: library, defaults: defaults, credentials: credentials).archive.map(\.id) == [meeting.id])
        app.restore(try #require(app.meeting(meeting.id)))
        #expect(app.notes.map(\.id) == [meeting.id])
        #expect(app.archive.isEmpty)
    }

    @Test func deletingANoteRemovesItForGood() throws {
        let meeting = try library.create(title: "Standup")
        try library.saveNote("# Secret", for: meeting)
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.delete(meeting)
        #expect(app.meetings.isEmpty)
        #expect(app.previews[meeting.id] == nil)
        #expect(try library.meetings().isEmpty)
    }

    @Test func archivingKeepsARenameMadeAfterTheNoteWasPickedUp() throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.rename(meeting, to: "Retro")
        app.archive(meeting)
        #expect(app.archive.map(\.title) == ["Retro"])
    }

    @Test func filingANoteIntoANewProjectShelvesItThere() throws {
        let meeting = try library.create(title: "Kickoff")
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.file(meeting, inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        #expect(atlas.name == "Atlas")
        #expect(app.project(of: try #require(app.meeting(meeting.id))) == atlas)
        #expect(app.shelves.map(\.id) == [.project(atlas.id)])
        app.file(meeting, in: nil)
        #expect(app.shelves.map(\.id) == [.project(atlas.id), .unassigned])
    }

    @Test func aNoteIsLabelledWithItsProjectEvenOnceTheProjectIsArchived() throws {
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
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
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
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
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
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
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        app.rename(try #require(app.projects.first), to: "  Atlas Redesign ")
        #expect(app.projects.map(\.name) == ["Atlas Redesign"])
        app.rename(try #require(app.projects.first), to: "   ")
        #expect(app.projects.map(\.name) == ["Atlas Redesign"])
    }

    @Test func renamingAProjectArchivedSinceKeepsItArchived() throws {
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        app.archive(atlas)
        app.rename(atlas, to: "Atlas Redesign")
        #expect(app.projects.isEmpty)
        #expect(app.archivedProjects.map(\.name) == ["Atlas Redesign"])
    }

    @Test func deletingAProjectDeletesItsNotes() throws {
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        let kept = try library.create(startedAt: .distantPast)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        app.delete(try #require(app.projects.first))
        #expect(app.allProjects.isEmpty)
        #expect(app.meetings.map(\.id) == [kept.id])
    }

    @Test func aRepositoryIsTurnedOnThenLinkedAndRememberedUntilRemoved() throws {
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.file(try library.create(), inNewProjectNamed: "Martin")
        #expect(app.projects.map(\.repository) == [nil])
        app.link(try #require(app.projects.first), to: .unset)
        #expect(AppState(library: library, defaults: defaults, credentials: credentials).projects.map(\.repository) == [.unset])
        let folder = URL(filePath: "/Users/ada/Developer/martin", directoryHint: .isDirectory)
        app.link(try #require(app.projects.first), to: .folder(folder))
        #expect(AppState(library: library, defaults: defaults, credentials: credentials).projects.map(\.repository) == [.folder(folder)])
        app.link(try #require(app.projects.first), to: nil)
        #expect(AppState(library: library, defaults: defaults, credentials: credentials).projects.map(\.repository) == [nil])
    }

    @Test func linkingAProjectArchivedSinceKeepsItArchived() throws {
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        app.file(try library.create(), inNewProjectNamed: "Martin")
        let martin = try #require(app.projects.first)
        app.archive(martin)
        app.link(martin, to: .folder(URL(filePath: "/Users/ada/Developer/martin", directoryHint: .isDirectory)))
        #expect(app.projects.isEmpty)
        #expect(app.archivedProjects.map(\.repository?.folder?.lastPathComponent) == ["martin"])
    }

    @Test func theSavedAPIKeyIsRememberedAcrossLaunches() {
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(nil))
        #expect(app.credential == nil)
        app.use(openAI)
        #expect(AppState(library: library, defaults: defaults, credentials: credentials).credential == openAI)
        app.credential = nil
        #expect(AppState(library: library, defaults: defaults, credentials: credentials).credential == nil)
    }

    @Test func noRepositoryIsSoughtWithoutAnAPIKeyOrForALinkedProject() async throws {
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(nil))
        app.file(try library.create(), inNewProjectNamed: "Martin")
        await app.suggestRepositories()
        #expect(app.suggestions.isEmpty)
        app.link(try #require(app.projects.first), to: .folder(URL(filePath: "/Users/ada/Developer/martin", directoryHint: .isDirectory)))
        app.credential = claude
        await app.suggestRepositories()
        #expect(app.suggestions.isEmpty)
    }

    private func clone(_ name: String) throws -> Repository {
        let folder = library.root.appending(path: "clones/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: ".git"), withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = git@github.com:ethanyxchen/\(name).git\n".write(to: folder.appending(path: ".git/config"), atomically: true, encoding: .utf8)
        return try #require(Repository(at: folder))
    }

    private func finding(_ repository: Repository?, asked: Asked = Asked(), failing: Bool = false) -> RepositoryFinder {
        RepositoryFinder(nearby: { _ in repository.map { [$0] } ?? [] }, match: { _, _, _, _ in
            await asked.count()
            return failing ? nil : Set(repository.map { [$0.slug.lowercased()] } ?? [])
        })
    }

    @Test func aRepositoryFoundInTheBackgroundIsLinkedTheMomentItIsTurnedOn() async throws {
        let martin = try clone("martin")
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(martin))
        app.file(try library.create(), inNewProjectNamed: "Martin")
        app.credential = claude
        await app.suggestRepositories()
        #expect(app.projects.map(\.repository) == [nil])
        app.addRepository(to: try #require(app.projects.first))
        #expect(app.projects.map(\.repository) == [.folder(martin.folder)])
    }

    @Test func aRepositoryTurnedOnBeforeItIsFoundIsLinkedOnceItIs() async throws {
        let martin = try clone("martin")
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(martin))
        app.file(try library.create(), inNewProjectNamed: "Martin")
        app.credential = claude
        app.addRepository(to: try #require(app.projects.first))
        #expect(app.projects.map(\.repository) == [.unset])
        await app.suggestRepository(for: try #require(app.projects.first))
        #expect(app.projects.map(\.repository) == [.folder(martin.folder)])
    }

    @Test func withNothingFoundTurningItOnLeavesTheRepositoryToChoose() async throws {
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(nil))
        app.file(try library.create(), inNewProjectNamed: "Interviews")
        app.credential = claude
        await app.suggestRepositories()
        app.addRepository(to: try #require(app.projects.first))
        #expect(app.projects.map(\.repository) == [.unset])
    }

    @Test func aSecretProjectAndItsNotesStayOutOfSightUntilSecretsAreShown() throws {
        let app = AppState(library: library, defaults: defaults, credentials: credentials)
        let loose = try library.create(startedAt: .distantPast)
        let filed = try library.create()
        app.file(filed, inNewProjectNamed: "Atlas")
        app.pin(try #require(app.meeting(filed.id)), true)
        let atlas = try #require(app.projects.first)
        app.keepSecret(atlas, true)
        #expect(app.shelves.map(\.id) == [.unassigned])
        #expect(app.pinned.isEmpty)
        #expect(app.unpinned.map(\.id) == [loose.id])
        #expect(AppState(library: library, defaults: defaults, credentials: credentials).shelves.map(\.id) == [.unassigned])
        app.showsSecrets = true
        #expect(app.shelves.map(\.id) == [.project(atlas.id), .unassigned])
        #expect(app.pinned.map(\.id) == [filed.id])
        app.showsSecrets = false
        app.keepSecret(try #require(app.projects.first), false)
        #expect(app.shelves.map(\.id) == [.project(atlas.id), .unassigned])
        #expect(app.pinned.map(\.id) == [filed.id])
    }

    @Test func aSavedLookupIsKeptAcrossRelaunchesEvenAfterTheNotesChange() async throws {
        let martin = try clone("martin")
        let asked = Asked()
        let meeting = try library.create(title: "Kickoff")
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(martin, asked: asked))
        app.file(meeting, inNewProjectNamed: "Notepad")
        app.credential = claude
        await app.suggestRepositories()
        app.save("- ship the menu bar", for: try #require(app.meeting(meeting.id)))
        let relaunched = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(nil, asked: asked))
        await relaunched.suggestRepositories()
        #expect(await asked.times == 1)
        #expect(relaunched.suggestions.values.map(\.self) == [.found(martin)])
    }

    @Test func findingNothingIsSavedTooAndNotAskedAgain() async throws {
        let asked = Asked()
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(nil, asked: asked))
        app.file(try library.create(), inNewProjectNamed: "Interviews")
        app.credential = claude
        await app.suggestRepositories()
        let relaunched = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(try clone("martin"), asked: asked))
        await relaunched.suggestRepositories()
        #expect(await asked.times == 1)
        #expect(relaunched.suggestions.values.map(\.self) == [.found(nil)])
    }

    @Test func aRepositoryLinkedByHandReplacesTheSavedLookup() async throws {
        let martin = try clone("martin"), notepad = try clone("notepad")
        let asked = Asked()
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(martin, asked: asked))
        app.file(try library.create(), inNewProjectNamed: "Notepad")
        app.credential = claude
        await app.suggestRepositories()
        app.link(try #require(app.projects.first), to: .folder(notepad.folder))
        app.link(try #require(app.projects.first), to: nil)
        let relaunched = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(martin, asked: asked))
        await relaunched.suggestRepositories()
        relaunched.addRepository(to: try #require(relaunched.projects.first))
        #expect(relaunched.projects.map(\.repository) == [.folder(notepad.folder)])
        #expect(await asked.times == 1)
    }

    @Test func aFailedLookupIsNotSavedSoTheNextLaunchAsksAgain() async throws {
        let martin = try clone("martin")
        let asked = Asked()
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(martin, asked: asked, failing: true))
        app.file(try library.create(), inNewProjectNamed: "Notepad")
        app.credential = claude
        await app.suggestRepositories()
        await AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(martin, asked: asked)).suggestRepositories()
        #expect(await asked.times == 2)
        #expect(library.lookups().values.map(\.folder) == [martin.folder])
    }

    @Test func aMeetingWithoutANoteYetStillTellsTheLookupItsTitle() async throws {
        let finder = RepositoryFinder(nearby: { _ in [] }, match: { _, notes, _, _ in notes.isEmpty ? nil : [] })
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finder)
        app.file(try library.create(title: "Lumen sync"), inNewProjectNamed: "Lumen")
        app.credential = claude
        await app.suggestRepositories()
        #expect(library.lookups().count == 1)
    }

    @Test func aSecretProjectIsNotLookedUpInTheBackground() async throws {
        let asked = Asked()
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finding(try clone("martin"), asked: asked))
        app.file(try library.create(), inNewProjectNamed: "Martin")
        app.keepSecret(try #require(app.projects.first), true)
        app.credential = claude
        await app.suggestRepositories()
        #expect(await asked.times == 0)
    }

    @Test(arguments: [true, false])
    func aLookupAbandonedWhileTheProviderWorksIsNotSaved(deleting: Bool) async throws {
        let martin = try clone("martin")
        let current = Current()
        let finder = RepositoryFinder(nearby: { _ in [martin] }, match: { project, _, _, _ in
            await MainActor.run {
                guard let app = current.app else { return }
                if deleting { app.delete(project) } else { app.credential = openAI }
            }
            return [martin.slug.lowercased()]
        })
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finder)
        current.app = app
        app.file(try library.create(), inNewProjectNamed: "Notepad")
        app.credential = claude
        await app.suggestRepository(for: try #require(app.projects.first ?? app.allProjects.first))
        #expect(library.lookups().isEmpty)
        #expect(app.suggestions.isEmpty)
    }

    @Test func changingTheKeyStopsTheLookupsStartedWithTheOldOne() async throws {
        let martin = try clone("martin")
        let current = Current()
        let log = Log()
        let finder = RepositoryFinder(nearby: { _ in [martin] }, match: { _, _, _, credential in
            if credential == claude { await MainActor.run { current.app?.credential = openAI } }
            await log.add("\(credential.provider.rawValue) \(Task.isCancelled ? "cancelled" : "running")")
            return []
        })
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finder)
        current.app = app
        app.file(try library.create(), inNewProjectNamed: "Notepad")
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        app.credential = claude
        await app.suggestRepositories()
        #expect(await log.entries == ["anthropic cancelled"])
        #expect(app.suggestions.isEmpty)
    }

    @Test func aLookupCancelledWithItsViewIsAskedAgainNextTime() async throws {
        let martin = try clone("martin")
        let asked = Asked()
        let finder = RepositoryFinder(nearby: { _ in [martin] }, match: { _, _, _, _ in
            await asked.count()
            withUnsafeCurrentTask { $0?.cancel() }
            return nil
        })
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: finder)
        app.file(try library.create(), inNewProjectNamed: "Notepad")
        app.credential = claude
        let project = try #require(app.projects.first)
        await app.suggestRepository(for: project)
        #expect(app.suggestions.isEmpty)
        await app.suggestRepository(for: project)
        #expect(await asked.times == 2)
    }
}

actor Log {
    private(set) var entries: [String] = []

    func add(_ entry: String) {
        entries.append(entry)
    }
}

private let claude = Credential(provider: .anthropic, key: "sk-ant")
private let openAI = Credential(provider: .openai, key: "sk-proj")

@MainActor
final class Current: @unchecked Sendable {
    var app: AppState?
}

actor Asked {
    private(set) var times = 0

    func count() {
        times += 1
    }
}
