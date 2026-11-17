import Foundation
import Testing
@testable import MartinKit

struct ProviderTests {
    private let schema = #"{"type":"object","properties":{"slug":{"type":"string"}}}"#

    private func object(_ data: Data?) throws -> NSDictionary {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func claudeIsAskedWithTheKeyAndTheSchema() throws {
        let request = Provider.anthropic.request("Martin", instructions: "Find it", schema: schema, key: "sk-ant")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        let body = try object(request.httpBody)
        #expect(body["system"] as? String == "Find it")
        #expect(body.value(forKeyPath: "output_config.format.schema") as? NSDictionary == (try object(Data(schema.utf8))))
    }

    @Test func openAIIsAskedWithTheKeyAndTheSchema() throws {
        let request = Provider.openai.request("Martin", instructions: "Find it", schema: schema, key: "sk-proj")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-proj")
        let body = try object(request.httpBody)
        #expect(body["instructions"] as? String == "Find it")
        #expect(body.value(forKeyPath: "text.format.schema") as? NSDictionary == (try object(Data(schema.utf8))))
    }

    @Test func claudesAnswerIsTheTextOfAFinishedReply() throws {
        let reply = #"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"slug\":\"ethanyxchen/martin\"}"}]}"#
        #expect(try object(Provider.anthropic.structuredOutput(of: Data(reply.utf8))) == ["slug": "ethanyxchen/martin"])
        #expect(Provider.anthropic.structuredOutput(of: Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)) == nil)
    }

    @Test func openAIsAnswerIsTheTextOfACompletedResponse() throws {
        let reply = #"{"status":"completed","output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"{\"slug\":null}"}]}]}"#
        #expect(try object(Provider.openai.structuredOutput(of: Data(reply.utf8))) == ["slug": NSNull()])
        #expect(Provider.openai.structuredOutput(of: Data(#"{"status":"incomplete","output":[]}"#.utf8)) == nil)
    }
}
