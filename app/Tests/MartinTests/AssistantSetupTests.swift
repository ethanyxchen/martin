import AppKit
import MartinKit
import Testing
@testable import Martin

@MainActor
struct AssistantSetupTests {
    @Test func theSetupWindowKeepsItsSizeInsteadOfGrowingToFitItsContent() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let app = AppState(library: MeetingLibrary(root: root), defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let window = app.present(AssistantSetup(app: app), id: "assistant", title: "Set Up an Assistant", size: AssistantSetup.size)
        try await Task.sleep(for: .seconds(1))
        #expect(window.contentLayoutRect.size == AssistantSetup.size)
        window.close()
    }
}
