import AppKit
import Foundation
import MartinKit
import SwiftUI
import Testing
@testable import Martin

@MainActor
final class NotePageTests: Sandbox {
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

    @Test func theNoteMenuActsOnTheNoteOnScreen() throws {
        let meeting = try library.create(title: "Standup")
        let app = AppState(library: library, defaults: defaults)
        #expect(app.focusedNote == nil)
        app.open(meeting)
        #expect(app.focusedNote == meeting)
        app.openArchive()
        #expect(app.focusedNote == nil)
        app.back()
        app.back()
        #expect(app.focusedNote == nil)
    }

    @Test func theProjectMenuActsOnTheProjectOpenOnHome() throws {
        let app = AppState(library: library, defaults: defaults)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        app.page = .projects
        app.selectedShelf = .project(atlas.id)
        #expect(app.focusedProject == atlas)
        app.selectedShelf = .unassigned
        #expect(app.focusedProject == nil)
        app.selectedShelf = .project(atlas.id)
        app.page = .notes
        #expect(app.focusedProject == nil)
        app.page = .projects
        app.selectedShelf = .project(atlas.id)
        app.open(try #require(app.meetings.first))
        #expect(app.focusedProject == nil)
        app.back()
        #expect(app.focusedProject == atlas)
    }

    @Test func aQuickNoteLandsInTheProjectOpenOnHome() throws {
        let app = AppState(library: library, defaults: defaults)
        app.file(try library.create(), inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        app.page = .projects
        app.selectedShelf = .project(atlas.id)
        #expect(try app.newQuickNote().project == atlas.id)
    }

    @Test func makingAProjectSecretLeavesItsNotesUnlessSecretsAreShown() throws {
        let app = AppState(library: library, defaults: defaults)
        let meeting = try library.create()
        app.file(meeting, inNewProjectNamed: "Atlas")
        let atlas = try #require(app.projects.first)
        app.open(meeting)
        app.showsSecrets = true
        app.keepSecret(atlas, true)
        #expect(app.focusedNote?.id == meeting.id)
        app.keepSecret(atlas, false)
        app.showsSecrets = false
        app.keepSecret(atlas, true)
        #expect(app.focusedNote == nil)
    }
}
