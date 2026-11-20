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

struct OverviewJobTests {
    let clones = RepositoryTests()
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let cutoff = Date(timeIntervalSince1970: 1_795_000_000)

    @Test func theOverviewJobCarriesEveryInputWithTimesInTheLocalOffsetAndNullsSpelledOut() throws {
        let martin = clones.repository("ethanyxchen/martin", in: "martin")
        let owner = Owner(name: "Ada Lovelace", email: "Ada@Example.com", account: "ada 42")
        let previous = Overview(now: [.init(title: "Agent", caption: "Wiring it up.")], next: [], shelved: [], readAt: cutoff - 3600)
        let note = Agent.OverviewJob.Note(id: "2026-11-17-090000", title: "Standup", date: cutoff - 7200, changedAt: cutoff - 60, file: URL(filePath: "/notes/standup/note.md"))
        let job = Agent.OverviewJob(provider: .anthropic, project: "Martin", owner: owner, cutoff: cutoff, previous: previous, notes: [note], repository: martin)
        let encoded = try JSONSerialization.jsonObject(with: AgentClient.encoder(in: zone).encode(job)) as? NSDictionary
        #expect(encoded == [
            "kind": "overview",
            "provider": "anthropic",
            "project": ["name": "Martin"],
            "owner": ["name": "Ada Lovelace", "emails": ["ada@example.com", "42+ada@users.noreply.github.com"], "login": "ada"],
            "cutoff": "2026-11-18T03:06:40-08:00",
            "previous": [
                "now": [["title": "Agent", "caption": "Wiring it up.", "updated": NSNull()]],
                "next": [], "shelved": [],
                "readAt": "2026-11-18T02:06:40-08:00",
            ],
            "notes": [["id": "2026-11-17-090000", "title": "Standup", "date": "2026-11-18T01:06:40-08:00", "changedAt": "2026-11-18T03:05:40-08:00", "path": "/notes/standup/note.md"]],
            "repository": ["folder": martin.folder.path(percentEncoded: false), "slug": "ethanyxchen/martin"],
        ])
    }

    @Test func aFirstOverviewWithoutARepositorySendsNulls() throws {
        let job = Agent.OverviewJob(provider: .openai, project: "Interviews", owner: Owner(name: nil, email: nil, account: nil), cutoff: cutoff, previous: nil, notes: [], repository: nil)
        let encoded = try #require(JSONSerialization.jsonObject(with: AgentClient.encoder(in: zone).encode(job)) as? NSDictionary)
        #expect(encoded["previous"] as? NSNull != nil)
        #expect(encoded["repository"] as? NSNull != nil)
        #expect(encoded["owner"] as? NSDictionary == ["name": "", "emails": [], "login": ""])
    }

    @Test func theAgentsSectionsBecomeAnOverviewReadAtTheCutoff() throws {
        let line = #"{"type":"result","result":{"now":[{"title":"Agent","caption":"Wiring it up.","updated":"2026-11-17"}],"next":[],"shelved":[{"title":"Docs","caption":"Paused.","updated":null}]}}"#
        let sections: Agent.Sections = try AgentClient.result(of: Command.Outcome(output: line + "\n", ending: .exited(0))).result
        #expect(sections.now == [.init(title: "Agent", caption: "Wiring it up.", updated: "2026-11-17")])
        #expect(sections.shelved == [.init(title: "Docs", caption: "Paused.")])
        let lookup = #"{"type":"result","result":{"evidence":"","slugs":[]}}"#
        #expect(throws: AgentClient.Failure.broken) { let _: AgentClient.Reply<Agent.Sections> = try AgentClient.result(of: Command.Outcome(output: lookup, ending: .exited(0))) }
    }
}
