import Foundation
import Testing
@testable import MartinKit

struct NoteTests {
    @Test func markdownListsBulletsByKind() {
        let bullets = [
            Bullet(kind: .question, text: "Who owns the retry budget"),
            Bullet(kind: .action, text: "Review #412 before Thursday"),
            Bullet(kind: .decision, text: "Backoff capped at one hour"),
        ]
        let lines = Note.markdown(bullets: bullets, silence: "Nothing").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines == [
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
        #expect(Note.markdown(bullets: [], silence: "Nothing was transcribed.") == "Nothing was transcribed.\n")
        #expect(Note.markdown(bullets: []) == "\n")
    }
}
