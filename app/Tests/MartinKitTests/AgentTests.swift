import Foundation
import Testing
@testable import MartinKit

struct AgentTests {
    let clones = RepositoryTests()

    let goodmeet = Project(name: "Goodmeet"), interviews = Project(name: "Interviews")

    private func picked(_ project: Project, _ answer: Data?, _ candidates: [Repository]) -> Repository? {
        Agent.pick(for: project, matches: answer.flatMap(Agent.matches(in:)) ?? [], among: candidates)
    }

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
        #expect(picked(goodmeet, answer("GoodnotesGlobal/data-platform", "goodnotesglobal/MA-turbo-overload"), [martin, overload, platform]) == overload)
    }

    @Test func aRepositoryWhoseNameOrReadmeNamesTheProjectCountsEvenWhenTheAgentLeavesItOut() throws {
        let platform = clones.repository("GoodnotesGlobal/data-platform", in: "data-platform")
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let agents = clones.repository("GoodnotesGlobal/infrastructure-goodmeet-agents", in: "infrastructure-goodmeet-agents")
        try "# Turbo Overload\nSet up **Goodmeet .env** first.".write(to: overload.folder.appending(path: "README.md"), atomically: true, encoding: .utf8)
        #expect(picked(goodmeet, answer("GoodnotesGlobal/data-platform"), [overload, platform]) == overload)
        #expect(picked(goodmeet, nil, [agents, overload]) == agents)
        #expect(picked(Project(name: "Good"), nil, [agents, overload]) == nil)
        #expect(picked(Project(name: "Overload"), nil, [platform, overload]) == overload)
    }

    @Test func aProjectNameTooShortToMeanAnythingNamesNoRepository() {
        let platform = clones.repository("GoodnotesGlobal/data-platform", in: "data-platform")
        #expect(!Agent.names(Project(name: "QA"), platform))
        #expect(!Agent.names(Project(name: " - "), platform))
        #expect(Agent.names(Project(name: "Data Platform"), platform))
    }

    @Test func thereIsNoPickWhenTheAgentNamesNoneOnlyStrangersOrTooManyToBelieve() {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(picked(interviews, answer(), [martin]) == nil)
        #expect(picked(interviews, answer("acme/atlas"), [martin]) == nil)
        #expect(picked(interviews, answer("ethanyxchen/martin", "a/b", "c/d", "e/f"), [martin]) == nil)
        #expect(picked(interviews, Data("Not logged in".utf8), [martin]) == nil)
    }

    @Test func anAnswerIsItsSlugsUnlessItCannotBeReadOrNamesTooMany() {
        #expect(Agent.matches(in: answer("GoodnotesGlobal/MA-turbo-overload")) == ["goodnotesglobal/ma-turbo-overload"])
        #expect(Agent.matches(in: answer("a/b", "c/d", "e/f", "g/h")) == [])
        #expect(Agent.matches(in: Data("Not logged in".utf8)) == nil)
    }
}
