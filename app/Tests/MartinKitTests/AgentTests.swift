import Foundation
import Testing
@testable import MartinKit

struct AgentTests {
    let clones = RepositoryTests()

    let goodmeet = Project(name: "Goodmeet"), interviews = Project(name: "Interviews")

    private func answer(_ slugs: String...) -> Data {
        Data(#"{"evidence":"","slugs":[\#(slugs.map { "\"\($0)\"" }.joined(separator: ","))]}"#.utf8)
    }

    @Test func thePromptListsTheNotesThenOneLinePerRepositoryInRankedOrder() throws {
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        try "The Goodmeet Electron app.".write(to: overload.folder.appending(path: "README.md"), atomically: true, encoding: .utf8)
        let prompt = Agent.prompt(for: Project(name: "Goodmeet"), notes: ["# Tasks\n- ship RC 1.0.30", "# Sync"], among: [overload, martin])
        #expect(prompt == """
            Project: Goodmeet

            Notes:
            # Tasks
            - ship RC 1.0.30

            # Sync

            Repositories:
            GoodnotesGlobal/ma-turbo-overload: The Goodmeet Electron app.
            ethanyxchen/martin
            """)
    }

    @Test func aProjectWithoutNotesSaysSo() {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(Agent.prompt(for: Project(name: "Martin"), notes: [], among: [martin]).contains("Notes:\nNo notes yet.\n"))
    }

    @Test func longNotesAndSummariesAreCut() throws {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        try String(repeating: "b", count: Agent.summaryLimit + 1).write(to: martin.folder.appending(path: "README.md"), atomically: true, encoding: .utf8)
        let prompt = Agent.prompt(for: Project(name: "Martin"), notes: [String(repeating: "a", count: Agent.excerpt + 1)], among: [martin])
        #expect(prompt.contains("\n" + String(repeating: "a", count: Agent.excerpt) + "\n\n"))
        #expect(prompt.hasSuffix(": " + String(repeating: "b", count: Agent.summaryLimit)))
    }

    @Test func ofTheRepositoriesTheAgentNamesThePickIsTheFirstCandidateWhichIsTheMostRecentlyWorkedOn() {
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let platform = clones.repository("GoodnotesGlobal/data-platform", in: "data-platform")
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(Agent.pick(for: goodmeet, from: answer("GoodnotesGlobal/data-platform", "goodnotesglobal/MA-turbo-overload"), among: [martin, overload, platform]) == overload)
    }

    @Test func aRepositoryWhoseNameOrReadmeNamesTheProjectCountsEvenWhenTheAgentLeavesItOut() throws {
        let platform = clones.repository("GoodnotesGlobal/data-platform", in: "data-platform")
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let agents = clones.repository("GoodnotesGlobal/infrastructure-goodmeet-agents", in: "infrastructure-goodmeet-agents")
        try "# Turbo Overload\nSet up **Goodmeet .env** first.".write(to: overload.folder.appending(path: "README.md"), atomically: true, encoding: .utf8)
        #expect(Agent.pick(for: goodmeet, from: answer("GoodnotesGlobal/data-platform"), among: [overload, platform]) == overload)
        #expect(Agent.pick(for: goodmeet, from: nil, among: [agents, overload]) == agents)
        #expect(Agent.pick(for: Project(name: "Good"), from: nil, among: [agents, overload]) == nil)
        #expect(Agent.pick(for: Project(name: "Overload"), from: nil, among: [platform, overload]) == overload)
    }

    @Test func aProjectNameTooShortToMeanAnythingNamesNoRepository() {
        let platform = clones.repository("GoodnotesGlobal/data-platform", in: "data-platform")
        #expect(!Agent.names(Project(name: "QA"), platform))
        #expect(!Agent.names(Project(name: " - "), platform))
        #expect(Agent.names(Project(name: "Data Platform"), platform))
    }

    @Test func thereIsNoPickWhenTheAgentNamesNoneOnlyStrangersOrTooManyToBelieve() {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(Agent.pick(for: interviews, from: answer(), among: [martin]) == nil)
        #expect(Agent.pick(for: interviews, from: answer("acme/atlas"), among: [martin]) == nil)
        #expect(Agent.pick(for: interviews, from: answer("ethanyxchen/martin", "a/b", "c/d", "e/f"), among: [martin]) == nil)
        #expect(Agent.pick(for: interviews, from: Data("Not logged in".utf8), among: [martin]) == nil)
    }
}
