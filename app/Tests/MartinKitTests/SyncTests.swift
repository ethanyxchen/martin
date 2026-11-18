import Foundation
import MartinKit
import MartinKitFakes
import Testing

final class SyncTests {
    let server = FakeServer()
    let mac = LibrarySandbox()
    let other = LibrarySandbox()

    @discardableResult
    func sync(_ sandbox: LibrarySandbox, as user: String = "ada") async throws -> Set<SyncRecord.Key> {
        try await Sync(library: sandbox.library, server: server.syncServer(for: user), user: user).run()
    }

    @Test func notesAndProjectsReachAnotherMac() async throws {
        let project = try mac.library.createProject(named: "Martin")
        let meeting = try mac.library.create(title: "Standup", project: project.id)
        try mac.library.saveNote("- shipped sync", for: meeting)
        try await sync(mac)
        let applied = try await sync(other)
        #expect(Set(applied.map(\.id)) == [meeting.id, project.id])
        #expect(try other.library.meetings() == [meeting])
        #expect(try other.library.projects() == [project])
        #expect(other.library.note(of: meeting) == "- shipped sync")
    }

    @Test func aMacWithItsOwnNotesSigningInForTheFirstTimeKeepsThemAndGetsTheOthers() async throws {
        let mine = try mac.library.create(startedAt: .now - 60, title: "Standup")
        let project = try mac.library.createProject(named: "Martin")
        try await sync(mac)
        let theirs = try other.library.create(title: "Retro")
        let sameName = try other.library.createProject(named: "Martin")
        try await sync(other)
        try await sync(mac)
        #expect(Set(try mac.library.meetings().map(\.id)) == [mine.id, theirs.id])
        #expect(Set(try other.library.meetings().map(\.id)) == [mine.id, theirs.id])
        #expect(Set(try other.library.projects().map(\.id)) == [project.id, sameName.id])
    }

    @Test func anEditOnOneMacReplacesTheOtherMacsCopy() async throws {
        let meeting = try mac.library.create(title: "Standup")
        try await sync(mac)
        try await sync(other)
        try other.library.saveNote("edited elsewhere", for: meeting)
        try await sync(other)
        #expect(try await sync(mac).map(\.id) == [meeting.id])
        #expect(mac.library.note(of: meeting) == "edited elsewhere")
    }

    @Test func whenBothMacsEditTheSameNoteTheLaterEditWins() async throws {
        let meeting = try mac.library.create(title: "Standup")
        try await sync(mac)
        try await sync(other)
        try mac.library.saveNote("earlier", for: meeting)
        try touch(mac.library.noteFile(of: meeting), at: .now + 10)
        try other.library.saveNote("later", for: meeting)
        try touch(other.library.noteFile(of: meeting), at: .now + 20)
        try await sync(other)
        try await sync(mac)
        try await sync(other)
        #expect(mac.library.note(of: meeting) == "later")
        #expect(other.library.note(of: meeting) == "later")
    }

    @Test func anOlderEditPushedLateDoesNotOverwriteANewerOne() async throws {
        let meeting = try mac.library.create(title: "Standup")
        try await sync(mac)
        try await sync(other)
        try other.library.saveNote("later", for: meeting)
        try touch(other.library.noteFile(of: meeting), at: .now + 20)
        try mac.library.saveNote("earlier", for: meeting)
        try touch(mac.library.noteFile(of: meeting), at: .now + 10)
        try await sync(mac)
        try await sync(other)
        try await sync(mac)
        #expect(mac.library.note(of: meeting) == "later")
        #expect(other.library.note(of: meeting) == "later")
    }

    @Test func deletingANoteDeletesItOnTheOtherMacWithItsImages() async throws {
        let meeting = try mac.library.create(title: "Standup")
        let path = try NoteImages(meetingFolder: mac.library.folder(of: meeting)).add(Data("png".utf8), fileExtension: "png")
        try mac.library.saveNote("![](\(path))", for: meeting)
        try await sync(mac)
        try await sync(other)
        try other.library.delete(meeting)
        try await sync(other)
        try await sync(mac)
        #expect(try mac.library.meetings().isEmpty)
        #expect(server.images.isEmpty)
    }

