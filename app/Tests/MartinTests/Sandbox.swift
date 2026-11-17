import AppKit
import MartinKit
import os

@MainActor
class Sandbox {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let library: MeetingLibrary
    let defaults: UserDefaults
    let credentials = CredentialStore.memory()

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

extension CredentialStore {
    static func memory() -> CredentialStore {
        let saved = OSAllocatedUnfairLock<Credential?>(initialState: nil)
        return CredentialStore(load: { saved.withLock { $0 } }, save: { credential in saved.withLock { $0 = credential } })
    }
}
