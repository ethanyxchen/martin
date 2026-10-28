import AppKit
import SwiftUI
import Testing
@testable import Martin

@MainActor
struct PageTests {
    @Test func aTitledPageGivesItsWindowAToolbarLikeHome() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Page(title: "Standup") { Text("Standup") } content: { Text("Notes") })
        try await Task.sleep(for: .milliseconds(200))
        let toolbar = try #require(window.toolbar)
        #expect(toolbar.items.count == 1)
    }
}
