import Foundation
@testable import PostHog
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

    @Test func reportsSkipTheServerLookupOfTheUsersLocation() throws {
        let config = try #require(try Self.config(of: ["PostHogProjectToken": "phc_test", "PostHogHost": "https://eu.i.posthog.com"]))
        #expect(config.disableGeoIp)
    }

    @Test func theHomeDirectoryIsReplacedWithATildeEverywhereInAReport() {
        let properties: [String: Any] = [
            "$exception_list": [[
                "value": "Couldn't open /Users/ada/Notes/plan.md",
                "stacktrace": ["frames": [["package": "/Users/ada/Applications/Martin.app/Contents/MacOS/Martin", "instruction_addr": "0x10"]]],
            ]],
            "$debug_images": [["code_file": "/Users/ada/Applications/Martin.app/Contents/MacOS/Martin"]],
            "source": "/Users/ada",
            "neighbour": "/Users/adam/Notes",
        ]
        let scrubbed = HomePath("/Users/ada").scrubbing(properties)
        let exception = (scrubbed["$exception_list"] as? [[String: Any]])?.first
        let frame = ((exception?["stacktrace"] as? [String: Any])?["frames"] as? [[String: Any]])?.first
        let image = (scrubbed["$debug_images"] as? [[String: Any]])?.first
        #expect(exception?["value"] as? String == "Couldn't open ~/Notes/plan.md")
        #expect(frame?["package"] as? String == "~/Applications/Martin.app/Contents/MacOS/Martin")
        #expect(frame?["instruction_addr"] as? String == "0x10")
        #expect(image?["code_file"] as? String == "~/Applications/Martin.app/Contents/MacOS/Martin")
        #expect(scrubbed["source"] as? String == "~")
        #expect(scrubbed["neighbour"] as? String == "/Users/adam/Notes")
    }

    @Test func theHomeDirectoryIsReplacedWhereverItEndsAName() {
        let home = HomePath("/Users/ada")
        #expect(home.scrubbing("Couldn't write to /Users/ada.") == "Couldn't write to ~.")
        #expect(home.scrubbing("Scanning /Users/ada...") == "Scanning ~...")
        #expect(home.scrubbing("/Users/ada-old and /Users/ada.old") == "~-old and ~.old")
        #expect(home.scrubbing("/users/ADA/Notes") == "~/Notes")
    }

    @Test func aHomeDirectoryInAFileURLIsReplacedToo() {
        #expect(HomePath("/Users/José Ruiz").scrubbing("file:///Users/Jos%C3%A9%20Ruiz/Notes") == "file://~/Notes")
    }

    @Test func eventsAndLogsLeaveTheAppWithoutTheHomeDirectory() throws {
        let config = try #require(try Self.config(of: ["PostHogProjectToken": "phc_test", "PostHogHost": "https://eu.i.posthog.com"]))
        let path = NSHomeDirectory() + "/Notes/plan.md"
        let event = try #require(config.runBeforeSend(PostHogEvent(event: "$exception", distinctId: "install", properties: ["value": path])))
        #expect(event.properties["value"] as? String == "~/Notes/plan.md")
        let record = try #require(config.logs.runBeforeSend(PostHogLogRecord(body: "Couldn't open \(path)", attributes: ["file": path])))
        #expect(record.body == "Couldn't open ~/Notes/plan.md")
        #expect(record.attributes["file"] as? String == "~/Notes/plan.md")
    }

    private static func config(of info: [String: String]) throws -> PostHogConfig? {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url.appending(path: "Contents"), withIntermediateDirectories: true)
        try NSDictionary(dictionary: info.merging(["CFBundleIdentifier": "dev.ethanchen.martin.test"]) { $1 }).write(to: url.appending(path: "Contents/Info.plist"))
        return Telemetry.config(in: try #require(Bundle(url: url)))
    }
}
