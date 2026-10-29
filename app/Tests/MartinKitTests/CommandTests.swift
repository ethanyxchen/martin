import Foundation
import Testing
@testable import MartinKit

struct CommandTests {
    @Test func aToolThatExitsWithoutReadingItsInputFailsQuietly() async {
        #expect(await Command.run("sh", ["-c", "exit 0"], input: String(repeating: "notes ", count: 1_000_000)) == "")
    }

    @Test func aToolThatHangsIsStoppedAfterTheTimeout() async {
        let start = ContinuousClock.now
        #expect(await Command.run("sleep", ["30"], timeout: 0.5) == nil)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func aToolsOutputIsReturnedOnlyWhenItSucceeds() async {
        #expect(await Command.run("sh", ["-c", "cat; echo done"], input: "notes\n") == "notes\ndone\n")
        #expect(await Command.run("sh", ["-c", "echo nope; exit 1"]) == nil)
    }
}
