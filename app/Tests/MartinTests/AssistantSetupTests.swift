import MartinKit
import Testing
@testable import Martin

@MainActor
final class AssistantSetupTests: Sandbox {
    @Test func choosingAnAssistantLeavesTheSetupForTheScreenBeneath() {
        let app = AppState(library: library, defaults: defaults, finder: RepositoryFinder(nearby: { _ in [] }, match: { _, _, _, _ in nil }))
        app.openHome(on: .settings)
        app.openAssistantSetup()
        #expect(app.path == [.assistant])
        app.use(.claude)
        #expect(app.path.isEmpty)
        #expect(app.page == .settings)
    }
}
