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

    private func touch(_ file: URL, at date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }
}
