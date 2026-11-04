import Foundation
import MartinKit

class LibrarySandbox {
    let library = MeetingLibrary(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))

    deinit {
        try? FileManager.default.removeItem(at: library.root)
    }
}
