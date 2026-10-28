import Sparkle
import SwiftUI

@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        controller = bundle.object(forInfoDictionaryKey: "SUFeedURL") == nil
            ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var offersUpdates: Bool { controller != nil }

    func check() {
        controller?.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    let updater: Updater

    var body: some View {
        if updater.offersUpdates {
            Button("Check for Updates…") { updater.check() }
        }
    }
}
