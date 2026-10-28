import AppKit
import SwiftUI
import Testing
@testable import Martin

@MainActor
struct PageTests {
    typealias TitledPage = Page<Text, Text>

    @Test func aTitledPageGivesItsWindowAToolbarLikeHome() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: TitledPage(title: "Standup") { Text("Standup") } content: { Text("Notes") })
        for _ in 0..<100 where window.toolbar == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let toolbar = try #require(window.toolbar)
        #expect(toolbar.items.count == 1)
    }
}
