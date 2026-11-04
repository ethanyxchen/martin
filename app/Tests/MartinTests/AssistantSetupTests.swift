import AppKit
import MartinKit
import Testing
@testable import Martin

@MainActor
final class AssistantSetupTests: Sandbox {
    @Test func theSetupWindowKeepsItsSizeInsteadOfGrowingToFitItsContent() async throws {
        let app = AppState(library: library, defaults: defaults)
        let window = app.present(AssistantSetup(app: app), id: "assistant", title: "Set Up an Assistant", size: AssistantSetup.size)
        try await Task.sleep(for: .seconds(1))
        #expect(window.contentLayoutRect.size == AssistantSetup.size)
        window.close()
    }
}