    @Test func imagesInANoteFollowItToTheOtherMac() async throws {
        let meeting = try mac.library.create(title: "Whiteboard")
        let path = try NoteImages(meetingFolder: mac.library.folder(of: meeting)).add(Data("png".utf8), fileExtension: "png")
        try mac.library.saveNote("![board](\(path))", for: meeting)
        try await sync(mac)
        try await sync(other)
        let image = try #require(NoteImages(meetingFolder: other.library.folder(of: meeting)).url(for: path))
        #expect(try Data(contentsOf: image) == Data("png".utf8))
    }

    @Test func aLinkedRepositoryStaysOnTheMacThatLinkedIt() async throws {
        var project = try mac.library.createProject(named: "Martin")
        project.repository = .folder(URL(filePath: "/Users/ada/Developer/martin"))
        try mac.library.save(project)
        try await sync(mac)
        try await sync(other)
        #expect(try other.library.projects().map(\.repository) == [nil])
        var renamed = try #require(other.library.projects().first)
        renamed.name = "Martin App"
        try other.library.save(renamed)
        try await sync(other)
        try await sync(mac)
        #expect(try mac.library.projects() == [{ var expected = renamed; expected.repository = project.repository; return expected }()])
    }

    @Test func anUnchangedLibraryPushesNothing() async throws {
        _ = try mac.library.create(title: "Standup")
        try await sync(mac)
        let pushes = server.pushes
        try await sync(mac)
        #expect(server.pushes == pushes)
    }

    @Test func signingInAsSomeoneElsePushesTheWholeLibraryAgain() async throws {
        let meeting = try mac.library.create(title: "Standup")
        try await sync(mac)
        try await sync(mac, as: "grace")
        #expect(server.pushed.filter { $0.key.id == meeting.id }.count == 2)
    }

    @Test func aNoteEditedElsewhereAfterItWasDeletedHereComesBack() async throws {
        let meeting = try mac.library.create(title: "Standup")
        try await sync(mac)
        try await sync(other)
        try mac.library.delete(meeting)
        try await offline(mac)
        try await Task.sleep(for: .milliseconds(20))
        try other.library.saveNote("still needed", for: meeting)
        try await sync(other)
        try await Task.sleep(for: .milliseconds(20))
        try await sync(mac)
        #expect(mac.library.note(of: meeting) == "still needed")
        #expect(other.library.note(of: meeting) == "still needed")
    }

    @Test func aProjectRenamedOfflineLosesToALaterRenameEvenAfterAnotherProjectChanges() async throws {
        var first = try mac.library.createProject(named: "Atlas")
        var second = try mac.library.createProject(named: "Hiring")
        try await sync(mac)
        try await sync(other)
        first.name = "Atlas (mine)"
        try mac.library.save(first)
        try await offline(mac)
        try await Task.sleep(for: .milliseconds(20))
        var renamed = try #require(other.library.projects().first { $0.id == first.id })
        renamed.name = "Atlas (later)"
        try other.library.save(renamed)
        try await sync(other)
        second.name = "Hiring (mine)"
        try mac.library.save(second)
        try await sync(mac)
        #expect(try mac.library.projects().map(\.name) == ["Atlas (later)", "Hiring (mine)"])
    }

    @Test func anImageThatFailedToDownloadIsFetchedOnTheNextSync() async throws {
        let meeting = try mac.library.create(title: "Whiteboard")
        let path = try NoteImages(meetingFolder: mac.library.folder(of: meeting)).add(Data("png".utf8), fileExtension: "png")
        try mac.library.saveNote("![board](\(path))", for: meeting)
        try await sync(mac)
        var flaky = server.syncServer(for: "ada")
        flaky.download = { _ in throw URLError(.networkConnectionLost) }
        try await Sync(library: other.library, server: flaky, user: "ada").run()
        let image = try #require(NoteImages(meetingFolder: other.library.folder(of: meeting)).url(for: path))
        #expect(!FileManager.default.fileExists(atPath: image.path))
        try await sync(other)
        #expect(try Data(contentsOf: image) == Data("png".utf8))
    }

    private func offline(_ sandbox: LibrarySandbox) async throws {
        var offline = server.syncServer(for: "ada")
        offline.pull = { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) { try await Sync(library: sandbox.library, server: offline, user: "ada").run() }
    }

    private func touch(_ file: URL, at date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }
}
