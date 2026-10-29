import Foundation
import Testing
@testable import MartinKit

struct AgentTests {
    let clones = RepositoryTests()

    private func answer(_ slug: String?) -> Data {
        Data(#"{"slug":\#(slug.map { "\"\($0)\"" } ?? "null")}"#.utf8)
    }

    @Test func thePromptCarriesTheNotesAndEachCandidatesReadmeInRankedOrder() throws {
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        try "# Goodmeet\nMeeting summaries".write(to: overload.folder.appending(path: "README.md"), atomically: true, encoding: .utf8)
        let prompt = Agent.prompt(for: Project(name: "Goodmeet"), notes: ["# Tasks\n- ship RC 1.0.30"], among: [overload, martin])
        #expect(prompt.contains("<project name=\"Goodmeet\">\n<note>\n# Tasks\n- ship RC 1.0.30\n</note>\n</project>"))
        #expect(prompt.contains("<repository slug=\"GoodnotesGlobal/ma-turbo-overload\" folder=\"ma-turbo-overload\">\n# Goodmeet\nMeeting summaries\n</repository>\n<repository slug=\"ethanyxchen/martin\" folder=\"martin\">"))
    }

    @Test func aProjectWithoutNotesSaysSo() {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(Agent.prompt(for: Project(name: "Martin"), notes: [], among: [martin]).contains("<project name=\"Martin\">\nNo notes yet.\n</project>"))
    }

    @Test func longNotesAndReadmesAreCut() {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        let prompt = Agent.prompt(for: Project(name: "Martin"), notes: [String(repeating: "a", count: Agent.excerpt + 1)], among: [martin])
        #expect(prompt.contains(String(repeating: "a", count: Agent.excerpt) + "\n</note>"))
    }

    @Test func thePickIsTheCandidateTheAgentNamed() {
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(Agent.pick(from: answer("goodnotesglobal/MA-turbo-overload"), among: [martin, overload]) == overload)
    }

    @Test func thereIsNoPickWhenTheAgentDeclinesOrNamesAStranger() {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(Agent.pick(from: answer(nil), among: [martin]) == nil)
        #expect(Agent.pick(from: answer("acme/atlas"), among: [martin]) == nil)
        #expect(Agent.pick(from: Data("Not logged in".utf8), among: [martin]) == nil)
    }
}
