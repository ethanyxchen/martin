import Foundation
import Testing
@testable import MartinKit

struct AgentTests {
    let clones = RepositoryTests()

    let goodmeet = Project(name: "Goodmeet"), interviews = Project(name: "Interviews")

    private func picked(_ project: Project, _ matches: Set<String>, _ candidates: [Repository]) -> Repository? {
        Agent.pick(for: project, matches: matches, among: candidates)
    }

    @Test func theLookupJobNamesTheProviderTheNoteFilesAndEveryCandidate() throws {
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        try "The Goodmeet Electron app.".write(to: overload.folder.appending(path: "README.md"), atomically: true, encoding: .utf8)
        let note = Agent.Note(title: "Tasks", file: URL(filePath: "/notes/tasks/note.md"))
        let job = Agent.LookupJob(for: goodmeet, notes: [note], among: [overload, martin], provider: .openai)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? NSDictionary
        #expect(encoded == [
            "kind": "repositoryLookup",
            "provider": "openai",
            "project": ["name": "Goodmeet"],
            "notes": [["title": "Tasks", "path": "/notes/tasks/note.md"]],
            "candidates": [
                ["slug": "GoodnotesGlobal/ma-turbo-overload", "summary": "The Goodmeet Electron app."],
                ["slug": "ethanyxchen/martin", "summary": NSNull()],
            ],
        ])
    }

    @Test func theKeyReachesTheAgentAsItsProvidersVariable() {
        #expect(Credential(provider: .anthropic, key: "sk-ant").environment == ["ANTHROPIC_API_KEY": "sk-ant"])
        #expect(Credential(provider: .openai, key: "sk-proj").environment == ["OPENAI_API_KEY": "sk-proj"])
    }

    @Test func ofTheRepositoriesTheAgentNamesThePickIsTheFirstCandidateWhichIsTheMostRecentlyWorkedOn() {
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let platform = clones.repository("GoodnotesGlobal/data-platform", in: "data-platform")
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(picked(goodmeet, ["goodnotesglobal/data-platform", "goodnotesglobal/ma-turbo-overload"], [martin, overload, platform]) == overload)
    }

    @Test func aRepositoryWhoseNameOrReadmeNamesTheProjectCountsEvenWhenTheAgentLeavesItOut() throws {
        let platform = clones.repository("GoodnotesGlobal/data-platform", in: "data-platform")
        let overload = clones.repository("GoodnotesGlobal/ma-turbo-overload", in: "ma-turbo-overload")
        let agents = clones.repository("GoodnotesGlobal/infrastructure-goodmeet-agents", in: "infrastructure-goodmeet-agents")
        try "# Turbo Overload\nSet up **Goodmeet .env** first.".write(to: overload.folder.appending(path: "README.md"), atomically: true, encoding: .utf8)
        #expect(picked(goodmeet, ["goodnotesglobal/data-platform"], [overload, platform]) == overload)
        #expect(picked(goodmeet, [], [agents, overload]) == agents)
        #expect(picked(Project(name: "Good"), [], [agents, overload]) == nil)
        #expect(picked(Project(name: "Overload"), [], [platform, overload]) == overload)
    }

    @Test func aProjectNameTooShortToMeanAnythingNamesNoRepository() {
        let platform = clones.repository("GoodnotesGlobal/data-platform", in: "data-platform")
        #expect(!Agent.names(Project(name: "QA"), platform))
        #expect(!Agent.names(Project(name: " - "), platform))
        #expect(Agent.names(Project(name: "Data Platform"), platform))
    }

    @Test func thereIsNoPickWhenTheAgentNamesNoneOrOnlyStrangers() {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        #expect(picked(interviews, [], [martin]) == nil)
        #expect(picked(interviews, ["acme/atlas"], [martin]) == nil)
    }
}
