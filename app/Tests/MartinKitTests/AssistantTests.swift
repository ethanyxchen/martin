import Foundation
import Testing
@testable import MartinKit

struct AssistantTests {
    private func object(_ data: Data?) throws -> NSDictionary {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func claudesAnswerIsTheStructuredOutputOfASuccessfulRun() throws {
        let output = #"{"type":"result","is_error":false,"result":"done","structured_output":{"slug":"ethanyxchen/martin","reason":"README"}}"#
        #expect(try object(Assistant.claude.structuredOutput(of: output)) == ["slug": "ethanyxchen/martin", "reason": "README"])
    }

    @Test func claudeHasNoAnswerWhenTheRunFailed() {
        #expect(Assistant.claude.structuredOutput(of: #"{"is_error":true,"result":"Not logged in · Please run /login"}"#) == nil)
        #expect(Assistant.claude.structuredOutput(of: #"{"is_error":false,"result":"no schema"}"#) == nil)
        #expect(Assistant.claude.structuredOutput(of: "Not logged in") == nil)
    }

    @Test func codexPrintsItsAnswerAsIs() throws {
        #expect(try object(Assistant.codex.structuredOutput(of: #"{"slug":null,"reason":"Nothing fits"}"#)) == ["slug": NSNull(), "reason": "Nothing fits"])
    }

    @Test func eachAssistantSaysHowToInstallItAndSignIn() {
        #expect(Assistant.allCases.map(\.title) == ["Claude Code", "Codex"])
        #expect(Assistant.claude.signIn == "claude auth login")
        #expect(Assistant.codex.install == "brew install --cask codex")
        #expect(Assistant.codex.signIn == "codex login")
    }
}
