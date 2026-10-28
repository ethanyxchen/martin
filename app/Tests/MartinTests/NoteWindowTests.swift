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
}

private extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}
