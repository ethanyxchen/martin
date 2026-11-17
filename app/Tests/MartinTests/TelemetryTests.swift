import Foundation
import PostHog
@testable import MartinKit
import Testing
@testable import Martin

struct TelemetryTests {
    @Test func theAppReportsToTheEUHostWithATokenAddedOnlyWhenBuilt() throws {
        let plist = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Resources/Info.plist")
        let info = try #require(NSDictionary(contentsOf: plist))
        #expect(info["PostHogHost"] as? String == "https://eu.i.posthog.com")
        #expect(info["PostHogProjectToken"] == nil)
    }

    @Test func aBundleNamingAProjectIsConfiguredToReportToIt() throws {
        let config = try Self.config(of: ["PostHogProjectToken": "phc_test", "PostHogHost": "https://eu.i.posthog.com"])
        #expect(config?.projectToken == "phc_test")
        #expect(config?.host.absoluteString == "https://eu.i.posthog.com")
    }

    @Test func aBuildWithoutAProjectReportsNothing() throws {
        #expect(try Self.config(of: [:]) == nil)
    }

    @Test func aRepositoryMatchIsReportedWithoutWhatWasAskedOrAnswered() {
        let generation = Assistant.Generation(provider: "anthropic", model: "haiku", latency: 1.5, isError: false)
        let properties = Telemetry.generation(generation, trace: "trace", session: "session")
        #expect(Set(properties.keys) == ["$ai_trace_id", "$ai_session_id", "$ai_span_name", "$ai_model", "$ai_provider", "$ai_latency", "$ai_is_error"])
    }

    private static func config(of info: [String: String]) throws -> PostHogConfig? {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url.appending(path: "Contents"), withIntermediateDirectories: true)
        try NSDictionary(dictionary: info.merging(["CFBundleIdentifier": "dev.ethanchen.martin.test"]) { $1 }).write(to: url.appending(path: "Contents/Info.plist"))
        return Telemetry.config(in: try #require(Bundle(url: url)))
    }
}
