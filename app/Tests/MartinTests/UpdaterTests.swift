import Foundation
import Testing
@testable import Martin

@MainActor
struct UpdaterTests {
    @Test func theAppChecksTheLatestReleaseFeedSignedWithAnEdDSAKey() throws {
        let plist = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Resources/Info.plist")
        let info = try #require(NSDictionary(contentsOf: plist))
        #expect(info["SUFeedURL"] as? String == "https://github.com/ethanyxchen/martin/releases/latest/download/appcast.xml")
        let key = (info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
        #expect(key?.count == 32)
    }

    @Test func aBuildWithoutAFeedOffersNoUpdates() throws {
        let bundle = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: bundle) }
        try FileManager.default.createDirectory(at: bundle.appending(path: "Contents"), withIntermediateDirectories: true)
        try NSDictionary(dictionary: ["CFBundleIdentifier": "dev.ethanchen.martin.test"]).write(to: bundle.appending(path: "Contents/Info.plist"))
        #expect(!Updater(bundle: try #require(Bundle(url: bundle))).offersUpdates)
    }
}
