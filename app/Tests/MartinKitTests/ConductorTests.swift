import Foundation
import Testing
@testable import MartinKit

struct ConductorTests {
    let project = Project(name: "Martin")
    let today = try! Date("2026-10-29T12:00:00Z", strategy: .iso8601)

    private func note(_ id: String, _ text: String, changed: Date? = nil) -> Conductor.Note {
        Conductor.Note(id: id, title: "Note \(id)", date: today.addingTimeInterval(-86_400), changedAt: changed ?? today.addingTimeInterval(-86_400), text: text)
    }

    private func sources(notes: [Conductor.Note] = [], activity: String? = "2026-10-28 Link repositories") -> Conductor.Sources {
        Conductor.Sources(notes: notes) { _ in activity }
    }

    private func step(_ action: String, note: String? = nil, overview: String? = nil) -> Data {
        Data(#"{"thinking":"","action":"\#(action)","note":\#(note.map { "\"\($0)\"" } ?? "null"),"overview":\#(overview ?? "null")}"#.utf8)
    }

    private let overview = #"{"now":[{"title":"Project overview","caption":"Settling the layout.","updated":"2026-10-28"}],"next":[],"shelved":[]}"#

    private final class Script: @unchecked Sendable {
        private var answers: [Data?]
        private(set) var prompts: [String] = []

        init(_ answers: [Data?]) {
            self.answers = answers
        }

        func ask(_ prompt: String) -> Data? {
            prompts.append(prompt)
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }

    private func run(_ script: Script, previous: Overview? = nil, sources: Conductor.Sources? = nil, turns: Int = Conductor.turns) async -> Overview? {
        await Conductor.run(project, previous: previous, sources: sources ?? self.sources(), now: today, turns: turns) { script.ask($0) }
    }

    @Test func submittingEndsTheLoopWithTheOverviewReadAtNow() async throws {
        let script = Script([step("submit", overview: overview)])
        let result = try #require(await run(script))
        #expect(result.now == [Overview.Task(title: "Project overview", caption: "Settling the layout.", updatedAt: try Date("2026-10-28", strategy: .iso8601.year().month().day()))])
        #expect(result.readAt == today)
        #expect(script.prompts.count == 1)
    }

    @Test func theConductorReadsWhatItAsksForAndSeesItNextTurn() async throws {
        let script = Script([step("read_note", note: "a"), step("read_activity"), step("submit", overview: overview)])
        _ = await run(script, sources: sources(notes: [note("a", "Start with the working-on UI")]))
        #expect(script.prompts[0].contains("- a · Note a"))
        #expect(!script.prompts[0].contains("Start with the working-on UI"))
        #expect(script.prompts[1].contains("Note a, “Note a”:\nStart with the working-on UI"))
        #expect(script.prompts[2].contains("GitHub activity:\n2026-10-28 Link repositories"))
    }

    @Test func aRepeatedOrUnknownReadIsRefusedInsteadOfRepeated() async {
        let script = Script([step("read_note", note: "a"), step("read_note", note: "a"), step("read_note", note: "zzz"), step("read_activity"), step("read_activity"), step("submit", overview: overview)])
        _ = await run(script, sources: sources(notes: [note("a", "text")]))
        #expect(script.prompts[2].contains("Note a was already read."))
        #expect(script.prompts[3].contains("There is no note with id zzz."))
        #expect(script.prompts[5].contains("The activity was already read."))
    }

    @Test func aRevisedDraftIsShownBackSoItCanBeCondensed() async {
        let script = Script([step("revise", overview: overview), step("submit", overview: overview)])
        _ = await run(script)
        #expect(script.prompts[0].contains("Your current draft:\nNone."))
        #expect(script.prompts[1].contains("Your current draft:\nnow:\n- Project overview · 2026-10-28 · Settling the layout."))
    }

    @Test func whatHasChangedSinceTheLastReadIsFlaggedAndActivityIsAskedSinceThen() async throws {
        let before = Overview(readAt: today.addingTimeInterval(-3_600))
        let since = Script([step("read_activity"), step("submit", overview: overview)])
        let asked = AskedSince()
        let sources = Conductor.Sources(notes: [note("old", ""), note("edited", "", changed: today)]) { await asked.record($0); return "x" }
        _ = await run(since, previous: before, sources: sources)
        #expect(since.prompts[0].contains("- edited · Note edited"))
        #expect(since.prompts[0].contains("· new since last read"))
        #expect(since.prompts[0].components(separatedBy: "new since last read").count == 2)
        #expect(await asked.dates == [before.readAt])
    }

    @Test func aFailedAnswerGivesNoOverview() async {
        #expect(await run(Script([nil])) == nil)
        #expect(await run(Script([Data("nonsense".utf8)])) == nil)
    }

    @Test func theLastTurnIsToldToSubmitAndFallsBackToTheDraft() async {
        let script = Script([step("revise", overview: overview), step("read_activity")])
        let result = await run(script, turns: 2)
        #expect(script.prompts[1].contains("This is your last turn: submit now."))
        #expect(result?.now.first?.title == "Project overview")
        #expect(await run(Script([step("read_activity")]), turns: 1) == nil)
    }

    @Test func submittingWithoutAnOverviewIsRefused() async {
        let script = Script([step("submit"), step("submit", overview: overview)])
        #expect(await run(script) != nil)
        #expect(script.prompts[1].contains("Submit needs an overview"))
    }

    @Test func anOverviewIsTidiedAndCapped() async throws {
        let many = (1...9).map { #"{"title":" Task \#($0) ","caption":"c","updated":null}"# }.joined(separator: ",")
        let draft = #"{"now":[\#(many)],"next":[{"title":"  ","caption":"x","updated":null}],"shelved":[{"title":"Idea","caption":"\#(String(repeating: "a", count: 300))","updated":"2099-01-01"},{"title":"Other","caption":"","updated":"not a date"}]}"#
        let result = try #require(await run(Script([step("submit", overview: draft)])))
        #expect(result.now.map(\.title) == ["Task 1", "Task 2", "Task 3"])
        #expect(result.next.isEmpty)
        #expect(result.shelved.first?.caption.count == Conductor.captionLimit)
        #expect(result.shelved.map(\.updatedAt) == [nil, nil])
    }

    @Test func theSchemaIsValidJSONWithEveryPropertyRequired() throws {
        let schema = try #require(try JSONSerialization.jsonObject(with: Data(Conductor.schema.utf8)) as? [String: Any])
        #expect((schema["required"] as? [String])?.sorted() == ["action", "note", "overview", "thinking"])
    }
}

private actor AskedSince {
    private(set) var dates: [Date?] = []

    func record(_ date: Date?) {
        dates.append(date)
    }
}
