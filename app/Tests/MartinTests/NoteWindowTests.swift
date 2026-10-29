import AppKit
import Foundation
import MartinKit
import SwiftUI
import Testing
@testable import Martin

@MainActor
final class NoteWindowTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
    let suite = UUID().uuidString
    lazy var defaults = UserDefaults(suiteName: suite)!

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: library.root)
    }

    @Test func theNoteMenuSitsAtTheTrailingEdgeOfTheToolbar() async throws {
        let meeting = try library.create(title: "Standup")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: NoteView(app: AppState(library: library, defaults: defaults), meeting: meeting))
        for _ in 0..<100 where window.toolbar == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        window.layoutIfNeeded()
        let items = try #require(window.contentView?.superview).descendants.filter { $0.className == "NSToolbarItemViewer" }
        let trailing = try #require(items.map { $0.convert($0.bounds, to: nil).maxX }.max())
        #expect(trailing > window.frame.width - 10)
    }

    @Test func theNoteMenuActsOnTheKeyNoteWindow() throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults)
        let window = app.present(NoteView(app: app, meeting: meeting), id: meeting.id, title: meeting.displayTitle, size: NSSize(width: 520, height: 640))
        #expect(app.focusedNote == nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(app.focusedNote == meeting)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(app.focusedNote == nil)
    }

    @Test func closingTheKeyNoteWindowLeavesNoNoteFocused() throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults)
        let window = app.present(NoteView(app: app, meeting: meeting), id: meeting.id, title: meeting.displayTitle, size: NSSize(width: 520, height: 640))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(app.focusedNote == nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(app.focusedNote == nil)
    }

    @Test func theProjectMenuActsOnTheProjectOpenInTheKeyHomeWindow() throws {
        let app = AppState(library: library, defaults: defaults)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        let window = app.present(HomeView(app: app), id: "home", title: "Martin", size: NSSize(width: 520, height: 640))
        app.page = .projects
        app.selectedShelf = .project(atlas.id)
        #expect(app.focusedProject == nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(app.focusedProject == atlas)
        app.selectedShelf = .unassigned
        #expect(app.focusedProject == nil)
        app.selectedShelf = .project(atlas.id)
        app.page = .notes
        #expect(app.focusedProject == nil)
        app.page = .projects
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(app.focusedProject == nil)
    }

    @Test func makingAProjectSecretClosesItsNoteWindowsUnlessSecretsAreShown() throws {
        let app = AppState(library: library, defaults: defaults)
        let meeting = try library.create()
        app.file(meeting, inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        let window = app.present(NoteView(app: app, meeting: meeting), id: meeting.id, title: meeting.displayTitle, size: NSSize(width: 520, height: 640))
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        app.showsSecrets = true
        app.keepSecret(atlas, true)
        #expect(app.focusedNote?.id == meeting.id)
        app.keepSecret(atlas, false)
        app.showsSecrets = false
        app.keepSecret(atlas, true)
        #expect(app.focusedNote == nil)
    }
}

private extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}
