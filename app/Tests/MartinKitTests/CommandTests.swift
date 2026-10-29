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

    @Test func theHelpersAToolStartedAreStoppedWithItAtTheTimeout() async throws {
        let mark = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(await Command.run("sh", ["-c", "sh -c 'sleep 2; touch \(mark.path(percentEncoded: false))' & wait"], timeout: 0.5) == nil)
        try await Task.sleep(for: .seconds(3))
        #expect(!FileManager.default.fileExists(atPath: mark.path(percentEncoded: false)))
    }

    @Test func aToolThatSucceededIsJudgedByItsExitEvenWhenAHelperOutlivesTheDeadline() async {
        let start = ContinuousClock.now
        #expect(await Command.run("sh", ["-c", "sleep 30 & echo ok"], timeout: 0.5) == "ok\n")
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aToolThatCannotBeFoundFails() async {
        #expect(await Command.run("martin-no-such-tool", [], timeout: 5) == nil)
    }

    @Test(arguments: [
        "perl -MPOSIX -e 'POSIX::setsid(); sleep 2; open(my $f, \">\", $ARGV[0])' MARK & echo ok",
        "perl -MPOSIX -e 'POSIX::setsid(); close STDOUT; sleep 2; open(my $f, \">\", $ARGV[0])' MARK & echo ok",
        "(exec >/dev/null; sleep 2; touch MARK) & echo ok",
        "perl -MPOSIX -e 'close STDOUT; POSIX::close(3); POSIX::setsid(); sleep 2; open(my $f, \">\", $ARGV[0])' MARK & sleep 0.5; echo ok",
    ])
    func noHelperOutlivesASuccessfulRunEvenOneThatLeftTheProcessGroup(script: String) async throws {
        let mark = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
        let start = ContinuousClock.now
        #expect(await Command.run("sh", ["-c", script.replacingOccurrences(of: "MARK", with: mark)], timeout: 30) == "ok\n")
        #expect(ContinuousClock.now - start < .seconds(2))
        try await Task.sleep(for: .seconds(3))
        #expect(!FileManager.default.fileExists(atPath: mark))
    }

    @Test func aHelperThatWritesAfterTheToolExitsIsWaitedFor() async {
        #expect(await Command.run("sh", ["-c", "(sleep 1.5; echo late) & echo early"], timeout: 10) == "early\nlate\n")
    }
}
