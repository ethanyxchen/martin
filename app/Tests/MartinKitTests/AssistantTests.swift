import Foundation
import Testing
@testable import MartinKit

struct AssistantTests {
    private func object(_ data: Data?) throws -> NSDictionary {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func claudesAnswerIsTheStructuredOutputOfASuccessfulRun() throws {
        let output = #"{"type":"result","is_error":false,"result":"done","structured_output":{"slug":"ethanyxchen/martin"}}"#
        #expect(try object(Assistant.claude.structuredOutput(of: output)) == ["slug": "ethanyxchen/martin"])
    }

    @Test func claudeHasNoAnswerWhenTheRunFailed() {
        #expect(Assistant.claude.structuredOutput(of: #"{"is_error":true,"result":"Not logged in · Please run /login"}"#) == nil)
        #expect(Assistant.claude.structuredOutput(of: #"{"is_error":false,"result":"no schema"}"#) == nil)
        #expect(Assistant.claude.structuredOutput(of: "Not logged in") == nil)
    }

    @Test func codexPrintsItsAnswerAsIs() throws {
        #expect(try object(Assistant.codex.structuredOutput(of: #"{"slug":null}"#)) == ["slug": NSNull()])
    }

    @Test func eachAssistantNamesTheAccountItSignsInWith() {
        #expect(Assistant.allCases.map(\.title) == ["Claude Code", "Codex"])
        #expect(Assistant.allCases.map(\.account) == ["Claude", "ChatGPT"])
    }
}

struct AssistantEffortTests {
    @Test func deepWorkUsesTheLargeModelAtHighEffortWithMoreTime() {
        #expect(Assistant.claude.claudeModel(for: .deep) == ["--model", "opus", "--effort", "high"])
        #expect(Assistant.claude.claudeModel(for: .quick) == ["--model", "haiku"])
        #expect(Assistant.claude.timeout(for: .deep) > Assistant.claude.timeout(for: .quick))
    }
}
