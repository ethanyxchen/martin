import AppKit
import Foundation
import MartinKit
import SwiftUI
import Testing
@testable import Martin

@MainActor
final class FakeAgent {
    var now = Date(timeIntervalSince1970: (Date.now + 86400).timeIntervalSince1970.rounded(.down))
    var jobs: [Agent.OverviewJob] = []
    var activity = false
    var failure: AgentClient.Failure?
    var during: (() -> Void)?
    var checking: (() -> Void)?
    var waits: [TimeInterval] = []

    var overviewer: Overviewer {
        Overviewer(
            overview: { job, _ in try await self.answer(job) },
            hasActivity: { _, _ in await self.check() },
            owner: { _ in Owner(name: "Ada", email: "ada@example.com", account: "ada 42") },
            now: { MainActor.assumeIsolated { self.now } },
            wait: { interval in
                await MainActor.run { self.waits.append(interval) }
                withUnsafeCurrentTask { $0?.cancel() }
            }
        )
    }

    private func check() -> Bool {
        let checking = checking
        self.checking = nil
        checking?()
        return activity
    }

    private func answer(_ job: Agent.OverviewJob) throws -> Overview {
        jobs.append(job)
        let during = during
        self.during = nil
        during?()
        if let failure { throw failure }
        return Overview(now: [.init(title: "Run \(jobs.count)", caption: "Going.")], next: [], shelved: [], readAt: job.cutoff)
    }
}

@MainActor
final class OverviewRefreshTests: Sandbox {
    let agent = FakeAgent()

    private func launch() -> AppState {
        let app = AppState(library: library, defaults: defaults, credentials: credentials, finder: RepositoryFinder(nearby: { _ in [] }, match: { _, _, _, _ in [] }), overviewer: agent.overviewer)
        app.credential = Credential(provider: .anthropic, key: "sk-ant")
        return app
    }

    private func project(_ app: AppState, named name: String = "Martin", notes: Int = 1) throws -> Project {
        app.file(try library.create(), inNewProjectNamed: name)
        let project = try #require(app.allProjects.first { $0.name == name })
        for index in 0..<notes {
            let meeting = index == 0 ? try #require(app.notes(in: project).first) : try library.create(project: project.id)
            app.save("Notes \(index)", for: meeting)
        }
        app.reload()
        return project
    }

    private func linked(_ app: AppState, _ project: Project) throws -> Project {
        let folder = library.root.appending(path: "clones/martin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: ".git"), withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = git@github.com:ethanyxchen/martin.git\n".write(to: folder.appending(path: ".git/config"), atomically: true, encoding: .utf8)
        app.link(project, to: .folder(folder))
        return try #require(app.allProjects.first { $0.id == project.id })
    }

    private func touch(_ meeting: Meeting, at date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: library.noteFile(of: meeting).path(percentEncoded: false))
    }

    private func passTime(_ interval: TimeInterval) {
        agent.now += interval
    }

