import Foundation
import Testing
@testable import MartinKit

struct CommandTests {
    @Test func aToolThatExitsWithoutReadingItsInputFailsQuietly() async {
        #expect(await Command.run("sh", ["-c", "exit 0"], input: String(repeating: "notes ", count: 1_000_000), timeout: 10) == "")
    }

    @Test(arguments: ["sleep 30", "trap '' TERM; sleep 30", "sleep 30 & wait"])
    func aToolThatHangsIsGivenUpOnAtTheTimeout(script: String) async {
        let start = ContinuousClock.now
        #expect(await Command.run("sh", ["-c", script], timeout: 0.5) == nil)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aToolsOutputIsReturnedOnlyWhenItSucceeds() async {
        #expect(await Command.run("sh", ["-c", "cat; echo done"], input: "notes\n", timeout: 10) == "notes\ndone\n")
        #expect(await Command.run("sh", ["-c", "echo nope; exit 1"], timeout: 10) == nil)
    }
}
