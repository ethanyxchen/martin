import AppKit
import Foundation
import MartinKit
import MartinKitFakes
import SwiftUI
import Testing
@testable import Martin

@MainActor
final class AccountTests: Sandbox {
    let server = FakeServer()
    let elsewhere = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))

    deinit {
        try? FileManager.default.removeItem(at: elsewhere.root)
    }

    func cloud(signedIn: Bool = true) -> Cloud {
        let ada = CloudUser(id: "ada", email: "ada@example.com")
        return Cloud(user: { signedIn ? ada : nil }, signIn: { ada }, signOut: {}, server: server.syncServer(for: ada.id))
    }

    func app(signedIn: Bool = true) -> AppState {
        AppState(library: library, defaults: defaults, credentials: credentials, cloud: cloud(signedIn: signedIn))
    }

    func syncElsewhere() async throws {
        try await Sync(library: elsewhere, server: server.syncServer(for: "ada"), user: "ada").run()
    }

    @Test func signingInSyncsTheNotesAlreadyOnThisMac() async throws {
        let meeting = try library.create(title: "Standup")
        let app = app(signedIn: false)
        await app.signIn()
        await app.syncNow()
        #expect(app.user?.email == "ada@example.com")
        #expect(server.pushed.map(\.key.id) == [meeting.id])
        #expect({ if case .synced = app.syncStatus { true } else { false } }())
    }

    @Test func aNoteEditedOnAnotherMacReloadsInTheOpenEditor() async throws {
        let meeting = try library.create(title: "Standup")
        let app = app()
        await app.syncNow()
        try await syncElsewhere()
        try elsewhere.saveNote("edited elsewhere", for: meeting)
        try await syncElsewhere()
        app.open(meeting)
        await app.syncNow()
        #expect(app.revisions[meeting.id] == 1)
        #expect(app.previews[meeting.id] == "edited elsewhere")
        #expect(app.focusedNote?.id == meeting.id)
    }

    @Test func aNoteDeletedOnAnotherMacClosesItHere() async throws {
        let meeting = try library.create(title: "Standup")
        let app = app()
        await app.syncNow()
        try await syncElsewhere()
        try elsewhere.delete(meeting)
        try await syncElsewhere()
        app.open(meeting)
        await app.syncNow()
        #expect(app.meetings.isEmpty)
        #expect(app.focusedNote == nil)
    }

    @Test func signingOutKeepsTheNotesButStopsSyncingUntilTheNextSignIn() async throws {
        let meeting = try library.create(title: "Standup")
        let app = app()
        await app.syncNow()
        try await syncElsewhere()
        await app.signOut()
        try elsewhere.saveNote("edited elsewhere", for: meeting)
        try await syncElsewhere()
        await app.syncNow()
        #expect(app.user == nil)
        #expect(app.meetings.map(\.id) == [meeting.id])
        #expect(library.note(of: meeting) == nil)
        await app.signIn()
        await app.syncNow()
        #expect(library.note(of: meeting) == "edited elsewhere")
    }

    @Test func typingNotYetSavedSurvivesAnEditArrivingFromAnotherMac() async throws {
        let meeting = try library.create(title: "Standup")
        let app = app()
        await app.syncNow()
        try await syncElsewhere()
        try elsewhere.saveNote("edited elsewhere", for: meeting)
        try await syncElsewhere()
        let window = try await noteWindow(for: meeting, in: app)
        let editor = try editor(in: window)
        try await Task.sleep(for: .milliseconds(700))
        editor.insertText("typed here", replacementRange: NSRange(location: 0, length: 0))
        await app.syncNow()
        try await Task.sleep(for: .milliseconds(100))
        #expect(editor.string == "typed here")
    }

    @Test func aRenameFromAnotherMacReplacesTheTitleShownInTheOpenNote() async throws {
        let meeting = try library.create(title: "Standup")
        let app = app()
        await app.syncNow()
        try await syncElsewhere()
        var renamed = meeting
        renamed.title = "Retro"
        try elsewhere.save(renamed)
        try elsewhere.saveNote("edited elsewhere", for: renamed)
        try await syncElsewhere()
        let window = try await noteWindow(for: meeting, in: app)
        await app.syncNow()
        try await Task.sleep(for: .milliseconds(100))
        let titles = window.contentView!.descendants.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(titles.contains("Retro"))
        #expect(try editor(in: window).string == "edited elsewhere")
    }

    private func noteWindow(for meeting: Meeting, in app: AppState) async throws -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NoteView(app: app, meeting: meeting))
        for _ in 0..<100 where !window.contentView!.descendants.contains(where: { $0 is NoteTextView }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        return window
    }

    private func editor(in window: NSWindow) throws -> NoteTextView {
        try #require(window.contentView!.descendants.compactMap { $0 as? NoteTextView }.first)
    }
}