    @Test func aProjectNeverCheckedIsDueAtOnceAndNextWhenThirtyMinutesHavePassed() async throws {
        let app = launch()
        _ = try linked(app, try project(app))
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 1)
        agent.activity = true
        passTime(AppState.overviewInterval - 1)
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 1)
        passTime(1)
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 2)
    }

    @Test func aDueProjectWithNothingNewStartsNoAgentButCountsAsCheckedAcrossLaunches() async throws {
        let app = launch()
        let project = try project(app)
        await app.refreshDueOverviews()
        passTime(AppState.overviewInterval)
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 1)
        #expect(app.overviews[project.id]?.checkedAt == agent.now)
        let relaunched = launch()
        #expect(relaunched.overviews[project.id] == app.overviews[project.id])
        #expect(relaunched.nextOverviewCheck() == agent.now + AppState.overviewInterval)
        passTime(AppState.overviewInterval - 1)
        agent.activity = true
        await relaunched.refreshDueOverviews()
        #expect(agent.jobs.count == 1)
    }

    enum Change: CaseIterable {
        case editedNote, addedNote, removedNote, removedLastNote, archivedNote, changedLink, repositoryActivity
    }

    @Test(arguments: Change.allCases)
    func eachChangeStartsARefreshAtTheNextCheck(change: Change) async throws {
        let app = launch()
        let project = try linked(app, try project(app, notes: change == .removedLastNote ? 1 : 2))
        await app.refreshDueOverviews()
        passTime(AppState.overviewInterval)
        let note = try #require(app.notes(in: project).first)
        switch change {
        case .editedNote: try touch(note, at: agent.now - 60)
        case .addedNote: app.save("New", for: try library.create(project: project.id)); app.reload(); try touch(try #require(app.notes(in: project).last), at: agent.now - 3 * AppState.overviewInterval)
        case .removedNote, .removedLastNote: app.delete(note)
        case .archivedNote: app.archive(note)
        case .changedLink: app.link(project, to: .folder(library.root.appending(path: "other", directoryHint: .isDirectory)))
        case .repositoryActivity: agent.activity = true
        }
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 2)
    }

    @Test func noteEditsAloneStartNoAgent() async throws {
        let app = launch()
        let project = try project(app)
        await app.refreshDueOverviews()
        let note = try #require(app.notes(in: project).first)
        app.save("Edited", for: note)
        try touch(note, at: agent.now + 60)
        passTime(120)
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 1)
    }

    @Test func refreshingByHandSkipsTheWaitAndTheChangeCheckAndMovesTheNextCheck() async throws {
        let app = launch()
        let project = try project(app)
        await app.refreshDueOverviews()
        passTime(600)
        await app.refreshOverview(of: project)?.value
        #expect(agent.jobs.count == 2)
        #expect(app.nextOverviewCheck() == agent.now + AppState.overviewInterval)
        #expect(app.overviews[project.id]?.built?.overview.now.map(\.title) == ["Run 2"])
    }

    @Test func theJobSendsTheProjectsActiveWrittenNotesAndThePreviousOverview() async throws {
        let app = launch()
        let project = try project(app, notes: 2)
        let notes = app.notes(in: project)
        _ = try library.create(project: project.id)
        app.archive(notes[1])
        app.reload()
        await app.refreshOverview(of: project)?.value
        passTime(60)
        await app.refreshOverview(of: project)?.value
        let job = try #require(agent.jobs.last)
        #expect(job.notes.map(\.id) == [notes[0].id])
        #expect(job.cutoff == agent.now)
        let sent = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? NSDictionary)
        #expect((sent["previous"] as? NSDictionary)?["now"] as? [NSDictionary] == [["title": "Run 1", "caption": "Going.", "updated": NSNull()]])
    }

    @Test func secretArchivedAndUnconfiguredProjectsAreNeverRefreshed() async throws {
        let app = launch()
        let secret = try project(app, named: "Secret"), archived = try project(app, named: "Archived")
        app.keepSecret(secret, true)
        app.archive(archived)
        await app.refreshDueOverviews()
        #expect(app.refreshOverview(of: secret) == nil)
        #expect(app.refreshOverview(of: archived) == nil)
        app.credential = nil
        let plain = try project(app, named: "Plain")
        await app.refreshDueOverviews()
        #expect(app.refreshOverview(of: plain) == nil)
        #expect(agent.jobs.isEmpty)
    }

    @Test func refreshingByHandDuringARequestJoinsIt() async throws {
        let app = launch()
        let project = try project(app)
        agent.during = { #expect(app.refreshOverview(of: project) != nil) }
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 1)
        #expect(app.overviewStatus[project.id] == nil)
    }

    @Test func aNoteEditedDuringARequestKeepsItsResultAndIsReadAtTheNextCheck() async throws {
        let app = launch()
        let project = try project(app)
        let note = try #require(app.notes(in: project).first)
        let cutoff = agent.now
        agent.during = {
            self.passTime(30)
            try? self.touch(note, at: self.agent.now)
        }
        await app.refreshDueOverviews()
        #expect(app.overviews[project.id]?.built?.overview.readAt == cutoff)
        passTime(AppState.overviewInterval)
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 2)
    }

    enum Abandon: CaseIterable {
        case deleted, archived, secret, newKey, noKey
    }

    @Test(arguments: Abandon.allCases)
    func aRequestAbandonedWhileTheAgentWorksSavesNothing(abandon: Abandon) async throws {
        let app = launch()
        let project = try project(app)
        agent.during = {
            switch abandon {
            case .deleted: app.delete(project)
            case .archived: app.archive(project)
            case .secret: app.keepSecret(project, true)
            case .newKey: app.credential = Credential(provider: .openai, key: "sk-proj")
            case .noKey: app.credential = nil
            }
        }
        await app.refreshDueOverviews()
        #expect(app.overviews[project.id]?.built == nil)
        #expect(library.overviews()[project.id]?.built == nil)
        #expect(app.overviewStatus[project.id] == nil)
        if abandon == .deleted { #expect(library.overviews().isEmpty) }
    }

    @Test func aFailureKeepsTheLastOverviewAndASuccessClearsIt() async throws {
        let app = launch()
        let project = try linked(app, try project(app))
        agent.failure = .reported("The Claude API key was rejected.")
        await app.refreshOverview(of: project)?.value
        #expect(app.overviewStatus[project.id] == .failed("The Claude API key was rejected."))
        #expect(app.overviews[project.id]?.built == nil)
        agent.failure = nil
        await app.refreshOverview(of: project)?.value
        #expect(app.overviewStatus[project.id] == nil)
        let built = app.overviews[project.id]?.built
        agent.failure = .timedOut
        passTime(AppState.overviewInterval)
        agent.activity = true
        await app.refreshDueOverviews()
        #expect(app.overviewStatus[project.id] == .failed("The agent took too long and was stopped."))
        #expect(app.overviews[project.id]?.built == built)
        #expect(app.overviews[project.id]?.checkedAt == agent.now)
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 3)
    }

    @Test func theScheduleWaitsUntilTheNextProjectIsDue() async throws {
        let app = launch()
        _ = try project(app)
        await app.scheduleOverviews()
        #expect(agent.jobs.count == 1)
        #expect(agent.waits == [AppState.overviewInterval])
    }

    @Test func withNothingToRefreshTheScheduleChecksAgainInThirtyMinutes() async throws {
        let app = launch()
        app.credential = nil
        _ = try project(app)
        await app.scheduleOverviews()
        #expect(agent.waits == [AppState.overviewInterval])
    }

    @Test func refreshingByHandDuringAScheduledCheckRunsTheAgentEvenWithNothingNew() async throws {
        let app = launch()
        let project = try linked(app, try project(app))
        await app.refreshDueOverviews()
        passTime(AppState.overviewInterval)
        agent.checking = { #expect(app.refreshOverview(of: project) != nil) }
        await app.refreshDueOverviews()
        #expect(agent.jobs.count == 2)
    }

    @Test func aNewlyLinkedRepositoryIsReadFromScratch() async throws {
        let app = launch()
        let project = try project(app)
        await app.refreshDueOverviews()
        _ = try linked(app, project)
        passTime(60)
        await app.refreshOverview(of: project)?.value
        passTime(60)
        await app.refreshOverview(of: project)?.value
        let previous = try agent.jobs.map { try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) as? NSDictionary)["previous"] }
        #expect(previous.map { $0 is NSNull } == [true, true, false])
    }

    @Test func aCheckThatFindsNothingNewOrANewKeyClearsAnEarlierFailure() async throws {
        let app = launch()
        let project = try project(app)
        await app.refreshDueOverviews()
        agent.failure = .broken
        await app.refreshOverview(of: project)?.value
        #expect(app.overviewStatus[project.id] == .failed("The agent stopped unexpectedly."))
        passTime(AppState.overviewInterval)
        await app.refreshDueOverviews()
        #expect(app.overviewStatus[project.id] == nil)
        await app.refreshOverview(of: project)?.value
        #expect(app.overviewStatus[project.id] != nil)
        app.credential = Credential(provider: .openai, key: "sk-proj")
        #expect(app.overviewStatus.isEmpty)
    }

    @Test func aProjectIsRefreshingOnlyWhileTheAgentWorks() async throws {
        let app = launch()
        let project = try project(app)
        var during: [Bool] = []
        agent.during = { during.append(app.isRefreshingOverview(of: project)) }
        await app.refreshOverview(of: project)?.value
        #expect(during == [true])
        #expect(!app.isRefreshingOverview(of: project))
        agent.failure = .broken
        await app.refreshOverview(of: project)?.value
        #expect(!app.isRefreshingOverview(of: project))
    }

    @Test func theProjectPageShowsTheOverviewOnlyForAProjectItCanRefresh() throws {
        let app = launch()
        let project = try project(app)
        func height() -> CGFloat {
            let view = NSHostingView(rootView: ProjectOverview(app: app, project: project, now: agent.now).frame(width: 400))
            view.layoutSubtreeIfNeeded()
            return view.fittingSize.height
        }
        #expect(height() > 0)
        app.credential = nil
        #expect(height() == 0)
        app.credential = Credential(provider: .anthropic, key: "sk-ant")
        app.keepSecret(project, true)
        #expect(height() == 0)
    }

    @Test func aProjectWhoseOnlyNoteIsUnwrittenHasNothingToRefresh() throws {
        let app = launch()
        app.file(try library.create(), inNewProjectNamed: "Blank")
        let blank = try #require(app.projects.first)
        #expect(!app.canRefreshOverview(of: blank))
        app.save("Notes", for: try #require(app.notes(in: blank).first))
        #expect(app.canRefreshOverview(of: blank))
    }
}
