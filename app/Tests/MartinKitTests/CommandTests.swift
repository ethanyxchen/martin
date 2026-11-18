import Foundation
import Testing
@testable import MartinKit

struct CommandTests {
    @Test func aToolThatExitsWithoutReadingItsInputFailsQuietly() async {
        #expect(await Command.run("sh", ["-c", "exit 0"], input: String(repeating: "notes ", count: 1_000_000), timeout: 10).success == "")
    }

    @Test(arguments: ["sleep 30", "trap '' TERM; sleep 30", "sleep 30 & wait"])
    func aToolThatHangsIsGivenUpOnAtTheTimeout(script: String) async {
        let start = ContinuousClock.now
        #expect(await Command.run("sh", ["-c", script], timeout: 0.5).ending == .stopped)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aToolsOutputIsKeptWithHowItEnded() async {
        #expect(await Command.run("sh", ["-c", "cat; echo done"], input: "notes\n", timeout: 10) == .init(output: "notes\ndone\n", ending: .exited(0)))
        #expect(await Command.run("sh", ["-c", "echo nope; exit 1"], timeout: 10) == .init(output: "nope\n", ending: .exited(1)))
        #expect(await Command.run("sh", ["-c", "echo nope; exit 1"], timeout: 10).success == nil)
        #expect(await Command.run("sh", ["-c", "echo half; kill -KILL $$"], timeout: 10) == .init(output: "half\n", ending: .signalled(SIGKILL)))
    }

    @Test func theHelpersAToolStartedAreStoppedWithItAtTheTimeout() async throws {
        let mark = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(await Command.run("sh", ["-c", "sh -c 'sleep 2; touch \(mark.path(percentEncoded: false))' & wait"], timeout: 0.5).ending == .stopped)
        try await Task.sleep(for: .seconds(3))
        #expect(!FileManager.default.fileExists(atPath: mark.path(percentEncoded: false)))
    }

    @Test func aHelperIsStoppedBeforeItSeesItsOwnChildKilledAtTheTimeout() async throws {
        let mark = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
        let script = "sh -c 'sleep 1; sleep 30; : > \(mark)' & for i in $(seq 300); do sleep 30 & done; wait"
        #expect(await Command.run("sh", ["-c", script], timeout: 1.5).ending == .stopped)
        try await Task.sleep(for: .seconds(0.5))
        #expect(!FileManager.default.fileExists(atPath: mark))
    }

    @Test func aToolThatSucceededIsJudgedByItsExitEvenWhenAHelperOutlivesTheDeadline() async {
        let start = ContinuousClock.now
        #expect(await Command.run("sh", ["-c", "sleep 30 & echo ok"], timeout: 0.5).success == "ok\n")
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aToolSeesTheEnvironmentItIsGivenOnTopOfMartins() async {
        #expect(await Command.run("sh", ["-c", "printf '%s %s' \"$MARTIN_KEY\" \"${PATH:+path}\""], environment: ["MARTIN_KEY": "sk"], timeout: 10).success == "sk path")
    }

    @Test func aToolThatCannotBeFoundFails() async {
        #expect(await Command.run("martin-no-such-tool", [], timeout: 5).ending == .unlaunched)
        #expect(await Command.run("/martin/no-such-tool", [], timeout: 5).ending == .unlaunched)
    }

    @Test func aCancelledRunStopsTheToolAndItsHelpers() async throws {
        let mark = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
        let start = ContinuousClock.now
        let run = Task { await Command.run("sh", ["-c", "sh -c 'sleep 2; touch \(mark)' & wait"], timeout: 30) }
        try await Task.sleep(for: .seconds(0.3))
        run.cancel()
        #expect(await run.value.ending == .stopped)
        #expect(ContinuousClock.now - start < .seconds(2))
        try await Task.sleep(for: .seconds(2.5))
        #expect(!FileManager.default.fileExists(atPath: mark))
    }

    @Test func aRunCancelledBeforeItStartsNeverLaunchesTheTool() async throws {
        let mark = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
        let run = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Command.run("touch", [mark], timeout: 10)
        }
        #expect(await run.value.ending == .stopped)
        #expect(!FileManager.default.fileExists(atPath: mark))
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
        #expect(await Command.run("sh", ["-c", script.replacingOccurrences(of: "MARK", with: mark)], timeout: 30).success == "ok\n")
        #expect(ContinuousClock.now - start < .seconds(2))
        try await Task.sleep(for: .seconds(3))
        #expect(!FileManager.default.fileExists(atPath: mark))
    }

    @Test func aHelperThatWritesAfterTheToolExitsIsWaitedFor() async {
        #expect(await Command.run("sh", ["-c", "(sleep 1.5; echo late) & echo early"], timeout: 10).success == "early\nlate\n")
    }
}
