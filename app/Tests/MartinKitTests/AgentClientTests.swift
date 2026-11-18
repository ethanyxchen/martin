import Foundation
import Testing
@testable import MartinKit

struct AgentClientTests {
    struct Echo: Codable, Equatable {
        let evidence: String
        let slugs: [String]
    }

    let credential = Credential(provider: .anthropic, key: "sk-ant")
    let progress = #"{"type":"progress","tool":"read_note","input":{"id":"a"}}"#
    let answer = #"{"type":"result","result":{"evidence":"notes","slugs":["acme/atlas"]}}"#
    let rejected = #"{"type":"error","message":"The Claude API key was rejected."}"#

    private func result(_ lines: [String], _ ending: Command.Outcome.Ending) -> Result<Agent.Answer, AgentClient.Failure> {
        Result { () throws(AgentClient.Failure) in try AgentClient.result(of: Command.Outcome(output: lines.map { $0 + "\n" }.joined(), ending: ending)) }
    }

    private func agent(_ script: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try "#!/bin/sh\n\(script)\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
        return file
    }

    @Test func theResultIsTheOneResultEventAfterAnyProgressFromAnAgentThatExitedCleanly() throws {
        #expect(try result([progress, progress, answer], .exited(0)).get().slugs == ["acme/atlas"])
        #expect(try result([answer], .exited(0)).get().slugs == ["acme/atlas"])
    }

    @Test func aLineSeparatorInsideAStringDoesNotEndTheEvent() throws {
        #expect(try result([#"{"type":"result","result":{"evidence":"a\#u{2028}b\#u{85}c","slugs":["acme/atlas"]}}"#], .exited(0)).get().slugs == ["acme/atlas"])
    }

    @Test func anErrorTheAgentReportsSurvivesItsFailedExit() {
        #expect(result([progress, rejected], .exited(1)) == .failure(.reported("The Claude API key was rejected.")))
        #expect(AgentClient.Failure.reported("The Claude API key was rejected.").message == "The Claude API key was rejected.")
    }

    @Test(arguments: [
        ([String](), Command.Outcome.Ending.exited(0)),
        (["progress"], .exited(0)),
        (["answer", "answer"], .exited(0)),
        (["answer", "progress"], .exited(0)),
        (["answer", "rejected"], .exited(1)),
        (["answer"], .exited(1)),
        (["rejected"], .exited(0)),
        (["progress", "Not logged in", "answer"], .exited(0)),
        (["progress"], .signalled(SIGKILL)),
        (["answer"], .signalled(SIGKILL)),
        (["overview"], .exited(0)),
    ])
    func anythingButOneTerminalEventMatchingTheExitIsBroken(lines: [String], ending: Command.Outcome.Ending) {
        let events = [
            "progress": progress, "answer": answer, "rejected": rejected,
            "overview": #"{"type":"result","result":{"now":[],"next":[],"shelved":[]}}"#,
        ]
        #expect(result(lines.map { events[$0] ?? $0 }, ending) == .failure(.broken))
    }

    @Test func anAgentThatCouldNotStartOrWasStoppedSaysSo() {
        #expect(result([], .unlaunched) == .failure(.unavailable))
        #expect(result([progress], .stopped) == .failure(.timedOut))
    }

    @Test func theAgentReadsTheJobOnItsInputAndTheKeyInItsEnvironment() async throws {
        let job = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let agent = try agent(#"cat > "\#(job.path(percentEncoded: false))"; printf '{"type":"result","result":{"evidence":"%s","slugs":[]}}\n' "$ANTHROPIC_API_KEY""#)
        let echo: Echo = try await AgentClient(executable: agent).run(["job": 1], using: credential)
        #expect(echo == Echo(evidence: "sk-ant", slugs: []))
        #expect(try String(contentsOf: job, encoding: .utf8) == #"{"job":1}"#)
    }

    @Test func aMissingAgentIsUnavailable() async {
        await #expect(throws: AgentClient.Failure.unavailable) { let _: Echo = try await AgentClient(executable: nil).run(["job": 1], using: credential) }
        await #expect(throws: AgentClient.Failure.unavailable) { let _: Echo = try await AgentClient(executable: URL(filePath: "/martin/no-agent")).run(["job": 1], using: credential) }
    }

    @Test func anAgentThatHangsTimesOut() async throws {
        let agent = try agent("sleep 30")
        await #expect(throws: AgentClient.Failure.timedOut) { let _: Echo = try await AgentClient(executable: agent, timeout: 0.5).run(["job": 1], using: credential) }
    }

    @Test func cancellingARequestStopsTheAgentAndWhatItStarted() async throws {
        let mark = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
        let agent = try agent("sh -c 'sleep 2; touch \(mark)' & wait")
        let start = ContinuousClock.now
        let request = Task { () async throws -> Echo in try await AgentClient(executable: agent).run(["job": 1], using: credential) }
        try await Task.sleep(for: .seconds(0.3))
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(ContinuousClock.now - start < .seconds(2))
        try await Task.sleep(for: .seconds(2.5))
        #expect(!FileManager.default.fileExists(atPath: mark))
    }
}
