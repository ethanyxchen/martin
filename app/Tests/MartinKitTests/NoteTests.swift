import Foundation
import Testing
@testable import MartinKit

struct NoteTests {
    static let monday = Date(timeIntervalSince1970: 1_792_402_200)
    static let tuesday = monday.addingTimeInterval(86400)

    static func pullRequest(_ number: Int, _ state: PullRequest.State, mergedAt: Date? = nil, updatedAt: Date) -> PullRequest {
        PullRequest(repo: "acme/api", number: number, title: "Change \(number)", url: URL(string: "https://github.com/acme/api/pull/\(number)")!, state: state, mergedAt: mergedAt, updatedAt: updatedAt)
    }

    static let briefing = Briefing(since: monday, until: tuesday, pullRequests: [
        pullRequest(1, .merged, mergedAt: monday.addingTimeInterval(3600), updatedAt: monday.addingTimeInterval(3600)),
        pullRequest(2, .merged, mergedAt: monday.addingTimeInterval(-3600), updatedAt: monday.addingTimeInterval(-3600)),
        pullRequest(3, .merged, mergedAt: tuesday.addingTimeInterval(60), updatedAt: tuesday.addingTimeInterval(60)),
        pullRequest(4, .open, updatedAt: monday.addingTimeInterval(7200)),
        pullRequest(5, .open, updatedAt: monday.addingTimeInterval(-7200)),
        pullRequest(6, .closed, updatedAt: monday.addingTimeInterval(7200)),
    ])

    @Test func briefingKeepsWorkBetweenMeetings() {
        #expect(Self.briefing.merged.map(\.number) == [1])
        #expect(Self.briefing.open.map(\.number) == [4])
    }

    @Test func earliestLooksBackAtLeastTwoWeeks() {
        let fourteenDaysBefore = Calendar.current.date(byAdding: .day, value: -14, to: Self.tuesday)!
        #expect(Briefing.earliest(since: Self.monday, until: Self.tuesday) == fourteenDaysBefore)
        let monthBefore = Calendar.current.date(byAdding: .day, value: -30, to: Self.tuesday)!
        #expect(Briefing.earliest(since: monthBefore, until: Self.tuesday) == monthBefore)
    }

    @Test func markdownListsWorkThenBulletsByKind() {
        let bullets = [
            Bullet(kind: .question, text: "Who owns the retry budget"),
            Bullet(kind: .action, text: "Review #412 before Thursday"),
            Bullet(kind: .decision, text: "Backoff capped at one hour"),
        ]
        let lines = Note.markdown(briefing: Self.briefing, bullets: bullets, silence: "Nothing").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0].hasPrefix("## Merged since "))
        #expect(Array(lines[1...]) == [
            "- Change 1 [#1](https://github.com/acme/api/pull/1)",
            "",
            "## In progress",
            "- Change 4 [#4](https://github.com/acme/api/pull/4)",
            "",
            "## To do",
            "- [ ] Review #412 before Thursday",
            "",
            "## Decisions",
            "- Backoff capped at one hour",
            "",
            "## Questions",
            "- Who owns the retry budget",
            "",
        ])
    }

    @Test func markdownSaysSoWhenNothingHappened() {
        let quiet = Briefing(since: Self.monday, until: Self.tuesday, pullRequests: [])
        let lines = Note.markdown(briefing: quiet, bullets: [], silence: "Nothing was transcribed.").split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("## Since "))
        #expect(Array(lines[1...]) == ["No pull requests merged or in progress.", "Nothing was transcribed."])
        #expect(Note.markdown(briefing: nil, bullets: []) == "\n")
    }
}
