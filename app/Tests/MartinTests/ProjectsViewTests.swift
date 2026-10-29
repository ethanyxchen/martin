import AppKit
import MartinKit
import SwiftUI
import Testing
@testable import Martin

@MainActor
final class ProjectsViewTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
    let suite = UUID().uuidString
    lazy var defaults = UserDefaults(suiteName: suite)!

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: library.root)
    }

    @Test func closingAProjectLetsTheWindowNarrowAgain() async throws {
        let meeting = try library.create(title: "Kickoff")
        let app = AppState(library: library, defaults: defaults)
        app.file(meeting, inNewProjectNamed: "Atlas")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ProjectsView(app: app))
        func settle() async throws {
            for _ in 0..<10 {
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        try await settle()
        app.selectedShelf = app.notes.shelved(in: app.projects).first?.id
        try await settle()
        app.selectedShelf = nil
        try await settle()
        window.setContentSize(NSSize(width: 340, height: 600))
        try await settle()
        #expect(window.contentLayoutRect.width == 340)
    }
}
