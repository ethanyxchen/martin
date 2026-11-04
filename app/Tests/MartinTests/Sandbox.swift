import AppKit
import MartinKit

@MainActor
class Sandbox {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let library: MeetingLibrary
    let defaults: UserDefaults

    init() {
        library = MeetingLibrary(root: root.appending(path: "library", directoryHint: .isDirectory))
        defaults = UserDefaults(suiteName: root.appending(path: "defaults").path(percentEncoded: false))!
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

extension NSView {
    var descendants: [NSView] { subviews + subviews.flatMap(\.descendants) }
}
