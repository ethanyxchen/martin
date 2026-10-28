import Foundation
import MartinKit
import Testing
@testable import Martin

@MainActor
final class AppStateTests {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
    let suite = UUID().uuidString
    lazy var defaults = UserDefaults(suiteName: suite)!

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: library.root)
    }

    @Test func pageAndHiddenPagesAreRememberedAcrossLaunches() {
        let app = AppState(library: library, defaults: defaults)
        app.page = .meetings
        app.hiddenPages = [.upcoming]
        let relaunched = AppState(library: library, defaults: defaults)
        #expect(relaunched.page == .meetings)
        #expect(relaunched.hiddenPages == [.upcoming])
    }

    @Test func savingANoteUpdatesItsPreview() throws {
        let meeting = try library.create(title: "Standup")
        try library.saveNote("# Before", for: meeting)
        let app = AppState(library: library, defaults: defaults)
        #expect(app.previews[meeting.id] == "Before")
        app.save("- shipped **icons**", for: meeting)
        #expect(app.previews[meeting.id] == "shipped icons")
        #expect(library.note(of: meeting) == "- shipped **icons**")
    }
}
